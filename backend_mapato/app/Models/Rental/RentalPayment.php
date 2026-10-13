<?php

namespace App\Models\Rental;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use App\Traits\HasUuid;
use App\Models\User;

class RentalPayment extends Model
{
    use HasFactory, HasUuid;

    use \App\Models\Concerns\ScopedToAccount;

    /** Fail-closed account scope: payments the viewer may see (see App\Support\Tenancy\RentalAccess). */
    public function constrainToAccount(\Illuminate\Database\Eloquent\Builder $query, \App\Models\User $user): void
    {
        $query->whereIn($this->qualifyColumn('id'), \App\Support\Tenancy\RentalAccess::paymentIds($user));
    }

    protected $table = 'rental_payments';

    protected $fillable = [
        'bill_id',
        'tenant_id',
        'amount_paid',
        'payment_date',
        'payment_method',
        'transaction_reference',
        'collector_id',
        'notes',
    ];

    protected $casts = [
        'payment_date' => 'date',
    ];

    public function bill()
    {
        return $this->belongsTo(RentBill::class, 'bill_id');
    }

    public function tenant()
    {
        return $this->belongsTo(User::class, 'tenant_id');
    }

    public function collector()
    {
        return $this->belongsTo(User::class, 'collector_id');
    }

    public function receipt()
    {
        return $this->hasOne(RentalReceipt::class, 'payment_id');
    }
}
