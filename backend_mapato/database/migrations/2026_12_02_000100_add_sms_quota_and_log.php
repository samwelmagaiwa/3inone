<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * SMS counting and the SMS limit per business.
     *
     *   businesses.sms_used            how many SMS the business has used since its counter was last reset (kept for good)
     *   businesses.sms_limit           how many it may use; NULL = no limit (every existing business starts so: nothing changes)
     *   businesses.sms_limit_warned_at / sms_limit_reached_at   so the owner and the super admin are told once, not on every text
     *   sms_logs                       each text the business sent (to, words, parts); rows older than 3 days are deleted daily
     *   sms_daily_counts               texts per business per day, kept, so "this week" survives the 3-day clean-up
     *
     * Additive only. Checks first (MySQL has no transactional DDL).
     */
    public function up(): void
    {
        if (Schema::hasTable('businesses')) {
            Schema::table('businesses', function (Blueprint $table) {
                if (!Schema::hasColumn('businesses', 'sms_used')) {
                    $table->unsignedBigInteger('sms_used')->default(0);
                }
                if (!Schema::hasColumn('businesses', 'sms_limit')) {
                    $table->unsignedInteger('sms_limit')->nullable();
                }
                if (!Schema::hasColumn('businesses', 'sms_limit_warned_at')) {
                    $table->timestamp('sms_limit_warned_at')->nullable();
                }
                if (!Schema::hasColumn('businesses', 'sms_limit_reached_at')) {
                    $table->timestamp('sms_limit_reached_at')->nullable();
                }
            });
        }

        if (!Schema::hasTable('sms_logs')) {
            Schema::create('sms_logs', function (Blueprint $table) {
                $table->id();
                $table->uuid('business_id')->index();
                $table->string('to_phone', 32);
                $table->text('message');
                $table->unsignedSmallInteger('parts')->default(1);
                $table->string('sender', 40)->nullable();
                $table->timestamp('sent_at')->index();
            });
        }

        if (!Schema::hasTable('sms_daily_counts')) {
            Schema::create('sms_daily_counts', function (Blueprint $table) {
                $table->id();
                $table->uuid('business_id');
                $table->date('day');
                $table->unsignedInteger('messages')->default(0);
                $table->unsignedInteger('parts')->default(0);
                $table->unique(['business_id', 'day']);
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('sms_daily_counts');
        Schema::dropIfExists('sms_logs');
        foreach (['sms_used', 'sms_limit', 'sms_limit_warned_at', 'sms_limit_reached_at'] as $column) {
            if (Schema::hasTable('businesses') && Schema::hasColumn('businesses', $column)) {
                Schema::table('businesses', fn (Blueprint $t) => $t->dropColumn($column));
            }
        }
    }
};
