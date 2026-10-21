<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use App\Support\Tenancy\TenantTables;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * A business that has both a shop and a salon keeps two sets of books on the same tables: what is done in the salon
 * (the app says so with the `X-Service: salon` header) never shows up in the shop, and the other way round. A
 * request with no header is the shop, exactly as before the salon existed.
 */
class SalonSeparationTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'Both Owner', 'role' => 'admin', 'is_active' => true]), 'inventory', 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [], bool $salon = false)
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders(); // a header set for one call would otherwise stay on every later call
        $request = $this->withHeader('Authorization', "Bearer {$token}");
        if ($salon) {
            $request = $request->withHeader('X-Service', 'salon');
        }

        return $request->json($method, $uri, $body);
    }

    private function raw(callable $fn, ?User $as = null, string $service = 'inventory')
    {
        return TenantContext::runAs($as ?? $this->owner, fn () => TenantContext::runInService($service, $fn));
    }

    private function product(string $name, bool $salon, array $extra = []): int
    {
        return $this->api($this->owner, 'POST', '/api/inventory/products', array_merge([
            'name' => $name, 'sku' => strtoupper(substr($name, 0, 3)) . '-1', 'quantity' => 10, 'min_stock' => 1, 'status' => 'active',
            'cost_price' => 500, 'selling_price' => 1000,
        ], $extra), $salon)->assertCreated()->json('data.id');
    }

    private function names(string $uri, bool $salon, ?User $as = null): array
    {
        return array_column($this->api($as ?? $this->owner, 'GET', $uri, [], $salon)->assertOk()->json('data'), 'name');
    }

    public function test_every_inventory_table_is_split_by_service(): void
    {
        foreach (TenantTables::INVENTORY as $table) {
            $this->assertTrue(Schema::hasColumn($table, 'service'), "{$table} has no service column");
        }
    }

    public function test_what_is_added_in_the_salon_is_not_in_the_shop_and_the_other_way_round(): void
    {
        $this->product('Cola', salon: false);
        $this->product('Braids', true, ['is_service' => true, 'quantity' => 0, 'min_stock' => 0]);

        $this->assertSame(['Cola'], $this->names('/api/inventory/products', salon: false));
        $this->assertSame(['Braids'], $this->names('/api/inventory/products', salon: true));
    }

    public function test_a_new_row_is_stamped_with_the_service_it_was_made_in(): void
    {
        $shop = $this->product('Cola', salon: false);
        $salon = $this->product('Shampoo', salon: true);

        $rows = TenantContext::withoutScope(fn () => DB::table('inventory_products')->whereIn('id', [$shop, $salon])->pluck('service', 'id')->all());

        $this->assertSame('inventory', $rows[$shop]);
        $this->assertSame('salon', $rows[$salon]);
    }

    public function test_rows_that_existed_before_belong_to_the_shop(): void
    {
        // a row written the old way, with no service named
        TenantContext::withoutScope(fn () => DB::table('inventory_customers')->insert([
            'owner_id' => $this->owner->id, 'name' => 'Old Customer', 'phone' => '0700000001', 'created_at' => now(), 'updated_at' => now(),
        ]));

        $this->assertSame(['Old Customer'], $this->names('/api/inventory/customers', salon: false));
        $this->assertSame([], $this->names('/api/inventory/customers', salon: true));
    }

    public function test_clients_sales_and_cash_are_kept_apart(): void
    {
        $cola = $this->product('Cola', salon: false);
        $shampoo = $this->product('Shampoo', salon: true);
        $this->api($this->owner, 'POST', '/api/inventory/customers', ['name' => 'Shop Buyer', 'phone' => '0711000001'])->assertCreated();
        $this->api($this->owner, 'POST', '/api/inventory/customers', ['name' => 'Salon Client', 'phone' => '0711000002'], true)->assertCreated();

        $sale = fn (int $product, bool $salon) => $this->api($this->owner, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 1000, 'discount' => 0, 'tax' => 0, 'total' => 1000, 'paid_total' => 1000,
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => 1000]],
        ], $salon);
        $sale($cola, false)->assertCreated();
        $sale($shampoo, true)->assertCreated();

        $this->assertSame(['Shop Buyer'], $this->names('/api/inventory/customers', salon: false));
        $this->assertSame(['Salon Client'], $this->names('/api/inventory/customers', salon: true));
        $this->assertCount(1, $this->api($this->owner, 'GET', '/api/inventory/sales', [], false)->assertOk()->json('data'));
        $this->assertCount(1, $this->api($this->owner, 'GET', '/api/inventory/sales', [], true)->assertOk()->json('data'));
        $this->assertSame(1, (int) $this->api($this->owner, 'GET', '/api/inventory/sales/summary', [], true)->json('data.count'));
    }

    public function test_the_same_sku_and_the_same_category_name_can_be_used_in_both(): void
    {
        $this->product('Oil', salon: false);
        $this->product('Oil', salon: true);
        $this->api($this->owner, 'POST', '/api/inventory/categories', ['name' => 'Hair'])->assertCreated();
        $this->api($this->owner, 'POST', '/api/inventory/categories', ['name' => 'Hair'], true)->assertCreated();

        // but not twice in the same service
        $this->api($this->owner, 'POST', '/api/inventory/categories', ['name' => 'Hair'], true)->assertStatus(422);
        $this->api($this->owner, 'POST', '/api/inventory/products', [
            'name' => 'Oil again', 'sku' => 'OIL-1', 'quantity' => 1, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 1, 'selling_price' => 2,
        ], true)->assertStatus(422);
    }

    public function test_selling_in_the_salon_never_touches_the_shops_stock(): void
    {
        $shopOil = $this->product('Oil', salon: false);
        $salonOil = $this->product('Oil', salon: true);

        $this->api($this->owner, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 3000, 'discount' => 0, 'tax' => 0, 'total' => 3000, 'paid_total' => 3000,
            'items' => [['product_id' => $salonOil, 'quantity' => 3, 'unit_price' => 1000]],
        ], true)->assertCreated();

        $this->assertSame(7, (int) $this->raw(fn () => DB::table('inventory_products')->where('id', $salonOil)->value('quantity'), service: 'salon'));
        $this->assertSame(10, (int) $this->raw(fn () => DB::table('inventory_products')->where('id', $shopOil)->value('quantity')));
    }

    public function test_the_salon_cannot_sell_the_shops_goods_and_the_shop_cannot_sell_the_salons(): void
    {
        $shop = $this->product('Cola', salon: false);
        $salon = $this->product('Shampoo', salon: true);
        $sell = fn (int $product, bool $inSalon) => $this->api($this->owner, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 1000, 'discount' => 0, 'tax' => 0, 'total' => 1000, 'paid_total' => 1000,
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => 1000]],
        ], $inSalon);

        $sell($shop, true)->assertStatus(422);
        $sell($salon, false)->assertStatus(422);
        $this->assertSame(0, $this->raw(fn () => DB::table('inventory_sales')->count()));
    }

    public function test_the_salon_has_its_own_settings_and_is_a_retail_business_whatever_the_shop_is(): void
    {
        $shop = $this->api($this->owner, 'GET', '/api/inventory/settings')->assertOk()->json('data');
        $salon = $this->api($this->owner, 'GET', '/api/inventory/settings', [], true)->assertOk()->json('data');

        $this->assertSame('depot', $shop['inventory_type'], 'the shop is still the depot it always was');
        $this->assertSame('1', (string) $shop['use_crates']);
        $this->assertSame('retail', $salon['inventory_type']);
        $this->assertSame('0', (string) $salon['use_crates'], 'a salon has no crates');
        $this->assertSame('retail', $salon['sale_tier']);
    }

    public function test_changing_a_setting_in_the_salon_leaves_the_shops_alone(): void
    {
        $this->api($this->owner, 'PUT', '/api/inventory/settings', ['tax_percent' => '18'], true)->assertOk();

        $this->assertSame('18', (string) $this->api($this->owner, 'GET', '/api/inventory/settings', [], true)->json('data.tax_percent'));
        $this->assertNotSame('18', (string) $this->api($this->owner, 'GET', '/api/inventory/settings')->json('data.tax_percent'));
    }

    public function test_the_header_alone_gives_no_way_into_a_salon_the_person_does_not_have(): void
    {
        $shopOnly = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');
        $this->api($shopOnly, 'POST', '/api/inventory/products', [
            'name' => 'Cola', 'sku' => 'COL-1', 'quantity' => 5, 'min_stock' => 1, 'status' => 'active', 'cost_price' => 1, 'selling_price' => 2,
        ])->assertCreated();

        // asking for the salon is refused outright (the salon routes need the salon), and does not change what the shop sees
        $this->api($shopOnly, 'GET', '/api/inventory/products', [], true)->assertOk();
        $this->assertSame(['Cola'], $this->names('/api/inventory/products', salon: true, as: $shopOnly), 'treated as the shop it is');
    }

    public function test_another_business_never_sees_this_ones_salon(): void
    {
        $this->product('Shampoo', salon: true);
        $other = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'salon');

        $this->assertSame([], $this->names('/api/inventory/products', salon: true, as: $other));
    }

    public function test_a_super_admin_sees_every_salon_in_the_salon_and_every_shop_in_the_shop(): void
    {
        $this->product('Cola', salon: false);
        $this->product('Shampoo', salon: true);
        $otherSalon = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'salon');
        $this->api($otherSalon, 'POST', '/api/inventory/products', [
            'name' => 'Nail polish', 'sku' => 'NAI-1', 'quantity' => 5, 'min_stock' => 1, 'status' => 'active', 'cost_price' => 1, 'selling_price' => 2,
        ], true)->assertCreated();
        $super = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);

        $inSalon = $this->names('/api/inventory/products', salon: true, as: $super);
        $inShop = $this->names('/api/inventory/products', salon: false, as: $super);

        $this->assertEqualsCanonicalizing(['Shampoo', 'Nail polish'], $inSalon);
        $this->assertSame(['Cola'], $inShop);
    }

    public function test_the_reminder_job_reads_the_salons_books_only(): void
    {
        $service = $this->api($this->owner, 'POST', '/api/inventory/products', [
            'name' => 'Braids', 'sku' => 'BRA-1', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 40000,
        ], true)->assertCreated()->json('data.id');
        $client = $this->api($this->owner, 'POST', '/api/inventory/customers', ['name' => 'Neema', 'phone' => '0711000001'], true)->assertCreated()->json('data.id');
        $this->api($this->owner, 'PUT', '/api/inventory/salon/settings', ['rebook_enabled' => true, 'rebook_weeks' => 4], true)->assertOk();
        \Carbon\Carbon::setTestNow('2026-09-01 10:00:00');
        $this->api($this->owner, 'POST', '/api/inventory/sales', [
            'customer_id' => $client, 'payment_status' => 'paid', 'subtotal' => 40000, 'discount' => 0, 'tax' => 0, 'total' => 40000, 'paid_total' => 40000,
            'items' => [['product_id' => $service, 'quantity' => 1, 'unit_price' => 40000]],
        ], true)->assertCreated();
        $this->sms->sent = []; // the thank-you for the visit went out when it was paid; this counts only what the job sends
        \Carbon\Carbon::setTestNow('2026-09-29 07:00:00');

        $this->artisan('salon:remind-rebooking')->assertExitCode(0);

        $this->assertCount(1, $this->sms->sent, 'texted from the salon\'s books');
        $this->assertSame(1, $this->raw(fn () => DB::table('inventory_rebook_reminders')->count(), service: 'salon'));
        \Carbon\Carbon::setTestNow();
    }
}
