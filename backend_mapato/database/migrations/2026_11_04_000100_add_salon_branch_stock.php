<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Goods stock by branch. The product's own quantity stays the salon's whole stock; this table says how much of it sits
     * in each branch (what is not allocated is in the main store). A sale made in a branch takes from that branch first.
     * Each step checks first (MySQL has no transactional DDL); the table carries its own `service` column.
     */
    public function up(): void
    {
        if (!Schema::hasTable('inventory_branch_stock')) {
            Schema::create('inventory_branch_stock', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('product_id')->index();
                $table->unsignedBigInteger('branch_id')->index();
                $table->unsignedInteger('quantity')->default(0);
                $table->timestamps();
                $table->unique(['product_id', 'branch_id'], 'one_stock_row_per_branch');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('inventory_branch_stock');
    }
};
