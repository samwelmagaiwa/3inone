<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * The salon's own roles (receptionist, cashier, hair stylist, nail technician, lash and makeup artist, accountant,
 * stock manager) have to fit in the users.role enum, like every role before them. Widening an enum only ever adds
 * values, so nothing that exists changes. (SQLite, which the tests run on, has no such enum to widen.)
 */
return new class extends Migration
{
    private const OLD = "'super_admin','admin','manager','operator','viewer','sales_officer','driver','landlord','caretaker','tenant','vendor'";

    private const NEW = "'super_admin','admin','manager','operator','viewer','sales_officer','driver','landlord','caretaker','tenant','vendor',"
        . "'receptionist','cashier','hair_stylist','nail_technician','lash_makeup_artist','accountant','stock_manager'";

    public function up(): void
    {
        if (DB::getDriverName() !== 'sqlite') {
            DB::statement('ALTER TABLE users MODIFY COLUMN role ENUM(' . self::NEW . ") NOT NULL DEFAULT 'driver'");
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() !== 'sqlite') {
            // A salon role cannot stay in a column that no longer allows it: those people become plain viewers.
            DB::table('users')->whereIn('role', ['receptionist', 'cashier', 'hair_stylist', 'nail_technician', 'lash_makeup_artist', 'accountant', 'stock_manager'])->update(['role' => 'viewer']);
            DB::statement('ALTER TABLE users MODIFY COLUMN role ENUM(' . self::OLD . ") NOT NULL DEFAULT 'driver'");
        }
    }
};
