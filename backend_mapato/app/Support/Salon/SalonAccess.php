<?php

namespace App\Support\Salon;

use App\Models\User;

/**
 * Who may do what in a salon, in one place. It is decided by the person's PERMISSIONS (the role's own plus whatever the
 * owner added for that person on the access-rights screen), exactly as in the other services, never by the role's name.
 */
final class SalonAccess
{
    /**
     * Sees the business's money and everyone's work (reports, takings, pay, the cashbook, the books). By default the owner
     * and the accountant: whoever holds the "reports" right.
     */
    public static function isManager(User $user): bool
    {
        return $user->seesAllAccounts() || $user->hasInventoryPermission('inv_view_reports');
    }

    /** Sets the salon up (branches, loyalty, vouchers, messages, online booking). By default the owner: the "settings" right. */
    public static function canConfigure(User $user): bool
    {
        return $user->seesAllAccounts() || $user->hasInventoryPermission('inv_manage_settings');
    }

    /** Hair stylists, nail technicians, lash and makeup artists: they see only their own diary, results and pay. */
    public static function isStylist(User $user): bool
    {
        return in_array(strtolower((string) $user->role), ['hair_stylist', 'nail_technician', 'lash_makeup_artist'], true);
    }
}
