<?php

namespace App\Support\Salon;

use App\Models\User;

/** Who is who in a salon, in one place: the people who run it, and the people who do the work themselves. */
final class SalonAccess
{
    /** The owner, managers and accountants: they see the business's money and everyone's work. */
    public static function isManager(User $user): bool
    {
        return $user->seesAllAccounts() || in_array(strtolower((string) $user->role), ['admin', 'administrator', 'manager', 'accountant'], true);
    }

    /** Hair stylists, nail technicians, lash and makeup artists: they see only their own diary, results and pay. */
    public static function isStylist(User $user): bool
    {
        return in_array(strtolower((string) $user->role), ['hair_stylist', 'nail_technician', 'lash_makeup_artist'], true);
    }
}
