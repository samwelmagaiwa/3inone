<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * At the till: a name and number typed for a client make her a real client (saved once, found again by the number, texted
 * the thank-you with the feedback link); and every salon sale shows what the SERVICE earned apart from what the GOODS earned.
 */
class SalonTillClientAndProfitTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;
    protected FakeSmsGateway $sms;

    private function salon(string $name = 'Glow'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0730' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);
        config(['app.url' => 'https://3inone.example']);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [], string $service = 'salon')
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', $service)->json($method, $uri, $body);
    }

    private function service(User $as, string $name = 'Braids', int $price = 40000, array $extra = []): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', array_merge(['name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price, 'duration_minutes' => 60], $extra))->assertCreated()->json('data.id');
    }

    private function goods(User $as, string $name, int $stock, int $cost, int $price): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'quantity' => $stock, 'min_stock' => 0, 'status' => 'active', 'cost_price' => $cost, 'selling_price' => $price])->assertCreated()->json('data.id');
    }

    /** A cash sale with a client typed at the till (no client picked from the list). */
    private function cashSale(User $as, int $product, int $price, array $typed, string $status = 'paid', string $service = 'salon')
    {
        return $this->api($as, 'POST', '/api/inventory/sales', array_merge([
            'payment_status' => $status, 'subtotal' => $price, 'discount' => 0, 'tax' => 0, 'total' => $price, 'paid_total' => $status === 'paid' ? $price : 0,
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => $price]],
            'payments' => $status === 'paid' ? [['amount' => $price, 'method' => 'cash']] : [],
        ], $typed), $service);
    }

    private function clients(User $as): array
    {
        return collect($this->api($as, 'GET', '/api/inventory/customers')->json('data'))->map(fn ($c) => [$c['name'], $c['phone']])->all();
    }

    // ------------------------------------------------------------------ the client typed at the till

    public function test_a_name_and_number_typed_with_cash_become_a_saved_client_who_is_texted(): void
    {
        $owner = $this->salon('Glow Salon');
        $braids = $this->service($owner);

        $id = $this->cashSale($owner, $braids, 40000, ['customer_name_override' => 'Neema Juma', 'customer_phone' => '0743519104'])->assertCreated()->json('data.id');

        $sale = DB::table('inventory_sales')->find($id);
        $this->assertNotNull($sale->customer_id, 'the sale is tied to a real client');
        $this->assertNull($sale->customer_name_override);
        $this->assertSame([['Neema Juma', '0743519104']], $this->clients($owner));
        $this->assertCount(1, $this->sms->sent, 'the thank-you went out');
        $this->assertSame('0743519104', $this->sms->sent[0]['to']);
        $this->assertStringContainsString('Neema', $this->sms->sent[0]['message']);
        $this->assertStringContainsString('https://3inone.example/f/', $this->sms->sent[0]['message']);
    }

    public function test_the_same_number_written_another_way_is_the_same_client_and_not_a_second_one(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner);
        $first = $this->cashSale($owner, $braids, 40000, ['customer_name_override' => 'Neema', 'customer_phone' => '0743519104'])->json('data.id');
        $second = $this->cashSale($owner, $braids, 40000, ['customer_name_override' => 'Mama Neema', 'customer_phone' => '+255743519104'])->json('data.id');
        $third = $this->cashSale($owner, $braids, 40000, ['customer_phone' => '255 743 519 104'])->json('data.id');

        $ids = DB::table('inventory_sales')->whereIn('id', [$first, $second, $third])->pluck('customer_id')->unique();
        $this->assertCount(1, $ids, 'one client');
        $this->assertCount(1, $this->clients($owner));
        $this->assertSame('Neema', $this->clients($owner)[0][0], 'the name she was saved with is kept');
    }

    public function test_only_a_number_makes_a_client_named_by_her_number_and_only_a_name_makes_one_without_a_number(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner);

        $this->cashSale($owner, $braids, 40000, ['customer_phone' => '0711000009'])->assertCreated();
        $this->assertSame([['0711000009', '0711000009']], $this->clients($owner));
        $this->assertCount(1, $this->sms->sent);

        $this->sms->sent = [];
        $this->cashSale($owner, $braids, 40000, ['customer_name_override' => 'Rehema'])->assertCreated();
        $this->cashSale($owner, $braids, 40000, ['customer_name_override' => 'rehema'])->assertCreated();
        $this->assertCount(2, $this->clients($owner), 'the same name with no number is the same person');
        $this->assertCount(0, $this->sms->sent, 'no number, nobody to text');
    }

    public function test_nothing_typed_means_a_walk_in_as_before_and_a_picked_client_is_never_replaced(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner);
        $this->cashSale($owner, $braids, 40000, [])->assertCreated();
        $this->assertSame([], $this->clients($owner));
        $this->assertCount(0, $this->sms->sent);

        $picked = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Picked', 'phone' => '0712000001'])->assertSuccessful()->json('data.id');
        $this->cashSale($owner, $braids, 40000, ['customer_id' => $picked, 'customer_name_override' => 'Someone else', 'customer_phone' => '0799999999'])->assertCreated();
        $this->assertSame([['Picked', '0712000001']], $this->clients($owner), 'the client picked from the list wins');
    }

    public function test_a_typed_client_can_owe_and_a_cleared_debt_texts_her_then(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner);
        $id = $this->cashSale($owner, $braids, 40000, ['customer_name_override' => 'Neema', 'customer_phone' => '0743519104'], 'debt')->assertCreated()->json('data.id');
        $this->assertCount(0, $this->sms->sent, 'not cleared yet');

        $this->api($owner, 'POST', "/api/inventory/sales/{$id}/payments", ['amount' => 40000, 'method' => 'cash'])->assertSuccessful();
        $this->assertCount(1, $this->sms->sent, 'cleared: the thank-you goes out now');
    }

    public function test_the_shop_does_not_save_clients_from_what_is_typed_at_its_till(): void
    {
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'phone_number' => '0731000001']), 'inventory');
        $product = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Cola', 'quantity' => 10, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 500, 'selling_price' => 1000], 'inventory')->assertCreated()->json('data.id');
        $this->cashSale($owner, $product, 1000, ['customer_name_override' => 'Walk-in', 'customer_phone' => '0743519104'], 'paid', 'inventory')->assertCreated();
        $this->assertSame([], collect($this->api($owner, 'GET', '/api/inventory/customers', [], 'inventory')->json('data'))->all());
    }

    // ------------------------------------------------------------------ what the service and the goods each earned

    public function test_a_sale_shows_what_the_service_earned_apart_from_the_goods(): void
    {
        $owner = $this->salon();
        $asha = $this->givenServices(User::factory()->create(['name' => 'Asha', 'role' => 'hair_stylist', 'is_active' => true, 'created_by' => $owner->id]), 'salon');
        $braids = $this->service($owner, 'Braids', 40000, ['commission_percent' => 10]);
        $shampoo = $this->goods($owner, 'Shampoo', 10, 3000, 8000);
        $extensions = $this->goods($owner, 'Extensions', 5, 15000, 25000);
        $this->api($owner, 'PUT', "/api/inventory/salon/services/{$braids}/materials", ['items' => [['material_product_id' => $shampoo, 'quantity' => 2]]])->assertOk();

        $id = $this->api($owner, 'POST', '/api/inventory/sales', [
            'customer_name_override' => 'Neema', 'customer_phone' => '0743519104',
            'payment_status' => 'paid', 'subtotal' => 65000, 'discount' => 0, 'tax' => 0, 'total' => 65000, 'paid_total' => 65000,
            'items' => [['product_id' => $braids, 'quantity' => 1, 'unit_price' => 40000, 'staff_id' => (string) $asha->id], ['product_id' => $extensions, 'quantity' => 1, 'unit_price' => 25000]],
            'payments' => [['amount' => 65000, 'method' => 'cash']],
        ])->assertCreated()->json('data.id');

        $b = $this->api($owner, 'GET', "/api/inventory/sales/{$id}")->assertOk()->json('data.salon_breakdown');

        $service = $b['services'][0];
        $this->assertSame(['Braids', 'Asha'], [$service['name'], $service['stylist']]);
        $this->assertEquals([40000, 4000, 6000, 30000], [$service['revenue'], $service['commission'], $service['materials_cost'], $service['profit']]);
        $this->assertSame([['name' => 'Shampoo', 'quantity' => 2, 'cost' => 6000]], array_map(fn ($m) => ['name' => $m['name'], 'quantity' => $m['quantity'], 'cost' => (int) $m['cost']], $service['materials']));

        $goods = $b['goods'][0];
        $this->assertSame('Extensions', $goods['name']);
        $this->assertEquals([25000, 15000, 10000], [$goods['revenue'], $goods['cost'], $goods['profit']]);

        $this->assertEquals([30000, 10000, 40000], [$b['service_profit'], $b['goods_profit'], $b['profit']]);
    }

    public function test_a_discount_is_shared_between_the_service_and_the_goods(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);
        $extensions = $this->goods($owner, 'Extensions', 5, 15000, 25000);
        $id = $this->api($owner, 'POST', '/api/inventory/sales', [
            'customer_name_override' => 'Neema', 'payment_status' => 'paid', 'subtotal' => 65000, 'discount' => 6500, 'discount_reason' => 'Regular client', 'tax' => 0, 'total' => 58500, 'paid_total' => 58500,
            'items' => [['product_id' => $braids, 'quantity' => 1, 'unit_price' => 40000], ['product_id' => $extensions, 'quantity' => 1, 'unit_price' => 25000]],
            'payments' => [['amount' => 58500, 'method' => 'cash']],
        ])->assertCreated()->json('data.id');

        $b = $this->api($owner, 'GET', "/api/inventory/sales/{$id}")->json('data.salon_breakdown');
        $this->assertEquals(36000, $b['services'][0]['revenue']);
        $this->assertEquals(22500, $b['goods'][0]['revenue']);
        $this->assertEquals(7500, $b['goods'][0]['profit'], 'goods: 22 500 less the 15 000 they cost');
        $this->assertEquals(58500 - 15000, $b['profit']);
    }

    public function test_the_end_of_day_reports_show_the_profit_of_each_service_and_each_goods(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000, ['commission_percent' => 10]);
        $shampoo = $this->goods($owner, 'Shampoo', 10, 3000, 8000);
        $extensions = $this->goods($owner, 'Extensions', 5, 15000, 25000);
        $this->api($owner, 'PUT', "/api/inventory/salon/services/{$braids}/materials", ['items' => [['material_product_id' => $shampoo, 'quantity' => 2]]])->assertOk();
        $asha = $this->givenServices(User::factory()->create(['name' => 'Asha', 'role' => 'hair_stylist', 'is_active' => true, 'created_by' => $owner->id]), 'salon');
        foreach ([1, 2] as $_) {
            $this->api($owner, 'POST', '/api/inventory/sales', [
                'customer_name_override' => 'C', 'payment_status' => 'paid', 'subtotal' => 65000, 'discount' => 0, 'tax' => 0, 'total' => 65000, 'paid_total' => 65000,
                'items' => [['product_id' => $braids, 'quantity' => 1, 'unit_price' => 40000, 'staff_id' => (string) $asha->id], ['product_id' => $extensions, 'quantity' => 1, 'unit_price' => 25000]],
                'payments' => [['amount' => 65000, 'method' => 'cash']],
            ])->assertCreated();
        }

        $r = $this->api($owner, 'GET', '/api/inventory/salon/reports')->assertOk()->json('data');
        $svc = $r['by_service'][0];
        $this->assertSame('Braids', $svc['name']);
        $this->assertEquals([80000, 8000, 12000, 60000], [$svc['revenue'], $svc['commission'], $svc['materials_cost'], $svc['profit']]);
        $g = collect($r['goods_sold'])->firstWhere('name', 'Extensions');
        $this->assertEquals([50000, 30000, 20000], [$g['revenue'], $g['cost'], $g['profit']]);
    }

    public function test_the_breakdown_is_only_for_the_salon(): void
    {
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'phone_number' => '0731000002']), 'inventory');
        $product = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Cola', 'quantity' => 10, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 500, 'selling_price' => 1000], 'inventory')->assertCreated()->json('data.id');
        $id = $this->cashSale($owner, $product, 1000, [], 'paid', 'inventory')->assertCreated()->json('data.id');
        $this->assertArrayNotHasKey('salon_breakdown', $this->api($owner, 'GET', "/api/inventory/sales/{$id}", [], 'inventory')->json('data'));
    }
}
