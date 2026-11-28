<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Groups (Vikundi): what members held and owed BEFORE the group used the app ("previous data", brought forward), and refundable contributions.
 *
 *   - group_transactions.brought_forward: a member's total from before the app (savings, shares, joining fee, a contribution). It fills their
 *     balances and statement but is NOT cash: the group's real cash today is its opening balance, entered once.
 *   - group_transactions.contribution_type_id: which kind of contribution a brought-forward contribution total was (it has no obligation).
 *   - group_loans.brought_forward: a loan that was already running; it starts from what is still owed and paid no cash out here.
 *   - group_contribution_types.refundable: money the member gets back on leaving (a project contribution), shown in their account.
 *
 * Additive only, re-runnable; every column defaults to the old behaviour.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('group_transactions', function (Blueprint $table) {
            if (!Schema::hasColumn('group_transactions', 'brought_forward')) {
                $table->boolean('brought_forward')->default(false);
            }
            if (!Schema::hasColumn('group_transactions', 'contribution_type_id')) {
                $table->unsignedBigInteger('contribution_type_id')->nullable();
            }
        });
        Schema::table('group_loans', function (Blueprint $table) {
            if (!Schema::hasColumn('group_loans', 'brought_forward')) {
                $table->boolean('brought_forward')->default(false);
            }
        });
        Schema::table('group_contribution_types', function (Blueprint $table) {
            if (!Schema::hasColumn('group_contribution_types', 'refundable')) {
                $table->boolean('refundable')->default(false);
            }
        });
    }

    public function down(): void
    {
        foreach ([['group_transactions', ['brought_forward', 'contribution_type_id']], ['group_loans', ['brought_forward']], ['group_contribution_types', ['refundable']]] as [$t, $cols]) {
            foreach ($cols as $c) {
                if (Schema::hasColumn($t, $c)) {
                    Schema::table($t, fn (Blueprint $table) => $table->dropColumn($c));
                }
            }
        }
    }
};
