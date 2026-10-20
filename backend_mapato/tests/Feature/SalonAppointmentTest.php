<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * A salon's diary. The rules that matter: a stylist cannot be in two places (overlap is refused, back-to-back is not),
 * what an appointment may become, that services come from the business's own list, that one salon never sees another's
 * diary (nor the shop's), and that the "tomorrow" reminder goes out once, to the right people, in two languages.
 */
class SalonAppointmentTest extends TestCase
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

    private function stylist(User $owner, string $name): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [], bool $salon = true)
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders(); // headers stick from one call to the next in a test
        $request = $this->withHeader('Authorization', "Bearer {$token}");

        return ($salon ? $request->withHeader('X-Service', 'salon') : $request)->json($method, $uri, $body);
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, fn () => TenantContext::runInService('salon', $fn));
    }

    private function service(User $as, string $name, int $price, ?int $minutes = null, array $extra = []): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', array_merge([
            'name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active',
            'cost_price' => 0, 'selling_price' => $price, 'duration_minutes' => $minutes,
        ], $extra))->assertCreated()->json('data.id');
    }

    private function book(User $as, array $body)
    {
        return $this->api($as, 'POST', '/api/inventory/salon/appointments', $body);
    }

    private function freshSms(): FakeSmsGateway
    {
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);

        return $this->sms;
    }

    // ------------------------------------------------------------------ booking

    public function test_a_booking_takes_its_name_price_and_time_from_the_services(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $braids = $this->service($owner, 'Braids', 40000, 180);
        $wash = $this->service($owner, 'Wash', 5000, 30);

        $res = $this->book($owner, [
            'client_name' => 'Neema', 'client_phone' => '0711000001', 'staff_id' => (string) $asha->id,
            'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $braids], ['product_id' => $wash]], 'notes' => 'Bring extensions',
        ])->assertCreated();

        $res->assertJsonPath('data.status', 'booked')
            ->assertJsonPath('data.starts_at', '2026-10-08 10:00')
            ->assertJsonPath('data.ends_at', '2026-10-08 13:30')
            ->assertJsonPath('data.total', 45000)
            ->assertJsonPath('data.staff_name', 'Asha')
            ->assertJsonPath('data.client_name', 'Neema')
            ->assertJsonPath('data.notes', 'Bring extensions');
        $this->assertSame(['Braids', 'Wash'], array_column($res->json('data.services'), 'name'));
    }

    public function test_a_service_with_no_time_takes_an_hour_and_a_duration_can_be_given(): void
    {
        $owner = $this->salon();
        $set = $this->service($owner, 'Set', 15000);

        $this->book($owner, ['client_name' => 'A', 'starts_at' => '2026-10-08 09:00', 'services' => [['product_id' => $set]]])
            ->assertCreated()->assertJsonPath('data.ends_at', '2026-10-08 10:00');
        $this->book($owner, ['client_name' => 'B', 'starts_at' => '2026-10-08 12:00', 'services' => [['product_id' => $set]], 'duration_minutes' => 90])
            ->assertCreated()->assertJsonPath('data.ends_at', '2026-10-08 13:30');
    }

    public function test_a_price_option_is_the_price_of_that_booking(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000, 180, ['price_options' => [['label' => 'Short', 'price' => 30000], ['label' => 'Long', 'price' => 60000]]]);

        $res = $this->book($owner, ['client_name' => 'A', 'starts_at' => '2026-10-08 09:00', 'services' => [['product_id' => $braids, 'price' => 60000, 'label' => 'Long']]])->assertCreated();

        $res->assertJsonPath('data.total', 60000);
        $this->assertSame('Long', $res->json('data.services.0.label'));
    }

    public function test_the_two_lists_of_a_service_are_kept_and_only_for_services(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $braids = $this->service($owner, 'Braids', 40000, 180, ['staff_ids' => [(string) $asha->id], 'price_options' => [['label' => 'Long', 'price' => 60000]]]);

        $listed = collect($this->api($owner, 'GET', '/api/inventory/products')->assertOk()->json('data'))->firstWhere('id', $braids);
        $this->assertSame([(string) $asha->id], $listed['staff_ids']);
        $this->assertEquals(60000, $listed['price_options'][0]['price']);

        $this->api($owner, 'PUT', "/api/inventory/products/{$braids}", ['staff_ids' => [], 'price_options' => []])->assertOk();
        $listed = collect($this->api($owner, 'GET', '/api/inventory/products')->json('data'))->firstWhere('id', $braids);
        $this->assertSame([], $listed['staff_ids'], 'emptied: anyone may do it again');
        $this->assertSame([], $listed['price_options']);

        $goods = $this->api($owner, 'POST', '/api/inventory/products', [
            'name' => 'Oil', 'quantity' => 5, 'min_stock' => 1, 'status' => 'active', 'cost_price' => 1, 'selling_price' => 5,
            'staff_ids' => [(string) $asha->id], 'price_options' => [['label' => 'x', 'price' => 1]],
        ])->assertCreated();
        $this->assertEmpty($goods->json('data.staff_ids'));
        $this->assertEmpty($goods->json('data.price_options'));
    }

    // ------------------------------------------------------------------ clashes

    public function test_a_stylist_cannot_be_booked_twice_at_once_but_back_to_back_is_fine(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $bahati = $this->stylist($owner, 'Bahati');
        $wash = $this->service($owner, 'Wash', 5000, 60);
        $mk = fn (string $name, User $who, string $at) => $this->book($owner, ['client_name' => $name, 'staff_id' => (string) $who->id, 'starts_at' => $at, 'services' => [['product_id' => $wash]]]);

        $mk('First', $asha, '2026-10-08 10:00')->assertCreated();

        $mk('Overlap', $asha, '2026-10-08 10:30')->assertStatus(422)->assertJsonValidationErrors('staff_id');
        $this->assertStringContainsString('Asha ana miadi saa 10:00-11:00 (First). / Asha is already booked 10:00-11:00 (First)', $mk('Overlap', $asha, '2026-10-08 09:30')->json('errors.staff_id.0'));
        $mk('Next', $asha, '2026-10-08 11:00')->assertCreated();      // starts when the first ends
        $mk('Before', $asha, '2026-10-08 09:00')->assertCreated();    // ends when the first starts
        $mk('Same time other stylist', $bahati, '2026-10-08 10:00')->assertCreated();
        $mk('Nobody named', $asha, '2026-10-08 10:00')->assertStatus(422);
        $this->book($owner, ['client_name' => 'No stylist yet', 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]])->assertCreated();
        $mk('Forced', $asha, '2026-10-08 10:15')->assertStatus(422);
        $this->book($owner, ['client_name' => 'Forced', 'staff_id' => (string) $asha->id, 'starts_at' => '2026-10-08 10:15', 'services' => [['product_id' => $wash]], 'force' => true])->assertCreated();
    }

    public function test_a_cancelled_or_finished_appointment_no_longer_blocks_the_time(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 5000, 60);
        $body = fn (string $name) => ['client_name' => $name, 'staff_id' => (string) $asha->id, 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]];

        $id = $this->book($owner, $body('One'))->assertCreated()->json('data.id');
        $this->book($owner, $body('Two'))->assertStatus(422);
        $this->api($owner, 'POST', "/api/inventory/salon/appointments/{$id}/status", ['status' => 'cancelled'])->assertOk();
        $this->book($owner, $body('Two'))->assertCreated();
    }

    // ------------------------------------------------------------------ the diary

    public function test_a_day_lists_its_appointments_in_time_order_and_nothing_else(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 5000, 30);
        foreach ([['Late', '2026-10-08 15:00'], ['Early', '2026-10-08 08:30'], ['Tomorrow', '2026-10-09 09:00'], ['Yesterday', '2026-10-07 23:30']] as [$n, $at]) {
            $this->book($owner, ['client_name' => $n, 'starts_at' => $at, 'services' => [['product_id' => $wash]]])->assertCreated();
        }

        $day = $this->api($owner, 'GET', '/api/inventory/salon/appointments?date=2026-10-08')->assertOk()->json('data');
        $this->assertSame(['Early', 'Late'], array_column($day, 'client_name'));

        $period = $this->api($owner, 'GET', '/api/inventory/salon/appointments?from=2026-10-08&to=2026-10-09')->json('data');
        $this->assertSame(['Early', 'Late', 'Tomorrow'], array_column($period, 'client_name'));
    }

    public function test_a_salon_sees_only_its_own_diary_and_the_shop_sees_none(): void
    {
        $glow = $this->salon('Glow');
        $other = $this->salon('Other');
        $wash = $this->service($glow, 'Wash', 5000, 30);
        $this->book($glow, ['client_name' => 'Glow client', 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]])->assertCreated();

        $this->assertCount(1, $this->api($glow, 'GET', '/api/inventory/salon/appointments?date=2026-10-08')->json('data'));
        $this->assertCount(0, $this->api($other, 'GET', '/api/inventory/salon/appointments?date=2026-10-08')->json('data'));
        $this->assertSame(0, $this->rows($other, fn () => DB::table('inventory_appointments')->count()));
        $this->assertCount(0, $this->api($glow, 'GET', '/api/inventory/salon/appointments?date=2026-10-08', [], salon: false)->json('data') ?? [], 'the same account asked as the shop sees no salon diary');
    }

    // ------------------------------------------------------------------ states, changes

    public function test_an_appointment_moves_through_its_states_and_stops_at_the_end(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 5000, 30);
        $id = $this->book($owner, ['client_name' => 'A', 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]])->assertCreated()->json('data.id');
        $to = fn (string $s) => $this->api($owner, 'POST', "/api/inventory/salon/appointments/{$id}/status", ['status' => $s]);

        $to('confirmed')->assertOk()->assertJsonPath('data.status', 'confirmed');
        $to('in_progress')->assertOk();
        $to('confirmed')->assertStatus(422);
        $to('done')->assertOk()->assertJsonPath('data.status', 'done');
        $to('cancelled')->assertStatus(422);
        $to('banana')->assertStatus(422);
        $this->api($owner, 'PUT', "/api/inventory/salon/appointments/{$id}", ['notes' => 'late'])->assertStatus(422);
    }

    public function test_moving_an_appointment_does_not_clash_with_itself_and_is_reminded_again(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 5000, 60);
        $id = $this->book($owner, ['client_name' => 'A', 'staff_id' => (string) $asha->id, 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]])->assertCreated()->json('data.id');
        $this->rows($owner, fn () => DB::table('inventory_appointments')->where('id', $id)->update(['reminder_sent_at' => now()]));

        $this->api($owner, 'PUT', "/api/inventory/salon/appointments/{$id}", ['starts_at' => '2026-10-08 10:30'])->assertOk()->assertJsonPath('data.starts_at', '2026-10-08 10:30')->assertJsonPath('data.ends_at', '2026-10-08 11:30');
        $this->assertNull($this->rows($owner, fn () => DB::table('inventory_appointments')->where('id', $id)->value('reminder_sent_at')), 'a new time is a new reminder');
    }

    public function test_the_checks_on_what_is_booked(): void
    {
        $owner = $this->salon();
        $other = $this->salon('Other');
        $wash = $this->service($owner, 'Wash', 5000, 30);
        $goods = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Oil', 'quantity' => 5, 'min_stock' => 1, 'status' => 'active', 'cost_price' => 1, 'selling_price' => 5])->json('data.id');
        $foreignService = $this->service($other, 'Their service', 100, 30);
        $foreignStaff = $this->stylist($other, 'Foreign');
        $foreignClient = $this->api($other, 'POST', '/api/inventory/customers', ['name' => 'Theirs', 'phone' => '0799000000'])->json('data.id');
        $ok = ['client_name' => 'A', 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]];

        $this->book($owner, array_diff_key($ok, ['services' => 1]))->assertStatus(422);
        $this->book($owner, array_merge($ok, ['services' => []]))->assertStatus(422);
        $this->book($owner, array_merge($ok, ['services' => [['product_id' => $goods]]]))->assertStatus(422);
        $this->book($owner, array_merge($ok, ['services' => [['product_id' => $foreignService]]]))->assertStatus(422);
        $this->book($owner, array_merge($ok, ['staff_id' => (string) $foreignStaff->id]))->assertStatus(422);
        $this->book($owner, array_merge($ok, ['customer_id' => $foreignClient]))->assertStatus(422);
        $this->book($owner, array_merge($ok, ['client_name' => '  ']))->assertStatus(422);
        $this->book($owner, array_merge($ok, ['starts_at' => 'tomorrow']))->assertStatus(422);
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_appointments')->count()), 'nothing half-saved');
    }

    public function test_booking_for_a_known_client_fills_in_their_name_and_phone(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 5000, 30);
        $client = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Rehema', 'phone' => '0711000002'])->assertCreated()->json('data.id');

        $this->book($owner, ['customer_id' => $client, 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]])
            ->assertCreated()->assertJsonPath('data.client_name', 'Rehema')->assertJsonPath('data.client_phone', '0711000002');
    }

    // ------------------------------------------------------------------ the reminder

    private function remind(array $options = [])
    {
        return $this->artisan('salon:remind-appointments', $options);
    }

    private function enableReminders(User $owner): void
    {
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['appointment_reminders' => true])->assertOk()->assertJsonPath('data.appointment_reminders', true);
    }

    public function test_tomorrows_clients_are_texted_once_in_two_languages(): void
    {
        $owner = $this->salon('Glow Salon');
        $wash = $this->service($owner, 'Wash', 5000, 30);
        $braids = $this->service($owner, 'Braids', 40000, 120);
        $this->enableReminders($owner);
        $this->freshSms();
        Carbon::setTestNow(Carbon::parse('2026-10-07 12:30:00', 'UTC')); // 15:30 in Tanzania: tomorrow is the 8th

        $this->book($owner, ['client_name' => 'neema juma', 'client_phone' => '0711000001', 'starts_at' => '2026-10-08 10:30', 'services' => [['product_id' => $braids], ['product_id' => $wash]]])->assertCreated();
        $this->book($owner, ['client_name' => 'Today', 'client_phone' => '0711000002', 'starts_at' => '2026-10-07 17:00', 'services' => [['product_id' => $wash]]])->assertCreated();
        $this->book($owner, ['client_name' => 'Day after', 'client_phone' => '0711000003', 'starts_at' => '2026-10-09 09:00', 'services' => [['product_id' => $wash]]])->assertCreated();
        $this->book($owner, ['client_name' => 'No phone', 'starts_at' => '2026-10-08 12:00', 'services' => [['product_id' => $wash]]])->assertCreated();
        $cancelled = $this->book($owner, ['client_name' => 'Cancelled', 'client_phone' => '0711000004', 'starts_at' => '2026-10-08 13:00', 'services' => [['product_id' => $wash]]])->json('data.id');
        $this->api($owner, 'POST', "/api/inventory/salon/appointments/{$cancelled}/status", ['status' => 'cancelled'])->assertOk();

        $this->remind()->assertExitCode(0);

        $this->assertCount(1, $this->sms->sent);
        $this->assertSame('0711000001', $this->sms->sent[0]['to']);
        $this->assertSame(
            'Habari Neema, ukumbusho: una miadi Glow Salon kesho saa 10:30 (Braids, Wash). Karibu! / '
            . 'Hello Neema, reminder: your appointment at Glow Salon is tomorrow at 10:30 (Braids, Wash). See you!',
            $this->sms->sent[0]['message']
        );

        $this->remind()->assertExitCode(0);
        $this->assertCount(1, $this->sms->sent, 'the same afternoon again: not texted twice');
    }

    public function test_reminders_are_off_until_switched_on_and_a_client_who_opted_out_is_never_texted(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 5000, 30);
        $this->freshSms();
        Carbon::setTestNow(Carbon::parse('2026-10-07 12:30:00', 'UTC'));
        $this->book($owner, ['client_name' => 'A', 'client_phone' => '0711000001', 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]])->assertCreated();

        $this->remind()->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent, 'the owner has not switched them on');

        $this->enableReminders($owner);
        $client = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Opted', 'phone' => '0711000009'])->json('data.id');
        $this->rows($owner, fn () => DB::table('inventory_customers')->where('id', $client)->update(['sms_opt_out' => true]));
        $this->book($owner, ['customer_id' => $client, 'starts_at' => '2026-10-08 11:00', 'services' => [['product_id' => $wash]]])->assertCreated();

        $this->remind(['--dry-run' => true])->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent, 'a dry run sends nothing');
        $this->remind()->assertExitCode(0);
        $this->assertSame(['0711000001'], array_column($this->sms->sent, 'to'), 'the client who asked not to be texted is skipped');
    }

    public function test_a_text_that_could_not_be_sent_is_tried_again_and_a_moved_appointment_is_texted_again(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 5000, 30);
        $this->enableReminders($owner);
        $sms = $this->freshSms();
        Carbon::setTestNow(Carbon::parse('2026-10-07 12:30:00', 'UTC'));
        $id = $this->book($owner, ['client_name' => 'A', 'client_phone' => '0711000001', 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]])->json('data.id');

        $sms->refuseAll();
        $this->remind()->assertExitCode(0);
        $this->assertNull($this->rows($owner, fn () => DB::table('inventory_appointments')->where('id', $id)->value('reminder_sent_at')), 'the claim is given back');

        $this->freshSms();
        $this->remind()->assertExitCode(0);
        $this->assertCount(1, $this->sms->sent);

        $this->api($owner, 'PUT', "/api/inventory/salon/appointments/{$id}", ['starts_at' => '2026-10-08 15:00'])->assertOk();
        $this->remind()->assertExitCode(0);
        $this->assertCount(2, $this->sms->sent, 'moved: told again');
        $this->assertStringContainsString('15:00', $this->sms->sent[1]['message']);
    }

    public function test_two_salons_are_texted_separately_and_never_see_each_others_diary(): void
    {
        $glow = $this->salon('Glow');
        $other = $this->salon('Other');
        $this->enableReminders($glow);
        $this->enableReminders($other);
        $a = $this->service($glow, 'Wash', 5000, 30);
        $b = $this->service($other, 'Wash', 5000, 30);
        $this->freshSms();
        Carbon::setTestNow(Carbon::parse('2026-10-07 12:30:00', 'UTC'));
        $this->book($glow, ['client_name' => 'G', 'client_phone' => '0711000001', 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $a]]])->assertCreated();
        $this->book($other, ['client_name' => 'O', 'client_phone' => '0711000002', 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $b]]])->assertCreated();

        $this->remind()->assertExitCode(0);

        $byPhone = collect($this->sms->sent)->keyBy('to');
        $this->assertCount(2, $byPhone);
        $this->assertStringContainsString('Glow', $byPhone['0711000001']['message']);
        $this->assertStringNotContainsString('Other', $byPhone['0711000001']['message']);
        $this->assertStringContainsString('Other', $byPhone['0711000002']['message']);
    }

    public function test_the_job_is_on_the_daily_schedule_and_the_table_is_tenant_scoped(): void
    {
        $this->artisan('schedule:list')->expectsOutputToContain('salon:remind-appointments')->assertExitCode(0);
        $this->assertContains('inventory_appointments', \App\Support\Tenancy\TenantTables::INVENTORY);
        $this->assertSame(['booked', 'confirmed', 'in_progress'], AppointmentPlanner::ACTIVE);
    }
}
