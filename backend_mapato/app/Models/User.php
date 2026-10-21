<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;
use App\Traits\HasUuid;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable, HasUuid;

    /**
     * The attributes that are mass assignable.
     */
    protected $fillable = [
        'name',
        'email',
        'password',
        'phone_number',
        'role',
        'service_type',
        'full_access',
        'permissions',
        'created_by',
        'device_id',
        'is_active',
        'email_verified',
        'phone_verified',
        'avatar_url',
        'email_verified_at',
        'last_login_at',
        'two_factor_enabled',
        'two_factor_secret',
        'two_factor_confirmed_at',
    ];

    /**
     * The attributes that should be hidden for serialization.
     */
    protected $hidden = [
        'password',
        'remember_token',
    ];

    /**
     * The attributes that should be cast.
     */
    protected $casts = [
        'email_verified_at' => 'datetime',
        'last_login_at' => 'datetime',
        'two_factor_confirmed_at' => 'datetime',
        'password' => 'hashed',
        'is_active' => 'boolean',
        'full_access' => 'boolean',
        'must_change_password' => 'boolean',
        'permissions' => 'array',
        'email_verified' => 'boolean',
        'phone_verified' => 'boolean',
        'two_factor_enabled' => 'boolean',
    ];

    /**
     * Get the driver profile associated with the user.
     */
    public function driver()
    {
        return $this->hasOne(Driver::class);
    }

    /**
     * Check if user has a driver profile
     */
    public function hasDriverProfile(): bool
    {
        return $this->driver()->exists();
    }

    /**
     * Check if user is an active driver
     */
    public function isActiveDriver(): bool
    {
        return $this->hasDriverProfile() && $this->driver->is_active;
    }

    /**
     * User roles
     */
    const ROLES = [
        'super_admin'   => 'Super Admin',
        'admin'         => 'Admin',
        'manager'       => 'Manager',
        'sales_officer' => 'Sales Officer',
        // The salon's own roles.
        'hair_stylist'  => 'Hair Stylist',
        'nail_technician' => 'Nail Technician',
        'lash_makeup_artist' => 'Lash & Makeup Artist',
        'accountant'    => 'Accountant',
        'operator'      => 'Operator',
        'viewer'        => 'Viewer',
        'driver'        => 'Driver',
        'landlord'      => 'Landlord',
        'caretaker'     => 'Caretaker',
        'tenant'        => 'Tenant',
    ];

    /** All known inventory permission keys. Used to validate explicit grants. */
    const INV_PERMISSIONS = [
        'inv_view_products',   'inv_manage_products',
        // Narrower than inv_manage_products: may add NEW products only --
        // no editing, deleting, pricing changes, categories or brands.
        'inv_create_products',
        'inv_manage_stock',    'inv_create_sales',
        'inv_manage_sales',    'inv_view_reminders',
        'inv_view_purchasing', 'inv_view_credit',
        'inv_view_cash',       'inv_view_crates',
        'inv_view_reports',    'inv_view_expenses',
        'inv_manage_expenses', 'inv_manage_settings',
        // Narrower than inv_manage_stock: lets someone submit/view a damage
        // report without full stock-management rights. Approving one still
        // requires inv_manage_stock (see routes/api.php write-offs group).
        'inv_report_damage',
    ];

    /**
     * Per-user grants for the Rental and Transport services. Unlike the inv_*
     * keys these are not part of any role default; they only ever come from an
     * explicit grant in the permission-management screen. The route -> key
     * mapping that enforces them lives in config/feature_permissions.php.
     */
    const SERVICE_PERMISSIONS = [
        'manage_properties_rental', 'manage_houses_rental',
        'onboard_tenants_rental',   'manage_agreements_rental',
        'manage_billing_rental',    'view_reports_rental',
        'manage_maintenance_rental',
        'manage_vehicles_transport',   'manage_drivers_transport',
        'manage_agreements_transport', 'manage_payments_transport',
        'manage_debts_transport',      'view_reports_transport',
        'manage_reminders_transport',
    ];

    /** Every key an explicit grant may contain. */
    public static function grantablePermissions(): array
    {
        return array_merge(self::INV_PERMISSIONS, self::SERVICE_PERMISSIONS);
    }

    /** The service ('inventory'|'rental'|'transport') a grantable key belongs to. */
    public static function serviceForPermission(string $permission): string
    {
        return match (true) {
            str_starts_with($permission, 'inv_') => 'inventory',
            str_ends_with($permission, '_rental') => 'rental',
            default                               => 'transport',
        };
    }

    /** True when the user holds this explicit (non-role-default) grant. */
    public function hasExplicitGrant(string $permission): bool
    {
        return $this->full_access
            || (is_array($this->permissions) && in_array($permission, $this->permissions, true));
    }

    /**
     * Get the user who created this user
     */
    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    /**
     * Get users created by this user
     */
    public function createdUsers()
    {
        return $this->hasMany(User::class, 'created_by');
    }

    // ── Account scope ────────────────────────────────────────────────────────
    // "Who may see whose data" is derived from who created whom. An account has
    // one head (admin / landlord) and everything that head -- or staff the head
    // created -- creates belongs to that account. Data written by anyone in the
    // account is visible to everyone in it (subject to their permissions) and to
    // nobody outside it. super_admin is the only unrestricted user.

    /** Roles that head their own account: their creator never owns their data. */
    public const ACCOUNT_HEAD_ROLES = ['admin', 'administrator', 'landlord'];

    /** Counterparties who only ever see their own records, never a shared pool. */
    public const PORTAL_ROLES = ['driver', 'tenant', 'vendor'];

    private ?string $accountHeadIdCache = null;

    /** @var array<int, string>|null */
    private ?array $accountMemberIdsCache = null;

    /** super_admin is the one role that sees every account. */
    public function seesAllAccounts(): bool
    {
        return $this->isSuperAdmin();
    }

    /** A driver / tenant / vendor: scoped to their own records, not the account's. */
    public function isPortalUser(): bool
    {
        return in_array(strtolower((string) $this->role), self::PORTAL_ROLES, true);
    }

    /**
     * Id of the user heading this user's account: the nearest admin / landlord
     * at or above them in the created_by chain. A user with no such head
     * (created by super_admin, or an orphan) is their own account, so the
     * safe fallback is "sees only what they made".
     */
    public function accountHeadId(): string
    {
        if ($this->accountHeadIdCache !== null) {
            return $this->accountHeadIdCache;
        }

        $current = $this;
        for ($hops = 0; $current && $hops < 8; $hops++) {
            if (in_array(strtolower((string) $current->role), self::ACCOUNT_HEAD_ROLES, true)) {
                return $this->accountHeadIdCache = (string) $current->id;
            }
            if (!$current->created_by) {
                break;
            }
            $current = static::query()->find($current->created_by);
        }

        return $this->accountHeadIdCache = (string) $this->id;
    }

    /**
     * Can this user work right now? They must be active themselves AND belong to a
     * business whose owner is active: deactivating (suspending) an owner shuts the whole
     * business, staff included, without touching a single account or record.
     */
    public function accountIsActive(): bool
    {
        if (!$this->is_active) {
            return false;
        }

        $headId = $this->accountHeadId();
        if ($headId === (string) $this->id) {
            return true;
        }

        $head = static::query()->find($headId);

        return $head === null || (bool) $head->is_active;
    }

    /**
     * Ids of the account's head and every staff member below them (not
     * drivers/tenants/vendors, and not other account heads). A record belongs
     * to this account when its owner / creator is one of these ids.
     *
     * @return array<int, string>
     */
    public function accountMemberIds(): array
    {
        if ($this->accountMemberIdsCache !== null) {
            return $this->accountMemberIdsCache;
        }

        $head = $this->accountHeadId();
        $ids = [$head];
        $frontier = [$head];
        $excluded = array_merge(self::PORTAL_ROLES, self::ACCOUNT_HEAD_ROLES, ['super_admin']);

        for ($depth = 0; $depth < 8 && $frontier; $depth++) {
            $next = static::query()
                ->whereIn('created_by', $frontier)
                ->whereNotIn('role', $excluded)
                ->pluck('id')
                ->map(fn ($id) => (string) $id)
                ->all();
            $next = array_values(array_diff($next, $ids));
            $ids = array_merge($ids, $next);
            $frontier = $next;
        }

        // The user themself is always part of their own account, whatever their role.
        if (!in_array((string) $this->id, $ids, true)) {
            $ids[] = (string) $this->id;
        }

        return $this->accountMemberIdsCache = $ids;
    }

    /** Drop the memoised account lookups (after changing who created whom). */
    public function forgetAccountCache(): void
    {
        $this->accountHeadIdCache = null;
        $this->accountMemberIdsCache = null;
        $this->effectiveServicesCache = null;
    }

    /**
     * Restrict a User query to the accounts the caller may see: everyone they
     * or their staff created, plus themself. super_admin sees all.
     */
    public function scopeInAccountOf($query, self $viewer)
    {
        if ($viewer->seesAllAccounts()) {
            return $query;
        }

        return $query->where(function ($q) use ($viewer) {
            $q->whereIn('users.created_by', $viewer->accountMemberIds())
                ->orWhere('users.id', $viewer->id);
        });
    }

    /**
     * Get the device assigned to this user
     */
    public function assignedDevice()
    {
        return $this->belongsTo(Device::class, 'device_id');
    }

    /**
     * Services this user is bound to (rental/transport/inventory). A user
     * can hold more than one - see user_services migration for why this
     * replaced the old single `service_type` column as the source of truth.
     */
    public function services()
    {
        return $this->hasMany(\App\Models\UserService::class);
    }

    /** Plain list of service_type strings this user is bound to. */
    public function serviceTypes(): array
    {
        return $this->services->pluck('service_type')->all();
    }

    /**
     * Mirrors servicesForRole() in boda_mapato/lib/utils/role_services.dart
     * exactly -- keep both in sync. Only used as a fallback below when a
     * user has no explicit user_services rows; super_admin's implicit
     * access is also backfilled into real rows by getUserDataWithRelations(),
     * but this table is what a NEWLY affected role (one added to the app
     * without ever getting a binding row) falls back to.
     */
    private const SERVICE_ROLE_DEFAULTS = [
        'super_admin'   => ['inventory', 'rental', 'transport', 'salon'],
        // admin/administrator get NO implicit services -- a super_admin
        // must explicitly bind them, same as the Flutter mapping.
        'admin'         => [],
        'administrator' => [],
        'sales_officer' => ['inventory'],
        'manager'       => ['inventory'],
        'operator'      => ['inventory'],
        'hair_stylist'  => ['salon'],
        'nail_technician' => ['salon'],
        'lash_makeup_artist' => ['salon'],
        'accountant'    => ['salon'],
        'driver'        => ['transport'],
        'landlord'      => ['rental'],
        'caretaker'     => ['rental'],
        'tenant'        => ['rental'],
        'vendor'        => ['rental'],
    ];

    /**
     * The services this user may access: their explicit user_services
     * bindings if any exist, else whatever their role implies. Centralizes
     * what used to be a one-off super_admin special-case duplicated across
     * myServices() and getUserDataWithRelations() in AuthController --
     * every other role with zero bindings was silently falling through to
     * an empty list (the same "no access to any service" bug already found
     * and fixed on the Flutter side, just missed here for non-super-admin
     * roles).
     */
    public function allowedServiceTypes(): array
    {
        // A super admin has EVERY service, including one added after their account was made: the rows saved for them
        // are only what they had at that time, and are brought up to date the next time they sign in.
        if (strtolower((string) $this->role) === 'super_admin') {
            return self::SERVICE_ROLE_DEFAULTS['super_admin'];
        }

        $bound = $this->serviceTypes();
        if (!empty($bound)) {
            return $bound;
        }

        return self::SERVICE_ROLE_DEFAULTS[strtolower($this->role ?? '')] ?? [];
    }

    /** The self-registration this account was created from, if it registered itself. */
    public function registration()
    {
        return $this->hasOne(BusinessRegistration::class);
    }

    private ?array $effectiveServicesCache = null;

    /**
     * May this user use a service? Only when a super admin has given it to them
     * AND to the account head above them, so taking a service from a business
     * takes it from that business's staff and drivers as well. super_admin and
     * full_access users may use all three.
     *
     * Enforced by the `service:` route middleware; the mobile app's own service
     * picker is built from effectiveServiceTypes() so the two never disagree.
     */
    public function canUseService(string $service): bool
    {
        if ($this->seesAllAccounts() || $this->full_access) {
            return true;
        }
        if (!config('tenancy.enforce_services', true)) {
            return true;
        }
        if (!in_array($service, $this->allowedServiceTypes(), true)) {
            return false;
        }

        $headId = $this->accountHeadId();
        if ($headId === (string) $this->id) {
            return true;
        }

        $head = static::query()->find($headId);

        return $head !== null && $head->canUseService($service);
    }

    /** The services this user really has, as the app's service picker should list them. */
    public function effectiveServiceTypes(): array
    {
        if ($this->effectiveServicesCache !== null) {
            return $this->effectiveServicesCache;
        }

        if (!config('tenancy.enforce_services', true)) {
            return $this->effectiveServicesCache = $this->allowedServiceTypes();
        }

        return $this->effectiveServicesCache = array_values(array_filter(
            config('tenancy.services', ['inventory', 'rental', 'transport', 'salon']),
            fn (string $service) => $this->canUseService($service)
        ));
    }



    // ── Inventory role defaults ──────────────────────────────────────────────
    // Mirrors UserPermissions._getPermissionsForRole() in Flutter so the
    // server-side and client-side checks are always in sync.
    private static array $INV_ROLE_DEFAULTS = [
        // super_admin has unrestricted access to everything across all services.
        'super_admin'  => null,
        // admin has full permissions within their assigned service(s), but their
        // service access is enforced by service bindings — not by bypassing the
        // permission check.  Using a null here would give them a cross-service
        // bypass identical to super_admin, which is intentionally NOT the case.
        'admin'        => [
            'inv_view_products','inv_manage_products','inv_manage_stock',
            'inv_create_sales','inv_manage_sales','inv_view_reminders',
            'inv_view_purchasing','inv_view_credit','inv_view_cash',
            'inv_view_crates','inv_view_reports','inv_view_expenses',
            'inv_manage_expenses','inv_manage_settings',
        ],
        'administrator'=> [
            'inv_view_products','inv_manage_products','inv_manage_stock',
            'inv_create_sales','inv_manage_sales','inv_view_reminders',
            'inv_view_purchasing','inv_view_credit','inv_view_cash',
            'inv_view_crates','inv_view_reports','inv_view_expenses',
            'inv_manage_expenses','inv_manage_settings',
        ],
        'manager'      => [
            'inv_view_products','inv_manage_products','inv_manage_stock',
            'inv_create_sales','inv_manage_sales','inv_view_reminders',
            'inv_view_purchasing','inv_view_credit','inv_view_cash',
            'inv_view_crates','inv_view_reports','inv_view_expenses',
            'inv_manage_expenses',
        ],
        // Point-of-sale only -- deliberately excludes catalog management,
        // physical stock control, sales management/returns, purchasing,
        // reports, and the expense ledger. Mirrors the narrowed set in
        // UserPermissions._getPermissionsForRole() (Flutter), which was
        // scoped down from a broader default after an admin reported a
        // sales_officer account seeing near-admin-level quick menus.
        'sales_officer'=> [
            'inv_view_products','inv_create_products','inv_create_sales','inv_view_reminders',
            'inv_view_credit','inv_view_cash','inv_view_crates',
            // Can flag damaged/expired/broken stock they spot at the
            // counter without full stock-management rights -- approving
            // the report still needs inv_manage_stock, which they lack.
            'inv_report_damage',
        ],
        'operator'     => [
            'inv_view_products','inv_manage_products',
            'inv_create_sales','inv_view_reminders',
        ],
        // ---- The salon's roles: the owner (admin) runs everything; the accountant also keeps the till, books and the money;
        // the people who do the work see only their own. (Reception, cashier, manager and stock work were folded into these.)
        // Their own services, appointments and performance (the server shows them only their own); they flag damaged goods.
        'hair_stylist' => ['inv_view_products','inv_create_sales','inv_view_reminders','inv_report_damage'],
        'nail_technician' => ['inv_view_products','inv_create_sales','inv_view_reminders','inv_report_damage'],
        'lash_makeup_artist' => ['inv_view_products','inv_create_sales','inv_view_reminders','inv_report_damage'],
        // The till and the books: sales, bookings, payments, receipts, returns, the daily cash, clients' credit, expenses,
        // financial reports and payroll.
        'accountant'   => [
            'inv_view_products','inv_create_sales','inv_manage_sales','inv_view_credit','inv_view_cash',
            'inv_view_reports','inv_view_expenses','inv_manage_expenses','inv_view_reminders',
        ],
        'viewer'       => ['inv_view_products'],
    ];

    /**
     * Check whether this user has a given inventory permission.
     *
     * Resolution order:
     *  1. super_admin / admin / full_access → always yes
     *  2. Explicit per-user grant in users.permissions
     *  3. Role default set (INV_ROLE_DEFAULTS)
     */
    public function hasInventoryPermission(string $permission): bool
    {
        // Only super_admin and full_access users bypass the permission check entirely.
        // admin/administrator go through the role-default list so their access is
        // scoped to the service(s) assigned to them by a super_admin.
        $role = strtolower($this->role ?? '');
        if ($this->full_access || $role === 'super_admin') {
            return true;
        }

        // Explicit per-user grant
        $explicit = is_array($this->permissions) ? $this->permissions : [];
        if (in_array($permission, $explicit, true)) {
            return true;
        }

        // Role defaults
        $defaults = self::$INV_ROLE_DEFAULTS[$role] ?? [];
        if ($defaults === null) return true; // unrestricted role
        return in_array($permission, $defaults, true);
    }

    /**
     * Returns the merged effective inventory permission set for this user:
     * role defaults ∪ explicit grants. Used in the auth/user response so
     * the Flutter client always gets the resolved list.
     */
    public function effectiveInventoryPermissions(): array
    {
        $role = strtolower($this->role ?? '');
        if ($this->full_access || $role === 'super_admin') {
            // Sentinel for "unrestricted" -- the Flutter client strips this
            // value out and relies on isSuperAdmin/isAdmin/fullAccess
            // instead, so nothing here should return actual permission
            // strings for an unrestricted role (a prior version accidentally
            // returned the *role names* from INV_ROLE_DEFAULTS's keys via a
            // botched array union with ['__all__'], e.g. "manager",
            // "sales_officer" -- meaningless as permission strings, and the
            // union silently dropped the sentinel itself).
            return ['__all__'];
        }
        $defaults = self::$INV_ROLE_DEFAULTS[$role] ?? [];
        if ($defaults === null) return ['__all__'];
        $explicit = is_array($this->permissions) ? $this->permissions : [];
        return array_values(array_unique(array_merge($defaults, $explicit)));
    }

    /**
     * Check if user has specific role
     */
    public function hasRole(string $role): bool
    {
        return $this->role === $role;
    }

    /**
     * Check if user is super admin
     */
    public function isSuperAdmin(): bool
    {
        return $this->hasRole('super_admin');
    }

    /**
     * Check if user is admin
     */
    public function isAdmin(): bool
    {
        return $this->hasRole('admin');
    }

    /**
     * Check if user is driver
     */
    public function isDriver(): bool
    {
        return $this->hasRole('driver');
    }

    /**
     * Check if user is landlord
     */
    public function isLandlord(): bool
    {
        return $this->hasRole('landlord');
    }

    /**
     * Check if user is caretaker
     */
    public function isCaretaker(): bool
    {
        return $this->hasRole('caretaker');
    }

    /**
     * Check if user is tenant
     */
    public function isTenant(): bool
    {
        return $this->hasRole('tenant');
    }

    /**
     * Check if user can create other users
     */
    public function canCreateUsers(): bool
    {
        return $this->isSuperAdmin() || $this->isAdmin();
    }

    /**
     * Check if user can manage drivers
     */
    public function canManageDrivers(): bool
    {
        return $this->isSuperAdmin() || $this->isAdmin();
    }

    /**
     * Get the profile associated with the user (alias for tenantProfile).
     */
    public function profile()
    {
        return $this->tenantProfile();
    }

    /**
     * Get the tenant profile associated with the user.
     */
    public function tenantProfile()
    {
        return $this->hasOne(\App\Models\Rental\TenantProfile::class, 'user_id');
    }

    /**
     * Get properties owned by the landlord.
     */
    public function ownedProperties()
    {
        return $this->hasMany(\App\Models\Rental\Property::class, 'owner_id');
    }

    /**
     * Get agreements for the tenant.
     */
    public function rentalAgreements()
    {
        return $this->hasMany(\App\Models\Rental\RentalAgreement::class, 'tenant_id');
    }

    /**
     * Get role display name
     */
    public function getRoleDisplayAttribute(): string
    {
        return self::ROLES[$this->role] ?? $this->role;
    }

    /**
     * Update last login timestamp
     */
    public function updateLastLogin(): void
    {
        $this->update(['last_login_at' => now()]);
    }

    /**
     * Scope to get users by role
     */
    public function scopeByRole($query, string $role)
    {
        return $query->where('role', $role);
    }

    /**
     * Scope to get active users
     */
    public function scopeActive($query)
    {
        return $query->where('is_active', true);
    }

    /**
     * Scope to get drivers
     */
    public function scopeDrivers($query)
    {
        return $query->byRole('driver');
    }

    /**
     * Scope to get admins
     */
    public function scopeAdmins($query)
    {
        return $query->whereIn('role', ['super_admin', 'admin']);
    }

    /**
     * Get the external service vendors saved to this user's (landlord) roster.
     */
    public function savedVendors()
    {
        return $this->belongsToMany(\App\Models\Rental\Vendor::class, 'landlord_vendor', 'landlord_id', 'vendor_id')->withTimestamps();
    }
}