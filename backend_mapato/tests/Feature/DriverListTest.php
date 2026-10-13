<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * GET /api/admin/drivers: figures per driver, agreement status that never
 * leaks between drivers, and a query count that does not grow with the page.
 */
class DriverListTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    private string $deviceId;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'transport');

        // Transactions need a device to point at; one shared device is enough.
        $this->deviceId = (string) Str::uuid();
        DB::table('devices')->insert([
            'id' => $this->deviceId, 'name' => 'Test bajaji', 'type' => 'bajaji',
            'plate_number' => 'T 123 ABC', 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function driver(string $name, ?User $owner = null): string
    {
        $user = User::factory()->create([
            'name' => $name, 'role' => 'driver', 'is_active' => true,
            'created_by' => ($owner ?? $this->admin)->id,
        ]);
        $id = (string) Str::uuid();
        DB::table('drivers')->insert([
            'id' => $id, 'user_id' => $user->id, 'license_number' => 'LIC-' . Str::random(8),
            'license_expiry' => now()->addYear()->toDateString(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    private function transaction(string $driverId, float $amount, string $type, string $status, string $date): void
    {
        DB::table('transactions')->insert([
            'id' => (string) Str::uuid(), 'driver_id' => $driverId, 'device_id' => $this->deviceId,
            'amount' => $amount, 'type' => $type, 'category' => 'daily', 'description' => 'test',
            'status' => $status, 'transaction_date' => $date, 'reference_number' => 'REF-' . Str::random(10),
            'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function agreement(string $driverId, string $status): void
    {
        DB::table('driver_agreements')->insert([
            'id' => (string) Str::uuid(), 'driver_id' => $driverId, 'agreement_type' => 'dei_waka',
            'start_date' => now()->toDateString(), 'kiasi_cha_makubaliano' => 1000, 'payment_frequencies' => '[]',
            'status' => $status, 'created_by' => $this->admin->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function list(int $limit = 50): array
    {
        $this->app['auth']->forgetGuards();
        $token = $this->admin->createToken('t')->plainTextToken;

        $response = $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson("/api/admin/drivers?limit={$limit}")
            ->assertOk();

        return collect($response->json('data.data'))->keyBy('name')->all();
    }

    public function test_figures_and_agreement_status_are_computed_per_driver(): void
    {
        $a = $this->driver('Driver A');
        $this->driver('Driver B');              // no activity at all
        $c = $this->driver('Driver C');

        $this->transaction($a, 1000, 'income', 'completed', '2026-03-01 10:00:00');
        $this->transaction($a, 2000, 'income', 'completed', '2026-03-05 09:30:00');
        $this->transaction($a, 500, 'expense', 'completed', '2026-03-06 08:00:00');   // not income
        $this->transaction($a, 700, 'income', 'pending', '2026-03-07 08:00:00');       // not completed
        $this->agreement($a, 'active');
        $this->agreement($c, 'terminated');                                           // neither active nor completed

        // Another admin's driver with a completed agreement must not rub off on A/B/C.
        $other = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'transport');
        $this->agreement($this->driver('Elsewhere', $other), 'completed');

        $rows = $this->list();

        $this->assertCount(3, $rows);

        $this->assertEquals(3000.0, $rows['Driver A']['total_payments']);
        $this->assertSame(3, $rows['Driver A']['trips_completed']);     // every completed transaction
        $this->assertStringStartsWith('2026-03-05', $rows['Driver A']['last_payment']);
        $this->assertTrue($rows['Driver A']['has_completed_agreement']);
        $this->assertSame('active', $rows['Driver A']['agreement_status']);

        $this->assertEquals(0.0, $rows['Driver B']['total_payments']);
        $this->assertSame(0, $rows['Driver B']['trips_completed']);
        $this->assertNull($rows['Driver B']['last_payment']);
        $this->assertFalse($rows['Driver B']['has_completed_agreement']);
        $this->assertNull($rows['Driver B']['agreement_status']);

        $this->assertFalse($rows['Driver C']['has_completed_agreement']);
    }

    public function test_query_count_does_not_grow_with_the_number_of_drivers(): void
    {
        foreach (['One', 'Two', 'Three'] as $n) {
            $id = $this->driver("Driver {$n}");
            $this->transaction($id, 100, 'income', 'completed', '2026-03-01 10:00:00');
        }

        DB::enableQueryLog();
        $this->list();
        $few = count(DB::getQueryLog());

        foreach (['Four', 'Five', 'Six', 'Seven', 'Eight'] as $n) {
            $id = $this->driver("Driver {$n}");
            $this->transaction($id, 100, 'income', 'completed', '2026-03-01 10:00:00');
        }

        DB::flushQueryLog();
        $rows = $this->list();
        $many = count(DB::getQueryLog());

        $this->assertCount(8, $rows);
        $this->assertSame($few, $many, "Queries grew from {$few} to {$many} as drivers were added (N+1).");
    }

    public function test_limit_is_bounded(): void
    {
        $this->driver('Only Driver');

        $this->assertCount(1, $this->list(limit: 0));        // 0 / junk falls back instead of dividing by zero
        $this->assertCount(1, $this->list(limit: 100000));   // huge is clamped, not honoured
    }
}
