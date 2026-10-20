<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The salon's people and their cash: when each works (days and hours), days off, who came in and for how long, and
     * each shift's cash (what the till should hold against what was handed over). Each step checks first (MySQL has no
     * transactional DDL); the new tables carry their own `service` column, as they are made after the migration that
     * split the shop's books from the salon's.
     */
    public function up(): void
    {
        if (Schema::hasTable('inventory_staff_profiles')) {
            Schema::table('inventory_staff_profiles', function (Blueprint $table) {
                if (!Schema::hasColumn('inventory_staff_profiles', 'work_days')) {
                    // The weekdays they work, "1,2,3,4,5,6" (Monday is 1); empty = not said.
                    $table->string('work_days', 20)->nullable();
                }
                if (!Schema::hasColumn('inventory_staff_profiles', 'shift_start')) {
                    $table->string('shift_start', 5)->nullable();
                }
                if (!Schema::hasColumn('inventory_staff_profiles', 'shift_end')) {
                    $table->string('shift_end', 5)->nullable();
                }
            });
        }

        if (!Schema::hasTable('inventory_staff_days_off')) {
            Schema::create('inventory_staff_days_off', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->uuid('staff_id')->index();
                $table->date('off_on');
                $table->string('reason', 120)->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'service', 'staff_id', 'off_on'], 'one_day_off_per_person');
            });
        }

        if (!Schema::hasTable('inventory_attendance')) {
            Schema::create('inventory_attendance', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->uuid('staff_id');
                $table->string('staff_name', 120)->nullable();
                $table->date('work_date');
                $table->dateTime('clock_in');
                $table->dateTime('clock_out')->nullable();
                $table->string('note', 160)->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->index(['staff_id', 'work_date']);
            });
        }

        if (!Schema::hasTable('inventory_salon_shifts')) {
            Schema::create('inventory_salon_shifts', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->uuid('staff_id');
                $table->string('staff_name', 120)->nullable();
                $table->dateTime('opened_at');
                $table->decimal('opening_float', 14, 2)->default(0);
                $table->dateTime('closed_at')->nullable();
                // What the person says they hold and hand over, what the till should hold, and the difference.
                $table->decimal('counted_cash', 14, 2)->nullable();
                $table->decimal('expected_cash', 14, 2)->nullable();
                $table->decimal('difference', 14, 2)->nullable();
                // The cash, mobile money and bank taken during the shift: {cash, mobile_money, bank_transfer}.
                $table->json('collected')->nullable();
                $table->uuid('handed_to_id')->nullable();
                $table->string('handed_to_name', 120)->nullable();
                $table->string('note', 160)->nullable();
                $table->string('status', 10)->default('open')->index();
                $table->timestamps();
                $table->index(['staff_id', 'status']);
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('inventory_salon_shifts');
        Schema::dropIfExists('inventory_attendance');
        Schema::dropIfExists('inventory_staff_days_off');

        if (Schema::hasTable('inventory_staff_profiles')) {
            foreach (['work_days', 'shift_start', 'shift_end'] as $column) {
                if (Schema::hasColumn('inventory_staff_profiles', $column)) {
                    Schema::table('inventory_staff_profiles', fn (Blueprint $t) => $t->dropColumn($column));
                }
            }
        }
    }
};
