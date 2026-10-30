<?php

use App\Support\Tenancy\TenantTables;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Soft delete for the records an owner or admin manages from the dashboard: expenses, customers, debts from before the app, and
 * products/services. A trashed row keeps everything it had (and its history); it is only hidden, by one rule in the query grammar, from
 * every list, total and report until it is restored. Nothing is removed by this migration.
 */
return new class extends Migration {
    public function up(): void
    {
        foreach (TenantTables::SOFT_DELETES as $table) {
            if (!Schema::hasTable($table) || Schema::hasColumn($table, 'deleted_at')) {
                continue;
            }

            Schema::table($table, function (Blueprint $t) {
                $t->timestamp('deleted_at')->nullable();
                $t->string('deleted_by', 36)->nullable();
                $t->string('delete_reason', 255)->nullable();
                $t->index('deleted_at');
            });
        }

        TenantTables::forgetTrash(); // this process must not go on believing the column is missing
    }

    public function down(): void
    {
        foreach (TenantTables::SOFT_DELETES as $table) {
            if (!Schema::hasTable($table) || !Schema::hasColumn($table, 'deleted_at')) {
                continue;
            }

            Schema::table($table, function (Blueprint $t) use ($table) {
                $t->dropIndex(['deleted_at']);
                $t->dropColumn(['deleted_at', 'deleted_by', 'delete_reason']);
            });
        }

        TenantTables::forgetTrash();
    }
};
