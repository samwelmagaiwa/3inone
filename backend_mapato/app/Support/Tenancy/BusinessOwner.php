<?php

namespace App\Support\Tenancy;

use App\Models\User;

/**
 * Which business a value belongs to, for the things that must be unique inside one business
 * (a plate number, a licence number, a staff member's phone) rather than across the platform.
 *
 * "The business" is always the account head's user id, exactly as TenantContext and the inventory
 * `owner_id` columns define it.
 */
final class BusinessOwner
{
    /** The business a user belongs to (their account head's id), or null for an unknown user. */
    public static function ofUser(?string $userId): ?string
    {
        if ($userId === null || $userId === '') {
            return null;
        }

        $user = User::query()->find($userId);

        return $user?->accountHeadId();
    }

    /**
     * The business a request is working in: the signed-in user's own, or -- for a super admin
     * placing something inside a business -- the owner they name. Null when nobody is signed in.
     */
    public static function ofRequest(?string $namedOwnerId = null): ?string
    {
        if ($namedOwnerId !== null && $namedOwnerId !== '' && TenantContext::seesEverything()) {
            return $namedOwnerId;
        }

        return TenantContext::writeOwner();
    }
}
