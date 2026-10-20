<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Deposits on bookings and the cancellation policy: a deposit is held from the moment it is taken; when the appointment
 * ends it is put into the sale (done), kept (no-show, or cancelled too late) or given back (cancelled in time). What the
 * salon keeps is income on the day it is settled; what it still holds is the clients' money, not income.
 */
class SalonDepositsTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function salon(string $name = 'Glow Salon'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0723' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    private function at(string $when): void
    {
        Carbon::setTestNow(Carbon::parse($when, 'UTC'));
    }

    private function wash(User $as): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => 'Wash', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 10000, 'duration_minutes' => 60])->assertCreated()->json('data.id');
    }

    private function book(User $as, int $service, string $at, array $extra = [])
    {
        return $this->api($as, 'POST', '/api/inventory/salon/appointments', array_merge(['client_name' => 'Neema', 'starts_at' => $at, 'services' => [['product_id' => $service]]], $extra));
    }

    private function move(User $as, int $id, string $status)
    {
        return $this->api($as, 'POST', "/api/inventory/salon/appointments/{$id}/status", ['status' => $status]);
    }

    private function deposit(User $as, int $id): array
    {
        return $this->api($as, 'GET', '/api/inventory/salon/appointments?date=2026-10-08')->json('data.' . $this->index($as, $id) . '.deposit') ?? [];
    }

    private function index(User $as, int $id): int
    {
        $ids = array_column($this->api($as, 'GET', '/api/inventory/salon/appointments?date=2026-10-08')->json('data'), 'id');

        return (int) array_search($id, $ids, true);
    }

    public function test_a_deposit_is_held_when_taken_and_needs_to_say_how_it_was_paid(): void
    {
        $owner = $this->salon();
        $wash = $this->wash($owner);

        $res = $this->book($owner, $wash, '2026-10-08 10:00', ['deposit_amount' => 5000, 'deposit_method' => 'mpesa'])->assertCreated();
        $this->assertSame(['amount' => 5000, 'method' => 'mpesa', 'status' => 'held'], $res->json('data.deposit'));

        $this->book($owner, $wash, '2026-10-08 12:00', ['deposit_amount' => 5000])->assertStatus(422)->assertJsonValidationErrors('deposit_method');
        $this->book($owner, $wash, '2026-10-08 12:00', ['deposit_amount' => 5000, 'deposit_method' => 'bitcoin'])->assertStatus(422);
        $this->book($owner, $wash, '2026-10-08 12:00', ['deposit_amount' => -1, 'deposit_method' => 'cash'])->assertStatus(422);
        $none = $this->book($owner, $wash, '2026-10-08 14:00')->assertCreated();
        $this->assertNull($none->json('data.deposit'), 'no deposit, nothing shown');
    }

    public function test_a_deposit_can_be_changed_while_held_but_not_once_settled(): void
    {
        $owner = $this->salon();
        $wash = $this->wash($owner);
        $id = $this->book($owner, $wash, '2026-10-08 10:00', ['deposit_amount' => 5000, 'deposit_method' => 'cash'])->json('data.id');

        $this->api($owner, 'PUT', "/api/inventory/salon/appointments/{$id}", ['deposit_amount' => 8000, 'deposit_method' => 'mpesa'])->assertOk()->assertJsonPath('data.deposit.amount', 8000);
        $this->api($owner, 'PUT', "/api/inventory/salon/appointments/{$id}", ['notes' => 'moved'])->assertOk()->assertJsonPath('data.deposit.status', 'held');
        $this->api($owner, 'PUT', "/api/inventory/salon/appointments/{$id}", ['deposit_amount' => 0])->assertOk();
        $this->assertNull($this->api($owner, 'GET', '/api/inventory/salon/appointments?date=2026-10-08')->json('data.0.deposit'), 'taken back to nothing');

        $id2 = $this->book($owner, $wash, '2026-10-08 12:00', ['deposit_amount' => 5000, 'deposit_method' => 'cash'])->json('data.id');
        $this->move($owner, $id2, 'no_show')->assertOk();
        $this->api($owner, 'PUT', "/api/inventory/salon/appointments/{$id2}", ['deposit_amount' => 1])->assertStatus(422);   // a finished appointment can no longer be changed at all
    }

    public function test_when_the_appointment_is_done_the_deposit_is_put_into_the_sale(): void
    {
        $owner = $this->salon();
        $wash = $this->wash($owner);
        $id = $this->book($owner, $wash, '2026-10-08 10:00', ['deposit_amount' => 5000, 'deposit_method' => 'mpesa'])->json('data.id');

        $this->move($owner, $id, 'done')->assertOk();

        $this->assertSame('applied', $this->deposit($owner, $id)['status']);
    }

    public function test_a_no_show_loses_the_deposit(): void
    {
        $owner = $this->salon();
        $wash = $this->wash($owner);
        $id = $this->book($owner, $wash, '2026-10-08 10:00', ['deposit_amount' => 5000, 'deposit_method' => 'mpesa'])->json('data.id');

        $this->move($owner, $id, 'no_show')->assertOk();

        $this->assertSame('forfeited', $this->deposit($owner, $id)['status']);
    }

    public function test_with_no_policy_a_cancelled_booking_always_gets_the_deposit_back(): void
    {
        $owner = $this->salon();
        $wash = $this->wash($owner);
        $this->at('2026-10-08 09:30:00');                                  // 12:30 in Tanzania: the booking at 13:00 is in half an hour
        $id = $this->book($owner, $wash, '2026-10-08 13:00', ['deposit_amount' => 5000, 'deposit_method' => 'cash'])->json('data.id');

        $this->move($owner, $id, 'cancelled')->assertOk();

        $this->assertSame('refunded', $this->deposit($owner, $id)['status']);
        $this->assertSame(0, $this->api($owner, 'GET', '/api/inventory/salon/settings')->json('data.cancel_hours'));
    }

    public function test_cancelling_inside_the_window_loses_the_deposit_and_outside_it_gets_it_back(): void
    {
        $owner = $this->salon();
        $wash = $this->wash($owner);
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['cancel_hours' => 24])->assertOk()->assertJsonPath('data.cancel_hours', 24);
        $this->at('2026-10-06 09:00:00');                                  // 12:00 in Tanzania on the 6th
        $late = $this->book($owner, $wash, '2026-10-08 10:00', ['deposit_amount' => 5000, 'deposit_method' => 'cash'])->json('data.id');
        $early = $this->book($owner, $wash, '2026-10-08 14:00', ['deposit_amount' => 5000, 'deposit_method' => 'cash'])->json('data.id');

        $this->at('2026-10-07 09:00:00');                                  // 12:00 on the 7th: 22 hours before 10:00, 26 before 14:00
        $this->move($owner, $late, 'cancelled')->assertOk();
        $this->move($owner, $early, 'cancelled')->assertOk();

        $this->assertSame('forfeited', $this->deposit($owner, $late)['status'], 'less than a day\'s notice');
        $this->assertSame('refunded', $this->deposit($owner, $early)['status'], 'more than a day\'s notice');
    }

    public function test_the_cancellation_hours_are_checked(): void
    {
        $owner = $this->salon();

        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['cancel_hours' => -1])->assertStatus(422);
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['cancel_hours' => 999])->assertStatus(422);
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['cancel_hours' => 'soon'])->assertStatus(422);
    }

    public function test_a_kept_deposit_is_income_on_the_day_it_is_kept_and_a_held_one_is_not(): void
    {
        $owner = $this->salon();
        $wash = $this->wash($owner);
        $this->at('2026-10-05 09:00:00');
        $kept = $this->book($owner, $wash, '2026-10-08 10:00', ['deposit_amount' => 5000, 'deposit_method' => 'mpesa'])->json('data.id');
        $this->book($owner, $wash, '2026-10-08 12:00', ['deposit_amount' => 3000, 'deposit_method' => 'cash'])->assertCreated();          // still held
        $applied = $this->book($owner, $wash, '2026-10-08 14:00', ['deposit_amount' => 7000, 'deposit_method' => 'cash'])->json('data.id');
        $this->at('2026-10-08 12:00:00');
        $this->move($owner, $kept, 'no_show')->assertOk();
        $this->move($owner, $applied, 'done')->assertOk();

        $d = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?from=2026-10-01&to=2026-10-31')->assertOk()->json('data');

        $this->assertSame(5000, $d['other_income'], 'only the one that was kept');
        $this->assertSame(3000, $d['deposits_held'], 'the clients\' money, not income');
        $this->assertSame(5000, $d['net_profit'], 'no sales, no costs: the kept deposit is the whole profit');
        $this->assertSame([['method' => 'mpesa', 'amount' => 5000]], $d['collections'], 'the kept deposit is money received, by how it was paid; the applied one is in its sale');
        $this->assertSame(5000, $d['collected']);

        $before = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?from=2026-10-01&to=2026-10-07')->json('data');
        $this->assertSame(0, $before['other_income'], 'kept on the 8th: not income on the 7th');
        $this->assertSame(3000, $before['deposits_held']);
    }

    public function test_a_salons_deposits_are_its_own(): void
    {
        $owner = $this->salon();
        $other = $this->salon('Other');
        $wash = $this->wash($owner);
        $this->at('2026-10-05 09:00:00');
        $id = $this->book($owner, $wash, '2026-10-08 10:00', ['deposit_amount' => 5000, 'deposit_method' => 'cash'])->json('data.id');
        $this->at('2026-10-08 12:00:00');
        $this->move($owner, $id, 'no_show')->assertOk();

        $d = $this->api($other, 'GET', '/api/inventory/salon/profit-loss?from=2026-10-01&to=2026-10-31')->json('data');

        $this->assertSame([0, 0, 0], [$d['other_income'], $d['deposits_held'], $d['collected']]);
    }
}
