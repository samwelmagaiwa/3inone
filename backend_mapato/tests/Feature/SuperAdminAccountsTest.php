<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A super admin may make another super admin and change their own password, and the platform is never locked out: nobody deletes,
 * switches off or demotes their own account, so an active super admin always remains.
 */
class SuperAdminAccountsTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function user(string $role, string $password = 'OldPassw0rd'): User
    {
        return User::factory()->create([
            'role' => $role, 'is_active' => true, 'password' => bcrypt($password),
            'email' => $role . ++$this->seq . '@example.test', 'phone_number' => '0729' . str_pad((string) $this->seq, 6, '0', STR_PAD_LEFT),
        ]);
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function newSuperAdmin(User $by)
    {
        return $this->api($by, 'POST', '/api/admin/users', [
            'name' => 'Second Super', 'email' => 'second@example.test', 'phone_number' => '0729999002',
            'password' => 'Secret12345', 'password_confirmation' => 'Secret12345', 'role' => 'super_admin',
        ]);
    }

    public function test_a_super_admin_makes_another_who_can_sign_in(): void
    {
        $this->newSuperAdmin($this->user('super_admin'))->assertCreated();

        $this->assertSame('super_admin', User::where('email', 'second@example.test')->value('role'));
        $this->flushHeaders();
        $this->postJson('/api/auth/login', ['email' => 'second@example.test', 'password' => 'Secret12345', 'phone_number' => '0729999002'])->assertOk();
    }

    public function test_nobody_else_can_make_a_super_admin(): void
    {
        $this->user('super_admin');
        $owner = $this->user('admin');

        $this->newSuperAdmin($owner)->assertForbidden();
        $this->assertSame(0, User::where('email', 'second@example.test')->count());
    }

    public function test_a_super_admin_changes_their_own_password(): void
    {
        $super = $this->user('super_admin');

        $this->api($super, 'POST', '/api/auth/change-password', ['current_password' => 'OldPassw0rd', 'new_password' => 'NewPassw0rd1', 'new_password_confirmation' => 'NewPassw0rd1'])->assertOk();

        $this->flushHeaders();
        $this->postJson('/api/auth/login', ['email' => $super->email, 'password' => 'NewPassw0rd1', 'phone_number' => $super->phone_number])->assertOk();
        $this->postJson('/api/auth/login', ['email' => $super->email, 'password' => 'OldPassw0rd', 'phone_number' => $super->phone_number])->assertStatus(401);
    }

    public function test_nobody_removes_their_own_super_admin_account(): void
    {
        $me = $this->user('super_admin');
        $this->user('super_admin');

        $this->api($me, 'DELETE', "/api/admin/users/{$me->id}")->assertStatus(422);
        $this->api($me, 'PUT', "/api/admin/users/{$me->id}", ['is_active' => false])->assertStatus(422);
        $this->api($me, 'PUT', "/api/admin/users/{$me->id}", ['role' => 'admin'])->assertStatus(422);
        $this->assertTrue(User::find($me->id)->isSuperAdmin() && (bool) User::find($me->id)->is_active);
    }

    public function test_a_super_admin_can_switch_off_or_delete_another_but_never_themself(): void
    {
        $me = $this->user('super_admin');
        $other = $this->user('super_admin');

        $this->api($me, 'PUT', "/api/admin/users/{$other->id}", ['is_active' => false])->assertOk();
        $this->assertFalse((bool) User::find($other->id)->is_active);

        $this->api($me, 'DELETE', "/api/admin/users/{$other->id}")->assertOk();
        $this->api($me, 'DELETE', "/api/admin/users/{$me->id}")->assertStatus(422);
    }

    public function test_deleting_a_normal_account_is_unchanged(): void
    {
        $super = $this->user('super_admin');
        $owner = $this->user('admin');

        $this->api($super, 'DELETE', "/api/admin/users/{$owner->id}")->assertOk();
    }
}
