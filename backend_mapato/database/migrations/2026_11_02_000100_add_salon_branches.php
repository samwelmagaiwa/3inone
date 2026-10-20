<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A salon with more than one branch: each sale, expense, appointment, shift and attendance record says which branch it
     * belongs to, and each person has a home branch. A salon with one branch never sees any of it (every branch_id stays
     * empty and every report is of everything). Goods stock is NOT split by branch: it stays one store.
     *
     * Each step checks first (MySQL has no transactional DDL); the new table carries its own `service` column.
     */
    private const TABLES = ['inventory_sales', 'inventory_expenses', 'inventory_appointments', 'inventory_salon_shifts', 'inventory_attendance', 'inventory_staff_profiles'];

    public function up(): void
    {
        if (!Schema::hasTable('inventory_branches')) {
            Schema::create('inventory_branches', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->string('name', 80);
                $table->string('address', 160)->nullable();
                $table->string('phone', 30)->nullable();
                $table->boolean('active')->default(true);
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'service', 'name'], 'one_branch_name_per_business');
            });
        }

        foreach (self::TABLES as $name) {
            if (Schema::hasTable($name) && !Schema::hasColumn($name, 'branch_id')) {
                Schema::table($name, function (Blueprint $table) {
                    $table->unsignedBigInteger('branch_id')->nullable()->index();
                });
            }
        }
    }

    public function down(): void
    {
        foreach (self::TABLES as $name) {
            if (Schema::hasTable($name) && Schema::hasColumn($name, 'branch_id')) {
                Schema::table($name, function (Blueprint $table) {
                    $table->dropIndex(['branch_id']);
                    $table->dropColumn('branch_id');
                });
            }
        }
        Schema::dropIfExists('inventory_branches');
    }
};
