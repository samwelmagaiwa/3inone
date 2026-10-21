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
 * A client booking for themselves from the salon's own page: nobody is signed in, only a salon that switched it on is
 * there at all, and the same rules as the salon's diary apply (hours, days off, no double booking). The page shows free
 * times only, and a robot or a greedy phone number gets nowhere.
 */
class SalonOnlineBookingTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function setUp(): void
    {
        parent::setUp();
        // The page's own request limits are counted per address across the whole run: start each test fresh.
        \Illuminate\Support\Facades\Cache::flush();
        // 09:00 in Tanzania on Wednesday 7 October 2026.
        Carbon::setTestNow(Carbon::parse('2026-10-07 06:00:00', 'UTC'));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function salon(string $name = 'Glow Salon', ?string $slug = 'glow'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0723' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);
        if ($slug !== null) {
            $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['booking_slug' => $slug, 'online_booking' => true])->assertOk();
        }

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

    private function guest(string $method, string $uri, array $body = [])
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->json($method, $uri, $body);
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, fn () => TenantContext::runInService('salon', $fn));
    }

    private function freshSms(): FakeSmsGateway
    {
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);

        return $this->sms;
    }

    private function service(User $as, string $name, int $price, int $minutes = 60, array $extra = []): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', array_merge(['name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price, 'duration_minutes' => $minutes], $extra))->assertCreated()->json('data.id');
    }

    private function book(array $body = [], string $slug = 'glow')
    {
        return $this->guest('POST', "/api/public/salon/book/{$slug}", array_merge(['name' => 'Neema Juma', 'phone' => '0711000001', 'starts_at' => '2026-10-08 10:00'], $body));
    }

    // ------------------------------------------------------------------ switching it on

    public function test_the_owner_chooses_the_address_and_switches_booking_on(): void
    {
        $owner = $this->salon('Glow Salon', null);
        $other = $this->salon('Other', 'taken');
        $asha = $this->person($owner, 'Asha');
        config(['app.url' => 'https://3inone.example']);

        $s = $this->api($owner, 'GET', '/api/inventory/salon/settings')->json('data');
        $this->assertSame([false, null, null], [$s['online_booking'], $s['booking_slug'], $s['booking_url']]);

        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['online_booking' => true])->assertStatus(422);            // no address yet
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['booking_slug' => 'Glow Salon!'])->assertStatus(422);     // not an address
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['booking_slug' => 'ab'])->assertStatus(422);              // too short
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['booking_slug' => '-glow-'])->assertStatus(422);
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['booking_slug' => 'taken'])->assertStatus(422);            // another salon's
        $this->api($asha, 'PUT', '/api/inventory/salon/settings', ['booking_slug' => 'mine', 'online_booking' => true])->assertStatus(403);

        $d = $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['booking_slug' => 'glow-salon', 'online_booking' => true])->assertOk()->json('data');
        $this->assertSame([true, 'glow-salon', 'https://3inone.example/book/glow-salon'], [$d['online_booking'], $d['booking_slug'], $d['booking_url']]);
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['online_booking' => false])->assertOk()->assertJsonPath('data.online_booking', false);
        $this->assertNotNull($other);
    }

    public function test_a_salon_that_is_off_or_unknown_is_not_found(): void
    {
        $owner = $this->salon('Glow Salon', 'glow');
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['online_booking' => false])->assertOk();

        $this->guest('GET', '/api/public/salon/book/glow')->assertStatus(404);
        $this->guest('GET', '/api/public/salon/book/glow/slots?service_ids=1&date=2026-10-08')->assertStatus(404);
        $this->book()->assertStatus(404);
        $this->guest('GET', '/api/public/salon/book/nobody')->assertStatus(404);
        $page = $this->guest('GET', '/book/glow')->assertStatus(404);
        $this->assertStringNotContainsString('Glow', $page->getContent());
    }

    // ------------------------------------------------------------------ what the page shows

    public function test_the_page_lists_active_services_with_other_prices_and_the_people_who_do_the_work(): void
    {
        $owner = $this->salon();
        $this->person($owner, 'Asha');
        $this->person($owner, 'Bahati', 'nail_technician');
        $this->person($owner, 'Mary', 'manager');
        $this->person($owner, 'Acc', 'accountant');
        $this->service($owner, 'Braids', 40000, 180, ['price_options' => [['label' => 'Short', 'price' => 30000], ['label' => 'Long', 'price' => 60000]]]);
        $this->service($owner, 'Wash', 5000, 30);
        $hidden = $this->service($owner, 'Retired', 1000);
        $this->api($owner, 'PUT', "/api/inventory/products/{$hidden}", ['status' => 'inactive'])->assertOk();
        $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Oil', 'quantity' => 5, 'min_stock' => 1, 'status' => 'active', 'cost_price' => 1, 'selling_price' => 5000])->assertCreated();
        $this->service($owner, 'Wash x5', 20000, 30, ['package_sessions' => 5, 'package_service_id' => $this->rows($owner, fn () => DB::table('inventory_products')->where('name', 'Wash')->value('id'))]);

        $d = $this->guest('GET', '/api/public/salon/book/glow')->assertOk()->json('data');

        $this->assertSame('Glow Salon', $d['business']['name']);
        $this->assertSame(['Braids', 'Wash'], array_column($d['services'], 'name'), 'no goods, no retired service, no package');
        $this->assertSame([['label' => 'Short', 'price' => 30000], ['label' => 'Long', 'price' => 60000]], $d['services'][0]['options']);
        $this->assertSame([180, 40000], [$d['services'][0]['minutes'], $d['services'][0]['price']]);
        $this->assertSame(['Asha', 'Bahati'], array_column($d['stylists'], 'name'), 'only the people who do the work');
        $this->assertArrayNotHasKey('email', $d['stylists'][0]);
    }

    public function test_the_page_itself_works_without_sign_in_and_escapes_the_salons_name(): void
    {
        $owner = $this->salon('Glow & <Co>', 'glow');

        $page = $this->guest('GET', '/book/glow')->assertOk();

        $this->assertStringContainsString('Glow &amp; &lt;Co&gt;', $page->getContent());
        $this->assertStringNotContainsString('<Co>', $page->getContent());
        $this->assertStringContainsString('"glow"', $page->getContent());
        $this->assertStringContainsString('noindex', (string) $page->headers->get('X-Robots-Tag'));
        $this->assertNotNull($owner);
    }

    // ------------------------------------------------------------------ free times

    private function slots(array $q = []): array
    {
        return $this->guest('GET', '/api/public/salon/book/glow/slots?' . http_build_query(array_merge(['date' => '2026-10-08'], $q)))->assertOk()->json('data');
    }

    public function test_free_times_run_every_half_hour_through_the_opening_hours(): void
    {
        $owner = $this->salon();
        $this->person($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 5000, 60);

        $d = $this->slots(['service_ids' => $wash]);

        $times = array_column($d['slots'], 'time');
        $this->assertSame(['08:00', '08:30'], array_slice($times, 0, 2));
        $this->assertSame('17:00', end($times), 'a 60-minute visit must finish by six');
        $this->assertSame(60, $d['minutes']);
        $this->assertSame([['id' => (string) $this->rows($owner, fn () => DB::table('users')->where('name', 'Asha')->value('id')), 'name' => 'Asha']], $d['slots'][0]['staff']);
    }

    public function test_a_long_visit_leaves_fewer_times_and_a_stylists_own_hours_are_kept(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $braids = $this->service($owner, 'Braids', 40000, 180);
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha->id}", ['shift_start' => '10:00', 'shift_end' => '16:00'])->assertOk();

        $times = array_column($this->slots(['service_ids' => $braids])['slots'], 'time');

        $this->assertSame(['10:00', '10:30', '11:00', '11:30', '12:00', '12:30', '13:00'], $times, 'three hours, inside ten to four');
    }

    public function test_booked_times_days_off_and_working_days_are_not_offered(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 5000, 60);
        $this->api($owner, 'POST', '/api/inventory/salon/appointments', ['client_name' => 'Taken', 'staff_id' => (string) $asha->id, 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/salon/days-off', ['staff_id' => (string) $asha->id, 'off_on' => '2026-10-09'])->assertCreated();
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha->id}", ['work_days' => [1, 2, 3, 4, 5]])->assertOk();

        $thursday = array_column($this->slots(['service_ids' => $wash])['slots'], 'time');
        $this->assertNotContains('10:00', $thursday);
        $this->assertNotContains('09:30', $thursday, 'a booking at half past nine would run into the one at ten');
        $this->assertContains('09:00', $thursday);
        $this->assertContains('11:00', $thursday, 'back to back is fine');
        $this->assertSame([], $this->slots(['service_ids' => $wash, 'date' => '2026-10-09'])['slots'], 'her day off');
        $this->assertSame([], $this->slots(['service_ids' => $wash, 'date' => '2026-10-10'])['slots'], 'Saturday is not a working day');
    }

    public function test_the_time_must_be_a_little_ahead_and_the_date_not_too_far_off(): void
    {
        $owner = $this->salon();
        $this->person($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 5000, 60);

        $today = array_column($this->slots(['service_ids' => $wash, 'date' => '2026-10-07'])['slots'], 'time');
        $this->assertSame('10:00', $today[0], 'it is nine now and an hour\'s notice is needed');

        $this->guest('GET', "/api/public/salon/book/glow/slots?service_ids={$wash}&date=2026-10-06")->assertStatus(422);
        $this->guest('GET', "/api/public/salon/book/glow/slots?service_ids={$wash}&date=2026-12-30")->assertStatus(422);
        $this->guest('GET', "/api/public/salon/book/glow/slots?service_ids={$wash}&date=2026-12-06")->assertOk();
        $this->guest('GET', '/api/public/salon/book/glow/slots?service_ids=abc&date=2026-10-08')->assertStatus(422);
        $this->guest('GET', '/api/public/salon/book/glow/slots?date=2026-10-08')->assertStatus(422);
        $this->guest('GET', '/api/public/salon/book/glow/slots?service_ids=99999&date=2026-10-08')->assertStatus(422);
    }

    public function test_a_service_only_some_can_do_is_offered_only_with_them_and_a_choice_narrows_it(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $bahati = $this->person($owner, 'Bahati');
        $wash = $this->service($owner, 'Wash', 5000, 60);
        $makeup = $this->service($owner, 'Makeup', 50000, 60, ['staff_ids' => [(string) $bahati->id]]);

        $both = $this->slots(['service_ids' => $wash])['slots'][0];
        $this->assertSame(['Asha', 'Bahati'], array_column($both['staff'], 'name'));
        $this->assertSame(['Bahati'], array_column($this->slots(['service_ids' => $makeup])['slots'][0]['staff'], 'name'));
        $this->assertSame(['Bahati'], array_column($this->slots(['service_ids' => "{$wash},{$makeup}"])['slots'][0]['staff'], 'name'), 'both services: only who can do both');
        $this->assertSame(['Asha'], array_column($this->slots(['service_ids' => $wash, 'staff_id' => (string) $asha->id])['slots'][0]['staff'], 'name'));
        $this->guest('GET', "/api/public/salon/book/glow/slots?service_ids={$makeup}&date=2026-10-08&staff_id={$asha->id}")->assertStatus(422);
    }

    // ------------------------------------------------------------------ booking

    public function test_a_client_books_and_everyone_who_needs_to_know_is_told(): void
    {
        $owner = $this->salon('Glow Salon');
        $manager = $this->person($owner, 'Mary', 'manager');
        $asha = $this->person($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 5000, 60);
        $this->freshSms();

        $res = $this->book(['services' => [['product_id' => $wash]], 'staff_id' => (string) $asha->id, 'notes' => 'First time'])->assertCreated();

        $this->assertSame(['2026-10-08 10:00', '2026-10-08 11:00', 'Asha', 5000], [$res->json('data.starts_at'), $res->json('data.ends_at'), $res->json('data.staff_name'), $res->json('data.total')]);
        $a = $this->rows($owner, fn () => DB::table('inventory_appointments')->first());
        $this->assertSame(['online', 'booked', 'Neema Juma', '0711000001', 'First time'], [$a->source, $a->status, $a->client_name, $a->client_phone, $a->notes]);
        $this->assertSame(1, $this->rows($owner, fn () => DB::table('inventory_customers')->where('phone', '0711000001')->count()), 'a client record was made');

        $this->assertCount(1, $this->sms->sent);
        $this->assertSame('0711000001', $this->sms->sent[0]['to']);
        $this->assertStringContainsString('miadi yako Glow Salon 08/10 10:00 imepokelewa', $this->sms->sent[0]['message']);
        $this->assertStringContainsString('your appointment at Glow Salon on 08/10 10:00 is booked', $this->sms->sent[0]['message']);
        $note = fn (User $u, string $type) => collect($this->api($u, 'GET', '/api/inventory/notifications')->json('data'))->firstWhere('type', $type);
        $this->assertNotNull($note($owner, 'salon_online_booking'));
        $this->assertNotNull($note($manager, 'salon_online_booking'));
        $this->assertSame('Neema Juma - 08/10 10:00', $note($asha, 'salon_new_booking')['body']);

        $listed = $this->api($owner, 'GET', '/api/inventory/salon/appointments?date=2026-10-08')->json('data.0');
        $this->assertSame(['online', 'Neema Juma'], [$listed['source'], $listed['client_name']]);
    }

    public function test_when_nobody_is_chosen_the_first_free_stylist_gets_it_and_a_known_client_is_not_duplicated(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $this->person($owner, 'Bahati');
        $wash = $this->service($owner, 'Wash', 5000, 60);
        $existing = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Neema Old Name', 'phone' => '0711000001'])->json('data.id');
        $this->api($owner, 'POST', '/api/inventory/salon/appointments', ['client_name' => 'Taken', 'staff_id' => (string) $asha->id, 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]])->assertCreated();

        $res = $this->book(['services' => [['product_id' => $wash]]])->assertCreated();

        $this->assertSame('Bahati', $res->json('data.staff_name'), 'Asha is busy then');
        $a = $this->rows($owner, fn () => DB::table('inventory_appointments')->where('source', 'online')->first());
        $this->assertSame([$existing, 'Neema Old Name'], [(int) $a->customer_id, $a->client_name], 'the salon\'s own record of the client');
        $this->assertSame(1, $this->rows($owner, fn () => DB::table('inventory_customers')->where('phone', '0711000001')->count()));
    }

    public function test_a_taken_time_a_past_time_and_a_time_nobody_works_are_refused_and_nothing_is_saved(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 5000, 60);
        $this->api($owner, 'POST', '/api/inventory/salon/appointments', ['client_name' => 'Taken', 'staff_id' => (string) $asha->id, 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]]])->assertCreated();
        $count = fn () => $this->rows($owner, fn () => DB::table('inventory_appointments')->count());

        $this->book(['services' => [['product_id' => $wash]], 'starts_at' => '2026-10-08 10:30'])->assertStatus(422)->assertJsonValidationErrors('starts_at');
        $this->book(['services' => [['product_id' => $wash]], 'starts_at' => '2026-10-07 09:30'])->assertStatus(422);        // inside the notice
        $this->book(['services' => [['product_id' => $wash]], 'starts_at' => '2026-10-06 10:00'])->assertStatus(422);        // yesterday
        $this->book(['services' => [['product_id' => $wash]], 'starts_at' => '2026-10-08 22:00'])->assertStatus(422);        // after hours
        $this->assertSame(1, $count());
    }

    public function test_the_services_come_from_the_salons_list_with_only_its_own_prices(): void
    {
        $owner = $this->salon();
        $this->person($owner, 'Asha');
        $braids = $this->service($owner, 'Braids', 40000, 120, ['price_options' => [['label' => 'Long', 'price' => 60000]]]);
        $other = $this->salon('Other', 'other');
        $theirs = $this->service($other, 'Their service', 100, 30);

        $ok = $this->book(['services' => [['product_id' => $braids, 'label' => 'Long']]])->assertCreated();
        $this->assertSame(60000, $ok->json('data.total'));
        $lines = json_decode($this->rows($owner, fn () => DB::table('inventory_appointments')->value('services')), true);
        $this->assertSame(['Braids', 60000.0, 'Long'], [$lines[0]['name'], (float) $lines[0]['price'], $lines[0]['label']]);

        $this->book(['services' => [['product_id' => $braids, 'label' => 'Tiny']], 'starts_at' => '2026-10-08 15:00'])->assertStatus(422);       // a price the service does not have
        $this->book(['services' => [['product_id' => $theirs]], 'starts_at' => '2026-10-08 15:00'])->assertStatus(422);                           // another salon's service
        $this->book(['services' => [['product_id' => 99999]], 'starts_at' => '2026-10-08 15:00'])->assertStatus(422);
        $this->book(['services' => [], 'starts_at' => '2026-10-08 15:00'])->assertStatus(422);
        $this->assertSame(0, $this->rows($other, fn () => DB::table('inventory_appointments')->count()), 'nothing reached the other salon');
    }

    public function test_the_form_is_checked_and_a_robot_gets_nowhere(): void
    {
        $owner = $this->salon();
        $this->person($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 5000, 60);
        $svc = [['product_id' => $wash]];
        $this->freshSms();

        $this->book(['services' => $svc, 'name' => 'A'])->assertStatus(422);
        $this->book(['services' => $svc, 'phone' => '12345'])->assertStatus(422);
        $this->book(['services' => $svc, 'phone' => '0511000001'])->assertStatus(422);
        $this->book(['services' => $svc, 'starts_at' => 'tomorrow'])->assertStatus(422);
        $this->book(['services' => $svc, 'notes' => str_repeat('x', 501)])->assertStatus(422);

        $trap = $this->book(['services' => $svc, 'website' => 'http://spam.example'])->assertCreated();
        $this->assertSame(0, $trap->json('data.id'), 'looks like it worked');
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_appointments')->count()));
        $this->assertCount(0, $this->sms->sent);
    }

    public function test_a_phone_in_international_form_is_the_same_phone_and_holds_only_a_few_bookings(): void
    {
        $owner = $this->salon();
        $this->person($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 5000, 30);
        $svc = [['product_id' => $wash]];

        $this->book(['services' => $svc, 'phone' => '+255 711 000 001', 'starts_at' => '2026-10-08 09:00'])->assertCreated();
        $this->assertSame('0711000001', $this->rows($owner, fn () => DB::table('inventory_appointments')->value('client_phone')), 'kept the way the salon keeps numbers');
        $this->book(['services' => $svc, 'phone' => '255711000001', 'starts_at' => '2026-10-08 10:00'])->assertCreated();
        $this->book(['services' => $svc, 'phone' => '0711000001', 'starts_at' => '2026-10-08 11:00'])->assertCreated();
        $this->book(['services' => $svc, 'phone' => '0711000001', 'starts_at' => '2026-10-08 12:00'])->assertStatus(422)->assertJsonValidationErrors('phone');
        $this->book(['services' => $svc, 'phone' => '0722000002', 'starts_at' => '2026-10-08 12:00'])->assertCreated();            // somebody else may
    }

    public function test_a_booking_for_one_salon_never_lands_in_another(): void
    {
        $glow = $this->salon('Glow', 'glow');
        $other = $this->salon('Other', 'other');
        $this->person($glow, 'Asha');
        $this->person($other, 'Zawadi');
        $wash = $this->service($glow, 'Wash', 5000, 60);
        $this->service($other, 'Wash', 5000, 60);

        $this->book(['services' => [['product_id' => $wash]]], 'other')->assertStatus(422);            // Glow's service on the other salon's page
        $this->book(['services' => [['product_id' => $wash]]], 'glow')->assertCreated();

        $this->assertSame(1, $this->rows($glow, fn () => DB::table('inventory_appointments')->count()));
        $this->assertSame(0, $this->rows($other, fn () => DB::table('inventory_appointments')->count()));
        $this->assertSame(['Zawadi'], array_column($this->guest('GET', '/api/public/salon/book/other')->json('data.stylists'), 'name'));
    }

    public function test_the_booking_page_is_an_installable_app_with_the_salons_own_name_and_icon(): void
    {
        $this->salon('Glow & <Co>', 'glow');

        $page = $this->guest('GET', '/book/glow')->assertOk()->getContent();
        $this->assertStringContainsString('rel="manifest" href="/book/glow/manifest.webmanifest"', $page);
        $this->assertStringContainsString('rel="icon" href="/book/glow/icon.svg"', $page);
        $this->assertStringContainsString("navigator.serviceWorker.register('/book/' + encodeURIComponent(slug) + '/sw.js'", $page);
        $this->assertStringContainsString("localStorage.setItem(KEY", $page, 'bookings made from the phone are remembered');

        $m = $this->guest('GET', '/book/glow/manifest.webmanifest')->assertOk();
        $this->assertStringContainsString('manifest+json', (string) $m->headers->get('Content-Type'));
        $this->assertSame('Glow & <Co>', $m->json('name'));
        $this->assertSame('/book/glow', $m->json('start_url'));
        $this->assertSame('/book/glow', $m->json('scope'));
        $this->assertSame('standalone', $m->json('display'));

        $icon = $this->guest('GET', '/book/glow/icon.svg')->assertOk();
        $this->assertStringContainsString('image/svg+xml', (string) $icon->headers->get('Content-Type'));
        $this->assertStringContainsString('>G</text>', $icon->getContent());

        $sw = $this->guest('GET', '/book/glow/sw.js')->assertOk();
        $this->assertStringContainsString('javascript', (string) $sw->headers->get('Content-Type'));
        $this->assertSame('/book/glow', $sw->headers->get('Service-Worker-Allowed'));
        $js = $sw->getContent();
        $this->assertStringContainsString("'/api/public/salon/book/' + \"glow\"", $js);
        $this->assertStringNotContainsString('slots', $js, 'free times and bookings are never kept: they must be live');
    }

    public function test_the_app_files_of_a_salon_that_is_off_or_unknown_are_not_found(): void
    {
        $owner = $this->salon('Glow Salon', 'glow');
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['online_booking' => false])->assertOk();
        foreach (['manifest.webmanifest', 'icon.svg', 'sw.js'] as $file) {
            $this->guest('GET', "/book/glow/{$file}")->assertStatus(404);
            $this->guest('GET', "/book/nobody/{$file}")->assertStatus(404);
        }
    }
}
