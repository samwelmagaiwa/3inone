<?php

namespace App\Models\Rental;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use App\Traits\HasUuid;
use App\Models\User;

class RentalAgreement extends Model
{
    use HasFactory, HasUuid;

    use \App\Models\Concerns\ScopedToAccount;

    /** Fail-closed account scope: the leases the viewer may see (see App\Support\Tenancy\RentalAccess). */
    public function constrainToAccount(\Illuminate\Database\Eloquent\Builder $query, \App\Models\User $user): void
    {
        $query->whereIn($this->qualifyColumn('id'), \App\Support\Tenancy\RentalAccess::agreementIds($user));
    }

    protected $table = 'rental_agreements';

    protected $fillable = [
        'agreement_number',
        'tenant_id',
        'property_id',
        'house_id',
        'start_date',
        'end_date',
        'rent_cycle',
        'rent_amount',
        'deposit_amount',
        'deposit_paid',
        'due_day',
        'grace_period_days',
        'late_fee_type',
        'late_fee_amount',
        'utility_charges',
        'rules',
        'status',
        'terms',
        'notes',
        'documents',
        'signed_pdf_url',
        'notice_period_days',
        'auto_renew',
        'penalty_per_day',
        'created_by',
        'selected_units',
    ];

    protected $casts = [
        'start_date' => 'date',
        'end_date' => 'date',
        'utility_charges' => 'array',
        'rules' => 'array',
        'documents' => 'array',
        'auto_renew' => 'boolean',
        'selected_units' => 'array',
    ];

    public function tenant()
    {
        return $this->belongsTo(User::class, 'tenant_id');
    }

    public function house()
    {
        return $this->belongsTo(House::class);
    }

    public function property()
    {
        return $this->belongsTo(Property::class);
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function bills()
    {
        return $this->hasMany(RentBill::class, 'agreement_id');
    }

    public function payments()
    {
        return $this->hasMany(RentalPayment::class, 'tenant_id', 'tenant_id');
    }

    /**
     * In API responses each uploaded document carries a short-lived signed `url` (the lease
     * documents are signed contracts and ID cards, so they are not publicly reachable).
     */
    public function attributesToArray()
    {
        $attributes = parent::attributesToArray();

        if (!empty($attributes['documents']) && is_array($attributes['documents'])) {
            $attributes['documents'] = array_map(
                fn ($doc) => is_array($doc) && !empty($doc['path'])
                    ? array_merge($doc, ['url' => \App\Support\PrivateFile::url($doc['path'])])
                    : $doc,
                $attributes['documents']
            );
        }

        return $attributes;
    }
}
