<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * A group member's sign-in (Vikundi) has the role `group_member`, which has to fit in the users.role enum like every role before it. Without
 * this, giving a member a sign-in failed on MariaDB ("Data truncated for column 'role'") -- SQLite, which the tests run on, has no such enum.
 * Widening an enum only ever adds a value, so nothing that exists changes.
 */
return new class extends Migration
{
    private const OLD = "'super_admin','admin','manager','operator','viewer','sales_officer','driver','landlord','caretaker','tenant','vendor',"
        . "'receptionist','cashier','hair_stylist','nail_technician','lash_makeup_artist','accountant','stock_manager'";

    private const NEW = self::OLD . ",'group_member'";

    public function up(): void
    {
        if (DB::getDriverName() !== 'sqlite') {
            DB::statement('ALTER TABLE users MODIFY COLUMN role ENUM(' . self::NEW . ") NOT NULL DEFAULT 'driver'");
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'sqlite') {
            // A member's sign-in cannot stay in a column that no longer allows it: those people become plain viewers.
            DB::table('users')->where('role', 'group_member')->update(['role' => 'viewer']);
            DB::statement('ALTER TABLE users MODIFY COLUMN role ENUM(' . self::OLD . ") NOT NULL DEFAULT 'driver'");
        }
    }
};
