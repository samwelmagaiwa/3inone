<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The owner's master switch for the business's text messages: while `sms_paused` is true nothing the business sends goes out
     * (receipts, reminders, summaries, campaigns, rent texts), until the owner turns it back on. Nothing is deleted: every other SMS
     * setting stays as it was. Additive and off by default, so nothing existing changes. Checks first (MySQL has no transactional DDL).
     */
    public function up(): void
    {
        if (Schema::hasTable('businesses') && !Schema::hasColumn('businesses', 'sms_paused')) {
            Schema::table('businesses', function (Blueprint $table) {
                $table->boolean('sms_paused')->default(false);
                $table->timestamp('sms_paused_at')->nullable();
                $table->string('sms_paused_by', 64)->nullable();
            });
        }
    }

    public function down(): void
    {
        foreach (['sms_paused', 'sms_paused_at', 'sms_paused_by'] as $column) {
            if (Schema::hasTable('businesses') && Schema::hasColumn('businesses', $column)) {
                Schema::table('businesses', fn (Blueprint $t) => $t->dropColumn($column));
            }
        }
    }
};
