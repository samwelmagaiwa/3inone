<?php

namespace Tests\Feature;

use App\Models\Driver;
use App\Models\User;
use App\Services\ReportService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The revenue report builds several breakdowns (by period, category, payment method, vehicle) from
 * the same filtered transactions. They used to share ONE query object, so the first breakdown's
 * `group by period` leaked into the next ones. SQLite let that through; MySQL answered
 * "Unknown column 'period' in 'group statement'", i.e. every revenue report was a 500 on the real
 * database. SQLite cannot show that failure, so this checks the SQL that is actually sent.
 */
class ReportQueriesTest extends TestCase
{
    use RefreshDatabase;

    public function test_each_revenue_breakdown_groups_by_its_own_column_only(): void
    {
        $user = User::factory()->create(['role' => 'driver', 'is_active' => true]);
        $driver = Driver::create(['user_id' => $user->id, 'license_number' => 'LIC-REP-1', 'license_expiry' => now()->addYear()->toDateString()]);

        DB::enableQueryLog();
        app(ReportService::class)->generateRevenueReport($driver, '2026-10-01', '2026-10-31');
        $queries = collect(DB::getQueryLog())->pluck('query')->all();
        DB::disableQueryLog();

        $grouped = array_values(array_filter($queries, fn (string $sql) => stripos($sql, 'group by') !== false));
        $this->assertGreaterThanOrEqual(4, count($grouped), 'period, category, payment method and vehicle');

        foreach ($grouped as $sql) {
            preg_match('/group by\s+(.+?)(?:\s+order by|\s+having|\s+limit|$)/is', $sql, $m);
            $columns = array_filter(array_map('trim', explode(',', $m[1] ?? '')));

            $this->assertCount(1, $columns, "a breakdown must group by one thing, not inherit the previous one's: {$sql}");
        }
    }
}
