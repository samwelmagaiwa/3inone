<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * When a device is signed in, and when -- rarely -- it is not any more.
 *
 * One account can be signed in on any number of devices at once, and none of them is ever
 * signed out because another one signed in, or because a number of devices was reached, or
 * because some days went by since it signed in. A device stays signed in for as long as it is
 * used. The only automatic end is a device nobody has touched for a very long time
 * (config('sanctum.idle_days'), a year by default; 0 turns even that off), measured from its
 * LAST USE, so a device in regular use never reaches it.
 *
 * Other ways a session ends are decisions, not accidents: the person signs out, an
 * administrator deactivates or deletes the account (or suspends the business), the password
 * is reset after being forgotten, or the person changes their password and chooses to end
 * their other sessions (config 'sanctum.revoke_other_devices_on_password_change').
 */
final class SessionPolicy
{
    public static function idleDays(): int
    {
        return max((int) config('sanctum.idle_days', 365), 0);
    }

    /** Has this token gone unused for longer than the idle limit? */
    public static function isIdle(PersonalAccessToken $token): bool
    {
        $days = self::idleDays();
        if ($days === 0) {
            return false;
        }

        $lastSeen = $token->last_used_at ?? $token->created_at;

        return $lastSeen !== null && $lastSeen->lt(now()->subDays($days));
    }

    /** Remove the rows of devices idle past the limit (they are already refused; this tidies up). */
    public static function pruneIdle(): int
    {
        $days = self::idleDays();
        if ($days === 0) {
            return 0;
        }

        $cutoff = now()->subDays($days);

        return DB::table('personal_access_tokens')
            ->where(function ($q) use ($cutoff) {
                $q->where('last_used_at', '<', $cutoff)
                    ->orWhere(fn ($never) => $never->whereNull('last_used_at')->where('created_at', '<', $cutoff));
            })
            ->delete();
    }
}
