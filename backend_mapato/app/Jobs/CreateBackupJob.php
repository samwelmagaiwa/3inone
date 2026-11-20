<?php

namespace App\Jobs;

use App\Http\Controllers\API\BackupController;
use App\Models\User;
use App\Services\Inventory\AuditTrail;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * A backup the super admin asked for, written by the queue worker (a copy of the whole database takes long once it is big; done inside
 * the request it would time out). The file name was chosen when it was asked for, so the app already knows which one it will be.
 */
class CreateBackupJob implements ShouldQueue
{
    use Queueable;

    public int $tries = 1;

    public int $timeout = 1800;

    public function __construct(public string $filename, public string $userId, public string $ip)
    {
    }

    public function handle(AuditTrail $audit): void
    {
        $user = User::query()->withoutGlobalScopes()->find($this->userId);
        try {
            $result = app(BackupController::class)->safetySnapshot('backup', $this->filename);
        } catch (\Throwable $e) {
            Log::error('Backup failed', ['error' => $e->getMessage(), 'user_id' => $this->userId, 'filename' => $this->filename]);

            return;
        }

        $audit->record(
            self::requestFor($user, $this->ip), 'system', null, 'backup_created', null,
            ['filename' => $result['filename'], 'tables' => $result['tables'], 'rows' => $result['rows']],
            ($user?->name ?? 'Super admin') . " created a system backup ({$result['rows']} rows in " . count($result['tables']) . ' tables)',
        );
        Log::info('Backup created', ['user_id' => $this->userId, 'filename' => $result['filename'], 'ip' => $this->ip]);
    }

    /** A stand-in request, so the audit trail still names who asked and from where. */
    public static function requestFor(?User $user, string $ip): Request
    {
        $request = Request::create('/', 'POST', server: ['REMOTE_ADDR' => $ip]);
        $request->setUserResolver(fn () => $user);

        return $request;
    }
}
