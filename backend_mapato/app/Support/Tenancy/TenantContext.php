<?php

namespace App\Support\Tenancy;

use App\Models\User;
use Closure;
use LogicException;

/**
 * Who is acting, as far as data isolation is concerned.
 *
 * Every service resolves "whose data is this?" here, so Transport (Eloquent
 * AccountScope), Rental (Eloquent AccountScope + explicit owner checks) and
 * Inventory (the tenant-aware query grammar) can never disagree:
 *
 *   - a signed-in user acts as themself;
 *   - super_admin reads and writes only their own account's operational rows, like everyone else (the platform's
 *     own records -- businesses, payments, users -- are read through the admin endpoints);
 *   - everyone else reads and writes only their account head's rows;
 *   - with nobody signed in (queue workers, artisan, the login flow) nothing is
 *     scoped and nothing is stamped -- use runAs() to act as a business there.
 */
final class TenantContext
{
    private const UUID = '/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i';

    private static ?User $acting = null;

    /** More than 0 while the Trash is being looked at or worked on: trashed rows are then visible to queries. */
    private static int $trashDepth = 0;

    private static bool $unscoped = false;

    private static ?User $defaultBusiness = null;

    /** The service chosen on purpose (a scheduled job, a test); null = read it from the request. */
    private static ?string $service = null;

    /** @var array<string, string> viewer id => the service they were let into for this request */
    private static array $resolved = [];

    /** The user whose account every scoped query is limited to. */
    public static function viewer(): ?User
    {
        if (self::$unscoped) {
            return null;
        }

        if (self::$acting !== null) {
            return self::$acting;
        }

        $user = auth()->user();
        if ($user instanceof User) {
            return $user;
        }

        return self::$defaultBusiness;
    }

    /**
     * The business to act as when NOBODY is signed in. Meant for tests and one-off
     * scripts that read and write raw rows outside a request; a signed-in user
     * always takes precedence, so requests are unaffected. Pass null (or call
     * reset()) to go back to "nobody signed in means nothing is scoped".
     */
    public static function useDefaultBusiness(?User $business): void
    {
        self::$defaultBusiness = $business;
    }

    /** Forget every override: acting user, unscoped flag and default business. */
    public static function reset(): void
    {
        self::$acting = null;
        self::$unscoped = false;
        self::$defaultBusiness = null;
        self::$service = null;
        self::$resolved = [];
    }

    /**
     * Which service's books this request works in: 'salon' when the app says so (the `X-Service: salon` header,
     * sent only from the salon's screens) AND the person really has the salon; otherwise 'inventory', which is what
     * every request meant before the salon existed. Null when nobody is signed in or nothing is scoped (migrations,
     * maintenance), so those still see every row.
     */
    public static function service(): ?string
    {
        $viewer = self::viewer();
        if ($viewer === null) {
            return null;
        }

        if (self::$service !== null) {
            return self::$service;
        }

        $asked = app()->bound('request') ? (string) request()->header('X-Service', '') : '';
        if ($asked !== 'salon') {
            return 'inventory';
        }

        return self::$resolved[(string) $viewer->id] ??= $viewer->canUseService('salon') ? 'salon' : 'inventory';
    }

    /**
     * Run $callback in one service's books (a scheduled job texting salon clients), whatever the request says.
     *
     * @template T
     * @param  Closure(): T  $callback
     * @return T
     */
    public static function runInService(string $service, Closure $callback): mixed
    {
        if (!in_array($service, TenantTables::SERVICES, true)) {
            throw new LogicException('Unknown service.');
        }

        $previous = self::$service;
        self::$service = $service;

        try {
            return $callback();
        } finally {
            self::$service = $previous;
        }
    }

    /**
     * Run $callback as a business: its queries are scoped to that account and
     * the rows it creates are stamped with it. Restores the previous context
     * afterwards, even if the callback throws.
     *
     * @template T
     * @param  User|string  $actor  a user, or a user id (usually the account head's)
     * @param  Closure(): T  $callback
     * @return T
     */
    public static function runAs(User|string $actor, Closure $callback): mixed
    {
        $user = $actor instanceof User ? $actor : User::query()->findOrFail($actor);

        $previous = self::$acting;
        self::$acting = $user;

        try {
            return $callback();
        } finally {
            self::$acting = $previous;
        }
    }

    /**
     * Run $callback with no scoping at all and nothing stamped, whoever is signed
     * in. Only for data migrations and maintenance commands that must see every
     * business's rows (for instance, rows that have no owner yet) -- never from a
     * request handler.
     *
     * @template T
     * @param  Closure(): T  $callback
     * @return T
     */
    /** Run [callback] with trashed rows visible (the Trash screen, a restore, removing for good). Nothing else ever sees them. */
    public static function withTrashed(Closure $callback): mixed
    {
        self::$trashDepth++;
        try {
            return $callback();
        } finally {
            self::$trashDepth--;
        }
    }

    public static function seesTrashed(): bool
    {
        return self::$trashDepth > 0;
    }

    public static function withoutScope(Closure $callback): mixed
    {
        $previous = self::$unscoped;
        self::$unscoped = true;

        try {
            return $callback();
        } finally {
            self::$unscoped = $previous;
        }
    }

    /**
     * The business every read, update and delete is limited to, or null when
     * nothing is signed in or the viewer is a super_admin (unrestricted).
     */
    public static function readOwner(): ?string
    {
        $viewer = self::viewer();

        // Nobody signed in: unscoped (jobs, login). A super admin is scoped like anyone else: the platform owner runs the
        // platform (businesses, plans, payments, users), and never reads or writes a business's products, sales or clients.
        if ($viewer === null) {
            return null;
        }

        return self::validated($viewer->accountHeadId());
    }

    /**
     * The business a newly created row belongs to, or null when nobody is
     * signed in. A super_admin's rows belong to their own account.
     */
    public static function writeOwner(): ?string
    {
        $viewer = self::viewer();

        return $viewer === null ? null : self::validated($viewer->accountHeadId());
    }

    /** True when the current viewer may see every business (super_admin). */
    public static function seesEverything(): bool
    {
        $viewer = self::viewer();

        return $viewer !== null && $viewer->seesAllAccounts();
    }

    /**
     * An owner id is spliced into SQL as a literal (so it can never disturb the
     * statement's bindings), which is only safe for a real UUID. Anything else
     * stops the request instead of producing an unscoped or malformed query.
     */
    public static function validated(string $ownerId): string
    {
        if (preg_match(self::UUID, $ownerId) !== 1) {
            throw new LogicException('Refusing to scope a query to a malformed owner id.');
        }

        return $ownerId;
    }
}
