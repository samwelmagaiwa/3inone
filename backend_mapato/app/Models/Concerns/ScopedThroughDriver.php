<?php

namespace App\Models\Concerns;

use App\Models\Driver;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;

/**
 * For transport records (payments, debts, receipts, agreements, ...) that have
 * no owner of their own: they belong to the account of the driver they are
 * about, so they are visible exactly when that driver is.
 */
trait ScopedThroughDriver
{
    use ScopedToAccount;

    public function constrainToAccount(Builder $query, User $user): void
    {
        // Driver carries its own account scope, so this subquery is already narrowed.
        $query->whereIn(
            $this->qualifyColumn('driver_id'),
            Driver::query()->select('drivers.id')->toBase()
        );
    }
}
