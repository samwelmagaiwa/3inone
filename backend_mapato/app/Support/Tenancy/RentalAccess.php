<?php

namespace App\Support\Tenancy;

use App\Models\User;
use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\DB;

/**
 * Who may see which Rental record -- defined once, for every Rental model.
 *
 * The Rental models carry the same fail-closed account scope Transport does (see
 * App\Models\Scopes\AccountScope), and each model's rule is a one-liner over the id
 * sets below. By role:
 *
 *   owner / staff   the properties the account owns, and everything under them;
 *   caretaker       only the properties they are assigned to, and what is under those;
 *   tenant          only their own leases, and the bills, payments, receipts and
 *                   maintenance requests of those leases;
 *   vendor          only the maintenance work assigned to them;
 *   anyone else     nothing.
 *
 * The id sets are plain query-builder sub-selects on the tables themselves (never
 * Eloquent), so the models can reference each other without scopes recursing.
 */
final class RentalAccess
{
    private const NOTHING = '1 = 0';

    public static function role(User $user): string
    {
        return strtolower((string) $user->role);
    }

    /** True for the people who run properties (owners, their staff, caretakers); false for tenants, vendors and strangers. */
    public static function managesProperties(User $user): bool
    {
        return !in_array(self::role($user), ['tenant', 'vendor', 'driver'], true);
    }

    /** Ids of rental_properties the user may see. */
    private static function rawPropertyIds(User $user): Builder
    {
        $query = DB::table('rental_properties')->select('rental_properties.id');

        // Looking at one branch: only its properties (houses, bills, tenants, payments and repairs all hang off these).
        if (self::managesProperties($user) && ($branch = ServiceBranch::selected('rental', $user)) !== null) {
            $query->where('rental_properties.branch_id', $branch);
        }

        return match (self::role($user)) {
            'tenant' => $query->whereIn('rental_properties.id', self::leasedHouses($user)->select('h.property_id')),
            'vendor' => $query->whereIn('rental_properties.id', self::assignedRequests($user)->select('m.property_id')),
            'caretaker' => $query->where('rental_properties.caretaker_id', $user->id),
            'driver' => $query->whereRaw(self::NOTHING),
            default => $query->whereIn('rental_properties.owner_id', $user->accountMemberIds()),
        };
    }

    /** Ids of rental_houses the user may see. */
    private static function rawHouseIds(User $user): Builder
    {
        $query = DB::table('rental_houses')->select('rental_houses.id');

        return match (self::role($user)) {
            'tenant' => $query->whereIn('rental_houses.id', self::leasedHouses($user)->select('h.id')),
            'vendor' => $query->whereIn('rental_houses.id', self::assignedRequests($user)->whereNotNull('m.house_id')->select('m.house_id')),
            'driver' => $query->whereRaw(self::NOTHING),
            default => $query->whereIn('rental_houses.property_id', self::rawPropertyIds($user)),
        };
    }

    /** Ids of rental_agreements (leases) the user may see. */
    private static function rawAgreementIds(User $user): Builder
    {
        $query = DB::table('rental_agreements')->select('rental_agreements.id');

        return match (self::role($user)) {
            'tenant' => $query->where('rental_agreements.tenant_id', $user->id),
            'vendor', 'driver' => $query->whereRaw(self::NOTHING),
            default => $query->whereIn('rental_agreements.house_id', self::rawHouseIds($user)),
        };
    }

    /** Ids of rental_bills the user may see. */
    private static function rawBillIds(User $user): Builder
    {
        return DB::table('rental_bills')->select('rental_bills.id')
            ->whereIn('rental_bills.agreement_id', self::rawAgreementIds($user));
    }

    /**
     * Ids of rental_payments the user may see: a tenant's own, otherwise those on the
     * account's bills -- plus advance payments (no bill yet) its own people collected.
     */
    private static function rawPaymentIds(User $user): Builder
    {
        $query = DB::table('rental_payments')->select('rental_payments.id');

        return match (self::role($user)) {
            'tenant' => $query->where('rental_payments.tenant_id', $user->id),
            'vendor', 'driver' => $query->whereRaw(self::NOTHING),
            default => $query->where(function ($q) use ($user) {
                $q->whereIn('rental_payments.bill_id', self::rawBillIds($user))
                    ->orWhere(function ($advance) use ($user) {
                        $advance->whereNull('rental_payments.bill_id')
                            ->whereIn('rental_payments.collector_id', $user->accountMemberIds());
                    });
            }),
        };
    }

    /** Ids of rental_maintenance_requests the user may see. */
    private static function rawRequestIds(User $user): Builder
    {
        $query = DB::table('rental_maintenance_requests')->select('rental_maintenance_requests.id');

        return match (self::role($user)) {
            'tenant' => $query->where('rental_maintenance_requests.tenant_id', $user->id),
            'vendor' => $query->whereIn('rental_maintenance_requests.id', self::assignedRequests($user)->select('m.id')),
            'driver' => $query->whereRaw(self::NOTHING),
            default => $query->whereIn('rental_maintenance_requests.property_id', self::rawPropertyIds($user)),
        };
    }

    /**
     * User ids of the tenants the account deals with: those on its leases, and those
     * its own people created. (A tenant sees only themself.)
     */
    private static function rawTenantUserIds(User $user): Builder
    {
        $query = DB::table('users')->select('users.id');

        return match (self::role($user)) {
            'tenant' => $query->where('users.id', $user->id),
            'vendor', 'driver' => $query->whereRaw(self::NOTHING),
            default => $query->where(function ($q) use ($user) {
                $q->whereIn('users.id', DB::table('rental_agreements')->select('tenant_id')
                    ->whereIn('rental_agreements.id', self::rawAgreementIds($user)))
                    ->orWhereIn('users.created_by', $user->accountMemberIds());
            }),
        };
    }


    // ----------------------------------------------------------------------------------
    // The public id sets. Each is the raw set above, built once as a derived table.
    //
    // Why: a model's scope is "id IN (select id from <the same table> where ...)". That is
    // fine to READ, but MySQL refuses an UPDATE or DELETE whose sub-select reads the very
    // table being changed (error 1093) -- SQLite does not, so tests never showed it, and it
    // would have made things like deleting a property fail for every business user. A derived
    // table that cannot be merged into the outer statement (DISTINCT) is built first, which
    // MySQL allows.
    // ----------------------------------------------------------------------------------

    /** Ids of rental_properties the user may see. */
    public static function propertyIds(User $user): Builder
    {
        return self::materialised(self::rawPropertyIds($user));
    }

    /** Ids of rental_houses the user may see. */
    public static function houseIds(User $user): Builder
    {
        return self::materialised(self::rawHouseIds($user));
    }

    /** Ids of rental_agreements (leases) the user may see. */
    public static function agreementIds(User $user): Builder
    {
        return self::materialised(self::rawAgreementIds($user));
    }

    /** Ids of rental_bills the user may see. */
    public static function billIds(User $user): Builder
    {
        return self::materialised(self::rawBillIds($user));
    }

    /**
     * Ids of rental_payments the user may see: a tenant's own, otherwise those on the
     * account's bills -- plus advance payments (no bill yet) its own people collected.
     */
    public static function paymentIds(User $user): Builder
    {
        return self::materialised(self::rawPaymentIds($user));
    }

    /** Ids of rental_maintenance_requests the user may see. */
    public static function requestIds(User $user): Builder
    {
        return self::materialised(self::rawRequestIds($user));
    }

    /**
     * User ids of the tenants the account deals with: those on its leases, and those
     * its own people created. (A tenant sees only themself.)
     */
    public static function tenantUserIds(User $user): Builder
    {
        return self::materialised(self::rawTenantUserIds($user));
    }

    private static function materialised(Builder $ids): Builder
    {
        return DB::query()->select('scope_ids.id')->fromSub($ids->distinct(), 'scope_ids');
    }

    /** The houses a tenant has leased (alias h), for their own leases. */
    private static function leasedHouses(User $user): Builder
    {
        return DB::table('rental_agreements as a')
            ->join('rental_houses as h', 'h.id', '=', 'a.house_id')
            ->where('a.tenant_id', $user->id);
    }

    /** The maintenance requests (alias m) that have work assigned to this vendor. */
    private static function assignedRequests(User $user): Builder
    {
        return DB::table('rental_maintenance_requests as m')
            ->join('rental_work_orders as w', 'w.maintenance_request_id', '=', 'm.id')
            ->join('rental_vendors as v', 'v.id', '=', 'w.vendor_id')
            ->where('v.user_id', $user->id);
    }
}
