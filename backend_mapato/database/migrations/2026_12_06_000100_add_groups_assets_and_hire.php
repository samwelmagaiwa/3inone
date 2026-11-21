<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Groups (Vikundi), phase 4: the group's assets and hiring them out (chairs).
     *
     *   group_assets        what the group owns: how many usable, condition, where (private), who keeps it (a member), whether it shows to
     *                       members, and its hire rate and late rate per unit per day (empty = not for hire / no late charge yet)
     *   group_asset_events  each change: keeper handed over, maintenance, damage, loss, a count corrected, retired -- never edited
     *   group_hires         a hire from request to closed: who (a member, or someone outside the group), how many, from when to when,
     *                       the charge worked out when it was approved, what was issued and returned, late and damage charges
     *   group_transactions  + hire_id (the hire a payment pays)
     */
    public function up(): void
    {
        if (!Schema::hasTable('group_assets')) {
            Schema::create('group_assets', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('code', 30);
                $table->string('name', 120);
                $table->string('category', 60)->nullable();
                $table->string('description', 255)->nullable();
                $table->unsignedInteger('quantity')->default(1);
                $table->string('condition', 12)->default('good'); // good | fair | poor
                $table->date('acquired_on')->nullable();
                $table->decimal('cost', 15, 2)->nullable();
                $table->string('location', 150)->nullable();
                $table->unsignedBigInteger('custodian_id')->nullable();
                $table->boolean('visible')->default(true);
                $table->decimal('hire_rate', 12, 2)->nullable();
                $table->decimal('late_rate', 12, 2)->nullable();
                $table->string('status', 12)->default('active'); // active | retired
                $table->timestamps();
                $table->unique(['owner_id', 'code']);
            });
        }

        if (!Schema::hasTable('group_asset_events')) {
            Schema::create('group_asset_events', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->unsignedBigInteger('asset_id')->index();
                $table->string('kind', 20); // custody | maintenance | damage | loss | adjust | retire
                $table->integer('quantity')->nullable(); // change in the usable count (- for damage or loss)
                $table->decimal('cost', 15, 2)->nullable();
                $table->string('note', 255)->nullable();
                $table->unsignedBigInteger('hire_id')->nullable();
                $table->uuid('by_user')->nullable();
                $table->timestamp('created_at')->nullable();
            });
        }

        if (!Schema::hasTable('group_hires')) {
            Schema::create('group_hires', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('reference', 20);
                $table->unsignedBigInteger('asset_id')->index();
                $table->unsignedBigInteger('member_id')->nullable()->index();
                $table->string('customer_name', 150)->nullable();
                $table->string('customer_phone', 20)->nullable();
                $table->string('purpose', 255)->nullable();
                $table->unsignedInteger('quantity');
                $table->date('start_date');
                $table->date('end_date');
                $table->unsignedSmallInteger('days');
                $table->decimal('rate', 12, 2);
                $table->decimal('amount', 15, 2);
                $table->string('status', 12)->default('requested'); // requested | approved | declined | issued | returned | closed | cancelled
                $table->string('decision_note', 255)->nullable();
                $table->uuid('decided_by')->nullable();
                $table->timestamp('decided_at')->nullable();
                $table->unsignedInteger('issued_quantity')->nullable();
                $table->string('issued_condition', 255)->nullable();
                $table->timestamp('issued_at')->nullable();
                $table->unsignedInteger('returned_quantity')->nullable();
                $table->unsignedInteger('damaged_quantity')->nullable();
                $table->unsignedInteger('missing_quantity')->nullable();
                $table->string('return_note', 255)->nullable();
                $table->date('returned_on')->nullable();
                $table->decimal('late_charge', 15, 2)->default(0);
                $table->decimal('damage_charge', 15, 2)->default(0);
                $table->string('damage_note', 255)->nullable();
                $table->string('damage_status', 12)->nullable(); // pending | decided
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'reference']);
                $table->index(['owner_id', 'status']);
                $table->index(['owner_id', 'asset_id', 'start_date', 'end_date']);
            });
        }

        if (Schema::hasTable('group_transactions') && !Schema::hasColumn('group_transactions', 'hire_id')) {
            Schema::table('group_transactions', function (Blueprint $table) {
                $table->unsignedBigInteger('hire_id')->nullable()->index();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('group_transactions') && Schema::hasColumn('group_transactions', 'hire_id')) {
            Schema::table('group_transactions', function (Blueprint $table) {
                $table->dropIndex(['hire_id']);
                $table->dropColumn('hire_id');
            });
        }
        foreach (['group_hires', 'group_asset_events', 'group_assets'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
