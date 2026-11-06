<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * A client's own page: the owner's staff make a private link (and can text it), the page shows only that client's visits, points, packages and
 * what they owe, lets them cancel their own appointment, and asks for the link again by phone without saying who the salon's clients are.
 */
class SalonPortalTest extends TestCase
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
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('t')->plainTextToken;
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

    private function sms(): FakeSmsGateway
    {
        $sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $sms);

        return $sms;
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, fn () => TenantContext::runInService('salon', $fn));
    }

    private function client(User $as, string $name, string $phone): int
    {
        return (int) $this->api($as, 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertCreated()->json('data.id');
    }

    private function link(User $as, int $client, array $body = []): string
    {
        $url = $this->api($as, 'POST', "/api/inventory/salon/clients/{$client}/link", $body)->assertOk()->json('data.url');
        $this->assertStringContainsString('/me/', $url);

        return substr($url, strrpos($url, '/') + 1);
    }

    /** A paid visit and a part-paid one, so there is history and something owed. */
    private function visits(User $owner, int $client): void
    {
        $svc = (int) $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Braids', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 50000, 'duration_minutes' => 60])->assertCreated()->json('data.id');
        $this->api($owner, 'POST', '/api/inventory/sales', ['customer_id' => $client, 'payment_status' => 'paid', 'subtotal' => 50000, 'discount' => 0, 'tax' => 0, 'total' => 50000, 'paid_total' => 50000, 'items' => [['product_id' => $svc, 'quantity' => 1, 'unit_price' => 50000, 'staff_id' => (string) $owner->id]], 'payments' => [['amount' => 50000, 'method' => 'cash']]])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/sales', ['customer_id' => $client, 'payment_status' => 'partial', 'subtotal' => 30000, 'discount' => 0, 'tax' => 0, 'total' => 30000, 'paid_total' => 10000, 'items' => [['product_id' => $svc, 'quantity' => 1, 'unit_price' => 30000, 'staff_id' => (string) $owner->id]], 'payments' => [['amount' => 10000, 'method' => 'cash']]])->assertCreated();
    }

    private function appointment(User $owner, int $client, string $when): int
    {
        $svc = (int) $this->rows($owner, fn () => DB::table('inventory_products')->where('is_service', true)->value('id'));

        return (int) $this->api($owner, 'POST', '/api/inventory/salon/appointments', ['customer_id' => $client, 'starts_at' => $when, 'services' => [['product_id' => $svc]]])->assertCreated()->json('data.id');
    }

    public function test_staff_make_a_private_link_that_stays_the_same_and_can_text_it(): void
    {
        $owner = $this->salon();
        $neema = $this->client($owner, 'Neema Joseph', '0712345678');
        $sms = $this->sms();

        $one = $this->link($owner, $neema);
        $this->assertSame($one, $this->link($owner, $neema), 'the same link every time');
        $this->assertGreaterThanOrEqual(30, strlen($one));
        $this->assertCount(0, $sms->sent, 'making a link texts nobody');

        $this->link($owner, $neema, ['send' => true]);
        $this->assertCount(1, $sms->sent);
        $this->assertSame('0712345678', $sms->sent[0]['to']);
        $this->assertStringContainsString("/me/{$one}", $sms->sent[0]['message']);
        $this->assertStringContainsString('Glow Salon', $sms->sent[0]['message']);
    }

    public function test_the_secret_never_leaves_in_the_list_of_clients(): void
    {
        $owner = $this->salon();
        $neema = $this->client($owner, 'Neema Joseph', '0712345678');
        $token = $this->link($owner, $neema);

        $list = json_encode($this->api($owner, 'GET', '/api/inventory/customers')->assertOk()->json('data'));
        $this->assertStringNotContainsString($token, $list);
        $this->assertStringNotContainsString('portal_token', $list);
    }

    public function test_the_page_shows_only_that_clients_things(): void
    {
        $owner = $this->salon();
        $neema = $this->client($owner, 'Neema Joseph', '0712345678');
        $other = $this->client($owner, 'Mary Peter', '0755000111');
        $this->visits($owner, $neema);
        $this->api($owner, 'POST', '/api/inventory/sales', ['customer_id' => $other, 'payment_status' => 'paid', 'subtotal' => 99000, 'discount' => 0, 'tax' => 0, 'total' => 99000, 'paid_total' => 99000, 'items' => [['product_id' => $this->rows($owner, fn () => DB::table('inventory_products')->value('id')), 'quantity' => 1, 'unit_price' => 99000, 'staff_id' => (string) $owner->id]], 'payments' => [['amount' => 99000, 'method' => 'cash']]])->assertCreated();
        $token = $this->link($owner, $neema);

        $d = $this->guest('GET', "/api/public/salon/me/{$token}")->assertOk()->json('data');

        $this->assertSame('Glow Salon', $d['business']);
        $this->assertSame('Neema', $d['client']);
        $this->assertSame(20000.0, (float) $d['owed'], '30,000 less the 10,000 paid');
        $this->assertCount(2, $d['visits']);
        $this->assertSame(['Braids'], $d['visits'][0]['services']);
        $this->assertNotContains(99000.0, array_map('floatval', array_column($d['visits'], 'total')), 'nobody else\'s visit');
        $this->assertSame([], $d['upcoming']);
        $this->assertSame([], $d['packages']);
    }

    public function test_an_unknown_link_is_simply_not_found(): void
    {
        $this->salon();

        $this->guest('GET', '/api/public/salon/me/' . str_repeat('x', 40))->assertNotFound();
        $this->guest('GET', '/api/public/salon/me/short')->assertNotFound();
        $this->get('/me/' . str_repeat('y', 40))->assertNotFound();
    }

    public function test_the_page_itself_opens_without_signing_in(): void
    {
        $owner = $this->salon();
        $token = $this->link($owner, $this->client($owner, 'Neema Joseph', '0712345678'));

        $page = $this->get("/me/{$token}");

        $page->assertOk()->assertHeader('X-Robots-Tag', 'noindex, nofollow');
        $this->assertStringContainsString('Glow Salon', $page->getContent());
        $this->assertStringContainsString('/api/public/salon/me/', $page->getContent());
    }

    public function test_a_client_cancels_only_her_own_appointment(): void
    {
        $owner = $this->salon();
        $neema = $this->client($owner, 'Neema Joseph', '0712345678');
        $mary = $this->client($owner, 'Mary Peter', '0755000111');
        $this->visits($owner, $neema);
        $when = now('Africa/Dar_es_Salaam')->addDays(3)->format('Y-m-d') . ' 10:00';
        $mine = $this->appointment($owner, $neema, $when);
        $hers = $this->appointment($owner, $mary, now('Africa/Dar_es_Salaam')->addDays(3)->format('Y-m-d') . ' 14:00');
        $token = $this->link($owner, $neema);

        $shown = $this->guest('GET', "/api/public/salon/me/{$token}")->json('data.upcoming');
        $this->assertSame([$mine], array_column($shown, 'id'));
        $this->assertTrue($shown[0]['can_cancel']);

        $this->guest('POST', "/api/public/salon/me/{$token}/appointments/{$hers}/cancel")->assertStatus(422);
        $this->guest('POST', "/api/public/salon/me/{$token}/appointments/{$mine}/cancel")->assertOk();

        $this->assertSame('cancelled', $this->rows($owner, fn () => DB::table('inventory_appointments')->where('id', $mine)->value('status')));
        $this->assertSame('booked', $this->rows($owner, fn () => DB::table('inventory_appointments')->where('id', $hers)->value('status')), 'her friend\'s is untouched');
        $this->assertSame([], $this->guest('GET', "/api/public/salon/me/{$token}")->json('data.upcoming'));
        $this->guest('POST', "/api/public/salon/me/{$token}/appointments/{$mine}/cancel")->assertStatus(422);
    }

    public function test_one_salons_link_never_shows_another_salons_client(): void
    {
        $one = $this->salon('One');
        $two = $this->salon('Two');
        $a = $this->client($one, 'Neema Joseph', '0712345678');
        $this->client($two, 'Neema Joseph', '0712345678');
        $token = $this->link($one, $a);

        $d = $this->guest('GET', "/api/public/salon/me/{$token}")->assertOk()->json('data');

        $this->assertSame('One', $d['business']);
    }

    public function test_asking_for_the_link_by_phone_texts_it_and_never_says_whether_the_number_is_known(): void
    {
        $owner = $this->salon();
        $this->client($owner, 'Neema Joseph', '0712 345 678');
        Business::forOwnerId($owner->id)->update(['online_booking' => true, 'booking_slug' => 'glow']);
        $sms = $this->sms();

        $known = $this->guest('POST', '/api/public/salon/book/glow/my-link', ['phone' => '+255712345678'])->assertOk()->json('message');
        $unknown = $this->guest('POST', '/api/public/salon/book/glow/my-link', ['phone' => '0788000999'])->assertOk()->json('message');

        $this->assertSame($known, $unknown, 'the same words either way');
        $this->assertCount(1, $sms->sent, 'only the known number is texted');
        $this->assertSame('0712 345 678', $sms->sent[0]['to']);
        $this->assertMatchesRegularExpression('#/me/[A-Za-z0-9]{40}#', $sms->sent[0]['message']);
    }

    public function test_a_client_who_asked_not_to_be_texted_is_not_texted_either_way(): void
    {
        $owner = $this->salon();
        $neema = $this->client($owner, 'Neema Joseph', '0712345678');
        $this->rows($owner, fn () => DB::table('inventory_customers')->where('id', $neema)->update(['sms_opt_out' => true]));
        Business::forOwnerId($owner->id)->update(['online_booking' => true, 'booking_slug' => 'glow']);
        $sms = $this->sms();

        $this->guest('POST', '/api/public/salon/book/glow/my-link', ['phone' => '0712345678'])->assertOk();
        $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/link", ['send' => true])->assertStatus(422);

        $this->assertCount(0, $sms->sent);
    }
}
