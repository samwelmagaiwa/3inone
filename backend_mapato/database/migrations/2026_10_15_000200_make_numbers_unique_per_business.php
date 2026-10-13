<?php

use App\Models\User;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Numbers that identify a thing INSIDE one business must be unique inside that business, not
     * across every business on the platform:
     *
     *   devices.plate_number          two businesses each have their own "T123ABC" (a motorbike sold
     *                                 from one to the other); one business must not be blocked by, or
     *                                 learn about, another's vehicles
     *   drivers.license_number        a driver who changed employer keeps their licence number
     *   payment_receipts.receipt_number, receipts.receipt_number
     *                                 each business numbers its own receipts from 0001 (the numbering
     *                                 already counts only the business's own), so with ONE global index
     *                                 the second business's first receipt of the day collided with the
     *                                 first business's and failed with a 500
     *
     * These tables have no business column; their business was only ever worked out from the creator
     * chain (users.created_by). This adds `owner_id` (the account head's user id, the same value the
     * inventory tables carry), fills it in for every existing row from that same chain, and replaces
     * each global unique index with a per-business one.
     *
     * Nothing is deleted or rewritten except the new column. The global indexes were stricter than the
     * new ones, so every existing row satisfies them; a row whose owner cannot be worked out keeps a
     * NULL owner_id, which a unique index treats as distinct (it stays readable and editable exactly
     * as before, it is just not de-duplicated against other unowned rows).
     */
    private const TABLES = [
        'devices' => 'plate_number',
        'drivers' => 'license_number',
        'payment_receipts' => 'receipt_number',
        'receipts' => 'receipt_number',
    ];

    public function up(): void
    {
        foreach (array_keys(self::TABLES) as $table) {
            // (MySQL cannot roll back a half-applied schema change, so a failed run is re-runnable.)
            if (!Schema::hasColumn($table, 'owner_id')) {
                Schema::table($table, function (Blueprint $t) {
                    $t->uuid('owner_id')->nullable();
                });
            }
        }

        $this->backfill();

        foreach (self::TABLES as $table => $column) {
            // After a rollback that had to keep duplicates, the global unique index is not there to drop.
            $global = $this->uniqueIndexOn($table, $column);

            Schema::table($table, function (Blueprint $t) use ($column, $global) {
                $t->unique(['owner_id', $column]);
                if ($global !== null) {
                    $t->dropUnique($global);
                }
            });
        }
    }

    public function down(): void
    {
        // The global indexes can only come back if no two businesses now share a value; otherwise a
        // plain index keeps lookups fast and no row is touched.
        foreach (self::TABLES as $table => $column) {
            Schema::table($table, function (Blueprint $t) use ($column) {
                $t->dropUnique(['owner_id', $column]);
            });
            Schema::table($table, function (Blueprint $t) use ($table, $column) {
                if (!$this->hasDuplicates($table, $column)) {
                    $t->unique($column);
                } elseif (!$this->hasIndexOn($table, $column)) {
                    // (the tables already carry a plain index on these columns; add one only if not)
                    $t->index($column);
                }
            });
            Schema::table($table, function (Blueprint $t) {
                $t->dropColumn('owner_id');
            });
        }
    }

    private function hasDuplicates(string $table, string $column): bool
    {
        return DB::table($table)->select($column)->groupBy($column)->havingRaw('count(*) > 1')->exists();
    }

    /** The name of the UNIQUE index on exactly this one column, or null. */
    private function uniqueIndexOn(string $table, string $column): ?string
    {
        foreach (Schema::getIndexes($table) as $index) {
            if ($index['unique'] && $index['columns'] === [$column]) {
                return $index['name'];
            }
        }

        return null;
    }

    /** Is there already an index (of any kind) on exactly this one column? */
    private function hasIndexOn(string $table, string $column): bool
    {
        foreach (Schema::getIndexes($table) as $index) {
            if ($index['columns'] === [$column]) {
                return true;
            }
        }

        return false;
    }

    private function backfill(): void
    {
        // Same walk as User::accountHeadId(): the nearest admin / landlord at or above the user in
        // the created_by chain; a user with none is their own account.
        $users = DB::table('users')->get(['id', 'role', 'created_by'])->keyBy('id');
        $headRoles = User::ACCOUNT_HEAD_ROLES;
        $memo = [];

        $head = function (?string $userId) use ($users, $headRoles, &$memo): ?string {
            if ($userId === null || !isset($users[$userId])) {
                return null;
            }
            if (isset($memo[$userId])) {
                return $memo[$userId];
            }

            $current = $users[$userId];
            for ($hops = 0; $current !== null && $hops < 8; $hops++) {
                if (in_array(strtolower((string) $current->role), $headRoles, true)) {
                    return $memo[$userId] = (string) $current->id;
                }
                if (!$current->created_by) {
                    break;
                }
                $current = $users[$current->created_by] ?? null;
            }

            return $memo[$userId] = $userId;
        };

        // Drivers first: everything else is placed through them.
        $driverUser = [];
        $driverOwner = [];
        DB::table('drivers')->orderBy('id')->select(['id', 'user_id'])->chunk(500, function ($rows) use ($head, &$driverUser, &$driverOwner) {
            $byOwner = [];
            foreach ($rows as $row) {
                $driverUser[$row->id] = $row->user_id;
                $owner = $head($row->user_id);
                if ($owner !== null) {
                    $driverOwner[$row->id] = $owner;
                    $byOwner[$owner][] = $row->id;
                }
            }
            $this->assign('drivers', $byOwner);
        });

        // A vehicle belongs to its creator's business, else to its driver's.
        DB::table('devices')->orderBy('id')->select(['id', 'created_by', 'driver_id'])->chunk(500, function ($rows) use ($head, $driverOwner) {
            $byOwner = [];
            foreach ($rows as $row) {
                $owner = $head($row->created_by) ?? ($driverOwner[$row->driver_id] ?? null);
                if ($owner !== null) {
                    $byOwner[$owner][] = $row->id;
                }
            }
            $this->assign('devices', $byOwner);
        });

        // A payment receipt belongs to its driver's business.
        DB::table('payment_receipts')->orderBy('id')->select(['id', 'driver_id'])->chunk(500, function ($rows) use ($driverOwner) {
            $byOwner = [];
            foreach ($rows as $row) {
                if (isset($driverOwner[$row->driver_id])) {
                    $byOwner[$driverOwner[$row->driver_id]][] = $row->id;
                }
            }
            $this->assign('payment_receipts', $byOwner);
        });

        // A (trip) receipt belongs to the business of the driver of its transaction.
        DB::table('receipts')->orderBy('id')->select(['id', 'transaction_id'])->chunk(500, function ($rows) use ($driverOwner) {
            $drivers = DB::table('transactions')->whereIn('id', $rows->pluck('transaction_id')->filter()->all())->pluck('driver_id', 'id');
            $byOwner = [];
            foreach ($rows as $row) {
                $driver = $drivers[$row->transaction_id] ?? null;
                if ($driver !== null && isset($driverOwner[$driver])) {
                    $byOwner[$driverOwner[$driver]][] = $row->id;
                }
            }
            $this->assign('receipts', $byOwner);
        });
    }

    /** @param  array<string, array<int, string|int>>  $byOwner  owner id => row ids */
    private function assign(string $table, array $byOwner): void
    {
        foreach ($byOwner as $owner => $ids) {
            DB::table($table)->whereIn('id', $ids)->update(['owner_id' => $owner]);
        }
    }
};
