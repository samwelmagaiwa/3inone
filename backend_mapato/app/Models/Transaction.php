<?php

namespace App\Models;

use App\Models\Concerns\ScopedThroughDriver;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use App\Traits\HasUuid;
use App\Enums\PaymentStatus;

class Transaction extends Model
{
    use HasFactory, HasUuid, ScopedThroughDriver;

    /**
     * The attributes that are mass assignable.
     */
    protected $fillable = [
        'driver_id',
        'device_id',
        'amount',
        'type',
        'category',
        'description',
        'customer_name',
        'customer_phone',
        'status',
        'notes',
        'transaction_date',
        'reference_number',
        'payment_method',
    ];

    /**
     * The attributes that should be cast.
     */
    protected $casts = [
        'amount' => 'decimal:2',
        'transaction_date' => 'datetime',
        'status' => PaymentStatus::class,
    ];

    /**
     * Transaction types
     */
    const TYPES = [
        'income' => 'Mapato',
        'expense' => 'Matumizi',
    ];

    /**
     * Transaction statuses
     */
    const STATUSES = [
        'pending' => 'Inasubiri',
        'completed' => 'Imekamilika',
        'cancelled' => 'Imeghairiwa',
    ];

    /**
     * Payment categories (Admin records driver payments)
     */
    const PAYMENT_CATEGORIES = [
        'daily_payment' => 'Malipo ya Kila Siku',
        'weekly_payment' => 'Malipo ya Kila Wiki',
        'trip_payment' => 'Malipo ya Safari',
        'delivery_payment' => 'Malipo ya Uwasilishaji',
        'rental_payment' => 'Malipo ya Kukodisha',
        'fuel_contribution' => 'Mchango wa Mafuta',
        'maintenance_fee' => 'Ada ya Matengenezo',
        'other_payment' => 'Malipo Mengine',
    ];

    /**
     * Admin expense categories
     */
    const EXPENSE_CATEGORIES = [
        'fuel' => 'Mafuta',
        'maintenance' => 'Matengenezo',
        'insurance' => 'Bima',
        'license_renewal' => 'Upyaji wa Leseni',
        'parking_fees' => 'Ada ya Maegesho',
        'vehicle_repair' => 'Ukarabati wa Gari',
        'spare_parts' => 'Vipuri',
        'driver_allowance' => 'Posho ya Dereva',
        'other_expenses' => 'Matumizi Mengine',
    ];

    /**
     * Payment methods
     */
    const PAYMENT_METHODS = [
        'cash' => 'Fedha Taslimu',
        'mobile_money' => 'Pesa za Simu',
        'bank_transfer' => 'Uhamisho wa Benki',
        'card' => 'Kadi',
    ];

    /**
     * Get the driver that owns the transaction.
     */
    public function driver()
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * Get the device associated with the transaction.
     */
    public function device()
    {
        return $this->belongsTo(Device::class);
    }

    /**
     * Get the receipt for the transaction.
     */
    public function receipt()
    {
        return $this->hasOne(Receipt::class);
    }

    /**
     * Get the transaction type display name.
     */
    public function getTypeDisplayAttribute()
    {
        return self::TYPES[$this->type] ?? $this->type;
    }

    /**
     * Get the transaction status display name.
     */
    public function getStatusDisplayAttribute()
    {
        return self::STATUSES[$this->status] ?? $this->status;
    }

    /**
     * Get the category display name.
     */
    public function getCategoryDisplayAttribute()
    {
        $categories = $this->type === 'income' ? self::PAYMENT_CATEGORIES : self::EXPENSE_CATEGORIES;
        return $categories[$this->category] ?? $this->category;
    }

    /**
     * Get the payment method display name.
     */
    public function getPaymentMethodDisplayAttribute()
    {
        return self::PAYMENT_METHODS[$this->payment_method] ?? $this->payment_method;
    }

    /**
     * Check if transaction is income.
     */
    public function isIncome(): bool
    {
        return $this->type === 'income';
    }

    /**
     * Check if transaction is expense.
     */
    public function isExpense(): bool
    {
        return $this->type === 'expense';
    }

    /**
     * Check if transaction is completed.
     */
    public function isCompleted(): bool
    {
        return $this->status === 'completed';
    }

    /**
     * Check if transaction is pending.
     */
    public function isPending(): bool
    {
        return $this->status === 'pending';
    }

    /**
     * Check if transaction is cancelled.
     */
    public function isCancelled(): bool
    {
        return $this->status === 'cancelled';
    }

    /**
     * Generate reference number.
     */
    public static function generateReferenceNumber(): string
    {
        return 'TXN' . date('Ymd') . str_pad(self::count() + 1, 6, '0', STR_PAD_LEFT);
    }

    /**
     * Scope to get income transactions.
     */
    public function scopeIncome($query)
    {
        return $query->where('type', 'income');
    }

    /**
     * Scope to get expense transactions.
     */
    public function scopeExpense($query)
    {
        return $query->where('type', 'expense');
    }

    /**
     * Scope to get completed transactions.
     */
    public function scopeCompleted($query)
    {
        return $query->where('status', 'completed');
    }

    /**
     * Scope to get pending transactions.
     */
    public function scopePending($query)
    {
        return $query->where('status', 'pending');
    }

    /**
     * Scope to get transactions for today.
     */
    public function scopeToday($query)
    {
        return $query->whereDate('transaction_date', today());
    }

    /**
     * Scope to get transactions for this week.
     */
    public function scopeThisWeek($query)
    {
        return $query->whereBetween('transaction_date', [now()->startOfWeek(), now()->endOfWeek()]);
    }

    /**
     * Scope to get transactions for this month.
     */
    public function scopeThisMonth($query)
    {
        return $query->whereMonth('transaction_date', now()->month)
                    ->whereYear('transaction_date', now()->year);
    }

    /**
     * Scope to get transactions by date range.
     */
    public function scopeDateRange($query, $startDate, $endDate)
    {
        return $query->whereBetween('transaction_date', [$startDate, $endDate]);
    }

    /**
     * Scope to get transactions by category.
     */
    public function scopeByCategory($query, $category)
    {
        return $query->where('category', $category);
    }

    /**
     * Boot method to set default values.
     */
    protected static function boot()
    {
        parent::boot();

        static::creating(function ($transaction) {
            if (!$transaction->reference_number) {
                $transaction->reference_number = self::generateReferenceNumber();
            }
            
            if (!$transaction->transaction_date) {
                $transaction->transaction_date = now();
            }
            
            if (!$transaction->status) {
                $transaction->status = 'pending';
            }
        });
    }
}