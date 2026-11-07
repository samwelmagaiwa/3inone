<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Where people really are when they start work. The administrator captures a reference place with their own phone: one for the whole office,
     * and optionally one for a single person (it wins over the office's). At every start the server measures the distance from that place and
     * keeps the verdict (at work / away / no location / old location / weak signal / fake location) next to the attendance and in the log.
     * Checks first (MySQL has no transactional DDL).
     */
    public function up(): void
    {
        $this->add('inventory_attendance_offices', function (Blueprint $t) {
            $t->timestamp('captured_at')->nullable();
            $t->string('captured_by', 64)->nullable();
            $t->decimal('capture_accuracy_m', 8, 1)->nullable();
        }, 'captured_at');

        $this->add('inventory_attendance_office_staff', function (Blueprint $t) {
            $t->decimal('latitude', 10, 7)->nullable();
            $t->decimal('longitude', 10, 7)->nullable();
            $t->unsignedInteger('radius_m')->nullable();
            $t->timestamp('captured_at')->nullable();
            $t->string('captured_by', 64)->nullable();
            $t->decimal('capture_accuracy_m', 8, 1)->nullable();
        }, 'captured_at');

        foreach (['inventory_attendance', 'inventory_attendance_checks'] as $table) {
            $this->add($table, function (Blueprint $t) {
                $t->decimal('distance_m', 10, 1)->nullable();
                $t->string('place_status', 20)->nullable();
                $t->string('place_reference', 10)->nullable();
                $t->boolean('mocked')->default(false);
            }, 'place_status');
        }
    }

    public function down(): void
    {
        foreach ([
            'inventory_attendance_offices' => ['captured_at', 'captured_by', 'capture_accuracy_m'],
            'inventory_attendance_office_staff' => ['latitude', 'longitude', 'radius_m', 'captured_at', 'captured_by', 'capture_accuracy_m'],
            'inventory_attendance' => ['distance_m', 'place_status', 'place_reference', 'mocked'],
            'inventory_attendance_checks' => ['distance_m', 'place_status', 'place_reference', 'mocked'],
        ] as $table => $columns) {
            foreach ($columns as $column) {
                if (Schema::hasTable($table) && Schema::hasColumn($table, $column)) {
                    Schema::table($table, fn (Blueprint $t) => $t->dropColumn($column));
                }
            }
        }
    }

    private function add(string $table, callable $columns, string $probe): void
    {
        if (Schema::hasTable($table) && !Schema::hasColumn($table, $probe)) {
            Schema::table($table, fn (Blueprint $t) => $columns($t));
        }
    }
};
