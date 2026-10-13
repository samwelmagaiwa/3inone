<?php

namespace App\Support;

/**
 * One-time passwords for accounts somebody else creates (a tenant, a driver, a fundi,
 * a caretaker). They replace the fixed defaults ("tenant123", "password123", ...) that
 * anyone who has ever read the code or been onboarded could use on every other account.
 *
 * The generated password is shown ONCE to whoever created the account, to hand over; the
 * account is also flagged `must_change_password`, so the person chooses their own at the
 * first sign-in and the handed-over one stops working.
 */
final class TemporaryPassword
{
    /** No 0/O, 1/l/I: the password is read out or typed from a screen. */
    private const UPPER = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    private const LOWER = 'abcdefghijkmnpqrstuvwxyz';
    private const DIGITS = '23456789';

    public const LENGTH = 10;

    /** Passwords that were handed out by earlier versions of the app. */
    public const RETIRED_DEFAULTS = ['tenant123', 'caretaker123', 'password123', '12345678'];

    public static function generate(): string
    {
        $all = self::UPPER . self::LOWER . self::DIGITS;

        // At least one of each kind, so it satisfies any password rule, then fill up.
        $chars = [self::pick(self::UPPER), self::pick(self::LOWER), self::pick(self::DIGITS)];
        while (count($chars) < self::LENGTH) {
            $chars[] = self::pick($all);
        }

        // Fisher-Yates with a CSPRNG, so the first three are not always upper/lower/digit.
        for ($i = count($chars) - 1; $i > 0; $i--) {
            $j = random_int(0, $i);
            [$chars[$i], $chars[$j]] = [$chars[$j], $chars[$i]];
        }

        return implode('', $chars);
    }

    private static function pick(string $alphabet): string
    {
        return $alphabet[random_int(0, strlen($alphabet) - 1)];
    }
}
