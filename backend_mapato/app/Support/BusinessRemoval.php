<?php

namespace App\Support;

use App\Models\Business;
use App\Models\Concerns\ScopedThroughDriver;
use App\Models\Concerns\ScopedToAccount;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use App\Support\Tenancy\TenantTables;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Removing ONE business for good: its record, its owner, every account made under it (staff, and its drivers and tenants), and its
 * data in every service. Nothing of any other business is touched.
 *
 *   plan()    what would go, table by table (the warning the super admin reads first); nothing changes
 *   remove()  deletes it all in one transaction: all or nothing
 *
 * What belongs to the business is found the same way the app decides what a business may see:
 *   - the people: the owner, everyone in User::accountMemberIds(), and the drivers / tenants they created (vendors are a shared
 *     marketplace and stay; another business's head made under it stays too);
 *   - Transport / Rental rows: every model with the account scope, read AS the owner, so exactly the rows that business sees;
 *   - Inventory / Salon rows: owner_id = the owner in every inventory table, Trash included;
 *   - business-level rows (SMS log, payments, counters): business_id = the business; and rows keyed to the removed people (user_id).
 * The caller takes a full safety snapshot first (see BusinessRemovalController), so a mistake can be restored.
 */
final class BusinessRemoval
{
    /** How many delete rounds: rows that others still point at go in a later round, after those others. */
    private const ROUNDS = 6;

    /** Never touched here, whatever their columns say. */
    private const NEVER = [
        'migrations', 'cache', 'cache_locks', 'sessions', 'jobs', 'job_batches', 'failed_jobs', 'personal_access_tokens',
        'users', 'businesses', 'states', 'lgas', 'wards', 'villages', 'places', 'plan_prices', 'tenancy_reparent_log',
    ];

    /**
     * What removing the business would delete: [table => rows], plus the people by name.
     *
     * @return array{business: array<string, mixed>, users: array<int, array<string, string>>, tables: array<string, int>, total_rows: int}
     */
    public static function plan(Business $business): array
    {
        $targets = self::targets($business);
        $tables = [];
        foreach ($targets['deletes'] as [$table, $column, $values]) {
            if ($values === []) {
                continue;
            }
            $count = self::unscoped(fn () => DB::table($table)->whereIn($column, $values)->count());
            if ($count > 0) {
                $tables[$table] = ($tables[$table] ?? 0) + $count;
            }
        }
        ksort($tables);

        $users = User::query()->withoutGlobalScopes()->whereIn('id', $targets['users'])->orderBy('name')->get(['id', 'name', 'email', 'role'])
            ->map(fn (User $u) => ['name' => (string) $u->name, 'email' => (string) $u->email, 'role' => (string) $u->role])->values()->all();

        return [
            'business' => ['id' => $business->id, 'name' => $business->name, 'owner' => $business->owner?->name],
            'users' => $users,
            'tables' => $tables,
            'total_rows' => array_sum($tables) + count($users) + 1,
        ];
    }

    /**
     * Delete the business and everything that belongs to it. All or nothing.
     *
     * @return array{tables: array<string, int>, users: int}
     */
    public static function remove(Business $business): array
    {
        $targets = self::targets($business);
        $deleted = [];

        DB::transaction(function () use ($business, $targets, &$deleted) {
            self::unscoped(function () use ($business, $targets, &$deleted) {
                $pending = $targets['deletes'];
                for ($round = 0; $round < self::ROUNDS && $pending !== []; $round++) {
                    $left = [];
                    foreach ($pending as $op) {
                        [$table, $column, $values] = $op;
                        if ($values === []) {
                            continue;
                        }
                        try {
                            $n = 0;
                            foreach (array_chunk($values, 500) as $chunk) {
                                $n += DB::table($table)->whereIn($column, $chunk)->delete();
                            }
                            if ($n > 0) {
                                $deleted[$table] = ($deleted[$table] ?? 0) + $n;
                            }
                        } catch (QueryException $e) {
                            if (!self::isForeignKeyError($e)) {
                                throw $e;
                            }
                            $left[] = $op; // something still points at these rows: try again after the others
                        }
                    }
                    $pending = $left;
                }
                if ($pending !== []) {
                    throw new \RuntimeException('The business could not be removed completely (rows still referenced in: '
                        . implode(', ', array_unique(array_map(fn ($op) => $op[0], $pending))) . '). Nothing was removed.');
                }

                // The people last (their sign-ins first), then the business itself.
                DB::table('personal_access_tokens')->where('tokenable_type', User::class)->whereIn('tokenable_id', $targets['users'])->delete();
                foreach (array_chunk($targets['users'], 500) as $chunk) {
                    // Staff first, the owner last: a staff account points at the owner through created_by.
                    DB::table('users')->whereIn('id', array_diff($chunk, [(string) $business->owner_id]))->delete();
                }
                DB::table('users')->where('id', (string) $business->owner_id)->delete();
                DB::table('businesses')->where('id', $business->id)->delete();
            });
        });

        ksort($deleted);

        return ['tables' => $deleted, 'users' => count($targets['users'])];
    }

    // ------------------------------------------------------------------ what belongs to it

    /**
     * @return array{users: array<int, string>, deletes: array<int, array{0: string, 1: string, 2: array<int, int|string>}>}
     */
    private static function targets(Business $business): array
    {
        $owner = $business->owner_id ? User::query()->withoutGlobalScopes()->find($business->owner_id) : null;
        $users = $owner ? self::people($owner) : [];
        $deletes = [];

        if ($owner !== null) {
            // Transport / Rental: exactly what the business itself sees, read as its owner (deleted-but-kept rows too).
            TenantContext::runAs($owner, function () use (&$deletes) {
                foreach (self::scopedModels() as $class) {
                    /** @var Model $model */
                    $model = new $class();
                    if (!Schema::hasTable($model->getTable())) {
                        continue; // an old model whose table this database does not have
                    }
                    $query = $class::query();
                    if (method_exists($model, 'bootSoftDeletes')) {
                        $query->withTrashed();
                    }
                    $ids = $query->pluck($model->getQualifiedKeyName())->map(fn ($v) => is_numeric($v) ? (int) $v : (string) $v)->all();
                    if ($ids !== [] && $model->getTable() !== 'businesses') {
                        $deletes[] = [$model->getTable(), $model->getKeyName(), $ids];
                    }
                }
            });

            // Inventory / Salon / Groups: every row stamped with the owner, Trash included.
            foreach (TenantTables::all() as $table) {
                if (Schema::hasTable($table) && Schema::hasColumn($table, TenantTables::OWNER_COLUMN)) {
                    $deletes[] = [$table, TenantTables::OWNER_COLUMN, [(string) $owner->id]];
                }
            }
        }

        // Rows of the business itself, and rows keyed to the people who go with it.
        foreach (array_column(Schema::getTables(), 'name') as $table) {
            if (in_array($table, self::NEVER, true) || in_array($table, TenantTables::all(), true) || str_starts_with($table, 'sqlite_')) {
                continue;
            }
            if (Schema::hasColumn($table, 'business_id')) {
                $deletes[] = [$table, 'business_id', [(string) $business->id]];
            }
            if ($users !== [] && Schema::hasColumn($table, 'user_id')) {
                $deletes[] = [$table, 'user_id', $users];
            }
        }

        return ['users' => $users, 'deletes' => $deletes];
    }

    /**
     * The owner, the staff of the business, and the drivers / tenants / group members they made. Never a super admin, a vendor, or another business's head.
     *
     * @return array<int, string>
     */
    private static function people(User $owner): array
    {
        $members = array_map('strval', $owner->accountMemberIds());
        $portal = User::query()->withoutGlobalScopes()
            ->whereIn('created_by', $members)
            ->whereIn('role', ['driver', 'tenant', User::GROUP_MEMBER_ROLE])
            ->pluck('id')->map(fn ($id) => (string) $id)->all();

        $ids = array_values(array_unique(array_merge($members, $portal)));

        // Belt and braces: nobody who heads another business or runs the platform.
        return User::query()->withoutGlobalScopes()->whereIn('id', $ids)
            ->where(fn ($q) => $q->where('id', (string) $owner->id)->orWhereNotIn('role', array_merge(User::ACCOUNT_HEAD_ROLES, ['super_admin', 'vendor'])))
            ->pluck('id')->map(fn ($id) => (string) $id)->all();
    }

    /** @return array<int, class-string<Model>> every model that carries the account scope */
    private static function scopedModels(): array
    {
        $found = [];
        $root = app_path('Models');
        foreach (new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($root, \FilesystemIterator::SKIP_DOTS)) as $file) {
            if ($file->getExtension() !== 'php') {
                continue;
            }
            $relative = str_replace(['/', '.php'], ['\\', ''], substr(str_replace('\\', '/', $file->getPathname()), strlen(str_replace('\\', '/', $root)) + 1));
            $class = 'App\\Models\\' . $relative;
            if (!class_exists($class) || !is_subclass_of($class, Model::class) || (new \ReflectionClass($class))->isAbstract()) {
                continue;
            }
            $traits = class_uses_recursive($class);
            if (isset($traits[ScopedToAccount::class]) || isset($traits[ScopedThroughDriver::class])) {
                $found[] = $class;
            }
        }
        sort($found);

        return $found;
    }

    private static function unscoped(\Closure $callback): mixed
    {
        return TenantContext::withoutScope(fn () => TenantContext::withTrashed($callback));
    }

    private static function isForeignKeyError(QueryException $e): bool
    {
        $message = $e->getMessage();

        return str_contains($message, 'FOREIGN KEY') || str_contains($message, 'foreign key') || str_contains($message, '1451') || (string) $e->getCode() === '23000';
    }
}
