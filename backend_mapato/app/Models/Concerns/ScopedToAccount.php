<?php

namespace App\Models\Concerns;

use App\Models\Scopes\AccountScope;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;

/**
 * Opt a model into per-account isolation (see AccountScope).
 *
 * Implement constrainToAccount() to say which rows the given non-super_admin
 * user may see. Use Model::withoutAccountScope() only where a query must span
 * accounts on purpose (and say why in a comment).
 */
trait ScopedToAccount
{
    public static function bootScopedToAccount(): void
    {
        static::addGlobalScope(AccountScope::NAME, new AccountScope());
    }

    /** Narrow $query to the rows $user's account may see. */
    abstract public function constrainToAccount(Builder $query, User $user): void;

    public static function withoutAccountScope(): Builder
    {
        return static::withoutGlobalScope(AccountScope::NAME);
    }
}
