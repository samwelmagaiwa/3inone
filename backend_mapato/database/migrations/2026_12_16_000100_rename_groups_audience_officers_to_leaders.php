<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * In a group everyone is a member; some are elected leaders. A notice or a text "to the officers" was stored with the audience "officers":
 * it is now "leaders". An app from before the change that still says "officers" is understood by the server and means the same.
 */
return new class extends Migration
{
    public function up(): void
    {
        foreach (['group_announcements', 'group_messages'] as $table) {
            if (Schema::hasTable($table) && Schema::hasColumn($table, 'audience')) {
                DB::table($table)->where('audience', 'officers')->update(['audience' => 'leaders']);
            }
        }
    }

    public function down(): void
    {
        foreach (['group_announcements', 'group_messages'] as $table) {
            if (Schema::hasTable($table) && Schema::hasColumn($table, 'audience')) {
                DB::table($table)->where('audience', 'leaders')->update(['audience' => 'officers']);
            }
        }
    }
};
