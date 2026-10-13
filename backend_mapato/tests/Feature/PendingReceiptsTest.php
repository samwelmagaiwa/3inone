<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * GET /api/admin/receipts/pending: which payments are listed, the outstanding
 * debt shown per driver, and a query count that does not grow with the list.
 */
class PendingReceiptsTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->admin = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'transport');
    }

    private function driver(string $name): string
    {
        // A driver belongs to the account of whoever created them (as the app does).
        $user = User::factory()->create([
            'name' => $name, 'role' => 'driver', 'is_active' => true, 'created_by' => $this->admin->id,
        ]);
        $id = (string) Str::uuid();
        DB::table('drivers')->insert([
            'id' => $id, 'user_id' => $user->id, 'license_number' => 'LIC-' . Str::random(8),
            'license_expiry' => now()->addYear()->toDateString(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    private function payment(string $driverId, string $status, ?string $receiptStatus, float $amount = 1000): int
    {
        return DB::table('payments')->insertGetId([
            'reference_number' => 'PAY-' . Str::random(10), 'driver_id' => $driverId, 'amount' => $amount,
            'covers_days' => json_encode(['2026-03-01']), 'status' => $status, 'receipt_status' => $receiptStatus,
            'payment_date' => now(), 'recorded_by' => $this->admin->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function debt(string $driverId, string $date, float $expected, float $paid, bool $isPaid): void
    {
        DB::table('debt_records')->insert([
            'driver_id' => $driverId, 'earning_date' => $date, 'expected_amount' => $expected,
            'paid_amount' => $paid, 'is_paid' => $isPaid, 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function pending(): array
    {
        $this->app['auth']->forgetGuards();
        $token = $this->admin->createToken('t')->plainTextToken;

        return $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/admin/receipts/pending')
            ->assertOk()
            ->json('data.pending_receipts');
    }

    public function test_lists_only_completed_payments_awaiting_a_receipt_with_each_drivers_debt(): void
    {
        $a = $this->driver('Driver A');
        $b = $this->driver('Driver B');

        $pendingId = $this->payment($a, 'completed', 'pending');
        $nullId = $this->payment($a, 'completed', null);
        $this->payment($a, 'completed', 'generated');   // receipt already made
        $this->payment($a, 'cancelled', null);          // not a completed payment
        $bId = $this->payment($b, 'completed', 'pending');

        $this->debt($a, '2026-03-03', 1000, 250, false);
        $this->debt($a, '2026-03-02', 1000, 0, false);
        $this->debt($a, '2026-03-01', 1000, 1000, true);   // settled: not counted

        $rows = collect($this->pending())->keyBy('payment_id');

        $this->assertEqualsCanonicalizing(
            [(string) $pendingId, (string) $nullId, (string) $bId],
            $rows->keys()->all(),
        );

        $forA = $rows[(string) $pendingId];
        $this->assertEquals(1750.0, $forA['remaining_debt_total']);          // 750 + 1000
        $this->assertTrue($forA['has_remaining_debt']);
        $this->assertSame(2, $forA['unpaid_days_count']);
        $this->assertSame(['2026-03-02', '2026-03-03'], $forA['unpaid_dates']); // oldest first
        $this->assertSame('Driver A', $forA['driver']['name']);

        $forB = $rows[(string) $bId];
        $this->assertEquals(0.0, $forB['remaining_debt_total']);
        $this->assertFalse($forB['has_remaining_debt']);
        $this->assertSame([], $forB['unpaid_dates']);
    }

    public function test_query_count_does_not_grow_with_the_number_of_payments(): void
    {
        foreach (['One', 'Two'] as $n) {
            $id = $this->driver("Driver {$n}");
            $this->payment($id, 'completed', 'pending');
            $this->debt($id, '2026-03-01', 500, 0, false);
        }

        DB::enableQueryLog();
        $this->pending();
        $few = count(DB::getQueryLog());

        foreach (['Three', 'Four', 'Five', 'Six'] as $n) {
            $id = $this->driver("Driver {$n}");
            $this->payment($id, 'completed', 'pending');
            $this->payment($id, 'completed', 'pending');
            $this->debt($id, '2026-03-01', 500, 0, false);
        }

        DB::flushQueryLog();
        $rows = $this->pending();
        $many = count(DB::getQueryLog());

        $this->assertCount(10, $rows);
        $this->assertSame($few, $many, "Queries grew from {$few} to {$many} as payments were added (N+1).");
    }
}
