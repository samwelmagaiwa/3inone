<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The Salon service: a fourth service next to Transport, Rental and Inventory. It runs on the same sales
     * engine as Inventory (customers, sales, payments, cash, expenses), so what it needs is small:
     *
     *  - `user_services.service_type` was a closed list of three; it becomes a plain string so a service can be
     *    added without altering the column again (the allowed names live in config/tenancy.php).
     *  - a product can be a SERVICE (no stock, a duration, and how many weeks until the client should come back);
     *  - a sale line remembers who served the client (`staff_id`, and their name as it was) and whether it was a
     *    service, so cancelling or returning it never puts "stock" back and later edits of the product change nothing;
     *  - a customer can have notes (hair type, allergies) and can ask not to be texted;
     *  - `inventory_rebook_reminders`: which "come back" text was sent for which visit, so each visit is texted once.
     *
     * Every step checks first: MySQL has no transactional DDL, so a half-finished run must be safe to repeat.
     */
    public function up(): void
    {
        Schema::table('user_services', function (Blueprint $table) {
            $table->string('service_type', 30)->change();
        });

        Schema::table('inventory_products', function (Blueprint $table) {
            if (!Schema::hasColumn('inventory_products', 'is_service')) {
                $table->boolean('is_service')->default(false);
            }
            if (!Schema::hasColumn('inventory_products', 'duration_minutes')) {
                $table->unsignedSmallInteger('duration_minutes')->nullable();
            }
            if (!Schema::hasColumn('inventory_products', 'rebook_after_weeks')) {
                $table->unsignedTinyInteger('rebook_after_weeks')->nullable();
            }
        });

        Schema::table('inventory_sale_items', function (Blueprint $table) {
            if (!Schema::hasColumn('inventory_sale_items', 'is_service')) {
                $table->boolean('is_service')->default(false);
            }
            if (!Schema::hasColumn('inventory_sale_items', 'staff_id')) {
                $table->uuid('staff_id')->nullable()->index();
            }
            if (!Schema::hasColumn('inventory_sale_items', 'staff_name')) {
                $table->string('staff_name', 120)->nullable();
            }
        });

        Schema::table('inventory_customers', function (Blueprint $table) {
            if (!Schema::hasColumn('inventory_customers', 'notes')) {
                $table->text('notes')->nullable();
            }
            if (!Schema::hasColumn('inventory_customers', 'sms_opt_out')) {
                $table->boolean('sms_opt_out')->default(false);
            }
        });

        if (!Schema::hasTable('inventory_rebook_reminders')) {
            Schema::create('inventory_rebook_reminders', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->unsignedBigInteger('customer_id');
                $table->unsignedBigInteger('sale_id')->nullable();
                // The day of the visit this text was about: one text per visit.
                $table->date('visit_on');
                $table->unsignedTinyInteger('weeks');
                $table->timestamp('sent_at')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'customer_id', 'visit_on'], 'rebook_once_per_visit');
            });
        }
    }

    /**
     * Takes back what was added. `user_services.service_type` stays a string: turning it back into a closed list
     * could fail on a row that already says "salon", and a string holds the three old names just as well.
     */
    public function down(): void
    {
        Schema::dropIfExists('inventory_rebook_reminders');

        Schema::table('inventory_customers', function (Blueprint $table) {
            foreach (['notes', 'sms_opt_out'] as $column) {
                if (Schema::hasColumn('inventory_customers', $column)) {
                    $table->dropColumn($column);
                }
            }
        });

        Schema::table('inventory_sale_items', function (Blueprint $table) {
            if (Schema::hasColumn('inventory_sale_items', 'staff_id')) {
                $table->dropIndex(['staff_id']);
            }
            foreach (['is_service', 'staff_id', 'staff_name'] as $column) {
                if (Schema::hasColumn('inventory_sale_items', $column)) {
                    $table->dropColumn($column);
                }
            }
        });

        Schema::table('inventory_products', function (Blueprint $table) {
            foreach (['is_service', 'duration_minutes', 'rebook_after_weeks'] as $column) {
                if (Schema::hasColumn('inventory_products', $column)) {
                    $table->dropColumn($column);
                }
            }
        });
    }
};
