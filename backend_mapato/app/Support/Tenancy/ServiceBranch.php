<?php

namespace App\Support\Tenancy;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Which branch a Transport or Rental request is about (the shop and the salon have SalonBranch). The app sends
 * `X-Branch: <id>` together with `X-Branch-Service: transport|rental` when someone has chosen a branch to look at;
 * with no header it is "all branches". A header that names a branch of another business, one that is switched off, or one
 * chosen in another service (ids of different services are different lists) is ignored.
 *
 * Read by the account scope of the three records that carry a branch (driver, vehicle, property), so everything built on
 * them follows without each screen asking.
 */
final class ServiceBranch
{
    /** @var array<string, int|null> */
    private static array $memo = [];

    private static ?bool $tableExists = null;

    public static function available(): bool
    {
        return self::$tableExists ??= Schema::hasTable('business_branches');
    }

    /** The branch looked at in this service for this user's business, or null for "all". */
    public static function selected(string $service, ?User $user, ?Request $request = null): ?int
    {
        if ($user === null || !self::available()) {
            return null;
        }
        $request ??= request();
        $asked = $request?->header('X-Branch');
        if ($asked === null || $asked === '' || !ctype_digit((string) $asked)) {
            return null;
        }
        if ($request->header('X-Branch-Service') !== $service) {
            return null;
        }

        $owner = $user->accountHeadId();
        $key = "$owner|$service|$asked";

        return self::$memo[$key] ??= (DB::table('business_branches')
            ->where('id', (int) $asked)->where('owner_id', $owner)->where('service', $service)->where('active', true)
            ->exists() ? (int) $asked : null);
    }

    /** A branch id the person typed into a form: kept only if it is an active branch of their business in this service. */
    public static function valid(mixed $id, string $service, ?User $user): ?int
    {
        if ($user === null || !self::available() || $id === null || $id === '' || !ctype_digit((string) $id)) {
            return null;
        }

        return DB::table('business_branches')
            ->where('id', (int) $id)->where('owner_id', $user->accountHeadId())->where('service', $service)->where('active', true)
            ->exists() ? (int) $id : null;
    }

    /** For tests: forget what was looked up. */
    public static function forget(): void
    {
        self::$memo = [];
        self::$tableExists = null;
    }
}
