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
 * What clients say: after a visit a client gets one text with a private link to rate it and leave a comment or a
 * complaint; the page works with nobody signed in, once, for a few days, and only ever reaches its own salon. Staff can
 * write feedback down too; the owner and managers see everything and settle complaints, a stylist only what is about her.
 */
class SalonFeedbackTest extends TestCase
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

    /** Somebody who is not signed in, like a client opening their link. */
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

    private function at(string $when): void
    {
        Carbon::setTestNow(Carbon::parse($when, 'UTC'));
    }

    private function freshSms(): FakeSmsGateway
    {
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);

        return $this->sms;
    }

    private function service(User $as, string $name = 'Wash', int $price = 10000): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price])->assertCreated()->json('data.id');
    }

    private function client(User $as, string $name = 'neema juma', string $phone = '0711000001'): int
    {
        return $this->api($as, 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertCreated()->json('data.id');
    }

    private function visit(User $as, ?int $client, array $lines, array $extra = [])
    {
        $subtotal = array_sum(array_map(fn ($l) => $l[1] * $l[2], $lines));

        return $this->api($as, 'POST', '/api/inventory/sales', array_merge(array_filter([
            'customer_id' => $client, 'payment_status' => 'paid', 'subtotal' => $subtotal, 'discount' => 0, 'tax' => 0, 'total' => $subtotal, 'paid_total' => $subtotal,
            'items' => array_map(fn ($l) => array_filter(['product_id' => $l[0], 'quantity' => $l[1], 'unit_price' => $l[2], 'staff_id' => $l[3] ?? null]), $lines),
        ], fn ($v) => $v !== null), $extra));
    }

    private function switchOn(User $owner): void
    {
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['feedback_sms' => true])->assertOk()->assertJsonPath('data.feedback_sms', true);
    }

    private function token(User $owner): ?string
    {
        return $this->rows($owner, fn () => DB::table('inventory_feedback_requests')->orderByDesc('id')->value('token'));
    }

    // ------------------------------------------------------------------ the text after a visit

    public function test_nothing_is_sent_until_the_owner_switches_it_on(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner);
        $neema = $this->client($owner);
        $this->freshSms();

        $this->visit($owner, $neema, [[$wash, 1, 10000]])->assertCreated();

        $this->assertCount(0, $this->sms->sent);
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_feedback_requests')->count()));
    }

    public function test_a_paid_visit_sends_one_text_with_a_private_link(): void
    {
        config(['app.url' => 'https://3inone.example']);
        $owner = $this->salon('Glow Salon');
        $asha = $this->person($owner, 'Asha');
        $bahati = $this->person($owner, 'Bahati');
        $braids = $this->service($owner, 'Braids', 40000);
        $wash = $this->service($owner, 'Wash', 5000);
        $neema = $this->client($owner);
        $this->switchOn($owner);
        $this->freshSms();

        $this->visit($owner, $neema, [[$wash, 1, 5000, (string) $bahati->id], [$braids, 1, 40000, (string) $asha->id]])->assertCreated();

        $this->assertCount(1, $this->sms->sent);
        $token = $this->token($owner);
        $this->assertSame('0711000001', $this->sms->sent[0]['to']);
        $this->assertSame(
            "Asante Neema kwa kutembelea Glow Salon! Tupe maoni yako: https://3inone.example/f/{$token} / "
            . "Thank you Neema for visiting Glow Salon! Tell us how it went: https://3inone.example/f/{$token}",
            $this->sms->sent[0]['message']
        );
        $req = $this->rows($owner, fn () => DB::table('inventory_feedback_requests')->first());
        $this->assertSame('Asha', $req->staff_name, 'the stylist of the main service (the dearest one)');
        $this->assertGreaterThan(30, strlen($token));
    }

    public function test_no_text_for_goods_only_a_walk_in_no_phone_or_someone_who_opted_out(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner);
        $oil = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Oil', 'quantity' => 9, 'min_stock' => 1, 'status' => 'active', 'cost_price' => 1, 'selling_price' => 5000])->json('data.id');
        $neema = $this->client($owner);
        $quiet = $this->client($owner, 'Quiet', '0711000002');
        $nophone = (int) $this->rows($owner, fn () => DB::table('inventory_customers')->insertGetId(['name' => 'Nophone', 'phone' => '', 'created_at' => now(), 'updated_at' => now()]));
        $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$quiet}", ['sms_opt_out' => true])->assertOk();
        $this->switchOn($owner);
        $this->freshSms();

        $this->visit($owner, $neema, [[$oil, 1, 5000]])->assertCreated();          // goods only
        $this->visit($owner, null, [[$wash, 1, 10000]])->assertCreated();          // walk-in
        $this->visit($owner, $quiet, [[$wash, 1, 10000]])->assertCreated();        // asked not to be texted
        $this->visit($owner, $nophone, [[$wash, 1, 10000]])->assertCreated();      // no number

        $this->assertCount(0, $this->sms->sent);
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_feedback_requests')->count()));
    }

    public function test_a_debt_is_asked_about_only_when_it_is_paid_off_and_only_once(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner);
        $neema = $this->client($owner);
        $this->switchOn($owner);
        $this->freshSms();

        $id = $this->visit($owner, $neema, [[$wash, 1, 10000]], ['payment_status' => 'debt', 'paid_total' => 0])->assertCreated()->json('data.id');
        $this->assertCount(0, $this->sms->sent);
        $this->api($owner, 'POST', "/api/inventory/sales/{$id}/payments", ['amount' => 4000, 'method' => 'cash'])->assertOk();
        $this->assertCount(0, $this->sms->sent, 'part paid');
        $this->api($owner, 'POST', "/api/inventory/sales/{$id}/payments", ['amount' => 6000, 'method' => 'cash'])->assertOk();
        $this->assertCount(1, $this->sms->sent);
        $this->assertSame(1, $this->rows($owner, fn () => DB::table('inventory_feedback_requests')->count()));
    }

    public function test_a_text_that_could_not_be_sent_leaves_no_link_behind_and_never_fails_the_sale(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner);
        $neema = $this->client($owner);
        $this->switchOn($owner);
        $this->freshSms()->refuseAll();

        $this->visit($owner, $neema, [[$wash, 1, 10000]])->assertCreated();

        $this->assertSame(1, $this->rows($owner, fn () => DB::table('inventory_sales')->count()), 'the sale is saved');
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_feedback_requests')->count()), 'but no link that nobody was told about');
    }

    // ------------------------------------------------------------------ the client's page and answer

    private function asked(User $owner, string $name = 'Glow Salon'): string
    {
        $asha = $this->person($owner, 'Asha');
        $wash = $this->service($owner);
        $neema = $this->client($owner);
        $this->switchOn($owner);
        $this->freshSms();
        $this->visit($owner, $neema, [[$wash, 1, 10000, (string) $asha->id]])->assertCreated();

        return (string) $this->token($owner);
    }

    public function test_the_link_tells_who_is_asking_without_anyone_signed_in(): void
    {
        $owner = $this->salon('Glow Salon');
        $token = $this->asked($owner);

        $this->guest('GET', "/api/public/salon/feedback/{$token}")->assertOk()
            ->assertJsonPath('data.business', 'Glow Salon')->assertJsonPath('data.stylist', 'Asha')->assertJsonPath('data.client', 'Neema');
        $this->guest('GET', '/api/public/salon/feedback/' . str_repeat('x', 40))->assertStatus(404);
        $this->guest('GET', '/api/public/salon/feedback/short')->assertStatus(404);
    }

    public function test_a_rating_and_comment_are_saved_for_that_salon_and_that_stylist_and_the_link_is_used_up(): void
    {
        $owner = $this->salon();
        $manager = $this->person($owner, 'Mary', 'manager');
        $token = $this->asked($owner);

        $this->guest('POST', "/api/public/salon/feedback/{$token}", ['rating' => 5, 'message' => 'Lovely braids'])->assertCreated();

        $f = $this->rows($owner, fn () => DB::table('inventory_feedback')->first());
        $this->assertSame(['review', 5, 'Lovely braids', 'link', 'Asha', 'new'], [$f->kind, (int) $f->rating, $f->message, $f->source, $f->staff_name, $f->status]);
        $this->assertNotNull($f->customer_id);
        $this->guest('POST', "/api/public/salon/feedback/{$token}", ['rating' => 1])->assertStatus(422);
        $this->guest('GET', "/api/public/salon/feedback/{$token}")->assertStatus(404);
        $this->assertSame(1, $this->rows($owner, fn () => DB::table('inventory_feedback')->count()), 'the second try saved nothing');
        $this->assertCount(0, collect($this->api($manager, 'GET', '/api/inventory/notifications')->json('data'))->where('type', 'salon_complaint'), 'a good review is not a complaint');
    }

    public function test_a_comment_alone_is_enough_but_nothing_at_all_or_a_silly_rating_is_not(): void
    {
        $owner = $this->salon();
        $token = $this->asked($owner);

        $this->guest('POST', "/api/public/salon/feedback/{$token}", [])->assertStatus(422);
        $this->guest('POST', "/api/public/salon/feedback/{$token}", ['rating' => 9])->assertStatus(422);
        $this->guest('POST', "/api/public/salon/feedback/{$token}", ['rating' => 3, 'message' => str_repeat('x', 501)])->assertStatus(422);
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_feedback')->count()), 'the link is still good after those');
        $this->guest('POST', "/api/public/salon/feedback/{$token}", ['message' => 'Waited too long'])->assertCreated();
        $f = $this->rows($owner, fn () => DB::table('inventory_feedback')->first());
        $this->assertSame([null, 'Waited too long'], [$f->rating, $f->message]);
    }

    public function test_a_complaint_tells_the_owner_and_managers_at_once_but_not_the_stylist(): void
    {
        $owner = $this->salon();
        $manager = $this->person($owner, 'Mary', 'manager');
        $asha = $this->person($owner, 'Asha 2');
        $token = $this->asked($owner);

        $this->guest('POST', "/api/public/salon/feedback/{$token}", ['rating' => 1, 'message' => 'She burnt my hair', 'complaint' => true])->assertCreated();

        $this->assertSame('complaint', $this->rows($owner, fn () => DB::table('inventory_feedback')->value('kind')));
        foreach ([$owner, $manager] as $who) {
            $n = collect($this->api($who, 'GET', '/api/inventory/notifications')->json('data'))->firstWhere('type', 'salon_complaint');
            $this->assertNotNull($n);
            $this->assertSame('Asha: She burnt my hair', $n['body']);
        }
        $this->assertNull(collect($this->api($asha, 'GET', '/api/inventory/notifications')->json('data'))->firstWhere('type', 'salon_complaint'));
    }

    public function test_the_link_stops_working_after_its_days_are_up(): void
    {
        $owner = $this->salon();
        $this->at('2026-10-07 10:00:00');
        $token = $this->asked($owner);

        $this->at('2026-10-20 10:00:00');
        $this->guest('GET', "/api/public/salon/feedback/{$token}")->assertOk();
        $this->at('2026-10-22 10:00:00');
        $this->guest('GET', "/api/public/salon/feedback/{$token}")->assertStatus(404);
        $this->guest('POST', "/api/public/salon/feedback/{$token}", ['rating' => 5])->assertStatus(422);
    }

    public function test_an_answer_only_ever_reaches_the_salon_whose_link_it_was(): void
    {
        $glow = $this->salon('Glow');
        $other = $this->salon('Other');
        $token = $this->asked($glow);

        $this->guest('POST', "/api/public/salon/feedback/{$token}", ['rating' => 4])->assertCreated();

        $this->assertSame(1, $this->rows($glow, fn () => DB::table('inventory_feedback')->count()));
        $this->assertSame(0, $this->rows($other, fn () => DB::table('inventory_feedback')->count()));
        $this->assertSame([], $this->api($other, 'GET', '/api/inventory/salon/feedback')->json('data.feedback'));
    }

    public function test_the_page_a_client_opens_says_who_asks_works_without_sign_in_and_is_private(): void
    {
        $owner = $this->salon('Glow & <Co>');
        $token = $this->asked($owner);

        $page = $this->guest('GET', "/f/{$token}");

        $page->assertOk();
        $html = $page->getContent();
        $this->assertStringContainsString('Glow &amp; &lt;Co&gt;', $html, 'the salon\'s name is escaped');
        $this->assertStringNotContainsString('<Co>', $html);
        $this->assertStringContainsString('Habari Neema', $html);
        $this->assertStringContainsString($token, $html);
        $this->assertStringContainsString('noindex', (string) $page->headers->get('X-Robots-Tag'));
        $this->assertStringContainsString('no-store', (string) $page->headers->get('Cache-Control'));

        $bad = $this->guest('GET', '/f/' . str_repeat('y', 40))->assertStatus(404);
        $this->assertStringNotContainsString('Glow', $bad->getContent());
    }

    // ------------------------------------------------------------------ for the salon

    public function test_staff_write_down_a_review_or_a_complaint_with_the_checks_it_needs(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $stranger = $this->person($this->salon('Other'), 'Stranger');
        $neema = $this->client($owner);

        $this->api($owner, 'POST', '/api/inventory/salon/feedback', ['kind' => 'review', 'rating' => 5, 'message' => 'Great', 'customer_id' => $neema, 'staff_id' => (string) $asha->id])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/salon/feedback', ['kind' => 'complaint'])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/feedback', ['kind' => 'review'])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/feedback', ['kind' => 'review', 'rating' => 6])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/feedback', ['kind' => 'gossip', 'rating' => 3])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/feedback', ['kind' => 'review', 'rating' => 3, 'staff_id' => (string) $stranger->id])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/feedback', ['kind' => 'review', 'rating' => 3, 'customer_id' => 99999])->assertStatus(422);
        $this->assertSame(1, $this->rows($owner, fn () => DB::table('inventory_feedback')->count()));
    }

    public function test_the_owner_sees_everything_with_averages_and_a_stylist_only_what_is_about_her(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $bahati = $this->person($owner, 'Bahati');
        $say = fn (array $b) => $this->api($owner, 'POST', '/api/inventory/salon/feedback', $b)->assertCreated();
        $say(['kind' => 'review', 'rating' => 5, 'staff_id' => (string) $asha->id]);
        $say(['kind' => 'review', 'rating' => 4, 'staff_id' => (string) $asha->id]);
        $say(['kind' => 'review', 'rating' => 2, 'staff_id' => (string) $bahati->id, 'message' => 'Slow']);
        $say(['kind' => 'complaint', 'message' => 'Dirty towels']);

        $all = $this->api($owner, 'GET', '/api/inventory/salon/feedback')->assertOk()->json('data');
        $this->assertSame([3.7, 3, 1, 4], [$all['summary']['average'], $all['summary']['ratings'], $all['summary']['open_complaints'], $all['summary']['total']]);
        $this->assertSame([['Asha', 4.5, 2], ['Bahati', 2, 1]], array_map(fn ($s) => [$s['name'], $s['average'], $s['ratings']], $all['summary']['by_staff']));
        $this->assertSame('complaint', $all['feedback'][0]['kind'], 'what is new and unsettled first, then the newest');

        $mine = $this->api($asha, 'GET', '/api/inventory/salon/feedback')->assertOk()->json('data');
        $this->assertSame([4.5, 2, 2], [$mine['summary']['average'], $mine['summary']['ratings'], $mine['summary']['total']]);
        $this->assertSame([], $mine['summary']['by_staff'], 'a stylist does not see the others\' averages');
        $this->assertSame(['Asha', 'Asha'], array_column($mine['feedback'], 'staff_name'));

        $this->assertCount(1, $this->api($owner, 'GET', '/api/inventory/salon/feedback?kind=complaint')->json('data.feedback'));
        $this->assertCount(3, $this->api($owner, 'GET', '/api/inventory/salon/feedback?kind=review')->json('data.feedback'));
        $this->api($owner, 'GET', '/api/inventory/salon/feedback?kind=nonsense')->assertStatus(422);
    }

    public function test_the_owner_settles_a_complaint_once_and_a_stylist_cannot(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $id = $this->api($owner, 'POST', '/api/inventory/salon/feedback', ['kind' => 'complaint', 'message' => 'Dirty towels'])->json('data.id');

        $this->api($asha, 'POST', "/api/inventory/salon/feedback/{$id}/resolve", ['note' => 'Fixed'])->assertStatus(403);
        $this->api($owner, 'POST', "/api/inventory/salon/feedback/{$id}/resolve", ['note' => 'New towels bought'])->assertOk();
        $this->api($owner, 'POST', "/api/inventory/salon/feedback/{$id}/resolve", [])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/feedback/99999/resolve', [])->assertStatus(404);

        $d = $this->api($owner, 'GET', '/api/inventory/salon/feedback')->json('data');
        $this->assertSame([0, 'resolved', 'New towels bought'], [$d['summary']['open_complaints'], $d['feedback'][0]['status'], $d['feedback'][0]['resolution']]);
        $this->assertCount(1, $this->api($owner, 'GET', '/api/inventory/salon/feedback?status=resolved')->json('data.feedback'));
        $this->assertCount(0, $this->api($owner, 'GET', '/api/inventory/salon/feedback?status=new')->json('data.feedback'));
    }
}
