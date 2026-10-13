<?php

namespace App\Models;

use App\Models\Concerns\ScopedThroughDriver;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Str;

class Payment extends Model
{
    use HasFactory, ScopedThroughDriver;

    protected $fillable = [
        'reference_number',
        'driver_id',
        'amount',
        'payment_channel',
        'remarks',
        'covers_days',
        'status',
        'payment_date',
        'recorded_by',
        'receipt_status',
        'payment_type',
    ];

    protected $casts = [
        'amount' => 'decimal:2',
        'covers_days' => 'array',
        'payment_date' => 'datetime',
    ];

    protected $dates = [
        'payment_date',
    ];

    /**
     * Boot the model and generate reference number
     */
    protected static function boot()
    {
        parent::boot();

        static::creating(function ($payment) {
            if (empty($payment->reference_number)) {
                $payment->reference_number = self::generateReferenceNumber();
            }
        });

        // Trigger prediction refresh when payments change
        static::created(function ($payment) {
            \App\Jobs\PredictDriverCompletionJob::dispatch($payment->driver_id);
        });
        static::updated(function ($payment) {
            \App\Jobs\PredictDriverCompletionJob::dispatch($payment->driver_id);
        });
        static::deleted(function ($payment) {
            \App\Jobs\PredictDriverCompletionJob::dispatch($payment->driver_id);
        });
    }

    /**
     * Generate unique reference number
     */
    public static function generateReferenceNumber(): string
    {
        do {
            $reference = 'PAY-' . strtoupper(Str::random(8));
        } while (self::where('reference_number', $reference)->exists());

        return $reference;
    }

    /**
     * Get the driver that owns the payment
     */
    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * Get the user who recorded this payment
     */
    public function recordedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'recorded_by');
    }

    /**
     * Get the debt records covered by this payment
     */
    public function debtRecords(): HasMany
    {
        return $this->hasMany(DebtRecord::class);
    }

    /**
     * Get the payment receipt
     */
    public function paymentReceipt()
    {
        return $this->hasOne(PaymentReceipt::class);
    }

    /**
     * Scope for completed payments
     */
    public function scopeCompleted($query)
    {
        return $query->where('status', 'completed');
    }

    /**
     * Scope for payments by driver
     */
    public function scopeByDriver($query, $driverId)
    {
        return $query->where('driver_id', $driverId);
    }

    /**
     * Scope for payments within date range
     */
    public function scopeDateRange($query, $startDate, $endDate)
    {
        return $query->whereBetween('payment_date', [$startDate, $endDate]);
    }

    /**
     * Scope for payments without receipts generated
     */
    public function scopePendingReceipt($query)
    {
        return $query->where('receipt_status', 'pending')
                    ->orWhereNull('receipt_status');
    }

    /**
     * Scope for payments with receipts generated but not sent
     */
    public function scopeReceiptGenerated($query)
    {
        return $query->where('receipt_status', 'generated');
    }

    /**
     * Get formatted payment channel
     */
    public function getFormattedPaymentChannelAttribute(): string
    {
        return match($this->payment_channel) {
            'cash' => 'Pesa Taslimu',
            'mpesa' => 'M-Pesa',
            'bank' => 'Benki',
            'mobile' => 'Simu ya Mkono',
            'other' => 'Nyingine',
            default => 'Pesa Taslimu'
        };
    }

    /**
     * Get the number of days covered by this payment
     */
    public function getCoveredDaysCountAttribute(): int
    {
        return count($this->covers_days ?? []);
    }

    /**
     * Check if payment covers a specific date
     */
    public function coversDate(string $date): bool
    {
        return in_array($date, $this->covers_days ?? []);
    }

    /**
     * Get payment summary for API response
     */
    public function toApiResponse(): array
    {
        return [
            'id' => $this->id,
            'reference_number' => $this->reference_number,
            'driver_id' => $this->driver_id,
            'driver_name' => $this->driver->name ?? null,
            'amount' => $this->amount,
            'payment_channel' => $this->payment_channel,
            'formatted_payment_channel' => $this->formatted_payment_channel,
            'covers_days' => $this->covers_days,
            'covered_days_count' => $this->covered_days_count,
            'remarks' => $this->remarks,
            'status' => $this->status,
            'payment_date' => $this->payment_date->toISOString(),
            'recorded_by' => $this->recordedBy->name ?? null,
            'created_at' => $this->created_at->toISOString(),
            'updated_at' => $this->updated_at->toISOString(),
        ];
    }
}