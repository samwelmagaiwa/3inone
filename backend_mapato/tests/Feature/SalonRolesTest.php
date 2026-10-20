<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The salon's roles: receptionist, cashier, hair stylist, nail technician, lash and makeup artist, accountant, stock
 * manager. What each may do, and above all what each may NOT see: a stylist never sees anyone else's income, pay or
 * diary; reception books but sees no money; only the owner, managers and accountants see the business's money.
 */
class SalonRolesTest extends TestCase
{
    use RefreshDatabase;

    private const SALON_ROLES = ['receptionist', 'cashier', 'hair_stylist', 'nail_technician', 'lash_makeup_artist', 'accountant', 'stock_manager'];

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function salon(string $name = 'Glow Salon'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0723' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function person(User $owner, string $name, string $role): User
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

    private function service(User $as, string $name, int $price): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price, 'duration_minutes' => 60])->assertCreated()->json('data.id');
    }

    private function sell(User $as, int $product, int $price, ?User $stylist = null)
    {
        return $this->api($as, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => $price, 'discount' => 0, 'tax' => 0, 'total' => $price, 'paid_total' => $price,
            'items' => [array_filter(['product_id' => $product, 'quantity' => 1, 'unit_price' => $price, 'staff_id' => $stylist ? (string) $stylist->id : null])],
        ]);
    }

    public function test_every_salon_role_can_be_given_to_a_new_person_and_means_the_salon(): void
    {
        $owner = $this->salon();

        foreach (self::SALON_ROLES as $i => $role) {
            $res = $this->api($owner, 'POST', '/api/admin/users', [
                'name' => "Person {$i}", 'email' => "p{$i}@example.test", 'password' => 'password123', 'password_confirmation' => 'password123',
                'phone_number' => '07110000' . str_pad((string) $i, 2, '0', STR_PAD_LEFT), 'role' => $role, 'service_types' => ['salon'],
            ]);
            $res->assertSuccessful();
            $user = User::where('email', "p{$i}@example.test")->firstOrFail();
            $this->assertSame($role, $user->role, $role);
            $this->assertContains('salon', $user->allowedServiceTypes(), $role);
        }
    }

    public function test_a_role_nobody_made_is_still_refused(): void
    {
        $owner = $this->salon();

        $this->api($owner, 'POST', '/api/admin/users', [
            'name' => 'X', 'email' => 'x@example.test', 'password' => 'password123', 'password_confirmation' => 'password123',
            'phone_number' => '0711999999', 'role' => 'wizard', 'service_types' => ['salon'],
        ])->assertStatus(422);
    }

    public function test_what_each_role_may_do_in_the_inventory_engine(): void
    {
        $owner = $this->salon();
        $expect = [
            'receptionist' => ['inv_create_sales' => true, 'inv_view_credit' => true, 'inv_view_reports' => false, 'inv_view_expenses' => false, 'inv_manage_stock' => false],
            'cashier' => ['inv_create_sales' => true, 'inv_manage_sales' => true, 'inv_view_cash' => true, 'inv_view_reports' => false, 'inv_manage_expenses' => false],
            'hair_stylist' => ['inv_create_sales' => true, 'inv_view_reports' => false, 'inv_view_expenses' => false, 'inv_view_cash' => false, 'inv_manage_settings' => false],
            'nail_technician' => ['inv_create_sales' => true, 'inv_view_reports' => false, 'inv_manage_products' => false],
            'lash_makeup_artist' => ['inv_create_sales' => true, 'inv_view_reports' => false, 'inv_manage_products' => false],
            'accountant' => ['inv_view_reports' => true, 'inv_view_expenses' => true, 'inv_manage_expenses' => true, 'inv_view_cash' => true, 'inv_create_sales' => false, 'inv_manage_stock' => false],
            'stock_manager' => ['inv_manage_products' => true, 'inv_manage_stock' => true, 'inv_view_purchasing' => true, 'inv_view_reports' => false, 'inv_create_sales' => false],
        ];

        foreach ($expect as $role => $perms) {
            $user = $this->person($owner, ucfirst($role), $role);
            foreach ($perms as $perm => $allowed) {
                $this->assertSame($allowed, $user->hasInventoryPermission($perm), "{$role} / {$perm}");
            }
        }
    }

    public function test_reception_books_but_a_stylist_only_works_her_own_diary(): void
    {
        $owner = $this->salon();
        $desk = $this->person($owner, 'Desk', 'receptionist');
        $asha = $this->person($owner, 'Asha', 'hair_stylist');
        $bahati = $this->person($owner, 'Bahati', 'nail_technician');
        $wash = $this->service($owner, 'Wash', 5000);
        $book = fn (User $who, ?User $for, string $name) => $this->api($who, 'POST', '/api/inventory/salon/appointments', array_filter([
            'client_name' => $name, 'starts_at' => '2026-10-08 10:00', 'services' => [['product_id' => $wash]], 'staff_id' => $for ? (string) $for->id : null,
        ]));

        $mine = $book($desk, $asha, 'Neema')->assertCreated()->json('data.id');
        $theirs = $book($desk, $bahati, 'Rehema')->assertCreated()->json('data.id');
        $book($owner, null, 'Walk-in')->assertCreated();

        $this->api($asha, 'POST', '/api/inventory/salon/appointments', ['client_name' => 'Self booked', 'starts_at' => '2026-10-08 12:00', 'services' => [['product_id' => $wash]]])->assertStatus(403);
        $this->api($asha, 'PUT', "/api/inventory/salon/appointments/{$mine}", ['notes' => 'x'])->assertStatus(403);

        $ashasDay = $this->api($asha, 'GET', '/api/inventory/salon/appointments?date=2026-10-08')->assertOk()->json('data');
        $this->assertSame(['Neema'], array_column($ashasDay, 'client_name'), 'only her own');
        $this->assertCount(3, $this->api($desk, 'GET', '/api/inventory/salon/appointments?date=2026-10-08')->json('data'));

        $this->api($asha, 'POST', "/api/inventory/salon/appointments/{$mine}/status", ['status' => 'in_progress'])->assertOk();
        $this->api($asha, 'POST', "/api/inventory/salon/appointments/{$theirs}/status", ['status' => 'in_progress'])->assertStatus(403);
    }

    public function test_a_stylist_sees_her_own_sales_and_commission_never_anyone_elses(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha', 'hair_stylist');
        $bahati = $this->person($owner, 'Bahati', 'nail_technician');
        $cashier = $this->person($owner, 'Cash', 'cashier');
        $braids = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Braids', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 40000, 'commission_percent' => 10])->json('data.id');
        $this->sell($asha, $braids, 40000, $asha)->assertCreated();
        $this->sell($bahati, $braids, 40000, $bahati)->assertCreated();

        $report = $this->api($asha, 'GET', '/api/inventory/salon/stylists')->assertOk()->json('data.stylists');
        $this->assertSame(['Asha'], array_column($report, 'name'));
        $this->assertSame(4000, $report[0]['commission']);
        $this->api($asha, 'GET', "/api/inventory/salon/stylists/{$bahati->id}/transactions")->assertStatus(403);
        $this->assertCount(1, $this->api($asha, 'GET', '/api/inventory/sales')->json('data'), 'her own sales only');
        $this->assertCount(2, $this->api($cashier, 'GET', '/api/inventory/sales')->json('data'), 'the cashier works across everyone\'s');
    }

    public function test_only_the_owner_managers_and_accountants_see_the_money_and_pay(): void
    {
        $owner = $this->salon();
        $uris = ['/api/inventory/salon/profit-loss', '/api/inventory/salon/payroll', '/api/inventory/salon/payouts', '/api/inventory/salon/overview', '/api/inventory/salon/staff-profiles'];

        foreach (['manager' => true, 'accountant' => true, 'receptionist' => false, 'cashier' => false, 'hair_stylist' => false, 'nail_technician' => false, 'lash_makeup_artist' => false, 'stock_manager' => false] as $role => $sees) {
            $user = $this->person($owner, ucfirst($role), $role);
            foreach ($uris as $uri) {
                $this->api($user, 'GET', $uri)->assertStatus($sees ? 200 : 403);
            }
        }
    }

    public function test_the_accountant_approves_spending_and_sees_everyones_results_but_cannot_sell(): void
    {
        $owner = $this->salon();
        $accountant = $this->person($owner, 'Acc', 'accountant');
        $stock = $this->person($owner, 'Stock', 'stock_manager');
        $asha = $this->person($owner, 'Asha', 'hair_stylist');
        $braids = $this->service($owner, 'Braids', 40000);
        $this->sell($asha, $braids, 40000, $asha)->assertCreated();

        $made = $this->api($accountant, 'POST', '/api/inventory/expenses', ['category' => 'rent', 'description' => 'Rent', 'amount' => 1000, 'expense_date' => '2026-10-01'])->assertCreated();
        $made->assertJsonPath('data.status', 'approved');
        $this->api($stock, 'POST', '/api/inventory/expenses', ['category' => 'rent', 'description' => 'Nope', 'amount' => 1000, 'expense_date' => '2026-10-01'])->assertStatus(403);
        $this->assertCount(1, $this->api($accountant, 'GET', '/api/inventory/salon/stylists')->json('data.stylists'));
        $this->assertCount(0, array_filter([$this->sell($accountant, $braids, 40000)->status() === 403 ? null : 1]), 'an accountant does not ring up sales');
    }
}
