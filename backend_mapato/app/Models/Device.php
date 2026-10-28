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

class Device extends Model
{
    use HasFactory, HasUuid, ScopedToAccount, HasBusinessOwner;
    use \App\Models\Concerns\BelongsToBranch;

    protected function branchService(): string
    {
        return 'transport';
    }

    /**
     * The business a new vehicle belongs to: its creator's, else its driver's, else the
     * business of whoever is signed in. A plate number is unique inside that business only.
     */
    protected function resolveBusinessOwnerId(): ?string
    {
        if ($this->created_by) {
            return BusinessOwner::ofUser((string) $this->created_by);
        }

        if ($this->driver_id) {
            $driver = Driver::withoutAccountScope()->find($this->driver_id);
            if ($driver) {
                return $driver->owner_id ?: BusinessOwner::ofUser((string) $driver->user_id);
            }
        }

        return TenantContext::writeOwner();
    }

    /**
     * A vehicle belongs to the account that created it, or -- for vehicles
     * that predate created_by -- the account of the driver it is assigned to.
     * A driver sees only the vehicle they drive.
     */
    public function constrainToAccount(Builder $query, User $user): void
    {
        $table = $this->getTable();
        $drivers = Driver::query()->select('drivers.id')->toBase();

        if ($user->isPortalUser()) {
            $query->where(function (Builder $scope) use ($table, $user, $drivers) {
                $scope->whereIn("{$table}.driver_id", $drivers);
                if ($user->device_id) {
                    $scope->orWhere("{$table}.id", $user->device_id);
                }
            });

            return;
        }

        // Looking at one branch: only its vehicles.
        if (($branch = \App\Support\Tenancy\ServiceBranch::selected('transport', $user)) !== null) {
            $query->where("{$table}.branch_id", $branch);
        }

        $query->where(function (Builder $scope) use ($table, $user, $drivers) {
            $scope->whereIn("{$table}.created_by", $user->accountMemberIds())
                ->orWhereIn("{$table}.driver_id", $drivers);
        });
    }

    /**
     * The attributes that are mass assignable.
     */
    protected $fillable = [
        'branch_id',
        'driver_id',
        'created_by',
        'name',
        'type',
        'plate_number',
        'description',
        'is_active',
        'purchase_date',
        'purchase_price',
        'insurance_expiry',
        'last_service_date',
    ];

    /**
     * The attributes that should be cast.
     */
    protected $casts = [
        'is_active' => 'boolean',
        'purchase_date' => 'date',
        'purchase_price' => 'decimal:2',
        'insurance_expiry' => 'date',
        'last_service_date' => 'date',
    ];

    /**
     * Device types
     */
    const TYPES = [
        'bajaji' => 'Bajaji',
        'pikipiki' => 'Pikipiki',
        'gari' => 'Gari',
    ];

    /**
     * Get the driver that owns the device.
     */
    public function driver()
    {
        return $this->belongsTo(Driver::class);
    }

    /**
     * Get the transactions for the device.
     */
    public function transactions()
    {
        return $this->hasMany(Transaction::class);
    }

    /**
     * Get completed transactions for the device.
     */
    public function completedTransactions()
    {
        return $this->transactions()->where('status', 'completed');
    }

    /**
     * Get income transactions for the device.
     */
    public function incomeTransactions()
    {
        return $this->transactions()->where('type', 'income')->where('status', 'completed');
    }

    /**
     * Get expense transactions for the device.
     */
    public function expenseTransactions()
    {
        return $this->transactions()->where('type', 'expense')->where('status', 'completed');
    }

    /**
     * Calculate total revenue for the device.
     */
    public function getTotalRevenueAttribute()
    {
        return $this->incomeTransactions()->sum('amount');
    }

    /**
     * Calculate total expenses for the device.
     */
    public function getTotalExpensesAttribute()
    {
        return $this->expenseTransactions()->sum('amount');
    }

    /**
     * Calculate net profit for the device.
     */
    public function getNetProfitAttribute()
    {
        return $this->total_revenue - $this->total_expenses;
    }

    /**
     * Get today's revenue for the device.
     */
    public function getTodayRevenueAttribute()
    {
        return $this->incomeTransactions()
                   ->whereDate('created_at', today())
                   ->sum('amount');
    }

    /**
     * Get this month's revenue for the device.
     */
    public function getThisMonthRevenueAttribute()
    {
        return $this->incomeTransactions()
                   ->whereMonth('created_at', now()->month)
                   ->whereYear('created_at', now()->year)
                   ->sum('amount');
    }

    /**
     * Get the device type display name.
     */
    public function getTypeDisplayAttribute()
    {
        return self::TYPES[$this->type] ?? $this->type;
    }

    /**
     * Check if insurance is expired or expiring soon.
     */
    public function isInsuranceExpiringSoon($days = 30): bool
    {
        return $this->insurance_expiry && $this->insurance_expiry->diffInDays(now()) <= $days;
    }

    /**
     * Check if insurance is expired.
     */
    public function isInsuranceExpired(): bool
    {
        return $this->insurance_expiry && $this->insurance_expiry->isPast();
    }

    /**
     * Check if service is due.
     */
    public function isServiceDue($months = 6): bool
    {
        if (!$this->last_service_date) {
            return true;
        }
        
        return $this->last_service_date->addMonths($months)->isPast();
    }

    /**
     * Scope to get active devices.
     */
    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }

    /**
     * Scope to get devices by type.
     */
    public function scopeOfType($query, $type)
    {
        return $query->where('type', $type);
    }

    /**
     * Scope to get devices with expiring insurance.
     */
    public function scopeWithExpiringInsurance($query, $days = 30)
    {
        return $query->whereDate('insurance_expiry', '<=', now()->addDays($days));
    }

    /**
     * Scope to get devices needing service.
     */
    public function scopeNeedingService($query, $months = 6)
    {
        return $query->where(function ($q) use ($months) {
            $q->whereNull('last_service_date')
              ->orWhereDate('last_service_date', '<=', now()->subMonths($months));
        });
    }
}