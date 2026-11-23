<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Groups (Vikundi): how often a loan is repaid. Each loan keeps the rhythm of the day it was applied under (like its rate and method):
 * every day, week, two weeks, month, two months, three months, six months, or every N days. Loans that exist stay monthly.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('group_loans', function (Blueprint $table) {
            if (!Schema::hasColumn('group_loans', 'repayment_every')) {
                $table->string('repayment_every', 16)->default('monthly');
            }
            if (!Schema::hasColumn('group_loans', 'repayment_days')) {
                $table->unsignedSmallInteger('repayment_days')->nullable(); // only for `custom`: every N days
            }
        });
    }

    public function down(): void
    {
        Schema::table('group_loans', function (Blueprint $table) {
            foreach (['repayment_every', 'repayment_days'] as $col) {
                if (Schema::hasColumn('group_loans', $col)) {
                    $table->dropColumn($col);
                }
            }
        });
    }
};
