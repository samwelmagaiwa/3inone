<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** The owner's books and the salon's day to day: cashbook, counts, analytics, walk-in queue, categories, materials. */
class SalonBooksTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function salon(string $name = 'Glow'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0725' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    /** The salon's own clock (Dar es Salaam), which is a day ahead of the server late in the evening. */
    private function eat(): \Carbon\Carbon
    {
        return \Carbon\Carbon::now('Africa/Dar_es_Salaam');
    }

    private function stylist(User $owner): User
    {
        return $this->givenServices(User::factory()->create(['name' => 'Asha', 'role' => 'hair_stylist', 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    private function service(User $as, string $name = 'Braids', int $price = 10000, int $minutes = 60): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price, 'duration_minutes' => $minutes])->assertCreated()->json('data.id');
    }

    private function goods(User $as, string $name = 'Shampoo', int $stock = 10, int $cost = 3000): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'quantity' => $stock, 'min_stock' => 0, 'status' => 'active', 'cost_price' => $cost, 'selling_price' => 8000])->assertCreated()->json('data.id');
    }

    private function sell(User $as, int $product, int $price, string $method = 'cash', int $qty = 1, ?int $customer = null)
    {
        return $this->api($as, 'POST', '/api/inventory/sales', array_filter([
            'customer_id' => $customer,
            'payment_status' => 'paid', 'subtotal' => $price * $qty, 'discount' => 0, 'tax' => 0, 'total' => $price * $qty, 'paid_total' => $price * $qty,
            'items' => [['product_id' => $product, 'quantity' => $qty, 'unit_price' => $price]],
            'payments' => [['amount' => $price * $qty, 'method' => $method]],
        ], fn ($v) => $v !== null))->assertCreated();
    }

    public function test_the_cashbook_adds_what_came_in_and_took_out_per_place(): void
    {
        $owner = $this->salon();
        $p = $this->service($owner);
        $this->sell($owner, $p, 10000, 'cash');
        $this->sell($owner, $p, 5000, 'mpesa');
        $this->api($owner, 'POST', '/api/inventory/expenses', ['description' => 'Soap', 'category' => 'supplies', 'amount' => 2000, 'expense_date' => $this->eat()->toDateString(), 'payment_method' => 'cash'])->assertSuccessful();
        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'owner_deposit', 'method' => 'cash', 'amount' => 3000, 'note' => 'Float'])->assertCreated();

        $book = $this->api($owner, 'GET', '/api/inventory/salon/cashbook')->assertOk()->json('data');
        $this->assertEquals(13000, $book['places']['cash']['in']);
        $this->assertEquals(2000, $book['places']['cash']['out']);
        $this->assertEquals(11000, $book['places']['cash']['closing']);
        $this->assertEquals(5000, $book['places']['mobile']['closing']);
        $this->assertEquals(0, $book['places']['bank']['closing']);
        $this->assertEquals(16000, $book['total']['closing']);
    }

    public function test_an_opening_balance_carries_into_the_period_and_a_withdrawal_cannot_exceed_the_book(): void
    {
        $owner = $this->salon();
        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'opening', 'method' => 'cash', 'amount' => 50000, 'moved_on' => $this->eat()->subDays(40)->toDateString()])->assertCreated();

        $book = $this->api($owner, 'GET', '/api/inventory/salon/cashbook')->assertOk()->json('data');
        $this->assertEquals(50000, $book['places']['cash']['opening']);

        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'owner_withdrawal', 'method' => 'cash', 'amount' => 60000])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'owner_withdrawal', 'method' => 'cash', 'amount' => 20000])->assertCreated();
        $this->assertEquals(30000, $this->api($owner, 'GET', '/api/inventory/salon/cashbook')->json('data.places.cash.closing'));
    }

    public function test_a_count_shows_the_difference_and_tells_the_owner(): void
    {
        $owner = $this->salon();
        $manager = $this->givenServices(User::factory()->create(['name' => 'Boss', 'role' => 'manager', 'is_active' => true, 'created_by' => $owner->id]), 'salon');
        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'opening', 'method' => 'cash', 'amount' => 11000])->assertCreated();

        $r = $this->api($manager, 'POST', '/api/inventory/salon/cashbook/counts', ['method' => 'cash', 'counted' => 10500])->assertCreated();
        $this->assertEquals(11000, $r->json('data.expected'));
        $this->assertEquals(-500, $r->json('data.difference'));
        $this->assertSame(1, DB::table('inventory_notifications')->where('type', 'salon_book_difference')->count());

        $day = $this->api($owner, 'GET', '/api/inventory/salon/cashbook')->json('data.places.cash.days');
        $this->assertEquals(-500, $day[0]['count']['difference']);

        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/counts', ['method' => 'cash', 'counted' => 11000])->assertCreated();
        $this->assertSame(1, DB::table('inventory_notifications')->where('type', 'salon_book_difference')->count(), 'no alert when it adds up');
    }

    public function test_only_managers_see_the_books(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner);
        $this->api($asha, 'GET', '/api/inventory/salon/cashbook')->assertForbidden();
        $this->api($asha, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'owner_deposit', 'method' => 'cash', 'amount' => 1])->assertForbidden();
        $this->api($asha, 'GET', '/api/inventory/salon/analytics')->assertForbidden();
    }

    public function test_analytics_counts_new_and_returning_clients_and_the_best_services(): void
    {
        $owner = $this->salon();
        $p = $this->service($owner);
        $a = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Neema', 'phone' => '0711000001'])->assertSuccessful()->json('data.id');
        $b = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Rehema', 'phone' => '0711000002'])->assertSuccessful()->json('data.id');
        $this->sell($owner, $p, 10000, 'cash', 1, $a);
        $this->sell($owner, $p, 10000, 'cash', 1, $a);
        $this->sell($owner, $p, 10000, 'cash', 1, $b);

        $d = $this->api($owner, 'GET', '/api/inventory/salon/analytics?months=3')->assertOk()->json('data');
        $this->assertCount(3, $d['trend']);
        $now = end($d['trend']);
        $this->assertSame($this->eat()->format('Y-m'), $now['month']);
        $this->assertSame(3, $now['visits']);
        $this->assertSame(2, $now['clients']);
        $this->assertSame(2, $now['new_clients']);
        $this->assertSame(0, $now['returning_clients']);
        $this->assertEquals(30000, $now['revenue']);
        $this->assertSame('Braids', $d['top_services'][0]['name']);
        $this->assertSame(0, $d['retention']['eligible'], 'nobody has been a client for 60 days yet');
        $this->assertCount(7, $d['busiest']['weekdays']);
    }

    public function test_the_walk_in_queue_keeps_order_works_out_the_wait_and_ends_for_good(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner);
        $braids = $this->service($owner, 'Braids', 40000, 90);
        $wash = $this->service($owner, 'Wash', 5000, 30);

        $one = $this->api($owner, 'POST', '/api/inventory/salon/queue', ['name' => 'Neema', 'product_id' => $braids, 'staff_id' => (string) $asha->id])->assertCreated()->json('data.id');
        $two = $this->api($owner, 'POST', '/api/inventory/salon/queue', ['name' => 'Rehema', 'product_id' => $wash])->assertCreated()->json('data.id');
        $this->api($owner, 'POST', '/api/inventory/salon/queue', ['name' => 'Zawadi'])->assertCreated();

        $q = $this->api($owner, 'GET', '/api/inventory/salon/queue')->assertOk()->json('data');
        $this->assertSame(3, $q['waiting']);
        $this->assertSame([1, 2, 3], array_column($q['queue'], 'position'));
        $this->assertSame([0, 90, 120], array_column($q['queue'], 'wait_minutes'));
        $this->assertSame('Asha', $q['queue'][0]['staff_name']);

        $this->api($owner, 'POST', "/api/inventory/salon/queue/{$one}/status", ['status' => 'serving'])->assertOk();
        $q = $this->api($owner, 'GET', '/api/inventory/salon/queue')->json('data');
        $this->assertSame(1, $q['serving']);
        $this->assertSame([90, 120], array_values(array_filter(array_column($q['queue'], 'wait_minutes'), fn ($v) => $v !== null)), 'the one being served still counts');

        $this->api($owner, 'POST', "/api/inventory/salon/queue/{$one}/status", ['status' => 'done'])->assertOk();
        $this->api($owner, 'POST', "/api/inventory/salon/queue/{$one}/status", ['status' => 'waiting'])->assertStatus(422);
        $this->api($owner, 'POST', "/api/inventory/salon/queue/{$two}/status", ['status' => 'left'])->assertOk();
        $q = $this->api($owner, 'GET', '/api/inventory/salon/queue')->json('data');
        $this->assertSame([1, 1, 1], [$q['done'], $q['left'], $q['waiting']]);

        $this->api($owner, 'POST', '/api/inventory/salon/queue', ['name' => 'X', 'product_id' => 999999])->assertStatus(422);
    }

    public function test_the_queue_is_one_salons_only(): void
    {
        $one = $this->salon('One');
        $two = $this->salon('Two');
        $this->api($one, 'POST', '/api/inventory/salon/queue', ['name' => 'Neema'])->assertCreated();
        $this->assertSame([], $this->api($two, 'GET', '/api/inventory/salon/queue')->json('data.queue'));
    }

    public function test_a_salon_starts_with_its_categories_and_brands_once_and_the_owner_may_change_them(): void
    {
        $owner = $this->salon();
        $cats = collect($this->api($owner, 'GET', '/api/inventory/categories')->assertOk()->json('data'))->pluck('name');
        $this->assertCount(15, $cats);
        $this->assertTrue($cats->contains('Kusuka / Braiding'));
        $brands = collect($this->api($owner, 'GET', '/api/inventory/brands')->assertOk()->json('data'))->pluck('name');
        $this->assertTrue($brands->contains('Darling') && $brands->contains('X-pression'));

        // Deleted by the owner, they do not come back.
        foreach ($this->api($owner, 'GET', '/api/inventory/categories')->json('data') as $c) {
            $this->api($owner, 'DELETE', '/api/inventory/categories/' . $c['id'])->assertOk();
        }
        $this->assertSame([], $this->api($owner, 'GET', '/api/inventory/categories')->json('data'));
    }

    public function test_ready_made_categories_are_added_once(): void
    {
        $owner = $this->salon();
        $first = $this->api($owner, 'POST', '/api/inventory/salon/category-presets')->assertOk()->json('data');
        $this->assertCount(15, $first['added']);
        $second = $this->api($owner, 'POST', '/api/inventory/salon/category-presets')->assertOk()->json('data');
        $this->assertSame([], $second['added']);
        $this->assertSame(15, $second['already']);
        $this->assertSame(15, DB::table('inventory_categories')->count());
        $this->api($this->stylist($owner), 'POST', '/api/inventory/salon/category-presets')->assertForbidden();
    }

    public function test_a_service_uses_up_goods_and_a_cancelled_sale_puts_them_back(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 10000);
        $shampoo = $this->goods($owner, 'Shampoo', 5, 3000);
        $this->api($owner, 'PUT', "/api/inventory/salon/services/{$braids}/materials", ['items' => [['material_product_id' => $shampoo, 'quantity' => 2]]])->assertOk();
        $this->assertSame('Shampoo', $this->api($owner, 'GET', "/api/inventory/salon/services/{$braids}/materials")->json('data.0.name'));

        $sale = $this->sell($owner, $braids, 10000, 'cash', 2)->json('data.id');
        $this->assertSame(1, (int) DB::table('inventory_products')->where('id', $shampoo)->value('quantity'), 'two braids use four, five were there');
        $usage = DB::table('inventory_service_usage')->first();
        $this->assertSame(4, (int) $usage->quantity);

        $pl = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?period=today')->assertOk()->json('data');
        $this->assertEquals(12000, $pl['materials_cost']);
        $this->assertEquals(12000, $pl['cost_of_goods']);

        $use = $this->api($owner, 'GET', '/api/inventory/salon/materials-usage')->assertOk()->json('data');
        $this->assertSame(4, $use['materials'][0]['used']);

        $this->api($owner, 'POST', "/api/inventory/sales/{$sale}/cancel", ['reason' => 'Mistake'])->assertOk();
        $this->assertSame(5, (int) DB::table('inventory_products')->where('id', $shampoo)->value('quantity'));
    }

    public function test_a_service_is_never_stopped_by_missing_goods_and_materials_must_be_goods(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 10000);
        $shampoo = $this->goods($owner, 'Shampoo', 0, 3000);
        $this->api($owner, 'PUT', "/api/inventory/salon/services/{$braids}/materials", ['items' => [['material_product_id' => $shampoo, 'quantity' => 2]]])->assertOk();
        $this->sell($owner, $braids, 10000);
        $this->assertSame(0, DB::table('inventory_service_usage')->count());

        $this->api($owner, 'PUT', "/api/inventory/salon/services/{$braids}/materials", ['items' => [['material_product_id' => $braids, 'quantity' => 1]]])->assertStatus(422);
        $this->api($this->stylist($owner), 'PUT', "/api/inventory/salon/services/{$braids}/materials", ['items' => []])->assertForbidden();
    }

    public function test_the_cashbook_can_be_exported_as_csv_and_pdf(): void
    {
        $owner = $this->salon();
        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'opening', 'method' => 'cash', 'amount' => 11000, 'moved_on' => $this->eat()->subDays(2)->toDateString()])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/counts', ['method' => 'cash', 'counted' => 10900, 'counted_on' => $this->eat()->toDateString()])->assertCreated();

        $csv = $this->api($owner, 'GET', '/api/inventory/salon/export/cashbook?format=csv&from=' . $this->eat()->subDays(5)->toDateString() . '&to=' . $this->eat()->toDateString());
        $csv->assertOk();
        $body = (string) $csv->getContent();
        $this->assertStringContainsString('Cashbook', $body);
        $this->assertStringContainsString('Opening balance', $body);
        $this->assertStringContainsString('10900', $body, 'the counted amount is in the file');
        $this->assertStringContainsString('-100', $body, 'and the difference');
        $this->assertStringContainsString('"Total that should be held",11000', $body);

        $pdf = $this->api($owner, 'GET', '/api/inventory/salon/export/cashbook?format=pdf&lang=sw');
        $pdf->assertOk();
        $this->assertStringStartsWith('%PDF', (string) $pdf->getContent());

        $this->api($this->stylist($owner), 'GET', '/api/inventory/salon/export/cashbook')->assertForbidden();
    }

    public function test_a_past_day_can_be_entered_and_counted_and_a_future_one_cannot(): void
    {
        $owner = $this->salon();
        $three = $this->eat()->subDays(3)->toDateString();
        $two = $this->eat()->subDays(2)->toDateString();
        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'opening', 'method' => 'cash', 'amount' => 10000, 'moved_on' => $three])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'owner_withdrawal', 'method' => 'cash', 'amount' => 4000, 'moved_on' => $two])->assertCreated();

        // As the book stood on that day (the later withdrawal does not exist yet): 10 000, so 12 000 cannot be taken out then.
        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'owner_withdrawal', 'method' => 'cash', 'amount' => 12000, 'moved_on' => $three])->assertStatus(422);

        $count = $this->api($owner, 'POST', '/api/inventory/salon/cashbook/counts', ['method' => 'cash', 'counted' => 6000, 'counted_on' => $two])->assertCreated();
        $this->assertEquals(6000, $count->json('data.expected'));
        $this->assertEquals(0, $count->json('data.difference'));

        // Yesterday's count of the earlier day sees only what was entered up to then.
        $early = $this->api($owner, 'POST', '/api/inventory/salon/cashbook/counts', ['method' => 'cash', 'counted' => 10000, 'counted_on' => $three])->assertCreated();
        $this->assertEquals(10000, $early->json('data.expected'));

        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'owner_deposit', 'method' => 'cash', 'amount' => 1, 'moved_on' => $this->eat()->addDay()->toDateString()])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/counts', ['method' => 'cash', 'counted' => 1, 'counted_on' => $this->eat()->addDay()->toDateString()])->assertStatus(422);
    }

    public function test_today_is_the_default_view_and_a_single_day_range_works(): void
    {
        $owner = $this->salon();
        $this->api($owner, 'POST', '/api/inventory/salon/cashbook/moves', ['kind' => 'owner_deposit', 'method' => 'bank', 'amount' => 7000])->assertCreated();
        $today = $this->eat()->toDateString();
        $day = $this->api($owner, 'GET', "/api/inventory/salon/cashbook?from={$today}&to={$today}")->assertOk()->json('data');
        $this->assertSame($today, $day['from']);
        $this->assertSame($today, $day['to']);
        $this->assertEquals(7000, $day['places']['bank']['closing']);
        $this->assertEquals(0, $day['places']['bank']['opening']);

        $this->api($owner, 'GET', "/api/inventory/salon/cashbook?from={$today}&to=" . $this->eat()->subDay()->toDateString())->assertStatus(422);
    }

    public function test_the_till_picks_the_goods_a_visit_used_and_that_replaces_the_usual_ones(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner);
        $shampoo = $this->goods($owner, 'Shampoo', 20, 3000);
        $dye = $this->goods($owner, 'Dye', 20, 5000);
        $this->api($owner, 'PUT', "/api/inventory/salon/services/{$braids}/materials", ['items' => [['material_product_id' => $shampoo, 'quantity' => 2]]])->assertOk();
        $this->assertSame([['product_id' => $shampoo, 'name' => 'Shampoo', 'quantity' => 2]], $this->api($owner, 'GET', "/api/inventory/salon/services/{$braids}/usual-goods")->assertOk()->json('data'));

        $visit = fn (?array $materials) => $this->api($owner, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 10000, 'discount' => 0, 'tax' => 0, 'total' => 10000, 'paid_total' => 10000,
            'items' => [array_filter(['product_id' => $braids, 'quantity' => 1, 'unit_price' => 10000, 'materials' => $materials], fn ($v) => $v !== null)],
        ])->assertCreated();
        $stock = fn (int $id) => (int) DB::table('inventory_products')->where('id', $id)->value('quantity');

        $visit(null);                                                            // nothing picked: the usual goods
        $this->assertSame([18, 20], [$stock($shampoo), $stock($dye)]);

        $sale = $visit([['product_id' => $dye, 'quantity' => 3], ['product_id' => $shampoo, 'quantity' => 1]])->json('data.id'); // picked: these instead
        $this->assertSame([17, 17], [$stock($shampoo), $stock($dye)]);
        $used = collect($this->api($owner, 'GET', "/api/inventory/sales/{$sale}")->json('data.salon_breakdown.services.0.materials'))->pluck('quantity', 'name')->all();
        $this->assertSame(['Dye' => 3, 'Shampoo' => 1], $used);

        $visit([]);                                                              // picked nothing: no goods used
        $this->assertSame([17, 17], [$stock($shampoo), $stock($dye)]);

        $this->api($owner, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 10000, 'discount' => 0, 'tax' => 0, 'total' => 10000, 'paid_total' => 10000,
            'items' => [['product_id' => $braids, 'quantity' => 1, 'unit_price' => 10000, 'materials' => [['product_id' => $dye, 'quantity' => 0]]]],
        ])->assertStatus(422);
    }
}
