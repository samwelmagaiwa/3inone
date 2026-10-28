<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\BusinessRegistration;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * What kind of stock business is it -- retail, wholesale, mixed or depot? The owner says so when registering.
 * It only decides what a NEW business's inventory settings start with (crates or not, which price the till
 * uses); it moves no data, and a depot -- every business that existed before types -- is exactly as it was.
 */
class InventoryTypeTest extends TestCase
{
    use RefreshDatabase;

    private function superAdmin(): User
    {
        return User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
    }

    private function api(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'Asha Owner', 'business_name' => 'Asha Shop', 'email' => 'asha@example.test',
            'phone_number' => '0743519100', 'password' => 'secret-pass-1', 'password_confirmation' => 'secret-pass-1',
            'requested_services' => ['inventory'],
        ], $overrides);
    }

    private function register(array $overrides = []): BusinessRegistration
    {
        $payload = $this->payload($overrides);
        $this->postJson('/api/auth/register', $payload)->assertCreated();
        $this->postJson('/api/auth/register/verify-phone', [
            'email' => $payload['email'], 'code' => $this->sms->lastCodeFor($payload['phone_number']) ?? '000000',
        ])->assertOk();

        return BusinessRegistration::whereHas('user', fn ($q) => $q->where('email', $payload['email']))->firstOrFail();
    }

    private function approve(BusinessRegistration $registration, array $extra = [])
    {
        return $this->api($this->superAdmin(), 'POST', "/api/admin/registrations/{$registration->id}/approve",
            array_merge(['service_types' => ['inventory']], $extra));
    }

    /** Settings of a business, as stored (not as defaulted). */
    private function stored(User $owner): array
    {
        return TenantContext::runAs($owner, fn () => DB::table('inventory_settings')->pluck('value', 'key')->all());
    }

    /** An owner who already has inventory, of this kind (null = never said, like every business before types). */
    private function owner(?string $type): User
    {
        $owner = User::factory()->create(['role' => 'admin', 'is_active' => true]);
        Business::forOwnerId($owner->id)->update(['inventory_type' => $type]);

        return $this->givenServices($owner, 'inventory');
    }

    // ----------------------------------------------------------- registering

    public function test_registering_for_inventory_needs_the_kind_of_business(): void
    {
        $this->postJson('/api/auth/register', $this->payload())
            ->assertStatus(422)->assertJsonValidationErrors('inventory_type');
        $this->postJson('/api/auth/register', $this->payload(['inventory_type' => 'bakery']))
            ->assertStatus(422)->assertJsonValidationErrors('inventory_type');
    }

    public function test_every_kind_is_accepted_and_kept_on_the_registration(): void
    {
        foreach (['retail', 'wholesale', 'mixed', 'depot'] as $i => $type) {
            $registration = $this->register([
                'email' => "owner{$i}@example.test", 'phone_number' => '07430000' . (10 + $i), 'inventory_type' => $type,
            ]);

            $this->assertSame($type, $registration->inventory_type);
            $this->assertSame($type, Business::forOwnerId($registration->user_id)->inventory_type, 'and on the business record');
        }
    }

    public function test_a_business_that_does_not_ask_for_inventory_is_not_asked_and_keeps_none(): void
    {
        $this->postJson('/api/auth/register', $this->payload(['requested_services' => ['rental']]))->assertCreated();
        $this->assertNull(BusinessRegistration::firstOrFail()->inventory_type);

        // Even if one is sent, it means nothing without inventory.
        $this->postJson('/api/auth/register', $this->payload([
            'email' => 'two@example.test', 'phone_number' => '0743000022', 'requested_services' => ['transport'], 'inventory_type' => 'retail',
        ]))->assertCreated();
        $this->assertNull(BusinessRegistration::whereHas('user', fn ($q) => $q->where('email', 'two@example.test'))->firstOrFail()->inventory_type);
    }

    public function test_the_super_admin_sees_the_kind_and_may_correct_it_at_approval(): void
    {
        $registration = $this->register(['inventory_type' => 'retail']);

        $this->api($this->superAdmin(), 'GET', "/api/admin/registrations/{$registration->id}")
            ->assertOk()->assertJsonPath('data.inventory_type', 'retail');

        $this->approve($registration, ['inventory_type' => 'wholesale'])->assertOk()->assertJsonPath('data.inventory_type', 'wholesale');
        $this->assertSame('wholesale', Business::forOwnerId($registration->user_id)->inventory_type);

        $this->approve($this->register(['email' => 'x@example.test', 'phone_number' => '0743000033', 'inventory_type' => 'retail']), ['inventory_type' => 'bakery'])
            ->assertStatus(422)->assertJsonValidationErrors('inventory_type');
    }

    // ------------------------------------------------------- what each starts with

    public function test_each_kind_starts_its_inventory_with_its_own_settings(): void
    {
        $expected = [
            'depot' => ['use_crates' => '1', 'sale_tier' => 'product'],
            'retail' => ['use_crates' => '0', 'sale_tier' => 'retail'],
            'wholesale' => ['use_crates' => '0', 'sale_tier' => 'wholesale'],
            'mixed' => ['use_crates' => '0', 'sale_tier' => 'retail'],
        ];

        foreach ($expected as $type => $settings) {
            $registration = $this->register([
                'email' => "{$type}@example.test", 'phone_number' => '07430' . random_int(10000, 99999), 'inventory_type' => $type,
            ]);
            $this->approve($registration)->assertOk();

            $owner = User::find($registration->user_id);
            $stored = $this->stored($owner);
            foreach ($settings as $key => $value) {
                $this->assertSame($value, $stored[$key], "{$type}: {$key}");
            }
            $this->assertSame('1', $stored['prices_include_vat'], 'VAT-inclusive by default for every kind');
            // Everything else about the settings is the same for all of them.
            $this->assertSame(count(\App\Support\InventoryDefaults::SETTINGS), count($stored), $type);
        }
    }

    public function test_a_business_that_never_chose_a_kind_is_a_depot_exactly_as_before(): void
    {
        $legacy = $this->owner(null);

        $settings = $this->api($legacy, 'GET', '/api/inventory/settings')->assertOk()->json('data');
        $this->assertSame('depot', $settings['inventory_type']);
        $this->assertSame('1', $settings['use_crates']);
        $this->assertSame('product', $settings['sale_tier']);
        // ...but the app is told the kind was never chosen, so it speaks in general words and asks the owner to choose
        $this->assertSame('0', $settings['inventory_type_chosen']);
    }

    public function test_a_chosen_kind_a_salon_and_a_super_admin_count_as_chosen(): void
    {
        $this->assertSame('1', $this->api($this->owner('depot'), 'GET', '/api/inventory/settings')->json('data.inventory_type_chosen'), 'a depot that said so');
        $this->assertSame('1', $this->api($this->owner('retail'), 'GET', '/api/inventory/settings')->json('data.inventory_type_chosen'));
        $this->assertSame('1', $this->api($this->superAdmin(), 'GET', '/api/inventory/settings')->json('data.inventory_type_chosen'));
    }

    public function test_the_kind_is_part_of_the_business_and_a_super_admin_has_none(): void
    {
        $retail = $this->owner('retail');

        $this->api($retail, 'GET', '/api/inventory/settings')->assertOk()->assertJsonPath('data.inventory_type', 'retail');
        $this->api($retail, 'GET', '/api/business')->assertOk()->assertJsonPath('data.inventory_type', 'retail');
        $this->api($this->superAdmin(), 'GET', '/api/inventory/settings')->assertOk()->assertJsonPath('data.inventory_type', 'retail');
    }

    // ---------------------------------------------------------- changing it later

    public function test_changing_the_kind_moves_only_settings_that_still_hold_the_old_kinds_values(): void
    {
        $owner = $this->owner('depot');
        $this->assertSame('1', $this->stored($owner)['use_crates']);

        // The owner has already customised how the till prices things.
        $this->api($owner, 'PUT', '/api/inventory/settings', ['sale_tier' => 'wholesale'])->assertOk();

        $this->api($owner, 'PUT', '/api/business', ['inventory_type' => 'retail'])->assertOk()->assertJsonPath('data.inventory_type', 'retail');

        $stored = $this->stored($owner);
        $this->assertSame('0', $stored['use_crates'], 'still the depot starting value, so it follows the new kind');
        $this->assertSame('wholesale', $stored['sale_tier'], 'what the owner set is theirs and is never overwritten');
    }

    public function test_changing_the_kind_never_touches_stock_prices_or_sales(): void
    {
        $owner = $this->owner('depot');
        $this->api($owner, 'POST', '/api/inventory/products', [
            'name' => 'Soda', 'cost_price' => 500, 'selling_price' => 800, 'quantity' => 40, 'min_stock' => 5, 'status' => 'active',
        ])->assertCreated();
        $before = TenantContext::runAs($owner, fn () => [
            DB::table('inventory_products')->get()->toArray(), DB::table('inventory_product_prices')->get()->toArray(),
        ]);

        $this->api($owner, 'PUT', '/api/business', ['inventory_type' => 'wholesale'])->assertOk();
        $this->api($owner, 'PUT', '/api/business', ['inventory_type' => 'mixed'])->assertOk();

        $after = TenantContext::runAs($owner, fn () => [
            DB::table('inventory_products')->get()->toArray(), DB::table('inventory_product_prices')->get()->toArray(),
        ]);
        $this->assertEquals($before, $after);
    }

    public function test_only_a_real_kind_is_accepted_and_the_super_admin_can_correct_it_too(): void
    {
        $owner = $this->owner('retail');
        $business = Business::forOwnerId($owner->id);

        $this->api($owner, 'PUT', '/api/business', ['inventory_type' => 'bakery'])->assertStatus(422)->assertJsonValidationErrors('inventory_type');
        $this->assertSame('retail', $business->fresh()->inventory_type);

        $this->api($this->superAdmin(), 'PUT', "/api/admin/businesses/{$business->id}", ['inventory_type' => 'mixed'])
            ->assertOk()->assertJsonPath('data.inventory_type', 'mixed');
        $this->assertSame('mixed', $business->fresh()->inventory_type);
    }

    public function test_one_business_changing_its_kind_leaves_another_alone(): void
    {
        $alpha = $this->owner('depot');
        $bravo = $this->owner('depot');

        $this->api($alpha, 'PUT', '/api/business', ['inventory_type' => 'retail'])->assertOk();

        $this->assertSame('0', $this->stored($alpha)['use_crates']);
        $this->assertSame('1', $this->stored($bravo)['use_crates']);
        $this->assertSame('depot', Business::forOwnerId($bravo->id)->inventory_type);
    }

    // ----------------------------------------------------------------- the upgrade

    public function test_the_upgrade_marks_every_business_that_already_uses_inventory_as_a_depot(): void
    {
        $uses = $this->owner(null);
        $noInventory = $this->givenServices(User::factory()->create(['role' => 'landlord', 'is_active' => true]), 'rental');
        DB::table('businesses')->update(['inventory_type' => null]);

        $migration = require database_path('migrations/2026_10_16_000100_add_inventory_type_to_businesses.php');
        $migration->up();

        $this->assertSame('depot', Business::forOwnerId($uses->id)->inventory_type);
        $this->assertNull(Business::forOwnerId($noInventory->id)->inventory_type, 'no inventory, nothing to mark');

        $migration->up(); // again
        $this->assertSame('depot', Business::forOwnerId($uses->id)->inventory_type);
    }
}
