<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Inventory\CrateLedgerService;
use App\Support\InventoryDefaults;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Customers (no duplicates, safe delete), the depot settings screen, and the
 * migration that restores default crate types/settings after a data wipe.
 */
class CustomersAndDefaultsTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        // A business owner given inventory: it gets its own settings and crate types.
        $this->admin = $this->actAsBusiness(
            $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory')
        );
    }

    private function api(string $method, string $uri, array $body = [])
    {
        $token = $this->admin->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function customer(string $name = 'mama anna', string $phone = '0783510498'): int
    {
        return (int) DB::table('inventory_customers')->insertGetId([
            'name' => $name, 'phone' => $phone, 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function crateTypeId(): int
    {
        return (int) DB::table('inventory_crate_types')->where('name', 'Crate')->value('id');
    }

    // ---------------------------------------------------------- duplicates

    public function test_saving_the_same_customer_twice_returns_the_existing_record(): void
    {
        $payload = ['name' => 'Mama Anna', 'phone' => '0783510498'];

        $first = $this->api('POST', '/api/inventory/customers', $payload)->assertCreated()->json('data.id');
        $second = $this->api('POST', '/api/inventory/customers', ['name' => ' mama anna ', 'phone' => '0783510498'])
            ->assertOk()->json('data');

        $this->assertSame($first, $second['id']);
        $this->assertTrue($second['existing']);
        $this->assertSame(1, DB::table('inventory_customers')->count());
    }

    public function test_a_different_person_sharing_a_phone_is_still_a_new_customer(): void
    {
        $this->api('POST', '/api/inventory/customers', ['name' => 'Mama Anna', 'phone' => '0783510498'])->assertCreated();
        $this->api('POST', '/api/inventory/customers', ['name' => 'Baba Anna', 'phone' => '0783510498'])->assertCreated();

        $this->assertSame(2, DB::table('inventory_customers')->count());
    }

    // -------------------------------------------------------------- delete

    public function test_a_customer_with_nothing_outstanding_can_be_deleted(): void
    {
        $id = $this->customer();

        $this->api('DELETE', "/api/inventory/customers/{$id}")->assertOk();

        $this->assertDatabaseMissing('inventory_customers', ['id' => $id]);
    }

    public function test_deleting_a_customer_keeps_their_past_sales_under_the_same_name(): void
    {
        $id = $this->customer();
        $saleId = DB::table('inventory_sales')->insertGetId([
            'number' => 'S-TEST-1', 'customer_id' => $id, 'payment_status' => 'paid',
            'subtotal' => 1000, 'total' => 1000, 'paid_total' => 1000, 'created_at' => now(), 'updated_at' => now(),
        ]);

        $this->api('DELETE', "/api/inventory/customers/{$id}")->assertOk();

        $sale = DB::table('inventory_sales')->find($saleId);
        $this->assertNull($sale->customer_id);
        $this->assertSame('mama anna', $sale->customer_name_override);
    }

    public function test_a_customer_with_an_unpaid_sale_cannot_be_deleted(): void
    {
        $id = $this->customer();
        DB::table('inventory_sales')->insert([
            'number' => 'S-TEST-2', 'customer_id' => $id, 'payment_status' => 'debt',
            'subtotal' => 112000, 'total' => 112000, 'paid_total' => 0, 'created_at' => now(), 'updated_at' => now(),
        ]);

        $this->api('DELETE', "/api/inventory/customers/{$id}")
            ->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'outstanding debt'));

        $this->assertDatabaseHas('inventory_customers', ['id' => $id]);
    }

    public function test_a_customer_holding_crates_cannot_be_deleted_even_with_force(): void
    {
        $id = $this->customer();
        app(CrateLedgerService::class)->post($this->crateTypeId(), 'issued', 10, $id, 'S-TEST-3', null, $this->admin->id);

        $this->api('DELETE', "/api/inventory/customers/{$id}")
            ->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, '10 crate'));
        $this->api('DELETE', "/api/inventory/customers/{$id}?force=1")->assertStatus(422);

        $this->assertDatabaseHas('inventory_customers', ['id' => $id]);
        $this->assertSame(10, (int) DB::table('inventory_crate_movements')
            ->where('party_type', 'customer')->where('customer_id', $id)->sum('quantity'));
    }

    public function test_once_the_crates_are_returned_the_customer_can_be_deleted(): void
    {
        $id = $this->customer();
        $ledger = app(CrateLedgerService::class);
        $ledger->post($this->crateTypeId(), 'issued', 10, $id, 'S-TEST-4', null, $this->admin->id);
        $ledger->post($this->crateTypeId(), 'returned', 10, $id, null, null, $this->admin->id);

        $this->api('DELETE', "/api/inventory/customers/{$id}")->assertOk();
    }

    public function test_deleting_an_unknown_customer_is_a_404(): void
    {
        $this->api('DELETE', '/api/inventory/customers/999999')->assertNotFound();
    }

    // ------------------------------------------------------------ settings

    public function test_settings_read_as_defaults_when_no_rows_exist_and_can_then_be_saved(): void
    {
        DB::table('inventory_settings')->delete();

        $read = $this->api('GET', '/api/inventory/settings')->assertOk()->json('data');
        // A depot with no stored name reads as the business it belongs to, not a platform placeholder.
        $this->assertSame($this->admin->name, $read['depot_name']);
        $this->assertSame('10', $read['max_discount_percent']);

        $this->api('PUT', '/api/inventory/settings', ['depot_name' => 'Remagwe Depot', 'bogus_key' => 'x'])
            ->assertOk()->assertJsonPath('data.saved', ['depot_name']);

        $after = $this->api('GET', '/api/inventory/settings')->json('data');
        $this->assertSame('Remagwe Depot', $after['depot_name']);
        $this->assertArrayNotHasKey('bogus_key', $after);
        $this->assertSame(1, DB::table('inventory_settings')->count());
    }

    public function test_saving_nothing_recognisable_is_still_rejected(): void
    {
        $this->api('PUT', '/api/inventory/settings', ['bogus_key' => 'x'])->assertStatus(422);
    }

    // ------------------------------------------------- restore migration

    public function test_the_defaults_list_matches_what_a_fresh_install_seeds(): void
    {
        // If a later migration seeds another setting, this fails until InventoryDefaults
        // (and the restore migration) learn about it -- so a wipe can never lose it.
        $this->assertEqualsCanonicalizing(
            array_keys(InventoryDefaults::SETTINGS),
            DB::table('inventory_settings')->pluck('key')->all(),
        );
    }

    private function restore(): void
    {
        (require base_path('database/migrations/2026_10_08_120000_restore_inventory_default_reference_data.php'))->up();
    }

    public function test_the_restore_migration_brings_back_wiped_defaults(): void
    {
        DB::table('inventory_crate_types')->delete();
        DB::table('inventory_settings')->delete();

        $this->restore();

        $this->assertEqualsCanonicalizing(['Crate', 'Empty bottle'], DB::table('inventory_crate_types')->pluck('name')->all());
        $this->assertSame(2000.0, (float) DB::table('inventory_crate_types')->where('name', 'Crate')->value('deposit_value'));
        // Everything the migration knew about. The settings added later (READ_TIME_DEFAULTS) are not rows a
        // migration restores: with no row they read as their default, and seedFor() writes them.
        $this->assertEqualsCanonicalizing(
            array_values(array_diff(array_keys(InventoryDefaults::SETTINGS), InventoryDefaults::READ_TIME_DEFAULTS)),
            DB::table('inventory_settings')->pluck('key')->all(),
        );
    }

    public function test_the_restore_migration_is_repeatable_and_never_overwrites_edits(): void
    {
        DB::table('inventory_settings')->where('key', 'depot_name')->update(['value' => 'My Depot']);
        DB::table('inventory_crate_types')->where('name', 'Crate')->update(['deposit_value' => 3500]);

        $this->restore();
        $this->restore();

        $this->assertSame('My Depot', DB::table('inventory_settings')->where('key', 'depot_name')->value('value'));
        $this->assertSame(3500.0, (float) DB::table('inventory_crate_types')->where('name', 'Crate')->value('deposit_value'));
        $this->assertSame(2, DB::table('inventory_crate_types')->count());
        $this->assertSame(count(InventoryDefaults::SETTINGS), DB::table('inventory_settings')->count());
    }
}
