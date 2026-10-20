<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The salon's money, beyond the sale: expenses that say who supplied, how they were paid, a receipt photo and
     * whether the owner approved them; a fixed commission per service; what each person earns (monthly salary, own
     * commission rate); and what has been paid out to them (salary, commission, advances).
     *
     * Each step checks first (MySQL has no transactional DDL). The two new tables carry their own `service` column:
     * they are created after the migration that split the shop's books from the salon's.
     */
    public function up(): void
    {
        if (Schema::hasTable('inventory_expenses')) {
            Schema::table('inventory_expenses', function (Blueprint $table) {
                if (!Schema::hasColumn('inventory_expenses', 'supplier')) {
                    $table->string('supplier', 120)->nullable();
                }
                if (!Schema::hasColumn('inventory_expenses', 'payment_method')) {
                    $table->string('payment_method', 30)->nullable();
                }
                if (!Schema::hasColumn('inventory_expenses', 'receipt_path')) {
                    $table->string('receipt_path', 255)->nullable();
                }
                if (!Schema::hasColumn('inventory_expenses', 'status')) {
                    // approved | pending | rejected. Everything that exists, and everything the shop records, is approved.
                    $table->string('status', 20)->default('approved')->index();
                }
                if (!Schema::hasColumn('inventory_expenses', 'approved_by')) {
                    $table->uuid('approved_by')->nullable();
                }
                if (!Schema::hasColumn('inventory_expenses', 'approved_at')) {
                    $table->timestamp('approved_at')->nullable();
                }
            });
        }

        if (Schema::hasTable('inventory_products') && !Schema::hasColumn('inventory_products', 'commission_fixed')) {
            Schema::table('inventory_products', function (Blueprint $table) {
                $table->decimal('commission_fixed', 14, 2)->nullable();
            });
        }

        if (!Schema::hasTable('inventory_staff_profiles')) {
            Schema::create('inventory_staff_profiles', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->uuid('staff_id');
                $table->string('specialization', 60)->nullable();
                $table->decimal('monthly_salary', 14, 2)->default(0);
                // Used for a service that has no rate of its own.
                $table->decimal('commission_percent', 5, 2)->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'service', 'staff_id'], 'staff_profile_per_business');
            });
        }

        if (!Schema::hasTable('inventory_staff_payouts')) {
            Schema::create('inventory_staff_payouts', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->uuid('staff_id')->index();
                $table->string('staff_name', 120)->nullable();
                // salary | commission | advance
                $table->string('kind', 20)->index();
                $table->decimal('amount', 14, 2);
                $table->date('paid_on')->index();
                // The month (YYYY-MM) it settles; an advance counts against the month it was given in.
                $table->string('period_month', 7)->index();
                $table->string('method', 30)->default('cash');
                $table->string('note', 160)->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('inventory_staff_payouts');
        Schema::dropIfExists('inventory_staff_profiles');

        if (Schema::hasTable('inventory_products') && Schema::hasColumn('inventory_products', 'commission_fixed')) {
            Schema::table('inventory_products', fn (Blueprint $t) => $t->dropColumn('commission_fixed'));
        }

        if (Schema::hasTable('inventory_expenses')) {
            foreach (['supplier', 'payment_method', 'receipt_path', 'approved_by', 'approved_at'] as $column) {
                if (Schema::hasColumn('inventory_expenses', $column)) {
                    Schema::table('inventory_expenses', fn (Blueprint $t) => $t->dropColumn($column));
                }
            }
            if (Schema::hasColumn('inventory_expenses', 'status')) {
                Schema::table('inventory_expenses', function (Blueprint $t) {
                    $t->dropIndex(['status']);
                    $t->dropColumn('status');
                });
            }
        }
    }
};
