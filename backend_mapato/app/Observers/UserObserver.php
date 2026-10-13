<?php

namespace App\Observers;

use App\Models\Business;
use App\Models\User;

/**
 * Every business has its record. The head of an account (admin / administrator / landlord) is the
 * business, so the moment such a user exists -- a self-registration, an owner a super admin
 * creates, a staff account promoted -- the business record exists too. Anyone else (staff,
 * drivers, tenants, a super admin) is not a business and gets none.
 *
 * Only ever adds the missing row; it never edits an existing one, so what an owner has typed
 * about their business is not overwritten when their login changes.
 */
class UserObserver
{
    public function created(User $user): void
    {
        Business::ensureFor($user);
    }

    public function updated(User $user): void
    {
        if ($user->wasChanged('role')) {
            Business::ensureFor($user);
        }
    }
}
