<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The salon's cashbook (money the owner put in or took out, and the counts that check the books against what is really
     * held), the walk-in queue, and the goods a service uses up (with what was taken for each sale line, so a cancelled sale
     * puts it back). Each step checks first (MySQL has no transactional DDL); every table carries its own `service` column.
     */
    public function up(): void
    {
        if (!Schema::hasTable('inventory_cash_moves')) {
            Schema::create('inventory_cash_moves', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                // opening (what was held when the book was started) | owner_deposit | owner_withdrawal
                $table->string('kind', 20)->index();
                // cash | mobile | bank
                $table->string('method', 10)->default('cash');
                $table->decimal('amount', 14, 2);
                $table->date('moved_on')->index();
                $table->string('note', 160)->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_cash_counts')) {
            Schema::create('inventory_cash_counts', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->date('counted_on')->index();
                $table->string('method', 10)->default('cash');
                $table->decimal('expected', 14, 2);
                $table->decimal('counted', 14, 2);
                $table->decimal('difference', 14, 2);
                $table->string('note', 160)->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_walkins')) {
            Schema::create('inventory_walkins', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('customer_id')->nullable()->index();
                $table->string('name', 120);
                $table->string('phone', 30)->nullable();
                $table->unsignedBigInteger('product_id')->nullable();
                $table->string('product_name', 120)->nullable();
                $table->uuid('staff_id')->nullable()->index();
                $table->string('staff_name', 120)->nullable();
                // waiting | serving | done | left
                $table->string('status', 10)->default('waiting')->index();
                $table->string('note', 160)->nullable();
                $table->timestamp('arrived_at')->nullable();
                $table->timestamp('started_at')->nullable();
                $table->timestamp('finished_at')->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_service_materials')) {
            Schema::create('inventory_service_materials', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('service_product_id')->index();
                $table->unsignedBigInteger('material_product_id')->index();
                $table->unsignedInteger('quantity')->default(1);
                $table->timestamps();
                $table->unique(['service_product_id', 'material_product_id'], 'one_material_per_service');
            });
        }

        if (!Schema::hasTable('inventory_service_usage')) {
            Schema::create('inventory_service_usage', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('sale_id')->index();
                $table->unsignedBigInteger('sale_item_id')->nullable();
                $table->unsignedBigInteger('material_product_id');
                $table->unsignedInteger('quantity');
                $table->decimal('unit_cost', 14, 2)->default(0);
                $table->timestamp('created_at')->nullable();
            });
        }
    }

    public function down(): void
    {
        foreach (['inventory_service_usage', 'inventory_service_materials', 'inventory_walkins', 'inventory_cash_counts', 'inventory_cash_moves'] as $t) {
            Schema::dropIfExists($t);
        }
    }
};
