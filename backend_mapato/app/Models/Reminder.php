<?php

namespace App\Models;

use App\Models\Concerns\ScopedThroughDriver;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use App\Traits\HasUuid;

class Reminder extends Model
{
    use HasFactory, HasUuid, ScopedThroughDriver;

    /**
     * The attributes that are mass assignable.
     */
    protected $fillable = [
        'driver_id',
        'device_id',
        'title',
        'message',
        'reminder_type',
        'reminder_date',
        'reminder_time',
        'is_recurring',
        'recurrence_pattern',
        'status',
        'is_sent',
        'sent_at',
        'priority',
    ];

    /**
     * The attributes that should be cast.
     */
    protected $casts = [
        'reminder_date' => 'date',
        'reminder_time' => 'datetime',
        'sent_at' => 'datetime',
        'is_recurring' => 'boolean',
        'is_sent' => 'boolean',
    ];

    /**
     * Reminder types
     */
    const TYPES = [
        'license_renewal' => 'Upyaji wa Leseni',
        'insurance_renewal' => 'Upyaji wa Bima',
        'service_maintenance' => 'Huduma na Matengenezo',
        'payment_due' => 'Malipo Yanayodaiwa',
        'fuel_reminder' => 'Kikumbusho cha Mafuta',
        'custom' => 'Maalum',
    ];

    /**
     * Reminder statuses
     */
    const STATUSES = [
        'active' => 'Inatumika',
        'completed' => 'Imekamilika',
        'cancelled' => 'Imeghairiwa',
        'expired' => 'Imeisha',
    ];

    /**
     * Priority levels
     */
    const PRIORITIES = [
        'low' => 'Chini',
        'medium' => 'Wastani',
        'high' => 'Juu',
        'urgent' => 'Dharura',
    ];

    /**
     * Recurrence patterns
     */
    const RECURRENCE_PATTERNS = [
        'daily' => 'Kila Siku',
        'weekly' => 'Kila Wiki',
        'monthly' => 'Kila Mwezi',
        'quarterly' => 'Kila Robo Mwaka',
        'yearly' => 'Kila Mwaka',
    ];

    /**
     * Get the driver that owns the reminder.
     */
    public function driver()
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * Get the device associated with the reminder.
     */
    public function device()
    {
        return $this->belongsTo(Device::class);
    }

    /**
     * Get the reminder type display name.
     */
    public function getTypeDisplayAttribute()
    {
        return self::TYPES[$this->reminder_type] ?? $this->reminder_type;
    }

    /**
     * Get the status display name.
     */
    public function getStatusDisplayAttribute()
    {
        return self::STATUSES[$this->status] ?? $this->status;
    }

    /**
     * Get the priority display name.
     */
    public function getPriorityDisplayAttribute()
    {
        return self::PRIORITIES[$this->priority] ?? $this->priority;
    }

    /**
     * Get the recurrence pattern display name.
     */
    public function getRecurrencePatternDisplayAttribute()
    {
        return self::RECURRENCE_PATTERNS[$this->recurrence_pattern] ?? $this->recurrence_pattern;
    }

    /**
     * Check if reminder is active.
     */
    public function isActive(): bool
    {
        return $this->status === 'active';
    }

    /**
     * Check if reminder is overdue.
     */
    public function isOverdue(): bool
    {
        return $this->isActive() && $this->reminder_time->isPast();
    }

    /**
     * Check if reminder is due today.
     */
    public function isDueToday(): bool
    {
        return $this->isActive() && $this->reminder_date->isToday();
    }

    /**
     * Check if reminder is due soon (within specified days).
     */
    public function isDueSoon($days = 3): bool
    {
        return $this->isActive() && $this->reminder_date->diffInDays(now()) <= $days;
    }

    /**
     * Mark reminder as sent.
     */
    public function markAsSent(): void
    {
        $this->update([
            'is_sent' => true,
            'sent_at' => now(),
        ]);
    }

    /**
     * Mark reminder as completed.
     */
    public function markAsCompleted(): void
    {
        $this->update(['status' => 'completed']);
    }

    /**
     * Cancel reminder.
     */
    public function cancel(): void
    {
        $this->update(['status' => 'cancelled']);
    }

    /**
     * Create next occurrence for recurring reminders.
     */
    public function createNextOccurrence(): ?self
    {
        if (!$this->is_recurring || !$this->recurrence_pattern) {
            return null;
        }

        $nextDate = match($this->recurrence_pattern) {
            'daily' => $this->reminder_date->addDay(),
            'weekly' => $this->reminder_date->addWeek(),
            'monthly' => $this->reminder_date->addMonth(),
            'quarterly' => $this->reminder_date->addMonths(3),
            'yearly' => $this->reminder_date->addYear(),
            default => null,
        };

        if (!$nextDate) {
            return null;
        }

        return self::create([
            'driver_id' => $this->driver_id,
            'device_id' => $this->device_id,
            'title' => $this->title,
            'message' => $this->message,
            'reminder_type' => $this->reminder_type,
            'reminder_date' => $nextDate,
            'reminder_time' => $nextDate->setTimeFrom($this->reminder_time),
            'is_recurring' => true,
            'recurrence_pattern' => $this->recurrence_pattern,
            'status' => 'active',
            'priority' => $this->priority,
        ]);
    }

    /**
     * Scope to get active reminders.
     */
    public function scopeActive($query)
    {
        return $query->where('status', 'active');
    }

    /**
     * Scope to get overdue reminders.
     */
    public function scopeOverdue($query)
    {
        return $query->active()->where('reminder_time', '<', now());
    }

    /**
     * Scope to get reminders due today.
     */
    public function scopeDueToday($query)
    {
        return $query->active()->whereDate('reminder_date', today());
    }

    /**
     * Scope to get reminders due soon.
     */
    public function scopeDueSoon($query, $days = 3)
    {
        return $query->active()->whereDate('reminder_date', '<=', now()->addDays($days));
    }

    /**
     * Scope to get unsent reminders.
     */
    public function scopeUnsent($query)
    {
        return $query->where('is_sent', false);
    }

    /**
     * Scope to get reminders by type.
     */
    public function scopeOfType($query, $type)
    {
        return $query->where('reminder_type', $type);
    }

    /**
     * Scope to get reminders by priority.
     */
    public function scopeByPriority($query, $priority)
    {
        return $query->where('priority', $priority);
    }

    /**
     * Boot method to set default values.
     */
    protected static function boot()
    {
        parent::boot();

        static::creating(function ($reminder) {
            if (!$reminder->status) {
                $reminder->status = 'active';
            }
            
            if (!$reminder->priority) {
                $reminder->priority = 'medium';
            }
        });
    }
}