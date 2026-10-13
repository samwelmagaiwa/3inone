<?php

namespace App\Models\Rental;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Concerns\HasUuids;

class PreventiveMaintenance extends Model
{
    use HasFactory, HasUuids;

    use \App\Models\Concerns\ScopedToAccount;

    /** Fail-closed account scope: the maintenance plans of properties the viewer manages (see App\Support\Tenancy\RentalAccess). */
    public function constrainToAccount(\Illuminate\Database\Eloquent\Builder $query, \App\Models\User $user): void
    {
        if (!\App\Support\Tenancy\RentalAccess::managesProperties($user)) {
            $query->whereRaw('1 = 0'); // a landlord's plans are not for tenants or vendors

            return;
        }

        $query->whereIn($this->qualifyColumn('property_id'), \App\Support\Tenancy\RentalAccess::propertyIds($user));
    }

    protected $table = 'rental_preventive_maintenance';

    protected $fillable = [
        'property_id',
        'house_id',
        'description',
        'frequency',
        'last_run',
        'next_run',
        'is_active',
    ];

    protected $casts = [
        'last_run' => 'date',
        'next_run' => 'date',
        'is_active' => 'boolean',
    ];

    public function property()
    {
        return $this->belongsTo(Property::class);
    }

    public function house()
    {
        return $this->belongsTo(House::class);
    }
}
