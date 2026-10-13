<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Staff a super admin creates used to belong to no business (the super admin has none), so
 * they saw an empty one. A super admin can now name the business the new account joins.
 */
class SuperAdminStaffPlacementTest extends TestCase
{
    use RefreshDatabase;

    private User $super;

    private User $asha;

    private User $juma;

    protected function setUp(): void
    {
        parent::setUp();

        $this->super = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
        $this->asha = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'name' => 'Asha']), 'inventory');
        $this->juma = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'name' => 'Juma']), 'rental');

        TenantContext::runAs($this->asha, fn () => DB::table('inventory_customers')->insert(['name' => 'Asha Duka', 'phone' => '0799111222', 'created_at' => now(), 'updated_at' => now()]));
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'New Officer', 'email' => 'officer@example.test', 'phone_number' => '0711000777',
            'password' => 'STAFFNEW1', 'password_confirmation' => 'STAFFNEW1',
            'role' => 'sales_officer', 'service_types' => ['inventory'],
        ], $overrides);
    }

    public function test_staff_created_by_the_super_admin_can_join_a_named_business(): void
    {
        $this->as($this->super, 'POST', '/api/admin/users', $this->payload(['business_owner_id' => $this->asha->id]))->assertCreated();

        $officer = User::where('email', 'officer@example.test')->firstOrFail();
        $this->assertSame((string) $this->asha->id, (string) $officer->created_by);
        $this->assertSame((string) $this->asha->id, $officer->accountHeadId(), 'they belong to Asha\'s business');

        $names = collect($this->as($officer, 'GET', '/api/inventory/customers')->assertOk()->json('data'))->pluck('name')->all();
        $this->assertContains('Asha Duka', $names, 'and see its data from the first day');
    }

    public function test_without_naming_a_business_nothing_changes(): void
    {
        $this->as($this->super, 'POST', '/api/admin/users', $this->payload())->assertCreated();

        $this->assertSame((string) $this->super->id, (string) User::where('email', 'officer@example.test')->value('created_by'));
    }

    public function test_an_owner_cannot_use_it_to_place_staff_in_another_business(): void
    {
        $this->as($this->asha, 'POST', '/api/admin/users', $this->payload(['business_owner_id' => $this->juma->id]))->assertCreated();

        $this->assertSame((string) $this->asha->id, (string) User::where('email', 'officer@example.test')->value('created_by'), 'ignored: they join the creator\'s own business');
    }

    public function test_it_only_accepts_a_real_owner_who_holds_the_services_asked_for(): void
    {
        $officer = User::factory()->create(['role' => 'sales_officer', 'is_active' => true, 'created_by' => $this->asha->id]);

        // Not an owner.
        $this->as($this->super, 'POST', '/api/admin/users', $this->payload(['business_owner_id' => $officer->id]))->assertStatus(422);
        // Not a real user.
        $this->as($this->super, 'POST', '/api/admin/users', $this->payload(['business_owner_id' => (string) \Illuminate\Support\Str::uuid()]))->assertStatus(422);
        // Juma has rental only: inventory staff cannot join his business.
        $this->as($this->super, 'POST', '/api/admin/users', $this->payload(['business_owner_id' => $this->juma->id]))->assertStatus(422);
        // An owner is never placed inside another business.
        $this->as($this->super, 'POST', '/api/admin/users', $this->payload(['role' => 'admin', 'business_owner_id' => $this->asha->id]))->assertStatus(422);

        $this->assertSame(0, User::where('email', 'officer@example.test')->count());
    }
}
