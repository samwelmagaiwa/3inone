<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;

/**
 * Date parts in raw SQL that work on the database the app runs on (MySQL) and on the
 * SQLite the test suite uses. MySQL's YEAR(), MONTH(), DAY() and YEARWEEK() do not exist
 * in SQLite, so a report written with them cannot be tested.
 *
 * $column is a column name written in the code, never user input.
 */
final class SqlDate
{
    public static function year(string $column): string
    {
        return self::sqlite() ? "CAST(strftime('%Y', {$column}) AS INTEGER)" : "YEAR({$column})";
    }

    public static function month(string $column): string
    {
        return self::sqlite() ? "CAST(strftime('%m', {$column}) AS INTEGER)" : "MONTH({$column})";
    }

    public static function day(string $column): string
    {
        return self::sqlite() ? "CAST(strftime('%d', {$column}) AS INTEGER)" : "DAY({$column})";
    }

    /**
     * Year and week as one number, e.g. 202640 (weeks start on Sunday, like MySQL's default).
     *
     * SQLite's own week-of-year format (the one called percent-U) only exists from SQLite 3.46: an older one
     * (the CI runner's) answers NULL for it. So the week is worked out from the day of the year and the weekday, which
     * every SQLite has: week = (day of year - 1 + 7 - weekday) / 7, the definition of %U. Do not use %U, %V,
     * %G, %g or %u here (a test checks).
     */
    public static function yearWeek(string $column): string
    {
        if (!self::sqlite()) {
            return "YEARWEEK({$column})";
        }

        return "(CAST(strftime('%Y', {$column}) AS INTEGER) * 100"
            . " + (CAST(strftime('%j', {$column}) AS INTEGER) + 6 - CAST(strftime('%w', {$column}) AS INTEGER)) / 7)";
    }

    private static function sqlite(): bool
    {
        return DB::connection()->getDriverName() === 'sqlite';
    }
}
