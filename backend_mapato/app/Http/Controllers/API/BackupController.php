<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Services\Inventory\AuditTrail;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use OpenApi\Attributes as OA;

/**
 * Backup and restore of the whole system (every business).
 *
 * Security model:
 *   - super_admin ONLY. A snapshot holds every business's data and every password hash,
 *     and a restore can rewrite any table, so `full_access` staff are not enough.
 *   - A backup covers EVERY table that exists (minus sessions, caches, queues and login
 *     tokens), so a new table can never be forgotten the way a hand-written list was.
 *   - A restore needs an explicit confirmation, first takes a safety snapshot of the
 *     current data (so a mistake can be undone), and only ever adds or overwrites rows:
 *     it never deletes any.
 *   - Everything is audit-logged with who did it and from where.
 */
class BackupController extends Controller
{
    public const FORMAT = '2.0';

    /** What a restore must be asked for, word for word. */
    public const CONFIRMATION = 'RESTORE';

    /**
     * Tables that are never backed up or restored: temporary or secret by nature, or the
     * schema's own bookkeeping. (Restoring login tokens or reset codes would also hand out
     * access that was revoked.)
     */
    private const EXCLUDED = [
        'migrations', 'cache', 'cache_locks', 'sessions', 'jobs', 'job_batches', 'failed_jobs',
        'personal_access_tokens', 'password_reset_tokens', 'password_reset_codes', 'sms_codes',
    ];

    private const CHUNK = 500;

    public function __construct(private readonly AuditTrail $audit) {}

    // ── Gate ────────────────────────────────────────────────────────────

    private function authorise(Request $request): ?JsonResponse
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['success' => false, 'message' => 'Unauthenticated.'], 401);
        }
        if (!$user->isSuperAdmin()) {
            return response()->json([
                'success' => false,
                'message' => 'Only the super admin can perform backup/restore operations.',
            ], 403);
        }

        return null;
    }

    // ── Status ───────────────────────────────────────────────────────────

    #[OA\Get(
        path: '/auth/admin/backup',
        summary: 'List the backups stored on the server',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Backup'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function status(Request $request): JsonResponse
    {
        if ($err = $this->authorise($request)) {
            return $err;
        }

        $files = $this->listBackupFiles();

        return response()->json([
            'success' => true,
            'data' => [
                'backups' => $files,
                'total' => count($files),
                'last_backup_at' => count($files) ? $files[0]['created_at'] : null,
                'storage_driver' => config('filesystems.default'),
            ],
        ]);
    }

    // ── Create ───────────────────────────────────────────────────────────

    #[OA\Post(
        path: '/auth/admin/backup',
        summary: 'Back up every business\'s data to a file on the server',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Backup'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function create(Request $request): JsonResponse
    {
        if ($err = $this->authorise($request)) {
            return $err;
        }

        $user = $request->user();

        try {
            $result = $this->writeSnapshot('backup');

            $this->audit->record(
                $request, 'system', null, 'backup_created', null,
                ['filename' => $result['filename'], 'tables' => $result['tables'], 'rows' => $result['rows']],
                "{$user->name} created a system backup ({$result['rows']} rows in " . count($result['tables']) . ' tables)',
            );

            Log::info('Backup created', ['user_id' => $user->id, 'filename' => $result['filename'], 'ip' => $request->ip()]);

            return response()->json([
                'success' => true,
                'message' => 'Backup created successfully.',
                'data' => [
                    'filename' => basename($result['filename']),
                    'created_at' => now()->toISOString(),
                    'size_bytes' => Storage::disk('local')->size($result['filename']),
                    'tables' => count($result['tables']),
                    'rows' => $result['rows'],
                    'skipped_tables' => $result['skipped'],
                ],
            ]);
        } catch (\Throwable $e) {
            Log::error('Backup failed', ['error' => $e->getMessage(), 'user_id' => $user->id]);

            return response()->json(['success' => false, 'message' => 'Backup failed: ' . $e->getMessage()], 500);
        }
    }

    // ── Restore ──────────────────────────────────────────────────────────

    #[OA\Post(
        path: '/auth/admin/restore',
        summary: 'Restore from a backup stored on the server (filename) or an uploaded one (backup_file)',
        description: 'Needs confirm="RESTORE". Takes a safety snapshot first. Adds and overwrites rows; never deletes.',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Backup'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['confirm'],
                properties: [
                    new OA\Property(property: 'confirm', type: 'string', example: 'RESTORE'),
                    new OA\Property(property: 'filename', type: 'string', example: 'backup_2026-10-12_101500_ab12cd.json'),
                    new OA\Property(property: 'backup_file', type: 'string', format: 'binary'),
                ],
            ),
        ),
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function restore(Request $request): JsonResponse
    {
        if ($err = $this->authorise($request)) {
            return $err;
        }

        $user = $request->user();

        $request->validate([
            'confirm' => ['required', 'in:' . self::CONFIRMATION],
            'filename' => ['nullable', 'string', 'regex:/^[A-Za-z0-9_.\-]+\.json$/'],
            'backup_file' => ['nullable', 'file', 'mimes:json,txt', 'max:51200'], // 50 MB
        ]);

        if (!$request->hasFile('backup_file') && !$request->filled('filename')) {
            return response()->json([
                'success' => false,
                'message' => 'Choose a backup: send its filename, or upload the file.',
            ], 422);
        }

        try {
            if ($request->hasFile('backup_file')) {
                $raw = (string) file_get_contents($request->file('backup_file')->getRealPath());
            } else {
                $path = 'backups/' . basename((string) $request->input('filename'));
                if (!Storage::disk('local')->exists($path)) {
                    return response()->json(['success' => false, 'message' => 'That backup was not found on the server.'], 404);
                }
                $raw = (string) Storage::disk('local')->get($path);
            }

            $data = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
            unset($raw);

            if (!is_array($data) || !isset($data['version'], $data['created_at'], $data['tables']) || !is_array($data['tables']) || $data['tables'] === []) {
                return response()->json(['success' => false, 'message' => 'Invalid backup file: missing required fields or no table data.'], 422);
            }

            // Before changing anything, keep what is there now, so a wrong restore can itself be undone.
            $safety = $this->writeSnapshot('pre_restore');

            $summary = $this->applySnapshot($data['tables']);

            $this->audit->record(
                $request, 'system', null, 'backup_restored', null,
                ['backup_date' => $data['created_at'], 'tables' => array_keys($summary['restored']), 'safety_snapshot' => $safety['filename']],
                "{$user->name} restored a system backup from {$data['created_at']}",
            );

            Log::warning('System restore performed', [
                'user_id' => $user->id,
                'backup_date' => $data['created_at'],
                'safety_snapshot' => $safety['filename'],
                'ip' => $request->ip(),
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Restore completed successfully.',
                'data' => [
                    'restored_tables' => count($summary['restored']),
                    'restored_rows' => array_sum($summary['restored']),
                    'skipped_tables' => $summary['skipped'],
                    'backup_date' => $data['created_at'],
                    'safety_snapshot' => basename($safety['filename']),
                ],
            ]);
        } catch (\JsonException $e) {
            return response()->json(['success' => false, 'message' => 'Invalid JSON backup file.'], 422);
        } catch (\Throwable $e) {
            Log::error('Restore failed', ['error' => $e->getMessage(), 'user_id' => $user->id]);

            return response()->json(['success' => false, 'message' => 'Restore failed: ' . $e->getMessage()], 500);
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    /**
     * The tables a backup covers: every one that exists, except the excluded kinds and any
     * without an `id` column (a restore matches rows on `id`).
     *
     * @return array{include: array<int, string>, skipped: array<string, string>}
     */
    private function plan(): array
    {
        $include = [];
        $skipped = [];

        foreach (array_column(Schema::getTables(), 'name') as $table) {
            if (in_array($table, self::EXCLUDED, true) || str_starts_with($table, 'sqlite_')
                || str_starts_with($table, 'telescope_') || str_starts_with($table, 'pulse_')) {
                continue;
            }
            if (!Schema::hasColumn($table, 'id')) {
                $skipped[$table] = 'no id column';
                continue;
            }
            $include[] = $table;
        }

        sort($include);

        return ['include' => $include, 'skipped' => $skipped];
    }

    /**
     * Write every table to a JSON file on the server, row by row so a big database never has
     * to fit in memory. Reads as the platform (nothing scoped to one business).
     *
     * @return array{filename: string, tables: array<int, string>, rows: int, skipped: array<string, string>}
     */
    private function writeSnapshot(string $prefix): array
    {
        $disk = Storage::disk('local');
        $disk->makeDirectory('backups');
        $filename = 'backups/' . $prefix . '_' . now()->format('Y-m-d_His') . '_' . Str::random(6) . '.json';
        $absolute = $disk->path($filename);

        $plan = $this->plan();
        $rows = 0;
        $flags = JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE | JSON_PRESERVE_ZERO_FRACTION;

        $handle = fopen($absolute, 'wb');
        if ($handle === false) {
            throw new \RuntimeException('Could not write the backup file.');
        }

        try {
            fwrite($handle, '{"version":' . json_encode(self::FORMAT) . ',"created_at":' . json_encode(now()->toISOString())
                . ',"app":' . json_encode((string) config('app.name')) . ',"tables":{');

            TenantContext::withoutScope(function () use ($handle, $plan, &$rows, $flags) {
                foreach ($plan['include'] as $i => $table) {
                    fwrite($handle, ($i > 0 ? ',' : '') . json_encode($table) . ':[');
                    $first = true;

                    DB::table($table)->orderBy('id')->chunkById(self::CHUNK, function ($chunk) use ($handle, &$first, &$rows, $flags) {
                        foreach ($chunk as $row) {
                            fwrite($handle, ($first ? '' : ',') . json_encode((array) $row, $flags));
                            $first = false;
                            $rows++;
                        }
                    });

                    fwrite($handle, ']');
                }
            });

            fwrite($handle, '}}');
        } finally {
            fclose($handle);
        }

        return ['filename' => $filename, 'tables' => $plan['include'], 'rows' => $rows, 'skipped' => $plan['skipped']];
    }

    /**
     * Write a snapshot's rows back, matching on `id`: rows that exist are overwritten, rows
     * that are missing are added, nothing is deleted. All or nothing. Columns the table no
     * longer has are ignored, so a backup from an older version still restores.
     *
     * @param  array<string, mixed>  $tables
     * @return array{restored: array<string, int>, skipped: array<string, string>}
     */
    private function applySnapshot(array $tables): array
    {
        $allowed = array_flip($this->plan()['include']);
        $restored = [];
        $skipped = [];

        // Foreign keys are switched off for the duration (rows arrive table by table, not in
        // dependency order) and always switched back on. Done outside the transaction: some
        // databases ignore the switch inside one.
        Schema::disableForeignKeyConstraints();

        try {
            TenantContext::withoutScope(function () use ($tables, $allowed, &$restored, &$skipped) {
                DB::transaction(function () use ($tables, $allowed, &$restored, &$skipped) {
                    foreach ($tables as $table => $rows) {
                        if (!isset($allowed[$table])) {
                            $skipped[$table] = 'not a restorable table here';
                            continue;
                        }
                        if (!is_array($rows) || $rows === []) {
                            continue;
                        }

                        $columns = array_flip(Schema::getColumnListing($table));
                        $count = 0;

                        foreach (array_chunk($rows, self::CHUNK) as $chunk) {
                            $chunk = array_map(fn ($row) => array_intersect_key((array) $row, $columns), $chunk);
                            $keys = array_keys($chunk[0] ?? []);
                            if (!in_array('id', $keys, true)) {
                                $skipped[$table] = 'rows have no id';
                                continue 2;
                            }
                            // Every row must carry the same columns for one multi-row statement.
                            $chunk = array_map(
                                fn ($row) => array_replace(array_fill_keys($keys, null), array_intersect_key($row, array_flip($keys))),
                                $chunk
                            );

                            $update = array_values(array_diff($keys, ['id']));
                            if ($update === []) {
                                DB::table($table)->insertOrIgnore($chunk);
                            } else {
                                DB::table($table)->upsert($chunk, ['id'], $update);
                            }
                            $count += count($chunk);
                        }

                        $restored[$table] = $count;
                    }
                });
            });
        } finally {
            Schema::enableForeignKeyConstraints();
        }

        return ['restored' => $restored, 'skipped' => $skipped];
    }

    private function listBackupFiles(): array
    {
        try {
            $files = Storage::disk('local')->files('backups');
            $result = [];
            foreach ($files as $file) {
                $result[] = [
                    'filename' => basename($file),
                    'size_bytes' => Storage::disk('local')->size($file),
                    'created_at' => date('Y-m-d\TH:i:s\Z', Storage::disk('local')->lastModified($file)),
                    'kind' => str_starts_with(basename($file), 'pre_restore_') ? 'pre_restore' : 'backup',
                ];
            }
            usort($result, fn ($a, $b) => strcmp($b['created_at'], $a['created_at']));

            return $result;
        } catch (\Throwable) {
            return [];
        }
    }
}
