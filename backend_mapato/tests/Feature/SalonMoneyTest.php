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
 * The salon's money, step by step: how a payment was made (cash, M-Pesa, Mixx by Yas, Airtel Money, HaloPesa, bank),
 * why a discount was given, what each stylist really brought in after the discount, and the lines behind that total.
 * Staff revenue, commission and cash are different figures; here the first two are checked, and that a stylist sees
 * only their own.
 */
class SalonMoneyTest extends TestCase
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
        $this->flushHeaders();
        $request = $this->withHeader('Authorization', "Bearer {$token}");

        return ($salon ? $request->withHeader('X-Service', 'salon') : $request)->json($method, $uri, $body);
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, fn () => TenantContext::runInService('salon', $fn));
    }

    private function service(User $as, string $name, int $price, array $extra = []): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', array_merge([
            'name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price,
        ], $extra))->assertCreated()->json('data.id');
    }

    private function goods(User $as, string $name, int $qty, int $price): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', [
            'name' => $name, 'quantity' => $qty, 'min_stock' => 1, 'status' => 'active', 'cost_price' => (int) ($price / 2), 'selling_price' => $price,
        ])->assertCreated()->json('data.id');
    }

    /** Ring up a sale. Lines: [product_id, quantity, unit_price, (staff_id)]. */
    private function sell(User $as, array $lines, array $extra = [], bool $salon = true)
    {
        $subtotal = array_sum(array_map(fn (array $i) => $i[1] * $i[2], $lines));
        $discount = $extra['discount'] ?? 0;
        $total = $subtotal - $discount;

        return $this->api($as, 'POST', '/api/inventory/sales', array_merge([
            'payment_status' => 'paid', 'subtotal' => $subtotal, 'discount' => 0, 'tax' => 0, 'total' => $total, 'paid_total' => $total,
            'items' => array_map(fn (array $i) => array_filter(['product_id' => $i[0], 'quantity' => $i[1], 'unit_price' => $i[2], 'staff_id' => $i[3] ?? null], fn ($v) => $v !== null), $lines),
        ], $extra), $salon);
    }

    private function at(string $when): void
    {
        Carbon::setTestNow(Carbon::parse($when, 'UTC'));
    }

    // ------------------------------------------------------------------ how it was paid

    public function test_every_way_of_paying_is_kept_as_a_known_method_and_its_own_channel(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 5000);
        $channels = ['cash' => ['cash', null], 'mpesa' => ['mobile_money', 'mpesa'], 'mixx' => ['mobile_money', 'mixx'], 'airtel_money' => ['mobile_money', 'airtel_money'], 'halopesa' => ['mobile_money', 'halopesa'], 'bank_transfer' => ['bank_transfer', null]];

        foreach ($channels as $name => [$method, $channel]) {
            $id = $this->sell($owner, [[$wash, 1, 5000]], ['payments' => [['amount' => 5000, 'method' => $name]]])->assertCreated()->json('data.id');
            $row = $this->rows($owner, fn () => DB::table('inventory_sale_payments')->where('sale_id', $id)->first());
            $this->assertSame($method, $row->method, $name);
            $this->assertSame($channel, $row->method_extended, $name);
        }
    }

    public function test_an_unknown_way_of_paying_is_refused_and_nothing_is_saved(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 5000);

        $this->sell($owner, [[$wash, 1, 5000]], ['payments' => [['amount' => 5000, 'method' => 'bitcoin']]])->assertStatus(422);

        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_sales')->count()));
    }

    public function test_a_later_payment_can_name_the_channel_too(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 5000);
        $client = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Neema', 'phone' => '0711000001'])->json('data.id');
        $id = $this->sell($owner, [[$wash, 1, 5000]], ['customer_id' => $client, 'payment_status' => 'debt', 'paid_total' => 0])->assertCreated()->json('data.id');

        $this->api($owner, 'POST', "/api/inventory/sales/{$id}/payments", ['amount' => 5000, 'method' => 'halopesa'])->assertOk();

        $row = $this->rows($owner, fn () => DB::table('inventory_sale_payments')->where('sale_id', $id)->first());
        $this->assertSame(['mobile_money', 'halopesa'], [$row->method, $row->method_extended]);
        $this->assertSame('paid', $this->rows($owner, fn () => DB::table('inventory_sales')->where('id', $id)->value('payment_status')));
    }

    // ------------------------------------------------------------------ discounts

    public function test_a_salon_discount_must_say_why_and_the_reason_is_kept(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);

        $this->sell($owner, [[$braids, 1, 40000]], ['discount' => 4000])->assertStatus(422)->assertJsonPath('message', 'Andika sababu ya punguzo. / Write the reason for the discount.');
        $this->sell($owner, [[$braids, 1, 40000]], ['discount' => 4000, 'discount_reason' => '   '])->assertStatus(422);
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_sales')->count()), 'nothing saved without a reason');

        $id = $this->sell($owner, [[$braids, 1, 40000]], ['discount' => 4000, 'discount_reason' => 'Regular client'])->assertCreated()->json('data.id');
        $this->assertSame('Regular client', $this->rows($owner, fn () => DB::table('inventory_sales')->where('id', $id)->value('discount_reason')));
        $this->assertSame('Regular client', $this->api($owner, 'GET', '/api/inventory/sales/' . $id)->json('data.discount_reason'));
    }

    public function test_no_discount_needs_no_reason_and_keeps_none(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);

        $id = $this->sell($owner, [[$braids, 1, 40000]], ['discount_reason' => 'ignored: there is no discount'])->assertCreated()->json('data.id');

        $this->assertNull($this->rows($owner, fn () => DB::table('inventory_sales')->where('id', $id)->value('discount_reason')));
    }

    public function test_the_shop_is_not_asked_why(): void
    {
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'phone_number' => '0724000001']), 'inventory');
        $goods = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Soda', 'quantity' => 50, 'min_stock' => 1, 'status' => 'active', 'cost_price' => 500, 'selling_price' => 1000], false)->assertCreated()->json('data.id');

        $this->sell($owner, [[$goods, 2, 1000]], ['discount' => 100], false)->assertCreated();
    }

    // ------------------------------------------------------------------ what each stylist brought in

    /** A 100,000 sale with 10,000 off: braids (Asha) 80,000 and a wash (Bahati) 20,000, paid by M-Pesa. */
    private function discountedVisit(User $owner, User $asha, User $bahati): array
    {
        $braids = $this->service($owner, 'Braids', 80000, ['commission_percent' => 10]);
        $wash = $this->service($owner, 'Wash', 20000);
        $neema = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Neema', 'phone' => '0711000001'])->json('data.id');
        $this->at('2026-10-05 10:00:00');
        $id = $this->sell($owner, [[$braids, 1, 80000, (string) $asha->id], [$wash, 1, 20000, (string) $bahati->id]], [
            'customer_id' => $neema, 'discount' => 10000, 'discount_reason' => 'Loyal client', 'payments' => [['amount' => 90000, 'method' => 'mpesa']],
        ])->assertCreated()->json('data.id');
        $this->at('2026-10-07 09:00:00');

        return compact('braids', 'wash', 'neema', 'id');
    }

    public function test_a_stylists_revenue_is_what_is_left_after_her_share_of_the_discount(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $bahati = $this->stylist($owner, 'Bahati');
        $this->discountedVisit($owner, $asha, $bahati);

        $data = $this->api($owner, 'GET', '/api/inventory/salon/stylists')->assertOk()->json('data');
        $by = collect($data['stylists'])->keyBy('name');

        $this->assertSame([72000, 8000, 8000], [$by['Asha']['revenue'], $by['Asha']['discount'], $by['Asha']['commission']], 'a tenth of the 80,000 she did, whatever the discount');
        $this->assertSame([18000, 2000], [$by['Bahati']['revenue'], $by['Bahati']['discount']]);
        $this->assertSame(90000, $data['totals']['revenue'], 'together exactly what the client paid');
        $this->assertSame(10000, $data['totals']['discount']);
    }

    public function test_a_stylists_page_lists_the_lines_behind_the_total(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $bahati = $this->stylist($owner, 'Bahati');
        $ids = $this->discountedVisit($owner, $asha, $bahati);
        $shampoo = $this->goods($owner, 'Shampoo', 10, 8000);
        $this->at('2026-10-06 12:00:00');
        $this->sell($owner, [[$shampoo, 1, 8000, (string) $asha->id]])->assertCreated();                                  // goods: not a service
        $cancelled = $this->sell($owner, [[$ids['braids'], 1, 80000, (string) $asha->id]])->assertCreated()->json('data.id');
        $this->api($owner, 'POST', "/api/inventory/sales/{$cancelled}/cancel", ['reason' => 'No show'])->assertOk();    // cancelled
        $this->at('2026-09-20 12:00:00');
        $this->sell($owner, [[$ids['wash'], 1, 20000, (string) $asha->id]])->assertCreated();                             // last month
        $this->at('2026-10-07 09:00:00');

        $data = $this->api($owner, 'GET', "/api/inventory/salon/stylists/{$asha->id}/transactions")->assertOk()->json('data');

        $this->assertSame('Asha', $data['name']);
        $this->assertCount(1, $data['transactions'], 'braids only: no goods, no cancelled sale, nothing from last month');
        $line = $data['transactions'][0];
        $this->assertSame('Braids', $line['service']);
        $this->assertSame('Neema', $line['client']);
        $this->assertSame([80000, 8000, 72000, 8000], [$line['value'], $line['discount'], $line['net'], $line['commission']]);
        $this->assertSame(['mpesa'], $line['methods']);
        $this->assertSame('Loyal client', $line['discount_reason']);
        $this->assertSame('paid', $line['payment_status']);
        $this->assertSame('2026-10-05 10:00', $line['date']);
        $this->assertSame(['services' => 1, 'value' => 80000, 'discount' => 8000, 'net' => 72000, 'commission' => 8000], $data['totals']);

        // and what the report says about her is exactly what her page adds up to
        $report = collect($this->api($owner, 'GET', '/api/inventory/salon/stylists')->json('data.stylists'))->firstWhere('name', 'Asha');
        $this->assertSame($data['totals']['net'], $report['revenue']);
    }

    public function test_the_page_follows_the_period_and_has_one_for_nobody_named(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $bahati = $this->stylist($owner, 'Bahati');
        $ids = $this->discountedVisit($owner, $asha, $bahati);
        $this->sell($owner, [[$ids['wash'], 1, 20000]])->assertCreated();

        $none = $this->api($owner, 'GET', '/api/inventory/salon/stylists/none/transactions')->assertOk()->json('data');
        $this->assertNull($none['staff_id']);
        $this->assertCount(1, $none['transactions']);
        $this->assertSame(20000, $none['totals']['net']);

        $other = $this->api($owner, 'GET', "/api/inventory/salon/stylists/{$asha->id}/transactions?from=2026-09-01&to=2026-09-30")->assertOk()->json('data');
        $this->assertSame([], $other['transactions']);
        $this->api($owner, 'GET', "/api/inventory/salon/stylists/{$asha->id}/transactions?from=2026-10-09&to=2026-10-01")->assertStatus(422);
    }

    public function test_a_stylist_sees_only_her_own_page_and_another_salons_stylist_shows_nothing(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $bahati = $this->stylist($owner, 'Bahati');
        $this->discountedVisit($owner, $asha, $bahati);
        $other = $this->salon('Other');

        $this->api($asha, 'GET', "/api/inventory/salon/stylists/{$asha->id}/transactions")->assertOk()->assertJsonCount(1, 'data.transactions');
        $this->api($asha, 'GET', "/api/inventory/salon/stylists/{$bahati->id}/transactions")->assertStatus(403);
        $this->api($asha, 'GET', '/api/inventory/salon/stylists/none/transactions')->assertStatus(403);
        $this->api($other, 'GET', "/api/inventory/salon/stylists/{$asha->id}/transactions")->assertOk()->assertJsonCount(0, 'data.transactions');
    }
}
