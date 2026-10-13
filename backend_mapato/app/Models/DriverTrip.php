<?php

namespace App\Models;

use App\Models\Concerns\ScopedThroughDriver;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DriverTrip extends Model
{
    use HasFactory, ScopedThroughDriver;

    protected $fillable = [
        'driver_id',
        'trip_date',
        'start_time',
        'end_time',
        'pickup_location',
        'destination',
        'distance_km',
        'fare_amount',
        'commission_amount',
        'driver_earnings',
        'trip_status',
        'payment_status',
        'rating',
        'trip_notes',
        'trip_metadata',
    ];

    protected $casts = [
        'trip_date' => 'date',
        'start_time' => 'datetime:H:i',
        'end_time' => 'datetime:H:i',
        'distance_km' => 'decimal:2',
        'fare_amount' => 'decimal:2',
        'commission_amount' => 'decimal:2',
        'driver_earnings' => 'decimal:2',
        'rating' => 'integer',
        'trip_metadata' => 'array',
    ];

    /**
     * Get the driver that owns the trip
     */
    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * Scope for completed trips
     */
    public function scopeCompleted($query)
    {
        return $query->where('trip_status', 'completed');
    }

    /**
     * Scope for trips by payment status
     */
    public function scopeByPaymentStatus($query, $status)
    {
        return $query->where('payment_status', $status);
    }

    /**
     * Scope for trips within date range
     */
    public function scopeDateRange($query, $startDate, $endDate)
    {
        return $query->whereBetween('trip_date', [$startDate, $endDate]);
    }
}
