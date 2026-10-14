<?php

namespace App\Models;

use App\Models\Concerns\ScopedToAccount;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One payment a business made for its plan, as a super admin recorded it. `period_start` .. `period_end`
 * is the time it bought; `period_end` became the business's `valid_until`.
 */
class BusinessPayment extends Model
{
    use ScopedToAccount;

    protected $fillable = [
        'business_id', 'amount', 'currency', 'method', 'reference', 'plan',
        'period_start', 'period_end', 'paid_at', 'recorded_by', 'note',
    ];

    protected $casts = [
        'amount' => 'float',
        'period_start' => 'datetime',
        'period_end' => 'datetime',
        'paid_at' => 'datetime',
    ];

    /** An owner (or their staff) can only ever see the payments of their own business; a super admin sees all. */
    public function constrainToAccount(Builder $query, User $user): void
    {
        $query->whereIn(
            $this->getTable() . '.business_id',
            Business::withoutAccountScope()->where('owner_id', $user->accountHeadId())->select('id')
        );
    }

    public function business(): BelongsTo
    {
        return $this->belongsTo(Business::class, 'business_id');
    }

    /** What the apps show: dates in ISO form, the money as a number. */
    public function toApiArray(): array
    {
        return [
            'id' => $this->id,
            'amount' => $this->amount,
            'currency' => $this->currency,
            'method' => $this->method,
            'reference' => $this->reference,
            'plan' => $this->plan,
            'period_start' => $this->period_start?->toIso8601String(),
            'period_end' => $this->period_end?->toIso8601String(),
            'paid_at' => $this->paid_at?->toIso8601String(),
            'note' => $this->note,
        ];
    }
}
