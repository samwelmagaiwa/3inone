<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Salon appointments, plus two things a service can say: who may do it, and its price options (short, medium or
     * long hair...). Every step checks first (MySQL has no transactional DDL).
     *
     * The appointments table is made with its own `service` column: it is created after the one that split the shop's
     * books from the salon's, so that migration never saw it.
     */
    public function up(): void
    {
        if (!Schema::hasTable('inventory_appointments')) {
            Schema::create('inventory_appointments', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('customer_id')->nullable()->index();
                $table->string('client_name', 120);
                $table->string('client_phone', 30)->nullable();
                $table->uuid('staff_id')->nullable()->index();
                $table->string('staff_name', 120)->nullable();
                $table->dateTime('starts_at')->index();
                $table->dateTime('ends_at');
                $table->string('status', 20)->default('booked')->index();
                // [{product_id, name, price, minutes, label?}] as they were when booked.
                $table->json('services');
                $table->text('notes')->nullable();
                $table->decimal('total', 14, 2)->default(0);
                $table->timestamp('reminder_sent_at')->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        Schema::table('inventory_products', function (Blueprint $table) {
            if (!Schema::hasColumn('inventory_products', 'staff_ids')) {
                // Who may do this service (a list of account ids); empty = anyone.
                $table->json('staff_ids')->nullable();
            }
            if (!Schema::hasColumn('inventory_products', 'price_options')) {
                // [{label, price}]: the same service at different prices (short / medium / long hair).
                $table->json('price_options')->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('inventory_appointments');

        Schema::table('inventory_products', function (Blueprint $table) {
            foreach (['staff_ids', 'price_options'] as $column) {
                if (Schema::hasColumn('inventory_products', $column)) {
                    $table->dropColumn($column);
                }
            }
        });
    }
};
