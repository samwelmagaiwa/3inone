<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Someone who signed up with an email, phone and password and has not yet told us about their business: an "applicant". Their phone is
 * confirmed by a text code, they sign in again with email and password, and only then are they asked for the business details (which
 * creates the registration a super admin approves). The flag ends the moment that registration exists.
 */
return new class extends Migration {
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->boolean('is_applicant')->default(false)->after('phone_verified');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('is_applicant');
        });
    }
};
