<?php

namespace App\Models\Rental;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use App\Traits\HasUuid;
use App\Models\User;

class House extends Model
{
    use HasFactory, HasUuid, SoftDeletes;

    use \App\Models\Concerns\ScopedToAccount;

    /** Fail-closed account scope: the houses the viewer may see (see App\Support\Tenancy\RentalAccess). */
    public function constrainToAccount(\Illuminate\Database\Eloquent\Builder $query, \App\Models\User $user): void
    {
        $query->whereIn($this->qualifyColumn('id'), \App\Support\Tenancy\RentalAccess::houseIds($user));
    }

    protected $table = 'rental_houses';

    protected $fillable = [
        'property_id',
        'block_id',
        'house_number',
        'type',
        'rent_amount',
        'deposit_amount',
        'electricity_meter',
        'water_meter',
        'status',
        'current_tenant_id',
        'floor',
        'bedrooms',
        'bathrooms',
        'square_meters',
        'description',
        'has_fence',
        'has_tiles',
        'has_sitting_room',
        'has_master_bedroom',
        'has_kitchen',
        'kitchen_location',
        'distance_from_road',
        'electricity_type',
        'electricity_sharing_count',
        'water_type',
        'water_sharing_count',
        'landlord_lives_present',
        'images',
        'image_captions',
        'maintenance_until',
        'units_count',
        'unit_names',
        'billing_cycle',
        'currency',
        'utility_billing_enabled',
        'ownership_notes',
    ];

    protected $casts = [
        'rent_amount' => 'decimal:2',
        'deposit_amount' => 'decimal:2',
        'bedrooms' => 'integer',
        'bathrooms' => 'integer',
        'square_meters' => 'integer',
        'images' => 'array',
        'image_captions' => 'array',
        'has_fence' => 'boolean',
        'has_tiles' => 'boolean',
        'has_sitting_room' => 'boolean',
        'has_master_bedroom' => 'boolean',
        'has_kitchen' => 'boolean',
        'landlord_lives_present' => 'boolean',
        'maintenance_until' => 'date',
        'units_count' => 'integer',
        'unit_names' => 'array',
        'utility_billing_enabled' => 'boolean',
    ];

    // Note: 'occupied_units' is NOT auto-appended here to avoid N+1 queries on list endpoints.
    // Append it explicitly in the single-house show() endpoint using $house->append('occupied_units').
    protected $appends = [];

    public function getOccupiedUnitsAttribute()
    {
        return $this->agreements()
            ->where('status', 'active')
            ->get()
            ->pluck('selected_units')
            ->flatten()
            ->filter()
            ->values()
            ->toArray();
    }

    /**
     * House type options.
     */
    public static function houseTypes(): array
    {
        return [
            'apartment' => 'Apartment',
            'room' => 'Room',
            'commercial' => 'Commercial',
            'studio' => 'Studio',
            'bedroom' => 'Bedroom',
            'single_room' => 'Single Room',
            'bedsitter' => 'Bedsitter',
            'one_bedroom' => '1 Bedroom',
            'two_bedroom' => '2 Bedroom',
            'three_bedroom' => '3 Bedroom',
        ];
    }

    /**
     * Status options.
     */
    public static function statuses(): array
    {
        return [
            'vacant' => 'Vacant',
            'occupied' => 'Occupied',
            'maintenance' => 'Under Maintenance',
            'reserved' => 'Reserved',
        ];
    }

    public function property()
    {
        return $this->belongsTo(Property::class);
    }

    public function block()
    {
        return $this->belongsTo(Block::class);
    }

    public function currentTenant()
    {
        return $this->belongsTo(User::class, 'current_tenant_id');
    }

    public function agreements()
    {
        return $this->hasMany(RentalAgreement::class);
    }

    public function activeAgreement()
    {
        return $this->hasOne(RentalAgreement::class)->where('status', 'active');
    }

    public function bills()
    {
        return $this->hasManyThrough(RentBill::class, RentalAgreement::class, 'house_id', 'agreement_id');
    }

    public function payments()
    {
        return $this->hasManyThrough(RentalPayment::class, RentalAgreement::class, 'house_id', 'tenant_id', 'id', 'tenant_id');
    }

    /**
     * Check if house is vacant.
     */
    public function getIsVacantAttribute(): bool
    {
        return $this->status === 'vacant';
    }

    /**
     * Get display identifier.
     */
    public function getDisplayNameAttribute(): string
    {
        $parts = array_filter([
            $this->property?->name,
            $this->block?->name,
            $this->house_number,
        ]);
        return implode(' - ', $parts);
    }
}