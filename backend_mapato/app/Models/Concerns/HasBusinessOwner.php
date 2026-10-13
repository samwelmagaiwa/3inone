<?php

namespace App\Models\Concerns;

use Illuminate\Database\Eloquent\Model;

/**
 * Stamps a new row with the business it belongs to (the `owner_id` column: the account head's
 * user id), so values that must be unique inside ONE business -- a plate number, a licence
 * number -- can be enforced by the database per business instead of across the platform.
 *
 * The model says how to work its business out; rows that already carry an owner_id keep it.
 * Reads are NOT scoped by this column: who may see a row is still decided by the model's
 * ScopedToAccount rule, so a row with no owner_id (written by raw SQL, or whose owner could not
 * be worked out) stays visible to exactly who could see it before.
 *
 * @mixin Model
 */
trait HasBusinessOwner
{
    public static function bootHasBusinessOwner(): void
    {
        static::creating(function (Model $model) {
            if (empty($model->owner_id)) {
                $model->owner_id = $model->resolveBusinessOwnerId();
            }
        });
    }

    /** The account head's user id this new row belongs to, or null when it cannot be told. */
    abstract protected function resolveBusinessOwnerId(): ?string;
}
