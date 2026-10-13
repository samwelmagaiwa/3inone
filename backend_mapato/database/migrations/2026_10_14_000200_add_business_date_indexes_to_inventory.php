<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Every inventory query is now limited to one business (owner_id = ...), and the busiest
     * screens then ask for "this business's rows for a day / week / month". An index on
     * (owner_id, created_at) lets the database jump straight to that slice instead of reading
     * the business's whole history, which matters as businesses and their history grow.
     *
     * Only adds indexes: no column, row or existing index is changed or removed, and each one
     * is skipped if it is already there, so running this twice is harmless.
     */
    private const INDEXES = [
        'inventory_sales' => ['inv_sales_owner_created_idx', ['owner_id', 'created_at']],
        'inventory_stock_movements' => ['inv_stock_mov_owner_created_idx', ['owner_id', 'created_at']],
        'inventory_expenses' => ['inv_expenses_owner_created_idx', ['owner_id', 'created_at']],
        'inventory_customers' => ['inv_customers_owner_name_idx', ['owner_id', 'name']],
    ];

    public function up(): void
    {
        foreach (self::INDEXES as $table => [$name, $columns]) {
            if (!Schema::hasTable($table) || Schema::hasIndex($table, $name)) {
                continue;
            }
            if (collect($columns)->contains(fn ($c) => !Schema::hasColumn($table, $c))) {
                continue;
            }

            Schema::table($table, fn (Blueprint $t) => $t->index($columns, $name));
        }
    }

    public function down(): void
    {
        foreach (self::INDEXES as $table => [$name]) {
            if (Schema::hasTable($table) && Schema::hasIndex($table, $name)) {
                Schema::table($table, fn (Blueprint $t) => $t->dropIndex($name));
            }
        }
    }
};
