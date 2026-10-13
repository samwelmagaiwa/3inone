<?php

namespace App\Database;

use App\Database\Concerns\ScopesTenantTables;
use Illuminate\Database\Query\Grammars\MySqlGrammar;

/** MySQL query grammar that limits registered tables to the signed-in business. */
class TenantMySqlGrammar extends MySqlGrammar
{
    use ScopesTenantTables;
}
