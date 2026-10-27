<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * A super admin places a staff member under a business admin: the person then works in that business, sees its data and nothing of
 * the old one. Only a super admin may do it, only under a real business admin that runs the service, and it is logged.
 */
class AssignToAdminTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function person(string $role, string $name, ?User $by = null, string $service = 'salon'): User
    {
        return $this->givenServices(User::factory()->create([
            'name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $by?->id,
            'phone_number' => '0728' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), $service);
    }

    private function api(User $as, string $method, string $uri, array $body = [], string $service = 'salon')
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeaders(['Authorization' => "Bearer {$token}", 'X-Service' => $service])->json($method, $uri, $body);
    }

    private function superAdmin(): User
    {
        return User::factory()->create(['name' => 'Super', 'role' => 'super_admin', 'is_active' => true, 'phone_number' => '0728999001']);
    }

    public function test_the_person_joins_the_admins_business_and_sees_its_goods(): void
    {
        $super = $this->superAdmin();
        $sammy = $this->person('admin', 'Sammy');
        $ivan = $this->person('accountant', 'Ivan', $super);
        $this->api($sammy, 'POST', '/api/inventory/products', ['name' => 'Knotless Braids', 'sku' => 'KNO1', 'quantity' => 1, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 22000, 'is_service' => true, 'duration_minutes' => 120])->assertCreated();

        $this->assertSame(0, $this->api($ivan, 'GET', '/api/inventory/products')->assertOk()->json('meta.total'), 'a business of his own, with nothing in it');

        $r = $this->api($super, 'PUT', "/api/admin/users/{$ivan->id}/assign-admin", ['admin_id' => $sammy->id, 'service' => 'salon'])->assertOk()->json();
        $this->assertTrue($r['data']['changed']);
        $this->assertSame($sammy->id, $ivan->fresh()->created_by);

        $names = collect($this->api($ivan->fresh(), 'GET', '/api/inventory/products')->assertOk()->json('data'))->pluck('name')->all();
        $this->assertSame(['Knotless Braids'], $names);

        $this->assertSame(1, DB::table('tenancy_reparent_log')->where('user_id', $ivan->id)->where('new_created_by', $sammy->id)->count());
        $this->assertSame(1, \App\Support\Tenancy\TenantContext::runAs($super, fn () => DB::table('inventory_audit_log')->where('action', 'assigned_to_admin')->count()), 'recorded in the audit trail');
    }

    public function test_the_person_signs_in_again_after_the_move(): void
    {
        $super = $this->superAdmin();
        $sammy = $this->person('admin', 'Sammy');
        $ivan = $this->person('accountant', 'Ivan', $super);
        $ivan->createToken('phone');

        $this->api($super, 'PUT', "/api/admin/users/{$ivan->id}/assign-admin", ['admin_id' => $sammy->id])->assertOk();

        $this->assertSame(0, $ivan->tokens()->count());
    }

    public function test_doing_it_twice_changes_nothing_more(): void
    {
        $super = $this->superAdmin();
        $sammy = $this->person('admin', 'Sammy');
        $ivan = $this->person('accountant', 'Ivan', $super);
        $this->api($super, 'PUT', "/api/admin/users/{$ivan->id}/assign-admin", ['admin_id' => $sammy->id])->assertOk();

        $again = $this->api($super, 'PUT', "/api/admin/users/{$ivan->id}/assign-admin", ['admin_id' => $sammy->id])->assertOk()->json();

        $this->assertFalse($again['data']['changed']);
        $this->assertSame(1, DB::table('tenancy_reparent_log')->where('user_id', $ivan->id)->count());
    }

    public function test_only_a_super_admin_may_do_it(): void
    {
        $this->superAdmin();
        $sammy = $this->person('admin', 'Sammy');
        $rose = $this->person('admin', 'Rose');
        $ivan = $this->person('accountant', 'Ivan', $rose);

        $this->api($rose, 'PUT', "/api/admin/users/{$ivan->id}/assign-admin", ['admin_id' => $sammy->id])->assertForbidden();
        $this->api($sammy, 'PUT', "/api/admin/users/{$ivan->id}/assign-admin", ['admin_id' => $sammy->id])->assertForbidden();
        $this->assertSame($rose->id, $ivan->fresh()->created_by);
    }

    public function test_the_target_must_be_a_business_admin_that_runs_the_service_and_the_person_must_be_staff(): void
    {
        $super = $this->superAdmin();
        $sammy = $this->person('admin', 'Sammy');
        $shopAdmin = $this->person('admin', 'Shop Admin', null, 'inventory');
        $clerk = $this->person('accountant', 'Clerk', $sammy);
        $ivan = $this->person('accountant', 'Ivan', $super);
        $driver = $this->person('driver', 'Driver', $sammy, 'transport');
        $go = fn (User $who, array $body) => $this->api($super, 'PUT', "/api/admin/users/{$who->id}/assign-admin", $body);

        $go($ivan, ['admin_id' => $clerk->id])->assertStatus(422);              // not a business admin
        $go($ivan, ['admin_id' => $super->id])->assertStatus(422);              // not a business admin
        $go($ivan, ['admin_id' => '00000000-0000-0000-0000-000000000000'])->assertStatus(422);
        $go($ivan, ['admin_id' => $shopAdmin->id, 'service' => 'salon'])->assertStatus(422); // that admin does not run the salon
        $go($sammy, ['admin_id' => $shopAdmin->id])->assertStatus(422);         // an owner is not placed under another
        $go($driver, ['admin_id' => $sammy->id])->assertStatus(422);            // an outside party
        $go($ivan, [])->assertStatus(422);

        $this->assertSame($super->id, $ivan->fresh()->created_by, 'nothing changed');
        $this->assertSame(0, DB::table('tenancy_reparent_log')->count());
    }
}
