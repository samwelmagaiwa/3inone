<?php

namespace App\Rules;

use App\Support\Tenancy\TenantContext;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Unique;

/**
 * "Unique" validation for values that only have to be unique inside ONE business.
 *
 * `unique:devices,plate_number` checks the whole platform, which is wrong for a plate or a
 * licence number: it refuses a value another business uses, and so tells one business what
 * another one has. These rules check only rows stamped with the same business (`owner_id`, the
 * account head's user id), which is also exactly what the database's per-business unique indexes
 * enforce.
 *
 * Usage: 'plate_number' => ['required', PerBusiness::unique('devices', 'plate_number')]
 *        on an edit, pass the row being edited: PerBusiness::unique('devices', 'plate_number',
 *        ignoreId: $id, ownerId: $device->owner_id)
 */
final class PerBusiness
{
    /**
     * @param  string|null  $ownerId  the business to check inside; the signed-in business when omitted.
     *                                An edit passes the ROW's business, so a super admin fixing another
     *                                business's record is checked against that business.
     */
    public static function unique(string $table, string $column, ?string $ownerId = null, string|int|null $ignoreId = null): Unique
    {
        $owner = $ownerId ?? TenantContext::writeOwner();

        $rule = Rule::unique($table, $column)->where(function ($query) use ($owner) {
            $owner === null
                ? $query->whereNull('owner_id')
                : $query->where('owner_id', $owner);
        });

        return $ignoreId === null ? $rule : $rule->ignore($ignoreId);
    }
}
