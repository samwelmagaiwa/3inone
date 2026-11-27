<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A logo per service: a business may print one logo on its shop's receipts and another on its group's (Vikundi) receipts.
 * service key => file path on the public disk. A service without its own logo uses the business logo (logo_path).
 */
return new class extends Migration {
    public function up(): void
    {
        if (!Schema::hasColumn('businesses', 'service_logos')) {
            Schema::table('businesses', function (Blueprint $table) {
                $table->json('service_logos')->nullable()->after('logo_path');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('businesses', 'service_logos')) {
            Schema::table('businesses', function (Blueprint $table) {
                $table->dropColumn('service_logos');
            });
        }
    }
};
