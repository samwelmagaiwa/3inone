<?php

namespace App\Services\Inventory;

use App\Models\User;
use App\Support\Tenancy\TenantContext;
use App\Support\Tenancy\TenantTables;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Gives the inventory data that existed before per-business isolation to the
 * business that has really been running the depot.
 *
 * Used by the data migration and by `php artisan inventory:assign-owner`. It only
 * ever fills in rows that have NO owner, so running it again changes nothing.
 */
class InventoryOwnership
{
    /** Roles that work inside a depot rather than own one. */
    private const STAFF_ROLES = ['manager', 'operator', 'sales_officer', 'viewer'];

    /** Tables every business is seeded with when it is given the inventory service. */
    private const SEEDED = ['inventory_settings', 'inventory_crate_types'];

    private const BATCH = 5000;

    /**
     * The business that owns today's shared depot, or null when it cannot be told.
     *
     * Normally exactly one active owner (admin / landlord) has been given the
     * inventory service. If several have, the one whose accounts created the most
     * sales and products is the one running the depot.
     */
    public function findDepotOwner(): ?User
    {
        $candidates = $this->candidates();

        if ($candidates->count() <= 1) {
            return $candidates->first();
        }

        return TenantContext::withoutScope(
            fn () => $candidates
                ->sortByDesc(fn (User $u) => $this->activity($u)) // stable: ties keep the oldest first
                ->first()
        );
    }

    /**
     * Every active business owner who holds the inventory service today. More than one
     * means the shared depot has been split between owners by accident: only one of
     * them can keep it, so a human should confirm which.
     *
     * @return \Illuminate\Support\Collection<int, User>
     */
    public function candidates()
    {
        return TenantContext::withoutScope(fn () => User::query()
            ->whereIn('role', User::ACCOUNT_HEAD_ROLES)
            ->where('is_active', true)
            ->whereHas('services', fn ($q) => $q->where('service_type', 'inventory'))
            ->orderBy('created_at')
            ->get());
    }

    /**
     * Inventory staff who belong to no business -- created by a super admin, or by
     * nobody -- and so would find an empty depot once everything is scoped.
     *
     * @return \Illuminate\Support\Collection<int, User>
     */
    public function orphanStaff(User $owner)
    {
        return TenantContext::withoutScope(fn () => User::query()
            ->whereIn('role', self::STAFF_ROLES)
            ->where('id', '!=', $owner->id)
            ->whereHas('services', fn ($q) => $q->where('service_type', 'inventory'))
            ->get()
            ->filter(fn (User $u) => $u->accountHeadId() === (string) $u->id)
            ->values());
    }

    /** Rows with no owner yet, per table. @return array<string, int> */
    public function unownedRows(): array
    {
        return TenantContext::withoutScope(function () {
            $counts = [];
            foreach (TenantTables::INVENTORY as $table) {
                $counts[$table] = Schema::hasColumn($table, TenantTables::OWNER_COLUMN)
                    ? DB::table($table)->whereNull(TenantTables::OWNER_COLUMN)->count()
                    : 0;
            }

            return $counts;
        });
    }

    /**
     * Make $owner the owner of every unowned inventory row and bring orphaned
     * inventory staff into their business.
     *
     * @return array{rows: array<string, int>, adopted: array<int, string>}
     */
    public function assign(User $owner): array
    {
        $ownerId = TenantContext::validated((string) $owner->id);

        return TenantContext::withoutScope(function () use ($owner, $ownerId) {
            $adopted = [];
            foreach ($this->orphanStaff($owner) as $staff) {
                $this->logReparent($staff, $owner);
                $staff->created_by = $owner->id;
                $staff->save();
                $adopted[] = (string) $staff->email;
            }

            $rows = [];
            foreach (TenantTables::INVENTORY as $table) {
                $rows[$table] = 0;
                do {
                    $changed = DB::table($table)
                        ->whereNull(TenantTables::OWNER_COLUMN)
                        ->limit(self::BATCH)
                        ->update([TenantTables::OWNER_COLUMN => $ownerId]);
                    $rows[$table] += $changed;
                } while ($changed > 0);
            }

            return ['rows' => $rows, 'adopted' => $adopted];
        });
    }

    /** Rows each table holds for one business. @return array<string, int> */
    public function ownedBy(User $owner): array
    {
        return TenantContext::withoutScope(function () use ($owner) {
            $counts = [];
            foreach (TenantTables::INVENTORY as $table) {
                $counts[$table] = DB::table($table)->where(TenantTables::OWNER_COLUMN, $owner->id)->count();
            }

            return $counts;
        });
    }

    /**
     * What a business holds beyond the reference data it was seeded with; empty means
     * it has no depot of its own. @return array<string, int>
     */
    public function ownDepot(User $owner): array
    {
        return array_filter(array_diff_key($this->ownedBy($owner), array_flip(self::SEEDED)));
    }

    /**
     * Move a whole depot from one business to another: the correction for when the
     * wrong owner was given the existing depot. Every inventory row owned by $from
     * becomes $to's. Staff are not moved (they belong to whoever created them).
     *
     * Only into a business that has no depot of its own: merging two real depots
     * would collide on SKUs, invoice numbers and names. The reference data every
     * business is seeded with (settings, crate types) does not count -- it is replaced
     * by the depot's own. All or nothing: one transaction.
     *
     * @return array<string, int> rows moved per table
     * @throws \DomainException when the target business already holds inventory data
     */
    public function reassign(User $from, User $to): array
    {
        $fromId = TenantContext::validated((string) $from->id);
        $toId = TenantContext::validated((string) $to->id);

        $holds = $this->ownDepot($to);
        if ($holds !== []) {
            throw new \DomainException(
                "{$to->email} already has its own inventory data (" . implode(', ', array_keys($holds))
                . '). A depot can only be moved into a business that has none.'
            );
        }

        return TenantContext::withoutScope(function () use ($fromId, $toId) {
            $moved = [];

            DB::transaction(function () use ($fromId, $toId, &$moved) {
                // The incoming depot brings its own settings and crate types.
                foreach (self::SEEDED as $table) {
                    DB::table($table)->where(TenantTables::OWNER_COLUMN, $toId)->delete();
                }

                foreach (TenantTables::INVENTORY as $table) {
                    $moved[$table] = 0;
                    do {
                        $changed = DB::table($table)
                            ->where(TenantTables::OWNER_COLUMN, $fromId)
                            ->limit(self::BATCH)
                            ->update([TenantTables::OWNER_COLUMN => $toId]);
                        $moved[$table] += $changed;
                    } while ($changed > 0);
                }
            });

            return $moved;
        });
    }

    /** How much of the depot's history a business's own accounts created. */
    private function activity(User $user): int
    {
        $members = $user->accountMemberIds();

        return DB::table('inventory_sales')->whereIn('created_by', $members)->count()
            + DB::table('inventory_products')->whereIn('created_by', $members)->count();
    }

    private function logReparent(User $staff, User $owner): void
    {
        if (!Schema::hasTable('tenancy_reparent_log')) {
            return;
        }

        DB::table('tenancy_reparent_log')->insert([
            'user_id' => $staff->id,
            'old_created_by' => $staff->created_by,
            'new_created_by' => $owner->id,
            'reason' => 'inventory staff with no business: moved under the depot owner',
            'created_at' => now(),
        ]);
    }
}
