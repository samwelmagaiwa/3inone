<?php

namespace App\Models\Rental;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use App\Traits\HasUuid;

class RentalReceipt extends Model
{
    use HasFactory, HasUuid;

    use \App\Models\Concerns\ScopedToAccount;

    /** Fail-closed account scope: receipts for visible payments (see App\Support\Tenancy\RentalAccess). */
    public function constrainToAccount(\Illuminate\Database\Eloquent\Builder $query, \App\Models\User $user): void
    {
        $query->whereIn($this->qualifyColumn('payment_id'), \App\Support\Tenancy\RentalAccess::paymentIds($user));
    }

    protected $table = 'rental_receipts';

    protected $fillable = [
        'payment_id',
        'receipt_number',
        'details',
        'is_dispatched',
    ];

    protected $casts = [
        'details' => 'array',
    ];

    public function payment()
    {
        return $this->belongsTo(RentalPayment::class, 'payment_id');
    }
}
