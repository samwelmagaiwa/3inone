<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /** A stylist asks for a day off; whoever sets the schedule approves or turns it down, and an approved one becomes a day off. */
    public function up(): void
    {
        if (!Schema::hasTable('inventory_day_off_requests')) {
            Schema::create('inventory_day_off_requests', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->uuid('staff_id')->index();
                $table->string('staff_name', 120)->nullable();
                $table->date('off_on')->index();
                $table->string('reason', 120)->nullable();
                // pending | approved | rejected
                $table->string('status', 10)->default('pending')->index();
                $table->uuid('decided_by')->nullable();
                $table->timestamp('decided_at')->nullable();
                $table->timestamps();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('inventory_day_off_requests');
    }
};
