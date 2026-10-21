<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The salon decides who may do what by the person's RIGHTS (the role's own plus what the owner added for that person), the same
 * as the other services, never by the role's name. Giving a right opens the door; taking the extra back closes it again.
 */
class SalonAccessRightsTest extends TestCase
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

    private function person(User $owner, string $role, array $extra = []): User
    {
        return $this->givenServices(User::factory()->create(['name' => ucfirst($role), 'role' => $role, 'is_active' => true, 'created_by' => $owner->id, 'permissions' => $extra]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    private function give(User $owner, User $who, array $rights)
    {
        return $this->api($owner, 'PUT', "/api/admin/users/{$who->id}", ['permissions' => $rights]);
    }

    public function test_the_money_follows_the_reports_right_not_the_role_name(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'hair_stylist');
        $money = ['/api/inventory/salon/profit-loss', '/api/inventory/salon/overview', '/api/inventory/salon/payroll', '/api/inventory/salon/cashbook', '/api/inventory/salon/analytics', '/api/inventory/salon/export/sales'];

        foreach ($money as $uri) {
            $this->api($asha, 'GET', $uri)->assertForbidden();
        }
        $this->give($owner, $asha, ['inv_view_cash'])->assertSuccessful();
        $this->api($asha, 'GET', '/api/inventory/salon/profit-loss')->assertForbidden();

        $this->give($owner, $asha, ['inv_view_reports'])->assertSuccessful();
        foreach ($money as $uri) {
            $this->api($asha->refresh(), 'GET', $uri)->assertOk();
        }

        $this->give($owner, $asha, [])->assertSuccessful();
        foreach ($money as $uri) {
            $this->api($asha->refresh(), 'GET', $uri)->assertForbidden();
        }
    }

    public function test_setting_the_salon_up_follows_the_settings_right_so_the_accountant_cannot_by_default(): void
    {
        $owner = $this->salon();
        $acc = $this->person($owner, 'accountant');

        $this->api($acc, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertForbidden();
        $this->api($acc, 'POST', '/api/inventory/salon/vouchers', ['code' => 'WELCOME', 'kind' => 'percent', 'value' => 10])->assertForbidden();
        $this->api($acc, 'POST', '/api/inventory/salon/campaigns', ['segment' => 'all', 'message' => 'Karibu tena saluni'])->assertForbidden();
        $this->api($acc, 'PUT', '/api/inventory/salon/settings', ['daily_summary' => true])->assertForbidden();

        $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertCreated();

        $this->give($owner, $acc, ['inv_manage_settings'])->assertSuccessful();
        $this->api($acc->refresh(), 'POST', '/api/inventory/salon/branches', ['name' => 'Second'])->assertCreated();
        $this->api($acc, 'POST', '/api/inventory/salon/vouchers', ['code' => 'WELCOME', 'kind' => 'percent', 'value' => 10])->assertCreated();
        $this->api($acc, 'PUT', '/api/inventory/salon/settings', ['daily_summary' => true])->assertOk();
    }

    public function test_the_owner_and_the_accountant_keep_what_their_role_gives_and_a_stylist_does_not_have_it(): void
    {
        $owner = $this->salon();
        $acc = $this->person($owner, 'accountant');
        $asha = $this->person($owner, 'hair_stylist');

        foreach (['/api/inventory/salon/profit-loss', '/api/inventory/salon/cashbook', '/api/inventory/salon/branch-stock'] as $uri) {
            $this->api($owner, 'GET', $uri)->assertOk();
            $this->api($acc, 'GET', $uri)->assertOk();
        }
        $this->api($asha, 'GET', '/api/inventory/salon/profit-loss')->assertForbidden();
        $this->api($asha, 'GET', '/api/inventory/salon/cashbook')->assertForbidden();
    }

    public function test_spending_is_approved_by_whoever_holds_the_reports_right(): void
    {
        $owner = $this->salon();
        $helper = $this->person($owner, 'hair_stylist', ['inv_view_expenses', 'inv_manage_expenses']);
        $body = ['category' => 'transport', 'description' => 'Taxi', 'amount' => 5000, 'expense_date' => now('Africa/Dar_es_Salaam')->toDateString()];

        $this->api($helper, 'POST', '/api/inventory/expenses', $body)->assertCreated()->assertJsonPath('data.status', 'pending');

        $this->give($owner, $helper, ['inv_view_expenses', 'inv_manage_expenses', 'inv_view_reports'])->assertSuccessful();
        $this->api($helper->refresh(), 'POST', '/api/inventory/expenses', $body)->assertCreated()->assertJsonPath('data.status', 'approved');
    }

    public function test_a_person_sees_everyones_sales_only_with_the_reports_right(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'hair_stylist');
        $bahati = $this->person($owner, 'nail_technician');
        $svc = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Braids', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 10000, 'duration_minutes' => 60])->assertCreated()->json('data.id');
        foreach ([$asha, $bahati] as $who) {
            $this->api($who, 'POST', '/api/inventory/sales', [
                'payment_status' => 'paid', 'subtotal' => 10000, 'discount' => 0, 'tax' => 0, 'total' => 10000, 'paid_total' => 10000,
                'items' => [['product_id' => $svc, 'quantity' => 1, 'unit_price' => 10000, 'staff_id' => (string) $who->id]], 'payments' => [['amount' => 10000, 'method' => 'cash']],
            ])->assertCreated();
        }

        $this->assertCount(1, $this->api($asha, 'GET', '/api/inventory/sales')->json('data'));
        $this->give($owner, $asha, ['inv_view_reports'])->assertSuccessful();
        $this->assertCount(2, $this->api($asha->refresh(), 'GET', '/api/inventory/sales')->json('data'));
    }

    public function test_one_salons_owner_cannot_give_rights_to_another_salons_person(): void
    {
        $one = $this->salon('One');
        $two = $this->salon('Two');
        $theirs = $this->person($two, 'hair_stylist');

        $this->give($one, $theirs, ['inv_view_reports'])->assertForbidden();
        $this->assertFalse($theirs->refresh()->hasInventoryPermission('inv_view_reports'));
    }
}
