<?php

namespace App\Models;

use App\Models\Concerns\HasBusinessOwner;
use App\Models\Concerns\ScopedThroughDriver;
use App\Support\Tenancy\BusinessOwner;
use App\Support\Tenancy\TenantContext;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class PaymentReceipt extends Model
{
    use HasFactory, ScopedThroughDriver, HasBusinessOwner;

    protected $table = 'payment_receipts';

    /**
     * Receipts are numbered per business (each starts from 0001), so the number is unique inside the
     * business of the driver the receipt is for, not across the platform.
     */
    protected function resolveBusinessOwnerId(): ?string
    {
        $driver = $this->driver_id ? Driver::withoutAccountScope()->find($this->driver_id) : null;

        return $driver
            ? ($driver->owner_id ?: BusinessOwner::ofUser((string) $driver->user_id))
            : TenantContext::writeOwner();
    }

    protected $fillable = [
        'receipt_number',
        'payment_id',
        'driver_id',
        'generated_by',
        'amount',
        'payment_period',
        'covered_days',
        'status',
        'generated_at',
        'sent_at',
        'sent_via',
        'receipt_data',
    ];

    protected $casts = [
        'covered_days' => 'array',
        'receipt_data' => 'array',
        'amount' => 'decimal:2',
        'generated_at' => 'datetime',
        'sent_at' => 'datetime',
    ];

    /**
     * Generate a unique receipt number
     */
    public static function generateReceiptNumber(): string
    {
        $prefix = 'RCT';
        $date = now()->format('ymd');
        
        // Get the last receipt number for today
        $lastReceipt = static::whereDate('generated_at', today())
            ->orderByDesc('id')
            ->first();
            
        if ($lastReceipt) {
            $lastNumber = (int) substr($lastReceipt->receipt_number, -4);
            $nextNumber = $lastNumber + 1;
        } else {
            $nextNumber = 1;
        }
        
        return $prefix . $date . str_pad($nextNumber, 4, '0', STR_PAD_LEFT);
    }

    /**
     * Relationship with Payment
     */
    public function payment(): BelongsTo
    {
        return $this->belongsTo(Payment::class);
    }

    /**
     * Relationship with Driver
     */
    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * Relationship with User (who generated the receipt)
     */
    public function generatedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'generated_by');
    }

    /**
     * Check if receipt has been sent
     */
    public function isSent(): bool
    {
        return in_array($this->status, ['sent', 'delivered']);
    }

    /**
     * Mark receipt as sent
     */
    public function markAsSent(string $via): void
    {
        $this->update([
            'status' => 'sent',
            'sent_at' => now(),
            'sent_via' => $via,
        ]);
    }

    /**
     * Get formatted payment period
     */
    public function getFormattedPeriodAttribute(): string
    {
        $days = count($this->covered_days ?? []);
        
        if ($days === 1) {
            return '1 siku';
        } elseif ($days <= 7) {
            return $days . ' siku';
        } elseif ($days <= 14) {
            return '1-2 wiki';
        } elseif ($days <= 30) {
            return round($days / 7) . ' wiki';
        } else {
            return round($days / 30) . ' miezi';
        }
    }

    /**
     * Get receipt preview data
     */
    public function getPreviewData(): array
    {
        $tripsTotal = static::where('driver_id', $this->driver_id)->count();
        return [
            'id' => $this->id,
            'receipt_id' => $this->id, // Alternative key for compatibility
            'receipt_number' => $this->receipt_number,
            'driver_name' => $this->driver->name ?? '',
            'driver_phone' => $this->driver->phone ?? '',
            'amount' => $this->amount,
            'payment_period' => $this->formatted_period,
            'covered_days' => $this->covered_days ?? [],
            'generated_at' => optional($this->generated_at)->format('d/m/Y H:i') ?? '',
            'status' => $this->status,
            'owner_name' => $this->generatedBy->name ?? '',
            'trips_total' => (int) $tripsTotal,
        ];
    }

    /**
     * Scope to get pending receipts (generated but not sent)
     */
    public function scopePending($query)
    {
        return $query->where('status', 'generated');
    }

    /**
     * Scope to get sent receipts
     */
    public function scopeSent($query)
    {
        return $query->whereIn('status', ['sent', 'delivered']);
    }
}