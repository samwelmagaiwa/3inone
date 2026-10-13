<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * What kind of inventory business this is: retail, wholesale, mixed or depot.
     *
     * The owner picks it when registering; it is copied onto the business record at approval. It only
     * decides what a NEW business's inventory settings start with, so nothing here moves data.
     *
     * Every business that already uses inventory is a depot: that is what the inventory was built as,
     * and the platform's defaults are the depot's, so marking them changes nothing about how they work.
     * Businesses without inventory keep it empty.
     */
    public function up(): void
    {
        foreach (['businesses', 'business_registrations'] as $table) {
            if (!Schema::hasColumn($table, 'inventory_type')) {
                Schema::table($table, function (Blueprint $t) {
                    $t->string('inventory_type', 20)->nullable();
                });
            }
        }

        $withInventory = DB::table('user_services')->where('service_type', 'inventory')->pluck('user_id');
        if ($withInventory->isNotEmpty()) {
            foreach ($withInventory->chunk(500) as $owners) {
                DB::table('businesses')->whereIn('owner_id', $owners->all())->whereNull('inventory_type')
                    ->update(['inventory_type' => 'depot']);
                DB::table('business_registrations')->whereIn('user_id', $owners->all())->whereNull('inventory_type')
                    ->update(['inventory_type' => 'depot']);
            }
        }
    }

    public function down(): void
    {
        foreach (['businesses', 'business_registrations'] as $table) {
            if (Schema::hasColumn($table, 'inventory_type')) {
                Schema::table($table, function (Blueprint $t) {
                    $t->dropColumn('inventory_type');
                });
            }
        }
    }
};
