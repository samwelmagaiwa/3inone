<?php

namespace App\Models;

use App\Models\Concerns\ScopedThroughDriver;
use Illuminate\Database\Eloquent\Model;

class DriverPredictionCache extends Model
{
    use ScopedThroughDriver;

    protected $fillable = [
        'driver_id',
        'start_date',
        'contract_end',
        'total_amount',
        'total_paid',
        'balance',
        'days_passed',
        'total_days',
        'on_track',
        'predicted_date',
        'estimated_delay_days',
        'model',
        'r2',
        'weekends_countable',
        'saturday_included',
        'sunday_included',
        'calculated_at',
    ];

    protected $casts = [
        'start_date' => 'date',
        'contract_end' => 'date',
        'predicted_date' => 'date',
        'on_track' => 'boolean',
        'weekends_countable' => 'boolean',
        'saturday_included' => 'boolean',
        'sunday_included' => 'boolean',
        'calculated_at' => 'datetime',
    ];
}
