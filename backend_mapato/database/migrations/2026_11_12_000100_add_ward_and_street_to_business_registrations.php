<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Where a business is, down to the ward and the street or village (chosen from the imported Tanzania locations, or typed when the
 * list has nothing for the place). The region and district were already kept.
 */
return new class extends Migration {
    public function up(): void
    {
        Schema::table('business_registrations', function (Blueprint $table) {
            $table->string('ward', 100)->nullable()->after('district');
            $table->string('street', 100)->nullable()->after('ward');
        });
    }

    public function down(): void
    {
        Schema::table('business_registrations', function (Blueprint $table) {
            $table->dropColumn(['ward', 'street']);
        });
    }
};
