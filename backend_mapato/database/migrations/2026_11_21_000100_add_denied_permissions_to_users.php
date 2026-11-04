<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * What a person's role gives them can now be taken BACK for that one person: `permissions` holds what the owner added, and
     * `denied_permissions` what the owner switched off. The person's rights are the role's own, plus the first, minus the second.
     */
    public function up(): void
    {
        if (!Schema::hasColumn('users', 'denied_permissions')) {
            Schema::table('users', function (Blueprint $table) {
                $table->json('denied_permissions')->nullable()->after('permissions');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('users', 'denied_permissions')) {
            Schema::table('users', function (Blueprint $table) {
                $table->dropColumn('denied_permissions');
            });
        }
    }
};
