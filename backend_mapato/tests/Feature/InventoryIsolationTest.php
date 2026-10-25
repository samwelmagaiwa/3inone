<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Inventory\InventoryOwnership;
use App\Services\Inventory\StockLedger;
use App\Support\InventoryDefaults;
use App\Support\Tenancy\TenantContext;
use App\Support\Tenancy\TenantTables;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use LogicException;
use Tests\TestCase;

/**
 * Two businesses share one inventory database and must never see, change or even
 * detect each other's stock, sales, customers, prices or settings.
 *
 * The generic mechanism (the tenant query grammar) is proven statement by statement in
 * Tests\Unit\TenantQueryScopeTest; this file proves it end to end through the real API,
 * with real middleware, validation and controllers, for the "Alpha" business and the
 * "Bravo" business. Every Alpha record carries "Alpha" in its text, so a leak shows up
 * as that word turning up anywhere in a Bravo response.
 */
class InventoryIsolationTest extends TestCase
{
    use RefreshDatabase;

    private User $alpha;

    private User $bravo;

    private User $alphaStaff;

    private User $bravoStaff;

    /** @var array<string, array<string, int>> business label => table => id */
    private array $ids = [];

    protected function setUp(): void
    {
        parent::setUp();

        $this->alpha = $this->business('Alpha');
        $this->bravo = $this->business('Bravo');
        $this->alphaStaff = $this->staff($this->alpha, 'sales_officer', 'alpha.officer@example.test');
        $this->bravoStaff = $this->staff($this->bravo, 'sales_officer', 'bravo.officer@example.test');

        $this->ids['Alpha'] = $this->seedBusiness($this->alpha, 'Alpha');
        $this->ids['Bravo'] = $this->seedBusiness($this->bravo, 'Bravo');
    }

    // ------------------------------------------------------------ fixtures

    private function business(string $label): User
    {
        return $this->givenServices(User::factory()->create([
            'name' => "{$label} Owner", 'role' => 'admin', 'is_active' => true,
        ]), 'inventory');
    }

    private function staff(User $owner, string $role, string $email): User
    {
        return $this->givenServices(User::factory()->create([
            'role' => $role, 'is_active' => true, 'email' => $email, 'created_by' => $owner->id,
        ]), 'inventory');
    }

    /** One of everything a depot has, owned by $owner and named after $label. @return array<string, int> */
    private function seedBusiness(User $owner, string $label): array
    {
        return TenantContext::runAs($owner, function () use ($owner, $label) {
            $now = now();
            $ids = [];

            $ids['category'] = DB::table('inventory_categories')->insertGetId([
                'name' => "{$label} Drinks", 'status' => 'active', 'created_at' => $now, 'updated_at' => $now,
            ]);
            $ids['brand'] = DB::table('inventory_brands')->insertGetId([
                'name' => "{$label} Brand", 'status' => 'active', 'created_at' => $now, 'updated_at' => $now,
            ]);
            $ids['product'] = DB::table('inventory_products')->insertGetId([
                'name' => "{$label} Soda", 'sku' => "{$label}-SODA", 'cost_price' => 500, 'selling_price' => 800,
                'unit' => 'bottle', 'quantity' => 0, 'min_stock' => 5, 'status' => 'active',
                'created_by' => $owner->id, 'created_at' => $now, 'updated_at' => $now,
            ]);
            $ids['customer'] = DB::table('inventory_customers')->insertGetId([
                'name' => "{$label} Duka", 'phone' => $label === 'Alpha' ? '0711000001' : '0711000002',
                'credit_limit' => 500000, 'created_at' => $now, 'updated_at' => $now,
            ]);
            $ids['supplier'] = DB::table('inventory_suppliers')->insertGetId([
                'name' => "{$label} Wholesaler", 'status' => 'active', 'created_at' => $now, 'updated_at' => $now,
            ]);
            $ids['expense'] = DB::table('inventory_expenses')->insertGetId([
                'category' => 'rent', 'description' => "{$label} rent", 'amount' => 1000,
                'expense_date' => $now->toDateString(), 'created_by' => $owner->id,
                'created_at' => $now, 'updated_at' => $now,
            ]);
            $ids['sale'] = DB::table('inventory_sales')->insertGetId([
                'number' => "{$label}-S-1", 'customer_id' => $ids['customer'], 'payment_status' => 'debt',
                'subtotal' => 8000, 'total' => 8000, 'paid_total' => 0, 'due_date' => $now->copy()->addDays(7)->toDateString(),
                'created_by' => $owner->id, 'created_at' => $now, 'updated_at' => $now,
            ]);
            DB::table('inventory_sale_items')->insert([
                'sale_id' => $ids['sale'], 'product_id' => $ids['product'], 'quantity' => 10, 'unit_price' => 800,
                'unit_cost_snapshot' => 500, 'total' => 8000, 'created_at' => $now, 'updated_at' => $now,
            ]);
            $ids['reminder'] = DB::table('inventory_reminders')->insertGetId([
                'type' => 'payment_due', 'related_id' => $ids['sale'], 'title' => "{$label} payment due",
                'description' => "{$label} owes money", 'due_at' => $now->copy()->addDays(7), 'status' => 'open',
                'created_at' => $now, 'updated_at' => $now,
            ]);

            // Stock goes in through the real ledger: a batch, and a movement.
            app(StockLedger::class)->receive($ids['product'], 50, "{$label}-BATCH", null, 500, "{$label} seed");
            $ids['batch'] = (int) DB::table('inventory_batches')->where('product_id', $ids['product'])->value('id');

            return $ids;
        });
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    /** Every string anywhere in a JSON response, so a leaked "Alpha" cannot hide in a nested key. @return array<int, string> */
    private function strings($response): array
    {
        $found = [];
        $json = $response->json() ?? [];
        array_walk_recursive($json, function ($value) use (&$found) {
            if (is_string($value)) {
                $found[] = $value;
            }
        });

        return $found;
    }

    private function mentions(array $strings, string $needle): bool
    {
        foreach ($strings as $s) {
            if (stripos($s, $needle) !== false) {
                return true;
            }
        }

        return false;
    }

    /** Raw rows of a table as seen from inside one business. */
    private function rows(User $business, string $table, ?callable $where = null): array
    {
        return TenantContext::runAs($business, function () use ($table, $where) {
            $query = DB::table($table);

            return ($where ? $where($query) : $query)->get()->all();
        });
    }

    // --------------------------------------------------------------- schema

    public function test_every_inventory_table_is_registered_and_carries_an_owner_column(): void
    {
        $tables = collect(Schema::getTableListing())
            ->map(fn ($t) => str_contains($t, '.') ? substr($t, strrpos($t, '.') + 1) : $t)
            ->filter(fn ($t) => str_starts_with($t, 'inventory_'))
            ->values()
            ->all();

        $accountedFor = array_merge(TenantTables::INVENTORY, TenantTables::UNSCOPED_INVENTORY);

        $this->assertSame(
            [],
            array_values(array_diff($tables, $accountedFor)),
            'A new inventory_* table is not in App\Support\Tenancy\TenantTables, so its rows would be shared by every business. Add it (and an owner_id column).'
        );
        $this->assertSame([], array_values(array_diff(TenantTables::INVENTORY, $tables)), 'TenantTables lists a table that does not exist.');

        foreach (TenantTables::INVENTORY as $table) {
            $this->assertTrue(Schema::hasColumn($table, TenantTables::OWNER_COLUMN), "{$table} has no owner_id column");
        }
    }

    // ------------------------------------------------------- reading lists

    public function test_each_business_lists_only_its_own_inventory(): void
    {
        $lists = [
            '/api/inventory/products', '/api/inventory/customers', '/api/inventory/sales',
            '/api/inventory/categories', '/api/inventory/brands', '/api/inventory/suppliers',
            '/api/inventory/expenses', '/api/inventory/stock-movements', '/api/inventory/batches',
            '/api/inventory/credit/customers', '/api/inventory/credit/debtors-ageing',
            '/api/inventory/reminders', '/api/inventory/alerts', '/api/inventory/audit-log',
            '/api/inventory/reports/daily_sales', '/api/inventory/reports/stock_valuation',
            '/api/inventory/reports/debtors_ageing', '/api/inventory/kpis', '/api/inventory/sales/summary',
        ];

        foreach (['Alpha' => [$this->alpha, 'Bravo'], 'Bravo' => [$this->bravo, 'Alpha']] as $own => [$owner, $other]) {
            foreach ($lists as $uri) {
                $response = $this->as($owner, 'GET', $uri);
                $this->assertSame(200, $response->status(), "{$own} could not read {$uri}");
                $this->assertFalse(
                    $this->mentions($this->strings($response), $other),
                    "{$own} saw {$other} data on {$uri}"
                );
            }
        }

        // And they really do see their own (so the checks above are not passing on empty answers).
        foreach (['/api/inventory/products' => 'Alpha Soda', '/api/inventory/customers' => 'Alpha Duka',
            '/api/inventory/sales' => 'Alpha-S-1', '/api/inventory/categories' => 'Alpha Drinks',
            '/api/inventory/brands' => 'Alpha Brand', '/api/inventory/suppliers' => 'Alpha Wholesaler',
            '/api/inventory/expenses' => 'Alpha rent'] as $uri => $expected) {
            $this->assertTrue(
                $this->mentions($this->strings($this->as($this->alpha, 'GET', $uri)), $expected),
                "Alpha should see its own record on {$uri}"
            );
        }
    }

    public function test_staff_see_their_business_and_nobody_elses(): void
    {
        $alpha = $this->strings($this->as($this->alphaStaff, 'GET', '/api/inventory/products')->assertOk());
        $bravo = $this->strings($this->as($this->bravoStaff, 'GET', '/api/inventory/products')->assertOk());

        $this->assertTrue($this->mentions($alpha, 'Alpha Soda'));
        $this->assertFalse($this->mentions($alpha, 'Bravo'));
        $this->assertTrue($this->mentions($bravo, 'Bravo Soda'));
        $this->assertFalse($this->mentions($bravo, 'Alpha'));
    }

    public function test_totals_and_reports_count_only_the_callers_business(): void
    {
        // Give Alpha extra sales so the two businesses' figures differ.
        TenantContext::runAs($this->alpha, function () {
            foreach ([2, 3] as $n) {
                DB::table('inventory_sales')->insert([
                    'number' => "Alpha-S-{$n}", 'payment_status' => 'paid', 'subtotal' => 1000, 'total' => 1000,
                    'paid_total' => 1000, 'created_at' => now(), 'updated_at' => now(),
                ]);
            }
        });

        $alpha = $this->as($this->alpha, 'GET', '/api/inventory/sales/summary')->assertOk();
        $bravo = $this->as($this->bravo, 'GET', '/api/inventory/sales/summary')->assertOk();

        $this->assertNotSame($alpha->json(), $bravo->json(), 'the two businesses have different sales, so different summaries');
        $this->assertCount(3, $this->rows($this->alpha, 'inventory_sales'));
        $this->assertCount(1, $this->rows($this->bravo, 'inventory_sales'));
    }

    // --------------------------------------------------- reaching by an id

    public function test_one_business_cannot_read_change_or_remove_anothers_record_by_id(): void
    {
        $a = $this->ids['Alpha'];
        $b = fn (string $method, string $uri, array $body = []) => $this->as($this->bravo, $method, $uri, $body);

        $b('GET', "/api/inventory/sales/{$a['sale']}")->assertNotFound();
        $b('POST', "/api/inventory/sales/{$a['sale']}/cancel", ['reason' => 'x'])->assertNotFound();
        $b('POST', "/api/inventory/sales/{$a['sale']}/payments", ['amount' => 100, 'method' => 'cash'])->assertNotFound();
        $b('PUT', "/api/inventory/products/{$a['product']}", ['name' => 'Hijacked', 'cost_price' => 1, 'selling_price' => 1, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active'])->assertNotFound();
        $b('DELETE', "/api/inventory/products/{$a['product']}")->assertNotFound();
        $b('PUT', "/api/inventory/customers/{$a['customer']}", ['name' => 'Hijacked', 'phone' => '0700'])->assertNotFound();
        $b('DELETE', "/api/inventory/customers/{$a['customer']}")->assertNotFound();
        $b('PUT', "/api/inventory/suppliers/{$a['supplier']}", ['name' => 'Hijacked'])->assertNotFound();
        $b('DELETE', "/api/inventory/suppliers/{$a['supplier']}")->assertNotFound();
        $b('GET', "/api/inventory/categories/{$a['category']}")->assertNotFound();
        $b('PUT', "/api/inventory/categories/{$a['category']}", ['name' => 'Hijacked'])->assertNotFound();
        $b('DELETE', "/api/inventory/categories/{$a['category']}")->assertNotFound();
        $b('GET', "/api/inventory/brands/{$a['brand']}")->assertNotFound();
        $b('PUT', "/api/inventory/brands/{$a['brand']}", ['name' => 'Hijacked'])->assertNotFound();
        $b('DELETE', "/api/inventory/brands/{$a['brand']}")->assertNotFound();
        $b('PUT', "/api/inventory/expenses/{$a['expense']}", ['category' => 'x', 'description' => 'Hijacked', 'amount' => 1, 'expense_date' => now()->toDateString()])->assertNotFound();
        $b('DELETE', "/api/inventory/expenses/{$a['expense']}")->assertNotFound();
        $b('PUT', "/api/inventory/reminders/{$a['reminder']}/done")->assertNotFound();

        // Nothing of Alpha's changed.
        $this->assertSame('Alpha Soda', $this->rows($this->alpha, 'inventory_products', fn ($q) => $q->where('id', $a['product']))[0]->name);
        $this->assertCount(1, $this->rows($this->alpha, 'inventory_customers', fn ($q) => $q->where('name', 'Alpha Duka')));
        $this->assertCount(1, $this->rows($this->alpha, 'inventory_sales', fn ($q) => $q->where('id', $a['sale'])->whereNull('cancelled_at')));
        $this->assertSame(1, count($this->rows($this->alpha, 'inventory_expenses', fn ($q) => $q->where('description', 'Alpha rent'))));
    }

    public function test_a_sale_cannot_use_another_businesss_product_or_customer(): void
    {
        $sale = fn (array $over) => $this->as($this->bravo, 'POST', '/api/inventory/sales', array_merge([
            'payment_status' => 'paid', 'subtotal' => 800, 'total' => 800, 'paid_total' => 800,
            'items' => [['product_id' => $this->ids['Bravo']['product'], 'quantity' => 1, 'unit_price' => 800]],
            'payments' => [['amount' => 800, 'method' => 'cash']],
        ], $over));

        // Alpha's product id, then Alpha's customer id: refused as "does not exist", not a crash.
        $sale(['items' => [['product_id' => $this->ids['Alpha']['product'], 'quantity' => 1, 'unit_price' => 800]]])
            ->assertStatus(422);
        $sale(['customer_id' => $this->ids['Alpha']['customer']])->assertStatus(422);

        // Alpha's stock is untouched.
        $this->assertSame(50, (int) $this->rows($this->alpha, 'inventory_products', fn ($q) => $q->where('id', $this->ids['Alpha']['product']))[0]->quantity);

        // Bravo's own product works, and the sale belongs to Bravo.
        $created = $sale([])->assertCreated();
        $this->assertSame(49, (int) $this->rows($this->bravo, 'inventory_products', fn ($q) => $q->where('id', $this->ids['Bravo']['product']))[0]->quantity);
        $this->assertCount(2, $this->rows($this->bravo, 'inventory_sales'));
        $this->assertCount(1, $this->rows($this->alpha, 'inventory_sales'), 'Bravo\'s sale did not appear in Alpha\'s books');
        $this->assertNotEmpty($created->json('data.number'));
    }

    // ----------------------------------------------------------- writing

    public function test_the_same_names_are_allowed_in_each_business_but_not_twice_in_one(): void
    {
        foreach ([$this->alpha, $this->bravo] as $business) {
            $this->as($business, 'POST', '/api/inventory/categories', ['name' => 'Soda'])->assertCreated();
            $this->as($business, 'POST', '/api/inventory/brands', ['name' => 'Fanta'])->assertCreated();
            $this->as($business, 'POST', '/api/inventory/crate-types', ['name' => 'Pallet', 'deposit_value' => 100])->assertCreated();
            $this->as($business, 'POST', '/api/inventory/products', [
                'name' => 'Cola', 'sku' => 'COLA-1', 'cost_price' => 1, 'selling_price' => 2,
                'quantity' => 0, 'min_stock' => 0, 'status' => 'active',
            ])->assertCreated();
        }

        // Inside one business a repeat is still refused.
        $this->as($this->alpha, 'POST', '/api/inventory/categories', ['name' => 'Soda'])->assertStatus(422);
        $this->as($this->alpha, 'POST', '/api/inventory/crate-types', ['name' => 'Pallet', 'deposit_value' => 100])->assertStatus(422);
        $this->as($this->alpha, 'POST', '/api/inventory/products', [
            'name' => 'Cola', 'sku' => 'COLA-1', 'cost_price' => 1, 'selling_price' => 2,
            'quantity' => 0, 'min_stock' => 0, 'status' => 'active',
        ])->assertStatus(422);
    }

    public function test_new_rows_belong_to_the_business_even_when_staff_create_them(): void
    {
        $this->as($this->bravoStaff, 'POST', '/api/inventory/customers', ['name' => 'Bravo New Duka', 'phone' => '0799123456'])->assertCreated();

        $row = TenantContext::withoutScope(fn () => DB::table('inventory_customers')->where('name', 'Bravo New Duka')->first());
        $this->assertSame((string) $this->bravo->id, (string) $row->owner_id, 'stamped with the business, not the staff member');

        $this->assertFalse($this->mentions($this->strings($this->as($this->alpha, 'GET', '/api/inventory/customers')), 'Bravo New Duka'));
        $this->assertTrue($this->mentions($this->strings($this->as($this->bravo, 'GET', '/api/inventory/customers')), 'Bravo New Duka'));
    }

    public function test_settings_are_per_business(): void
    {
        $this->as($this->bravo, 'PUT', '/api/inventory/settings', ['depot_name' => 'Bravo Depot', 'tax_percent' => '18'])->assertOk();

        $this->assertSame('Bravo Depot', $this->as($this->bravo, 'GET', '/api/inventory/settings')->json('data.depot_name'));
        $this->assertSame('18', $this->as($this->bravo, 'GET', '/api/inventory/settings')->json('data.tax_percent'));
        // Alpha still has what it started with: its own business name (never Bravo's edit).
        $this->assertSame($this->alpha->name, $this->as($this->alpha, 'GET', '/api/inventory/settings')->json('data.depot_name'));
        $this->assertSame('0', $this->as($this->alpha, 'GET', '/api/inventory/settings')->json('data.tax_percent'));
        // Staff of Bravo read Bravo's (the POS needs them).
        $this->assertSame('Bravo Depot', $this->as($this->bravoStaff, 'GET', '/api/inventory/settings')->json('data.depot_name'));
    }

    public function test_cash_sessions_and_crates_do_not_cross(): void
    {
        $open = $this->as($this->alpha, 'POST', '/api/inventory/cash-sessions', ['opening_float' => 5000])->assertCreated();
        $sessionId = $open->json('data.id');

        $this->as($this->bravo, 'GET', "/api/inventory/cash-sessions/{$sessionId}")->assertNotFound();
        $this->as($this->bravo, 'POST', "/api/inventory/cash-sessions/{$sessionId}/close", ['closing_count' => 1])->assertNotFound();

        $alphaCrate = (int) $this->rows($this->alpha, 'inventory_crate_types', fn ($q) => $q->where('name', 'Crate'))[0]->id;
        $this->as($this->bravo, 'PUT', "/api/inventory/crate-types/{$alphaCrate}", ['deposit_value' => 1])->assertNotFound();
        $this->as($this->bravo, 'POST', '/api/inventory/crate-movements', [
            'crate_type_id' => $alphaCrate, 'direction' => 'issued', 'quantity' => 3, 'customer_id' => $this->ids['Bravo']['customer'],
        ])->assertStatus(422);
        $this->assertSame(2000.0, (float) $this->rows($this->alpha, 'inventory_crate_types', fn ($q) => $q->where('id', $alphaCrate))[0]->deposit_value);
    }

    // ------------------------------------------------------ people around

    public function test_notifications_and_officer_lists_stay_inside_the_business(): void
    {
        $alphaManager = $this->staff($this->alpha, 'manager', 'alpha.manager@example.test');
        $bravoManager = $this->staff($this->bravo, 'manager', 'bravo.manager@example.test');

        // Alpha's officer reports damage; only people in Alpha who can approve it are told.
        $this->as($this->alphaStaff, 'POST', '/api/inventory/write-offs', [
            'product_id' => $this->ids['Alpha']['product'], 'reason' => 'breakage', 'quantity' => 2,
        ])->assertCreated();

        $told = TenantContext::withoutScope(fn () => DB::table('inventory_notifications')->pluck('user_id')->all());
        $this->assertContains((string) $alphaManager->id, $told);
        $this->assertNotContains((string) $bravoManager->id, $told, 'another business must not be notified');
        $this->assertNotContains((string) $this->bravo->id, $told);

        // The officer list is the business's own people.
        $alphaOfficers = collect($this->as($this->alpha, 'GET', '/api/inventory/sales-officers')->assertOk()->json('data'))->pluck('id')->all();
        $this->assertContains((string) $this->alphaStaff->id, $alphaOfficers);
        $this->assertNotContains((string) $this->bravoStaff->id, $alphaOfficers);
        $this->assertNotContains((string) $bravoManager->id, $alphaOfficers);
    }

    public function test_super_admin_sees_no_business_and_what_they_create_is_their_own(): void
    {
        $super = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);

        $names = $this->strings($this->as($super, 'GET', '/api/inventory/products')->assertOk());
        $this->assertFalse($this->mentions($names, 'Alpha Soda'), 'the platform owner does not read any business stock');
        $this->assertFalse($this->mentions($names, 'Bravo Soda'));

        $this->as($super, 'POST', '/api/inventory/products', [
            'name' => 'Platform Soda', 'sku' => 'PLAT-1', 'cost_price' => 1, 'selling_price' => 2,
            'quantity' => 0, 'min_stock' => 0, 'status' => 'active',
        ])->assertCreated();

        $owner = TenantContext::withoutScope(fn () => DB::table('inventory_products')->where('sku', 'PLAT-1')->value('owner_id'));
        $this->assertSame((string) $super->id, (string) $owner);
        $this->assertFalse($this->mentions($this->strings($this->as($this->alpha, 'GET', '/api/inventory/products')), 'Platform Soda'));
    }

    // ------------------------------------------- the safety net underneath

    public function test_a_query_that_forgets_to_filter_still_cannot_cross_businesses(): void
    {
        $alphaProduct = $this->ids['Alpha']['product'];

        TenantContext::runAs($this->bravo, function () use ($alphaProduct) {
            // Unfiltered reads, aggregates, and an OR that tries to widen the result.
            $this->assertSame(['Bravo Soda'], DB::table('inventory_products')->pluck('name')->all());
            $this->assertSame(1, DB::table('inventory_products')->count());
            $this->assertNull(DB::table('inventory_products')->find($alphaProduct));
            $this->assertSame(0, DB::table('inventory_products')->where('id', 0)->orWhere('id', $alphaProduct)->count());
            $this->assertFalse(DB::table('inventory_products')->where('id', $alphaProduct)->exists());

            // Changes and deletes miss, with no error.
            $this->assertSame(0, DB::table('inventory_products')->where('id', $alphaProduct)->update(['name' => 'Hijacked']));
            $this->assertSame(0, DB::table('inventory_products')->where('id', $alphaProduct)->delete());
            // Joins do not pull in the other business's rows.
            $this->assertSame(0, DB::table('inventory_sales as s')
                ->join('inventory_customers as c', 'c.id', '=', 's.customer_id')
                ->where('c.name', 'Alpha Duka')->count());
        });

        $this->assertSame('Alpha Soda', $this->rows($this->alpha, 'inventory_products', fn ($q) => $q->where('id', $alphaProduct))[0]->name);
    }

    public function test_a_business_cannot_write_a_row_for_another_business(): void
    {
        $this->expectException(LogicException::class);

        TenantContext::runAs($this->bravo, fn () => DB::table('inventory_customers')->insert([
            'owner_id' => (string) $this->alpha->id, 'name' => 'Smuggled', 'phone' => '0700000000',
            'created_at' => now(), 'updated_at' => now(),
        ]));
    }

    public function test_statements_that_cannot_be_scoped_are_refused_on_these_tables(): void
    {
        foreach ([
            fn () => DB::table('inventory_products')->upsert([['sku' => 'X', 'name' => 'X']], ['sku'], ['name']),
            fn () => DB::table('inventory_products')->insertUsing(['name'], DB::table('inventory_products')->select('name')),
        ] as $statement) {
            try {
                TenantContext::runAs($this->bravo, $statement);
                $this->fail('expected the statement to be refused');
            } catch (LogicException) {
                $this->addToAssertionCount(1);
            }
        }

        // Other tables keep every statement type.
        $this->assertSame(0, TenantContext::runAs($this->bravo, fn () => DB::table('cache')->count()));
    }

    // ------------------------------------------- handing over the live depot

    public function test_the_existing_depot_is_handed_to_its_owner_and_nobody_elses_data_moves(): void
    {
        // Rebuild the pre-isolation world: a depot owner, a sales officer a super admin created
        // (so they belong to no business), and rows that have no owner.
        $super = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'email' => 'depot.owner@example.test', 'created_by' => $super->id]), 'inventory');
        $orphan = $this->givenServices(User::factory()->create(['role' => 'sales_officer', 'is_active' => true, 'email' => 'orphan@example.test', 'created_by' => $super->id]), 'inventory');
        $attached = $this->staff($this->alpha, 'viewer', 'attached@example.test'); // already has a business

        TenantContext::withoutScope(function () {
            DB::table('inventory_products')->insert(['name' => 'Legacy Soda', 'sku' => 'LEGACY-1', 'cost_price' => 1, 'selling_price' => 2,
                'quantity' => 4, 'min_stock' => 0, 'status' => 'active', 'created_at' => now(), 'updated_at' => now()]);
            DB::table('inventory_customers')->insert(['name' => 'Legacy Duka', 'phone' => '0700111222', 'created_at' => now(), 'updated_at' => now()]);
            DB::table('inventory_settings')->insert(['key' => 'legacy_key', 'value' => '1', 'updated_at' => now()]);
        });
        $this->assertGreaterThan(0, array_sum(app(InventoryOwnership::class)->unownedRows()));

        $result = app(InventoryOwnership::class)->assign($owner);

        $this->assertSame(0, array_sum(app(InventoryOwnership::class)->unownedRows()), 'every legacy row now has an owner');
        $this->assertGreaterThanOrEqual(3, array_sum($result['rows']));
        $this->assertSame(['orphan@example.test'], $result['adopted'], 'only the staff member who belonged to nobody moved');
        $this->assertSame((string) $owner->id, (string) $orphan->fresh()->created_by);
        $this->assertSame((string) $this->alpha->id, (string) $attached->fresh()->created_by, 'staff of another business are left alone');

        // The depot owner and the adopted officer now see the legacy depot; the other businesses do not.
        $this->assertTrue($this->mentions($this->strings($this->as($owner, 'GET', '/api/inventory/products')), 'Legacy Soda'));
        $this->assertTrue($this->mentions($this->strings($this->as($orphan->fresh(), 'GET', '/api/inventory/products')), 'Legacy Soda'));
        $this->assertFalse($this->mentions($this->strings($this->as($this->alpha, 'GET', '/api/inventory/products')), 'Legacy'));
        $this->assertFalse($this->mentions($this->strings($this->as($this->bravo, 'GET', '/api/inventory/products')), 'Legacy'));
        // Rows other businesses already owned were not reassigned.
        $this->assertTrue($this->mentions($this->strings($this->as($this->alpha, 'GET', '/api/inventory/products')), 'Alpha Soda'));

        // The move was recorded so it can be undone by hand, and running it again changes nothing.
        $this->assertSame(1, DB::table('tenancy_reparent_log')->where('user_id', $orphan->id)->count());
        $again = app(InventoryOwnership::class)->assign($owner);
        $this->assertSame(0, array_sum($again['rows']));
        $this->assertSame([], $again['adopted']);
    }

    public function test_the_depot_owner_is_the_business_that_has_actually_been_trading(): void
    {
        $ownership = app(InventoryOwnership::class);

        // Alpha registered a day before Bravo. (Set explicitly: both fixtures are created in the same
        // second, and a tie in created_at is broken differently by MySQL and SQLite.)
        DB::table('users')->where('id', $this->alpha->id)->update(['created_at' => now()->subDay()]);

        // Alpha and Bravo both hold inventory but neither has any activity: the older wins.
        $this->assertSame((string) $this->alpha->id, (string) $ownership->findDepotOwner()->id);

        // Bravo's accounts created the sales and products: Bravo is running the depot.
        TenantContext::withoutScope(function () {
            DB::table('inventory_sales')->where('number', 'Bravo-S-1')->update(['created_by' => $this->bravo->id]);
            DB::table('inventory_products')->where('sku', 'Bravo-SODA')->update(['created_by' => $this->bravo->id]);
            DB::table('inventory_sales')->where('number', 'Alpha-S-1')->update(['created_by' => null]);
            DB::table('inventory_products')->where('sku', 'Alpha-SODA')->update(['created_by' => null]);
        });
        $this->assertSame((string) $this->bravo->id, (string) $ownership->findDepotOwner()->id);

        // Nobody active holds inventory: nothing is guessed.
        TenantContext::withoutScope(fn () => DB::table('user_services')->where('service_type', 'inventory')->delete());
        $this->assertNull($ownership->findDepotOwner());
    }

    public function test_the_assign_command_previews_and_then_assigns(): void
    {
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'email' => 'cmd.owner@example.test']), 'inventory');
        TenantContext::withoutScope(fn () => DB::table('inventory_customers')->insert([
            'name' => 'Unowned Duka', 'phone' => '0700999888', 'created_at' => now(), 'updated_at' => now(),
        ]));

        $this->artisan('inventory:ownership-report')->assertFailed(); // an unowned row is a problem
        $this->artisan('inventory:assign-owner', ['user' => 'cmd.owner@example.test', '--dry-run' => true])->assertSuccessful();
        $this->assertSame(1, TenantContext::withoutScope(fn () => DB::table('inventory_customers')->whereNull('owner_id')->count()), 'a dry run changes nothing');

        $this->artisan('inventory:assign-owner', ['user' => 'bravo.officer@example.test'])->assertFailed(); // staff are not owners
        $this->artisan('inventory:assign-owner', ['user' => 'cmd.owner@example.test'])->assertSuccessful();
        $this->assertSame(0, TenantContext::withoutScope(fn () => DB::table('inventory_customers')->whereNull('owner_id')->count()));
        $this->artisan('inventory:ownership-report')->assertSuccessful();
    }

    public function test_a_depot_given_to_the_wrong_business_can_be_moved_to_the_right_one(): void
    {
        // The right owner was given the inventory service later, so was only seeded with defaults.
        $right = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'email' => 'right.owner@example.test']), 'inventory');
        $count = fn (string $table, User $of) => TenantContext::withoutScope(fn () => DB::table($table)->where('owner_id', $of->id)->count());
        $alphaProducts = $count('inventory_products', $this->alpha);
        $this->assertGreaterThan(0, $alphaProducts);
        $this->assertGreaterThan(0, $count('inventory_settings', $right), 'seeded defaults exist before the move');

        // A dry run says what would move and changes nothing.
        $this->artisan('inventory:assign-owner', ['user' => 'right.owner@example.test', '--from' => $this->alpha->email, '--dry-run' => true])->assertSuccessful();
        $this->assertSame($alphaProducts, $count('inventory_products', $this->alpha));

        $this->artisan('inventory:assign-owner', ['user' => 'right.owner@example.test', '--from' => $this->alpha->email])->assertSuccessful();

        $this->assertSame(0, $count('inventory_products', $this->alpha), 'the wrong owner no longer holds the depot');
        $this->assertSame($alphaProducts, $count('inventory_products', $right));
        $this->assertSame(
            count(\App\Support\InventoryDefaults::SETTINGS),
            $count('inventory_settings', $right),
            'the seeded defaults were replaced by the depot\'s own, not added to them'
        );
        $this->assertTrue($this->mentions($this->strings($this->as($right, 'GET', '/api/inventory/products')), 'Alpha Soda'));
        $this->assertFalse($this->mentions($this->strings($this->as($this->alpha, 'GET', '/api/inventory/products')), 'Alpha Soda'));
        $this->assertTrue($this->mentions($this->strings($this->as($this->bravo, 'GET', '/api/inventory/products')), 'Bravo Soda'), 'other businesses are untouched');
    }

    public function test_a_depot_is_never_merged_into_a_business_that_already_trades(): void
    {
        $before = TenantContext::withoutScope(fn () => DB::table('inventory_products')->where('owner_id', $this->alpha->id)->count());

        // Bravo has its own products and sales: merging would collide, so it is refused up front.
        $this->artisan('inventory:assign-owner', ['user' => $this->bravo->email, '--from' => $this->alpha->email, '--dry-run' => true])->assertFailed();
        $this->artisan('inventory:assign-owner', ['user' => $this->bravo->email, '--from' => $this->alpha->email])->assertFailed();

        $this->assertSame($before, TenantContext::withoutScope(fn () => DB::table('inventory_products')->where('owner_id', $this->alpha->id)->count()));
        $this->expectException(\DomainException::class);
        app(InventoryOwnership::class)->reassign($this->alpha, $this->bravo);
    }
}
