<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * What clients say about the salon: a rating and a comment, or a complaint, recorded by staff or sent by the client
     * from a link in the text they got after their visit. Each step checks first (MySQL has no transactional DDL); the
     * new tables carry their own `service` column.
     */
    public function up(): void
    {
        if (!Schema::hasTable('inventory_feedback')) {
            Schema::create('inventory_feedback', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('customer_id')->nullable()->index();
                $table->unsignedBigInteger('sale_id')->nullable()->index();
                // Who served them: the stylist the feedback is about.
                $table->uuid('staff_id')->nullable()->index();
                $table->string('staff_name', 120)->nullable();
                // review | complaint
                $table->string('kind', 10)->default('review')->index();
                $table->unsignedTinyInteger('rating')->nullable();
                $table->text('message')->nullable();
                // new | resolved
                $table->string('status', 10)->default('new')->index();
                $table->string('resolution', 255)->nullable();
                $table->uuid('resolved_by')->nullable();
                $table->timestamp('resolved_at')->nullable();
                // staff | link
                $table->string('source', 10)->default('staff');
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_feedback_requests')) {
            Schema::create('inventory_feedback_requests', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                // The secret in the link. Found WITHOUT a signed-in business, so it is unique across all of them.
                $table->string('token', 64)->unique();
                $table->unsignedBigInteger('customer_id')->nullable();
                $table->unsignedBigInteger('sale_id')->nullable()->unique();
                $table->uuid('staff_id')->nullable();
                $table->string('staff_name', 120)->nullable();
                $table->timestamp('expires_at');
                $table->timestamp('used_at')->nullable();
                $table->timestamps();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('inventory_feedback_requests');
        Schema::dropIfExists('inventory_feedback');
    }
};
