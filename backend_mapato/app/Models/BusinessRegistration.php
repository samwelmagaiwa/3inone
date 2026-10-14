<?php

namespace App\Models;

use App\Traits\HasUuid;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * A business owner's self-registration, waiting for a super admin to review it
 * and assign services. The owner's login is the linked users row (inactive
 * until approval).
 */
class BusinessRegistration extends Model
{
    use HasFactory, HasUuid;

    public const PENDING = 'pending';
    public const APPROVED = 'approved';
    public const REJECTED = 'rejected';

    protected $fillable = [
        'user_id',
        'business_name',
        'requested_services',
        'requested_plan',
        'requested_months',
        'inventory_type',
        'region',
        'district',
        'address',
        'id_number',
        'notes',
        'status',
        'reviewed_by',
        'reviewed_at',
        'rejection_reason',
    ];

    protected $casts = [
        'requested_services' => 'array',
        'reviewed_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function reviewer()
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    public function isPending(): bool
    {
        return $this->status === self::PENDING;
    }
}
