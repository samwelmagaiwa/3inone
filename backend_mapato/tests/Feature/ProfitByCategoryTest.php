<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * The monthly report says what each CATEGORY earned: the goods of one category with their profit added up and each product under it, and
 * the services the same way in their own list, the biggest earner first. It is the owner's: anyone else sees what a category sold, not earned.
 */
class ProfitByCategoryTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function owner(string $service, string $name = 'Glow'): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0729' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), $service);
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [], string $service = 'inventory')
    {
        $token = $as->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', $service)->json($method, $uri, $body);
    }

    private function category(User $as, string $name, string $service = 'inventory'): int
    {
        return (int) $this->api($as, 'POST', '/api/inventory/categories', ['name' => $name, 'status' => 'active'], $service)->assertCreated()->json('data.id');
    }

    private function product(User $as, string $name, ?int $category, int $cost, int $price, bool $service = false, string $svc = 'inventory'): int
    {
        return (int) $this->api($as, 'POST', '/api/inventory/products', array_filter([
            'name' => $name, 'sku' => strtoupper(substr($name, 0, 3)) . ++$this->seq, 'quantity' => $service ? 0 : 500, 'min_stock' => 0, 'status' => 'active',
            'cost_price' => $cost, 'selling_price' => $price, 'category_id' => $category, 'is_service' => $service ?: null, 'duration_minutes' => $service ? 60 : null,
        ], fn ($v) => $v !== null), $svc)->assertCreated()->json('data.id');
    }

    private function sell(User $as, int $product, int $qty, int $price, int $cost, string $svc = 'inventory', string $status = 'paid'): int
    {
        $total = $qty * $price;

        return (int) $this->api($as, 'POST', '/api/inventory/sales', [
            'payment_status' => $status, 'subtotal' => $total, 'discount' => 0, 'tax' => 0, 'total' => $total, 'paid_total' => $status === 'paid' ? $total : 0,
            'items' => [['product_id' => $product, 'quantity' => $qty, 'unit_price' => $price, 'unit_cost_snapshot' => $cost]],
        ], $svc)->assertCreated()->json('data.id');
    }

    private function report(User $as, string $svc = 'inventory'): array
    {
        return $this->api($as, 'GET', '/api/inventory/monthly-report?month=2026-11', [], $svc)->assertOk()->json('data');
    }

    public function test_a_shops_profit_is_added_up_per_category_with_each_product_under_it_and_the_biggest_first(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-11-18 10:00:00', 'Africa/Dar_es_Salaam')->utc());
        $owner = $this->owner('inventory', 'Duka');
        $hair = $this->category($owner, 'Nywele');
        $drinks = $this->category($owner, 'Vinywaji');
        $oil = $this->product($owner, 'Mafuta ya nywele', $hair, 600, 1000);
        $gel = $this->product($owner, 'Gel', $hair, 300, 800);
        $soda = $this->product($owner, 'Soda', $drinks, 400, 500);
        $loose = $this->product($owner, 'Mfuko', null, 100, 200);

        $this->sell($owner, $oil, 10, 1000, 600);  // sales 10,000  profit 4,000
        $this->sell($owner, $gel, 5, 800, 300);    // sales 4,000   profit 2,500
        $this->sell($owner, $soda, 20, 500, 400);  // sales 10,000  profit 2,000
        $this->sell($owner, $loose, 3, 200, 100);  // sales 600     profit 300
        $cancelled = $this->sell($owner, $soda, 100, 500, 400);
        $this->api($owner, 'POST', "/api/inventory/sales/{$cancelled}/cancel", ['reason' => 'a mistake in the till'])->assertSuccessful();

        $r = $this->report($owner);
        $goods = collect($r['profit_by_category']['goods']);

        // the hair category: both products together, 6,500 of profit, biggest first
        $this->assertSame(['Nywele', 'Vinywaji', null], $goods->pluck('category')->all());
        $hairRow = $goods->firstWhere('category', 'Nywele');
        $this->assertEquals([14000, 7500, 15], [$hairRow['sales'], $hairRow['cost'], $hairRow['qty']]);
        $this->assertEquals(6500, $hairRow['profit']);
        $this->assertEquals(46.4, $hairRow['margin_percent']);
        $this->assertSame(['Mafuta ya nywele', 'Gel'], array_column($hairRow['items'], 'name'));
        $this->assertEquals([4000, 2500], array_column($hairRow['items'], 'profit'));
        $this->assertEquals(2000, $goods->firstWhere('category', 'Vinywaji')['profit'], 'the cancelled sale is not counted');
        $this->assertEquals(300, $goods->firstWhere('category', null)['profit'], 'a product without a category is listed apart');
        $this->assertSame([], $r['profit_by_category']['services']);

        // the categories add up to the month's gross profit
        $this->assertEquals($r['figures']['gross_profit'], round($goods->sum('profit'), 2));
    }

    public function test_a_salon_reads_its_services_by_category_apart_from_its_goods(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-11-18 10:00:00', 'Africa/Dar_es_Salaam')->utc());
        $owner = $this->owner('salon');
        $braids = $this->category($owner, 'Kusuka', 'salon');
        $nails = $this->category($owner, 'Kucha', 'salon');
        $kinky = $this->product($owner, 'Knotless', $braids, 0, 40000, true, 'salon');
        $box = $this->product($owner, 'Box braids', $braids, 0, 30000, true, 'salon');
        $gel = $this->product($owner, 'Gel polish', $nails, 0, 20000, true, 'salon');
        $shampoo = $this->product($owner, 'Shampoo', $braids, 2000, 5000, false, 'salon');

        $this->sell($owner, $kinky, 2, 40000, 0, 'salon');
        $this->sell($owner, $box, 1, 30000, 0, 'salon');
        $this->sell($owner, $gel, 3, 20000, 0, 'salon');
        $this->sell($owner, $shampoo, 4, 5000, 2000, 'salon');

        $r = $this->report($owner, 'salon')['profit_by_category'];

        $this->assertSame(['Kusuka', 'Kucha'], array_column($r['services'], 'category'));
        $this->assertEquals(110000, $r['services'][0]['profit']);
        $this->assertSame(['Knotless', 'Box braids'], array_column($r['services'][0]['items'], 'name'));
        $this->assertEquals(60000, $r['services'][1]['profit']);
        // the goods are their own list: the shampoo sits under the same category name but is not a service
        $this->assertSame(['Kusuka'], array_column($r['goods'], 'category'));
        $this->assertEquals(12000, $r['goods'][0]['profit']);
        $this->assertSame(['Shampoo'], array_column($r['goods'][0]['items'], 'name'));
    }

    public function test_only_the_owner_sees_what_a_category_earned_anyone_else_sees_what_it_sold(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-11-18 10:00:00', 'Africa/Dar_es_Salaam')->utc());
        $owner = $this->owner('inventory', 'Duka');
        $hair = $this->category($owner, 'Nywele');
        $oil = $this->product($owner, 'Mafuta', $hair, 600, 1000);
        $this->sell($owner, $oil, 10, 1000, 600);
        $accountant = $this->givenServices(User::factory()->create(['name' => 'Acc', 'role' => 'accountant', 'is_active' => true, 'created_by' => $owner->id]), 'inventory');

        $row = $this->report($accountant)['profit_by_category']['goods'][0];

        $this->assertSame('Nywele', $row['category']);
        $this->assertEquals(10000, $row['sales']);
        $this->assertEquals(0, $row['profit']);
        $this->assertEquals(0, $row['cost']);
        $this->assertEquals(0, $row['items'][0]['profit']);
        $this->assertEquals(10000, $row['items'][0]['sales']);
    }

    public function test_one_business_never_reads_anothers_categories(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-11-18 10:00:00', 'Africa/Dar_es_Salaam')->utc());
        $a = $this->owner('inventory', 'A');
        $b = $this->owner('inventory', 'B');
        $this->sell($a, $this->product($a, 'Mafuta', $this->category($a, 'Nywele'), 600, 1000), 1, 1000, 600);

        $p = $this->report($b)['profit_by_category'];
        $this->assertSame([], $p['goods']);
        $this->assertSame([], $p['services']);
        $this->assertSame([], $p['categories']);
        $this->assertEquals(0, $p['totals']['all']['sales']);
    }

    public function test_a_service_earns_what_it_sold_for_less_the_goods_it_used_and_those_goods_are_listed_under_it_with_subtotals_and_a_grand_total(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-11-18 10:00:00', 'Africa/Dar_es_Salaam')->utc());
        $owner = $this->owner('salon');
        $hair = $this->category($owner, 'Nywele', 'salon');
        $braids = $this->product($owner, 'Knotless', $hair, 0, 40000, true, 'salon');
        $gel = $this->product($owner, 'Gel ya nywele', $hair, 1500, 4000, false, 'salon');
        $shampoo = $this->product($owner, 'Shampoo', $hair, 2000, 5000, false, 'salon');
        $this->api($owner, 'PUT', "/api/inventory/salon/services/{$braids}/materials", ['items' => [['material_product_id' => $gel, 'quantity' => 2]]], 'salon')->assertOk();

        $this->sell($owner, $braids, 2, 40000, 0, 'salon');   // 2 braids: sales 80,000, uses 4 gel = 6,000
        $this->sell($owner, $shampoo, 3, 5000, 2000, 'salon'); // goods sold: sales 15,000, cost 6,000, profit 9,000

        $r = $this->report($owner, 'salon');
        $p = $r['profit_by_category'];

        $svc = $p['services'][0];
        $this->assertEquals(80000, $svc['sales']);
        $this->assertEquals(6000, $svc['cost'], 'the goods the service used');
        $this->assertEquals(74000, $svc['profit']);
        $item = $svc['items'][0];
        $this->assertEquals(74000, $item['profit']);
        $this->assertSame('Gel ya nywele', $item['materials'][0]['name']);
        $this->assertEquals(4, $item['materials'][0]['qty']);
        $this->assertEquals(6000, $item['materials'][0]['cost']);

        // one block per category: goods, services and both together
        $cat = $p['categories'][0];
        $this->assertSame('Nywele', $cat['category']);
        $this->assertEquals(9000, $cat['goods']['profit']);
        $this->assertEquals(74000, $cat['services']['profit']);
        $this->assertEquals(95000, $cat['total']['sales']);
        $this->assertEquals(83000, $cat['total']['profit']);

        // the totals at the end, and they are the month's gross profit
        $this->assertEquals(9000, $p['totals']['goods']['profit']);
        $this->assertEquals(74000, $p['totals']['services']['profit']);
        $this->assertEquals(83000, $p['totals']['all']['profit']);
        $this->assertEquals($r['figures']['gross_profit'], $p['totals']['all']['profit'], 'the report ties to the month');
        $this->assertEquals(12000, $r['figures']['cost_of_goods'], 'goods sold 6,000 + goods the services used 6,000');
    }

    public function test_the_accountant_sees_the_sales_of_services_and_their_goods_but_no_cost_or_profit(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-11-18 10:00:00', 'Africa/Dar_es_Salaam')->utc());
        $owner = $this->owner('salon');
        $hair = $this->category($owner, 'Nywele', 'salon');
        $braids = $this->product($owner, 'Knotless', $hair, 0, 40000, true, 'salon');
        $gel = $this->product($owner, 'Gel', $hair, 1500, 4000, false, 'salon');
        $this->api($owner, 'PUT', "/api/inventory/salon/services/{$braids}/materials", ['items' => [['material_product_id' => $gel, 'quantity' => 2]]], 'salon')->assertOk();
        $this->sell($owner, $braids, 1, 40000, 0, 'salon');
        $accountant = $this->givenServices(User::factory()->create(['name' => 'Acc', 'role' => 'accountant', 'is_active' => true, 'created_by' => $owner->id]), 'salon');

        $p = $this->report($accountant, 'salon')['profit_by_category'];

        $this->assertEquals(40000, $p['categories'][0]['services']['sales']);
        $this->assertEquals(0, $p['categories'][0]['services']['profit']);
        $this->assertEquals(0, $p['categories'][0]['services']['items'][0]['materials'][0]['cost']);
        $this->assertEquals(0, $p['totals']['all']['profit']);
        $this->assertEquals(40000, $p['totals']['all']['sales']);
    }
}
