<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * What a business has paid, and which reminders it has already been sent.
     *
     * `business_payments` is the ledger behind a business's plan: every payment a super admin records
     * says when it was paid, how much, and which period it bought (period_start .. period_end, and
     * period_end is the new `valid_until`). The owner reads it as "my subscription".
     *
     * `billing_reminders` makes the daily reminder job safe to run any number of times: a reminder is
     * identified by (business, the valid_until DATE it is about, its kind), so each one goes out once,
     * and a renewal (a new valid_until) starts a fresh set.
     *
     * Neither table has a foreign key: a payment record must outlive anything, and nothing here may
     * ever block or be removed with an account.
     */
    public function up(): void
    {
        if (!Schema::hasTable('business_payments')) {
            Schema::create('business_payments', function (Blueprint $table) {
                $table->id();
                $table->uuid('business_id');
                $table->decimal('amount', 14, 2);
                $table->string('currency', 8)->default('TZS');
                $table->string('method', 30)->nullable();
                $table->string('reference', 100)->nullable();
                $table->string('plan', 32);
                $table->dateTime('period_start');
                $table->dateTime('period_end');
                $table->dateTime('paid_at');
                $table->uuid('recorded_by')->nullable();
                $table->string('note', 500)->nullable();
                $table->timestamps();

                $table->index(['business_id', 'paid_at']);
            });
        }

        if (!Schema::hasTable('billing_reminders')) {
            Schema::create('billing_reminders', function (Blueprint $table) {
                $table->id();
                $table->uuid('business_id');
                $table->date('valid_until_date');
                $table->string('kind', 16);
                $table->dateTime('sent_at');
                $table->timestamps();

                $table->unique(['business_id', 'valid_until_date', 'kind'], 'billing_reminders_once');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('billing_reminders');
        Schema::dropIfExists('business_payments');
    }
};
