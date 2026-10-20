<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The salon's equipment (dryers, steamers, chairs...) with its upkeep, and online booking: where a client books from a
     * page of their own (the business's booking address, whether it is on) and how an appointment came in. Each step
     * checks first (MySQL has no transactional DDL); the new tables carry their own `service` column.
     */
    public function up(): void
    {
        if (!Schema::hasTable('inventory_equipment')) {
            Schema::create('inventory_equipment', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->string('name', 120);
                $table->string('kind', 40)->nullable();
                $table->string('serial', 80)->nullable();
                $table->date('bought_on')->nullable();
                $table->decimal('cost', 14, 2)->default(0);
                // working | repair | retired
                $table->string('status', 10)->default('working')->index();
                $table->date('next_service_on')->nullable();
                $table->string('notes', 255)->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_equipment_logs')) {
            Schema::create('inventory_equipment_logs', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('equipment_id')->index();
                // maintenance | repair
                $table->string('kind', 12);
                $table->date('done_on');
                $table->decimal('cost', 14, 2)->default(0);
                $table->string('description', 255);
                // The expense this was recorded as (so the money is in the books once).
                $table->unsignedBigInteger('expense_id')->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (Schema::hasTable('businesses')) {
            Schema::table('businesses', function (Blueprint $table) {
                if (!Schema::hasColumn('businesses', 'booking_slug')) {
                    // The address of the page a client books from: /book/<slug>. Unique across all salons.
                    $table->string('booking_slug', 60)->nullable()->unique();
                }
                if (!Schema::hasColumn('businesses', 'online_booking')) {
                    $table->boolean('online_booking')->default(false);
                }
            });
        }

        if (Schema::hasTable('inventory_appointments') && !Schema::hasColumn('inventory_appointments', 'source')) {
            Schema::table('inventory_appointments', function (Blueprint $table) {
                // staff (booked at the salon) | online (booked by the client)
                $table->string('source', 10)->default('staff');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('inventory_equipment_logs');
        Schema::dropIfExists('inventory_equipment');

        if (Schema::hasTable('businesses')) {
            if (Schema::hasColumn('businesses', 'booking_slug')) {
                Schema::table('businesses', function (Blueprint $t) {
                    $t->dropUnique(['booking_slug']);
                    $t->dropColumn('booking_slug');
                });
            }
            if (Schema::hasColumn('businesses', 'online_booking')) {
                Schema::table('businesses', fn (Blueprint $t) => $t->dropColumn('online_booking'));
            }
        }
        if (Schema::hasTable('inventory_appointments') && Schema::hasColumn('inventory_appointments', 'source')) {
            Schema::table('inventory_appointments', fn (Blueprint $t) => $t->dropColumn('source'));
        }
    }
};
