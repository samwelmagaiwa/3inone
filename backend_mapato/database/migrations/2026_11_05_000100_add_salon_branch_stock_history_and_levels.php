<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The history of goods moved between the main store and branches, and the level at which a branch is told it is running
     * low (per product per branch; empty = no alert). Each step checks first (MySQL has no transactional DDL).
     */
    public function up(): void
    {
        if (!Schema::hasTable('inventory_branch_transfers')) {
            Schema::create('inventory_branch_transfers', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('product_id')->index();
                $table->string('product_name', 160)->nullable();
                // null = the main store
                $table->unsignedBigInteger('from_branch_id')->nullable();
                $table->unsignedBigInteger('to_branch_id')->nullable();
                $table->unsignedInteger('quantity');
                $table->uuid('created_by')->nullable();
                $table->string('created_by_name', 120)->nullable();
                $table->timestamps();
            });
        }

        if (Schema::hasTable('inventory_branch_stock') && !Schema::hasColumn('inventory_branch_stock', 'min_quantity')) {
            Schema::table('inventory_branch_stock', function (Blueprint $table) {
                $table->unsignedInteger('min_quantity')->nullable();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('inventory_branch_stock') && Schema::hasColumn('inventory_branch_stock', 'min_quantity')) {
            Schema::table('inventory_branch_stock', function (Blueprint $table) {
                $table->dropColumn('min_quantity');
            });
        }
        Schema::dropIfExists('inventory_branch_transfers');
    }
};
