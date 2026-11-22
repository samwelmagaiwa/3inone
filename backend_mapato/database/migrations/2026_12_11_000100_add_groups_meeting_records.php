<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Groups (Vikundi): the record of a meeting beyond its minutes.
     *
     *   group_meeting_items   what the meeting decided (a resolution) and what someone must do after it (an action, with who and by when,
     *                         ticked off when done)
     *   group_meetings        + minutes_approved_by / _at: the chair approves the secretary's minutes; until then they are a draft that
     *                         only officers see, and once approved they are not edited without the chair reopening them
     */
    public function up(): void
    {
        if (!Schema::hasTable('group_meeting_items')) {
            Schema::create('group_meeting_items', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('meeting_id')->index();
                $table->string('kind', 12); // resolution | action
                $table->string('text', 500);
                $table->unsignedBigInteger('assignee_member_id')->nullable()->index();
                $table->date('due_date')->nullable();
                $table->string('status', 8)->default('open'); // open | done (actions only)
                $table->timestamp('done_at')->nullable();
                $table->uuid('done_by')->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (Schema::hasTable('group_meetings')) {
            Schema::table('group_meetings', function (Blueprint $table) {
                if (!Schema::hasColumn('group_meetings', 'minutes_approved_by')) {
                    $table->uuid('minutes_approved_by')->nullable();
                }
                if (!Schema::hasColumn('group_meetings', 'minutes_approved_at')) {
                    $table->timestamp('minutes_approved_at')->nullable();
                }
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('group_meetings')) {
            Schema::table('group_meetings', function (Blueprint $table) {
                foreach (['minutes_approved_by', 'minutes_approved_at'] as $column) {
                    if (Schema::hasColumn('group_meetings', $column)) {
                        $table->dropColumn($column);
                    }
                }
            });
        }
        Schema::dropIfExists('group_meeting_items');
    }
};
