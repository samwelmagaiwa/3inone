<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * The salon's people at work: days off and working hours (and that a booking respects them), attendance with hours,
 * and each shift's cash: what the till should hold against what was handed over, with an alert to the owner when they
 * differ. Plus the alerts and the end-of-day text. A person only ever sees their own attendance and shifts.
 */
class SalonStaffTest extends TestCase
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

    private function person(User $owner, string $name, string $role = 'hair_stylist'): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, fn () => TenantContext::runInService('salon', $fn));
    }

    private function at(string $when): void
    {
        Carbon::setTestNow(Carbon::parse($when, 'UTC'));
    }

    private function service(User $as, string $name, int $price): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price, 'duration_minutes' => 60])->assertCreated()->json('data.id');
    }

    private function sell(User $as, int $product, int $price, string $method = 'cash')
    {
        return $this->api($as, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => $price, 'discount' => 0, 'tax' => 0, 'total' => $price, 'paid_total' => $price,
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => $price]],
            'payments' => [['amount' => $price, 'method' => $method]],
        ]);
    }

    private function book(User $as, int $service, ?User $stylist, string $at, array $extra = [])
    {
        return $this->api($as, 'POST', '/api/inventory/salon/appointments', array_merge(array_filter([
            'client_name' => 'Neema', 'starts_at' => $at, 'services' => [['product_id' => $service]], 'staff_id' => $stylist ? (string) $stylist->id : null,
        ]), $extra));
    }

    // ------------------------------------------------------------------ days off, hours and bookings

    public function test_a_manager_gives_days_off_and_a_stylist_cannot_give_herself_one(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $stranger = $this->person($this->salon('Other'), 'Stranger');

        $id = $this->api($owner, 'POST', '/api/inventory/salon/days-off', ['staff_id' => (string) $asha->id, 'off_on' => '2026-10-08', 'reason' => 'Family'])->assertCreated()->json('data.id');
        $this->api($owner, 'POST', '/api/inventory/salon/days-off', ['staff_id' => (string) $asha->id, 'off_on' => '2026-10-08'])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/days-off', ['staff_id' => (string) $stranger->id, 'off_on' => '2026-10-08'])->assertStatus(422);
        $this->api($asha, 'POST', '/api/inventory/salon/days-off', ['staff_id' => (string) $asha->id, 'off_on' => '2026-10-09'])->assertStatus(403);

        $list = $this->api($owner, 'GET', '/api/inventory/salon/days-off?month=2026-10')->json('data');
        $this->assertSame(['Asha', '2026-10-08', 'Family'], [$list[0]['staff_name'], $list[0]['off_on'], $list[0]['reason']]);
        $this->assertCount(1, $this->api($asha, 'GET', '/api/inventory/salon/days-off?month=2026-10')->json('data'));
        $this->assertCount(0, $this->api($owner, 'GET', '/api/inventory/salon/days-off?month=2026-11')->json('data'));

        $this->api($asha, 'DELETE', "/api/inventory/salon/days-off/{$id}")->assertStatus(403);
        $this->api($owner, 'DELETE', "/api/inventory/salon/days-off/{$id}")->assertOk();
        $this->api($owner, 'DELETE', "/api/inventory/salon/days-off/{$id}")->assertStatus(404);
    }

    public function test_a_stylists_days_and_hours_are_saved_and_checked(): void
    {
        $owner = $this->salon();
        $asha = (string) $this->person($owner, 'Asha')->id;

        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha}", ['work_days' => [6, 1, 2, 2], 'shift_start' => '08:30', 'shift_end' => '17:00'])->assertOk();
        $row = collect($this->api($owner, 'GET', '/api/inventory/salon/staff-profiles')->json('data'))->firstWhere('name', 'Asha');
        $this->assertSame([[1, 2, 6], '08:30', '17:00'], [$row['work_days'], $row['shift_start'], $row['shift_end']]);

        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha}", ['shift_start' => '17:00', 'shift_end' => '08:30'])->assertStatus(422);
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha}", ['work_days' => [8]])->assertStatus(422);
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha}", ['shift_start' => '25:99'])->assertStatus(422);

        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha}", ['work_days' => [], 'shift_start' => null, 'shift_end' => null])->assertOk();
        $row = collect($this->api($owner, 'GET', '/api/inventory/salon/staff-profiles')->json('data'))->firstWhere('name', 'Asha');
        $this->assertSame([[], null, null], [$row['work_days'], $row['shift_start'], $row['shift_end']], 'emptied: anyone, any time again');
    }

    public function test_a_booking_respects_days_off_working_days_and_hours_unless_told_otherwise(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $bahati = $this->person($owner, 'Bahati');
        $wash = $this->service($owner, 'Wash', 5000);
        // 2026-10-08 is a Thursday.
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha->id}", ['work_days' => [1, 2, 3, 4, 5], 'shift_start' => '09:00', 'shift_end' => '17:00'])->assertOk();
        $this->api($owner, 'POST', '/api/inventory/salon/days-off', ['staff_id' => (string) $asha->id, 'off_on' => '2026-10-13'])->assertCreated();

        $this->book($owner, $wash, $asha, '2026-10-08 10:00')->assertCreated();

        $off = $this->book($owner, $wash, $asha, '2026-10-13 10:00')->assertStatus(422);
        $this->assertStringContainsString('Asha ana mapumziko tarehe 13/10/2026. / Asha is off on 13/10/2026.', $off->json('errors.staff_id.0'));
        $saturday = $this->book($owner, $wash, $asha, '2026-10-10 10:00')->assertStatus(422);
        $this->assertStringContainsString('hafanyi kazi siku ya Jumamosi (10/10/2026). / Asha does not work on Saturdays (10/10/2026).', $saturday->json('errors.staff_id.0'));
        $early = $this->book($owner, $wash, $asha, '2026-10-08 08:00')->assertStatus(422);
        $this->assertStringContainsString('Asha anafanya kazi saa 09:00-17:00. / Asha works 09:00-17:00.', $early->json('errors.staff_id.0'));
        $this->book($owner, $wash, $asha, '2026-10-08 17:00')->assertStatus(422);
        $this->book($owner, $wash, $asha, '2026-10-08 16:30')->assertCreated();

        $this->book($owner, $wash, $bahati, '2026-10-10 08:00')->assertCreated();                                  // Bahati has no limits
        $this->book($owner, $wash, null, '2026-10-13 22:00')->assertCreated();                                      // nobody named
        $this->book($owner, $wash, $asha, '2026-10-13 10:00', ['force' => true])->assertCreated();                  // the owner says book anyway
    }

    public function test_moving_an_appointment_onto_a_day_off_is_refused_too(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 5000);
        $id = $this->book($owner, $wash, $asha, '2026-10-08 10:00')->assertCreated()->json('data.id');
        $this->api($owner, 'POST', '/api/inventory/salon/days-off', ['staff_id' => (string) $asha->id, 'off_on' => '2026-10-09'])->assertCreated();

        $this->api($owner, 'PUT', "/api/inventory/salon/appointments/{$id}", ['starts_at' => '2026-10-09 10:00'])->assertStatus(422);
        $this->api($owner, 'PUT', "/api/inventory/salon/appointments/{$id}", ['starts_at' => '2026-10-10 10:00'])->assertOk();
    }

    // ------------------------------------------------------------------ attendance

    public function test_clocking_in_and_out_counts_the_hours(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');

        $this->at('2026-10-07 06:00:00');                                  // 09:00 in Tanzania
        $this->assertFalse($this->api($asha, 'GET', '/api/inventory/salon/attendance/today')->json('data.at_work'));
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-in')->assertCreated()->assertJsonPath('data.clock_in', '2026-10-07 09:00');
        $this->assertTrue($this->api($asha, 'GET', '/api/inventory/salon/attendance/today')->json('data.at_work'));
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-in')->assertStatus(422);

        $this->at('2026-10-07 15:30:00');                                  // 18:30
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-out')->assertOk()->assertJsonPath('data.hours', 9.5);
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-out')->assertStatus(422);

        $this->at('2026-10-08 06:00:00');
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-in')->assertCreated();
        $this->at('2026-10-08 10:00:00');
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-out')->assertOk();

        $month = $this->api($owner, 'GET', '/api/inventory/salon/attendance?month=2026-10')->assertOk()->json('data.staff');
        $this->assertSame(['Asha', 2, 13.5, false], [$month[0]['name'], $month[0]['days'], $month[0]['hours'], $month[0]['at_work']]);
        $this->assertCount(2, $month[0]['records']);
    }

    public function test_someone_still_at_work_is_shown_as_such_and_their_open_day_has_no_hours_yet(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $this->at('2026-10-07 06:00:00');
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-in')->assertCreated();

        $row = $this->api($owner, 'GET', '/api/inventory/salon/attendance?month=2026-10')->json('data.staff.0');

        $this->assertTrue($row['at_work']);
        $this->assertSame(0, $row['hours']);
        $this->assertNull($row['records'][0]['hours']);
        $this->assertNull($row['records'][0]['clock_out']);
    }

    public function test_a_manager_clocks_someone_in_a_stylist_only_herself_and_each_sees_only_their_own(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $bahati = $this->person($owner, 'Bahati');
        $this->at('2026-10-07 06:00:00');

        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-in', ['staff_id' => (string) $bahati->id])->assertStatus(403);
        $this->api($owner, 'POST', '/api/inventory/salon/attendance/clock-in', ['staff_id' => (string) $bahati->id])->assertCreated()->assertJsonPath('data.name', 'Bahati');
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-in')->assertCreated();

        $mine = $this->api($asha, 'GET', '/api/inventory/salon/attendance?month=2026-10')->json('data.staff');
        $this->assertSame(['Asha'], array_column($mine, 'name'));
        $this->assertSame(['Asha'], array_column($this->api($asha, 'GET', '/api/inventory/salon/attendance?month=2026-10&staff_id=' . $bahati->id)->json('data.staff'), 'name'), 'asking for someone else changes nothing');
        $this->assertSame(['Asha', 'Bahati'], array_column($this->api($owner, 'GET', '/api/inventory/salon/attendance?month=2026-10')->json('data.staff'), 'name'));
        $this->assertSame(['Bahati'], array_column($this->api($owner, 'GET', '/api/inventory/salon/attendance?month=2026-10&staff_id=' . $bahati->id)->json('data.staff'), 'name'));
    }

    public function test_another_salons_staff_cannot_be_clocked_in(): void
    {
        $owner = $this->salon();
        $stranger = $this->person($this->salon('Other'), 'Stranger');

        $this->api($owner, 'POST', '/api/inventory/salon/attendance/clock-in', ['staff_id' => (string) $stranger->id])->assertStatus(422);
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_attendance')->count()));
    }

    // ------------------------------------------------------------------ shifts and cash

    private function openAndSell(User $owner, User $asha, int $float = 20000, array $sales = [['cash', 40000]]): array
    {
        $wash = $this->service($owner, 'Wash', 40000);
        $this->at('2026-10-07 06:00:00');
        $shift = $this->api($asha, 'POST', '/api/inventory/salon/shifts/open', ['opening_float' => $float])->assertCreated()->json('data');
        $this->at('2026-10-07 08:00:00');
        foreach ($sales as [$method, $amount]) {
            $this->sell($asha, $wash, $amount, $method)->assertCreated();
        }
        $this->at('2026-10-07 15:00:00');

        return ['shift' => $shift, 'wash' => $wash];
    }

    public function test_the_till_should_hold_the_float_plus_the_cash_taken(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $r = $this->openAndSell($owner, $asha, 20000, [['cash', 40000], ['mpesa', 30000], ['cash', 5000], ['bank_transfer', 10000]]);

        $now = $this->api($asha, 'GET', '/api/inventory/salon/shifts/current')->assertOk()->json('data');

        $this->assertSame(65000, $now['expected_cash'], '20,000 float + 45,000 cash');
        $this->assertSame(['cash' => 45000, 'mobile_money' => 30000, 'bank_transfer' => 10000], $now['collected'], 'what went elsewhere is shown so the owner can match it');
        $this->assertSame('open', $now['status']);
        $this->assertSame(0, $r['shift']['id'] === $now['id'] ? 0 : 1);
    }

    public function test_closing_with_the_right_cash_leaves_no_difference_and_no_alert(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $r = $this->openAndSell($owner, $asha);

        $res = $this->api($asha, 'POST', "/api/inventory/salon/shifts/{$r['shift']['id']}/close", ['counted_cash' => 60000, 'handed_to_id' => (string) $owner->id, 'note' => 'All there'])->assertOk();

        $this->assertSame(['closed', 60000, 60000, 0, 'Glow Salon Owner', 'All there'], [$res->json('data.status'), $res->json('data.expected_cash'), $res->json('data.counted_cash'), $res->json('data.difference'), $res->json('data.handed_to_name'), $res->json('data.note')]);
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_notifications')->where('type', 'salon_cash_discrepancy')->count()));
    }

    public function test_cash_that_is_short_alerts_the_owner_and_managers_but_not_the_person(): void
    {
        $owner = $this->salon();
        $manager = $this->person($owner, 'Mary', 'manager');
        $asha = $this->person($owner, 'Asha');
        $r = $this->openAndSell($owner, $asha);

        $res = $this->api($asha, 'POST', "/api/inventory/salon/shifts/{$r['shift']['id']}/close", ['counted_cash' => 55000])->assertOk();

        $this->assertSame(-5000, $res->json('data.difference'));
        $alerts = fn (User $who) => $this->api($who, 'GET', '/api/inventory/notifications')->json('data');
        $ownerAlert = collect($alerts($owner))->firstWhere('type', 'salon_cash_discrepancy');
        $this->assertNotNull($ownerAlert);
        $this->assertStringContainsString('Asha: pungufu / short 5,000', $ownerAlert['body']);
        $this->assertSame(-5, $ownerAlert['data']['difference'] / 1000);
        $this->assertNotNull(collect($alerts($manager))->firstWhere('type', 'salon_cash_discrepancy'));
        $this->assertNull(collect($alerts($asha))->firstWhere('type', 'salon_cash_discrepancy'), 'the person is not alerted about themselves');
    }

    public function test_cash_that_is_over_also_alerts(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $r = $this->openAndSell($owner, $asha);

        $res = $this->api($asha, 'POST', "/api/inventory/salon/shifts/{$r['shift']['id']}/close", ['counted_cash' => 62500])->assertOk();

        $this->assertSame(2500, $res->json('data.difference'));
        $alert = collect($this->api($owner, 'GET', '/api/inventory/notifications')->json('data'))->firstWhere('type', 'salon_cash_discrepancy');
        $this->assertStringContainsString('zaidi / over 2,500', $alert['body']);
    }

    public function test_only_what_the_person_took_inside_the_shift_counts(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $bahati = $this->person($owner, 'Bahati');
        $wash = $this->service($owner, 'Wash', 40000);
        $this->at('2026-10-07 05:00:00');
        $this->sell($asha, $wash, 11000)->assertCreated();                                    // before the shift opened
        $this->at('2026-10-07 06:00:00');
        $shift = $this->api($asha, 'POST', '/api/inventory/salon/shifts/open', ['opening_float' => 0])->json('data');
        $this->at('2026-10-07 07:00:00');
        $this->sell($asha, $wash, 40000)->assertCreated();                                    // hers
        $this->sell($bahati, $wash, 22000)->assertCreated();                                  // someone else's
        $cancelled = $this->sell($asha, $wash, 33000)->assertCreated()->json('data.id');
        $this->api($owner, 'POST', "/api/inventory/sales/{$cancelled}/cancel", ['reason' => 'No show'])->assertOk();   // cancelled
        $this->at('2026-10-07 09:00:00');

        $res = $this->api($asha, 'POST', "/api/inventory/salon/shifts/{$shift['id']}/close", ['counted_cash' => 40000])->assertOk();

        $this->assertSame([40000, 0], [$res->json('data.expected_cash'), $res->json('data.difference')]);
        $this->at('2026-10-07 10:00:00');
        $this->sell($asha, $wash, 9000)->assertCreated();                                      // after it closed
        $again = $this->api($owner, 'GET', '/api/inventory/salon/shifts?month=2026-10')->json('data.shifts.0');
        $this->assertSame(40000, $again['expected_cash'], 'a closed shift does not move');
    }

    public function test_one_open_shift_each_and_a_closed_one_stays_closed(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $bahati = $this->person($owner, 'Bahati');
        $this->at('2026-10-07 06:00:00');

        $id = $this->api($asha, 'POST', '/api/inventory/salon/shifts/open', ['opening_float' => 5000])->assertCreated()->json('data.id');
        $this->api($asha, 'POST', '/api/inventory/salon/shifts/open', ['opening_float' => 5000])->assertStatus(422);
        $this->api($bahati, 'POST', '/api/inventory/salon/shifts/open', ['opening_float' => 0])->assertCreated();

        $this->api($bahati, 'POST', "/api/inventory/salon/shifts/{$id}/close", ['counted_cash' => 5000])->assertStatus(403);
        $this->api($asha, 'POST', "/api/inventory/salon/shifts/{$id}/close", ['counted_cash' => 5000])->assertOk();
        $this->api($asha, 'POST', "/api/inventory/salon/shifts/{$id}/close", ['counted_cash' => 5000])->assertStatus(422);
        $this->api($asha, 'POST', '/api/inventory/salon/shifts/open', ['opening_float' => 5000])->assertCreated();
        $this->assertNull($this->api($owner, 'GET', '/api/inventory/salon/shifts/current')->json('data'), 'the owner has none of their own open');
        $this->api($asha, 'POST', '/api/inventory/salon/shifts/999/close', ['counted_cash' => 1])->assertStatus(404);
    }

    public function test_a_manager_may_close_a_shift_someone_left_open(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $this->at('2026-10-07 06:00:00');
        $id = $this->api($asha, 'POST', '/api/inventory/salon/shifts/open', ['opening_float' => 5000])->json('data.id');

        $this->api($owner, 'POST', "/api/inventory/salon/shifts/{$id}/close", ['counted_cash' => 5000])->assertOk()->assertJsonPath('data.status', 'closed');
    }

    public function test_shifts_are_listed_with_their_differences_and_each_person_sees_only_their_own(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $bahati = $this->person($owner, 'Bahati');
        $this->at('2026-10-07 06:00:00');
        $a = $this->api($asha, 'POST', '/api/inventory/salon/shifts/open', ['opening_float' => 1000])->json('data.id');
        $b = $this->api($bahati, 'POST', '/api/inventory/salon/shifts/open', ['opening_float' => 1000])->json('data.id');
        $this->at('2026-10-07 15:00:00');
        $this->api($asha, 'POST', "/api/inventory/salon/shifts/{$a}/close", ['counted_cash' => 1000])->assertOk();
        $this->api($bahati, 'POST', "/api/inventory/salon/shifts/{$b}/close", ['counted_cash' => 700])->assertOk();

        $all = $this->api($owner, 'GET', '/api/inventory/salon/shifts?month=2026-10')->assertOk()->json('data');
        $this->assertSame([2, 1, -300], [$all['totals']['shifts'], $all['totals']['with_difference'], $all['totals']['difference']]);
        $this->assertSame(['Asha'], array_column($this->api($asha, 'GET', '/api/inventory/salon/shifts?month=2026-10')->json('data.shifts'), 'staff_name'));
        $this->assertSame(['Asha'], array_column($this->api($asha, 'GET', '/api/inventory/salon/shifts?month=2026-10&staff_id=' . $bahati->id)->json('data.shifts'), 'staff_name'));
        $this->assertSame(['Bahati'], array_column($this->api($owner, 'GET', '/api/inventory/salon/shifts?month=2026-10&staff_id=' . $bahati->id)->json('data.shifts'), 'staff_name'));
        $this->assertCount(0, $this->api($owner, 'GET', '/api/inventory/salon/shifts?month=2026-09')->json('data.shifts'));
    }

    public function test_the_handover_must_go_to_someone_in_the_business(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $stranger = $this->person($this->salon('Other'), 'Stranger');
        $this->at('2026-10-07 06:00:00');
        $id = $this->api($asha, 'POST', '/api/inventory/salon/shifts/open', ['opening_float' => 0])->json('data.id');

        $this->api($asha, 'POST', "/api/inventory/salon/shifts/{$id}/close", ['counted_cash' => 0, 'handed_to_id' => (string) $stranger->id])->assertStatus(422);
        $this->api($asha, 'POST', "/api/inventory/salon/shifts/{$id}/close", ['counted_cash' => -5])->assertStatus(422);
        $this->api($asha, 'POST', "/api/inventory/salon/shifts/{$id}/close", [])->assertStatus(422);
    }

    public function test_another_salon_never_sees_these_shifts_or_attendance(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $other = $this->salon('Other');
        $this->at('2026-10-07 06:00:00');
        $this->api($asha, 'POST', '/api/inventory/salon/shifts/open', ['opening_float' => 100])->assertCreated();
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-in')->assertCreated();

        $this->assertCount(0, $this->api($other, 'GET', '/api/inventory/salon/shifts?month=2026-10')->json('data.shifts'));
        $this->assertCount(0, $this->api($other, 'GET', '/api/inventory/salon/attendance?month=2026-10')->json('data.staff'));
    }

    // ------------------------------------------------------------------ the other alerts

    public function test_an_expense_waiting_for_approval_alerts_the_people_who_can_approve(): void
    {
        $owner = $this->salon();
        $manager = $this->person($owner, 'Mary', 'manager');
        $helper = $this->person($owner, 'Helper', 'hair_stylist');
        $helper->forceFill(['permissions' => ['inv_view_expenses', 'inv_manage_expenses']])->save();

        $this->api($helper, 'POST', '/api/inventory/expenses', ['category' => 'transport', 'description' => 'Taxi', 'amount' => 20000, 'expense_date' => '2026-10-07'])->assertCreated()->assertJsonPath('data.status', 'pending');

        foreach ([$owner, $manager] as $approver) {
            $a = collect($this->api($approver, 'GET', '/api/inventory/notifications')->json('data'))->firstWhere('type', 'salon_expense_pending');
            $this->assertNotNull($a);
            $this->assertStringContainsString('Taxi: 20,000 TSh', $a['body']);
        }
        $this->assertNull(collect($this->api($helper, 'GET', '/api/inventory/notifications')->json('data'))->firstWhere('type', 'salon_expense_pending'));

        $this->api($owner, 'POST', '/api/inventory/expenses', ['category' => 'rent', 'description' => 'Rent', 'amount' => 1000, 'expense_date' => '2026-10-07'])->assertCreated();
        $this->assertCount(1, collect($this->api($manager, 'GET', '/api/inventory/notifications')->json('data'))->where('type', 'salon_expense_pending'), 'the owner\'s own spending needs no approval, so no alert');
    }

    public function test_a_new_booking_alerts_the_stylist_unless_she_made_it(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 5000);

        $this->book($owner, $wash, $asha, '2026-10-08 10:00')->assertCreated();
        $a = collect($this->api($asha, 'GET', '/api/inventory/notifications')->json('data'))->firstWhere('type', 'salon_new_booking');
        $this->assertSame('Neema - 08/10 10:00', $a['body']);

        $this->book($owner, $wash, null, '2026-10-08 12:00')->assertCreated();
        $this->assertCount(1, collect($this->api($asha, 'GET', '/api/inventory/notifications')->json('data'))->where('type', 'salon_new_booking'), 'a booking with nobody named alerts nobody');
    }

    public function test_a_payment_recorded_for_someone_is_told_to_them(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');

        $this->api($owner, 'POST', '/api/inventory/salon/payouts', ['staff_id' => (string) $asha->id, 'kind' => 'advance', 'amount' => 30000])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/salon/payouts', ['staff_id' => (string) $owner->id, 'kind' => 'salary', 'amount' => 1000])->assertCreated();

        $n = collect($this->api($asha, 'GET', '/api/inventory/notifications')->json('data'))->where('type', 'salon_payout');
        $this->assertCount(1, $n);
        $this->assertSame('Advance: 30,000 TSh', $n->first()['body']);
        $this->assertCount(0, collect($this->api($owner, 'GET', '/api/inventory/notifications')->json('data'))->where('type', 'salon_payout'), 'the owner is not told about paying themselves');
    }

    // ------------------------------------------------------------------ the end-of-day text

    private function freshSms(): FakeSmsGateway
    {
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);

        return $this->sms;
    }

    public function test_the_owner_is_texted_how_the_day_went_once_and_only_when_switched_on(): void
    {
        $owner = $this->salon('Glow Salon');
        $wash = $this->service($owner, 'Wash', 40000);
        $this->freshSms();
        $this->at('2026-10-07 10:00:00');
        $this->sell($owner, $wash, 40000)->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/expenses', ['category' => 'rent', 'description' => 'Rent', 'amount' => 10000, 'expense_date' => '2026-10-07'])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/salon/appointments', ['client_name' => 'Tomorrow', 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]])->assertCreated();
        $this->at('2026-10-07 16:30:00');

        $this->artisan('salon:daily-summary')->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent, 'off until the owner switches it on');

        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['daily_summary' => true])->assertOk()->assertJsonPath('data.daily_summary', true);
        $this->artisan('salon:daily-summary', ['--dry-run' => true])->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent, 'a dry run sends nothing');
        $this->artisan('salon:daily-summary')->assertExitCode(0);

        $this->assertCount(1, $this->sms->sent);
        $this->assertSame($owner->phone_number, $this->sms->sent[0]['to']);
        $this->assertSame(
            'Leo Glow Salon: mapato TSh 40,000, matumizi TSh 10,000, faida TSh 30,000, wateja 1. Kesho miadi 1. / '
            . 'Today at Glow Salon: revenue TSh 40,000, expenses TSh 10,000, profit TSh 30,000, 1 clients. 1 booked tomorrow.',
            $this->sms->sent[0]['message']
        );

        $this->artisan('salon:daily-summary')->assertExitCode(0);
        $this->assertCount(1, $this->sms->sent, 'the same evening again: not texted twice');
        $this->at('2026-10-08 16:30:00');
        $this->artisan('salon:daily-summary')->assertExitCode(0);
        $this->assertCount(2, $this->sms->sent, 'the next evening: texted again');
    }

    public function test_a_day_at_a_loss_says_loss_and_a_failed_text_is_tried_again(): void
    {
        $owner = $this->salon('Glow Salon');
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['daily_summary' => true])->assertOk();
        $sms = $this->freshSms();
        $this->at('2026-10-07 10:00:00');
        $this->api($owner, 'POST', '/api/inventory/expenses', ['category' => 'rent', 'description' => 'Rent', 'amount' => 5000, 'expense_date' => '2026-10-07'])->assertCreated();
        $this->at('2026-10-07 16:30:00');

        $sms->refuseAll();
        $this->artisan('salon:daily-summary')->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent);

        $this->freshSms();
        $this->artisan('salon:daily-summary')->assertExitCode(0);
        $this->assertCount(1, $this->sms->sent, 'the failed one gave the day back');
        $this->assertStringContainsString('hasara TSh 5,000', $this->sms->sent[0]['message']);
        $this->assertStringContainsString('loss TSh 5,000', $this->sms->sent[0]['message']);
    }

    public function test_each_salon_is_told_about_itself_only_and_the_job_is_scheduled(): void
    {
        $glow = $this->salon('Glow');
        $other = $this->salon('Other');
        $this->api($glow, 'PUT', '/api/inventory/salon/settings', ['daily_summary' => true])->assertOk();
        $this->api($other, 'PUT', '/api/inventory/salon/settings', ['daily_summary' => true])->assertOk();
        $wash = $this->service($glow, 'Wash', 40000);
        $this->freshSms();
        $this->at('2026-10-07 10:00:00');
        $this->sell($glow, $wash, 40000)->assertCreated();
        $this->at('2026-10-07 16:30:00');

        $this->artisan('salon:daily-summary')->assertExitCode(0);

        $by = collect($this->sms->sent)->keyBy('to');
        $this->assertStringContainsString('TSh 40,000', $by[$glow->phone_number]['message']);
        $this->assertStringContainsString('mapato TSh 0,', $by[$other->phone_number]['message']);
        $this->artisan('schedule:list')->expectsOutputToContain('salon:daily-summary')->assertExitCode(0);
    }
}
