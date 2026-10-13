<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DriverStatusHistory extends Model
{
    use HasFactory, \App\Models\Concerns\ScopedThroughDriver;

    protected $fillable = [
        'driver_id',
        'previous_status',
        'new_status',
        'changed_by',
        'reason',
        'additional_data',
        'changed_at',
    ];

    protected $casts = [
        'additional_data' => 'array',
        'changed_at' => 'datetime',
    ];

    /**
     * Get the driver that owns the status history
     */
    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * Get the user who made the status change
     */
    public function changedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'changed_by');
    }

    /**
     * Scope for status changes by driver
     */
    public function scopeByDriver($query, $driverId)
    {
        return $query->where('driver_id', $driverId);
    }

    /**
     * Scope for status changes within date range
     */
    public function scopeDateRange($query, $startDate, $endDate)
    {
        return $query->whereBetween('changed_at', [$startDate, $endDate]);
    }
}
