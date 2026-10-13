<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Plan and valid_until: recorded for every business from day one, and -- only when billing is
 * switched on (BILLING_ENFORCE) -- the reason an unpaid business is held back after its grace
 * period. Held back means HTTP 402, never a sign-out: the device keeps its session, can still
 * see why, and everything works again the moment a super admin renews.
 */
class BillingTest extends TestCase
{
    use RefreshDatabase;

    private function owner(string $name, string $phone, ?string $validUntil, string $plan = 'basic'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => $name, 'role' => 'admin', 'is_active' => true,
            'phone_number' => $phone, 'password' => 'owner-pass-1',
        ]), 'transport', 'rental', 'inventory');

        Business::forOwnerId($owner->id)->update(['plan' => $plan, 'valid_until' => $validUntil]);

        return $owner;
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function login(User $user)
    {
        $this->app['auth']->forgetGuards();

        return $this->postJson('/api/auth/login', ['email' => $user->email, 'password' => 'owner-pass-1', 'phone_number' => $user->phone_number]);
    }

    private function superAdmin(): User
    {
        return User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
    }

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(now()->setDate(2026, 10, 15)->setTime(12, 0));
        config(['billing.grace_days' => 7]);
    }

    // -------------------------------------------------------------- the dates

    public function test_the_summary_counts_days_and_the_grace_period(): void
    {
        $business = fn (string $validUntil) => (new Business())->forceFill(['plan' => 'basic', 'valid_until' => $validUntil]);

        $future = $business('2026-10-20 23:59:59')->billingSummary();
        $this->assertSame(5, $future['days_left']);
        $this->assertFalse($future['is_expired']);
        $this->assertFalse($future['in_grace']);

        $today = $business('2026-10-15 23:59:59')->billingSummary();
        $this->assertSame(0, $today['days_left'], 'works through the end of the last day');
        $this->assertFalse($today['is_expired']);

        $late = $business('2026-10-10 23:59:59')->billingSummary();
        $this->assertSame(-5, $late['days_left']);
        $this->assertTrue($late['is_expired']);
        $this->assertTrue($late['in_grace'], 'five days over, seven allowed');

        $over = $business('2026-10-01 23:59:59')->billingSummary();
        $this->assertTrue($over['is_expired']);
        $this->assertFalse($over['in_grace']);

        $forever = (new Business())->forceFill(['plan' => 'free', 'valid_until' => null])->billingSummary();
        $this->assertNull($forever['days_left']);
        $this->assertFalse($forever['is_expired']);
        $this->assertFalse($forever['blocked']);
    }

    public function test_the_api_tells_the_owner_where_they_stand(): void
    {
        $owner = $this->owner('Alpha', '0722000001', '2026-10-18 23:59:59', 'standard');

        $this->as($owner, 'GET', '/api/business')->assertOk()
            ->assertJsonPath('data.billing.plan', 'standard')
            ->assertJsonPath('data.billing.days_left', 3)
            ->assertJsonPath('data.billing.is_expired', false)
            ->assertJsonPath('data.billing.enforced', false);
    }

    // ------------------------------------------------- enforcement switched off

    public function test_nothing_is_locked_while_enforcement_is_off(): void
    {
        $owner = $this->owner('Alpha', '0722000001', '2026-01-01 23:59:59'); // expired months ago

        $this->login($owner)->assertOk();
        $this->as($owner, 'GET', '/api/admin/vehicles')->assertOk();
        $this->as($owner, 'GET', '/api/business')->assertOk()->assertJsonPath('data.billing.is_expired', true)->assertJsonPath('data.billing.blocked', false);
    }

    // ------------------------------------------------- enforcement switched on

    public function test_a_business_past_its_grace_period_is_held_back_but_not_signed_out(): void
    {
        config(['billing.enforce' => true]);
        $owner = $this->owner('Alpha', '0722000001', '2026-10-10 23:59:59'); // five days over, seven allowed
        $token = $owner->createToken('device')->plainTextToken;

        $get = fn (string $uri) => $this->withHeader('Authorization', "Bearer {$token}")->getJson($uri);

        // Inside the grace period everything still works.
        $this->login($owner)->assertOk();
        $this->app['auth']->forgetGuards();
        $get('/api/admin/vehicles')->assertOk();

        // Two days later the grace period is over.
        $this->travelTo(now()->addDays(3));

        $this->app['auth']->forgetGuards();
        $this->login($owner)->assertStatus(402)->assertJsonPath('errors.code', 'subscription_expired');

        // A device that is already signed in is told so, with a code the app acts on...
        $this->app['auth']->forgetGuards();
        $get('/api/admin/vehicles')->assertStatus(402)->assertJsonPath('errors.code', 'subscription_expired')->assertJsonPath('errors.plan', 'basic');
        $this->app['auth']->forgetGuards();
        $get('/api/inventory/customers')->assertStatus(402);

        // ...but is NOT signed out: the session still exists and the owner can see why.
        $this->assertSame(1, $owner->tokens()->where('name', 'device')->count());
        $this->app['auth']->forgetGuards();
        $get('/api/business')->assertOk()->assertJsonPath('data.billing.blocked', true)->assertJsonPath('data.billing.is_expired', true);
        $this->app['auth']->forgetGuards();
        $get('/api/auth/user')->assertOk();
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$token}")->postJson('/api/auth/logout')->assertOk();
    }

    public function test_renewing_opens_everything_again_at_once_on_the_same_devices(): void
    {
        config(['billing.enforce' => true]);
        $owner = $this->owner('Alpha', '0722000001', '2026-09-01 23:59:59');
        $business = Business::forOwnerId($owner->id);
        $token = $owner->createToken('device')->plainTextToken;
        $get = fn (string $uri) => $this->withHeader('Authorization', "Bearer {$token}")->getJson($uri);

        $get('/api/admin/vehicles')->assertStatus(402);

        $this->app['auth']->forgetGuards();
        $this->as($this->superAdmin(), 'PUT', "/api/admin/businesses/{$business->id}", ['plan' => 'standard', 'valid_until' => '2027-01-31'])->assertOk();

        $this->app['auth']->forgetGuards();
        $get('/api/admin/vehicles')->assertOk();
        $this->app['auth']->forgetGuards();
        $this->login($owner)->assertOk();
    }

    public function test_staff_are_held_back_with_their_business_but_customers_are_not(): void
    {
        config(['billing.enforce' => true]);
        $owner = $this->owner('Alpha', '0722000001', '2026-09-01 23:59:59');
        $staff = $this->givenServices(User::factory()->create([
            'role' => 'manager', 'is_active' => true, 'created_by' => $owner->id,
            'permissions' => ['manage_vehicles_transport'], 'phone_number' => '0722000002', 'password' => 'owner-pass-1',
        ]), 'transport');
        $driver = $this->givenServices(User::factory()->create([
            'role' => 'driver', 'is_active' => true, 'created_by' => $owner->id,
            'phone_number' => '0722000003', 'password' => 'owner-pass-1',
        ]), 'transport');

        $this->as($staff, 'GET', '/api/admin/vehicles')->assertStatus(402);
        $this->login($staff)->assertStatus(402);

        // The business's driver is its customer: its own late payment does not take their records away.
        \App\Models\Driver::create(['user_id' => $driver->id, 'license_number' => 'LIC-1', 'license_expiry' => now()->addYear()->toDateString()]);
        $this->login($driver)->assertOk();
        $this->as($driver, 'GET', '/api/driver/profile')->assertOk();
    }

    public function test_a_super_admin_a_business_without_an_end_date_and_other_businesses_are_never_held_back(): void
    {
        config(['billing.enforce' => true]);
        $expired = $this->owner('Expired', '0722000001', '2026-01-01 23:59:59');
        $forever = $this->owner('Forever', '0722000002', null, 'free');
        $paid = $this->owner('Paid', '0722000003', '2027-12-31 23:59:59', 'premium');
        $super = $this->superAdmin();

        $this->as($expired, 'GET', '/api/admin/vehicles')->assertStatus(402);
        $this->as($forever, 'GET', '/api/admin/vehicles')->assertOk();
        $this->as($paid, 'GET', '/api/admin/vehicles')->assertOk();
        $this->as($super, 'GET', '/api/admin/businesses')->assertOk();
        $this->as($super, 'GET', '/api/admin/vehicles')->assertOk();
    }

    public function test_an_unauthenticated_call_is_untouched_by_billing(): void
    {
        config(['billing.enforce' => true]);
        $this->owner('Expired', '0722000001', '2026-01-01 23:59:59');

        $this->getJson('/api/admin/vehicles')->assertUnauthorized(); // 401, not 402
        $this->getJson('/api/health')->assertOk();
    }
}
