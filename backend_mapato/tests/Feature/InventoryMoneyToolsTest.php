<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Inventory\BusinessAdvisor;
use App\Support\Inventory\MonthlyFigures;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/** Old debts, personal spending, the monthly report with its comparison and target, the advice, and the month-end job. */
class InventoryMoneyToolsTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function shop(string $name = 'Mama Shop'): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, fn () => TenantContext::runInService('inventory', $fn));
    }

    private function product(User $as, string $name, int $stock, int $cost, int $price): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'sku' => strtoupper(substr($name, 0, 3)) . ++$this->seq, 'quantity' => $stock, 'min_stock' => 0, 'status' => 'active', 'cost_price' => $cost, 'selling_price' => $price])->assertCreated()->json('data.id');
    }

    /** A paid (or credit) sale of one product, optionally dated into another month. */
    private function sell(User $as, int $product, int $qty, int $price, int $cost, ?int $customer = null, string $status = 'paid', ?string $on = null): int
    {
        $total = $qty * $price;
        $id = $this->api($as, 'POST', '/api/inventory/sales', array_filter([
            'customer_id' => $customer, 'payment_status' => $status, 'subtotal' => $total, 'discount' => 0, 'tax' => 0, 'total' => $total,
            'paid_total' => $status === 'paid' ? $total : 0,
            'due_date' => $status === 'paid' ? null : now()->addDays(7)->toDateString(),
            'items' => [['product_id' => $product, 'quantity' => $qty, 'unit_price' => $price, 'unit_cost_snapshot' => $cost]],
        ], fn ($v) => $v !== null))->assertCreated()->json('data.id');
        if ($on !== null) {
            $this->rows($as, fn () => DB::table('inventory_sales')->where('id', $id)->update(['created_at' => $on . ' 09:00:00']));
        }

        return $id;
    }

    private function customer(User $as, string $name, string $phone): int
    {
        return $this->api($as, 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertCreated()->json('data.id');
    }

    private function expense(User $as, string $category, int $amount, string $on, array $extra = [])
    {
        return $this->api($as, 'POST', '/api/inventory/expenses', array_merge(['category' => $category, 'description' => ucfirst($category), 'amount' => $amount, 'expense_date' => $on], $extra));
    }

    private function now(string $day = '2026-11-18 10:00:00'): void
    {
        Carbon::setTestNow(Carbon::parse($day, 'Africa/Dar_es_Salaam')->utc());
    }

    // ------------------------------------------------------------------ old debts

    public function test_a_debt_a_customer_had_before_the_app_joins_every_debt_view_and_is_paid_in_parts(): void
    {
        $this->now();
        $owner = $this->shop();
        $id = $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'name' => 'Mama Neema', 'phone' => '0711000001', 'amount' => 350000, 'started_on' => '2026-06-01', 'due_on' => '2026-07-01', 'note' => 'Soda za mwaka jana'])->assertCreated()->json('data.id');

        $list = $this->api($owner, 'GET', '/api/inventory/opening-debts?kind=receivable')->assertOk()->json('data');
        $this->assertEquals([350000, 350000, 0], [$list['total'], $list['old'], $list['from_records']]);
        $this->assertEquals(['Mama Neema', 350000, 350000], [$list['debts'][0]['name'], $list['debts'][0]['left'], $list['debts'][0]['amount']]);
        $this->assertGreaterThan(100, $list['debts'][0]['days_late']);

        // the debtor is a real customer now: the credit list, credit check, ageing and statement all see the debt
        $cid = $list['debts'][0]['customer_id'];
        $credit = collect($this->api($owner, 'GET', '/api/inventory/credit/customers')->json('data'))->firstWhere('id', $cid);
        $this->assertSame([350000.0, 350000.0], [(float) $credit['balance'], (float) $credit['old_balance']]);
        $this->assertEquals(350000, $this->api($owner, 'GET', "/api/inventory/credit/customers/{$cid}/check")->json('data.balance'));
        $ageing = $this->api($owner, 'GET', '/api/inventory/credit/debtors-ageing')->json();
        $this->assertSame('Mama Neema', $ageing['data'][0]['customer_name']);
        $this->assertEquals(350000, $ageing['data'][0]['days_90_plus']);
        $this->assertEquals(350000, $this->api($owner, 'GET', "/api/inventory/credit/customers/{$cid}/statement")->json('data.old_debt'));

        // the same number written another way is the same customer
        $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'name' => 'Neema J', 'phone' => '+255711000001', 'amount' => 10000])->assertCreated();
        $this->assertSame(1, $this->rows($owner, fn () => DB::table('inventory_customers')->count()));

        // paying in parts, never more than is left
        $this->api($owner, 'POST', "/api/inventory/opening-debts/{$id}/payments", ['amount' => 100000, 'method' => 'cash'])->assertOk()->assertJsonPath('data.left', 250000);
        $this->api($owner, 'POST', "/api/inventory/opening-debts/{$id}/payments", ['amount' => 250001])->assertStatus(422);
        $this->assertCount(1, $this->api($owner, 'GET', "/api/inventory/opening-debts/{$id}/payments")->json('data'));
        $this->api($owner, 'POST', "/api/inventory/opening-debts/{$id}/payments", ['amount' => 250000])->assertOk()->assertJsonPath('data.left', 0);
        $this->assertCount(1, $this->api($owner, 'GET', '/api/inventory/opening-debts?kind=receivable')->json('data.debts'), 'the paid one drops off the list, the other stays');
        $this->assertCount(2, $this->api($owner, 'GET', '/api/inventory/opening-debts?kind=receivable&paid=1')->json('data.debts'));

        // a debt with payments stays as a record; a wrong one with none can be removed
        $this->api($owner, 'DELETE', "/api/inventory/opening-debts/{$id}")->assertStatus(422);
        $other = $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'name' => 'Wrong', 'amount' => 5])->json('data.id');
        $this->api($owner, 'DELETE', "/api/inventory/opening-debts/{$other}")->assertOk();
    }

    public function test_what_the_business_owes_is_written_down_and_paid_too_and_the_checks_hold(): void
    {
        $this->now();
        $owner = $this->shop();
        $id = $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'payable', 'name' => 'Bakhresa Wholesale', 'amount' => 800000, 'started_on' => '2026-10-01'])->assertCreated()->json('data.id');
        $this->assertEquals(800000, $this->api($owner, 'GET', '/api/inventory/opening-debts?kind=payable')->json('data.total'));
        $this->api($owner, 'POST', "/api/inventory/opening-debts/{$id}/payments", ['amount' => 300000])->assertOk();
        $this->assertEquals(500000, $this->api($owner, 'GET', '/api/inventory/opening-debts?kind=payable')->json('data.total'));

        $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'amount' => 100])->assertStatus(422); // no name
        $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'payable', 'name' => 'X', 'amount' => 0])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'other', 'name' => 'X', 'amount' => 5])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'payable', 'name' => 'X', 'amount' => 5, 'started_on' => '2026-05-02', 'due_on' => '2026-05-01'])->assertStatus(422);
    }

    public function test_one_business_never_sees_or_pays_another_ones_old_debts_and_staff_without_rights_are_refused(): void
    {
        $this->now();
        $a = $this->shop('A shop');
        $b = $this->shop('B shop');
        $id = $this->api($a, 'POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'name' => 'Only A', 'amount' => 1000])->assertCreated()->json('data.id');

        $this->assertCount(0, $this->api($b, 'GET', '/api/inventory/opening-debts?kind=receivable')->json('data.debts'));
        $this->api($b, 'POST', "/api/inventory/opening-debts/{$id}/payments", ['amount' => 10])->assertNotFound();
        $this->api($b, 'DELETE', "/api/inventory/opening-debts/{$id}")->assertNotFound();
        $this->api($b, 'GET', "/api/inventory/opening-debts/{$id}/payments")->assertNotFound();

        $driver = $this->givenServices(User::factory()->create(['role' => 'driver', 'is_active' => true, 'created_by' => $a->id]), 'inventory');
        $this->api($driver, 'GET', '/api/inventory/opening-debts?kind=receivable')->assertForbidden();
        $this->api($driver, 'GET', '/api/inventory/monthly-report')->assertForbidden();
        $this->api($driver, 'PUT', '/api/inventory/monthly-target', ['month' => '2026-11', 'profit_target' => 5])->assertForbidden();
    }

    // ------------------------------------------------------------------ personal spending

    public function test_personal_spending_is_listed_but_never_lowers_the_profit(): void
    {
        $this->now();
        $owner = $this->shop();
        $p = $this->product($owner, 'Soda', 100, 500, 1000);
        $this->sell($owner, $p, 10, 1000, 500);                       // sales 10,000, cost 5,000
        $this->expense($owner, 'rent', 1000, '2026-11-05')->assertCreated();
        $this->expense($owner, 'family', 700, '2026-11-06')->assertCreated();                       // personal by its category
        $this->expense($owner, 'other', 300, '2026-11-07', ['is_personal' => true])->assertCreated(); // personal by the switch

        $s = $this->api($owner, 'GET', '/api/inventory/expenses/summary?period=custom&from=2026-11-01&to=2026-11-30')->assertOk()->json('data');
        $this->assertEquals(1000, $s['total_expenses']);
        $this->assertEquals(1000, $s['personal_total']);
        $this->assertEquals(4000, $s['net_profit']);
        $this->assertCount(3, $this->api($owner, 'GET', '/api/inventory/expenses?period=custom&from=2026-11-01&to=2026-11-30')->json('data'));

        $m = $this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-11')->assertOk()->json('data.figures');
        $this->assertEquals([10000, 5000, 5000, 1000, 1000, 4000], [$m['sales'], $m['cost_of_goods'], $m['gross_profit'], $m['expenses'], $m['personal_spending'], $m['net_profit']]);

        // moving a business expense to personal takes it off the profit
        $id = $this->rows($owner, fn () => DB::table('inventory_expenses')->where('category', 'rent')->value('id'));
        $this->api($owner, 'PUT', "/api/inventory/expenses/{$id}", ['is_personal' => true])->assertOk();
        $this->assertEquals(5000, $this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-11')->json('data.figures.net_profit'));
    }

    // ------------------------------------------------------------------ the monthly report

    public function test_the_report_adds_up_the_month_and_compares_it_with_the_month_before(): void
    {
        $this->now('2026-11-30 18:00:00'); // the last day: the whole month is there, so it is compared with all of October
        $owner = $this->shop();
        $soda = $this->product($owner, 'Soda', 200, 500, 1000);
        $mama = $this->customer($owner, 'Mama Neema', '0711000001');

        // October: sales 20,000, cost 10,000, rent 2,000 -> profit 8,000
        $this->sell($owner, $soda, 20, 1000, 500, null, 'paid', '2026-10-10');
        $this->expense($owner, 'rent', 2000, '2026-10-05')->assertCreated();
        // November: sales 30,000 (one on credit), cost 15,000, rent 3,000 -> profit 12,000
        $this->sell($owner, $soda, 20, 1000, 500, null, 'paid', '2026-11-08');
        $this->sell($owner, $soda, 10, 1000, 500, $mama, 'debt', '2026-11-20');
        $this->expense($owner, 'rent', 3000, '2026-11-05')->assertCreated();
        // a cancelled sale counts for nothing
        $cancelled = $this->sell($owner, $soda, 5, 1000, 500, null, 'paid', '2026-11-12');
        $this->api($owner, 'POST', "/api/inventory/sales/{$cancelled}/cancel", ['reason' => 'Mistake'])->assertOk();
        $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'name' => 'Old Debtor', 'amount' => 40000, 'started_on' => '2026-05-01'])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'payable', 'name' => 'Supplier Old', 'amount' => 25000])->assertCreated();

        $r = $this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-11')->assertOk()->json('data');

        $this->assertEquals([30000, 15000, 15000, 3000, 12000], [$r['figures']['sales'], $r['figures']['cost_of_goods'], $r['figures']['gross_profit'], $r['figures']['expenses'], $r['figures']['net_profit']]);
        $this->assertEquals(50.0, $r['figures']['margin_percent']);
        $this->assertEquals(8000, $r['previous']['figures']['net_profit']);
        $this->assertSame(['up', 50.0], [$r['compare']['net_profit']['direction'], (float) $r['compare']['net_profit']['percent']], 'profit 8,000 -> 12,000 is +50%');
        $this->assertSame(['up', 50.0], [$r['compare']['sales']['direction'], (float) $r['compare']['sales']['percent']]);
        $this->assertSame(['up', false], [$r['compare']['expenses']['direction'], $r['compare']['expenses']['good']], '3,000 vs 2,000 is more spending, and that is not good');
        $this->assertSame(['up', 'profit'], [$r['overall']['direction'], $r['overall']['based_on']]);

        // where the business stands: stock at cost (200 - 20 - 20 - 10 = 150; the cancelled 5 went back) + debts - what it owes
        $p = $r['position'];
        $this->assertEquals(150 * 500, $p['stock_value']);
        $this->assertEquals(10000 + 40000, $p['receivable'], 'the credit sale plus the old debt');
        $this->assertEquals(25000, $p['payable']);
        $this->assertEquals($p['stock_value'] + 50000 - 25000, $p['capital']);
        $this->assertEqualsCanonicalizing(['Mama Neema', 'Old Debtor'], array_column($r['debtors'], 'name'));
        $this->assertSame('Old Debtor', $r['debtors'][0]['name'], 'the biggest debt first');
        $this->assertSame(['Supplier Old'], array_column($r['creditors'], 'name'));
        $this->assertSame('Soda', $r['top_products'][0]['name']);

        // the sleeping-stock list never includes what sold this month
        $this->assertSame([], $r['slow_stock']);
    }

    public function test_a_month_in_progress_is_compared_with_the_same_days_of_the_month_before(): void
    {
        $this->now('2026-11-10 12:00:00'); // day 10
        $owner = $this->shop();
        $soda = $this->product($owner, 'Soda', 500, 500, 1000);
        $this->sell($owner, $soda, 10, 1000, 500, null, 'paid', '2026-10-05');   // inside October's first 10 days
        $this->sell($owner, $soda, 100, 1000, 500, null, 'paid', '2026-10-25');  // after them: must not be compared with a young month
        $this->sell($owner, $soda, 10, 1000, 500, null, 'paid', '2026-11-04');

        $r = $this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-11')->assertOk()->json('data');

        $this->assertTrue($r['previous']['like_for_like']);
        $this->assertEquals(10000, $r['previous']['figures']['sales'], 'only October 1-10');
        $this->assertEquals(110000, $r['previous']['full']['sales'], 'the whole of October is there too');
        $this->assertSame('same', $r['compare']['sales']['direction']);
        $this->assertSame(10, $r['days_elapsed']);
    }

    public function test_the_capital_change_needs_what_was_remembered_at_the_end_of_the_month_before(): void
    {
        $this->now('2026-11-15 10:00:00');
        $owner = $this->shop();
        $this->product($owner, 'Soda', 100, 500, 1000); // stock 50,000

        $first = $this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-11')->json('data');
        $this->assertNull($first['capital_change'], 'nothing was remembered for October');
        $this->assertEquals(50000, $this->rows($owner, fn () => DB::table('inventory_month_snapshots')->where('month', '2026-11')->value('capital')), 'this month is remembered from now on');

        $this->rows($owner, fn () => DB::table('inventory_month_snapshots')->insert(['month' => '2026-10', 'stock_value' => 20000, 'receivable' => 0, 'payable' => 0, 'capital' => 20000, 'created_at' => now(), 'updated_at' => now()]));
        $r = $this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-11')->json('data');
        $this->assertSame(['up', 150.0, 30000.0], [$r['capital_change']['direction'], (float) $r['capital_change']['percent'], (float) $r['capital_change']['change']]);

        // a past month shows what was remembered then, not today's stock
        $past = $this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-10')->json('data');
        $this->assertEquals(20000, $past['position']['capital']);
        // a month nobody watched has no balances
        $this->assertNull($this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-01')->json('data.position'));
    }

    public function test_a_month_must_be_a_real_month(): void
    {
        $this->now();
        $owner = $this->shop();
        foreach (['2026-13', 'abc', '2026-1', '26-11'] as $bad) {
            $this->api($owner, 'GET', '/api/inventory/monthly-report?month=' . $bad)->assertStatus(422);
        }
        $this->assertSame(MonthlyFigures::currentMonth(), $this->api($owner, 'GET', '/api/inventory/monthly-report')->json('data.month'));
    }

    // ------------------------------------------------------------------ the profit target

    public function test_a_target_says_on_track_behind_reached_or_missed(): void
    {
        $this->now('2026-11-15 10:00:00'); // day 15 of 30
        $owner = $this->shop();
        $soda = $this->product($owner, 'Soda', 1000, 500, 1000);
        $this->sell($owner, $soda, 20, 1000, 500, null, 'paid', '2026-11-03'); // profit 10,000

        $this->assertNull($this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-11')->json('data.target'));
        $t = $this->api($owner, 'PUT', '/api/inventory/monthly-target', ['month' => '2026-11', 'profit_target' => 30000])->assertOk()->json('data');
        $this->assertSame(['behind', 33.3, 20000.0, 15000.0, 15], [$t['status'], (float) $t['progress_percent'], (float) $t['left'], (float) $t['expected_by_today'], $t['days_left']], 'halfway through the month it should have 15,000');

        $this->api($owner, 'PUT', '/api/inventory/monthly-target', ['month' => '2026-11', 'profit_target' => 18000])->assertOk()->assertJsonPath('data.status', 'on_track');
        $this->api($owner, 'PUT', '/api/inventory/monthly-target', ['month' => '2026-11', 'profit_target' => 10000])->assertOk()->assertJsonPath('data.status', 'reached');
        $this->assertEquals(0, $this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-11')->json('data.target.left'));

        // a future month can have one; a past month cannot; zero clears it
        $this->api($owner, 'PUT', '/api/inventory/monthly-target', ['month' => '2026-12', 'profit_target' => 5000])->assertOk()->assertJsonPath('data.status', 'not_started');
        $this->api($owner, 'PUT', '/api/inventory/monthly-target', ['month' => '2026-10', 'profit_target' => 5000])->assertStatus(422);
        $this->api($owner, 'PUT', '/api/inventory/monthly-target', ['month' => '2026-12', 'profit_target' => 0])->assertOk();
        $this->assertNull($this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-12')->json('data.target'));
        $this->api($owner, 'PUT', '/api/inventory/monthly-target', ['month' => 'nope', 'profit_target' => 5])->assertStatus(422);

        // after the month: reached or missed
        $this->api($owner, 'PUT', '/api/inventory/monthly-target', ['month' => '2026-11', 'profit_target' => 30000])->assertOk();
        $this->now('2026-12-02 10:00:00');
        $this->assertSame('missed', $this->api($owner, 'GET', '/api/inventory/monthly-report?month=2026-11')->json('data.target.status'));
    }

    // ------------------------------------------------------------------ the advice

    private function seedAdviceShop(): User
    {
        $this->now('2026-11-20 10:00:00');
        $owner = $this->shop('Mama Shop');
        $soda = $this->product($owner, 'Soda', 100, 500, 520);                  // a thin margin
        $this->product($owner, 'Dusty Dye', 50, 2000, 3000);                  // never sells: sleeping stock
        $mama = $this->customer($owner, 'Mama Neema', '0711000001');
        $this->sell($owner, $soda, 10, 520, 500, null, 'paid', '2026-10-10');
        $this->sell($owner, $soda, 5, 520, 500, $mama, 'debt', '2026-11-05');
        $this->expense($owner, 'rent', 4000, '2026-11-02')->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'name' => 'Baba Juma', 'phone' => '0755999888', 'amount' => 90000, 'started_on' => '2026-04-01'])->assertCreated();

        return $owner;
    }

    public function test_without_an_ai_key_the_advice_is_written_by_rules_from_the_numbers(): void
    {
        config(['services.anthropic.key' => '']);
        Http::fake();
        $owner = $this->seedAdviceShop();

        $a = $this->api($owner, 'GET', '/api/inventory/advice?month=2026-11&lang=en')->assertOk()->json('data');

        $this->assertSame(['rules', false], [$a['source'], $a['ai_available']]);
        $titles = implode(' | ', array_column($a['items'], 'title'));
        $text = json_encode($a['items']);
        $this->assertStringContainsString('Stock is sleeping', $titles);
        $this->assertStringContainsString('Dusty Dye', $text);
        $this->assertStringContainsString('Baba Juma', $text, 'the customer who owes is named');
        $this->assertStringContainsString('Customer debts', $titles);
        $this->assertStringContainsString('Thin margin', $titles);
        $this->assertStringNotContainsString('0755999888', $text);
        Http::assertNothingSent();

        $sw = $this->api($owner, 'GET', '/api/inventory/advice?month=2026-11&lang=sw')->json('data');
        $this->assertStringContainsString('Bidhaa zimelala', implode(' | ', array_column($sw['items'], 'title')));
    }

    public function test_with_a_key_claude_gets_the_full_facts_with_names_and_never_phone_numbers(): void
    {
        config(['services.anthropic.key' => 'sk-test', 'services.anthropic.model' => 'claude-test']);
        Http::fake(['api.anthropic.com/*' => Http::response(['content' => [['type' => 'text', 'text' => "Here you go:\n" . json_encode([
            ['level' => 'warning', 'title' => 'Collect from Baba Juma', 'detail' => 'Baba Juma owes TSh 90,000 for 200+ days. Call him this week.'],
            ['level' => 'nonsense', 'title' => 'Move Dusty Dye', 'detail' => 'Dusty Dye has not sold: discount it.'],
            ['title' => '', 'detail' => 'dropped because it has no title'],
        ])]]], 200)]);
        $owner = $this->seedAdviceShop();

        $a = $this->api($owner, 'GET', '/api/inventory/advice?month=2026-11&lang=en')->assertOk()->json('data');

        $this->assertSame(['ai', true, null], [$a['source'], $a['ai_available'], $a['ai_error']]);
        $this->assertSame(['warning', 'tip'], array_column($a['items'], 'level'), 'a level the app does not know becomes a tip; an item with no title is dropped');
        $this->assertCount(2, $a['items']);

        Http::assertSentCount(1);
        Http::assertSent(function ($req) {
            $body = json_encode($req->data(), JSON_UNESCAPED_UNICODE);

            return $req->url() === 'https://api.anthropic.com/v1/messages'
                && $req->hasHeader('x-api-key', 'sk-test')
                && $req['model'] === 'claude-test'
                && str_contains($body, 'Baba Juma') && str_contains($body, 'Mama Neema') && str_contains($body, 'Dusty Dye') && str_contains($body, 'Soda')
                && str_contains($body, 'net_profit') && str_contains($body, 'sleeping_stock_30_days')
                && !str_contains($body, '0755999888') && !str_contains($body, '0711000001');
        });

        // asked again the same day: kept, no second call to the AI
        $this->api($owner, 'GET', '/api/inventory/advice?month=2026-11&lang=en')->assertOk()->assertJsonPath('data.source', 'ai');
        Http::assertSentCount(1);
    }

    public function test_when_the_ai_fails_the_owner_still_gets_rule_based_advice_and_refreshing_is_limited(): void
    {
        config(['services.anthropic.key' => 'sk-test']);
        Http::fake(['api.anthropic.com/*' => Http::sequence()->push(['error' => 'busy'], 529)->push(['content' => [['type' => 'text', 'text' => 'not json at all']]], 200)->whenEmpty(Http::response(['content' => [['type' => 'text', 'text' => 'still not json']]], 200))]);
        $owner = $this->seedAdviceShop();

        $a = $this->api($owner, 'GET', '/api/inventory/advice?month=2026-11&lang=en')->assertOk()->json('data');
        $this->assertSame('rules', $a['source']);
        $this->assertStringContainsString('529', (string) $a['ai_error']);
        $this->assertNotEmpty($a['items']);

        $b = $this->api($owner, 'GET', '/api/inventory/advice?month=2026-11&lang=en&refresh=1')->json('data');
        $this->assertSame(['rules', 'empty'], [$b['source'], $b['ai_error']]);

        $left = $b['refreshes_left'];
        for ($i = 0; $i < BusinessAdvisor::REFRESHES_PER_DAY + 2; $i++) {
            $left = $this->api($owner, 'GET', '/api/inventory/advice?month=2026-11&lang=en&refresh=1')->json('data.refreshes_left');
        }
        $this->assertSame(0, $left, 'a few fresh answers a day, then the kept one');
        Http::assertSentCount(BusinessAdvisor::REFRESHES_PER_DAY);
    }

    public function test_a_month_with_no_sales_is_told_to_record_sales_and_the_advice_is_private_to_the_shop(): void
    {
        config(['services.anthropic.key' => '']);
        $this->now();
        $a = $this->shop('A');
        $b = $this->shop('B');
        $this->product($a, 'Secret Item', 10, 100, 200);

        $x = $this->api($b, 'GET', '/api/inventory/advice?month=2026-11&lang=en')->json('data');
        $this->assertStringContainsString('No sales yet', $x['items'][0]['title']);
        $this->assertStringNotContainsString('Secret Item', json_encode($x));
    }

    // ------------------------------------------------------------------ the month-end job

    public function test_the_morning_job_remembers_the_position_and_tells_the_owner_once_how_the_month_ended(): void
    {
        $this->now('2026-11-20 10:00:00');
        $owner = $this->shop();
        $soda = $this->product($owner, 'Soda', 100, 500, 1000);
        $this->sell($owner, $soda, 10, 1000, 500, null, 'paid', '2026-11-04'); // profit 5,000
        $this->api($owner, 'PUT', '/api/inventory/monthly-target', ['month' => '2026-11', 'profit_target' => 4000])->assertOk();

        $this->artisan('inventory:month-close')->assertSuccessful();      // mid-month: remembers, tells nothing yet about November
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_notifications')->where('type', 'inventory_target_result')->count()));
        $this->assertNotNull($this->rows($owner, fn () => DB::table('inventory_month_snapshots')->where('month', '2026-11')->first()));

        $this->now('2026-12-01 05:00:00');
        $this->artisan('inventory:month-close', ['--dry-run' => true])->expectsOutputToContain('would tell')->assertSuccessful();
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_notifications')->count()), 'a dry run tells nobody');

        $this->artisan('inventory:month-close')->assertSuccessful();
        $this->artisan('inventory:month-close')->assertSuccessful();       // twice: nothing twice
        $notes = collect($this->api($owner, 'GET', '/api/inventory/notifications')->json('data'));
        $this->assertCount(1, $notes->where('type', 'inventory_month_report'));
        $this->assertCount(1, $notes->where('type', 'inventory_target_result'));
        $this->assertStringContainsString('reached', $notes->firstWhere('type', 'inventory_target_result')['title']);
        $this->assertStringContainsString('5,000', $notes->firstWhere('type', 'inventory_month_report')['body']);
    }

    public function test_the_money_tables_are_one_businesss_own(): void
    {
        $this->now();
        $a = $this->shop('A');
        $b = $this->shop('B');
        $this->api($a, 'PUT', '/api/inventory/monthly-target', ['month' => '2026-11', 'profit_target' => 9000])->assertOk();

        $this->assertNull($this->api($b, 'GET', '/api/inventory/monthly-report?month=2026-11')->json('data.target'));
        $this->assertSame(0, $this->rows($b, fn () => DB::table('inventory_targets')->count()));
        $this->assertSame(1, $this->rows($a, fn () => DB::table('inventory_targets')->count()));
    }
}
