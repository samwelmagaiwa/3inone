<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Start work from one's own approved phone in a SHOP or DEPOT (the inventory service): the same engine as the salon's, in the shop's own books.
 * The administrator's four rights are enforced here too (a cashier must never approve a phone or read the log), a business that has both
 * services keeps two separate sets of phones, offices, places and logs, and the owner hands the rights out on the access screen.
 */
class InventoryAttendanceTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function shop(string $name = 'Duka', array $services = ['inventory']): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0728' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), ...$services);
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function staff(User $owner, string $name = 'Juma', string $role = 'sales_officer', array $services = ['inventory']): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]), ...$services);
    }

    private function api(User $as, string $method, string $uri, array $body = [], string $service = 'inventory')
    {
        $token = $as->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', $service)->json($method, $uri, $body);
    }

    private function keys(): array
    {
        $key = openssl_pkey_new(['curve_name' => 'prime256v1', 'private_key_type' => OPENSSL_KEYTYPE_EC]);

        return [$key, openssl_pkey_get_details($key)['key']];
    }

    private function sign($key, string $payload): string
    {
        openssl_sign($payload, $sig, $key, OPENSSL_ALGO_SHA256);

        return base64_encode($sig);
    }

    private const BASE = '/api/inventory/salon/attendance';

    private function enroll(User $who, string $pem, string $uuid = 'shop-device-uuid-0001', string $service = 'inventory')
    {
        return $this->api($who, 'POST', self::BASE . '/device/enroll', [
            'device_uuid' => $uuid, 'public_key' => $pem, 'platform' => 'android', 'name' => "{$who->name}'s phone", 'model' => 'Spark 10', 'consent' => true,
        ], $service);
    }

    private function approve(User $owner, int $deviceId, string $service = 'inventory')
    {
        return $this->api($owner, 'POST', self::BASE . "/admin/devices/{$deviceId}/decision", ['decision' => 'approve'], $service);
    }

    private function office(User $owner, array $staff, array $extra = [], string $service = 'inventory'): int
    {
        $id = (int) $this->api($owner, 'POST', self::BASE . '/admin/offices', ['name' => 'Dukani'] + $extra, $service)->assertCreated()->json('data.id');
        $this->api($owner, 'PUT', self::BASE . "/admin/offices/{$id}/staff", ['user_ids' => array_map(fn ($u) => (string) $u->id, $staff)], $service)->assertOk();

        return $id;
    }

    /** Owner of a shop, a cashier with an APPROVED phone, and an office the cashier works at. */
    private function scene(array $officeExtra = []): array
    {
        $owner = $this->shop();
        $juma = $this->staff($owner);
        [$key, $pem] = $this->keys();
        $device = $this->enroll($juma, $pem)->assertCreated()->json('data');
        $this->approve($owner, $device['id'])->assertOk();
        $office = $this->office($owner, [$juma], $officeExtra);

        return [$owner, $juma, $key, $pem, $office, $device];
    }

    private function startWork(User $who, $key, ?int $office, array $extra = [], string $purpose = 'in', string $uuid = 'shop-device-uuid-0001', string $service = 'inventory')
    {
        $c = $this->api($who, 'POST', self::BASE . '/challenge', ['device_uuid' => $uuid, 'office_id' => $office, 'purpose' => $purpose], $service)->assertOk()->json('data');

        return $this->api($who, 'POST', self::BASE . '/verify', ['challenge_id' => $c['challenge_id'], 'signature' => $this->sign($key, $c['payload'])] + $extra, $service);
    }

    private function sessions(User $owner, string $service = 'inventory'): int
    {
        return (int) TenantContext::runAs($owner, fn () => TenantContext::runInService($service, fn () => DB::table('inventory_attendance')->count()));
    }

    private function switchOn(User $owner, string $service = 'inventory'): void
    {
        $this->api($owner, 'PUT', self::BASE . '/admin/policy', ['enabled' => true], $service)->assertOk();
    }

    // ------------------------------------------------------------------ the whole way, in a shop

    public function test_a_shop_cashier_registers_the_owner_approves_and_the_cashier_starts_and_finishes_work_at_the_shop(): void
    {
        [$owner, $juma, $key, , $office] = $this->scene(['latitude' => -6.8, 'longitude' => 39.27, 'radius_m' => 150, 'geofence_required' => true]);
        $this->switchOn($owner);

        // not at the shop: refused and nothing is written
        $this->startWork($juma, $key, $office, ['latitude' => -6.9, 'longitude' => 39.27, 'accuracy' => 8])->assertForbidden()->assertJsonPath('code', 'location_out_of_range');
        $this->assertSame(0, $this->sessions($owner));

        // at the shop: started at the server's time, with the distance and the verdict
        $res = $this->startWork($juma, $key, $office, ['latitude' => -6.7995, 'longitude' => 39.27, 'accuracy' => 8])->assertCreated();
        $this->assertSame('at_work', $res->json('data.place.status'));
        $this->assertSame(1, $this->sessions($owner));
        $this->assertTrue($this->api($juma, 'GET', self::BASE . '/today')->assertOk()->json('data.at_work'));

        // finishing needs no office
        $this->startWork($juma, $key, null, purpose: 'out')->assertOk();
        $this->assertFalse($this->api($juma, 'GET', self::BASE . '/today')->json('data.at_work'));

        // the owner reads it all in the shop's log, with the attendance it made
        $ok = collect($this->api($owner, 'GET', self::BASE . '/admin/checks?outcome=ok')->assertOk()->json('data'));
        $this->assertCount(2, $ok);
        $this->assertSame('at_work', $ok->last()['place_status']);
        $this->assertNotNull($ok->last()['attendance_id']);

        // and the month's hours, for the owner
        $month = $this->api($owner, 'GET', '/api/inventory/salon/attendance')->assertOk()->json('data.staff');
        $this->assertSame('Juma', $month[0]['name']);
    }

    public function test_with_the_switch_on_the_plain_tap_is_refused_for_ones_own_day_but_an_owner_may_start_someone_elses(): void
    {
        [$owner, $juma] = $this->scene();

        $this->api($juma, 'POST', self::BASE . '/clock-in')->assertSuccessful(); // off: the plain way still works
        $this->api($juma, 'POST', self::BASE . '/clock-out')->assertSuccessful();

        $this->switchOn($owner);
        $this->api($juma, 'POST', self::BASE . '/clock-in')->assertForbidden()->assertJsonPath('code', 'device_verification_required');
        // the owner cannot start the cashier's day for them: each person starts their own
        $this->api($owner, 'POST', self::BASE . '/clock-in', ['staff_id' => (string) $juma->id])->assertForbidden();
    }

    public function test_every_shop_role_can_register_and_start_work_even_a_read_only_viewer(): void
    {
        $owner = $this->shop();
        $office = null;
        $people = [];
        foreach (['sales_officer', 'operator', 'accountant', 'viewer', 'manager'] as $i => $role) {
            $people[$role] = $this->staff($owner, ucfirst($role), $role);
        }
        $office = $this->office($owner, array_values($people));
        $n = 0;
        foreach ($people as $role => $person) {
            [$key, $pem] = $this->keys();
            $uuid = 'shop-device-uuid-role-' . ++$n;
            $device = $this->enroll($person, $pem, $uuid)->assertCreated()->json('data');
            $this->approve($owner, $device['id'])->assertOk();
            $this->startWork($person, $key, $office, uuid: $uuid)->assertCreated();
        }
        $this->assertSame(5, $this->sessions($owner));
    }

    public function test_a_phone_must_be_agreed_to_in_a_shop_too(): void
    {
        $owner = $this->shop();
        $juma = $this->staff($owner);
        [, $pem] = $this->keys();

        $this->api($juma, 'POST', self::BASE . '/device/enroll', ['device_uuid' => 'shop-device-uuid-0001', 'public_key' => $pem])->assertStatus(422)->assertJsonValidationErrors('consent');
        $this->enroll($juma, $pem)->assertCreated();
    }

    public function test_the_owner_is_told_when_a_shop_phone_waits_and_when_another_phone_is_used(): void
    {
        [$owner, $juma, , , $office] = $this->scene();

        [, $pem] = $this->keys();
        $other = $this->staff($owner, 'Neema');
        $this->enroll($other, $pem, 'shop-device-uuid-0002')->assertCreated();
        $types = collect($this->api($owner, 'GET', '/api/inventory/notifications')->json('data'))->pluck('type');
        $this->assertContains('salon_device_request', $types);

        $this->api($juma, 'POST', self::BASE . '/challenge', ['device_uuid' => 'someone-elses-phone-1', 'device_name' => 'Samsung A14', 'office_id' => $office, 'purpose' => 'in'])->assertForbidden()->assertJsonPath('code', 'device_mismatch');
        $this->assertContains('salon_device_mismatch', collect($this->api($owner, 'GET', '/api/inventory/notifications')->json('data'))->pluck('type'));

        $row = collect($this->api($owner, 'GET', self::BASE . '/admin/checks?flagged=1')->json('data'))->first();
        $this->assertSame('not_logged_in_device', $row['status']);
        $this->assertSame('Samsung A14', $row['presented_device_name']);
        $this->assertSame('shop-device-uuid-0001', $row['registered_device_uuid']);
        $this->assertSame(1, $this->api($owner, 'GET', self::BASE . '/admin/checks?flagged=1')->json('meta.flagged_open'));
    }

    public function test_a_shop_office_can_be_one_of_the_shops_branches(): void
    {
        $owner = $this->shop();
        $juma = $this->staff($owner);
        $branch = (int) $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Tawi la Kariakoo', 'address' => 'Kariakoo, Dar'])->assertSuccessful()->json('data.id');

        $id = (int) $this->api($owner, 'POST', self::BASE . '/admin/offices', ['branch_id' => $branch])->assertCreated()->json('data.id');
        $this->api($owner, 'PUT', self::BASE . "/admin/offices/{$id}/staff", ['user_ids' => [(string) $juma->id]])->assertOk();

        $mine = $this->api($juma, 'GET', self::BASE . '/device')->assertOk()->json('data.offices');
        $this->assertSame('Tawi la Kariakoo', $mine[0]['name']);
        $this->assertSame($branch, $mine[0]['branch_id']);
    }

    public function test_a_place_for_one_person_wins_over_the_shops_in_a_shop_too(): void
    {
        [$owner, $juma, $key, , $office] = $this->scene(['latitude' => -6.8, 'longitude' => 39.27, 'radius_m' => 150]);

        $this->api($owner, 'PUT', self::BASE . "/admin/offices/{$office}/staff/{$juma->id}/place", ['latitude' => -6.5, 'longitude' => 39.0, 'accuracy' => 10])->assertOk();
        $res = $this->startWork($juma, $key, $office, ['latitude' => -6.5, 'longitude' => 39.0, 'accuracy' => 8])->assertCreated();

        $this->assertSame('at_work', $res->json('data.place.status'));
        $this->assertSame('person', $res->json('data.place.reference'));
    }

    // ------------------------------------------------------------------ the four rights, enforced in a shop

    private function adminCalls(): array
    {
        return [
            'inv_salon_devices' => ['GET', self::BASE . '/admin/devices'],
            'inv_salon_attendance_log' => ['GET', self::BASE . '/admin/checks'],
            'inv_salon_offices' => ['GET', self::BASE . '/admin/offices'],
            'inv_salon_attendance_policy' => ['GET', self::BASE . '/admin/policy'],
        ];
    }

    public function test_a_cashier_or_any_ordinary_shop_role_cannot_approve_phones_set_offices_read_the_log_or_switch_it_on(): void
    {
        $owner = $this->shop();
        foreach (['sales_officer', 'operator', 'accountant', 'viewer'] as $role) {
            $person = $this->staff($owner, ucfirst($role), $role);
            foreach ($this->adminCalls() as $right => [$method, $uri]) {
                $this->api($person, $method, $uri)->assertForbidden()->assertJsonPath('code', 'module_not_allowed');
            }
            $this->api($person, 'PUT', self::BASE . '/admin/policy', ['enabled' => true])->assertForbidden();
            $this->api($person, 'POST', self::BASE . '/admin/devices/1/decision', ['decision' => 'approve'])->assertForbidden();
            $this->api($person, 'POST', self::BASE . '/admin/offices', ['name' => 'X'])->assertForbidden();
        }
        $this->assertFalse(TenantContext::withoutScope(fn () => DB::table('inventory_attendance_offices')->exists()));
    }

    public function test_only_the_owner_holds_the_four_rights_in_a_shop_by_default_a_manager_has_them_off_until_the_owner_decides(): void
    {
        $owner = $this->shop();
        $manager = $this->staff($owner, 'Mwajuma', 'manager');
        foreach ($this->adminCalls() as [$method, $uri]) {
            $this->api($owner, $method, $uri)->assertOk();
            $this->api($manager, $method, $uri)->assertForbidden()->assertJsonPath('code', 'module_not_allowed');
        }

        // the owner switches them on for the manager, on the access screen
        $mods = collect($this->api($owner, 'GET', "/api/admin/users/{$manager->id}/access")->json('data.modules'))->keyBy('key');
        foreach (array_keys($this->adminCalls()) as $right) {
            $this->assertFalse($mods[$right]['on'], "{$right} starts off for a manager");
        }
        $on = $mods->filter(fn ($m) => $m['on'])->keys()->merge(array_keys($this->adminCalls()))->unique()->values()->all();
        $this->api($owner, 'PUT', "/api/admin/users/{$manager->id}/access", ['on' => $on])->assertOk();
        foreach ($this->adminCalls() as [$method, $uri]) {
            $this->api($manager->refresh(), $method, $uri)->assertOk();
        }
    }

    public function test_the_business_admin_controls_the_staff_and_never_starts_work_or_registers_a_phone(): void
    {
        [$owner, $juma, $key, , $office] = $this->scene();
        [, $pem] = $this->keys();

        // the owner's own phone and day: refused everywhere, in words that say why
        $this->enroll($owner, $pem, 'owner-phone-uuid-0001')->assertForbidden()->assertJsonPath('code', 'admin_does_not_start_work');
        $this->api($owner, 'POST', self::BASE . '/challenge', ['device_uuid' => 'owner-phone-uuid-0001', 'office_id' => $office, 'purpose' => 'in'])->assertForbidden()->assertJsonPath('code', 'admin_does_not_start_work');
        $this->api($owner, 'POST', self::BASE . '/clock-in')->assertForbidden()->assertJsonPath('code', 'admin_does_not_start_work');
        $this->api($owner, 'POST', self::BASE . '/clock-out')->assertForbidden()->assertJsonPath('code', 'admin_does_not_start_work');
        $this->assertSame(0, $this->sessions($owner));
        $this->assertNotContains((string) $owner->id, array_column($this->api($owner, 'GET', self::BASE . '/admin/devices')->json('data'), 'user_id'), 'no phone of the owner is registered');

        // the owner is never an office's staff, even if asked for
        $this->api($owner, 'PUT', self::BASE . "/admin/offices/{$office}/staff", ['user_ids' => [(string) $owner->id, (string) $juma->id]])->assertOk()->assertJsonPath('data.staff_ids', [(string) $juma->id]);

        // what the owner does see is what the staff did
        $this->startWork($juma, $key, $office)->assertCreated();
        $row = collect($this->api($owner, 'GET', self::BASE)->json('data.staff'))->firstWhere('name', 'Juma');
        $this->assertTrue($row['at_work']);
    }

    public function test_nobody_starts_someone_elses_day_in_a_shop_each_person_starts_their_own(): void
    {
        [$owner, $juma] = $this->scene();

        $this->api($owner, 'POST', self::BASE . '/clock-in', ['staff_id' => (string) $juma->id])->assertForbidden()->assertJsonPath('code', 'start_own_work');
        $this->assertSame(0, $this->sessions($owner));
        // the person starts their own, and then the owner sees them at work
        $this->api($juma, 'POST', self::BASE . '/clock-in')->assertCreated();
        $this->assertTrue(collect($this->api($owner, 'GET', self::BASE)->json('data.staff'))->firstWhere('name', 'Juma')['at_work']);
    }

    public function test_each_right_opens_only_its_own_part_in_a_shop_when_given_by_hand_or_taken_back(): void
    {
        $owner = $this->shop();
        $juma = $this->staff($owner);
        $juma->forceFill(['permissions' => ['inv_salon_devices']])->save();

        $this->api($juma, 'GET', self::BASE . '/admin/devices')->assertOk();
        $this->api($juma, 'GET', self::BASE . '/admin/offices')->assertForbidden();
        $this->api($juma, 'GET', self::BASE . '/admin/checks')->assertForbidden();
        $this->api($juma, 'GET', self::BASE . '/admin/policy')->assertForbidden();

        // a manager given three, with one of them taken back again, keeps just the other two
        $manager = $this->staff($owner, 'Mwajuma', 'manager');
        $manager->forceFill(['permissions' => ['inv_salon_devices', 'inv_salon_attendance_log', 'inv_salon_attendance_policy'], 'denied_permissions' => ['inv_salon_attendance_log']])->save();
        $this->api($manager, 'GET', self::BASE . '/admin/checks')->assertForbidden();
        $this->api($manager, 'GET', self::BASE . '/admin/devices')->assertOk();
        $this->api($manager, 'GET', self::BASE . '/admin/policy')->assertOk();
    }

    public function test_the_access_screen_of_a_shop_lists_the_four_rights_and_nothing_of_the_salons_and_the_owner_can_hand_them_out(): void
    {
        $owner = $this->shop();
        $juma = $this->staff($owner);

        $mods = collect($this->api($owner, 'GET', "/api/admin/users/{$juma->id}/access")->assertOk()->json('data.modules'))->keyBy('key');
        foreach (array_keys($this->adminCalls()) as $right) {
            $this->assertTrue($mods->has($right), "{$right} is a switch in a shop");
            $this->assertFalse($mods[$right]['on']);
        }
        $this->assertFalse($mods->has('inv_salon_equipment'), 'a salon-only switch is not offered to a shop');

        // switch two on for the cashier: the server then lets exactly those through
        $on = $mods->filter(fn ($m) => $m['on'])->keys()->merge(['inv_salon_devices', 'inv_salon_attendance_log'])->unique()->values()->all();
        $this->api($owner, 'PUT', "/api/admin/users/{$juma->id}/access", ['on' => $on])->assertOk();
        $this->api($juma->refresh(), 'GET', self::BASE . '/admin/devices')->assertOk();
        $this->api($juma, 'GET', self::BASE . '/admin/checks')->assertOk();
        $this->api($juma, 'GET', self::BASE . '/admin/offices')->assertForbidden();
        $this->assertContains('inv_salon_devices', $this->api($juma, 'GET', '/api/auth/user')->json('data.user.effective_permissions'));
    }

    // ------------------------------------------------------------------ two services, two sets of books

    public function test_a_business_with_both_services_keeps_separate_phones_offices_policy_and_log(): void
    {
        $owner = $this->shop('Both', ['inventory', 'salon']);
        $person = $this->staff($owner, 'Asha', 'sales_officer', ['inventory', 'salon']);

        // in the SALON: a phone, approved, an office, the switch on
        [$skey, $spem] = $this->keys();
        $sdev = $this->enroll($person, $spem, 'salon-device-uuid-001', 'salon')->assertCreated()->json('data');
        $this->approve($owner, $sdev['id'], 'salon')->assertOk();
        $soffice = $this->office($owner, [$person], [], 'salon');
        $this->switchOn($owner, 'salon');
        $this->startWork($person, $skey, $soffice, uuid: 'salon-device-uuid-001', service: 'salon')->assertCreated();

        // the SHOP sees none of it
        $this->assertSame([], $this->api($owner, 'GET', self::BASE . '/admin/devices')->json('data'));
        $this->assertSame([], $this->api($owner, 'GET', self::BASE . '/admin/offices')->json('data'));
        $this->assertSame([], $this->api($owner, 'GET', self::BASE . '/admin/checks')->json('data'));
        $this->assertFalse($this->api($owner, 'GET', self::BASE . '/admin/policy')->json('data.enabled'));
        $this->assertNull($this->api($person, 'GET', self::BASE . '/device')->json('data.device'));
        $this->assertSame(0, $this->sessions($owner, 'inventory'));
        $this->assertSame(1, $this->sessions($owner, 'salon'));

        // the shop's switch is off, so the plain tap still works there while the salon demands the phone
        $this->api($person, 'POST', self::BASE . '/clock-in', [], 'inventory')->assertCreated();
        $this->api($person, 'POST', self::BASE . '/clock-out', [], 'inventory')->assertSuccessful();
        $this->api($person, 'POST', self::BASE . '/clock-in', [], 'salon')->assertForbidden()->assertJsonPath('code', 'device_verification_required');

        // the salon's phone is nobody in the shop, and the salon's office is not the shop's
        $this->api($person, 'POST', self::BASE . '/challenge', ['device_uuid' => 'salon-device-uuid-001', 'office_id' => $soffice, 'purpose' => 'in'], 'inventory')
            ->assertForbidden()->assertJsonPath('code', 'device_not_registered');

        // the shop gets its own phone and office, and both lists stay one each
        [$hkey, $hpem] = $this->keys();
        $hdev = $this->enroll($person, $hpem, 'shop-device-uuid-0009')->assertCreated()->json('data');
        $this->approve($owner, $hdev['id'])->assertOk();
        $hoffice = $this->office($owner, [$person]);
        $this->startWork($person, $hkey, $hoffice, uuid: 'shop-device-uuid-0009')->assertCreated();
        $this->assertCount(1, $this->api($owner, 'GET', self::BASE . '/admin/devices', [], 'inventory')->json('data'));
        $this->assertCount(1, $this->api($owner, 'GET', self::BASE . '/admin/devices', [], 'salon')->json('data'));
        $this->assertCount(1, $this->api($owner, 'GET', self::BASE . '/admin/offices', [], 'inventory')->json('data'));
        $this->assertNotSame($soffice, $hoffice);

        // a shop office cannot be used from the salon
        $this->startWork($person, $skey, null, purpose: 'out', uuid: 'salon-device-uuid-001', service: 'salon')->assertOk();
        $this->api($person, 'POST', self::BASE . '/challenge', ['device_uuid' => 'salon-device-uuid-001', 'office_id' => $hoffice, 'purpose' => 'in'], 'salon')
            ->assertForbidden()->assertJsonPath('code', 'office_not_authorized');
    }

    public function test_one_shop_never_sees_anothers_phones_offices_or_log(): void
    {
        [$ownerA, $jumaA, $keyA, , $officeA] = $this->scene();
        $this->startWork($jumaA, $keyA, $officeA)->assertCreated();

        $ownerB = $this->shop('Duka B');
        $this->assertSame([], $this->api($ownerB, 'GET', self::BASE . '/admin/devices')->json('data'));
        $this->assertSame([], $this->api($ownerB, 'GET', self::BASE . '/admin/offices')->json('data'));
        $this->assertSame([], $this->api($ownerB, 'GET', self::BASE . '/admin/checks')->json('data'));

        // and cannot decide on A's phone by guessing its number
        $deviceId = (int) TenantContext::withoutScope(fn () => DB::table('inventory_attendance_devices')->value('id'));
        $this->api($ownerB, 'POST', self::BASE . "/admin/devices/{$deviceId}/decision", ['decision' => 'block'])->assertNotFound();
    }
}
