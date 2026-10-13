<?php

namespace App\Providers;

use App\Database\TenantSQLiteConnection;
use Illuminate\Database\Connection;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\ServiceProvider;

/**
 * Wires the per-business query scope (see App\Support\Tenancy\TenantTables) into
 * the database connections.
 *
 * MySQL is handled by MySQL57ServiceProvider / MySqlConnection57, which now
 * carries the tenant grammar and builder. SQLite -- the test suite's database --
 * gets the same behaviour here, so the tests exercise the code that runs in
 * production.
 */
class TenancyServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        Connection::resolverFor('sqlite', function ($connection, $database, $prefix, $config) {
            return new TenantSQLiteConnection($connection, $database, $prefix, $config);
        });
    }

    public function boot(): void
    {
        // SERVICE_ENFORCEMENT=false switches off the check that a business may only use the
        // services it was given. It exists for emergencies; left on by mistake in production
        // it would quietly let every business into every service, so say so loudly, every start.
        if ($this->app->isProduction() && !config('tenancy.enforce_services', true)) {
            Log::critical('SERVICE_ENFORCEMENT is OFF in production: businesses can use services they were never given. Remove it from the environment.');
        }
    }
}
