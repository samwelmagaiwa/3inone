<?php

namespace App\Models;

use App\Models\Concerns\ScopedToAccount;
use App\Support\Tenancy\BusinessOwner;
use App\Support\Tenancy\TenantContext;
use App\Traits\HasUuid;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * A business: the tenant that owns everything the tenancy contract isolates.
 *
 * `owner_id` is the account head's user id -- the value TenantContext calls "the business" and
 * inventory stores in its own `owner_id` -- so this record carries the business's identity (name,
 * address, TIN, logo: what a receipt or a text message says) and its billing (plan, valid_until)
 * without changing how any data is scoped.
 *
 * Scoped to the signed-in user's own business like every other Transport/Rental model; a super
 * admin sees all of them. Code that already holds a trusted owner id (a receipt, a background
 * job) goes through forOwnerId(), which does not depend on who is signed in.
 */
class Business extends Model
{
    use HasFactory, HasUuid, ScopedToAccount;

    /** Fields the owner may edit about their own business. */
    public const PROFILE_FIELDS = ['name', 'address', 'tin', 'phone', 'email', 'inventory_type'];

    protected $fillable = [
        'owner_id', 'name', 'address', 'tin', 'phone', 'email', 'logo_path', 'plan', 'valid_until', 'inventory_type',
    ];

    protected $casts = [
        'valid_until' => 'datetime',
    ];

    public function constrainToAccount(Builder $query, User $user): void
    {
        $query->where($this->getTable() . '.owner_id', $user->accountHeadId());
    }

    /**
     * The kinds of inventory business an owner can say they run (config/inventory_types.php).
     *
     * @return array<int, string>
     */
    public static function inventoryTypes(): array
    {
        return array_values((array) config('inventory_types.types', []));
    }

    public function owner()
    {
        return $this->belongsTo(User::class, 'owner_id');
    }

    // ------------------------------------------------------------------ finding it

    /** The business owned by this account head, or null. Independent of who is signed in. */
    public static function forOwnerId(?string $ownerId): ?self
    {
        if ($ownerId === null || $ownerId === '') {
            return null;
        }

        return static::withoutAccountScope()->where('owner_id', $ownerId)->first();
    }

    /**
     * The business a user works for (their account head's), creating its record if a head
     * somehow has none yet. Null for someone who belongs to no business (a super admin).
     */
    public static function forUser(?User $user): ?self
    {
        if ($user === null || $user->seesAllAccounts()) {
            return null;
        }

        $headId = $user->accountHeadId();

        return static::forOwnerId($headId) ?? static::ensureFor(User::query()->find($headId));
    }

    /**
     * Make sure an account head has a business record. A head is an admin / administrator /
     * landlord; anyone else has none and gets null. Safe to call repeatedly and concurrently.
     */
    public static function ensureFor(?User $head, array $attributes = []): ?self
    {
        if ($head === null || !in_array(strtolower((string) $head->role), User::ACCOUNT_HEAD_ROLES, true)) {
            return null;
        }

        $existing = static::forOwnerId($head->id);
        if ($existing !== null) {
            return $existing;
        }

        try {
            return static::withoutAccountScope()->create(array_merge([
                'owner_id' => $head->id,
                'name' => trim((string) $head->name) ?: 'Business',
                'phone' => $head->phone_number,
                'email' => $head->email,
                'plan' => config('billing.default_plan', 'free'),
            ], $attributes));
        } catch (\Illuminate\Database\QueryException $e) {
            // Lost a race with another request creating the same record: use theirs.
            $raced = static::forOwnerId($head->id);
            if ($raced === null) {
                throw $e;
            }

            return $raced;
        }
    }

    /**
     * Put what an owner typed on the registration form onto their business record.
     * Used when they register and when they re-apply after a rejection.
     */
    public static function syncFromRegistration(BusinessRegistration $registration): ?self
    {
        $owner = $registration->user ?? User::query()->find($registration->user_id);
        $business = static::ensureFor($owner);
        if ($business === null) {
            return null;
        }

        $address = trim(implode(', ', array_filter(
            [$registration->address, $registration->district, $registration->region],
            fn ($part) => $part !== null && trim((string) $part) !== ''
        )));

        $business->forceFill([
            'name' => trim((string) $registration->business_name) ?: $business->name,
            'address' => $address !== '' ? mb_substr($address, 0, 500) : null,
            'phone' => $owner->phone_number,
            'email' => $owner->email,
            // What kind of inventory business they said they run (only when they said).
            'inventory_type' => $registration->inventory_type ?: $business->inventory_type,
        ])->save();

        return $business;
    }

    // ------------------------------------------------------------------ identity

    /** Public address of the logo, or null. Logos are not sensitive: they are printed on receipts. */
    public function logoUrl(): ?string
    {
        return $this->logo_path ? url('api/files/public/' . ltrim($this->logo_path, '/')) : null;
    }

    /**
     * What a receipt or a message says about the business. Every key is always present, so a
     * template never has to check.
     *
     * @return array{name: string, address: string, phone: string, tin: string, email: string, logo_url: ?string}
     */
    public function identity(): array
    {
        return [
            'name' => (string) $this->name,
            'address' => (string) $this->address,
            'phone' => (string) $this->phone,
            'tin' => (string) $this->tin,
            'email' => (string) $this->email,
            'logo_url' => $this->logoUrl(),
        ];
    }

    /**
     * The identity of the business a user works for, or the platform's own name when they have
     * none (a super admin, a test). Never null, so receipts always have a heading.
     *
     * @return array{name: string, address: string, phone: string, tin: string, email: string, logo_url: ?string}
     */
    public static function identityFor(?User $user): array
    {
        return static::forUser($user)?->identity() ?? static::platformIdentity();
    }

    /** Same, for an account head's id (receipts and jobs that already know the owner). */
    public static function identityForOwnerId(?string $ownerId): array
    {
        return static::forOwnerId($ownerId)?->identity() ?? static::platformIdentity();
    }

    /**
     * The identity a rental receipt or text carries: the business of the property's owner (the
     * landlord), whoever happens to be signed in or running the job (the overdue-bills job has
     * nobody signed in).
     *
     * @return array{name: string, address: string, phone: string, tin: string, email: string, logo_url: ?string}
     */
    public static function identityForProperty(?\App\Models\Rental\Property $property): array
    {
        $owner = $property?->owner_id ? BusinessOwner::ofUser((string) $property->owner_id) : null;

        return static::identityForOwnerId($owner ?: TenantContext::writeOwner());
    }

    /**
     * The identity a driver's receipt carries: the business the DRIVER belongs to, whoever happens
     * to be signed in (a super admin printing it for them, a staff member). Falls back to the
     * signed-in business when the driver's own cannot be told.
     *
     * @return array{name: string, address: string, phone: string, tin: string, email: string, logo_url: ?string}
     */
    public static function identityForDriver(?Driver $driver): array
    {
        $owner = $driver?->owner_id ?: BusinessOwner::ofUser($driver?->user_id);

        return static::identityForOwnerId($owner ?: TenantContext::writeOwner());
    }

    public static function platformIdentity(): array
    {
        return [
            'name' => (string) config('app.name', 'Boda Mapato'),
            'address' => '',
            'phone' => '',
            'tin' => '',
            'email' => '',
            'logo_url' => null,
        ];
    }

    // ------------------------------------------------------------------ billing

    public function isExpired(): bool
    {
        return $this->valid_until !== null && $this->valid_until->isPast();
    }

    /** End of the grace period, or null when the business never expires. */
    public function graceEndsAt(): ?Carbon
    {
        return $this->valid_until?->copy()->addDays(max((int) config('billing.grace_days', 7), 0));
    }

    /** Expired, but still inside the grace period: works, and should be told to renew. */
    public function inGrace(): bool
    {
        return $this->isExpired() && !$this->pastGrace();
    }

    public function pastGrace(): bool
    {
        $end = $this->graceEndsAt();

        return $end !== null && $end->isPast();
    }

    /** Whole days until valid_until (negative once it has passed); null when it never expires. */
    public function daysLeft(): ?int
    {
        if ($this->valid_until === null) {
            return null;
        }

        return (int) now()->startOfDay()->diffInDays($this->valid_until->copy()->startOfDay(), false);
    }

    /** Is access refused? Only when enforcement is switched on AND the grace period is over. */
    public function blocksAccess(): bool
    {
        return (bool) config('billing.enforce', false) && $this->pastGrace();
    }

    /** The billing picture the apps show. */
    public function billingSummary(): array
    {
        return [
            'plan' => (string) $this->plan,
            'valid_until' => $this->valid_until?->toIso8601String(),
            'days_left' => $this->daysLeft(),
            'is_expired' => $this->isExpired(),
            'in_grace' => $this->inGrace(),
            'enforced' => (bool) config('billing.enforce', false),
            'blocked' => $this->blocksAccess(),
        ];
    }

    /** Profile + billing in one array. */
    public function toApiArray(): array
    {
        return array_merge(['id' => $this->id, 'owner_id' => $this->owner_id], $this->identity(), [
            'inventory_type' => $this->inventory_type,
            'billing' => $this->billingSummary(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ]);
    }
}
