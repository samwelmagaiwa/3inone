<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Salon: what a stylist earns. A service carries the percent of its price the stylist who did it gets; every sale
     * line keeps the AMOUNT worked out when it was sold, so changing the rate later never rewrites old earnings.
     * Each step checks first (MySQL has no transactional DDL).
     */
    public function up(): void
    {
        if (Schema::hasTable('inventory_products') && !Schema::hasColumn('inventory_products', 'commission_percent')) {
            Schema::table('inventory_products', function (Blueprint $table) {
                $table->decimal('commission_percent', 5, 2)->nullable();
            });
        }

        if (Schema::hasTable('inventory_sale_items') && !Schema::hasColumn('inventory_sale_items', 'commission_amount')) {
            Schema::table('inventory_sale_items', function (Blueprint $table) {
                $table->decimal('commission_amount', 14, 2)->nullable();
            });
        }
    }

    public function down(): void
    {
        foreach (['inventory_products' => 'commission_percent', 'inventory_sale_items' => 'commission_amount'] as $table => $column) {
            if (Schema::hasTable($table) && Schema::hasColumn($table, $column)) {
                Schema::table($table, fn (Blueprint $t) => $t->dropColumn($column));
            }
        }
    }
};
