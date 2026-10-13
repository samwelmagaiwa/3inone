<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\Pagination;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Tests\TestCase;

/**
 * Who may call what: login throttling, deactivated accounts, per-service
 * grants, grant scoping when creating staff, and the forced password change.
 * These use real bearer tokens (not actingAs) so the Sanctum token checks run.
 */
class AccessControlTest extends TestCase
{
    use RefreshDatabase;

    private function user(string $role, array $permissions = [], array $services = [], array $extra = []): User
    {
        $user = User::factory()->create(array_merge([
            'role' => $role,
            'permissions' => $permissions,
            'is_active' => true,
        ], $extra));

        foreach ($services as $service) {
            $user->services()->create(['service_type' => $service]);
        }

        return $user;
    }

    /** One request as $user's bearer token, with a fresh auth guard (as a real request would have). */
    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    // ------------------------------------------------------------- login

    public function test_login_is_throttled_per_email_and_ip(): void
    {
        $attempt = fn (string $email) => $this->postJson('/api/auth/login', [
            'email' => $email, 'password' => 'wrong', 'phone_number' => '0712345678',
        ])->status();

        for ($i = 0; $i < 10; $i++) {
            $this->assertNotSame(429, $attempt('victim@example.test'));
        }
        $this->assertSame(429, $attempt('victim@example.test'));

        // A different account from the same IP is unaffected.
        $this->assertNotSame(429, $attempt('someone.else@example.test'));
    }

    /** Ten bad logins for one email from the given client, as seen through the nginx proxy or directly. */
    private function hammerLogin(string $email, string $remoteAddr, ?string $forwardedFor, int $times = 11): int
    {
        $status = 0;
        for ($i = 0; $i < $times; $i++) {
            $headers = $forwardedFor ? ['X-Forwarded-For' => $forwardedFor] : [];
            $status = $this->withServerVariables(['REMOTE_ADDR' => $remoteAddr])
                ->withHeaders($headers)
                ->postJson('/api/auth/login', ['email' => $email, 'password' => 'wrong', 'phone_number' => '0712345678'])
                ->status();
        }

        return $status;
    }

    public function test_behind_the_proxy_each_real_client_gets_its_own_login_limit(): void
    {
        // Every request reaches the app from the Docker gateway; the real client is in X-Forwarded-For.
        $this->assertSame(429, $this->hammerLogin('victim@example.test', '172.20.0.1', '198.51.100.7'));

        // The same email from a different real client is not locked out by the attacker.
        $this->assertNotSame(429, $this->hammerLogin('victim@example.test', '172.20.0.1', '203.0.113.9', times: 1));
    }

    public function test_a_public_client_cannot_dodge_the_limit_by_spoofing_x_forwarded_for(): void
    {
        $statuses = [];
        for ($i = 0; $i < 12; $i++) {
            $statuses[] = $this->hammerLogin('victim@example.test', '203.0.113.50', "198.51.100.{$i}", times: 1);
        }

        $this->assertSame(429, end($statuses));
    }

    public function test_removed_otp_routes_are_gone(): void
    {
        $this->assertContains($this->postJson('/api/auth/verify-otp')->status(), [404, 405]);
        $this->assertContains($this->postJson('/api/auth/resend-otp')->status(), [404, 405]);
    }

    // ------------------------------------------------- deactivated accounts

    public function test_token_of_a_deactivated_account_is_rejected_everywhere(): void
    {
        $staff = $this->user('sales_officer', services: ['inventory']);
        $token = $staff->createToken('test')->plainTextToken;

        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/auth/user')->assertOk();

        $staff->forceFill(['is_active' => false])->save();

        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/auth/user')->assertUnauthorized();
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/inventory/products')->assertUnauthorized();
    }

    public function test_deactivating_or_deleting_a_user_revokes_their_tokens(): void
    {
        $admin = $this->user('admin', services: ['inventory']);
        $staff = $this->user('sales_officer', services: ['inventory'], extra: ['created_by' => $admin->id]);
        $staff->createToken('a');

        $this->as($admin, 'PUT', "/api/admin/users/{$staff->id}", ['is_active' => false])->assertOk();
        $this->assertSame(0, $staff->tokens()->count());

        $staff->forceFill(['is_active' => true])->save();
        $staff->createToken('b');
        $this->as($admin, 'DELETE', "/api/admin/users/{$staff->id}")->assertOk();
        $this->assertSame(0, $staff->tokens()->count());
    }

    // -------------------------------------------------------- token lifetime

    public function test_tokens_do_not_expire_by_age_only_after_a_very_long_time_unused(): void
    {
        $staff = $this->user('sales_officer', services: ['inventory']);
        $token = $staff->createToken('t')->plainTextToken;

        // 29 and then 31 days after sign-in: still signed in (there is no fixed lifetime any more).
        $this->travel(29)->days();
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/auth/user')->assertOk();

        $this->travel(2)->days();
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/auth/user')->assertOk();

        // A device nobody touches for over a year is the only thing that times out.
        $this->travel(400)->days();
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/auth/user')->assertUnauthorized();
    }

    public function test_refresh_issues_a_fresh_token_and_retires_the_old_one_after_a_grace_period(): void
    {
        $staff = $this->user('sales_officer', services: ['inventory']);
        $old = $staff->createToken('t')->plainTextToken;

        $this->app['auth']->forgetGuards();
        $new = $this->withHeader('Authorization', "Bearer {$old}")
            ->postJson('/api/auth/refresh')->assertOk()->json('data.token');
        $this->assertNotEmpty($new);

        // The old token still works for the grace window (a lost response must not log the user out)...
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$old}")->getJson('/api/auth/user')->assertOk();

        // ...it is a generous window (days, so a phone that was offline does not wake up signed out)...
        $this->travel(11)->minutes();
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$old}")->getJson('/api/auth/user')->assertOk();

        // ...but finite, so retired tokens do not pile up; the new one carries on regardless.
        $this->travel(8)->days();
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$old}")->getJson('/api/auth/user')->assertUnauthorized();
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$new}")->getJson('/api/auth/user')->assertOk();
    }

    // ----------------------------------------------- payment receipts / roles

    public function test_payment_receipts_need_admin_or_the_payments_grant(): void
    {
        $this->getJson('/api/payment-receipts')->assertUnauthorized();

        $this->as($this->user('sales_officer', services: ['inventory']), 'GET', '/api/payment-receipts')->assertForbidden();
        $this->as($this->user('viewer', ['manage_vehicles_transport']), 'GET', '/api/payment-receipts')->assertForbidden();

        $this->assertNotSame(403, $this->as($this->user('viewer', ['manage_payments_transport'], ['transport']), 'GET', '/api/payment-receipts')->status());
        $this->assertNotSame(403, $this->as($this->user('admin', services: ['transport']), 'GET', '/api/payment-receipts')->status());
    }

    // ------------------------------------------- rental / transport grants

    public function test_a_service_grant_opens_only_its_own_routes(): void
    {
        $vehicles = $this->user('viewer', ['manage_vehicles_transport'], ['transport']);
        $this->assertNotSame(403, $this->as($vehicles, 'GET', '/api/admin/vehicles')->status());
        $this->as($vehicles, 'GET', '/api/admin/drivers')->assertForbidden();
        $this->as($vehicles, 'GET', '/api/admin/users/mine')->assertForbidden();

        $properties = $this->user('viewer', ['manage_properties_rental'], ['rental']);
        $this->assertNotSame(403, $this->as($properties, 'GET', '/api/rental/properties')->status());
        $this->as($properties, 'GET', '/api/rental/houses')->assertForbidden();

        $this->as($this->user('viewer'), 'GET', '/api/rental/properties')->assertForbidden();
        $this->as($this->user('viewer', ['inv_manage_products']), 'GET', '/api/rental/properties')->assertForbidden();
    }

    public function test_roles_keep_their_existing_access(): void
    {
        $this->assertNotSame(403, $this->as($this->user('landlord'), 'GET', '/api/rental/properties')->status());
        $this->assertNotSame(403, $this->as($this->user('admin', services: ['transport']), 'GET', '/api/admin/vehicles')->status());
    }

    public function test_a_service_is_served_only_to_users_who_were_given_it(): void
    {
        // Role and permissions are not enough: an admin with no transport service is refused,
        // with a code the app can act on, however they got the grant.
        $noService = $this->user('admin');
        $this->as($noService, 'GET', '/api/admin/vehicles')->assertForbidden()->assertJsonPath('code', 'service_not_assigned');

        // A business given rental only cannot reach transport or inventory.
        $rentalOnly = $this->user('admin', services: ['rental']);
        $this->assertNotSame(403, $this->as($rentalOnly, 'GET', '/api/rental/properties')->status());
        $this->as($rentalOnly, 'GET', '/api/admin/vehicles')->assertForbidden()->assertJsonPath('code', 'service_not_assigned');
        $this->as($rentalOnly, 'GET', '/api/inventory/products')->assertForbidden()->assertJsonPath('code', 'service_not_assigned');

        // The emergency switch turns the check off (and only the check).
        config(['tenancy.enforce_services' => false]);
        $this->assertNotSame(403, $this->as($this->user('admin'), 'GET', '/api/admin/vehicles')->status());
    }

    // ------------------------------------------------------- creating staff

    private function staffPayload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'New Staff',
            'email' => 'new.staff@example.test',
            'phone_number' => '0712345678',
            'password' => 'STAFFNEW',
            'password_confirmation' => 'STAFFNEW',
            'role' => 'sales_officer',
            'service_types' => ['inventory'],
        ], $overrides);
    }

    public function test_new_staff_need_a_phone_number_and_start_on_a_temporary_password(): void
    {
        $admin = $this->user('admin', services: ['inventory']);

        $this->as($admin, 'POST', '/api/admin/users', $this->staffPayload(['phone_number' => null]))
            ->assertStatus(422)->assertJsonValidationErrors('phone_number');

        $this->as($admin, 'POST', '/api/admin/users', $this->staffPayload())->assertCreated();

        $created = User::where('email', 'new.staff@example.test')->firstOrFail();
        $this->assertTrue($created->must_change_password);
        $this->assertSame($admin->id, $created->created_by);
    }

    public function test_an_admin_cannot_grant_permissions_for_services_they_are_not_bound_to(): void
    {
        $admin = $this->user('admin', services: ['inventory']);

        $this->as($admin, 'POST', '/api/admin/users', $this->staffPayload(['permissions' => ['manage_vehicles_transport']]))
            ->assertForbidden();
        $this->assertDatabaseMissing('users', ['email' => 'new.staff@example.test']);

        $this->as($admin, 'POST', '/api/admin/users', $this->staffPayload(['permissions' => ['inv_view_cash']]))
            ->assertCreated();
    }

    public function test_login_tells_the_app_whether_the_password_must_be_changed(): void
    {
        $this->user('sales_officer', services: ['inventory'], extra: [
            'email' => 'flagged@example.test', 'password' => 'STAFFNEW',
            'phone_number' => '0712345678', 'must_change_password' => true,
        ]);
        $this->user('sales_officer', services: ['inventory'], extra: [
            'email' => 'settled@example.test', 'password' => 'STAFFNEW',
            'phone_number' => '0787654321', 'must_change_password' => false,
        ]);

        $login = fn (string $email, string $phone) => $this->postJson('/api/auth/login', [
            'email' => $email, 'password' => 'STAFFNEW', 'phone_number' => $phone,
        ])->assertOk()->json('data.user.must_change_password');

        $this->assertTrue($login('flagged@example.test', '0712345678'));
        $this->assertFalse($login('settled@example.test', '0787654321'));
    }

    public function test_changing_the_temporary_password_clears_the_flag(): void
    {
        $staff = $this->user('sales_officer', services: ['inventory'], extra: [
            'password' => 'STAFFNEW', 'must_change_password' => true,
        ]);

        // The field names the app used to send are rejected.
        $this->as($staff, 'POST', '/api/auth/change-password', [
            'current_password' => 'STAFFNEW', 'password' => 'MyOwnPass99', 'password_confirmation' => 'MyOwnPass99',
        ])->assertStatus(422);

        $this->as($staff, 'POST', '/api/auth/change-password', [
            'current_password' => 'STAFFNEW', 'new_password' => 'MyOwnPass99', 'new_password_confirmation' => 'MyOwnPass99',
        ])->assertOk();

        $this->assertFalse($staff->fresh()->must_change_password);
    }

    // ------------------------------------------------------------ paging

    public function test_per_page_is_clamped_to_a_safe_range(): void
    {
        $perPage = fn (array $query, int $default = 15) => Pagination::perPage(Request::create('/x', 'GET', $query), $default);

        $this->assertSame(15, $perPage([]));
        $this->assertSame(40, $perPage(['per_page' => 40]));
        $this->assertSame(100, $perPage(['per_page' => 1000000]));
        $this->assertSame(15, $perPage(['per_page' => 0]));
        $this->assertSame(15, $perPage(['per_page' => -5]));
        $this->assertSame(20, $perPage(['per_page' => 'abc'], 20));

        // An endpoint whose client really needs a long page can raise its own ceiling.
        $long = fn (array $query) => Pagination::perPage(Request::create('/x', 'GET', $query), 15, 1000);
        $this->assertSame(1000, $long(['per_page' => 1000]));
        $this->assertSame(1000, $long(['per_page' => 5000]));
    }
}
