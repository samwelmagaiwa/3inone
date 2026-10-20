<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * What a salon remembers about its clients: birthday, what they like, who sent them, photos of past styles (only
     * with their consent), the messages sent to groups of them, and which birthdays have been wished this year.
     * Each step checks first (MySQL has no transactional DDL); the new tables carry their own `service` column.
     */
    public function up(): void
    {
        if (Schema::hasTable('inventory_customers')) {
            Schema::table('inventory_customers', function (Blueprint $table) {
                if (!Schema::hasColumn('inventory_customers', 'birthday')) {
                    $table->date('birthday')->nullable();
                }
                if (!Schema::hasColumn('inventory_customers', 'preferences')) {
                    // {hairstyle, colour, nails, allergies} as JSON text.
                    $table->text('preferences')->nullable();
                }
                if (!Schema::hasColumn('inventory_customers', 'referred_by')) {
                    $table->unsignedBigInteger('referred_by')->nullable()->index();
                }
            });
        }

        if (!Schema::hasTable('inventory_client_photos')) {
            Schema::create('inventory_client_photos', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('customer_id')->index();
                $table->string('path', 255);
                $table->string('caption', 120)->nullable();
                // A photo is only ever kept with the client's say-so.
                $table->boolean('consent')->default(false);
                $table->date('taken_on');
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_campaigns')) {
            Schema::create('inventory_campaigns', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->string('name', 120);
                $table->string('segment', 30);
                $table->text('message');
                $table->unsignedInteger('recipients')->default(0);
                $table->unsignedInteger('sent')->default(0);
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_birthday_wishes')) {
            Schema::create('inventory_birthday_wishes', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('customer_id');
                $table->unsignedSmallInteger('year');
                $table->timestamp('sent_at')->nullable();
                $table->timestamps();
                // One wish per client per year, even if two runs overlap.
                $table->unique(['owner_id', 'service', 'customer_id', 'year'], 'one_birthday_wish_a_year');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('inventory_birthday_wishes');
        Schema::dropIfExists('inventory_campaigns');
        Schema::dropIfExists('inventory_client_photos');

        if (Schema::hasTable('inventory_customers')) {
            foreach (['birthday', 'preferences', 'referred_by'] as $column) {
                if (Schema::hasColumn('inventory_customers', $column)) {
                    if ($column === 'referred_by') {
                        Schema::table('inventory_customers', fn (Blueprint $t) => $t->dropIndex(['referred_by']));
                    }
                    Schema::table('inventory_customers', fn (Blueprint $t) => $t->dropColumn($column));
                }
            }
        }
    }
};
