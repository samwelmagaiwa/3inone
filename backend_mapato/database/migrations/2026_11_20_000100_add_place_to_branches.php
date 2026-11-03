<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Where a branch is, in the words of the Tanzania locations: region, district, ward and street or village (the "address" stays the free
     * part: the building, the landmark). Both kinds of branch get them: the shop's and salon's (inventory_branches) and the transport and
     * rental ones (business_branches). Nothing is removed or rewritten; a branch with no place simply has them empty.
     *
     * Each step checks first (MySQL has no transactional DDL).
     */
    private const TABLES = ['inventory_branches', 'business_branches'];
    private const COLUMNS = ['region', 'district', 'ward', 'street'];

    public function up(): void
    {
        foreach (self::TABLES as $table) {
            if (!Schema::hasTable($table)) {
                continue;
            }
            foreach (self::COLUMNS as $column) {
                if (!Schema::hasColumn($table, $column)) {
                    Schema::table($table, function (Blueprint $t) use ($column) {
                        $t->string($column, 80)->nullable();
                    });
                }
            }
        }
    }

    public function down(): void
    {
        foreach (self::TABLES as $table) {
            foreach (self::COLUMNS as $column) {
                if (Schema::hasTable($table) && Schema::hasColumn($table, $column)) {
                    Schema::table($table, function (Blueprint $t) use ($column) {
                        $t->dropColumn($column);
                    });
                }
            }
        }
    }
};
