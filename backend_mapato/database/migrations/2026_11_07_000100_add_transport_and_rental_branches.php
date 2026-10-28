<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Branches for Transport and Rental (the shop and the salon already have theirs, `inventory_branches`). A branch is a
     * place of the business: a yard or garage for transport, an area or office for rental. Three records say where they
     * belong -- a driver, a vehicle and a property -- and everything that hangs off them (payments, debts, receipts; houses,
     * bills, tenants) follows through the same account scope, so a report "for one branch" needs no new column elsewhere.
     * A business with no branch never sees any of it: every branch_id stays empty and nothing changes.
     *
     * Each step checks first (MySQL has no transactional DDL).
     */
    private const TABLES = ['drivers', 'devices', 'rental_properties'];

    public function up(): void
    {
        if (!Schema::hasTable('business_branches')) {
            Schema::create('business_branches', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('service', 20)->index();
                $table->string('name', 80);
                $table->string('address', 160)->nullable();
                $table->string('phone', 30)->nullable();
                $table->boolean('active')->default(true);
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'service', 'name'], 'one_service_branch_name_per_business');
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
        Schema::dropIfExists('business_branches');
    }
};
