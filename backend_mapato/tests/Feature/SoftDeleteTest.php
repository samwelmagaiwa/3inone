<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Soft delete for what the owner and the admins manage from the dashboard: expenses, customers, debts from before the app, products and
 * services. "Delete" moves a record to the Trash (hidden from every list, total and report, history untouched), the owner or an admin can
 * restore it, and removing it for good is a separate, confirmed step that is refused when the record has history to keep.
 */
class SoftDeleteTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private User $owner;
    private User $other;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = $this->business('Alpha Shop');
        $this->other = $this->business('Bravo Shop');
    }

    private function business(string $name): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function staff(User $owner, string $role = 'sales_officer', array $permissions = []): User
    {
        $user = User::factory()->create([
            'name' => 'Staff ' . ++$this->seq, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id,
            'phone_number' => '0727' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]);
        $this->givenServices($user, 'inventory');
        if ($permissions !== []) {
            $user->forceFill(['permissions' => $permissions])->save();
        }

        return $user;
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

    private function product(User $as, string $name = 'Soda', string $sku = 'SODA1', int $qty = 50): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'sku' => $sku, 'quantity' => $qty, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 600, 'selling_price' => 1000])->assertCreated()->json('data.id');
    }

    private function customer(User $as, string $name = 'Neema', string $phone = '0712000111'): int
    {
        return $this->api($as, 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertCreated()->json('data.id');
    }

    private function expense(User $as, int $amount = 5000, string $what = 'Charcoal'): int
    {
        return $this->api($as, 'POST', '/api/inventory/expenses', ['category' => 'transport', 'description' => $what, 'amount' => $amount, 'expense_date' => now()->toDateString(), 'payment_method' => 'cash'])->assertCreated()->json('data.id');
    }

    private function sell(User $as, int $product, ?int $customer, string $status = 'paid', int $qty = 1): int
    {
        $total = $qty * 1000;

        return $this->api($as, 'POST', '/api/inventory/sales', array_filter([
            'customer_id' => $customer, 'payment_status' => $status, 'subtotal' => $total, 'discount' => 0, 'tax' => 0, 'total' => $total,
            'paid_total' => $status === 'paid' ? $total : 0, 'due_date' => $status === 'paid' ? null : now()->addDays(7)->toDateString(),
            'items' => [['product_id' => $product, 'quantity' => $qty, 'unit_price' => 1000, 'unit_cost_snapshot' => 600]],
        ], fn ($v) => $v !== null))->assertCreated()->json('data.id');
    }

    private function trash(User $as, string $type): array
    {
        return $this->api($as, 'GET', "/api/inventory/trash?type={$type}")->assertOk()->json();
    }

    private function expenseIds(User $as): array
    {
        return array_column($this->api($as, 'GET', '/api/inventory/expenses?period=all')->assertOk()->json('data'), 'id');
    }

    // ------------------------------------------------------------------ expenses

    public function test_a_deleted_expense_leaves_the_list_and_the_totals_and_comes_back_when_restored(): void
    {
        $keep = $this->expense($this->owner, 4000, 'Rent');
        $gone = $this->expense($this->owner, 6000, 'Charcoal');
        $this->assertEqualsCanonicalizing([$keep, $gone], $this->expenseIds($this->owner));
        $total = fn () => (float) $this->api($this->owner, 'GET', '/api/inventory/expenses/summary?period=all')->assertOk()->json('data.total_expenses');
        $this->assertSame(10000.0, $total());

        $this->api($this->owner, 'DELETE', "/api/inventory/expenses/{$gone}", ['reason' => 'entered twice'])->assertOk();

        $this->assertSame([$keep], $this->expenseIds($this->owner));
        $this->assertSame(4000.0, $total(), 'the dashboard and the reports stop counting it');
        $trash = $this->trash($this->owner, 'expenses');
        $this->assertSame($gone, $trash['data'][0]['id']);
        $this->assertSame('Charcoal', $trash['data'][0]['title']);
        $this->assertSame('entered twice', $trash['data'][0]['reason']);
        $this->assertSame(1, $trash['counts']['expenses']);
        $this->assertSame(0, $trash['counts']['customers']);

        $this->api($this->owner, 'POST', "/api/inventory/trash/expenses/{$gone}/restore")->assertOk();

        $this->assertEqualsCanonicalizing([$keep, $gone], $this->expenseIds($this->owner));
        $this->assertSame(10000.0, $total());
        $this->assertSame([], $this->trash($this->owner, 'expenses')['data']);
        $this->rows($this->owner, fn () => $this->assertDatabaseHas('inventory_audit_log', ['entity_type' => 'expense', 'entity_id' => $gone, 'action' => 'trashed']));
        $this->rows($this->owner, fn () => $this->assertDatabaseHas('inventory_audit_log', ['entity_type' => 'expense', 'entity_id' => $gone, 'action' => 'restored']));
    }

    public function test_a_trashed_expense_cannot_be_edited_until_it_is_restored(): void
    {
        $id = $this->expense($this->owner);
        $this->api($this->owner, 'DELETE', "/api/inventory/expenses/{$id}")->assertOk();

        $this->api($this->owner, 'PUT', "/api/inventory/expenses/{$id}", ['category' => 'rent', 'description' => 'Changed', 'amount' => 1, 'expense_date' => now()->toDateString()])->assertNotFound();

        $this->api($this->owner, 'POST', "/api/inventory/trash/expenses/{$id}/restore")->assertOk();
        $this->api($this->owner, 'PUT', "/api/inventory/expenses/{$id}", ['category' => 'rent', 'description' => 'Changed', 'amount' => 7000, 'expense_date' => now()->toDateString()])->assertOk();
        $this->assertSame('Changed', collect($this->api($this->owner, 'GET', '/api/inventory/expenses?period=all')->json('data'))->firstWhere('id', $id)['description']);
    }

    // ------------------------------------------------------------------ products and services

    public function test_a_deleted_product_leaves_the_lists_but_its_sales_keep_its_name(): void
    {
        $soda = $this->product($this->owner);
        $other = $this->product($this->owner, 'Water', 'WAT1');
        $sale = $this->sell($this->owner, $soda, null);

        $this->api($this->owner, 'DELETE', "/api/inventory/products/{$soda}")->assertOk();

        $names = array_column($this->api($this->owner, 'GET', '/api/inventory/products')->assertOk()->json('data'), 'name');
        $this->assertSame(['Water'], $names);
        $this->assertNotContains($soda, array_column($this->api($this->owner, 'GET', '/api/inventory/products')->json('data'), 'id'));
        $line = $this->api($this->owner, 'GET', "/api/inventory/sales/{$sale}")->assertOk()->json('data.items.0');
        $this->assertSame('Soda', $line['product_name'], 'the old sale still says what was sold');
        $this->assertSame('Soda', $this->trash($this->owner, 'products')['data'][0]['title']);
        $this->assertSame($other, $this->api($this->owner, 'GET', '/api/inventory/products')->json('data.0.id'));
    }

    public function test_a_trashed_product_cannot_be_sold_and_its_sku_can_be_used_again(): void
    {
        $soda = $this->product($this->owner, 'Soda', 'SODA1');
        $this->api($this->owner, 'DELETE', "/api/inventory/products/{$soda}")->assertOk();

        $this->api($this->owner, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 1000, 'discount' => 0, 'tax' => 0, 'total' => 1000, 'paid_total' => 1000,
            'items' => [['product_id' => $soda, 'quantity' => 1, 'unit_price' => 1000, 'unit_cost_snapshot' => 600]],
        ])->assertStatus(422);

        $fresh = $this->product($this->owner, 'New Soda', 'SODA1'); // the same SKU, no clash
        $this->assertNotSame($soda, $fresh);
    }

    public function test_restoring_a_product_whose_sku_was_taken_asks_for_a_new_one(): void
    {
        $soda = $this->product($this->owner, 'Soda', 'SODA1');
        $this->api($this->owner, 'DELETE', "/api/inventory/products/{$soda}")->assertOk();
        $this->product($this->owner, 'New Soda', 'SODA1');

        $this->api($this->owner, 'POST', "/api/inventory/trash/products/{$soda}/restore")->assertStatus(422);
        $this->assertCount(1, $this->trash($this->owner, 'products')['data'], 'still in the Trash');

        $this->api($this->owner, 'POST', "/api/inventory/trash/products/{$soda}/restore", ['sku' => 'SODA-OLD'])->assertOk();
        $skus = array_column($this->api($this->owner, 'GET', '/api/inventory/products')->json('data'), 'sku');
        $this->assertEqualsCanonicalizing(['SODA1', 'SODA-OLD'], $skus);
    }

    public function test_a_product_comes_back_with_its_own_sku_when_nothing_clashes(): void
    {
        $soda = $this->product($this->owner, 'Soda', 'SODA1');
        $this->api($this->owner, 'DELETE', "/api/inventory/products/{$soda}")->assertOk();

        $this->api($this->owner, 'POST', "/api/inventory/trash/products/{$soda}/restore")->assertOk();

        $back = collect($this->api($this->owner, 'GET', '/api/inventory/products')->assertOk()->json('data'))->firstWhere('id', $soda);
        $this->assertSame('SODA1', $back['sku']);
    }

    // ------------------------------------------------------------------ customers

    public function test_a_customer_who_owes_cannot_be_deleted_and_one_who_does_not_keeps_their_sales(): void
    {
        $soda = $this->product($this->owner);
        $owes = $this->customer($this->owner, 'Owes Money', '0712000222');
        $clear = $this->customer($this->owner, 'All Paid', '0712000333');
        $this->sell($this->owner, $soda, $owes, 'debt');
        $paidSale = $this->sell($this->owner, $soda, $clear, 'paid');

        $this->api($this->owner, 'DELETE', "/api/inventory/customers/{$owes}")->assertStatus(422)->assertJsonPath('owing', 1000);
        $this->api($this->owner, 'DELETE', "/api/inventory/customers/{$owes}?force=1")->assertStatus(422);

        $this->api($this->owner, 'DELETE', "/api/inventory/customers/{$clear}")->assertOk();
        $names = array_column($this->api($this->owner, 'GET', '/api/inventory/customers')->assertOk()->json('data'), 'name');
        $this->assertNotContains('All Paid', $names);
        $this->assertContains('Owes Money', $names);
        $sale = $this->api($this->owner, 'GET', "/api/inventory/sales/{$paidSale}")->assertOk()->json('data');
        $this->assertSame('All Paid', $sale['customer_name'], 'the old sale still names them');
        $this->assertSame($clear, (int) $sale['customer_id'], 'and still points at them');

        $this->api($this->owner, 'POST', "/api/inventory/trash/customers/{$clear}/restore")->assertOk();
        $this->assertContains('All Paid', array_column($this->api($this->owner, 'GET', '/api/inventory/customers')->json('data'), 'name'));
    }

    // ------------------------------------------------------------------ debts from before the app

    public function test_an_old_debt_can_be_corrected_deleted_and_restored(): void
    {
        $id = $this->api($this->owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'name' => 'Mama Anna', 'amount' => 50000])->assertCreated()->json('data.id');
        $total = fn () => (float) $this->api($this->owner, 'GET', '/api/inventory/opening-debts?kind=receivable')->assertOk()->json('data.total');
        $this->assertSame(50000.0, $total());

        $this->api($this->owner, 'PUT', "/api/inventory/opening-debts/{$id}", ['name' => 'Mama Anna K.', 'amount' => 60000, 'note' => 'corrected'])->assertOk();
        $this->assertSame(60000.0, $total());

        $this->api($this->owner, 'DELETE', "/api/inventory/opening-debts/{$id}", ['reason' => 'not owed after all'])->assertOk();
        $this->assertSame(0.0, $total());
        $this->assertSame('Mama Anna K.', $this->trash($this->owner, 'debts')['data'][0]['title']);

        $this->api($this->owner, 'POST', "/api/inventory/trash/debts/{$id}/restore")->assertOk();
        $this->assertSame(60000.0, $total());
    }

    public function test_a_debt_cannot_be_corrected_below_what_was_paid_and_one_with_payments_cannot_be_deleted(): void
    {
        $id = $this->api($this->owner, 'POST', '/api/inventory/opening-debts', ['kind' => 'receivable', 'name' => 'Baba John', 'amount' => 50000])->assertCreated()->json('data.id');
        $this->api($this->owner, 'POST', "/api/inventory/opening-debts/{$id}/payments", ['amount' => 20000])->assertOk();

        $this->api($this->owner, 'PUT', "/api/inventory/opening-debts/{$id}", ['amount' => 10000])->assertStatus(422);
        $this->api($this->owner, 'PUT', "/api/inventory/opening-debts/{$id}", ['amount' => 30000])->assertOk();
        $this->api($this->owner, 'DELETE', "/api/inventory/opening-debts/{$id}")->assertStatus(422);
    }

    // ------------------------------------------------------------------ sales

    public function test_a_sale_can_be_corrected_for_who_and_when_but_never_its_goods_or_amounts(): void
    {
        $soda = $this->product($this->owner);
        $neema = $this->customer($this->owner, 'Neema', '0712000444');
        $juma = $this->customer($this->owner, 'Juma', '0712000555');
        $sale = $this->sell($this->owner, $soda, $neema, 'debt');

        $r = $this->api($this->owner, 'PUT', "/api/inventory/sales/{$sale}", ['customer_id' => $juma, 'due_date' => '2026-12-24', 'total' => 1, 'items' => []])->assertOk()->json('data');

        $this->assertSame($juma, (int) $r['customer_id']);
        $this->assertSame('Juma', $r['customer_name']);
        $this->assertStringStartsWith('2026-12-24', (string) $r['due_date']);
        $this->assertSame(1000, (int) $r['total'], 'the amount did not move');
        $this->assertCount(1, $r['items'], 'nor the goods');

        $this->api($this->owner, 'PUT', "/api/inventory/sales/{$sale}", ['customer_id' => null])->assertStatus(422); // a sale paid later needs a customer
    }

    public function test_a_cancelled_sale_is_listed_for_the_record_and_can_neither_be_changed_nor_restored(): void
    {
        $soda = $this->product($this->owner);
        $sale = $this->sell($this->owner, $soda, null);
        $this->api($this->owner, 'POST', "/api/inventory/sales/{$sale}/cancel", ['reason' => 'Wrong goods'])->assertOk();

        $list = $this->trash($this->owner, 'sales');
        $this->assertSame($sale, $list['data'][0]['id']);
        $this->assertSame('Wrong goods', $list['data'][0]['reason']);
        $this->assertFalse($list['data'][0]['can_restore']);
        $this->assertSame(1, $list['counts']['sales']);

        $this->api($this->owner, 'POST', "/api/inventory/trash/sales/{$sale}/restore")->assertStatus(422);
        $this->api($this->owner, 'DELETE', "/api/inventory/trash/sales/{$sale}", ['confirm' => 'DELETE'])->assertStatus(422);
        $this->api($this->owner, 'PUT', "/api/inventory/sales/{$sale}", ['due_date' => '2026-12-24'])->assertStatus(422);
    }

    // ------------------------------------------------------------------ who may

    public function test_only_the_owner_and_admins_may_use_the_trash(): void
    {
        $id = $this->expense($this->owner);
        $this->api($this->owner, 'DELETE', "/api/inventory/expenses/{$id}")->assertOk();
        $seller = $this->staff($this->owner, 'sales_officer', ['inv_create_sales', 'inv_view_expenses', 'inv_manage_expenses', 'inv_manage_settings']);
        $manager = $this->staff($this->owner, 'manager', ['inv_manage_settings']);
        $fullAccess = $this->staff($this->owner, 'manager');
        $fullAccess->forceFill(['full_access' => true])->save();

        foreach ([$seller, $manager] as $who) {
            $this->api($who, 'GET', '/api/inventory/trash?type=expenses')->assertForbidden();
            $this->api($who, 'POST', "/api/inventory/trash/expenses/{$id}/restore")->assertForbidden();
            $this->api($who, 'DELETE', "/api/inventory/trash/expenses/{$id}", ['confirm' => 'DELETE'])->assertForbidden();
        }
        $this->assertCount(1, $this->trash($fullAccess, 'expenses')['data'], 'someone the owner gave full access does');
        $this->assertCount(1, $this->trash($this->owner, 'expenses')['data'], 'and the owner');
        $this->api($fullAccess, 'POST', "/api/inventory/trash/expenses/{$id}/restore")->assertOk();
    }

    public function test_another_business_never_sees_or_restores_these_records(): void
    {
        $id = $this->expense($this->owner);
        $this->api($this->owner, 'DELETE', "/api/inventory/expenses/{$id}")->assertOk();

        $this->assertSame([], $this->trash($this->other, 'expenses')['data']);
        $this->assertSame(0, $this->trash($this->other, 'expenses')['counts']['expenses']);
        $this->api($this->other, 'POST', "/api/inventory/trash/expenses/{$id}/restore")->assertNotFound();
        $this->api($this->other, 'DELETE', "/api/inventory/trash/expenses/{$id}", ['confirm' => 'DELETE'])->assertNotFound();
        $this->assertCount(1, $this->trash($this->owner, 'expenses')['data'], 'it is still in the right Trash');
    }

    // ------------------------------------------------------------------ for good

    public function test_removing_for_good_asks_for_a_confirmation_and_only_works_on_the_trashed(): void
    {
        $id = $this->expense($this->owner);

        $this->api($this->owner, 'DELETE', "/api/inventory/trash/expenses/{$id}", ['confirm' => 'DELETE'])->assertNotFound(); // not in the Trash

        $this->api($this->owner, 'DELETE', "/api/inventory/expenses/{$id}")->assertOk();
        $this->api($this->owner, 'DELETE', "/api/inventory/trash/expenses/{$id}")->assertStatus(422); // no confirmation
        $this->api($this->owner, 'DELETE', "/api/inventory/trash/expenses/{$id}", ['confirm' => 'yes'])->assertStatus(422);
        $this->assertCount(1, $this->trash($this->owner, 'expenses')['data']);

        $this->api($this->owner, 'DELETE', "/api/inventory/trash/expenses/{$id}", ['confirm' => 'DELETE'])->assertOk();
        $this->assertSame([], $this->trash($this->owner, 'expenses')['data']);
        $this->rows($this->owner, fn () => $this->assertDatabaseMissing('inventory_expenses', ['id' => $id]));
    }

    public function test_what_has_history_stays_in_the_trash_and_what_has_none_can_go(): void
    {
        $sold = $this->product($this->owner, 'Sold Soda', 'SOLD1');
        $unsold = $this->product($this->owner, 'Fresh Soda', 'FRESH1', 0);
        $this->sell($this->owner, $sold, null);
        $buyer = $this->customer($this->owner, 'Buyer', '0712000666');
        $this->sell($this->owner, $sold, $buyer);
        foreach ([$sold, $unsold] as $p) {
            $this->api($this->owner, 'DELETE', "/api/inventory/products/{$p}")->assertOk();
        }
        $this->api($this->owner, 'DELETE', "/api/inventory/customers/{$buyer}")->assertOk();

        $this->api($this->owner, 'DELETE', "/api/inventory/trash/products/{$sold}", ['confirm' => 'DELETE'])->assertStatus(422);
        $this->api($this->owner, 'DELETE', "/api/inventory/trash/customers/{$buyer}", ['confirm' => 'DELETE'])->assertStatus(422);
        $this->api($this->owner, 'DELETE', "/api/inventory/trash/products/{$unsold}", ['confirm' => 'DELETE'])->assertOk();

        $titles = array_column($this->trash($this->owner, 'products')['data'], 'title');
        $this->assertSame(['Sold Soda'], $titles);
        $this->assertCount(1, $this->trash($this->owner, 'customers')['data']);
    }

    // ------------------------------------------------------------------ the one rule behind it all

    public function test_every_query_on_these_tables_skips_the_trash_but_a_join_still_shows_the_name(): void
    {
        $id = $this->expense($this->owner, 4000, 'Gone');
        $this->expense($this->owner, 6000, 'Kept');
        $customer = $this->customer($this->owner, 'Old Friend', '0712000777');
        $soda = $this->product($this->owner);
        $sale = $this->sell($this->owner, $soda, $customer);
        $this->api($this->owner, 'DELETE', "/api/inventory/expenses/{$id}")->assertOk();
        $this->api($this->owner, 'DELETE', "/api/inventory/customers/{$customer}")->assertOk();

        $this->rows($this->owner, function () use ($sale, $customer) {
            $this->assertSame(1, DB::table('inventory_expenses')->count());
            $this->assertSame(6000.0, (float) DB::table('inventory_expenses')->sum('amount'));
            $this->assertSame(0, DB::table('inventory_customers')->where('id', $customer)->count());
            $name = DB::table('inventory_sales as s')->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')->where('s.id', $sale)->value('c.name');
            $this->assertSame('Old Friend', $name, 'a join keeps the history readable');
            TenantContext::withTrashed(function () use ($customer) {
                $this->assertSame(1, DB::table('inventory_customers')->where('id', $customer)->count(), 'only the Trash itself sees it');
            });
        });
    }
}
