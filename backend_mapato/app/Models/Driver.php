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

class Driver extends Model
{
    use HasFactory, HasUuid, ScopedToAccount, HasBusinessOwner;

    /**
     * The business a new driver belongs to: the business of the login they were given (the
     * creator chain), else the signed-in user's. A licence number is unique inside it only.
     */
    protected function resolveBusinessOwnerId(): ?string
    {
        return $this->user_id
            ? BusinessOwner::ofUser((string) $this->user_id)
            : TenantContext::writeOwner();
    }

    /**
     * A driver belongs to the account of whoever created the driver's login.
     * The driver themself only ever sees their own row.
     */
    public function constrainToAccount(Builder $query, User $user): void
    {
        $table = $this->getTable();

        if ($user->isPortalUser()) {
            $query->where("{$table}.user_id", $user->id);

            return;
        }

        $query->where(function (Builder $scope) use ($table, $user) {
            $scope->where("{$table}.user_id", $user->id)
                ->orWhereIn(
                    "{$table}.user_id",
                    User::query()->select('id')->whereIn('created_by', $user->accountMemberIds())
                );
        });
    }

    /**
     * The attributes that are mass assignable.
     */
    protected $fillable = [
        'user_id',
        'license_number',
        'license_expiry',
        'address',
        'emergency_contact',
        'is_active',
        'profile_image',
        'date_of_birth',
        'national_id',
    ];

    /**
     * The attributes that should be cast.
     */
    protected $casts = [
        'license_expiry' => 'date',
        'date_of_birth' => 'date',
        'is_active' => 'boolean',
    ];

    /**
     * Get the user that owns the driver profile.
     */
    public function user()
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Get the devices for the driver.
     */
    public function devices()
    {
        return $this->hasMany(Device::class);
    }

    /**
     * Debt records associated with this driver
     */
    public function debtRecords()
    {
        return $this->hasMany(DebtRecord::class);
    }

    /**
     * Get the transactions for the driver.
     */
    public function transactions()
    {
        return $this->hasMany(Transaction::class);
    }

    /**
     * Get the reminders for the driver.
     */
    public function reminders()
    {
        return $this->hasMany(Reminder::class);
    }

    /**
     * Get the communications for the driver.
     */
    public function communications()
    {
        return $this->hasMany(Communication::class);
    }

    /**
     * Get the driver agreements.
     */
    public function driverAgreements()
    {
        return $this->hasMany(DriverAgreement::class);
    }

    /**
     * Get the active driver agreement.
     */
    public function activeAgreement()
    {
        return $this->hasOne(DriverAgreement::class)->where('status', 'active');
    }

    /**
     * Get the driver trips.
     */
    public function trips()
    {
        return $this->hasMany(DriverTrip::class);
    }

    /**
     * Get the driver performance metrics.
     */
    public function performanceMetrics()
    {
        return $this->hasOne(DriverPerformanceMetric::class);
    }

    /**
     * Get the driver status history.
     */
    public function statusHistory()
    {
        return $this->hasMany(DriverStatusHistory::class);
    }

    /**
     * Get the payments made by this driver.
     */
    public function payments()
    {
        return $this->hasMany(Payment::class);
    }

    /**
     * Get active devices for the driver.
     */
    public function activeDevices()
    {
        return $this->devices()->where('is_active', true);
    }

    /**
     * Get completed transactions for the driver.
     */
    public function completedTransactions()
    {
        return $this->transactions()->where('status', 'completed');
    }

    /**
     * Get income transactions for the driver.
     */
    public function incomeTransactions()
    {
        return $this->transactions()->where('type', 'income')->where('status', 'completed');
    }

    /**
     * Get expense transactions for the driver.
     */
    public function expenseTransactions()
    {
        return $this->transactions()->where('type', 'expense')->where('status', 'completed');
    }

    /**
     * Calculate total revenue for the driver.
     */
    public function getTotalRevenueAttribute()
    {
        return $this->incomeTransactions()->sum('amount');
    }

    /**
     * Calculate total expenses for the driver.
     */
    public function getTotalExpensesAttribute()
    {
        return $this->expenseTransactions()->sum('amount');
    }

    /**
     * Calculate net profit for the driver.
     */
    public function getNetProfitAttribute()
    {
        return $this->total_revenue - $this->total_expenses;
    }

    /**
     * Check if license is expired or expiring soon.
     */
    public function isLicenseExpiringSoon($days = 30): bool
    {
        return $this->license_expiry && $this->license_expiry->diffInDays(now()) <= $days;
    }

    /**
     * Check if license is expired.
     */
    public function isLicenseExpired(): bool
    {
        return $this->license_expiry && $this->license_expiry->isPast();
    }

    /**
     * Scope to get active drivers.
     */
    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }

    /**
     * Scope to get drivers with expiring licenses.
     */
    public function scopeWithExpiringLicenses($query, $days = 30)
    {
        return $query->whereDate('license_expiry', '<=', now()->addDays($days));
    }

    /*
     |--------------------------------------------------------------------------
     | Convenience accessors to surface related user/device fields
     |--------------------------------------------------------------------------
     */

    public function getNameAttribute()
    {
        return $this->user->name ?? null;
    }

    public function getEmailAttribute()
    {
        return $this->user->email ?? null;
    }

    public function getPhoneAttribute()
    {
        return $this->user->phone_number ?? null;
    }

    public function getVehicleNumberAttribute()
    {
        $device = $this->activeDevices()->latest('updated_at')->first()
            ?? $this->devices()->latest('updated_at')->first()
            ?? $this->user->assignedDevice;
        return $device?->plate_number;
    }

    public function getVehicleTypeAttribute()
    {
        $device = $this->activeDevices()->latest('updated_at')->first()
            ?? $this->devices()->latest('updated_at')->first()
            ?? $this->user->assignedDevice;
        return $device?->type;
    }

    public function getStatusAttribute()
    {
        return $this->is_active ? 'active' : 'inactive';
    }
}
