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
 * The same person must not become two customers (different capitals, spaces or way of writing the number), and two records that already
 * are one person can be merged: their sales, payments and old debts then add up on one customer account.
 */
class CustomerMergeTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;
    private int $rice;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::parse('2026-11-18 10:00:00', 'Africa/Dar_es_Salaam')->utc());
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726000001']), 'inventory');
        Business::forOwnerId($this->owner->id)->update(['name' => 'Mama Shop']);
        $this->rice = $this->api('POST', '/api/inventory/products', ['name' => 'Rice', 'sku' => 'RICE1', 'quantity' => 1000, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 600, 'selling_price' => 1000])->assertCreated()->json('data.id');
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

    private function customer(string $name, string $phone): int
    {
        return $this->api('POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertStatus(201)->json('data.id');
    }

    private function creditSale(int $customer, int $total, int $paid = 0): int
    {
        return $this->api('POST', '/api/inventory/sales', [
            'customer_id' => $customer, 'payment_status' => $paid > 0 ? 'partial' : 'debt', 'subtotal' => $total, 'discount' => 0, 'tax' => 0, 'total' => $total, 'paid_total' => $paid,
            'due_date' => now()->addDays(7)->toDateString(),
            'items' => [['product_id' => $this->rice, 'quantity' => (int) ($total / 1000), 'unit_price' => 1000, 'unit_cost_snapshot' => 600]],
        ])->assertCreated()->json('data.id');
    }

    private function oldDebt(int $customer, int $amount): int
    {
        return $this->api('POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'customer_id' => $customer, 'amount' => $amount, 'started_on' => '2026-06-01'])->assertCreated()->json('data.id');
    }

    /** A second record for the same person, made the way old data got in (straight into the table). */
    private function legacyDuplicate(string $name, string $phone): int
    {
        return $this->rows(fn () => (int) DB::table('inventory_customers')->insertGetId(['name' => $name, 'phone' => $phone, 'created_at' => now(), 'updated_at' => now()]));
    }

    public function test_the_same_person_written_another_way_is_not_saved_twice(): void
    {
        $first = $this->customer('Mama Chale', '0711000777');

        // other capitals and spaces, another way of writing the same number
        $again = $this->api('POST', '/api/inventory/customers', ['name' => '  mama   CHALE ', 'phone' => '+255711000777'])->assertOk();
        $this->assertTrue($again->json('data.existing'));
        $this->assertSame($first, $again->json('data.id'));

        $this->assertSame(1, $this->rows(fn () => DB::table('inventory_customers')->count()));
    }

    public function test_the_same_name_is_the_same_customer_even_with_another_number(): void
    {
        $a = $this->customer('Mama Chale', '0711000777');

        $again = $this->api('POST', '/api/inventory/customers', ['name' => 'mama chale', 'phone' => '0722000888'])->assertOk();

        $this->assertTrue($again->json('data.existing'));
        $this->assertSame('name', $again->json('data.matched_by'));
        $this->assertSame($a, $again->json('data.id'));
        $this->assertSame('Mama Chale', $again->json('data.name'), 'says who is already there');
        $this->assertStringContainsString('tayari yupo', $again->json('message'));
        $this->assertSame(1, $this->rows(fn () => DB::table('inventory_customers')->count()));
        $this->assertSame('0711000777', $this->rows(fn () => DB::table('inventory_customers')->where('id', $a)->value('phone')), 'the saved number is not overwritten');
    }

    public function test_the_same_number_is_the_same_customer_even_with_another_name(): void
    {
        $a = $this->customer('Baba Juma', '0733000999');

        $again = $this->api('POST', '/api/inventory/customers', ['name' => 'Juma Senior', 'phone' => '733000999'])->assertOk();

        $this->assertTrue($again->json('data.existing'));
        $this->assertSame('phone', $again->json('data.matched_by'));
        $this->assertSame($a, $again->json('data.id'));
        $this->assertSame(1, $this->rows(fn () => DB::table('inventory_customers')->count()));
    }

    public function test_a_sale_typed_with_a_known_name_goes_to_the_customer_who_is_there(): void
    {
        $a = $this->customer('Mama Chale', '0711000777');

        $sale = $this->api('POST', '/api/inventory/sales', [
            'customer_name_override' => 'mama chale', 'customer_phone' => '', 'payment_status' => 'paid', 'subtotal' => 1000, 'discount' => 0, 'tax' => 0, 'total' => 1000, 'paid_total' => 1000,
            'items' => [['product_id' => $this->rice, 'quantity' => 1, 'unit_price' => 1000, 'unit_cost_snapshot' => 600]],
        ])->assertCreated();

        $this->assertSame(1, $this->rows(fn () => DB::table('inventory_customers')->count()));
        $this->assertSame($a, $this->rows(fn () => (int) DB::table('inventory_sales')->where('id', $sale->json('data.id'))->value('customer_id')));
    }

    public function test_a_customer_cannot_be_edited_into_another_ones_name_or_number(): void
    {
        $a = $this->customer('Mama Chale', '0711000777');
        $b = $this->customer('Baba Juma', '0733000999');

        $this->api('PUT', "/api/inventory/customers/{$b}", ['name' => 'MAMA CHALE'])->assertStatus(422)->assertJsonPath('errors.name.0', 'Mteja huyu tayari yupo. / This customer already exists.');
        $this->api('PUT', "/api/inventory/customers/{$b}", ['phone' => '+255711000777'])->assertStatus(422);
        $this->api('PUT', "/api/inventory/customers/{$b}", ['name' => 'Baba Juma Jr', 'phone' => '0744000111'])->assertOk();
        $this->api('PUT', "/api/inventory/customers/{$a}", ['name' => 'mama chale', 'phone' => '0711000777'])->assertOk();   // itself is fine
    }

    public function test_an_old_debt_typed_with_just_the_name_goes_to_the_customer_already_saved(): void
    {
        $saved = $this->customer('Mama Chale', '0711000777');

        $debt = $this->api('POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'name' => 'mama chale', 'amount' => 430000, 'started_on' => '2026-06-01'])->assertCreated();

        $this->assertSame(1, $this->rows(fn () => DB::table('inventory_customers')->count()), 'no second Mama Chale');
        $this->assertSame($saved, $this->rows(fn () => (int) DB::table('inventory_opening_debts')->where('id', $debt->json('data.id'))->value('customer_id')));
    }

    public function test_a_customer_saved_without_a_number_takes_the_number_when_it_is_typed_later(): void
    {
        $first = $this->api('POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'name' => 'Mama Chale', 'amount' => 1000, 'started_on' => '2026-06-01'])->assertCreated();
        $id = $this->rows(fn () => (int) DB::table('inventory_opening_debts')->where('id', $first->json('data.id'))->value('customer_id'));

        $again = $this->api('POST', '/api/inventory/customers', ['name' => 'mama chale', 'phone' => '0711000777'])->assertOk();

        $this->assertSame($id, $again->json('data.id'));
        $this->assertSame('0711000777', $this->rows(fn () => DB::table('inventory_customers')->where('id', $id)->value('phone')));
    }

    public function test_duplicates_are_found_by_name_or_by_number(): void
    {
        $a = $this->customer('Mama Chale', '0711000777');
        $b = $this->legacyDuplicate('mama chale', '0722000888');   // same name, another number
        $c = $this->customer('Baba Juma', '0733000999');
        $d = $this->legacyDuplicate('Juma Senior', '0733000999');   // another name, the same number as Baba Juma
        $e = $this->customer('Asha', '0744000111');           // alone
        $this->creditSale($a, 210000);

        $groups = $this->api('GET', '/api/inventory/customers/duplicates')->assertOk()->json('data');

        $this->assertCount(2, $groups);
        $ids = array_map(fn ($g) => collect($g['customers'])->pluck('id')->sort()->values()->all(), $groups);
        $this->assertContains([$a, $b], $ids);
        $this->assertContains([$c, $d], $ids);
        $this->assertNotContains($e, collect($ids)->flatten()->all());
        $withSales = collect($groups)->flatMap(fn ($g) => $g['customers'])->firstWhere('id', $a);
        $this->assertSame(1, $withSales['sales']);
        $this->assertEquals(210000, $withSales['owes']);
    }

    public function test_merging_puts_both_customers_debts_payments_and_old_debts_on_one_account(): void
    {
        $keep = $this->customer('Mama Chale', '0711000777');
        $drop = $this->legacyDuplicate('mama chale', '0722000888');
        $oldDebt = $this->oldDebt($drop, 430000);
        $this->api('POST', "/api/inventory/opening-debts/{$oldDebt}/payments", ['amount' => 30000, 'method' => 'cash'])->assertOk();
        $this->creditSale($keep, 210000);
        $sale = $this->creditSale($drop, 50000);

        $this->api('POST', "/api/inventory/customers/{$drop}/merge", ['into_id' => $keep])->assertOk()->assertJsonPath('data.kept', $keep);

        // one account with everything
        $debt = $this->api('GET', "/api/inventory/credit/customers/{$keep}/debt-summary")->assertOk()->json('data.debt');
        $this->assertEquals(400000, $debt['old']['left'], 'the old debt, 430,000 less the 30,000 paid');
        $this->assertEquals(260000, $debt['new']['left'], 'both credit sales: 210,000 + 50,000');
        $this->assertEquals(660000, $debt['total']['left']);
        $this->assertEquals(30000, $debt['total']['paid']);
        $account = $this->api('GET', "/api/inventory/credit/customers/{$keep}/account")->assertOk()->json('data');
        $this->assertCount(2, $account['credit_sales']);
        $this->assertCount(1, $account['old_debts']);
        $this->assertSame(2, $account['lifetime']['purchases']);

        // the sale now belongs to the kept customer; the other record is in the Trash and out of every list
        $this->assertSame($keep, $this->rows(fn () => (int) DB::table('inventory_sales')->where('id', $sale)->value('customer_id')));
        $this->assertSame(1, $this->rows(fn () => DB::table('inventory_customers')->count()));
        $this->assertSame(0, count($this->api('GET', '/api/inventory/customers/duplicates')->json('data')));
    }

    public function test_a_customer_cannot_be_merged_into_itself_or_into_nobody_or_into_another_business(): void
    {
        $a = $this->customer('Mama Chale', '0711000777');
        $this->api('POST', "/api/inventory/customers/{$a}/merge", ['into_id' => $a])->assertStatus(422);
        $this->api('POST', "/api/inventory/customers/{$a}/merge", ['into_id' => 999999])->assertStatus(404);
        $this->api('POST', "/api/inventory/customers/{$a}/merge", [])->assertStatus(422);

        $other = $this->givenServices(User::factory()->create(['name' => 'Other', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726000002']), 'inventory');
        $token = $other->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json('POST', "/api/inventory/customers/{$a}/merge", ['into_id' => $a + 1])->assertStatus(404);
    }
}
