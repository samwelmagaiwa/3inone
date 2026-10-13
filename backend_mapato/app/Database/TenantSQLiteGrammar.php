<?php

namespace App\Database;

use App\Database\Concerns\ScopesTenantTables;
use Illuminate\Database\Query\Grammars\SQLiteGrammar;

/** SQLite query grammar (used by the test suite) that limits registered tables to the signed-in business. */
class TenantSQLiteGrammar extends SQLiteGrammar
{
    use ScopesTenantTables;
}
