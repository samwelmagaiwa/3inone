<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Groups (Vikundi), phase 5b: invitations, documents, and where an application came from.
     *
     *   group_invitations       a code someone outside the group uses to apply to join (or to ask to hire): a member's own code (the
     *                           applicant is linked to them as the one who brought them in) or the group's code (for a poster); codes
     *                           are unique across all groups, so a code alone finds its group
     *   group_member_documents  a member's photo, ID copy or other paper, kept privately (signed links that expire)
     *   group_members           + source: officer | invitation | group_code -- how the application came in
     */
    public function up(): void
    {
        if (!Schema::hasTable('group_invitations')) {
            Schema::create('group_invitations', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('code', 12)->unique();
                $table->string('kind', 10); // member | group
                $table->unsignedBigInteger('member_id')->nullable()->index();
                $table->boolean('active')->default(true);
                $table->unsignedInteger('used')->default(0);
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('group_member_documents')) {
            Schema::create('group_member_documents', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('member_id')->index();
                $table->string('kind', 12); // photo | id | other
                $table->string('path', 255);
                $table->string('caption', 150)->nullable();
                $table->uuid('uploaded_by')->nullable();
                $table->timestamp('created_at')->nullable();
            });
        }

        if (Schema::hasTable('group_members') && !Schema::hasColumn('group_members', 'source')) {
            Schema::table('group_members', function (Blueprint $table) {
                $table->string('source', 12)->nullable();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('group_members') && Schema::hasColumn('group_members', 'source')) {
            Schema::table('group_members', function (Blueprint $table) {
                $table->dropColumn('source');
            });
        }
        Schema::dropIfExists('group_member_documents');
        Schema::dropIfExists('group_invitations');
    }
};
