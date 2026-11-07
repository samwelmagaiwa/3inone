<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Attendance that is tied to a person's own approved phone (or browser): offices, who works at which, each person's registered device
     * (with its public key), the short-lived challenges the device signs, and a log of every check, good or bad. Nothing here is ever
     * deleted when a device is replaced: the old device keeps its row (status "replaced") and its history. Each step checks first (MySQL
     * has no transactional DDL).
     */
    public function up(): void
    {
        if (!Schema::hasTable('inventory_attendance_offices')) {
            Schema::create('inventory_attendance_offices', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->string('name', 120);
                $table->string('address', 200)->nullable();
                // Optional geofence: the centre, the radius in metres, and whether being outside it blocks clocking in.
                $table->decimal('latitude', 10, 7)->nullable();
                $table->decimal('longitude', 10, 7)->nullable();
                $table->unsignedInteger('radius_m')->default(150);
                $table->boolean('geofence_required')->default(false);
                $table->boolean('active')->default(true)->index();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_attendance_office_staff')) {
            Schema::create('inventory_attendance_office_staff', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('office_id')->index();
                $table->uuid('user_id')->index();
                $table->timestamps();
                $table->unique(['office_id', 'user_id'], 'one_assignment_per_office_and_person');
            });
        }

        if (!Schema::hasTable('inventory_attendance_devices')) {
            Schema::create('inventory_attendance_devices', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->uuid('user_id')->index();
                // The installation's own id (made by the app) and its public key; the private key never leaves the device.
                $table->string('device_uuid', 64)->index();
                $table->text('public_key');
                $table->string('key_algorithm', 20)->default('ES256');
                $table->string('platform', 12)->default('android');
                $table->string('name', 120)->nullable();
                $table->string('manufacturer', 80)->nullable();
                $table->string('model', 120)->nullable();
                $table->string('os_name', 40)->nullable();
                $table->string('os_version', 40)->nullable();
                $table->string('app_version', 30)->nullable();
                $table->string('user_agent', 255)->nullable();
                $table->string('ip', 45)->nullable();
                // pending | approved | rejected | blocked | replaced
                $table->string('status', 12)->default('pending')->index();
                $table->string('decision_note', 200)->nullable();
                $table->uuid('decided_by')->nullable();
                $table->timestamp('decided_at')->nullable();
                $table->timestamp('last_seen_at')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_attendance_challenges')) {
            Schema::create('inventory_attendance_challenges', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->uuid('user_id')->index();
                $table->unsignedBigInteger('device_id');
                $table->unsignedBigInteger('office_id')->nullable();
                // in | out
                $table->string('purpose', 4)->default('in');
                $table->string('nonce', 64);
                $table->timestamp('expires_at');
                $table->timestamp('used_at')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_attendance_checks')) {
            Schema::create('inventory_attendance_checks', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->uuid('user_id')->nullable()->index();
                $table->unsignedBigInteger('device_id')->nullable()->index();
                $table->unsignedBigInteger('office_id')->nullable();
                $table->string('purpose', 8)->default('in');
                // ok | device_mismatch | signature_invalid | challenge_expired | office_not_authorized | location_out_of_range | pending | rejected | blocked | ...
                $table->string('outcome', 30)->index();
                $table->string('detail', 255)->nullable();
                $table->string('ip', 45)->nullable();
                $table->string('user_agent', 255)->nullable();
                $table->decimal('latitude', 10, 7)->nullable();
                $table->decimal('longitude', 10, 7)->nullable();
                $table->decimal('accuracy_m', 8, 1)->nullable();
                $table->timestamp('location_at')->nullable();
                $table->timestamps();
            });
        }

        if (Schema::hasTable('inventory_attendance')) {
            Schema::table('inventory_attendance', function (Blueprint $table) {
                if (!Schema::hasColumn('inventory_attendance', 'office_id')) {
                    $table->unsignedBigInteger('office_id')->nullable();
                }
                if (!Schema::hasColumn('inventory_attendance', 'device_id')) {
                    $table->unsignedBigInteger('device_id')->nullable();
                }
                // verified (own approved device) | manual (an administrator, or before device checks were on)
                if (!Schema::hasColumn('inventory_attendance', 'source')) {
                    $table->string('source', 12)->default('manual');
                }
                if (!Schema::hasColumn('inventory_attendance', 'ip')) {
                    $table->string('ip', 45)->nullable();
                }
                if (!Schema::hasColumn('inventory_attendance', 'latitude')) {
                    $table->decimal('latitude', 10, 7)->nullable();
                    $table->decimal('longitude', 10, 7)->nullable();
                    $table->decimal('accuracy_m', 8, 1)->nullable();
                }
            });
        }
    }

    public function down(): void
    {
        foreach (['inventory_attendance_checks', 'inventory_attendance_challenges', 'inventory_attendance_devices', 'inventory_attendance_office_staff', 'inventory_attendance_offices'] as $t) {
            Schema::dropIfExists($t);
        }
    }
};
