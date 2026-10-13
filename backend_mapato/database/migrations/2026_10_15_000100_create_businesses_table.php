<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The business itself.
     *
     * Until now a "business" was only an idea: the account head's user row plus everyone that
     * head created. Its name lived on the registration form and nowhere else, so receipts and
     * text messages could not say whose they were. This is the record of it.
     *
     * `owner_id` is the account head's user id -- the same value the inventory tables carry in
     * their own `owner_id` and that TenantContext calls "the business" -- so the tenancy
     * contract is untouched: nothing is scoped by this table's id, only by that owner.
     *
     * There is deliberately no foreign key to users: a business row must never block, or be
     * removed with, an account (accounts are never deleted here).
     *
     * `plan` and `valid_until` are the billing fields. `valid_until` null means "never expires".
     */
    public function up(): void
    {
        Schema::create('businesses', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('owner_id')->unique();
            $table->string('name');
            $table->string('address', 500)->nullable();
            $table->string('tin', 20)->nullable();
            $table->string('phone', 30)->nullable();
            $table->string('email')->nullable();
            $table->string('logo_path')->nullable();
            $table->string('plan', 32)->default('free');
            $table->dateTime('valid_until')->nullable();
            $table->timestamps();

            $table->index(['plan', 'valid_until']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('businesses');
    }
};
