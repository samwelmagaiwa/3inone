<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A business owner registers themselves; a super admin reviews the details
     * and assigns the services. The login (users row) is created inactive at
     * registration and switched on at approval, so a pending business can sign
     * in to nothing.
     */
    public function up(): void
    {
        Schema::create('business_registrations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('user_id')->unique();
            $table->string('business_name');
            $table->json('requested_services');
            $table->string('region', 100)->nullable();
            $table->string('district', 100)->nullable();
            $table->string('address', 500)->nullable();
            $table->string('id_number', 50)->nullable();
            $table->text('notes')->nullable();
            $table->string('status', 20)->default('pending')->index(); // pending | approved | rejected
            $table->uuid('reviewed_by')->nullable();
            $table->timestamp('reviewed_at')->nullable();
            $table->text('rejection_reason')->nullable();
            $table->timestamps();

            $table->foreign('user_id')->references('id')->on('users')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('business_registrations');
    }
};
