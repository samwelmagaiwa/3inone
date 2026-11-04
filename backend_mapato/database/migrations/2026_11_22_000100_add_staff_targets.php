<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /** What the owner expects each stylist to bring in for a month, so the results can say how close they are. One row per person per month. */
    public function up(): void
    {
        if (!Schema::hasTable('inventory_staff_targets')) {
            Schema::create('inventory_staff_targets', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->uuid('staff_id')->index();
                $table->char('month', 7);
                $table->decimal('revenue_target', 14, 2);
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'staff_id', 'month'], 'one_target_per_person_per_month');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('inventory_staff_targets');
    }
};
