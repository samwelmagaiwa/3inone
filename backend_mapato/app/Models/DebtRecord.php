<?php

namespace App\Models;

use App\Models\Concerns\ScopedThroughDriver;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Carbon\Carbon;

class DebtRecord extends Model
{
    use HasFactory, ScopedThroughDriver;

    protected $fillable = [
        'driver_id',
        'earning_date',
        'expected_amount',
        'paid_amount',
        'is_paid',
        'payment_id',
        'paid_at',
        'days_overdue',
        'notes',
        'license_number',
        'promised_to_pay',
        'promise_to_pay_at',
    ];

    protected $casts = [
        'earning_date' => 'date',
        'expected_amount' => 'decimal:2',
        'paid_amount' => 'decimal:2',
        'is_paid' => 'boolean',
        'paid_at' => 'datetime',
        'promised_to_pay' => 'boolean',
        'promise_to_pay_at' => 'datetime',
    ];

    protected $dates = [
        'earning_date',
        'paid_at',
        'promise_to_pay_at',
    ];

    /**
     * Boot the model to calculate days overdue
     */
    protected static function boot()
    {
        parent::boot();

        static::saving(function ($debtRecord) {
            $debtRecord->calculateDaysOverdue();
        });
    }

    /**
     * Get the driver that owns the debt record
     */
    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * Get the payment that covers this debt record
     */
    public function payment(): BelongsTo
    {
        return $this->belongsTo(Payment::class);
    }

    /**
     * Calculate days overdue
     */
    public function calculateDaysOverdue(): void
    {
        if (!$this->is_paid) {
            $earningDate = Carbon::parse($this->earning_date);
            $today = Carbon::today();
            $this->days_overdue = max(0, $today->diffInDays($earningDate, false));
        } else {
            $this->days_overdue = 0;
        }
    }

    /**
     * Mark this debt record as paid
     */
    public function markAsPaid(Payment $payment, float $amount = null): void
    {
        $this->update([
            'is_paid' => true,
            'paid_amount' => $amount ?? $this->expected_amount,
            'payment_id' => $payment->id,
            'paid_at' => now(),
            'days_overdue' => 0,
        ]);
    }

    /**
     * Get remaining amount to be paid
     */
    public function getRemainingAmountAttribute(): float
    {
        return max(0, $this->expected_amount - $this->paid_amount);
    }

    /**
     * Check if this debt record is overdue
     */
    public function getIsOverdueAttribute(): bool
    {
        return $this->days_overdue > 0 && !$this->is_paid;
    }

    /**
     * Get formatted date
     */
    public function getFormattedDateAttribute(): string
    {
        return $this->earning_date->format('d/m/Y');
    }

    /**
     * Scope for unpaid debt records
     */
    public function scopeUnpaid($query)
    {
        return $query->where('is_paid', false);
    }

    /**
     * Scope for paid debt records
     */
    public function scopePaid($query)
    {
        return $query->where('is_paid', true);
    }

    /**
     * Scope for overdue debt records
     */
    public function scopeOverdue($query)
    {
        return $query->where('days_overdue', '>', 0)->where('is_paid', false);
    }

    /**
     * Scope for debt records by driver
     */
    public function scopeByDriver($query, $driverId)
    {
        return $query->where('driver_id', $driverId);
    }

    /**
     * Scope for debt records within date range
     */
    public function scopeDateRange($query, $startDate, $endDate)
    {
        return $query->whereBetween('earning_date', [$startDate, $endDate]);
    }

    /**
     * Create debt records for a driver for missing days
     */
    public static function createMissingRecords(string $driverId, array $dates, float $expectedAmount): void
    {
        foreach ($dates as $date) {
            self::firstOrCreate(
                [
                    'driver_id' => $driverId,
                    'earning_date' => $date,
                ],
                [
                    'expected_amount' => $expectedAmount,
                    'paid_amount' => 0,
                    'is_paid' => false,
                ]
            );
        }
    }

    /**
     * Get debt record summary for API response
     */
    public function toApiResponse(): array
    {
        return [
            'id' => $this->id,
            'driver_id' => $this->driver_id,
            'driver_name' => $this->driver->name ?? null,
            'date' => $this->earning_date->toDateString(),
            'formatted_date' => $this->formatted_date,
            'expected_amount' => $this->expected_amount,
            'paid_amount' => $this->paid_amount,
            'remaining_amount' => $this->remaining_amount,
            'is_paid' => $this->is_paid,
            'is_overdue' => $this->is_overdue,
            'days_overdue' => $this->days_overdue,
            'payment_id' => $this->payment_id,
            'paid_at' => $this->paid_at?->toISOString(),
            'notes' => $this->notes,
'license_number' => $this->license_number,
            'promised_to_pay' => (bool) ($this->promised_to_pay ?? false),
            'promise_to_pay_at' => $this->promise_to_pay_at?->toISOString(),
        ];
    }

    /**
     * Get summary statistics for a driver's debt records
     */
    public static function getSummaryForDriver(string $driverId): array
    {
        $records = self::byDriver($driverId)->get();
        
        $totalDebt = $records->where('is_paid', false)->sum('remaining_amount');
        $unpaidDays = $records->where('is_paid', false)->count();
        $overdueDays = $records->where('is_overdue', true)->count();
        $totalPaid = $records->sum('paid_amount');
        $lastPayment = $records->where('is_paid', true)->max('paid_at');

        return [
            'driver_id' => $driverId,
            'total_debt' => $totalDebt,
            'unpaid_days' => $unpaidDays,
            'overdue_days' => $overdueDays,
            'total_paid' => $totalPaid,
            'last_payment_date' => $lastPayment,
            'debt_records' => $records->map->toApiResponse(),
        ];
    }

    /**
     * Get summary for a driver within a date range
     */
    public static function getSummaryForDriverInRange(string $driverId, string $startDate, string $endDate): array
    {
        $records = self::byDriver($driverId)
            ->dateRange($startDate, $endDate)
            ->get();

        $totalDebt = $records->where('is_paid', false)->sum('remaining_amount');
        $unpaidDays = $records->where('is_paid', false)->count();
        $overdueDays = $records->where('is_overdue', true)->count();
        $totalPaid = $records->sum('paid_amount');
        $lastPayment = $records->where('is_paid', true)->max('paid_at');

        return [
            'driver_id' => $driverId,
            'total_debt' => $totalDebt,
            'unpaid_days' => $unpaidDays,
            'overdue_days' => $overdueDays,
            'total_paid' => $totalPaid,
            'last_payment_date' => $lastPayment,
            'debt_records' => $records->map->toApiResponse(),
        ];
    }
}
