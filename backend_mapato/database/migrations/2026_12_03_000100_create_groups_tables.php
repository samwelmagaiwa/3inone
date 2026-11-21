<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The Groups (Vikundi) service, phase 1: a savings / economic group's settings, members and the money they pay in.
     *
     *   group_settings        every value the group sets (joining fee, shares, ...), one row per change: the value in force on a day is
     *                         the newest row that started on or before it, so an old calculation can always be explained
     *   group_members         the member register: identity, contact, office held, status, referrer, member number once approved
     *   group_dependants      the people a member declares (parents, spouse, children, parents-in-law, other)
     *   group_member_events   each change of a member's status or office: who, when, why (never edited)
     *   group_transactions    money in or out per member and category; a row is SUBMITTED until the treasurer verifies it, and a
     *                         verified row is never changed or deleted -- a mistake is put right by a linked reversal
     *   group_audit_log       who did what in the group, in words
     *
     * Every table carries owner_id (the business) and is scoped by the query grammar (TenantTables::GROUPS). Additive only.
     */
    public function up(): void
    {
        if (!Schema::hasTable('group_settings')) {
            Schema::create('group_settings', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('key', 60);
                $table->string('value', 255)->nullable();
                $table->date('effective_from');
                $table->uuid('changed_by')->nullable();
                $table->string('reason', 255)->nullable();
                $table->timestamp('created_at')->nullable();
                $table->index(['owner_id', 'key', 'effective_from']);
            });
        }

        if (!Schema::hasTable('group_members')) {
            Schema::create('group_members', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('member_number', 30)->nullable();
                $table->string('application_ref', 30);
                $table->uuid('user_id')->nullable()->index();
                $table->string('full_name', 150);
                $table->string('phone', 20);
                $table->string('alt_phone', 20)->nullable();
                $table->string('email', 150)->nullable();
                $table->text('nida')->nullable(); // encrypted
                $table->string('nida_hash', 64)->nullable(); // to find a duplicate without decrypting
                $table->date('date_of_birth')->nullable();
                $table->string('gender', 10)->nullable();
                $table->string('region', 80)->nullable();
                $table->string('district', 80)->nullable();
                $table->string('ward', 80)->nullable();
                $table->string('street', 150)->nullable();
                $table->string('occupation', 120)->nullable();
                $table->string('photo_path', 255)->nullable();
                $table->string('office', 40)->nullable();
                $table->string('status', 30)->default('submitted');
                $table->string('status_reason', 255)->nullable();
                $table->unsignedBigInteger('referrer_id')->nullable();
                $table->boolean('founding')->default(false);
                $table->date('joined_on')->nullable();
                $table->timestamp('approved_at')->nullable();
                $table->uuid('approved_by')->nullable();
                $table->text('notes')->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'member_number']);
                $table->unique(['owner_id', 'application_ref']);
                $table->index(['owner_id', 'status']);
                $table->index(['owner_id', 'phone']);
                $table->index(['owner_id', 'nida_hash']);
                $table->index(['owner_id', 'referrer_id']);
            });
        }

        if (!Schema::hasTable('group_dependants')) {
            Schema::create('group_dependants', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('member_id')->index();
                $table->string('name', 150);
                $table->string('relationship', 30);
                $table->string('phone', 20)->nullable();
                $table->date('date_of_birth')->nullable();
                $table->string('notes', 255)->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('group_member_events')) {
            Schema::create('group_member_events', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('member_id')->index();
                $table->string('kind', 20); // status | office
                $table->string('from_value', 40)->nullable();
                $table->string('to_value', 40)->nullable();
                $table->string('reason', 255)->nullable();
                $table->uuid('by_user')->nullable();
                $table->timestamp('created_at')->nullable();
            });
        }

        if (!Schema::hasTable('group_transactions')) {
            Schema::create('group_transactions', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('reference', 30);
                $table->string('receipt_number', 30)->nullable();
                $table->unsignedBigInteger('member_id')->nullable()->index();
                $table->string('category', 40);
                $table->string('direction', 3); // in | out
                $table->decimal('amount', 15, 2);
                $table->string('method', 30);
                $table->string('external_ref', 80)->nullable();
                $table->date('paid_on');
                $table->string('status', 20)->default('pending'); // pending | verified | rejected
                $table->string('note', 255)->nullable();
                $table->uuid('submitted_by')->nullable();
                $table->timestamp('submitted_at')->nullable();
                $table->uuid('verified_by')->nullable();
                $table->timestamp('verified_at')->nullable();
                $table->string('reject_reason', 255)->nullable();
                $table->unsignedBigInteger('reverses_id')->nullable();
                $table->unsignedBigInteger('reversed_by_id')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'reference']);
                $table->unique(['owner_id', 'receipt_number']);
                $table->index(['owner_id', 'status']);
                $table->index(['owner_id', 'member_id', 'category']);
                $table->index(['owner_id', 'external_ref']);
            });
        }

        if (!Schema::hasTable('group_audit_log')) {
            Schema::create('group_audit_log', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->uuid('user_id')->nullable();
                $table->string('action', 60);
                $table->string('subject_type', 40)->nullable();
                $table->unsignedBigInteger('subject_id')->nullable();
                $table->string('summary', 500);
                $table->timestamp('created_at')->nullable()->index();
            });
        }
    }

    public function down(): void
    {
        foreach (['group_audit_log', 'group_transactions', 'group_member_events', 'group_dependants', 'group_members', 'group_settings'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
