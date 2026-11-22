<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Groups (Vikundi): expense requests. An official asks for money to be spent (a purpose, a payee, an amount, optionally a project);
     * the treasurer (or the chair) approves it or turns it down; the treasurer pays it out through the ledger and someone else verifies the
     * payment. An approved request is NOT a payment: it is paid only when its payout is verified.
     *
     *   group_expense_requests   the request, the decision and the amount approved
     *   group_transactions       + expense_id (the request a payout pays)
     */
    public function up(): void
    {
        if (!Schema::hasTable('group_expense_requests')) {
            Schema::create('group_expense_requests', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('reference', 20);
                $table->string('purpose', 255);
                $table->string('category', 30)->default('other');
                $table->string('payee', 150);
                $table->decimal('amount', 15, 2);
                $table->decimal('amount_approved', 15, 2)->nullable();
                $table->unsignedBigInteger('project_id')->nullable()->index();
                $table->unsignedBigInteger('requested_by_member_id')->nullable()->index();
                $table->uuid('requested_by')->nullable();
                $table->string('status', 12)->default('requested'); // requested | approved | rejected | cancelled
                $table->string('decision_note', 255)->nullable();
                $table->uuid('decided_by')->nullable();
                $table->timestamp('decided_at')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'reference']);
                $table->index(['owner_id', 'status']);
            });
        }

        if (Schema::hasTable('group_transactions') && !Schema::hasColumn('group_transactions', 'expense_id')) {
            Schema::table('group_transactions', function (Blueprint $table) {
                $table->unsignedBigInteger('expense_id')->nullable()->index();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('group_transactions') && Schema::hasColumn('group_transactions', 'expense_id')) {
            Schema::table('group_transactions', function (Blueprint $table) {
                $table->dropIndex(['expense_id']);
                $table->dropColumn('expense_id');
            });
        }
        Schema::dropIfExists('group_expense_requests');
    }
};
