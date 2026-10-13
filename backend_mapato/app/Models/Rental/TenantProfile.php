<?php

namespace App\Models\Rental;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use App\Traits\HasUuid;
use App\Models\User;

class TenantProfile extends Model
{
    use HasFactory, HasUuid;

    use \App\Models\Concerns\ScopedToAccount;

    /** Fail-closed account scope: the tenants the account deals with (see App\Support\Tenancy\RentalAccess). */
    public function constrainToAccount(\Illuminate\Database\Eloquent\Builder $query, \App\Models\User $user): void
    {
        $query->whereIn($this->qualifyColumn('user_id'), \App\Support\Tenancy\RentalAccess::tenantUserIds($user));
    }

    protected $table = 'rental_tenant_profiles';

    /**
     * What the API shows is a short-lived signed link, never the stored path. (Writing
     * photo_url is unaffected: it still stores the path.)
     */
    public function getPhotoUrlAttribute($value): ?string
    {
        return \App\Support\PrivateFile::url($value);
    }

    protected $fillable = [
        'user_id',
        'gender',
        'dob',
        'id_number',
        'id_state',
        'id_expiration',
        'occupation',
        'emergency_contact_name',
        'emergency_contact_phone',
        'employment',
        'history',
        'occupants',
        'pets',
        'photo_url',
        'contract_url',
        'notes',
    ];

    protected $casts = [
        'dob' => 'date',
        'id_expiration' => 'date',
        'employment' => 'array',
        'history' => 'array',
        'occupants' => 'array',
        'pets' => 'array',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
