<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The owner's money tools: debts from before the app (owed to the business and owed by it), a personal/business marker
 * on expenses, a profit target per month, and a snapshot of the business's position at each month end.
 * Safe to run again (MySQL has no transactional DDL, so a half-finished run must be repeatable).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('inventory_opening_debts')) {
            Schema::create('inventory_opening_debts', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('inventory')->index();
                // receivable = a customer owes the business; payable = the business owes a supplier or lender
                $table->string('kind', 12)->index();
                $table->unsignedBigInteger('customer_id')->nullable()->index();
                $table->unsignedBigInteger('supplier_id')->nullable()->index();
                $table->string('party_name', 160);
                $table->string('party_phone', 40)->nullable();
                $table->decimal('amount', 14, 2);
                $table->decimal('paid_amount', 14, 2)->default(0);
                $table->date('started_on');
                $table->date('due_on')->nullable();
                $table->string('note', 255)->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_opening_payments')) {
            Schema::create('inventory_opening_payments', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('inventory')->index();
                $table->unsignedBigInteger('debt_id')->index();
                $table->decimal('amount', 14, 2);
                $table->string('method', 30)->nullable();
                $table->date('paid_on');
                $table->string('note', 255)->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_targets')) {
            Schema::create('inventory_targets', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('inventory')->index();
                $table->string('month', 7); // 2026-11
                $table->decimal('profit_target', 14, 2);
                // set once the month has been judged, so the owner is told only once
                $table->timestamp('judged_at')->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'service', 'month'], 'one_target_per_month');
            });
        }

        if (!Schema::hasTable('inventory_month_snapshots')) {
            Schema::create('inventory_month_snapshots', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('inventory')->index();
                $table->string('month', 7);
                $table->decimal('stock_value', 16, 2)->default(0);
                $table->decimal('receivable', 16, 2)->default(0);
                $table->decimal('payable', 16, 2)->default(0);
                $table->decimal('capital', 16, 2)->default(0);
                $table->timestamps();
                $table->unique(['owner_id', 'service', 'month'], 'one_snapshot_per_month');
            });
        }

        if (Schema::hasTable('inventory_expenses') && !Schema::hasColumn('inventory_expenses', 'is_personal')) {
            Schema::table('inventory_expenses', function (Blueprint $table) {
                // spending that is not the business's (family, drawings): listed, but never taken off the profit
                $table->boolean('is_personal')->default(false)->index();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('inventory_expenses', 'is_personal')) {
            Schema::table('inventory_expenses', function (Blueprint $table) {
                $table->dropColumn('is_personal');
            });
        }
        foreach (['inventory_month_snapshots', 'inventory_targets', 'inventory_opening_payments', 'inventory_opening_debts'] as $t) {
            Schema::dropIfExists($t);
        }
    }
};
