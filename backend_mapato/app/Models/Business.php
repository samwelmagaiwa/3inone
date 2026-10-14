<?php

namespace App\Models;

use App\Models\Concerns\ScopedToAccount;
use App\Support\PlanCatalog;
use App\Support\Tenancy\BusinessOwner;
use App\Support\Tenancy\TenantContext;
use App\Traits\HasUuid;
use Carbon\Carbon;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

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

    /** Where a business's SMS sender name stands. Only `approved` is ever used to send. */
    public const SMS_SENDER_STATUSES = ['none', 'pending', 'approved', 'rejected'];

    protected $fillable = [
        'owner_id', 'name', 'address', 'tin', 'phone', 'email', 'logo_path', 'plan', 'valid_until', 'inventory_type',
        'sms_sender_id', 'sms_sender_status', 'sms_display_name', 'sms_sender_note',
        'sms_sender_requested_at', 'sms_sender_approved_at',
        'sms_sent_count', 'sms_own_count', 'sms_fallback_count', 'sms_last_sent_at', 'sms_last_error',
    ];

    /** A business's own SMS account key and secret never leave the server, whatever serialises the model. */
    protected $hidden = ['sms_api_key', 'sms_api_secret'];

    protected $casts = [
        'valid_until' => 'datetime',
        'sms_api_key' => 'encrypted',
        'sms_api_secret' => 'encrypted',
        'sms_fallback_platform' => 'boolean',
        'sms_sender_requested_at' => 'datetime',
        'sms_sender_approved_at' => 'datetime',
        'sms_last_sent_at' => 'datetime',
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

    /** The services this business has been given (transport, rental, inventory). */
    public function serviceTypes(): array
    {
        return $this->owner?->serviceTypes() ?? [];
    }

    /** Does a plan cover every service this business has? (trial and free have no limit.) */
    public function planCoversServices(string $plan): bool
    {
        return PlanCatalog::covers($plan, count($this->serviceTypes()));
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

    /**
     * The business of a rental property's owner (the landlord), whoever is signed in or running the job.
     * The same business identityForProperty() describes; texts need the business itself to pick its sender name.
     */
    public static function forProperty(?\App\Models\Rental\Property $property): ?self
    {
        $owner = $property?->owner_id ? BusinessOwner::ofUser((string) $property->owner_id) : null;

        return static::forOwnerId($owner ?: TenantContext::writeOwner());
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

    // ------------------------------------------------------------------ SMS sender name

    /** The registered sender name texts to this business's customers go out under, or null for the platform's own. */
    public function usableSmsSender(): ?string
    {
        $id = trim((string) $this->sms_sender_id);

        return $this->sms_sender_status === 'approved' && $id !== '' ? $id : null;
    }

    /**
     * The business's OWN account with the SMS provider (its API key and, if it has one, secret), or null when it
     * sends through the platform's account. A key that can no longer be decrypted (the app key was changed) counts
     * as none, so texts keep going out under the platform's account instead of failing.
     *
     * @return array{api_key: string, api_secret: ?string}|null
     */
    public function smsCredentials(): ?array
    {
        try {
            $key = trim((string) $this->sms_api_key);
            if ($key === '') {
                return null;
            }
            $secret = trim((string) $this->sms_api_secret);

            return ['api_key' => $key, 'api_secret' => $secret !== '' ? $secret : null];
        } catch (\Throwable) {
            return null;
        }
    }

    /** May a text go out through the platform's account when the business's own name or account is refused? */
    public function smsMayFallBack(): bool
    {
        return (bool) ($this->sms_fallback_platform ?? true);
    }

    /** The business name as written inside a text: the short display name when one was set. */
    public function smsName(): string
    {
        $name = trim((string) $this->sms_display_name);

        return $name !== '' ? $name : (string) $this->name;
    }

    /** An approved name that the provider stopped accepting (texts have gone out under the platform name instead). */
    public function smsNeedsAttention(): bool
    {
        return $this->sms_sender_status === 'approved' && trim((string) $this->sms_last_error) !== '';
    }

    /** What the business's own people see about its sender name. */
    public function smsSenderSummary(): array
    {
        return [
            'sender_id' => $this->sms_sender_id,
            'display_name' => $this->sms_display_name,
            'status' => $this->sms_sender_status ?: 'none',
            'note' => $this->sms_sender_note,
        ];
    }

    /** What the super admin sees: the summary plus what was sent and whether the provider still accepts the name. */
    public function smsSenderDetails(): array
    {
        $own = $this->smsCredentials();

        return array_merge($this->smsSenderSummary(), [
            // Never the key itself: only that there is one, and its last four characters so it can be recognised.
            'has_api_key' => $own !== null,
            'has_api_secret' => ($own['api_secret'] ?? null) !== null,
            'api_key_hint' => $own !== null ? '****' . substr($own['api_key'], -4) : null,
            'fallback_platform' => $this->smsMayFallBack(),
            'requested_at' => $this->sms_sender_requested_at?->toIso8601String(),
            'approved_at' => $this->sms_sender_approved_at?->toIso8601String(),
            'sent_count' => (int) $this->sms_sent_count,
            'own_count' => (int) $this->sms_own_count,
            'fallback_count' => (int) $this->sms_fallback_count,
            'last_sent_at' => $this->sms_last_sent_at?->toIso8601String(),
            'last_error' => $this->sms_last_error,
            'needs_attention' => $this->smsNeedsAttention(),
        ]);
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

    // ------------------------------------------------------------------ payments and the subscription

    /** Every payment recorded for this business, newest first. */
    public function payments(): HasMany
    {
        return $this->hasMany(BusinessPayment::class, 'business_id')->orderByDesc('paid_at')->orderByDesc('id');
    }

    /** The newest payment, or null when none was ever recorded (a trial, or an account from before plans). */
    public function lastPayment(): ?BusinessPayment
    {
        return $this->payments()->first();
    }

    /** When the current period began: the newest payment's period, else the day the business was created. */
    public function startedAt(): ?Carbon
    {
        $last = $this->lastPayment();

        return $last?->period_start ?? $this->created_at;
    }

    /**
     * never   -- no end date (an account from before plans)
     * active  -- paid up, more than `soon` days left
     * expiring -- paid up, but `soon` days or fewer remain
     * grace   -- ended, still working for a few days, and should be told to pay
     * expired -- ended and past the grace days
     */
    public function subscriptionStatus(int $soonDays = 7): string
    {
        if ($this->valid_until === null) {
            return 'never';
        }
        if (!$this->isExpired()) {
            return $this->daysLeft() <= $soonDays ? 'expiring' : 'active';
        }

        return $this->inGrace() ? 'grace' : 'expired';
    }

    /**
     * Record a payment and move `valid_until` on, in one step.
     *
     * Paying while still covered adds time AFTER the current end (nothing already paid for is lost);
     * paying after it ran out starts from today. The period is `months` long (1 when not said), or ends on
     * the exact `valid_until` date if one is given. The business works through the end of that last day.
     * The moment this returns, a business that was held back is open again: access is worked out from
     * `valid_until` on every request.
     *
     * @param  array{amount: float|int|string, currency?: ?string, method?: ?string, reference?: ?string, plan?: ?string, months?: ?int, valid_until?: ?string, paid_at?: ?string, note?: ?string}  $data
     */
    public function recordPayment(array $data, ?User $by = null): BusinessPayment
    {
        $now = now();
        $running = $this->valid_until !== null && $this->valid_until->isFuture();

        $periodStart = $running ? $this->valid_until->copy()->addDay()->startOfDay() : $now->copy()->startOfDay();
        $periodEnd = !empty($data['valid_until'])
            ? Carbon::parse($data['valid_until'])->endOfDay()
            : ($running ? $this->valid_until : $now)->copy()->addMonthsNoOverflow(max((int) ($data['months'] ?? 1), 1))->endOfDay();

        // A trial or a free account that starts paying moves to a paid plan: the smallest one that covers the services
        // it has (basic for one, standard for two, premium for all three), unless the super admin chose which.
        $plan = $data['plan'] ?? (in_array($this->plan, ['trial', 'free', ''], true) ? PlanCatalog::planFor(count($this->serviceTypes())) : $this->plan);

        $payment = $this->payments()->create([
            'amount' => $data['amount'],
            'currency' => $data['currency'] ?? 'TZS',
            'method' => $data['method'] ?? null,
            'reference' => $data['reference'] ?? null,
            'plan' => $plan,
            'period_start' => $periodStart,
            'period_end' => $periodEnd,
            'paid_at' => !empty($data['paid_at']) ? Carbon::parse($data['paid_at']) : $now,
            'recorded_by' => $by?->id,
            'note' => $data['note'] ?? null,
        ]);

        $this->plan = $plan;
        $this->valid_until = $periodEnd;
        $this->save();

        return $payment;
    }

    /**
     * What "my subscription" shows. The payment history (with amounts) is for the owner only; staff see the
     * plan and the dates.
     */
    public function subscriptionPayload(bool $withPayments): array
    {
        $last = $this->lastPayment();

        return array_merge($this->billingSummary(), [
            'status' => $this->subscriptionStatus(),
            'started_at' => $this->startedAt()?->toIso8601String(),
            'grace_ends_at' => $this->graceEndsAt()?->toIso8601String(),
            'grace_days' => max((int) config('billing.grace_days', 7), 0),
            'last_payment' => $last?->toApiArray(),
            'payments' => $withPayments ? $this->payments()->limit(100)->get()->map->toApiArray()->values()->all() : [],
            'contact_phone' => (string) config('billing.contact_phone', ''),
        ]);
    }

    /** Profile + billing in one array. */
    public function toApiArray(): array
    {
        return array_merge(['id' => $this->id, 'owner_id' => $this->owner_id], $this->identity(), [
            'inventory_type' => $this->inventory_type,
            'billing' => $this->billingSummary(),
            'sms_sender' => $this->smsSenderSummary(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ]);
    }
}
