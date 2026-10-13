<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Inventory\CrateLedgerService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Crate types and the security deposit charged per crate: who may change them,
 * validation, and the rules that keep the crate ledger consistent.
 */
class CrateTypesTest extends TestCase
{
    use RefreshDatabase;

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    /** A business owner given inventory (so it has its own default crate types), acting as that business. */
    private function admin(): User
    {
        return $this->actAsBusiness(
            $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory')
        );
    }

    private function customer(): int
    {
        return (int) DB::table('inventory_customers')->insertGetId([
            'name' => 'mama anna', 'phone' => '0783510498', 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function crateId(): int
    {
        return (int) DB::table('inventory_crate_types')->where('name', 'Crate')->value('id');
    }

    // --------------------------------------------------------- permissions

    public function test_only_people_who_manage_settings_can_change_crate_types(): void
    {
        // Staff belong to the business that created them.
        $owner = $this->admin();
        $officer = User::factory()->create(['role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id]);
        $officer->services()->create(['service_type' => 'inventory']);
        $id = $this->crateId();

        // A sales officer may look (inv_view_crates)...
        $this->api($officer, 'GET', '/api/inventory/crate-types')->assertOk();
        // ...but not create, change or delete.
        $this->api($officer, 'POST', '/api/inventory/crate-types', ['name' => 'Big crate', 'deposit_value' => 5000])->assertForbidden();
        $this->api($officer, 'PUT', "/api/inventory/crate-types/{$id}", ['deposit_value' => 1])->assertForbidden();
        $this->api($officer, 'DELETE', "/api/inventory/crate-types/{$id}")->assertForbidden();

        $this->assertSame(2000.0, (float) DB::table('inventory_crate_types')->where('id', $id)->value('deposit_value'));
    }

    // ---------------------------------------------------- create / validate

    public function test_an_admin_can_add_a_crate_type_and_it_is_audited(): void
    {
        $admin = $this->admin();

        $this->api($admin, 'POST', '/api/inventory/crate-types', ['name' => '  Big crate ', 'deposit_value' => 5000])
            ->assertCreated();

        $this->assertDatabaseHas('inventory_crate_types', ['name' => 'Big crate', 'deposit_value' => 5000, 'status' => 'active']);
        $this->assertDatabaseHas('inventory_audit_log', ['entity_type' => 'crate_type', 'action' => 'created']);
    }

    public function test_names_must_be_unique_and_deposits_non_negative(): void
    {
        $admin = $this->admin();

        $this->api($admin, 'POST', '/api/inventory/crate-types', ['name' => 'Crate', 'deposit_value' => 100])
            ->assertStatus(422)->assertJsonValidationErrors('name');
        $this->api($admin, 'POST', '/api/inventory/crate-types', ['name' => 'Bad', 'deposit_value' => -1])
            ->assertStatus(422)->assertJsonValidationErrors('deposit_value');
        $this->api($admin, 'POST', '/api/inventory/crate-types', ['name' => 'Bad', 'deposit_value' => 'lots'])
            ->assertStatus(422);
    }

    // ------------------------------------------------------------- update

    public function test_changing_the_deposit_changes_what_customers_have_at_risk(): void
    {
        $admin = $this->admin();
        $id = $this->crateId();
        app(CrateLedgerService::class)->post($id, 'issued', 10, $this->customer(), 'S-1', null, $admin->id);

        $before = $this->api($admin, 'GET', '/api/inventory/crate-balances')->json('data.0.deposit_at_risk');
        $this->assertEquals(20000, $before);

        $this->api($admin, 'PUT', "/api/inventory/crate-types/{$id}", ['deposit_value' => 3500])->assertOk();

        $after = $this->api($admin, 'GET', '/api/inventory/crate-balances')->json();
        $this->assertEquals(35000, $after['data'][0]['deposit_at_risk']);
        $this->assertEquals(35000, $after['meta']['total_deposit_at_risk']);
        $this->assertDatabaseHas('inventory_audit_log', ['entity_type' => 'crate_type', 'action' => 'updated']);
    }

    public function test_a_type_can_be_renamed_but_not_to_another_types_name(): void
    {
        $admin = $this->admin();
        $crate = $this->crateId();
        $bottle = (int) DB::table('inventory_crate_types')->where('name', 'Empty bottle')->value('id');

        $this->api($admin, 'PUT', "/api/inventory/crate-types/{$crate}", ['name' => 'Empty bottle'])
            ->assertStatus(422)->assertJsonValidationErrors('name');
        // Saving a type with its own unchanged name is fine.
        $this->api($admin, 'PUT', "/api/inventory/crate-types/{$bottle}", ['name' => 'Empty bottle', 'deposit_value' => 150])->assertOk();
        $this->api($admin, 'PUT', "/api/inventory/crate-types/{$crate}", ['name' => 'Plastic crate'])->assertOk();

        $this->assertDatabaseHas('inventory_crate_types', ['id' => $crate, 'name' => 'Plastic crate']);
    }

    public function test_an_empty_update_and_an_unknown_type_are_rejected(): void
    {
        $admin = $this->admin();

        $this->api($admin, 'PUT', '/api/inventory/crate-types/'.$this->crateId(), [])->assertStatus(422);
        $this->api($admin, 'PUT', '/api/inventory/crate-types/999999', ['deposit_value' => 1])->assertNotFound();
    }

    public function test_a_type_cannot_be_switched_off_while_customers_hold_crates_of_it(): void
    {
        $admin = $this->admin();
        $id = $this->crateId();
        $customer = $this->customer();
        $ledger = app(CrateLedgerService::class);
        $ledger->post($id, 'issued', 10, $customer, 'S-2', null, $admin->id);

        $this->api($admin, 'PUT', "/api/inventory/crate-types/{$id}", ['status' => 'inactive'])
            ->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, '10 crate'));
        $this->assertDatabaseHas('inventory_crate_types', ['id' => $id, 'status' => 'active']);

        // Once everything is back, it can be switched off and on again.
        $ledger->post($id, 'returned', 10, $customer, null, null, $admin->id);
        $this->api($admin, 'PUT', "/api/inventory/crate-types/{$id}", ['status' => 'inactive'])->assertOk();
        $this->api($admin, 'PUT', "/api/inventory/crate-types/{$id}", ['status' => 'active'])->assertOk();
    }

    // ------------------------------------------------------------- delete

    public function test_an_unused_type_can_be_deleted_and_a_used_one_cannot(): void
    {
        $admin = $this->admin();
        $unused = (int) DB::table('inventory_crate_types')->where('name', 'Empty bottle')->value('id');
        $used = $this->crateId();
        app(CrateLedgerService::class)->post($used, 'issued', 1, $this->customer(), 'S-3', null, $admin->id);

        $this->api($admin, 'DELETE', "/api/inventory/crate-types/{$unused}")->assertOk();
        $this->assertDatabaseMissing('inventory_crate_types', ['id' => $unused]);

        $this->api($admin, 'DELETE', "/api/inventory/crate-types/{$used}")
            ->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'crate history'));
        $this->assertDatabaseHas('inventory_crate_types', ['id' => $used]);

        $this->api($admin, 'DELETE', '/api/inventory/crate-types/999999')->assertNotFound();
    }
}
