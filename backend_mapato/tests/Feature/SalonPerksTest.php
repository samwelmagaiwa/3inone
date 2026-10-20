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
 * What brings a client back: loyalty points (earned when a sale is fully paid, spent as a discount, taken back when the
 * sale is cancelled), a referral bonus, vouchers, and prepaid packages. All of it is salon-only and off or empty until
 * the owner sets it up; the shop's sale is untouched.
 */
class SalonPerksTest extends TestCase
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

    private function api(User $as, string $method, string $uri, array $body = [], bool $salon = true)
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $request = $this->withHeader('Authorization', "Bearer {$token}");

        return ($salon ? $request->withHeader('X-Service', 'salon') : $request)->json($method, $uri, $body);
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, fn () => TenantContext::runInService('salon', $fn));
    }

    private function at(string $when): void
    {
        Carbon::setTestNow(Carbon::parse($when, 'UTC'));
    }

    private function service(User $as, string $name, int $price, array $extra = []): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', array_merge(['name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price], $extra))->assertCreated()->json('data.id');
    }

    private function client(User $as, string $name, string $phone): int
    {
        return $this->api($as, 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertCreated()->json('data.id');
    }

    /** Lines: [product_id, quantity, unit_price, (staff_id), (package_id)]. */
    private function sell(User $as, array $lines, array $extra = [], bool $salon = true)
    {
        $subtotal = array_sum(array_map(fn (array $i) => $i[1] * $i[2], $lines));
        $discount = $extra['discount'] ?? 0;
        $total = $subtotal - $discount;

        return $this->api($as, 'POST', '/api/inventory/sales', array_merge([
            'payment_status' => 'paid', 'subtotal' => $subtotal, 'discount' => 0, 'tax' => 0, 'total' => $total, 'paid_total' => $total,
            'items' => array_map(fn (array $i) => array_filter(['product_id' => $i[0], 'quantity' => $i[1], 'unit_price' => $i[2], 'staff_id' => $i[3] ?? null, 'package_id' => $i[4] ?? null], fn ($v) => $v !== null), $lines),
        ], $extra), $salon);
    }

    private function points(User $as, int $client): int
    {
        return (int) $this->rows($as, fn () => DB::table('inventory_loyalty_ledger')->where('customer_id', $client)->sum('points'));
    }

    private function loyaltyOn(User $owner, int $per = 1000, int $value = 100, int $referral = 50): void
    {
        $this->api($owner, 'PUT', '/api/inventory/salon/loyalty/settings', ['on' => true, 'per' => $per, 'value' => $value, 'referral' => $referral])->assertOk();
    }

    // ------------------------------------------------------------------ loyalty points

    public function test_nothing_is_earned_until_the_owner_switches_points_on(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 25000);
        $neema = $this->client($owner, 'Neema', '0711000001');

        $this->sell($owner, [[$wash, 1, 25000]], ['customer_id' => $neema])->assertCreated();

        $this->assertSame(0, $this->points($owner, $neema));
        $s = $this->api($owner, 'GET', '/api/inventory/salon/loyalty/settings')->json('data');
        $this->assertSame([false, 1000, 100, 50], [$s['on'], $s['per'], $s['value'], $s['referral']], 'the usual numbers wait, switched off');
    }

    public function test_a_paid_sale_earns_a_point_for_every_so_many_shillings_of_what_was_paid_for(): void
    {
        $owner = $this->salon();
        $this->loyaltyOn($owner);
        $wash = $this->service($owner, 'Wash', 25500);
        $neema = $this->client($owner, 'Neema', '0711000001');

        $id = $this->sell($owner, [[$wash, 1, 25500]], ['customer_id' => $neema, 'discount' => 500, 'discount_reason' => 'Loyal'])->assertCreated()->json('data.id');

        $this->assertSame(25, $this->points($owner, $neema), '25,000 after the discount: 25 points; the rest of a thousand earns none');
        $this->assertSame(25, (int) $this->rows($owner, fn () => DB::table('inventory_sales')->where('id', $id)->value('points_earned')));
        $this->sell($owner, [[$wash, 1, 25500]])->assertCreated();                                   // a walk-in earns nobody anything
        $this->assertSame(25, $this->points($owner, $neema));
    }

    public function test_a_debt_earns_its_points_only_when_it_is_paid_off(): void
    {
        $owner = $this->salon();
        $this->loyaltyOn($owner);
        $wash = $this->service($owner, 'Wash', 20000);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $id = $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema, 'payment_status' => 'debt', 'paid_total' => 0])->assertCreated()->json('data.id');
        $this->assertSame(0, $this->points($owner, $neema));

        $this->api($owner, 'POST', "/api/inventory/sales/{$id}/payments", ['amount' => 5000, 'method' => 'cash'])->assertOk();
        $this->assertSame(0, $this->points($owner, $neema), 'part paid: nothing yet');
        $this->api($owner, 'POST', "/api/inventory/sales/{$id}/payments", ['amount' => 15000, 'method' => 'mpesa'])->assertOk();
        $this->assertSame(20, $this->points($owner, $neema));
    }

    public function test_points_are_spent_as_a_discount_and_a_cancelled_sale_gives_everything_back(): void
    {
        $owner = $this->salon();
        $this->loyaltyOn($owner);
        $wash = $this->service($owner, 'Wash', 20000);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema])->assertCreated();            // 20 points
        $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema])->assertCreated();            // 40 points

        // 30 points are worth 3,000 off; the sale must really give that discount
        $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema, 'redeem_points' => 30, 'discount' => 1000, 'discount_reason' => 'x'])->assertStatus(422)->assertJsonValidationErrors('discount');
        $id = $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema, 'redeem_points' => 30, 'discount' => 3000])->assertCreated()->json('data.id');

        $row = $this->rows($owner, fn () => DB::table('inventory_sales')->where('id', $id)->first());
        $this->assertSame([3000.0, 'Pointi / Loyalty points', 30, 17], [(float) $row->discount, $row->discount_reason, (int) $row->points_redeemed, (int) $row->points_earned], 'the reason is filled in; 17,000 paid earns 17');
        $this->assertSame(40 - 30 + 17, $this->points($owner, $neema));

        $this->api($owner, 'POST', "/api/inventory/sales/{$id}/cancel", ['reason' => 'Mistake'])->assertOk();
        $this->assertSame(40, $this->points($owner, $neema), 'the 30 are back and the 17 are taken away');
    }

    public function test_points_cannot_be_spent_that_are_not_there_or_without_a_client_or_while_off(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 20000);
        $neema = $this->client($owner, 'Neema', '0711000001');

        $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema, 'redeem_points' => 5, 'discount' => 500, 'discount_reason' => 'x'])->assertStatus(422);   // off
        $this->loyaltyOn($owner);
        $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema, 'redeem_points' => 5, 'discount' => 500, 'discount_reason' => 'x'])->assertStatus(422);   // has none
        $this->sell($owner, [[$wash, 1, 20000]], ['redeem_points' => 5, 'discount' => 500, 'discount_reason' => 'x'])->assertStatus(422);                         // nobody named
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_sales')->count()), 'nothing half-saved');
    }

    public function test_points_never_discount_more_than_the_sale(): void
    {
        $owner = $this->salon();
        $this->loyaltyOn($owner, 1000, 1000);
        $wash = $this->service($owner, 'Wash', 20000);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/loyalty/adjust", ['points' => 100, 'note' => 'Welcome gift'])->assertOk();

        $id = $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema, 'redeem_points' => 100, 'discount' => 20000, 'paid_total' => 0, 'total' => 0])->assertCreated()->json('data.id');

        $this->assertSame(20000.0, (float) $this->rows($owner, fn () => DB::table('inventory_sales')->where('id', $id)->value('discount')), '100 points are worth 100,000 but the sale was 20,000');
    }

    public function test_a_client_who_was_sent_earns_the_sender_points_once(): void
    {
        $owner = $this->salon();
        $this->loyaltyOn($owner);
        $wash = $this->service($owner, 'Wash', 20000);
        $friend = $this->client($owner, 'Rehema', '0711000002');
        $neema = $this->client($owner, 'Neema', '0711000001');
        $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$neema}", ['referred_by' => $friend])->assertOk();

        $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema, 'payment_status' => 'debt', 'paid_total' => 0])->assertCreated();
        $this->assertSame(0, $this->points($owner, $friend), 'nothing until they have paid');
        $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema])->assertCreated();
        $this->assertSame(50, $this->points($owner, $friend));
        $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema])->assertCreated();
        $this->assertSame(50, $this->points($owner, $friend), 'once, ever');
        $this->assertSame(40, $this->points($owner, $neema), 'the debt was never paid, so only the two paid sales earn');

        $ledger = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$friend}/loyalty")->json('data');
        $this->assertSame(['referral', 50], [$ledger['ledger'][0]['kind'], $ledger['ledger'][0]['points']]);
        $this->assertStringContainsString('Neema', $ledger['ledger'][0]['note']);
    }

    public function test_a_referral_bonus_of_nothing_gives_nothing(): void
    {
        $owner = $this->salon();
        $this->loyaltyOn($owner, 1000, 100, 0);
        $wash = $this->service($owner, 'Wash', 20000);
        $friend = $this->client($owner, 'Rehema', '0711000002');
        $neema = $this->client($owner, 'Neema', '0711000001');
        $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$neema}", ['referred_by' => $friend])->assertOk();

        $this->sell($owner, [[$wash, 1, 20000]], ['customer_id' => $neema])->assertCreated();

        $this->assertSame(0, $this->points($owner, $friend));
    }

    public function test_a_clients_points_and_what_they_are_worth_are_shown_and_adjusted_by_hand(): void
    {
        $owner = $this->salon();
        $this->loyaltyOn($owner);
        $asha = $this->person($owner, 'Asha');
        $neema = $this->client($owner, 'Neema', '0711000001');

        $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/loyalty/adjust", ['points' => 40, 'note' => 'Welcome gift'])->assertOk()->assertJsonPath('data.balance', 40);
        $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/loyalty/adjust", ['points' => -50, 'note' => 'Too many'])->assertStatus(422);
        $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/loyalty/adjust", ['points' => 0, 'note' => 'Nothing'])->assertStatus(422);
        $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/loyalty/adjust", ['points' => 5])->assertStatus(422);
        $this->api($asha, 'POST', "/api/inventory/salon/clients/{$neema}/loyalty/adjust", ['points' => 5, 'note' => 'Sneaky'])->assertStatus(403);
        $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/loyalty/adjust", ['points' => -10, 'note' => 'Correction'])->assertOk()->assertJsonPath('data.balance', 30);

        $d = $this->api($asha, 'GET', "/api/inventory/salon/clients/{$neema}/loyalty")->assertOk()->json('data');
        $this->assertSame([true, 30, 3000], [$d['on'], $d['balance'], $d['worth']]);
        $this->assertSame(['adjust', -10, 'Correction'], [$d['ledger'][0]['kind'], $d['ledger'][0]['points'], $d['ledger'][0]['note']]);
        $this->assertSame(30, $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/history")->json('data.stats.loyalty_points'));
    }

    public function test_the_settings_are_checked_and_only_a_manager_changes_them(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');

        $this->api($asha, 'PUT', '/api/inventory/salon/loyalty/settings', ['on' => true])->assertStatus(403);
        $this->api($owner, 'PUT', '/api/inventory/salon/loyalty/settings', ['per' => 0])->assertStatus(422);
        $this->api($owner, 'PUT', '/api/inventory/salon/loyalty/settings', ['value' => -1])->assertStatus(422);
        $this->api($owner, 'PUT', '/api/inventory/salon/loyalty/settings', ['on' => true, 'per' => 500, 'value' => 50, 'referral' => 10])->assertOk()->assertJsonPath('data.per', 500);
        $this->assertSame([true, 500, 50, 10], array_values($this->api($asha, 'GET', '/api/inventory/salon/loyalty/settings')->json('data')));
    }

    // ------------------------------------------------------------------ vouchers

    private function voucher(User $owner, array $extra = [])
    {
        return $this->api($owner, 'POST', '/api/inventory/salon/vouchers', array_merge(['code' => 'welcome10', 'kind' => 'percent', 'value' => 10], $extra));
    }

    public function test_a_voucher_is_made_with_an_upper_case_code_and_checked(): void
    {
        $owner = $this->salon();

        $this->voucher($owner)->assertCreated()->assertJsonPath('data.code', 'WELCOME10');
        $this->voucher($owner)->assertStatus(422);                                                     // the same code again
        $this->voucher($owner, ['code' => 'a'])->assertStatus(422);
        $this->voucher($owner, ['code' => 'bad code!'])->assertStatus(422);
        $this->voucher($owner, ['code' => 'big', 'value' => 150])->assertStatus(422);                  // 150%
        $this->voucher($owner, ['code' => 'zero', 'kind' => 'amount', 'value' => 0])->assertStatus(422);
        $this->voucher($owner, ['code' => 'odd', 'kind' => 'gift'])->assertStatus(422);
        $this->voucher($owner, ['code' => 'amt', 'kind' => 'amount', 'value' => 5000, 'expires_on' => '2026-12-31', 'max_uses' => 2])->assertCreated();
        $list = $this->api($owner, 'GET', '/api/inventory/salon/vouchers')->json('data');
        $this->assertEqualsCanonicalizing(['WELCOME10', 'AMT'], array_column($list, 'code'));
    }

    public function test_what_a_voucher_takes_off_is_shown_before_the_sale(): void
    {
        $owner = $this->salon();
        $this->voucher($owner, ['code' => 'ten'])->assertCreated();
        $this->voucher($owner, ['code' => 'five', 'kind' => 'amount', 'value' => 5000])->assertCreated();

        $this->assertSame([5000, '10%'], array_values(array_map(fn ($v) => $v, $this->api($owner, 'GET', '/api/inventory/salon/vouchers/check?code=ten&subtotal=50000')->json('data'))));
        $this->assertSame(5000, $this->api($owner, 'GET', '/api/inventory/salon/vouchers/check?code=five&subtotal=50000')->json('data.discount'));
        $this->assertSame(3000, $this->api($owner, 'GET', '/api/inventory/salon/vouchers/check?code=five&subtotal=3000')->json('data.discount'), 'never more than the sale');
        $res = $this->api($owner, 'GET', '/api/inventory/salon/vouchers/check?code=nope&subtotal=1000')->assertStatus(422);
        $this->assertStringContainsString('Kuponi hii haipo au imezimwa. / This voucher does not exist or is switched off.', $res->json('errors.code.0'));
    }

    public function test_a_voucher_is_used_with_its_discount_and_its_reason_and_counted(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 50000);
        $this->voucher($owner, ['code' => 'ten', 'max_uses' => 2])->assertCreated();

        $this->sell($owner, [[$wash, 1, 50000]], ['voucher_code' => 'ten', 'discount' => 1000])->assertStatus(422)->assertJsonValidationErrors('discount');
        $id = $this->sell($owner, [[$wash, 1, 50000]], ['voucher_code' => 'ten', 'discount' => 5000])->assertCreated()->json('data.id');

        $row = $this->rows($owner, fn () => DB::table('inventory_sales')->where('id', $id)->first());
        $this->assertSame(['Kuponi / Voucher TEN', 'TEN'], [$row->discount_reason, $row->voucher_code]);
        $this->assertSame(1, (int) $this->rows($owner, fn () => DB::table('inventory_vouchers')->where('code', 'TEN')->value('used_count')));

        $this->sell($owner, [[$wash, 1, 50000]], ['voucher_code' => 'ten', 'discount' => 5000])->assertCreated();
        $this->sell($owner, [[$wash, 1, 50000]], ['voucher_code' => 'ten', 'discount' => 5000])->assertStatus(422)->assertJsonValidationErrors('voucher_code');
        $this->assertSame(2, (int) $this->rows($owner, fn () => DB::table('inventory_sales')->whereNotNull('voucher_code')->count()), 'the refused one saved nothing');
    }

    public function test_an_expired_or_switched_off_voucher_is_refused_and_a_cancelled_sale_frees_a_use(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 50000);
        $this->at('2026-10-07 10:00:00');
        $old = $this->voucher($owner, ['code' => 'old', 'expires_on' => '2026-10-06'])->json('data.id');
        $off = $this->voucher($owner, ['code' => 'off'])->json('data.id');
        $one = $this->voucher($owner, ['code' => 'one', 'max_uses' => 1])->json('data.id');
        $this->api($owner, 'PUT', "/api/inventory/salon/vouchers/{$off}", ['active' => false])->assertOk();

        $this->sell($owner, [[$wash, 1, 50000]], ['voucher_code' => 'old', 'discount' => 5000])->assertStatus(422);
        $this->sell($owner, [[$wash, 1, 50000]], ['voucher_code' => 'off', 'discount' => 5000])->assertStatus(422);
        $this->api($owner, 'PUT', "/api/inventory/salon/vouchers/{$old}", ['expires_on' => '2026-10-31'])->assertOk();
        $this->sell($owner, [[$wash, 1, 50000]], ['voucher_code' => 'old', 'discount' => 5000])->assertCreated();

        $sale = $this->sell($owner, [[$wash, 1, 50000]], ['voucher_code' => 'one', 'discount' => 5000])->assertCreated()->json('data.id');
        $this->sell($owner, [[$wash, 1, 50000]], ['voucher_code' => 'one', 'discount' => 5000])->assertStatus(422);
        $this->api($owner, 'POST', "/api/inventory/sales/{$sale}/cancel", ['reason' => 'Mistake'])->assertOk();
        $this->sell($owner, [[$wash, 1, 50000]], ['voucher_code' => 'one', 'discount' => 5000])->assertCreated();

        $usable = collect($this->api($owner, 'GET', '/api/inventory/salon/vouchers')->json('data'))->pluck('usable', 'code')->all();
        $this->assertSame(['ONE' => false, 'OLD' => true, 'OFF' => false], $usable);
    }

    public function test_only_an_unused_voucher_can_be_deleted_and_only_a_manager_manages_them(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $wash = $this->service($owner, 'Wash', 50000);
        $used = $this->voucher($owner, ['code' => 'used'])->json('data.id');
        $fresh = $this->voucher($owner, ['code' => 'fresh'])->json('data.id');
        $this->sell($owner, [[$wash, 1, 50000]], ['voucher_code' => 'used', 'discount' => 5000])->assertCreated();

        $this->api($owner, 'DELETE', "/api/inventory/salon/vouchers/{$used}")->assertStatus(422);
        $this->api($owner, 'DELETE', "/api/inventory/salon/vouchers/{$fresh}")->assertOk();
        $this->api($owner, 'DELETE', "/api/inventory/salon/vouchers/{$fresh}")->assertStatus(404);
        $this->api($asha, 'GET', '/api/inventory/salon/vouchers')->assertStatus(403);
        $this->voucher($asha, ['code' => 'mine'])->assertStatus(403);
        $this->api($asha, 'GET', '/api/inventory/salon/vouchers/check?code=used&subtotal=1000')->assertOk();   // anyone at the till may look one up
    }

    public function test_a_voucher_and_points_work_together_and_a_salons_vouchers_are_its_own(): void
    {
        $owner = $this->salon();
        $other = $this->salon('Other');
        $this->loyaltyOn($owner);
        $wash = $this->service($owner, 'Wash', 50000);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/loyalty/adjust", ['points' => 20, 'note' => 'Gift'])->assertOk();
        $this->voucher($owner, ['code' => 'ten'])->assertCreated();

        // 10% of 50,000 is 5,000, and 20 points are 2,000: 7,000 in all
        $this->sell($owner, [[$wash, 1, 50000]], ['customer_id' => $neema, 'voucher_code' => 'ten', 'redeem_points' => 20, 'discount' => 6999])->assertStatus(422);
        $this->sell($owner, [[$wash, 1, 50000]], ['customer_id' => $neema, 'voucher_code' => 'ten', 'redeem_points' => 20, 'discount' => 7000])->assertCreated();

        $this->assertSame([], $this->api($other, 'GET', '/api/inventory/salon/vouchers')->json('data'));
        $this->api($other, 'GET', '/api/inventory/salon/vouchers/check?code=ten&subtotal=1000')->assertStatus(422);
        $this->assertSame(0, $this->points($other, $neema), 'another salon has no such client');
    }

    // ------------------------------------------------------------------ packages

    /** A "braids x5" package: 5 visits of braids, valid 60 days, sold for 150,000 (braids alone are 40,000). */
    private function packageOf(User $owner, int $service, array $extra = []): int
    {
        return $this->service($owner, 'Braids x5', 150000, array_merge(['package_sessions' => 5, 'package_service_id' => $service, 'package_valid_days' => 60], $extra));
    }

    public function test_a_package_must_be_visits_of_a_real_service(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);
        $oil = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Oil', 'quantity' => 9, 'min_stock' => 1, 'status' => 'active', 'cost_price' => 1, 'selling_price' => 5000])->json('data.id');
        $pack = $this->packageOf($owner, $braids);
        $base = ['is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 1000];

        $this->api($owner, 'POST', '/api/inventory/products', $base + ['name' => 'A', 'package_sessions' => 5, 'package_service_id' => $oil])->assertStatus(422);              // goods
        $this->api($owner, 'POST', '/api/inventory/products', $base + ['name' => 'B', 'package_sessions' => 5, 'package_service_id' => $pack])->assertStatus(422);             // another package
        $this->api($owner, 'POST', '/api/inventory/products', $base + ['name' => 'C', 'package_sessions' => 5, 'package_service_id' => 99999])->assertStatus(422);            // nothing
        $this->api($owner, 'POST', '/api/inventory/products', $base + ['name' => 'D', 'package_sessions' => 1, 'package_service_id' => $braids])->assertStatus(422);          // one visit is not a package
        $this->api($owner, 'POST', '/api/inventory/products', $base + ['name' => 'E', 'package_sessions' => 5, 'package_service_id' => $braids, 'package_valid_days' => 0])->assertStatus(422);
        $this->api($owner, 'PUT', "/api/inventory/products/{$pack}", ['package_service_id' => $pack])->assertStatus(422);                                                       // itself

        $listed = collect($this->api($owner, 'GET', '/api/inventory/products')->json('data'))->firstWhere('id', $pack);
        $this->assertSame([5, $braids, 60], [(int) $listed['package_sessions'], (int) $listed['package_service_id'], (int) $listed['package_valid_days']]);
    }

    public function test_selling_a_package_gives_the_client_their_visits_and_needs_a_client(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);
        $pack = $this->packageOf($owner, $braids);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $this->at('2026-10-07 10:00:00');

        $this->sell($owner, [[$pack, 1, 150000]])->assertStatus(422)->assertJsonValidationErrors('customer_id');
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_sales')->count()));

        $this->sell($owner, [[$pack, 2, 150000]], ['customer_id' => $neema])->assertCreated();
        $list = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/packages")->assertOk()->json('data');
        $this->assertCount(2, $list, 'one package for each one sold');
        $this->assertSame(['Braids x5', 5, 5, '2026-12-06', 'active', true, 'Braids'], [$list[0]['name'], $list[0]['sessions_total'], $list[0]['sessions_left'], $list[0]['expires_on'], $list[0]['status'], $list[0]['usable'], $list[0]['service_name']]);
    }

    public function test_a_visit_paid_for_in_a_package_is_free_and_uses_one_up_and_the_stylist_still_earns(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $braids = $this->service($owner, 'Braids', 40000, ['commission_percent' => 10]);
        $pack = $this->packageOf($owner, $braids);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $this->sell($owner, [[$pack, 1, 150000]], ['customer_id' => $neema])->assertCreated();
        $pkg = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/packages")->json('data.0.id');

        // the till asks 40,000 but the package pays for it: the line is 0
        $id = $this->sell($owner, [[$braids, 1, 40000, (string) $asha->id, $pkg]], ['customer_id' => $neema, 'subtotal' => 0, 'total' => 0, 'paid_total' => 0])->assertCreated()->json('data.id');

        $line = $this->rows($owner, fn () => DB::table('inventory_sale_items')->where('sale_id', $id)->first());
        $this->assertSame([0.0, 0.0, $pkg], [(float) $line->unit_price, (float) $line->total, (int) $line->package_id]);
        $this->assertSame(4000.0, (float) $line->commission_amount, '10% of what the service is worth, not of the nothing paid');
        $left = fn () => $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/packages")->json('data.0');
        $this->assertSame([4, 'active'], [$left()['sessions_left'], $left()['status']]);

        $visits = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/history")->json('data.stats.visits');
        $this->assertSame(2, $visits, 'the package sale and the free visit are both visits');
    }

    public function test_the_last_visit_uses_the_package_up_and_cancelling_gives_it_back(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);
        $pack = $this->packageOf($owner, $braids, ['package_sessions' => 2]);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $this->sell($owner, [[$pack, 1, 150000]], ['customer_id' => $neema])->assertCreated();
        $pkg = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/packages")->json('data.0.id');
        $free = fn () => $this->sell($owner, [[$braids, 1, 40000, null, $pkg]], ['customer_id' => $neema, 'subtotal' => 0, 'total' => 0, 'paid_total' => 0]);

        $first = $free()->assertCreated()->json('data.id');
        $second = $free()->assertCreated()->json('data.id');
        $now = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/packages")->json('data.0');
        $this->assertSame([0, 'used', false], [$now['sessions_left'], $now['status'], $now['usable']]);
        $free()->assertStatus(422);

        $this->api($owner, 'POST', "/api/inventory/sales/{$second}/cancel", ['reason' => 'Did not come'])->assertOk();
        $back = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/packages")->json('data.0');
        $this->assertSame([1, 'active', true], [$back['sessions_left'], $back['status'], $back['usable']]);
        $this->assertNotNull($first);
    }

    public function test_a_package_cannot_be_used_by_someone_else_for_another_service_after_it_expires_or_beyond_its_visits(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);
        $wash = $this->service($owner, 'Wash', 5000);
        $pack = $this->packageOf($owner, $braids, ['package_sessions' => 2, 'package_valid_days' => 10]);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $rehema = $this->client($owner, 'Rehema', '0711000002');
        $this->at('2026-10-07 10:00:00');
        $this->sell($owner, [[$pack, 1, 150000]], ['customer_id' => $neema])->assertCreated();
        $pkg = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/packages")->json('data.0.id');
        $free = fn (int $service, int $client, int $qty = 1) => $this->sell($owner, [[$service, $qty, 1000, null, $pkg]], ['customer_id' => $client, 'subtotal' => 0, 'total' => 0, 'paid_total' => 0]);

        $free($braids, $rehema)->assertStatus(422);                    // someone else's
        $free($wash, $neema)->assertStatus(422);                       // another service
        $free($braids, $neema, 3)->assertStatus(422);                  // more visits than are left
        $this->sell($owner, [[$braids, 1, 0, null, $pkg], [$braids, 2, 0, null, $pkg]], ['customer_id' => $neema, 'subtotal' => 0, 'total' => 0, 'paid_total' => 0])->assertStatus(422);   // two lines that together are too many
        $this->at('2026-10-20 10:00:00');
        $free($braids, $neema)->assertStatus(422);                     // after its 10 days
        $this->assertSame(2, $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/packages")->json('data.0.sessions_left'), 'every refusal left it alone');
        $this->assertTrue($this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/packages")->json('data.0.expired'));
    }

    public function test_cancelling_the_sale_of_a_package_cancels_the_package(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);
        $pack = $this->packageOf($owner, $braids);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $sale = $this->sell($owner, [[$pack, 1, 150000]], ['customer_id' => $neema])->assertCreated()->json('data.id');

        $this->api($owner, 'POST', "/api/inventory/sales/{$sale}/cancel", ['reason' => 'Changed her mind'])->assertOk();

        $p = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/packages")->json('data.0');
        $this->assertSame(['cancelled', false], [$p['status'], $p['usable']]);
    }

    public function test_the_shop_is_untouched_by_all_of_this(): void
    {
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'phone_number' => '0724000010']), 'inventory');
        $goods = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Soda', 'quantity' => 50, 'min_stock' => 1, 'status' => 'active', 'cost_price' => 500, 'selling_price' => 1000], false)->assertCreated()->json('data.id');
        $customer = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Juma', 'phone' => '0711000009'], false)->assertCreated()->json('data.id');

        $this->sell($owner, [[$goods, 2, 1000]], ['customer_id' => $customer, 'voucher_code' => 'whatever', 'redeem_points' => 99], false)->assertCreated();
        $this->assertSame(0, (int) DB::table('inventory_loyalty_ledger')->count());
    }
}
