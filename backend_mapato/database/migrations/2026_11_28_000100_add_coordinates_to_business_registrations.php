<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Where the business really is: the applicant taps "capture my location" on the registration form, standing at the business, and the
     * super admin sees the point (and a map link) when deciding. Optional; nothing existing changes. Checks first (MySQL has no
     * transactional DDL).
     */
    public function up(): void
    {
        if (Schema::hasTable('business_registrations') && !Schema::hasColumn('business_registrations', 'latitude')) {
            Schema::table('business_registrations', function (Blueprint $table) {
                $table->decimal('latitude', 10, 7)->nullable();
                $table->decimal('longitude', 10, 7)->nullable();
                $table->decimal('location_accuracy_m', 8, 1)->nullable();
                $table->timestamp('location_captured_at')->nullable();
            });
        }
    }

    public function down(): void
    {
        foreach (['latitude', 'longitude', 'location_accuracy_m', 'location_captured_at'] as $column) {
            if (Schema::hasTable('business_registrations') && Schema::hasColumn('business_registrations', $column)) {
                Schema::table('business_registrations', fn (Blueprint $t) => $t->dropColumn($column));
            }
        }
    }
};
