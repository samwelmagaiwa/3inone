<?php

namespace App\Support;

use Carbon\Carbon;

/**
 * A date-time that arrived from a client, as a value every database takes.
 *
 * The app sends ISO-8601 text such as "2026-10-13T16:49:20.123456" or "2026-10-13T13:49:20+00:00". Written into a
 * DATETIME column as it is, MySQL 8 accepts it and MariaDB (the production database) answers error 1292 for the
 * time-zone suffix, so the sale was lost. Parsed into a date-time first, it is written in the database's own format
 * whichever engine is underneath, and an instant that carried a time zone is converted to the application's.
 */
final class ClientTime
{
    /** The moment the client named, or now when it named none. */
    public static function parse(mixed $value): Carbon
    {
        if ($value === null || $value === '') {
            return Carbon::now();
        }

        return Carbon::parse($value)->setTimezone((string) config('app.timezone', 'UTC'));
    }
}
