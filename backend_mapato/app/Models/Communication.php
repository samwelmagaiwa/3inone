<?php

namespace App\Models;

use App\Models\Concerns\ScopedThroughDriver;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Carbon\Carbon;

class Communication extends Model
{
    use HasFactory, ScopedThroughDriver;

    /**
     * The attributes that are mass assignable.
     */
    protected $fillable = [
        'driver_id',
        'driver_name',
        'message_date',
        'message_content',
        'response',
        'mode',
    ];

    /**
     * The attributes that should be cast.
     */
    protected $casts = [
        'message_date' => 'datetime',
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
    ];

    /**
     * Communication modes enumeration
     */
    const MODES = [
        'sms' => 'SMS',
        'call' => 'Simu',
        'whatsapp' => 'WhatsApp',
        'system_note' => 'Kumbuka ya Mfumo'
    ];

    /**
     * Get the driver that owns the communication.
     */
    public function driver()
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * Check if communication has a response
     */
    public function getHasResponseAttribute(): bool
    {
        return !empty($this->response);
    }

    /**
     * Get truncated message content for display
     */
    public function getTruncatedContentAttribute(): string
    {
        return strlen($this->message_content) > 50 
            ? substr($this->message_content, 0, 50) . '...' 
            : $this->message_content;
    }

    /**
     * Get truncated response for display
     */
    public function getTruncatedResponseAttribute(): string
    {
        if (!$this->has_response) {
            return 'Hakuna jibu';
        }
        
        return strlen($this->response) > 50 
            ? substr($this->response, 0, 50) . '...' 
            : $this->response;
    }

    /**
     * Get formatted message date
     */
    public function getFormattedMessageDateAttribute(): string
    {
        return $this->message_date->format('d/m/Y');
    }

    /**
     * Get formatted date and time
     */
    public function getFormattedDateTimeAttribute(): string
    {
        return $this->message_date->format('d/m/Y H:i');
    }

    /**
     * Get display name for communication mode
     */
    public function getModeDisplayNameAttribute(): string
    {
        return self::MODES[$this->mode] ?? ucfirst($this->mode);
    }

    /**
     * Get icon for communication mode
     */
    public function getModeIconAttribute(): string
    {
        switch ($this->mode) {
            case 'sms':
                return '📱';
            case 'call':
                return '📞';
            case 'whatsapp':
                return '📲';
            case 'system_note':
                return '📝';
            default:
                return '💬';
        }
    }

    /**
     * Scope to get unanswered communications
     */
    public function scopeUnanswered($query)
    {
        return $query->whereNull('response')->orWhere('response', '');
    }

    /**
     * Scope to get answered communications
     */
    public function scopeAnswered($query)
    {
        return $query->whereNotNull('response')->where('response', '!=', '');
    }

    /**
     * Scope to get recent communications (within specified days)
     */
    public function scopeRecent($query, $days = 7)
    {
        return $query->where('message_date', '>=', Carbon::now()->subDays($days));
    }

    /**
     * Scope to filter by communication mode
     */
    public function scopeByMode($query, $mode)
    {
        return $query->where('mode', $mode);
    }

    /**
     * Scope to search by content or driver name
     */
    public function scopeSearch($query, $search)
    {
        return $query->where(function ($q) use ($search) {
            $q->where('driver_name', 'like', "%{$search}%")
              ->orWhere('message_content', 'like', "%{$search}%")
              ->orWhere('response', 'like', "%{$search}%");
        });
    }

    /**
     * Get communication summary statistics
     */
    public static function getSummaryStats()
    {
        $total = self::count();
        $unanswered = self::unanswered()->count();
        $recent = self::recent()->count();
        
        $byMode = [];
        foreach (array_keys(self::MODES) as $mode) {
            $byMode[$mode] = self::byMode($mode)->count();
        }
        
        $lastCommunication = self::latest('message_date')->first();
        
        return [
            'total_communications' => $total,
            'unanswered_communications' => $unanswered,
            'recent_communications' => $recent,
            'communications_by_mode' => $byMode,
            'last_communication_date' => $lastCommunication ? $lastCommunication->message_date : null,
            'response_rate' => $total > 0 ? round((($total - $unanswered) / $total) * 100) : 0
        ];
    }
}