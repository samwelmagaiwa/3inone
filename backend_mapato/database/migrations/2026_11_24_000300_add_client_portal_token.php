<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /** A client's own private link (their page: visits, points, packages, what they owe): one long secret per client. */
    public function up(): void
    {
        if (Schema::hasTable('inventory_customers') && !Schema::hasColumn('inventory_customers', 'portal_token')) {
            Schema::table('inventory_customers', function (Blueprint $table) {
                $table->string('portal_token', 64)->nullable()->index();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('inventory_customers', 'portal_token')) {
            Schema::table('inventory_customers', function (Blueprint $table) {
                $table->dropColumn('portal_token');
            });
        }
    }
};
