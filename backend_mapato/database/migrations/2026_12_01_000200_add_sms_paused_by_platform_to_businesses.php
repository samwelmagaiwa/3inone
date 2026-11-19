<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The super admin can switch a business's texts off too. When the platform did it, the owner cannot switch them back on:
     * only a super admin can. Additive and off by default. Checks first (MySQL has no transactional DDL).
     */
    public function up(): void
    {
        if (Schema::hasTable('businesses') && !Schema::hasColumn('businesses', 'sms_paused_by_platform')) {
            Schema::table('businesses', function (Blueprint $table) {
                $table->boolean('sms_paused_by_platform')->default(false);
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('businesses') && Schema::hasColumn('businesses', 'sms_paused_by_platform')) {
            Schema::table('businesses', fn (Blueprint $t) => $t->dropColumn('sms_paused_by_platform'));
        }
    }
};
