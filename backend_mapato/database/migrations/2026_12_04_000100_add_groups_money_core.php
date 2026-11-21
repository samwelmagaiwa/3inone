<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Groups (Vikundi), phase 2: the money a group expects from its members, and its own spending.
     *
     *   group_contribution_types  what members pay in turn (monthly JAMII, a celebration, ...): amount, how often, the day it is due
     *   group_obligations         what one member owes for one contribution in one period (2026-11, once, an event): the amount
     *                             paid is read from the verified payments that name it; an approved udhuru (exemption) closes it
     *   group_promises            "I will pay 20,000 on the 30th": a promise never changes a balance, only a verified payment does
     *   group_reminders           a reminder text claimed before it is sent, so nobody is texted twice for the same thing on a day
     *   group_transactions        + obligation_id (the contribution a payment settles), + payee (who a group expense was paid to)
     *
     * Additive only; every table carries owner_id and is in TenantTables::GROUPS.
     */
    public function up(): void
    {
        if (!Schema::hasTable('group_contribution_types')) {
            Schema::create('group_contribution_types', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('name', 100);
                $table->string('description', 255)->nullable();
                $table->decimal('amount', 15, 2);
                $table->string('frequency', 12); // monthly | one_time | event
                $table->unsignedTinyInteger('due_day')->nullable(); // monthly: the day of the month it is due
                $table->boolean('mandatory')->default(true);
                $table->date('starts_on');
                $table->date('ends_on')->nullable();
                $table->boolean('active')->default(true);
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('group_obligations')) {
            Schema::create('group_obligations', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('member_id')->index();
                $table->unsignedBigInteger('contribution_type_id')->index();
                $table->string('period', 30); // 2026-11 | once | E20261122-1
                $table->string('label', 120)->nullable();
                $table->decimal('amount_due', 15, 2);
                $table->date('due_date');
                $table->string('status', 12)->default('open'); // open | exempt | cancelled
                $table->string('exempt_reason', 255)->nullable();
                $table->uuid('exempted_by')->nullable();
                $table->timestamp('exempted_at')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'member_id', 'contribution_type_id', 'period'], 'group_obligation_once');
                $table->index(['owner_id', 'status', 'due_date']);
            });
        }

        if (!Schema::hasTable('group_promises')) {
            Schema::create('group_promises', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('member_id')->index();
                $table->unsignedBigInteger('obligation_id')->nullable();
                $table->decimal('amount', 15, 2);
                $table->date('promised_on');
                $table->string('note', 255)->nullable();
                $table->string('status', 12)->default('open'); // open | cancelled
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('group_reminders')) {
            Schema::create('group_reminders', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('kind', 20); // due_soon | overdue | promise
                $table->unsignedBigInteger('subject_id');
                $table->date('sent_on');
                $table->timestamp('created_at')->nullable();
                $table->unique(['owner_id', 'kind', 'subject_id', 'sent_on'], 'group_reminder_once');
            });
        }

        if (Schema::hasTable('group_transactions')) {
            Schema::table('group_transactions', function (Blueprint $table) {
                if (!Schema::hasColumn('group_transactions', 'obligation_id')) {
                    $table->unsignedBigInteger('obligation_id')->nullable()->index();
                }
                if (!Schema::hasColumn('group_transactions', 'payee')) {
                    $table->string('payee', 150)->nullable();
                }
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('group_transactions')) {
            Schema::table('group_transactions', function (Blueprint $table) {
                foreach (['obligation_id', 'payee'] as $column) {
                    if (Schema::hasColumn('group_transactions', $column)) {
                        if ($column === 'obligation_id') {
                            $table->dropIndex(['obligation_id']);
                        }
                        $table->dropColumn($column);
                    }
                }
            });
        }
        foreach (['group_reminders', 'group_promises', 'group_obligations', 'group_contribution_types'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
