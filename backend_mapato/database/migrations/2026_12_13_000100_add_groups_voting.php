<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Groups (Vikundi): voting. Many voting processes run at once and each one is independent: its own target (a position with its candidates,
 * or an agenda with its answers), its own eligible voters, rules, dates, ballots and result.
 *
 *   group_votings           one voting process (an election for ONE position, or a decision on ONE agenda). `series` only groups related
 *                           processes for display ("Leadership election 2026"); nothing is ever counted across processes
 *   group_voting_options    the candidates (an election) or the answers (a decision: approve / reject / abstain)
 *   group_voting_eligible   who may vote in THIS process, fixed when it is published
 *   group_voting_turnout    WHO has voted in this process (one row per member: the unique key is what stops a second vote)
 *   group_ballots           WHAT was chosen. In a secret ballot the member is not stored here at all, the id is random and only the
 *                           date (not the time) is kept, so no list of ballots can be matched to the list of voters
 *   group_notifications     what each member is told, with a link to the exact voting item
 *
 * Additive only; every table carries owner_id and is in TenantTables::GROUPS.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('group_votings')) {
            Schema::create('group_votings', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('reference', 20);
                $table->string('series', 120)->nullable();
                $table->string('category', 12); // leadership | project | financial | policy | proposal | general
                $table->string('kind', 10); // election (candidates for a position) | decision (approve / reject / abstain on an agenda)
                $table->string('title', 150);
                $table->text('description')->nullable();
                $table->string('position', 100)->nullable(); // the position an election is for
                $table->string('eligibility', 10)->default('active'); // active | officers | selected
                $table->decimal('quorum_percent', 5, 2)->default(0);
                $table->decimal('threshold_percent', 5, 2)->default(50);
                $table->boolean('secret')->default(true);
                $table->boolean('allow_change')->default(false);
                $table->boolean('show_progress')->default(true);
                $table->string('results_visibility', 14)->default('after_close'); // live | after_close | after_publish
                $table->timestamp('opens_at')->nullable();
                $table->timestamp('closes_at')->nullable();
                $table->string('status', 10)->default('draft'); // draft | scheduled | open | paused | closed | cancelled
                $table->string('cancel_reason', 255)->nullable();
                $table->unsignedInteger('eligible_count')->default(0);
                $table->string('decision', 12)->nullable(); // passed | failed | no_quorum | winner | tie | none, worked out when it closes
                $table->unsignedBigInteger('winner_option_id')->nullable();
                $table->timestamp('closed_at')->nullable();
                $table->timestamp('results_published_at')->nullable();
                $table->uuid('results_published_by')->nullable();
                $table->timestamp('closing_notified_at')->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'reference']);
                $table->index(['owner_id', 'status']);
            });
        }

        if (!Schema::hasTable('group_voting_options')) {
            Schema::create('group_voting_options', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('voting_id')->index();
                $table->string('label', 150);
                $table->text('description')->nullable();
                $table->unsignedBigInteger('member_id')->nullable(); // the candidate, when the option is a member
                $table->string('role', 8)->nullable(); // decisions: approve | reject | abstain
                $table->unsignedTinyInteger('sort')->default(0);
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('group_voting_eligible')) {
            Schema::create('group_voting_eligible', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('voting_id');
                $table->unsignedBigInteger('member_id')->index();
                $table->unique(['voting_id', 'member_id']);
            });
        }

        if (!Schema::hasTable('group_voting_turnout')) {
            Schema::create('group_voting_turnout', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('voting_id');
                $table->unsignedBigInteger('member_id')->index();
                $table->date('voted_on'); // the day only: the time of day could be matched to a ballot
                $table->unique(['voting_id', 'member_id']);
            });
        }

        if (!Schema::hasTable('group_ballots')) {
            Schema::create('group_ballots', function (Blueprint $table) {
                $table->uuid('id')->primary(); // random, so the order of ballots says nothing about the order of voters
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('voting_id')->index();
                $table->unsignedBigInteger('option_id')->index();
                $table->unsignedBigInteger('member_id')->nullable(); // only in an open (not secret) vote
                $table->date('cast_on');
            });
        }

        if (!Schema::hasTable('group_notifications')) {
            Schema::create('group_notifications', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('member_id');
                $table->string('kind', 20); // voting_new | voting_open | voting_closing | voting_closed | voting_results | voting_voted
                $table->string('title', 150);
                $table->string('title_en', 150);
                $table->string('body', 255)->nullable();
                $table->string('body_en', 255)->nullable();
                $table->string('link_type', 20)->nullable(); // voting
                $table->unsignedBigInteger('link_id')->nullable(); // the exact voting item
                $table->timestamp('read_at')->nullable();
                $table->timestamp('created_at')->nullable();
                $table->index(['member_id', 'read_at']);
            });
        }
    }

    public function down(): void
    {
        foreach (['group_notifications', 'group_ballots', 'group_voting_turnout', 'group_voting_eligible', 'group_voting_options', 'group_votings'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
