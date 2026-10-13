<?php

namespace App\Models\Rental;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use App\Traits\HasUuid;

class Block extends Model
{
    use HasFactory, HasUuid, SoftDeletes;

    use \App\Models\Concerns\ScopedToAccount;

    /** Fail-closed account scope: blocks of a visible property; vendors have no business with them (see App\Support\Tenancy\RentalAccess). */
    public function constrainToAccount(\Illuminate\Database\Eloquent\Builder $query, \App\Models\User $user): void
    {
        if (in_array(\App\Support\Tenancy\RentalAccess::role($user), ['vendor', 'driver'], true)) {
            $query->whereRaw('1 = 0');

            return;
        }

        $query->whereIn($this->qualifyColumn('property_id'), \App\Support\Tenancy\RentalAccess::propertyIds($user));
    }

    protected $table = 'rental_blocks';

    protected $fillable = [
        'property_id',
        'name',
        'description',
    ];

    public function property()
    {
        return $this->belongsTo(Property::class);
    }

    public function houses()
    {
        return $this->hasMany(House::class);
    }
}
