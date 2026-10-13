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

    /** Year and week as one number, e.g. 202641 (weeks start on Sunday, like MySQL's default). */
    public static function yearWeek(string $column): string
    {
        return self::sqlite() ? "CAST(strftime('%Y%U', {$column}) AS INTEGER)" : "YEARWEEK({$column})";
    }

    private static function sqlite(): bool
    {
        return DB::connection()->getDriverName() === 'sqlite';
    }
}
