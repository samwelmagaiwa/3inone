<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Groups (Vikundi): projects (miradi).
     *
     *   group_projects         a project of the group: proposed by a member or an officer, reviewed by the projects committee, approved
     *                          or turned down by the chair, run by a manager (the Projects Chairperson names one), closed as completed or
     *                          cancelled. The budget is what the group PLANS; money still moves only through the ledger.
     *   group_project_reviews  each committee member's recommendation (yes / no and why), one per reviewer
     *   group_project_updates  the progress log: percent done and a note, never edited
     */
    public function up(): void
    {
        if (!Schema::hasTable('group_projects')) {
            Schema::create('group_projects', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('reference', 20);
                $table->string('title', 150);
                $table->text('description')->nullable();
                $table->decimal('budget', 15, 2)->default(0);
                $table->date('start_date')->nullable();
                $table->date('end_date')->nullable();
                $table->unsignedBigInteger('proposed_by_member_id')->nullable()->index();
                $table->unsignedBigInteger('manager_member_id')->nullable()->index();
                $table->string('status', 12)->default('proposed'); // proposed | active | completed | rejected | cancelled
                $table->unsignedTinyInteger('progress')->default(0);
                $table->string('decision_note', 255)->nullable();
                $table->uuid('decided_by')->nullable();
                $table->timestamp('decided_at')->nullable();
                $table->string('closing_note', 255)->nullable();
                $table->timestamp('closed_at')->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'reference']);
                $table->index(['owner_id', 'status']);
            });
        }

        if (!Schema::hasTable('group_project_reviews')) {
            Schema::create('group_project_reviews', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('project_id')->index();
                $table->unsignedBigInteger('member_id');
                $table->boolean('supports');
                $table->string('note', 255)->nullable();
                $table->timestamps();
                $table->unique(['project_id', 'member_id']);
            });
        }

        if (!Schema::hasTable('group_project_updates')) {
            Schema::create('group_project_updates', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('project_id')->index();
                $table->unsignedTinyInteger('progress');
                $table->string('note', 500);
                $table->uuid('created_by')->nullable();
                $table->timestamp('created_at')->nullable();
            });
        }
    }

    public function down(): void
    {
        foreach (['group_project_updates', 'group_project_reviews', 'group_projects'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
