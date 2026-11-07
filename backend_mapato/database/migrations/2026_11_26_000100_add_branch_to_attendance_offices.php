<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * An attendance office can BE a branch: it then shows the branch's name and address and keeps only the attendance rules. Offices made
     * before this have no branch and work as they did. Checks first (MySQL has no transactional DDL).
     */
    public function up(): void
    {
        if (Schema::hasTable('inventory_attendance_offices') && !Schema::hasColumn('inventory_attendance_offices', 'branch_id')) {
            Schema::table('inventory_attendance_offices', function (Blueprint $table) {
                $table->unsignedBigInteger('branch_id')->nullable()->index();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('inventory_attendance_offices') && Schema::hasColumn('inventory_attendance_offices', 'branch_id')) {
            Schema::table('inventory_attendance_offices', function (Blueprint $table) {
                $table->dropIndex(['branch_id']);
                $table->dropColumn('branch_id');
            });
        }
    }
};
