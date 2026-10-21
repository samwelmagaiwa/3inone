<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** The salon's reports page: every figure checked against sales, bookings and spending made in the test. */
class SalonReportsTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function salon(string $name = 'Glow'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0727' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function person(User $owner, string $role, string $name): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [], array $headers = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->withHeaders($headers)->json($method, $uri, $body);
    }

    private function service(User $as, string $name, int $price): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price, 'duration_minutes' => 60])->assertCreated()->json('data.id');
    }

    private function sell(User $as, int $product, int $price, ?User $stylist = null, ?int $customer = null, string $method = 'cash', int $paid = -1, array $headers = [])
    {
        $paid = $paid < 0 ? $price : $paid;

        return $this->api($as, 'POST', '/api/inventory/sales', array_filter([
            'customer_id' => $customer, 'customer_name_override' => $customer === null ? 'Walk-in' : null,
            'payment_status' => $paid >= $price ? 'paid' : ($paid > 0 ? 'partial' : 'debt'), 'subtotal' => $price, 'discount' => 0, 'tax' => 0, 'total' => $price, 'paid_total' => $paid,
            'items' => [array_filter(['product_id' => $product, 'quantity' => 1, 'unit_price' => $price, 'staff_id' => $stylist ? (string) $stylist->id : null])],
            'payments' => $paid > 0 ? [['amount' => $paid, 'method' => $method]] : [],
            'due_date' => $paid >= $price ? null : now()->addDays(7)->toDateString(),
        ], fn ($v) => $v !== null && $v !== []), $headers);
    }

    private function client(User $owner, string $name, string $phone, ?string $birthday = null): int
    {
        return $this->api($owner, 'POST', '/api/inventory/customers', array_filter(['name' => $name, 'phone' => $phone]))->assertSuccessful()->json('data.id');
    }

    public function test_the_figures_match_what_was_sold_and_spent(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'hair_stylist', 'Asha');
        $bahati = $this->person($owner, 'nail_technician', 'Bahati');
        $braids = $this->service($owner, 'Braids', 40000);
        $nails = $this->service($owner, 'Nails', 15000);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $rehema = $this->client($owner, 'Rehema', '0711000002');

        $this->sell($owner, $braids, 40000, $asha, $neema, 'mpesa')->assertCreated();
        $this->sell($owner, $braids, 40000, $asha, $rehema, 'cash')->assertCreated();
        $this->sell($owner, $nails, 15000, $bahati, $neema, 'cash')->assertCreated();
        $this->sell($owner, $nails, 15000, $bahati, $rehema, 'cash', 5000)->assertCreated();   // 10 000 still owed
        $this->api($owner, 'POST', '/api/inventory/expenses', ['category' => 'rent', 'description' => 'Rent', 'amount' => 20000, 'expense_date' => now('Africa/Dar_es_Salaam')->toDateString()])->assertCreated();

        $r = $this->api($owner, 'GET', '/api/inventory/salon/reports')->assertOk()->json('data');

        $this->assertEquals(110000, $r['summary']['revenue']);
        $this->assertEquals(20000, $r['summary']['expenses']);
        $this->assertSame(4, $r['summary']['sales']);

        $this->assertSame(['Braids', 'Nails'], array_column($r['by_service'], 'name'), 'best first');
        $this->assertEquals([80000, 30000], array_column($r['by_service'], 'revenue'));
        $this->assertSame([2, 2], array_column($r['by_service'], 'times'));

        $this->assertSame(['Asha', 'Bahati'], array_column($r['by_stylist'], 'name'));
        $this->assertEquals([80000, 30000], array_column($r['by_stylist'], 'revenue'));
        $this->assertSame([2, 2], array_column($r['by_stylist'], 'clients'));

        $methods = collect($r['by_method'])->pluck('amount', 'method');
        $this->assertEquals(40000, $methods['mpesa']);
        $this->assertEquals(60000, $methods['cash']);

        $this->assertSame('rent', $r['expenses_by_category'][0]['category']);

        $this->assertSame(2, $r['clients']['active']);
        $this->assertSame(2, $r['clients']['new']);
        $this->assertSame(0, $r['clients']['returning']);
        $this->assertSame(['Neema', 'Rehema'], array_column($r['clients']['top_spenders'], 'name'));
        $this->assertEquals([55000, 55000], array_column($r['clients']['top_spenders'], 'spent'));

        $this->assertEquals(10000, $r['owed']['total']);
        $this->assertSame(1, $r['owed']['count']);
        $this->assertSame('Rehema', $r['owed']['list'][0]['client']);
        $this->assertEquals(10000, $r['owed']['list'][0]['due']);
    }

    public function test_the_diary_counts_how_bookings_ended_and_how_many_came_online(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner, 'Wash', 5000);
        $day = now('Africa/Dar_es_Salaam')->addDay()->toDateString();
        $make = fn (string $time) => $this->api($owner, 'POST', '/api/inventory/salon/appointments', ['client_name' => 'C' . $time, 'starts_at' => "{$day} {$time}", 'services' => [['product_id' => $wash]]])->assertCreated()->json('data.id');
        $a = $make('09:00');
        $b = $make('10:30');
        $c = $make('12:00');
        $make('14:00');
        DB::table('inventory_appointments')->where('id', $c)->update(['source' => 'online']);
        $this->api($owner, 'POST', "/api/inventory/salon/appointments/{$a}/status", ['status' => 'cancelled'])->assertOk();
        $this->api($owner, 'POST', "/api/inventory/salon/appointments/{$b}/status", ['status' => 'no_show'])->assertOk();

        $r = $this->api($owner, 'GET', "/api/inventory/salon/reports?from={$day}&to={$day}")->assertOk()->json('data.diary');
        $this->assertSame([4, 1, 1, 2, 1], [$r['booked'], $r['cancelled'], $r['no_show'], $r['still_open'], $r['online']]);
        $this->assertEquals(50.0, $r['no_show_rate'], 'of the two that ended, one did not come');
    }

    public function test_returning_clients_and_the_goods_on_the_shelf(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 10000);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $this->sell($owner, $braids, 10000, null, $neema)->assertCreated();
        $this->sell($owner, $braids, 10000, null, $neema)->assertCreated();
        // Went back in time: her first visit was before this month, so she is returning now.
        DB::table('inventory_sales')->orderBy('id')->limit(1)->update(['created_at' => now()->subMonths(2)]);
        $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Shampoo', 'quantity' => 4, 'min_stock' => 5, 'status' => 'active', 'cost_price' => 3000, 'selling_price' => 8000])->assertCreated();

        $r = $this->api($owner, 'GET', '/api/inventory/salon/reports')->assertOk()->json('data');
        $this->assertSame([1, 0, 1], [$r['clients']['active'], $r['clients']['new'], $r['clients']['returning']]);
        $this->assertSame(['items' => 1, 'low' => 1], ['items' => $r['stock']['items'], 'low' => $r['stock']['low']]);
        $this->assertEquals(12000, $r['stock']['at_cost']);
        $this->assertEquals(32000, $r['stock']['at_price']);
    }

    public function test_by_branch_and_the_branch_filter(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 10000);
        $a = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Kariakoo'])->assertCreated()->json('data.id');
        $b = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Mikocheni'])->assertCreated()->json('data.id');
        $this->sell($owner, $braids, 10000, null, null, 'cash', -1, ['X-Branch' => (string) $a])->assertCreated();
        $this->sell($owner, $braids, 10000, null, null, 'cash', -1, ['X-Branch' => (string) $a])->assertCreated();
        $this->sell($owner, $braids, 10000, null, null, 'cash', -1, ['X-Branch' => (string) $b])->assertCreated();

        $all = $this->api($owner, 'GET', '/api/inventory/salon/reports')->assertOk()->json('data');
        $this->assertEquals(30000, $all['summary']['revenue']);
        $this->assertSame(['Kariakoo', 'Mikocheni'], array_column($all['by_branch'], 'name'));
        $this->assertEquals([20000, 10000], array_column($all['by_branch'], 'revenue'));

        $one = $this->api($owner, 'GET', '/api/inventory/salon/reports', [], ['X-Branch' => (string) $b])->assertOk()->json('data');
        $this->assertEquals(10000, $one['summary']['revenue']);
        $this->assertEquals([10000], array_column($one['by_service'], 'revenue'));
        $this->assertSame([], $one['by_branch'], 'one branch is already chosen');
    }

    public function test_it_follows_the_reports_right_and_never_shows_another_salon(): void
    {
        $owner = $this->salon('One');
        $other = $this->salon('Two');
        $asha = $this->person($owner, 'hair_stylist', 'Asha');
        $acc = $this->person($owner, 'accountant', 'Acc');
        $braids = $this->service($owner, 'Braids', 10000);
        $this->sell($owner, $braids, 10000)->assertCreated();

        $this->api($asha, 'GET', '/api/inventory/salon/reports')->assertForbidden();
        $this->assertEquals(10000, $this->api($acc, 'GET', '/api/inventory/salon/reports')->assertOk()->json('data.summary.revenue'));
        $this->assertEquals(0, $this->api($other, 'GET', '/api/inventory/salon/reports')->assertOk()->json('data.summary.revenue'));
        $this->assertSame([], $this->api($other, 'GET', '/api/inventory/salon/reports')->json('data.by_service'));

        $this->api($owner, 'GET', '/api/inventory/salon/reports?from=2026-10-09&to=2026-10-01')->assertStatus(422);
    }
}
