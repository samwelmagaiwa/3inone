<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Groups (Vikundi), phase 3: loans and welfare.
     *
     *   group_loans              a member's loan from application to repaid: the terms are copied from the group's settings when it is
     *                            applied for (a later change of rate never touches it), and every decision says who and when
     *   group_loan_guarantors    each guarantor's answer (pending, accepted, declined)
     *   group_loan_schedule      the instalments, made when the disbursement is verified; what was repaid is READ from the verified
     *                            repayments (interest first, then principal, instalment by instalment), never stored
     *   group_benefit_types      the kinds of welfare help (bereavement, illness, celebration ...) and their usual amount
     *   group_benefit_requests   a member's request, the chair's decision and the amount approved; it is paid when its payout is verified
     *   group_transactions       + loan_id, + benefit_id (the loan a disbursement or repayment belongs to, the request a welfare payout pays)
     */
    public function up(): void
    {
        if (!Schema::hasTable('group_loans')) {
            Schema::create('group_loans', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('reference', 20);
                $table->unsignedBigInteger('member_id')->index();
                $table->decimal('amount_requested', 15, 2);
                $table->decimal('amount_approved', 15, 2)->nullable();
                $table->string('purpose', 255);
                $table->unsignedSmallInteger('term_months');
                $table->decimal('interest_rate', 6, 3); // percent per month, copied when applied for
                $table->string('interest_method', 10); // flat | reducing
                $table->decimal('ceiling', 15, 2)->nullable(); // the ceiling when applied for (savings x multiplier - other loans)
                $table->string('status', 20)->default('awaiting_guarantors');
                $table->string('recommendation', 255)->nullable();
                $table->uuid('recommended_by')->nullable();
                $table->timestamp('recommended_at')->nullable();
                $table->uuid('approved_by')->nullable();
                $table->timestamp('approved_at')->nullable();
                $table->string('reject_reason', 255)->nullable();
                $table->uuid('decided_by')->nullable();
                $table->timestamp('decided_at')->nullable();
                $table->date('disbursed_on')->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'reference']);
                $table->index(['owner_id', 'status']);
            });
        }

        if (!Schema::hasTable('group_loan_guarantors')) {
            Schema::create('group_loan_guarantors', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('loan_id')->index();
                $table->unsignedBigInteger('member_id')->index();
                $table->string('status', 12)->default('pending'); // pending | accepted | declined
                $table->string('note', 255)->nullable();
                $table->timestamp('responded_at')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'loan_id', 'member_id'], 'group_loan_guarantor_once');
            });
        }

        if (!Schema::hasTable('group_loan_schedule')) {
            Schema::create('group_loan_schedule', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('loan_id')->index();
                $table->unsignedSmallInteger('number');
                $table->date('due_date');
                $table->decimal('principal_due', 15, 2);
                $table->decimal('interest_due', 15, 2);
                $table->unique(['owner_id', 'loan_id', 'number'], 'group_loan_instalment_once');
            });
        }

        if (!Schema::hasTable('group_benefit_types')) {
            Schema::create('group_benefit_types', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('name', 100);
                $table->string('description', 255)->nullable();
                $table->decimal('amount', 15, 2)->nullable(); // the usual amount; null = decided case by case
                $table->boolean('active')->default(true);
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('group_benefit_requests')) {
            Schema::create('group_benefit_requests', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('reference', 20);
                $table->unsignedBigInteger('member_id')->index();
                $table->unsignedBigInteger('benefit_type_id');
                $table->string('beneficiary', 150);
                $table->string('relationship', 30);
                $table->date('event_date');
                $table->text('description')->nullable();
                $table->decimal('amount_requested', 15, 2)->nullable();
                $table->decimal('amount_approved', 15, 2)->nullable();
                $table->string('status', 12)->default('submitted'); // submitted | approved | rejected | cancelled
                $table->string('decision_note', 255)->nullable();
                $table->uuid('decided_by')->nullable();
                $table->timestamp('decided_at')->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'reference']);
                $table->index(['owner_id', 'status']);
            });
        }

        if (Schema::hasTable('group_transactions')) {
            Schema::table('group_transactions', function (Blueprint $table) {
                if (!Schema::hasColumn('group_transactions', 'loan_id')) {
                    $table->unsignedBigInteger('loan_id')->nullable()->index();
                }
                if (!Schema::hasColumn('group_transactions', 'benefit_id')) {
                    $table->unsignedBigInteger('benefit_id')->nullable()->index();
                }
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('group_transactions')) {
            Schema::table('group_transactions', function (Blueprint $table) {
                foreach (['loan_id', 'benefit_id'] as $column) {
                    if (Schema::hasColumn('group_transactions', $column)) {
                        $table->dropIndex([$column]);
                        $table->dropColumn($column);
                    }
                }
            });
        }
        foreach (['group_benefit_requests', 'group_benefit_types', 'group_loan_schedule', 'group_loan_guarantors', 'group_loans'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
