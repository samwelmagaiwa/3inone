<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Access\Modules;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The owner of a salon decides, for each person, which sections they may open: switching one on adds it to what the role gives,
 * switching one off takes it back, and "back to the role" undoes both. What is off is off everywhere: the menu, and the server.
 */
class AccessModulesTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function salon(string $name = 'Glow'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function person(User $owner, string $role, string $name = 'Ivan Samwel'): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    /** The keys the person has right now, as the app is told at sign-in. */
    private function effective(User $who): array
    {
        return $this->api($who->refresh(), 'GET', '/api/auth/user')->assertOk()->json('data.user.effective_permissions');
    }

    private function modules(User $owner, User $who): array
    {
        return collect($this->api($owner, 'GET', "/api/admin/users/{$who->id}/access")->assertOk()->json('data.modules'))->keyBy('key')->all();
    }

    private function save(User $owner, User $who, array $on)
    {
        return $this->api($owner, 'PUT', "/api/admin/users/{$who->id}/access", ['on' => $on]);
    }

    private function allOn(User $owner, User $who, array $plus = [], array $minus = []): array
    {
        $on = collect($this->modules($owner, $who))->filter(fn ($m) => $m['on'])->keys()->all();

        return array_values(array_diff(array_unique(array_merge($on, $plus)), $minus));
    }

    public function test_the_accountant_starts_with_the_books_and_not_with_the_rest(): void
    {
        $owner = $this->salon();
        $ivan = $this->person($owner, 'accountant');
        $have = $this->effective($ivan);

        foreach (['inv_view_products', 'inv_create_products', 'inv_create_sales', 'inv_view_credit', 'inv_view_reports', 'inv_manage_expenses', 'inv_salon_money', 'inv_salon_team', 'inv_salon_insights', 'inv_salon_appointments'] as $key) {
            $this->assertContains($key, $have, $key);
        }
        foreach (['inv_salon_equipment', 'inv_salon_branch_stock', 'inv_salon_feedback', 'inv_salon_stylists', 'inv_salon_walkins', 'inv_salon_rebook', 'inv_manage_settings', 'inv_manage_products'] as $key) {
            $this->assertNotContains($key, $have, $key);
        }
    }

    public function test_the_owner_can_switch_a_section_on_and_the_server_opens_it(): void
    {
        $owner = $this->salon();
        $ivan = $this->person($owner, 'accountant');

        $this->api($ivan, 'GET', '/api/inventory/salon/equipment')->assertForbidden()->assertJsonPath('code', 'module_not_allowed');
        $this->assertFalse($this->modules($owner, $ivan)['inv_salon_equipment']['on']);

        $this->save($owner, $ivan, $this->allOn($owner, $ivan, ['inv_salon_equipment']))->assertOk();

        $this->assertContains('inv_salon_equipment', $this->effective($ivan));
        $this->api($ivan, 'GET', '/api/inventory/salon/equipment')->assertOk();
        $state = $this->modules($owner, $ivan)['inv_salon_equipment'];
        $this->assertTrue($state['on']);
        $this->assertTrue($state['added']);
        $this->assertFalse($state['from_role']);
    }

    public function test_the_owner_can_take_back_what_the_role_gives_and_put_it_back(): void
    {
        $owner = $this->salon();
        $ivan = $this->person($owner, 'accountant');
        $product = ['name' => 'Gel', 'sku' => 'GEL1', 'quantity' => 5, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 100, 'selling_price' => 500];

        $this->save($owner, $ivan, $this->allOn($owner, $ivan, [], ['inv_create_products']))->assertOk();

        $this->assertNotContains('inv_create_products', $this->effective($ivan));
        $this->api($ivan, 'POST', '/api/inventory/products', $product)->assertForbidden();
        $state = $this->modules($owner, $ivan)['inv_create_products'];
        $this->assertFalse($state['on']);
        $this->assertTrue($state['from_role']);
        $this->assertTrue($state['taken_back']);

        $this->save($owner, $ivan, $this->allOn($owner, $ivan, ['inv_create_products']))->assertOk();

        $this->assertContains('inv_create_products', $this->effective($ivan));
        $this->api($ivan, 'POST', '/api/inventory/products', $product)->assertCreated();
        $this->assertFalse($this->modules($owner, $ivan)['inv_create_products']['taken_back'], 'switching it on again clears the denial');
    }

    public function test_taking_back_the_reports_closes_the_monthly_report(): void
    {
        $owner = $this->salon();
        $ivan = $this->person($owner, 'accountant');
        $this->api($ivan, 'GET', '/api/inventory/monthly-report')->assertOk();

        $this->save($owner, $ivan, $this->allOn($owner, $ivan, [], ['inv_view_reports']))->assertOk();

        $this->api($ivan->refresh(), 'GET', '/api/inventory/monthly-report')->assertForbidden();
    }

    public function test_a_denial_wins_over_an_earlier_grant_and_over_the_role(): void
    {
        $owner = $this->salon();
        $ivan = $this->person($owner, 'accountant');
        $ivan->forceFill(['permissions' => ['inv_salon_equipment'], 'denied_permissions' => ['inv_salon_equipment', 'inv_view_credit']])->save();

        $this->assertFalse($ivan->refresh()->hasInventoryPermission('inv_salon_equipment'));
        $this->assertFalse($ivan->hasInventoryPermission('inv_view_credit'));
        $this->assertNotContains('inv_view_credit', $ivan->effectiveInventoryPermissions());
        $this->assertFalse($ivan->hasExplicitGrant('inv_salon_equipment'));
    }

    public function test_back_to_the_role_undoes_every_change_for_the_person(): void
    {
        $owner = $this->salon();
        $ivan = $this->person($owner, 'accountant');
        $this->save($owner, $ivan, $this->allOn($owner, $ivan, ['inv_salon_equipment', 'inv_salon_feedback'], ['inv_create_products', 'inv_salon_money']))->assertOk();

        $this->api($owner, 'POST', "/api/admin/users/{$ivan->id}/access/reset")->assertOk();

        $ivan->refresh();
        $this->assertSame([], $ivan->permissions);
        $this->assertSame([], $ivan->deniedPermissions());
        $this->assertContains('inv_create_products', $this->effective($ivan));
        $this->assertContains('inv_salon_money', $this->effective($ivan));
        $this->assertNotContains('inv_salon_equipment', $this->effective($ivan));
    }

    public function test_only_switches_of_the_persons_services_can_be_changed_and_nothing_else_is_touched(): void
    {
        $owner = $this->salon();
        $ivan = $this->person($owner, 'accountant');
        $ivan->forceFill(['permissions' => ['view_reports_transport']])->save();

        $this->save($owner, $ivan, $this->allOn($owner, $ivan, ['inv_view_purchasing']))->assertOk();

        $ivan->refresh();
        $this->assertContains('view_reports_transport', $ivan->permissions, 'a right of another service is kept');
        $this->assertNotContains('inv_view_purchasing', $ivan->permissions, 'purchasing is not a switch of a salon');
        $this->api($owner, 'PUT', "/api/admin/users/{$ivan->id}/access", ['on' => ['not_a_right']])->assertStatus(422);
    }

    public function test_nobody_else_can_configure_a_person_and_a_person_cannot_configure_themselves(): void
    {
        $owner = $this->salon('Glow');
        $other = $this->salon('Rival');
        $ivan = $this->person($owner, 'accountant');

        $this->save($other, $ivan, ['inv_salon_equipment'])->assertForbidden();
        $this->api($ivan, 'GET', "/api/admin/users/{$ivan->id}/access")->assertForbidden();
        $this->api($ivan, 'PUT', "/api/admin/users/{$ivan->id}/access", ['on' => ['inv_salon_equipment']])->assertForbidden();
        $this->save($owner, $owner, ['inv_salon_equipment'])->assertForbidden();
        $this->assertSame([], $ivan->refresh()->permissions ?? []);
    }

    public function test_a_stylist_keeps_the_diary_and_the_queue_but_not_the_money(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'hair_stylist', 'Asha');
        $have = $this->effective($asha);

        foreach (['inv_salon_appointments', 'inv_salon_walkins', 'inv_salon_rebook', 'inv_salon_stylists', 'inv_salon_team', 'inv_salon_feedback'] as $key) {
            $this->assertContains($key, $have, $key);
        }
        foreach (['inv_salon_money', 'inv_salon_insights', 'inv_salon_equipment', 'inv_view_reports'] as $key) {
            $this->assertNotContains($key, $have, $key);
        }
        $this->api($asha, 'GET', '/api/inventory/salon/queue')->assertOk();
        $this->api($asha, 'GET', '/api/inventory/salon/cashbook')->assertForbidden();
    }

    public function test_a_shop_is_not_asked_for_the_salon_sections(): void
    {
        $owner = $this->givenServices(User::factory()->create(['name' => 'Shop Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726000999']), 'inventory');
        $clerk = $this->givenServices(User::factory()->create(['name' => 'Clerk', 'role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id]), 'inventory');

        $keys = array_column(Modules::forServices(['inventory']), 'key');
        $this->assertNotContains('inv_salon_equipment', $keys);
        $this->assertContains('inv_view_purchasing', $keys);

        $token = $clerk->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        // The same controllers serve a shop (goods by branch): the salon switches never lock a shop out of them.
        $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json('GET', '/api/inventory/branch-stock')->assertStatus(200);
    }

    public function test_the_catalog_names_every_switch_in_both_languages_and_matches_the_known_rights(): void
    {
        foreach (Modules::catalog() as $m) {
            $this->assertContains($m['key'], User::INV_PERMISSIONS, $m['key']);
            $this->assertNotSame('', $m['en']);
            $this->assertNotSame('', $m['sw']);
            $this->assertNotEmpty($m['services']);
        }
        foreach (Modules::SALON as $key) {
            $this->assertContains($key, array_column(Modules::catalog(), 'key'), "{$key} is a switch");
        }
        $keys = array_column(Modules::catalog(), 'key');
        $this->assertSame($keys, array_values(array_unique($keys)), 'no switch twice');
    }

    public function test_the_change_is_written_in_the_audit_trail(): void
    {
        $owner = $this->salon();
        $ivan = $this->person($owner, 'accountant');
        $this->save($owner, $ivan, $this->allOn($owner, $ivan, ['inv_salon_equipment']))->assertOk();

        $log = $this->api($owner, 'GET', '/api/inventory/audit-log?entity_type=user')->assertOk()->json('data');

        $row = collect($log)->firstWhere('action', 'access_changed');
        $this->assertNotNull($row);
        $this->assertContains('inv_salon_equipment', $row['after']['permissions']);
        $this->assertStringContainsString('Ivan Samwel', $row['summary']);
    }
}
