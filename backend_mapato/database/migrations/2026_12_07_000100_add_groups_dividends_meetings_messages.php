<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Groups (Vikundi), phase 5a: dividends, meetings, announcements and texts to members.
     *
     *   group_dividend_runs       one dividend for a period: the approved profit it may use, the formula chosen for it (closing or average
     *                             savings; a rate or sharing out the pool), who prepared it and who approved and posted it (never the same)
     *   group_dividend_lines      each member's base and amount in that run, kept with it forever
     *   group_meetings            a meeting the chair calls: when, where, agenda; held with minutes, or cancelled
     *   group_meeting_attendance  who was there
     *   group_announcements       a notice to all members or to the leaders, until it expires
     *   group_messages            a text sent to a set of members: what, to whom, how many went out
     *   group_message_recipients  each member it was for, and whether it went
     */
    public function up(): void
    {
        if (!Schema::hasTable('group_dividend_runs')) {
            Schema::create('group_dividend_runs', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->date('period_from');
                $table->date('period_to');
                $table->decimal('profit_pool', 15, 2);
                $table->string('base', 10); // closing | average
                $table->string('method', 10); // rate | share
                $table->decimal('rate', 7, 3)->nullable(); // percent, for method rate
                $table->decimal('total', 15, 2)->default(0);
                $table->string('status', 12)->default('draft'); // draft | posted | discarded
                $table->string('note', 255)->nullable(); // the meeting decision it rests on
                $table->uuid('prepared_by')->nullable();
                $table->uuid('approved_by')->nullable();
                $table->timestamp('posted_at')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('group_dividend_lines')) {
            Schema::create('group_dividend_lines', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('run_id')->index();
                $table->unsignedBigInteger('member_id')->index();
                $table->decimal('base', 15, 2);
                $table->decimal('amount', 15, 2);
                $table->unsignedBigInteger('transaction_id')->nullable();
            });
        }

        if (!Schema::hasTable('group_meetings')) {
            Schema::create('group_meetings', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('title', 150);
                $table->text('agenda')->nullable();
                $table->dateTime('starts_at');
                $table->string('venue', 150)->nullable();
                $table->string('status', 12)->default('scheduled'); // scheduled | held | cancelled
                $table->text('minutes')->nullable();
                $table->string('cancel_reason', 255)->nullable();
                $table->uuid('called_by')->nullable();
                $table->uuid('minutes_by')->nullable();
                $table->timestamps();
                $table->index(['owner_id', 'starts_at']);
            });
        }

        if (!Schema::hasTable('group_meeting_attendance')) {
            Schema::create('group_meeting_attendance', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('meeting_id')->index();
                $table->unsignedBigInteger('member_id');
                $table->boolean('present')->default(true);
                $table->unique(['owner_id', 'meeting_id', 'member_id'], 'group_attendance_once');
            });
        }

        if (!Schema::hasTable('group_announcements')) {
            Schema::create('group_announcements', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('title', 150);
                $table->text('body');
                $table->string('category', 20)->default('general');
                $table->string('audience', 12)->default('all'); // all | leaders
                $table->date('expires_on')->nullable();
                $table->uuid('author_id')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('group_messages')) {
            Schema::create('group_messages', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->text('body');
                $table->string('audience', 20); // all | leaders | overdue | selected
                $table->unsignedInteger('recipients')->default(0);
                $table->unsignedInteger('sent')->default(0);
                $table->unsignedSmallInteger('parts')->default(1);
                $table->string('status', 12)->default('queued'); // queued | done
                $table->uuid('sent_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('group_message_recipients')) {
            Schema::create('group_message_recipients', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('message_id')->index();
                $table->unsignedBigInteger('member_id');
                $table->string('phone', 20);
                $table->string('status', 10)->default('waiting'); // waiting | sent | failed
            });
        }
    }

    public function down(): void
    {
        foreach (['group_message_recipients', 'group_messages', 'group_announcements', 'group_meeting_attendance', 'group_meetings', 'group_dividend_lines', 'group_dividend_runs'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
