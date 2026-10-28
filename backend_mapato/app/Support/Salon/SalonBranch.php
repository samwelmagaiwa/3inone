<?php

namespace App\Support\Salon;

use App\Support\Tenancy\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Which branch a request is about. The app sends `X-Branch: <id>` when someone has chosen a branch to work in or look
 * at; with no header it is "all branches" for a report, and for a new record it is the person's home branch (if they have
 * one). A header that names a branch of another salon, or one that is switched off, is ignored.
 *
 * A business with a single branch never sets any of this: every branch_id stays empty and nothing changes for it.
 */
final class SalonBranch
{
    public static function available(): bool
    {
        // A salon, and a shop or depot with more than one place to sell from (the same branches, the same stock by branch).
        return in_array(TenantContext::service(), ['salon', 'inventory'], true) && Schema::hasTable('inventory_branches') && Schema::hasColumn('inventory_sales', 'branch_id');
    }

    /** The branch looked at or worked in, or null for "all". */
    public static function selected(?Request $request = null): ?int
    {
        $request ??= request();
        $asked = $request?->header('X-Branch');
        if (!self::available() || $asked === null || $asked === '' || !ctype_digit((string) $asked)) {
            return null;
        }

        // A branch chosen in another service (ids of different services are different lists) is not this service's.
        $sent = $request->header('X-Branch-Service');
        if ($sent !== null && $sent !== TenantContext::service()) {
            return null;
        }

        return DB::table('inventory_branches')->where('id', (int) $asked)->where('active', true)->exists() ? (int) $asked : null;
    }

    /** The branch to stamp on a new record: the one chosen, else the person's home branch, else none. */
    public static function forNew(?Request $request = null): ?int
    {
        if (!self::available()) {
            return null;
        }
        $request ??= request();

        return self::selected($request) ?? self::homeOf((string) ($request?->user()?->id ?? ''));
    }

    public static function homeOf(string $staffId): ?int
    {
        if ($staffId === '' || !Schema::hasColumn('inventory_staff_profiles', 'branch_id')) {
            return null;
        }
        $home = DB::table('inventory_staff_profiles')->where('staff_id', $staffId)->value('branch_id');

        return $home !== null && DB::table('inventory_branches')->where('id', $home)->where('active', true)->exists() ? (int) $home : null;
    }
}
