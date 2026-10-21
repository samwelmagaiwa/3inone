<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The salon's owner runs his own staff: creates them, sees only his own, changes a role, gives or takes rights, switches one off. */
class SalonStaffAccountsTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function salon(string $name): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0729' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    private function create(User $owner, string $name, string $role, array $extra = [])
    {
        $n = ++$this->seq;

        return $this->api($owner, 'POST', '/api/admin/users', array_merge([
            'name' => $name, 'email' => "staff{$n}@example.test", 'password' => 'password123', 'password_confirmation' => 'password123',
            'phone_number' => '0711' . str_pad((string) $n, 6, '0', STR_PAD_LEFT), 'role' => $role, 'service_types' => ['salon'],
        ], $extra));
    }

    private function ids(User $as, string $query = ''): array
    {
        $res = $this->api($as, 'GET', '/api/admin/users?limit=100' . $query)->assertOk();

        return collect($res->json('data.users') ?? $res->json('data') ?? [])->pluck('name')->sort()->values()->all();
    }

    public function test_the_owner_creates_staff_and_each_one_belongs_to_his_salon_only(): void
    {
        $one = $this->salon('One');
        $two = $this->salon('Two');
        $this->create($one, 'Asha', 'hair_stylist')->assertSuccessful();
        $this->create($one, 'Acc One', 'accountant')->assertSuccessful();
        $this->create($two, 'Zawadi', 'nail_technician')->assertSuccessful();

        $asha = User::where('name', 'Asha')->firstOrFail();
        $this->assertSame($one->id, $asha->created_by);
        $this->assertContains('salon', $asha->allowedServiceTypes());
        $this->assertTrue($asha->must_change_password, 'a new person sets their own password at first sign-in');

        $mine = $this->ids($one);
        $this->assertContains('Asha', $mine);
        $this->assertContains('Acc One', $mine);
        $this->assertNotContains('Zawadi', $mine, 'another salon\'s staff is never listed');
        $this->assertNotContains('Asha', $this->ids($two));
    }

    public function test_the_owner_changes_a_role_and_the_rights_change_with_it(): void
    {
        $owner = $this->salon('One');
        $id = $this->create($owner, 'Mary', 'hair_stylist')->json('data.user.id');
        $mary = User::findOrFail($id);
        $this->assertFalse($mary->hasInventoryPermission('inv_view_reports'));
        $this->assertFalse($mary->hasInventoryPermission('inv_view_cash'));

        $this->api($owner, 'PUT', "/api/admin/users/{$id}", ['role' => 'accountant'])->assertSuccessful();
        $mary->refresh();
        $this->assertSame('accountant', $mary->role);
        $this->assertTrue($mary->hasInventoryPermission('inv_view_reports'));
        $this->assertTrue($mary->hasInventoryPermission('inv_view_cash'));
        $this->assertContains('salon', $mary->allowedServiceTypes(), 'still the salon after the change');

        $this->api($owner, 'PUT', "/api/admin/users/{$id}", ['role' => 'hair_stylist'])->assertSuccessful();
        $this->assertFalse($mary->refresh()->hasInventoryPermission('inv_view_reports'), 'back to a stylist: the money is closed again');
    }

    public function test_extra_rights_are_given_and_taken_back_and_a_person_cannot_widen_their_own(): void
    {
        $owner = $this->salon('One');
        $asha = $this->create($owner, 'Asha', 'hair_stylist')->assertSuccessful()->json('data.user.id');
        $acc = $this->create($owner, 'Acc', 'accountant')->assertSuccessful()->json('data.user.id');

        $this->api($owner, 'PUT', "/api/admin/users/{$asha}", ['permissions' => ['inv_view_cash']])->assertSuccessful();
        $this->assertTrue(User::find($asha)->hasInventoryPermission('inv_view_cash'));
        $this->api($owner, 'PUT', "/api/admin/users/{$asha}", ['permissions' => []])->assertSuccessful();
        $this->assertFalse(User::find($asha)->hasInventoryPermission('inv_view_cash'));

        // A stylist cannot hand herself rights, and cannot create staff at all.
        $stylist = User::find($asha);
        $this->api($stylist, 'PUT', "/api/admin/users/{$asha}", ['permissions' => ['inv_view_reports']])->assertForbidden();
        $this->assertFalse($stylist->refresh()->hasInventoryPermission('inv_view_reports'));
        $this->create($stylist, 'Sneaky', 'accountant')->assertForbidden();
        $this->assertNull(User::where('name', 'Sneaky')->first());
        $this->assertNotNull(User::find($acc));
    }

    public function test_a_person_switched_off_cannot_use_the_app_and_can_be_switched_on_again(): void
    {
        $owner = $this->salon('One');
        $id = $this->create($owner, 'Asha', 'hair_stylist')->json('data.user.id');
        $asha = User::findOrFail($id);
        $this->api($asha, 'GET', '/api/inventory/salon/appointments?date=' . now()->toDateString())->assertOk();

        $this->api($owner, 'PUT', "/api/admin/users/{$id}", ['is_active' => false])->assertSuccessful();
        $this->assertFalse($asha->refresh()->is_active);
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $token = $asha->createToken('again')->plainTextToken;
        $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json('GET', '/api/inventory/salon/appointments?date=' . now()->toDateString())->assertStatus(401);

        $this->api($owner, 'PUT', "/api/admin/users/{$id}", ['is_active' => true])->assertSuccessful();
        $this->api($asha->refresh(), 'GET', '/api/inventory/salon/appointments?date=' . now()->toDateString())->assertOk();
    }

    public function test_one_owner_cannot_change_another_salons_staff(): void
    {
        $one = $this->salon('One');
        $two = $this->salon('Two');
        $theirs = $this->create($two, 'Zawadi', 'hair_stylist')->json('data.user.id');

        $this->api($one, 'PUT', "/api/admin/users/{$theirs}", ['role' => 'accountant'])->assertForbidden();
        $this->api($one, 'PUT', "/api/admin/users/{$theirs}", ['permissions' => ['inv_view_reports']])->assertForbidden();
        $this->api($one, 'PUT', "/api/admin/users/{$theirs}", ['is_active' => false])->assertForbidden();
        $zawadi = User::find($theirs);
        $this->assertSame('hair_stylist', $zawadi->role);
        $this->assertTrue((bool) $zawadi->is_active);
    }
}
