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
 * A shop that grows: a customer's whole story for any period, more than one branch with the stock held in each, and a price the
 * cashier writes instead of the list price.
 */
class ShopGrowthTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function shop(string $name = 'Mama Shop'): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function officer(User $owner, string $role = 'sales_officer'): User
    {
        return $this->givenServices(User::factory()->create(['name' => 'Officer ' . $role, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]), 'inventory');
    }

    private function api(User $as, string $method, string $uri, array $body = [], array $headers = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeaders($headers + ['Authorization' => "Bearer {$token}", 'X-Service' => 'inventory'])->json($method, $uri, $body);
    }

    private function product(User $as, string $name, int $stock = 100, int $cost = 600, int $price = 1000): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'sku' => strtoupper(substr($name, 0, 3)) . ++$this->seq, 'quantity' => $stock, 'min_stock' => 0, 'status' => 'active', 'cost_price' => $cost, 'selling_price' => $price])->assertCreated()->json('data.id');
    }

    private function customer(User $as, string $name, string $phone): int
    {
        return $this->api($as, 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertCreated()->json('data.id');
    }

    /** One sale of one product; `on` (a day in Tanzania) moves it into another period; `price` writes the price instead of the list price. */
    private function sell(User $as, int $product, int $qty, ?int $customer = null, string $status = 'paid', ?string $on = null, ?int $price = null, array $headers = []): int
    {
        $unit = $price ?? 1000;
        $total = $qty * $unit;
        $id = $this->api($as, 'POST', '/api/inventory/sales', array_filter([
            'customer_id' => $customer, 'payment_status' => $status, 'subtotal' => $total, 'discount' => 0, 'tax' => 0, 'total' => $total,
            'paid_total' => $status === 'paid' ? $total : 0, 'due_date' => $status === 'paid' ? null : now()->addDays(7)->toDateString(),
            'items' => [['product_id' => $product, 'quantity' => $qty, 'unit_price' => $price, 'unit_cost_snapshot' => 600]],
        ], fn ($v) => $v !== null), $headers)->assertCreated()->json('data.id');
        if ($on !== null) {
            TenantContext::runAs($as, fn () => DB::table('inventory_sales')->where('id', $id)->update(['created_at' => Carbon::parse($on . ' 09:00:00', 'Africa/Dar_es_Salaam')->utc()->format('Y-m-d H:i:s')]));
        }

        return $id;
    }

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::parse('2026-11-25 10:00:00', 'Africa/Dar_es_Salaam')->utc());
    }

    // ------------------------------------------------------------------ the customer's story

    private function customerWithHistory(User $owner): array
    {
        $soda = $this->product($owner, 'Soda');
        $juice = $this->product($owner, 'Juice', 100, 400, 700);
        $neema = $this->customer($owner, 'Mama Neema Joseph', '0711000001');
        $this->sell($owner, $soda, 3, $neema, 'paid', '2026-10-20');            // October: 3,000
        $this->sell($owner, $soda, 2, $neema, 'paid', '2026-11-03');            // week of 2 Nov: 2,000
        $this->sell($owner, $soda, 1, $neema, 'debt', '2026-11-20');            // week of 16 Nov: 1,000 on credit
        $other = $this->customer($owner, 'Someone Else', '0711000002');
        $this->sell($owner, $juice, 5, $other, 'paid', '2026-11-05');

        return [$neema, $soda, $other];
    }

    public function test_a_customers_report_adds_up_purchases_profit_and_debt_for_the_period(): void
    {
        $owner = $this->shop();
        [$neema] = $this->customerWithHistory($owner);

        $r = $this->api($owner, 'GET', "/api/inventory/credit/customers/{$neema}/report?from=2026-11-01&to=2026-11-30")->assertOk()->json('data');

        $this->assertSame('Mama Neema Joseph', $r['customer']['name']);
        $this->assertSame(2, $r['totals']['purchases']);
        $this->assertEquals(3000, $r['totals']['sales']);
        $this->assertEquals(2000, $r['totals']['paid']);
        $this->assertEquals(1000, $r['totals']['unpaid_in_period']);
        $this->assertEquals(1800, $r['totals']['cost'], 'three soda at 600');
        $this->assertEquals(1200, $r['totals']['profit']);
        $this->assertEquals(40.0, $r['totals']['margin_percent']);
        $this->assertEquals(1500, $r['totals']['average_purchase']);
        $this->assertEquals(1000, $r['debt']['owes_now'], 'what the customer owes today, whatever the period');
        $this->assertSame('Soda', $r['top_products'][0]['name']);
        $this->assertEquals(3, $r['top_products'][0]['qty']);
        $this->assertSame(['2026-11'], array_column($r['by_period'], 'period'));
    }

    public function test_the_whole_history_is_there_whatever_the_period(): void
    {
        $owner = $this->shop();
        [$neema] = $this->customerWithHistory($owner);

        $r = $this->api($owner, 'GET', "/api/inventory/credit/customers/{$neema}/report?from=2026-11-01&to=2026-11-30")->json('data');

        $this->assertSame(3, $r['lifetime']['purchases']);
        $this->assertEquals(6000, $r['lifetime']['sales']);
        $this->assertEquals(2400, $r['lifetime']['profit']);
        $this->assertSame('2026-10-20 09:00', $r['lifetime']['first_purchase'], 'shown in Tanzania time');
        $this->assertSame('2026-11-20 09:00', $r['lifetime']['last_purchase']);
    }

    public function test_it_groups_week_by_week_month_by_month_or_day_by_day(): void
    {
        $owner = $this->shop();
        [$neema] = $this->customerWithHistory($owner);
        $q = "from=2026-10-01&to=2026-11-30";

        $weeks = $this->api($owner, 'GET', "/api/inventory/credit/customers/{$neema}/report?{$q}&group=week")->json('data.by_period');
        $this->assertSame(['2026-10-19', '2026-11-02', '2026-11-16'], array_column($weeks, 'period'), 'each week starts on its Monday');
        $this->assertEquals([3000, 2000, 1000], array_column($weeks, 'sales'));

        $months = $this->api($owner, 'GET', "/api/inventory/credit/customers/{$neema}/report?{$q}&group=month")->json('data.by_period');
        $this->assertSame(['2026-10', '2026-11'], array_column($months, 'period'));
        $this->assertEquals([3000, 3000], array_column($months, 'sales'));
        $this->assertEquals([1200, 1200], array_column($months, 'profit'));

        $days = $this->api($owner, 'GET', "/api/inventory/credit/customers/{$neema}/report?{$q}&group=day")->json('data.by_period');
        $this->assertCount(3, $days);
    }

    public function test_a_debt_from_before_the_app_is_part_of_what_the_customer_owes(): void
    {
        $owner = $this->shop();
        [$neema] = $this->customerWithHistory($owner);
        $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'name' => 'Mama Neema Joseph', 'customer_id' => $neema, 'amount' => 90000, 'started_on' => '2026-05-01'])->assertCreated();

        $debt = $this->api($owner, 'GET', "/api/inventory/credit/customers/{$neema}/report?from=2026-11-01&to=2026-11-30")->json('data.debt');

        $this->assertEquals(91000, $debt['owes_now']);
        $this->assertEquals(1000, $debt['from_sales']);
        $this->assertEquals(90000, $debt['from_before_app']);
    }

    public function test_someone_who_may_not_see_profit_never_receives_costs_or_profit(): void
    {
        $owner = $this->shop();
        [$neema, $soda] = $this->customerWithHistory($owner);
        $officer = $this->officer($owner);
        $this->sell($officer, $soda, 4, $neema, 'paid', '2026-11-10');

        $r = $this->api($officer, 'GET', "/api/inventory/credit/customers/{$neema}/report?from=2026-11-01&to=2026-11-30")->assertOk()->json('data');

        $this->assertFalse($r['profit_visible']);
        $this->assertNull($r['totals']['cost']);
        $this->assertNull($r['totals']['profit']);
        $this->assertNull($r['lifetime']['profit']);
        $this->assertNull($r['top_products'][0]['profit']);
        $this->assertDoesNotMatchRegularExpression('/"(cost|profit|margin_percent)":-?[0-9]/', json_encode($r) ?: '', 'not one cost, profit or margin figure anywhere');
    }

    public function test_a_sales_officer_sees_only_the_sales_they_made_but_the_whole_debt(): void
    {
        $owner = $this->shop();
        [$neema, $soda] = $this->customerWithHistory($owner);
        $officer = $this->officer($owner);
        $this->sell($officer, $soda, 4, $neema, 'paid', '2026-11-10');

        $mine = $this->api($officer, 'GET', "/api/inventory/credit/customers/{$neema}/report?from=2026-11-01&to=2026-11-30")->json('data');
        $this->assertSame(1, $mine['totals']['purchases']);
        $this->assertEquals(4000, $mine['totals']['sales']);
        $this->assertEquals(1000, $mine['debt']['owes_now'], 'the debt is the customer\'s, whoever sold');

        $all = $this->api($owner, 'GET', "/api/inventory/credit/customers/{$neema}/report?from=2026-11-01&to=2026-11-30")->json('data');
        $this->assertSame(3, $all['totals']['purchases']);
        $this->assertTrue($all['profit_visible']);
    }

    public function test_an_accountant_sees_profit_and_all_the_sales(): void
    {
        $owner = $this->shop();
        [$neema] = $this->customerWithHistory($owner);
        $accountant = $this->officer($owner, 'accountant');

        $r = $this->api($accountant, 'GET', "/api/inventory/credit/customers/{$neema}/report?from=2026-11-01&to=2026-11-30")->assertOk()->json('data');

        $this->assertTrue($r['profit_visible']);
        $this->assertSame(2, $r['totals']['purchases']);
        $this->assertEquals(1200, $r['totals']['profit']);
    }

    public function test_another_businesss_customer_is_not_found_and_the_dates_are_checked(): void
    {
        $a = $this->shop('Shop A');
        $b = $this->shop('Shop B');
        $theirs = $this->customer($b, 'Secret Customer', '0755000009');
        $mine = $this->customer($a, 'My Customer', '0755000008');

        $this->api($a, 'GET', "/api/inventory/credit/customers/{$theirs}/report")->assertNotFound();
        $this->api($a, 'GET', "/api/inventory/credit/customers/{$mine}/report?from=2026-11-30&to=2026-11-01")->assertStatus(422);
        $this->api($a, 'GET', "/api/inventory/credit/customers/{$mine}/report?group=year")->assertStatus(422);
        $this->api($a, 'GET', "/api/inventory/credit/customers/{$mine}/report")->assertOk()->assertJsonPath('data.totals.purchases', 0);
    }

    // ------------------------------------------------------------------ branches for a shop

    public function test_the_owner_adds_branches_to_a_shop_and_staff_only_read_them(): void
    {
        $owner = $this->shop();
        $officer = $this->officer($owner);

        $id = $this->api($owner, 'POST', '/api/inventory/branches', ['name' => 'Kariakoo', 'address' => 'Mtaa wa Kongo', 'phone' => '0711222333'])->assertCreated()->json('data.id');
        $this->api($owner, 'POST', '/api/inventory/branches', ['name' => 'Kariakoo'])->assertStatus(422);

        $this->api($officer, 'POST', '/api/inventory/branches', ['name' => 'Mbagala'])->assertStatus(403);
        $names = array_column($this->api($officer, 'GET', '/api/inventory/branches')->assertOk()->json('data'), 'name');
        $this->assertSame(['Kariakoo'], $names);

        $this->api($owner, 'PUT', "/api/inventory/branches/{$id}", ['active' => false])->assertOk();
        $this->assertSame([], $this->api($officer, 'GET', '/api/inventory/branches')->json('data'), 'staff do not see a branch that is switched off');
    }

    public function test_a_sale_made_in_a_branch_is_stamped_with_it_and_the_list_can_be_looked_at_by_branch(): void
    {
        $owner = $this->shop();
        $soda = $this->product($owner, 'Soda');
        $kariakoo = $this->api($owner, 'POST', '/api/inventory/branches', ['name' => 'Kariakoo'])->json('data.id');
        $mbagala = $this->api($owner, 'POST', '/api/inventory/branches', ['name' => 'Mbagala'])->json('data.id');

        $a = $this->sell($owner, $soda, 1, null, 'paid', null, null, ['X-Branch' => (string) $kariakoo]);
        $b = $this->sell($owner, $soda, 2, null, 'paid', null, null, ['X-Branch' => (string) $mbagala]);

        $this->assertSame($kariakoo, (int) TenantContext::runAs($owner, fn () => DB::table('inventory_sales')->where('id', $a)->value('branch_id')));

        $inKariakoo = collect($this->api($owner, 'GET', '/api/inventory/sales', [], ['X-Branch' => (string) $kariakoo])->assertOk()->json('data.data') ?? $this->api($owner, 'GET', '/api/inventory/sales', [], ['X-Branch' => (string) $kariakoo])->json('data'))->pluck('id')->all();
        $this->assertSame([$a], $inKariakoo);

        $everywhere = collect($this->api($owner, 'GET', '/api/inventory/sales')->json('data.data') ?? $this->api($owner, 'GET', '/api/inventory/sales')->json('data'))->pluck('id')->sort()->values()->all();
        $this->assertSame([$a, $b], $everywhere, 'with no branch chosen, every branch is shown');
    }

    public function test_goods_are_held_by_branch_a_sale_takes_from_its_branch_and_a_branch_of_another_shop_is_ignored(): void
    {
        $owner = $this->shop();
        $other = $this->shop('Other Shop');
        $soda = $this->product($owner, 'Soda', 50);
        $branch = $this->api($owner, 'POST', '/api/inventory/branches', ['name' => 'Kariakoo'])->json('data.id');
        $foreign = $this->api($other, 'POST', '/api/inventory/branches', ['name' => 'Foreign'])->json('data.id');

        $this->api($owner, 'POST', '/api/inventory/branch-stock/transfer', ['product_id' => $soda, 'to_branch_id' => $branch, 'quantity' => 10])->assertOk();
        $held = fn () => $this->api($owner, 'GET', '/api/inventory/branch-stock')->json('data.products.0.branches.0.quantity');
        $this->assertSame(10, $held());

        $this->sell($owner, $soda, 3, null, 'paid', null, null, ['X-Branch' => (string) $branch]);
        $this->assertSame(7, $held(), 'the sale took three from the branch shelf');
        $this->assertSame(47, TenantContext::runAs($owner, fn () => (int) DB::table('inventory_products')->where('id', $soda)->value('quantity')), 'and from the whole stock');

        $sale = $this->sell($owner, $soda, 1, null, 'paid', null, null, ['X-Branch' => (string) $foreign]);
        $this->assertNull(TenantContext::runAs($owner, fn () => DB::table('inventory_sales')->where('id', $sale)->value('branch_id')), 'another shop\'s branch is not a branch of this one');

        $this->api($owner, 'POST', '/api/inventory/branch-stock/transfer', ['product_id' => $soda, 'from_branch_id' => $branch, 'to_branch_id' => null, 'quantity' => 99])->assertStatus(422);
        $moves = $this->api($owner, 'GET', '/api/inventory/branch-stock/transfers')->assertOk()->json('data');
        $this->assertSame('Soda', $moves[0]['product']);
    }

    public function test_a_shop_with_no_branches_works_exactly_as_before(): void
    {
        $owner = $this->shop();
        $soda = $this->product($owner, 'Soda');

        $id = $this->sell($owner, $soda, 2);

        $this->assertNull(TenantContext::runAs($owner, fn () => DB::table('inventory_sales')->where('id', $id)->value('branch_id')));
        $this->assertSame(98, TenantContext::runAs($owner, fn () => (int) DB::table('inventory_products')->where('id', $soda)->value('quantity')));
    }

    // ------------------------------------------------------------------ a price the cashier writes

    public function test_the_cashier_can_write_the_price_and_the_sale_uses_it(): void
    {
        $owner = $this->shop();
        $soda = $this->product($owner, 'Soda', 100, 600, 1000);
        $neema = $this->customer($owner, 'Mama Neema Joseph', '0711000001');

        $id = $this->sell($owner, $soda, 3, $neema, 'paid', '2026-11-03', 850);

        $sale = $this->api($owner, 'GET', "/api/inventory/sales/{$id}")->assertOk()->json('data');
        $this->assertEquals(2550, $sale['total']);
        $item = $sale['items'][0];
        $this->assertEquals(850, $item['unit_price'], 'the written price, not the list price of 1,000');
        $this->assertEquals(2550, $item['total']);

        $r = $this->api($owner, 'GET', "/api/inventory/credit/customers/{$neema}/report?from=2026-11-01&to=2026-11-30")->json('data');
        $this->assertEquals(2550, $r['totals']['sales']);
        $this->assertEquals(750, $r['totals']['profit'], 'profit follows the price really charged: 2,550 less 3 x 600');
    }

    public function test_a_line_without_a_written_price_still_gets_the_list_price(): void
    {
        $owner = $this->shop();
        $soda = $this->product($owner, 'Soda', 100, 600, 1000);

        $id = $this->sell($owner, $soda, 2, null, 'paid', null, null);

        $this->assertEquals(1000, $this->api($owner, 'GET', "/api/inventory/sales/{$id}")->json('data.items.0.unit_price'));
    }

    public function test_a_written_price_can_not_be_negative(): void
    {
        $owner = $this->shop();
        $soda = $this->product($owner, 'Soda');

        $this->api($owner, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 0, 'discount' => 0, 'tax' => 0, 'total' => 0, 'paid_total' => 0,
            'items' => [['product_id' => $soda, 'quantity' => 1, 'unit_price' => -5]],
        ])->assertStatus(422);
    }

    // ------------------------------------------------------------------ branches in the reports, staff by branch

    private function twoBranches(User $owner): array
    {
        return [
            (int) $this->api($owner, 'POST', '/api/inventory/branches', ['name' => 'Kariakoo'])->json('data.id'),
            (int) $this->api($owner, 'POST', '/api/inventory/branches', ['name' => 'Mbagala'])->json('data.id'),
        ];
    }

    public function test_the_monthly_report_and_detailed_reports_follow_the_chosen_branch(): void
    {
        $owner = $this->shop();
        $soda = $this->product($owner, 'Soda');
        [$k, $m] = $this->twoBranches($owner);
        $this->sell($owner, $soda, 1, null, 'paid', null, null, ['X-Branch' => (string) $k]);
        $this->sell($owner, $soda, 3, null, 'paid', null, null, ['X-Branch' => (string) $m]);

        $sales = fn (array $h) => $this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-11', [], $h)->assertOk()->json('data.figures.sales');
        $this->assertEquals(4000, $sales([]), 'no branch chosen = the whole business');
        $this->assertEquals(1000, $sales(['X-Branch' => (string) $k]));
        $this->assertEquals(3000, $sales(['X-Branch' => (string) $m]));

        $daily = fn (array $h) => $this->api($owner, 'GET', '/api/inventory/reports/daily_sales?from=2026-11-01&to=2026-11-30', [], $h)->assertOk()->json('data.meta.total');
        $this->assertEquals(4000, $daily([]));
        $this->assertEquals(3000, $daily(['X-Branch' => (string) $m]));
    }

    public function test_the_owner_places_a_person_in_a_branch_and_their_sales_follow_it(): void
    {
        $owner = $this->shop();
        $officer = $this->officer($owner);
        $soda = $this->product($owner, 'Soda');
        [$k, $m] = $this->twoBranches($owner);

        $this->api($owner, 'PUT', "/api/inventory/branch-team/{$officer->id}", ['branch_id' => $m])->assertOk();
        $row = collect($this->api($owner, 'GET', '/api/inventory/branch-team')->assertOk()->json('data'))->firstWhere('staff_id', (string) $officer->id);
        $this->assertSame($m, $row['branch_id']);
        $this->assertSame('Mbagala', $row['branch']);

        $id = $this->sell($officer, $soda, 1);
        $this->assertSame($m, (int) TenantContext::runAs($owner, fn () => DB::table('inventory_sales')->where('id', $id)->value('branch_id')), 'no branch chosen: the home branch is stamped');

        $this->api($owner, 'PUT', "/api/inventory/branch-team/{$officer->id}", ['branch_id' => null])->assertOk();
        $this->assertNull(collect($this->api($owner, 'GET', '/api/inventory/branch-team')->json('data'))->firstWhere('staff_id', (string) $officer->id)['branch_id']);

        $this->api($owner, 'PUT', "/api/inventory/branch-team/{$officer->id}", ['branch_id' => 99999])->assertStatus(422);
        $this->api($officer, 'PUT', "/api/inventory/branch-team/{$officer->id}", ['branch_id' => $k])->assertForbidden();
        $this->api($officer, 'GET', '/api/inventory/branch-team')->assertForbidden();

        $other = $this->shop('Other Shop');
        $this->api($other, 'PUT', "/api/inventory/branch-team/{$officer->id}", ['branch_id' => null])->assertStatus(422);
    }

    public function test_sales_are_shown_per_branch_and_per_person_with_profit_only_for_those_who_may_see_it(): void
    {
        $owner = $this->shop();
        $officer = $this->officer($owner);
        $soda = $this->product($owner, 'Soda');
        [$k, $m] = $this->twoBranches($owner);
        $this->sell($owner, $soda, 2, null, 'paid', null, null, ['X-Branch' => (string) $k]);     // 2,000 owner, Kariakoo
        $this->sell($officer, $soda, 3, null, 'paid', null, null, ['X-Branch' => (string) $m]);   // 3,000 officer, Mbagala
        $this->sell($officer, $soda, 1, $this->customer($owner, 'Debtor', '0711000009'), 'debt', null, null, ['X-Branch' => (string) $k]);   // 1,000 officer, Kariakoo, unpaid

        $r = $this->api($owner, 'GET', '/api/inventory/branch-sales?from=2026-11-01&to=2026-11-30')->assertOk()->json('data');

        $this->assertEquals(6000, $r['total']['sales']);
        $byBranch = collect($r['by_branch'])->keyBy('name');
        $this->assertEquals(3000, $byBranch['Kariakoo']['sales']);
        $this->assertEquals(2, $byBranch['Kariakoo']['sales_count']);
        $this->assertEquals(1200, $byBranch['Kariakoo']['profit'], '3000 sold, 3 sodas at 600 cost');
        $this->assertEquals(3000, $byBranch['Mbagala']['sales']);
        $byStaff = collect($r['by_staff'])->keyBy('staff_id');
        $this->assertEquals(2000, $byStaff[(string) $owner->id]['sales']);
        $this->assertEquals(4000, $byStaff[(string) $officer->id]['sales']);
        $this->assertEquals(3000, $byStaff[(string) $officer->id]['paid']);
        $this->assertCount(2, $byStaff[(string) $officer->id]['branches']);

        $this->api($owner, 'GET', '/api/inventory/branch-sales?from=2026-12-01&to=2026-12-31')->assertOk()->assertJsonPath('data.by_branch', []);
    }
}
