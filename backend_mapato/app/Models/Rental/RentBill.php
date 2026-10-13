<?php

namespace App\Models\Rental;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use App\Traits\HasUuid;

class RentBill extends Model
{
    use HasFactory, HasUuid;

    use \App\Models\Concerns\ScopedToAccount;

    /** Fail-closed account scope: bills on visible leases (see App\Support\Tenancy\RentalAccess). */
    public function constrainToAccount(\Illuminate\Database\Eloquent\Builder $query, \App\Models\User $user): void
    {
        $query->whereIn($this->qualifyColumn('id'), \App\Support\Tenancy\RentalAccess::billIds($user));
    }

    protected $table = 'rental_bills';

    protected $fillable = [
        'agreement_id',
        'month_year',
        'amount_due',
        'balance',
        'due_date',
        'status',
        'notes',
    ];

    protected $casts = [
        'due_date' => 'date',
    ];

    public function agreement()
    {
        return $this->belongsTo(RentalAgreement::class, 'agreement_id');
    }

    public function payments()
    {
        return $this->hasMany(RentalPayment::class, 'bill_id');
    }

    /**
     * Check if bill is overdue.
     */
    public function getIsOverdueAttribute(): bool
    {
        return in_array($this->status, ['unpaid', 'partial']) && 
               $this->due_date && 
               $this->due_date->lt(now()->toDateString());
    }
}
