<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DriverPerformanceMetric extends Model
{
    use HasFactory, \App\Models\Concerns\ScopedThroughDriver;

    protected $fillable = [
        'driver_id',
        'payment_consistency_rating',
        'average_payment_delay_days',
        'payment_punctuality_percentage',
        'total_amount_submitted',
        'total_outstanding_debt',
        'total_debts_recorded',
        'total_paid_amount',
        'debt_to_earnings_ratio',
        'total_completed_trips',
        'total_cancelled_trips',
        'trip_completion_rate',
        'average_trip_rating',
        'total_ratings_count',
        'first_trip_date',
        'last_trip_date',
        'last_payment_date',
        'days_since_last_payment',
        'consecutive_late_payments',
        'consecutive_ontime_payments',
        'overall_performance_score',
        'performance_grade',
        'is_at_risk',
        'performance_notes',
        'last_calculated_at',
        'calculation_metadata',
    ];

    protected $casts = [
        'payment_punctuality_percentage' => 'decimal:2',
        'total_amount_submitted' => 'decimal:2',
        'total_outstanding_debt' => 'decimal:2',
        'total_debts_recorded' => 'decimal:2',
        'total_paid_amount' => 'decimal:2',
        'debt_to_earnings_ratio' => 'decimal:2',
        'trip_completion_rate' => 'decimal:2',
        'average_trip_rating' => 'decimal:2',
        'overall_performance_score' => 'decimal:2',
        'is_at_risk' => 'boolean',
        'first_trip_date' => 'date',
        'last_trip_date' => 'date',
        'last_payment_date' => 'date',
        'last_calculated_at' => 'datetime',
        'calculation_metadata' => 'array',
    ];

    /**
     * Get the driver that owns the performance metrics
     */
    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * Scope for at-risk drivers
     */
    public function scopeAtRisk($query)
    {
        return $query->where('is_at_risk', true);
    }

    /**
     * Scope by performance grade
     */
    public function scopeByGrade($query, $grade)
    {
        return $query->where('performance_grade', $grade);
    }
}
