<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /** Salon: a discount says why it was given. Checks first (MySQL has no transactional DDL). */
    public function up(): void
    {
        if (Schema::hasTable('inventory_sales') && !Schema::hasColumn('inventory_sales', 'discount_reason')) {
            Schema::table('inventory_sales', function (Blueprint $table) {
                $table->string('discount_reason', 160)->nullable();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('inventory_sales') && Schema::hasColumn('inventory_sales', 'discount_reason')) {
            Schema::table('inventory_sales', fn (Blueprint $t) => $t->dropColumn('discount_reason'));
        }
    }
};
