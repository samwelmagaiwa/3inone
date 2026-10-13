<?php

namespace App\Models\Scopes;

use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

/**
 * Limits every query on an opted-in model to the signed-in user's own account.
 *
 * It is a global scope on purpose: a controller that forgets to filter, or a
 * dashboard total written as Model::count(), is still safe. It only acts while
 * a user is authenticated, so queue workers, artisan commands and the login
 * flow (which has no user yet) are unaffected.
 *
 * The model decides what "its account" means in constrainToAccount().
 */
class AccountScope implements Scope
{
    public const NAME = 'account';

    public function apply(Builder $builder, Model $model): void
    {
        // The same "who is acting" the Inventory query scope uses, so every
        // service answers it identically (and TenantContext::runAs() works for all).
        $user = TenantContext::viewer();

        if (!$user instanceof User || $user->seesAllAccounts()) {
            return;
        }

        /** @var \App\Models\Concerns\ScopedToAccount $model */
        $model->constrainToAccount($builder, $user);
    }
}
