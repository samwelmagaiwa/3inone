<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Two things for the device checks.
     *
     * Consent: a device is registered only after the person has agreed, in the app, to what is collected (device name and model, the device's
     * own id, the network address, and the place when work starts or finishes). The moment and the wording's version are kept on the device.
     *
     * Audit: every attempt in the log now says which attendance it made (or none), the id of the device that is REGISTERED to the person, the
     * id and name of the device that was actually USED, and whether it is a "not the logged-in device" case, which an administrator then marks as
     * seen. Checks first (MySQL has no transactional DDL).
     */
    public function up(): void
    {
        $this->add('inventory_attendance_devices', 'consent_at', function (Blueprint $t) {
            $t->timestamp('consent_at')->nullable();
            $t->string('consent_version', 12)->nullable();
        });

        $this->add('inventory_attendance_checks', 'attendance_id', function (Blueprint $t) {
            $t->unsignedBigInteger('attendance_id')->nullable();
            $t->string('registered_device_uuid', 64)->nullable();
            $t->string('presented_device_uuid', 64)->nullable();
            $t->string('presented_device_name', 120)->nullable();
            // set for a device that is not the person's registered one; an administrator marks it seen
            $t->boolean('flagged')->default(false)->index();
            $t->timestamp('acknowledged_at')->nullable();
            $t->string('acknowledged_by', 64)->nullable();
        });
    }

    public function down(): void
    {
        $drop = [
            'inventory_attendance_devices' => ['consent_at', 'consent_version'],
            'inventory_attendance_checks' => ['attendance_id', 'registered_device_uuid', 'presented_device_uuid', 'presented_device_name', 'flagged', 'acknowledged_at', 'acknowledged_by'],
        ];
        foreach ($drop as $table => $columns) {
            foreach ($columns as $column) {
                if (Schema::hasTable($table) && Schema::hasColumn($table, $column)) {
                    Schema::table($table, fn (Blueprint $t) => $t->dropColumn($column));
                }
            }
        }
    }

    private function add(string $table, string $probe, callable $columns): void
    {
        if (Schema::hasTable($table) && !Schema::hasColumn($table, $probe)) {
            Schema::table($table, fn (Blueprint $t) => $columns($t));
        }
    }
};
