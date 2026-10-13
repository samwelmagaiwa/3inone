<?php

namespace App\Models;

use App\Models\Concerns\ScopedThroughDriver;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;
use Carbon\Carbon;

class DriverAgreement extends Model
{
    use HasFactory, ScopedThroughDriver;

    protected $fillable = [
        'driver_id',
        'agreement_type',
        'start_date',
        'end_date',
        'mwaka_atamaliza',
        'kiasi_cha_makubaliano',
        'faida_jumla',
        'wikendi_zinahesabika',
        'jumamosi',
        'jumapili',
        'payment_frequencies',
        'status',
        'created_by',
        // Contract-specific fields
        'vehicle_payment',
        'daily_target',
        'contract_period_months',
        // Daily work fields
        'salary_amount',
        'bonus_amount',
        // Additional fields
        'notes',
    ];

    protected $casts = [
        'id' => 'string',
        'driver_id' => 'string',
        'created_by' => 'string',
        'start_date' => 'date',
        'end_date' => 'date',
        'kiasi_cha_makubaliano' => 'decimal:2',
        'faida_jumla' => 'decimal:2',
        'wikendi_zinahesabika' => 'boolean',
        'jumamosi' => 'boolean',
        'jumapili' => 'boolean',
        'payment_frequencies' => 'array',
        // Contract-specific fields
        'vehicle_payment' => 'decimal:2',
        'daily_target' => 'decimal:2',
        'contract_period_months' => 'integer',
        // Daily work fields
        'salary_amount' => 'decimal:2',
        'bonus_amount' => 'decimal:2',
    ];

    public $incrementing = false;
    protected $keyType = 'string';

    protected static function boot()
    {
        parent::boot();
        static::creating(function ($model) {
            if (!$model->id) {
                $model->id = Str::uuid();
            }
            // Auto-calculate faida_jumla for 'kwa_mkataba' agreements
            if ($model->agreement_type === 'kwa_mkataba' && $model->start_date && $model->end_date) {
                $model->calculateFaidaJumla();
                $model->calculateContractPeriodMonths();
            }
        });
        
        static::updating(function ($model) {
            // Recalculate values if relevant fields changed for 'kwa_mkataba'
            if ($model->agreement_type === 'kwa_mkataba') {
                $relevantFieldsChanged = $model->isDirty(['start_date', 'end_date', 'kiasi_cha_makubaliano']);
                if ($relevantFieldsChanged && $model->start_date && $model->end_date) {
                    $model->calculateFaidaJumla();
                    $model->calculateContractPeriodMonths();
                }
            } else {
                // Not a contract-based agreement: ensure months is null
                if ($model->isDirty(['agreement_type'])) {
                    $model->contract_period_months = null;
                }
            }
        });

        // Trigger prediction refresh when agreements change
        static::created(function ($agreement) {
            \App\Jobs\PredictDriverCompletionJob::dispatch($agreement->driver_id);
        });
        static::updated(function ($agreement) {
            \App\Jobs\PredictDriverCompletionJob::dispatch($agreement->driver_id);
        });
        static::deleted(function ($agreement) {
            \App\Jobs\PredictDriverCompletionJob::dispatch($agreement->driver_id);
        });
    }

    /**
     * Calculate total profit (faida jumla) for contract-based agreements
     */
    public function calculateFaidaJumla()
    {
        if ($this->agreement_type === 'kwa_mkataba' && $this->start_date && $this->end_date) {
            $startDate = Carbon::parse($this->start_date);
            $endDate = Carbon::parse($this->end_date);
            $totalDays = $startDate->diffInDays($endDate) + 1;
            
            // If weekends don't count, subtract weekend days
            if (!$this->wikendi_zinahesabika) {
                $weekendDays = 0;
                $current = $startDate->copy();
                
                while ($current->lte($endDate)) {
                    $isSaturday = $current->isSaturday() && !$this->jumamosi;
                    $isSunday = $current->isSunday() && !$this->jumapili;
                    
                    if ($isSaturday || $isSunday) {
                        $weekendDays++;
                    }
                    $current->addDay();
                }
                $totalDays -= $weekendDays;
            }
            
            $this->faida_jumla = $totalDays * $this->kiasi_cha_makubaliano;
        }
    }

    /**
     * Calculate and set contract period in months based on start and end dates.
     * Counts any partial month as a full month.
     */
    public function calculateContractPeriodMonths(): void
    {
        if ($this->start_date && $this->end_date) {
            $start = Carbon::parse($this->start_date);
            $end = Carbon::parse($this->end_date);

            // Base difference in whole months (floor)
            $months = $start->diffInMonths($end);
            // If there are remaining days beyond full months, count as an extra month
            if ($start->copy()->addMonths($months)->lt($end)) {
                $months++;
            }
            $this->contract_period_months = max(1, (int) $months);
        } else {
            $this->contract_period_months = null;
        }
    }

    /**
     * Get the driver that owns this agreement
     */
    public function driver(): BelongsTo
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * Get the user who created this agreement
     */
    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    /**
     * Scope for active agreements
     */
    public function scopeActive($query)
    {
        return $query->where('status', 'active');
    }

    /**
     * Scope for contract-based agreements
     */
    public function scopeKwaMkataba($query)
    {
        return $query->where('agreement_type', 'kwa_mkataba');
    }

    /**
     * Scope for day-wage agreements
     */
    public function scopeDeiWaka($query)
    {
        return $query->where('agreement_type', 'dei_waka');
    }
}
