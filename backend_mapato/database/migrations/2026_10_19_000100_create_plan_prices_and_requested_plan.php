<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * What a plan costs, set by a super admin in the app and shown to anybody who registers.
     *
     * A plan is a number of services: basic = one, standard = two, premium = all three (config/billing.php). Its
     * price depends on how long it is paid for, so one row says "this plan, paid for this many months, costs this
     * much". A missing row means "no price set yet" and the registration form says so.
     *
     * A registration also remembers the package the applicant chose (and for how many months), so the super admin
     * knows what to collect when the 30-day trial ends.
     *
     * Re-runnable (MySQL has no transactional DDL).
     */
    public function up(): void
    {
        if (!Schema::hasTable('plan_prices')) {
            Schema::create('plan_prices', function (Blueprint $table) {
                $table->id();
                $table->string('plan', 32);
                $table->unsignedSmallInteger('months');
                $table->decimal('amount', 14, 2);
                $table->uuid('updated_by')->nullable();
                $table->timestamps();

                $table->unique(['plan', 'months'], 'plan_prices_plan_months_unique');
            });
        }

        Schema::table('business_registrations', function (Blueprint $table) {
            if (!Schema::hasColumn('business_registrations', 'requested_plan')) {
                $table->string('requested_plan', 32)->nullable();
            }
            if (!Schema::hasColumn('business_registrations', 'requested_months')) {
                $table->unsignedSmallInteger('requested_months')->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('plan_prices');

        $columns = array_values(array_filter(
            ['requested_plan', 'requested_months'],
            fn (string $c) => Schema::hasColumn('business_registrations', $c)
        ));
        if ($columns !== []) {
            Schema::table('business_registrations', function (Blueprint $table) use ($columns) {
                $table->dropColumn($columns);
            });
        }
    }
};
