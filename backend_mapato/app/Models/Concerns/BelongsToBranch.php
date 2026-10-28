<?php

namespace App\Models\Concerns;

use App\Models\User;
use App\Support\Tenancy\ServiceBranch;
use Illuminate\Database\Eloquent\Model;

/**
 * A record that can belong to one branch of the business (a driver, a vehicle, a property). A new record takes the branch
 * the person is looking at when they save it, unless the form named one; with "all branches" in view and none named it
 * stays without a branch. See ServiceBranch and the business_branches table.
 */
trait BelongsToBranch
{
    /** 'transport' or 'rental'. */
    abstract protected function branchService(): string;

    public static function bootBelongsToBranch(): void
    {
        static::creating(function (Model $model) {
            // A form that named a branch (or named none on purpose) is not second-guessed.
            if (array_key_exists('branch_id', $model->getAttributes())) {
                return;
            }
            $user = auth()->user();
            if ($user instanceof User) {
                $model->branch_id = ServiceBranch::selected($model->branchService(), $user);
            }
        });
    }
}
