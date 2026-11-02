<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * A customer who owed from before the app and then takes goods on credit again: the OLD debt and the NEW debt are kept apart, each with
 * what was owed, what was paid and what is left, and the TOTAL of both. The money received is shared between them (oldest first when
 * nobody says), and every view of the customer's debt reads the same figures.
 */
class CustomerDebtSummaryTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;
    private User $owner;
    private int $rice;
    private int $customer;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::parse('2026-11-18 10:00:00', 'Africa/Dar_es_Salaam')->utc());
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726000001']), 'inventory');
        Business::forOwnerId($this->owner->id)->update(['name' => 'Mama Shop']);
        $this->rice = $this->api('POST', '/api/inventory/products', ['name' => 'Rice', 'sku' => 'RICE1', 'quantity' => 1000, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 600, 'selling_price' => 1000])->assertCreated()->json('data.id');
        $this->customer = $this->api('POST', '/api/inventory/customers', ['name' => 'Mama Mary', 'phone' => '0711000777'])->assertCreated()->json('data.id');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function api(string $method, string $uri, array $body = [])
    {
        $token = $this->owner->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    private function rows(callable $fn)
    {
        return TenantContext::runAs($this->owner, fn () => TenantContext::runInService('inventory', $fn));
    }

    /** A sale on credit of $total (nothing paid), to $customer unless said otherwise. */
    private function creditSale(int $total, ?int $customer = null)
    {
        return $this->api('POST', '/api/inventory/sales', [
            'customer_id' => $customer ?? $this->customer, 'payment_status' => 'debt', 'subtotal' => $total, 'discount' => 0, 'tax' => 0, 'total' => $total, 'paid_total' => 0,
            'due_date' => now()->addDays(7)->toDateString(),
            'items' => [['product_id' => $this->rice, 'quantity' => (int) ($total / 1000), 'unit_price' => 1000, 'unit_cost_snapshot' => 600]],
        ])->assertCreated();
    }

    private function oldDebt(int $amount, ?int $customer = null): int
    {
        return $this->api('POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'customer_id' => $customer ?? $this->customer, 'amount' => $amount, 'started_on' => '2026-06-01'])->assertCreated()->json('data.id');
    }

    private function receive(array $body, ?int $customer = null)
    {
        return $this->api('POST', '/api/inventory/payments', $body + ['customer_id' => $customer ?? $this->customer, 'method' => 'cash']);
    }

    private function debt(?int $customer = null): array
    {
        return $this->api('GET', '/api/inventory/credit/customers/' . ($customer ?? $this->customer) . '/debt-summary')->assertOk()->json('data.debt');
    }

    /** old 350,000 (100,000 paid), new: A 50,000 (20,000 paid), B 30,000 (paid off), C 80,000 (cancelled). */
    private function theStory(): array
    {
        $old = $this->oldDebt(350000);
        $this->api('POST', "/api/inventory/opening-debts/{$old}/payments", ['amount' => 100000, 'method' => 'cash'])->assertOk();
        $a = $this->creditSale(50000)->json('data.id');
        $b = $this->creditSale(30000)->json('data.id');
        $c = $this->creditSale(80000)->json('data.id');
        $this->receive(['amount' => 20000, 'allocations' => [['sale_id' => $a, 'amount' => 20000]]])->assertCreated();
        $this->receive(['amount' => 30000, 'allocations' => [['sale_id' => $b, 'amount' => 30000]]])->assertCreated();
        $this->api('POST', "/api/inventory/sales/{$c}/cancel", ['reason' => 'Customer changed his mind'])->assertOk();

        return ['old' => $old, 'a' => $a, 'b' => $b, 'c' => $c];
    }

    public function test_the_old_debt_the_new_debt_and_the_total_are_kept_apart(): void
    {
        $this->theStory();

        $d = $this->debt();

        $this->assertEquals([350000, 100000, 250000], [$d['old']['original'], $d['old']['paid'], $d['old']['left']], 'the old debt');
        $this->assertEquals([80000, 50000, 30000], [$d['new']['billed'], $d['new']['paid'], $d['new']['left']], 'the new debt: A and B were on credit; the cancelled one never counted');
        $this->assertEquals([430000, 150000, 280000], [$d['total']['owed'], $d['total']['paid'], $d['total']['left']], 'together');
        $this->assertCount(1, $d['old']['entries']);
        $this->assertCount(1, $d['new']['sales'], 'only the sale still to be paid is listed');
        $this->assertEquals(30000, $d['new']['sales'][0]['left']);
    }

    public function test_a_customer_with_no_old_debt_has_only_a_new_debt(): void
    {
        $this->creditSale(40000);

        $d = $this->debt();

        $this->assertEquals([0, 0, 0], [$d['old']['original'], $d['old']['paid'], $d['old']['left']]);
        $this->assertSame([], $d['old']['entries']);
        $this->assertEquals([40000, 0, 40000], [$d['total']['owed'], $d['total']['paid'], $d['total']['left']]);
    }

    public function test_the_credit_check_the_statement_and_the_customer_list_read_the_same_figures(): void
    {
        $this->theStory();

        $check = $this->api('GET', "/api/inventory/credit/customers/{$this->customer}/check?amount=10000")->assertOk()->json('data');
        $this->assertEquals(280000, $check['balance'], 'a cancelled sale is not owed');
        $this->assertEquals(290000, $check['projected_balance']);
        $this->assertEquals(280000, $check['debt']['total']['left']);

        $statement = $this->api('GET', "/api/inventory/credit/customers/{$this->customer}/statement")->assertOk()->json('data');
        $this->assertEquals(280000, $statement['debt']['total']['left']);

        $row = collect($this->api('GET', '/api/inventory/credit/customers')->json('data'))->firstWhere('id', $this->customer);
        $this->assertEquals(280000, (float) $row['balance']);
        $this->assertEquals(250000, (float) $row['old_balance']);
    }

    public function test_money_received_goes_where_it_is_told_old_and_new_apart(): void
    {
        $ids = $this->theStory();

        $r = $this->receive([
            'amount' => 110000,
            'old_allocations' => [['debt_id' => $ids['old'], 'amount' => 100000]],
            'allocations' => [['sale_id' => $ids['a'], 'amount' => 10000]],
        ])->assertCreated()->json('data');

        $this->assertEquals([100000, 10000, 0], [$r['old_allocated'], $r['new_allocated'], $r['unallocated']]);
        $d = $r['debt'];
        $this->assertEquals([200000, 150000], [$d['old']['paid'], $d['old']['left']]);
        $this->assertEquals([60000, 20000], [$d['new']['paid'], $d['new']['left']]);
        $this->assertEquals([260000, 170000], [$d['total']['paid'], $d['total']['left']], 'all paid so far, and all that is left');
        $this->assertCount(2, $this->api('GET', "/api/inventory/opening-debts/{$ids['old']}/payments")->json('data'), 'the old debt keeps its own payment history');
    }

    public function test_money_received_with_no_instruction_pays_the_old_debt_first_then_the_credit_sales(): void
    {
        $ids = $this->theStory();

        $r = $this->receive(['amount' => 300000])->assertCreated()->json('data');

        $this->assertEquals([250000, 30000, 20000], [$r['old_allocated'], $r['new_allocated'], $r['unallocated']], 'the old debt (250,000), then sale A (30,000), 20,000 left over');
        $this->assertEquals(0, $r['debt']['total']['left']);
        $this->assertSame('paid', $this->rows(fn () => DB::table('inventory_sales')->where('id', $ids['a'])->value('payment_status')));
    }

    public function test_a_payment_never_pays_more_than_is_left_and_never_another_customers_debt(): void
    {
        $ids = $this->theStory();
        $other = $this->api('POST', '/api/inventory/customers', ['name' => 'Baba Juma', 'phone' => '0711000888'])->assertCreated()->json('data.id');
        $othersDebt = $this->oldDebt(70000, $other);
        $othersSale = $this->creditSale(20000, $other)->json('data.id');

        $this->receive(['amount' => 1, 'old_allocations' => [['debt_id' => $othersDebt, 'amount' => 1]]])->assertStatus(422);
        $this->receive(['amount' => 1, 'allocations' => [['sale_id' => $othersSale, 'amount' => 1]]])->assertStatus(422);
        $this->assertEquals(70000, $this->debt($other)['old']['left'], 'nothing moved');

        // asking to pay more than is left pays what is left
        $r = $this->receive(['amount' => 999999, 'old_allocations' => [['debt_id' => $ids['old'], 'amount' => 999999]]])->assertCreated()->json('data');
        $this->assertEquals(250000, $r['old_allocated']);
    }

    public function test_the_sale_answers_with_what_the_customer_owes_now_so_the_receipt_can_say_it(): void
    {
        $this->oldDebt(350000);

        $sale = $this->creditSale(50000)->json('data');

        $d = $sale['customer_debt'];
        $this->assertEquals(350000, $d['old']['left']);
        $this->assertEquals(50000, $d['new']['left'], 'this sale is the new debt');
        $this->assertEquals(400000, $d['total']['left']);
    }

    public function test_a_sale_to_nobody_has_no_account_to_show(): void
    {
        $r = $this->api('POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 1000, 'discount' => 0, 'tax' => 0, 'total' => 1000, 'paid_total' => 1000,
            'items' => [['product_id' => $this->rice, 'quantity' => 1, 'unit_price' => 1000, 'unit_cost_snapshot' => 600]],
        ])->assertCreated();

        $this->assertNull($r->json('data.customer_debt'));
    }

    public function test_a_cancelled_credit_sale_is_no_longer_counted_as_owed_anywhere(): void
    {
        $sale = $this->creditSale(80000)->json('data.id');
        $this->assertEquals(80000, (float) collect($this->api('GET', '/api/inventory/credit/customers')->json('data'))->firstWhere('id', $this->customer)['balance']);

        $this->api('POST', "/api/inventory/sales/{$sale}/cancel", ['reason' => 'Wrong customer'])->assertOk();

        $this->assertEquals(0, (float) collect($this->api('GET', '/api/inventory/credit/customers')->json('data'))->firstWhere('id', $this->customer)['balance']);
        $this->assertEquals(0, $this->api('GET', "/api/inventory/credit/customers/{$this->customer}/check")->json('data.balance'));
        $this->assertSame([], collect($this->api('GET', '/api/inventory/credit/debtors-ageing')->json('data'))->where('customer_id', $this->customer)->values()->all());
    }

    public function test_an_unknown_customer_is_not_found(): void
    {
        $this->api('GET', '/api/inventory/credit/customers/999999/debt-summary')->assertStatus(404);
    }
}
