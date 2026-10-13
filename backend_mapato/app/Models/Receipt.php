<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use App\Models\Concerns\HasBusinessOwner;
use App\Models\Concerns\ScopedToAccount;
use App\Support\Tenancy\BusinessOwner;
use App\Support\Tenancy\TenantContext;
use App\Traits\HasUuid;
use Illuminate\Database\Eloquent\Builder;

class Receipt extends Model
{
    use HasFactory, HasUuid, ScopedToAccount, HasBusinessOwner;

    /**
     * Receipts are numbered per business (each starts from 0001), so the number is unique inside the
     * business of the driver the receipt's transaction is for, not across the platform.
     */
    protected function resolveBusinessOwnerId(): ?string
    {
        $driverId = $this->transaction_id
            ? Transaction::withoutGlobalScopes()->whereKey($this->transaction_id)->value('driver_id')
            : null;
        $driver = $driverId ? Driver::withoutAccountScope()->find($driverId) : null;

        return $driver
            ? ($driver->owner_id ?: BusinessOwner::ofUser((string) $driver->user_id))
            : TenantContext::writeOwner();
    }

    /** A receipt belongs to the account of the transaction it was issued for. */
    public function constrainToAccount(Builder $query, User $user): void
    {
        $query->whereIn(
            $this->qualifyColumn('transaction_id'),
            Transaction::query()->select('transactions.id')->toBase()
        );
    }

    /**
     * The attributes that are mass assignable.
     */
    protected $fillable = [
        'transaction_id',
        'receipt_number',
        'customer_name',
        'customer_phone',
        'service_description',
        'amount',
        'notes',
        'file_path',
        'issued_at',
        'is_printed',
        'printed_at',
    ];

    /**
     * The attributes that should be cast.
     */
    protected $casts = [
        'amount' => 'decimal:2',
        'issued_at' => 'datetime',
        'printed_at' => 'datetime',
        'is_printed' => 'boolean',
    ];

    /**
     * Get the transaction that owns the receipt.
     */
    public function transaction()
    {
        return $this->belongsTo(Transaction::class);
    }

    /**
     * Get the driver through the transaction.
     */
    public function driver()
    {
        return $this->hasOneThrough(Driver::class, Transaction::class, 'id', 'id', 'transaction_id', 'driver_id');
    }

    /**
     * Get the device through the transaction.
     */
    public function device()
    {
        return $this->hasOneThrough(Device::class, Transaction::class, 'id', 'id', 'transaction_id', 'device_id');
    }

    /**
     * Generate receipt number.
     */
    public static function generateReceiptNumber(): string
    {
        return 'R' . date('Ymd') . str_pad(self::count() + 1, 4, '0', STR_PAD_LEFT);
    }

    /**
     * Get the receipt file URL.
     */
    public function getFileUrlAttribute()
    {
        if ($this->file_path) {
            return asset('storage/' . $this->file_path);
        }
        return null;
    }

    /**
     * Check if receipt has been printed.
     */
    public function isPrinted(): bool
    {
        return $this->is_printed;
    }

    /**
     * Mark receipt as printed.
     */
    public function markAsPrinted(): void
    {
        $this->update([
            'is_printed' => true,
            'printed_at' => now(),
        ]);
    }

    /**
     * Get formatted receipt data for PDF generation.
     */
    public function getFormattedDataAttribute()
    {
        return [
            'receipt_number' => $this->receipt_number,
            'customer_name' => $this->customer_name,
            'customer_phone' => $this->customer_phone,
            'service_description' => $this->service_description,
            'amount' => number_format($this->amount, 2),
            'amount_words' => $this->convertAmountToWords($this->amount),
            'notes' => $this->notes,
            'issued_date' => $this->issued_at->format('d/m/Y'),
            'issued_time' => $this->issued_at->format('H:i'),
            'driver_name' => $this->transaction->driver->user->name,
            'device_name' => $this->transaction->device->name,
            'device_plate' => $this->transaction->device->plate_number,
        ];
    }

    /**
     * Convert amount to words (Swahili).
     */
    private function convertAmountToWords($amount): string
    {
        // Basic implementation - you can enhance this
        $formatter = new \NumberFormatter('sw', \NumberFormatter::SPELLOUT);
        $words = $formatter->format($amount);
        return ucfirst($words) . ' shilingi';
    }

    /**
     * Scope to get receipts for today.
     */
    public function scopeToday($query)
    {
        return $query->whereDate('issued_at', today());
    }

    /**
     * Scope to get receipts for this month.
     */
    public function scopeThisMonth($query)
    {
        return $query->whereMonth('issued_at', now()->month)
                    ->whereYear('issued_at', now()->year);
    }

    /**
     * Scope to get printed receipts.
     */
    public function scopePrinted($query)
    {
        return $query->where('is_printed', true);
    }

    /**
     * Scope to get unprinted receipts.
     */
    public function scopeUnprinted($query)
    {
        return $query->where('is_printed', false);
    }

    /**
     * Boot method to set default values.
     */
    protected static function boot()
    {
        parent::boot();

        static::creating(function ($receipt) {
            if (!$receipt->receipt_number) {
                $receipt->receipt_number = self::generateReceiptNumber();
            }
            
            if (!$receipt->issued_at) {
                $receipt->issued_at = now();
            }
        });
    }
}