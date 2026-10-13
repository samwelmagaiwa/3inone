<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * GET /api/admin/reports/device-performance: revenue/trips per device within
 * the period (income + completed only), ranked, with a constant query count.
 */
class DevicePerformanceReportTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->admin = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'transport');
    }

    /** A device driven by a driver this admin created. Returns the device id. */
    private function device(string $plate, string $driverName): string
    {
        $user = User::factory()->create([
            'name' => $driverName, 'role' => 'driver', 'is_active' => true, 'created_by' => $this->admin->id,
        ]);
        $driverId = (string) Str::uuid();
        DB::table('drivers')->insert([
            'id' => $driverId, 'user_id' => $user->id, 'license_number' => 'LIC-' . Str::random(8),
            'license_expiry' => now()->addYear()->toDateString(), 'created_at' => now(), 'updated_at' => now(),
        ]);
        $deviceId = (string) Str::uuid();
        DB::table('devices')->insert([
            'id' => $deviceId, 'driver_id' => $driverId, 'name' => "Bajaji {$plate}", 'type' => 'bajaji',
            'plate_number' => $plate, 'created_at' => now(), 'updated_at' => now(),
        ]);

        return $deviceId;
    }

    private function transaction(string $deviceId, float $amount, string $type, string $status, string $date): void
    {
        $driverId = DB::table('devices')->where('id', $deviceId)->value('driver_id');
        DB::table('transactions')->insert([
            'id' => (string) Str::uuid(), 'driver_id' => $driverId, 'device_id' => $deviceId,
            'amount' => $amount, 'type' => $type, 'category' => 'daily', 'description' => 'test',
            'status' => $status, 'transaction_date' => $date, 'reference_number' => 'REF-' . Str::random(10),
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function report(): array
    {
        $this->app['auth']->forgetGuards();
        $token = $this->admin->createToken('t')->plainTextToken;

        return $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/reports/device-performance?start_date=2026-03-01&end_date=2026-03-31')
            ->assertOk()
            ->json('data');
    }

    public function test_revenue_and_trips_count_only_completed_income_in_the_period_and_are_ranked(): void
    {
        $low = $this->device('T 111 AAA', 'Low Earner');
        $high = $this->device('T 222 BBB', 'High Earner');
        $this->device('T 333 CCC', 'Idle');                                            // no transactions at all

        $this->transaction($low, 1000, 'income', 'completed', '2026-03-10 09:00:00');
        $this->transaction($high, 4000, 'income', 'completed', '2026-03-11 09:00:00');
        $this->transaction($high, 2000, 'income', 'completed', '2026-03-12 09:00:00');
        $this->transaction($high, 999, 'expense', 'completed', '2026-03-12 10:00:00');  // not income
        $this->transaction($high, 999, 'income', 'pending', '2026-03-12 11:00:00');      // not completed
        $this->transaction($high, 999, 'income', 'completed', '2026-02-20 11:00:00');    // outside the period

        $data = $this->report();

        // Only devices with income in the period are listed, best first.
        $this->assertSame(['T 222 BBB', 'T 111 AAA'], array_column($data['devices'], 'plate_number'));
        $this->assertSame('Bajaji T 222 BBB', $data['top_performer']);

        [$best, $other] = $data['devices'];
        $this->assertEquals(6000.0, $best['revenue']);
        $this->assertSame(2, $best['trips']);
        $this->assertEquals(3000.0, $best['average_per_trip']);
        $this->assertSame('High Earner', $best['driver_name']);
        $this->assertEquals(1000.0, $other['revenue']);
        $this->assertSame(1, $other['trips']);
    }

    public function test_query_count_does_not_grow_with_the_number_of_devices(): void
    {
        foreach (['T 001 AAA', 'T 002 AAA'] as $i => $plate) {
            $this->transaction($this->device($plate, "Driver {$i}"), 100, 'income', 'completed', '2026-03-10 09:00:00');
        }

        DB::enableQueryLog();
        $this->report();
        $few = count(DB::getQueryLog());

        foreach (['T 003 AAA', 'T 004 AAA', 'T 005 AAA', 'T 006 AAA', 'T 007 AAA'] as $i => $plate) {
            $this->transaction($this->device($plate, "More {$i}"), 100, 'income', 'completed', '2026-03-10 09:00:00');
        }

        DB::flushQueryLog();
        $data = $this->report();
        $many = count(DB::getQueryLog());

        $this->assertCount(7, $data['devices']);
        $this->assertSame($few, $many, "Queries grew from {$few} to {$many} as devices were added (N+1).");
    }
}
