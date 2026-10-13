<?php

namespace App\Support;

use Illuminate\Support\Facades\Schema;

/**
 * The columns for `select c.*, COUNT(...) ... group by <columns>`.
 *
 * Laravel's strict mode switches on MySQL's ONLY_FULL_GROUP_BY, which wants every selected column in the GROUP
 * BY. MySQL 8 works out that grouping by the primary key covers the rest; MariaDB (the production database) does
 * not, and SQLite never asks. A list written by hand is right the day it is written and wrong the day a column is
 * added: `owner_id` was added to every inventory table and the category, brand, customer and supplier lists
 * answered 500 on MariaDB while every test (SQLite) stayed green. Built from the table itself, the list can't go
 * out of date. A test (GroupByListsTest) fails if a hand-written list comes back.
 */
final class GroupColumns
{
    /** @var array<string, list<string>> */
    private static array $columns = [];

    /**
     * Every column of $table, qualified with the alias the query uses for it: ['c.id', 'c.name', ...].
     *
     * @return list<string>
     */
    public static function of(string $table, string $alias): array
    {
        $columns = self::$columns[$table] ??= Schema::getColumnListing($table);

        return array_map(static fn (string $column): string => "{$alias}.{$column}", $columns);
    }
}
