<?php

namespace App\Database;

use App\Database\Concerns\CreatesTenantQueries;
use Illuminate\Database\SQLiteConnection;

/** SQLite connection (the test suite) with the same per-business scoping as production MySQL. */
class TenantSQLiteConnection extends SQLiteConnection
{
    use CreatesTenantQueries;

    protected function getDefaultQueryGrammar()
    {
        return new TenantSQLiteGrammar($this);
    }
}
