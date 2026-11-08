<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Salon\DeviceAttendance;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Attendance from one's own approved device: one device per person, approved by an administrator; a short-lived single-use challenge signed with
 * the device's private key; the office, the place and the person checked; the server's own clock; a log of everything that was refused.
 */
class DeviceAttendanceTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function salon(string $name = 'Glow'): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0727' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function person(User $owner, string $name = 'Asha', string $role = 'hair_stylist'): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    /** A device's key pair, made the way an app would. */
    private function keys(): array
    {
        $key = openssl_pkey_new(['curve_name' => 'prime256v1', 'private_key_type' => OPENSSL_KEYTYPE_EC]);

        return [$key, openssl_pkey_get_details($key)['key']];
    }

    private function sign($key, string $payload, bool $raw = false): string
    {
        openssl_sign($payload, $sig, $key, OPENSSL_ALGO_SHA256);
        if ($raw) {
            $sig = $this->derToRaw($sig);
        }

        return base64_encode($sig);
    }

    /** The DER sequence as 64 bytes r||s, the way a browser's Web Crypto gives it. */
    private function derToRaw(string $der): string
    {
        $offset = 2;
        $parts = [];
        for ($i = 0; $i < 2; $i++) {
            $len = ord($der[$offset + 1]);
            $int = substr($der, $offset + 2, $len);
            $parts[] = str_pad(ltrim($int, "\x00"), 32, "\x00", STR_PAD_LEFT);
            $offset += 2 + $len;
        }

        return $parts[0] . $parts[1];
    }

    private function enroll(User $who, string $pem, string $uuid = 'device-uuid-0000001'): array
    {
        return $this->api($who, 'POST', '/api/inventory/salon/attendance/device/enroll', [
            'device_uuid' => $uuid, 'public_key' => $pem, 'platform' => 'android', 'name' => "{$who->name}'s phone", 'manufacturer' => 'Tecno', 'model' => 'Spark 10', 'os_name' => 'Android', 'os_version' => '13', 'app_version' => '1.0.0+72', 'consent' => true,
        ])->assertCreated()->json('data');
    }

    private function decide(User $owner, int $deviceId, string $decision)
    {
        return $this->api($owner, 'POST', "/api/inventory/salon/attendance/admin/devices/{$deviceId}/decision", ['decision' => $decision]);
    }

    private function office(User $owner, array $extra = [], array $staff = []): int
    {
        $id = (int) $this->api($owner, 'POST', '/api/inventory/salon/attendance/admin/offices', ['name' => 'Kariakoo' ] + $extra)->assertCreated()->json('data.id');
        $this->api($owner, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$id}/staff", ['user_ids' => array_map(fn ($u) => (string) $u->id, $staff)])->assertOk();

        return $id;
    }

    /** Owner, a stylist with an APPROVED device, and an office she works at. */
    private function scene(array $officeExtra = []): array
    {
        $owner = $this->salon();
        $asha = $this->person($owner);
        [$key, $pem] = $this->keys();
        $device = $this->enroll($asha, $pem);
        $this->decide($owner, $device['id'], 'approve')->assertOk();
        $office = $this->office($owner, $officeExtra, [$asha]);

        return [$owner, $asha, $key, $pem, $office, $device];
    }

    private function challenge(User $who, ?int $office, string $uuid = 'device-uuid-0000001', string $purpose = 'in')
    {
        return $this->api($who, 'POST', '/api/inventory/salon/attendance/challenge', ['device_uuid' => $uuid, 'office_id' => $office, 'purpose' => $purpose]);
    }

    /** Ask for a challenge, sign it with $key and send it. */
    private function startWork(User $who, $key, ?int $office, array $extra = [], string $purpose = 'in', bool $raw = false)
    {
        $c = $this->challenge($who, $office, purpose: $purpose)->assertOk()->json('data');

        return $this->api($who, 'POST', '/api/inventory/salon/attendance/verify', ['challenge_id' => $c['challenge_id'], 'signature' => $this->sign($key, $c['payload'], $raw)] + $extra);
    }

    private function checks(User $owner, string $outcome): array
    {
        return $this->api($owner, 'GET', "/api/inventory/salon/attendance/admin/checks?outcome={$outcome}")->assertOk()->json('data');
    }

    private function sessions(User $owner): int
    {
        return (int) TenantContext::runAs($owner, fn () => TenantContext::runInService('salon', fn () => DB::table('inventory_attendance')->count()));
    }

    // ------------------------------------------------------------------ the happy path

    public function test_an_approved_device_starts_and_finishes_work_at_the_servers_time_with_the_office_and_device_recorded(): void
    {
        [$owner, $asha, $key, , $office, $device] = $this->scene();
        Carbon::setTestNow(Carbon::parse('2026-11-09 06:30:00', 'UTC'));

        $in = $this->startWork($asha, $key, $office, ['latitude' => -6.8, 'longitude' => 39.27, 'accuracy' => 12.5, 'location_at' => '2001-01-01 00:00:00'])->assertCreated()->json('data');

        // the server's clock (09:30 in Dar es Salaam), never the phone's
        $this->assertSame('2026-11-09 09:30', $in['clock_in']);
        $this->assertSame($office, $in['office_id']);
        $row = TenantContext::runAs($owner, fn () => TenantContext::runInService('salon', fn () => DB::table('inventory_attendance')->first()));
        $this->assertSame('verified', $row->source);
        $this->assertSame((int) $device['id'], (int) $row->device_id);
        $this->assertEquals(-6.8, (float) $row->latitude);
        $this->assertTrue($this->api($asha, 'GET', '/api/inventory/salon/attendance/today')->json('data.at_work'));

        Carbon::setTestNow(Carbon::parse('2026-11-09 14:30:00', 'UTC'));
        $out = $this->startWork($asha, $key, null, purpose: 'out')->assertOk()->json('data');
        $this->assertSame('2026-11-09 17:30', $out['clock_out']);
        $this->assertFalse($this->api($asha, 'GET', '/api/inventory/salon/attendance/today')->json('data.at_work'));
        $this->assertCount(2, $this->checks($owner, 'ok'));
    }

    public function test_a_browsers_raw_signature_is_accepted_too(): void
    {
        [, $asha, $key, , $office] = $this->scene();

        $this->startWork($asha, $key, $office, raw: true)->assertCreated();
    }

    public function test_the_policy_is_off_until_the_owner_turns_it_on_and_the_plain_clock_in_still_works_then(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner);

        $this->assertFalse($this->api($owner, 'GET', '/api/inventory/salon/attendance/admin/policy')->json('data.enabled'));
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-in')->assertSuccessful();
    }

    public function test_with_the_policy_on_a_person_cannot_start_their_own_day_the_plain_way_and_nobody_starts_it_for_them(): void
    {
        [$owner, $asha, , , ] = $this->scene();
        $this->api($owner, 'PUT', '/api/inventory/salon/attendance/admin/policy', ['enabled' => true, 'timezone' => 'Africa/Dar_es_Salaam'])->assertOk();

        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-in')->assertForbidden()->assertJsonPath('code', 'device_verification_required');
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-out')->assertForbidden();
        // nobody starts someone else's day, the owner included: each person starts their own, so the owner can see who came
        $this->api($owner, 'POST', '/api/inventory/salon/attendance/clock-in', ['staff_id' => (string) $asha->id])->assertForbidden()->assertJsonPath('code', 'start_own_work');
        $this->assertSame(0, $this->sessions($owner));
    }

    // ------------------------------------------------------------------ the device

    public function test_a_device_waits_for_approval_and_cannot_start_work_until_it_is_approved(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner);
        [$key, $pem] = $this->keys();
        $device = $this->enroll($asha, $pem);
        $office = $this->office($owner, [], [$asha]);

        $this->assertSame('pending', $device['status']);
        $mine = $this->api($asha, 'GET', '/api/inventory/salon/attendance/device')->assertOk()->json('data');
        $this->assertSame('pending', $mine['device']['status']);
        $this->assertSame([$office], array_column($mine['offices'], 'id'));
        $this->challenge($asha, $office)->assertForbidden()->assertJsonPath('code', 'pending');
        $this->assertCount(1, $this->checks($owner, 'pending'));
        $this->assertSame(0, $this->sessions($owner));

        $this->decide($owner, $device['id'], 'approve')->assertOk();
        $this->startWork($asha, $key, $office)->assertCreated();
    }

    public function test_the_administrator_is_told_a_device_is_waiting(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner);
        [, $pem] = $this->keys();
        $this->enroll($asha, $pem);

        $told = collect($this->api($owner, 'GET', '/api/inventory/notifications')->json('data'))->firstWhere('type', 'salon_device_request');
        $this->assertNotNull($told);
    }

    public function test_one_device_per_person_and_a_device_belongs_to_one_person(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner);
        $bahati = $this->person($owner, 'Bahati');
        [, $pem] = $this->keys();
        [, $pem2] = $this->keys();
        $this->enroll($asha, $pem);

        $this->api($asha, 'POST', '/api/inventory/salon/attendance/device/enroll', ['device_uuid' => 'another-device-0002', 'public_key' => $pem2, 'consent' => true])->assertStatus(422)->assertJsonValidationErrors('device');
        $this->api($bahati, 'POST', '/api/inventory/salon/attendance/device/enroll', ['device_uuid' => 'device-uuid-0000001', 'public_key' => $pem2, 'consent' => true])->assertStatus(422)->assertJsonValidationErrors('device_uuid');
    }

    public function test_only_an_ec_p256_key_is_accepted(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner);
        $rsa = openssl_pkey_get_details(openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]))['key'];

        $this->api($asha, 'POST', '/api/inventory/salon/attendance/device/enroll', ['device_uuid' => 'device-uuid-0000001', 'public_key' => $rsa, 'consent' => true])->assertStatus(422)->assertJsonValidationErrors('public_key');
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/device/enroll', ['device_uuid' => 'device-uuid-0000001', 'public_key' => 'not a key', 'consent' => true])->assertStatus(422);
    }

    public function test_rejected_and_blocked_devices_cannot_start_work_and_say_so(): void
    {
        [$owner, $asha, , , $office, $device] = $this->scene();

        $this->decide($owner, $device['id'], 'block')->assertOk();
        $this->challenge($asha, $office)->assertForbidden()->assertJsonPath('code', 'blocked');

        $owner2 = $this->salon('Other');
        $bahati = $this->person($owner2, 'Bahati');
        [, $pem] = $this->keys();
        $d = $this->enroll($bahati, $pem, 'device-uuid-0000009');
        $this->decide($owner2, $d['id'], 'reject')->assertOk();
        $this->challenge($bahati, null, 'device-uuid-0000009')->assertForbidden()->assertJsonPath('code', 'rejected');
        // a rejected person may ask again with another device
        [, $pem3] = $this->keys();
        $this->api($bahati, 'POST', '/api/inventory/salon/attendance/device/enroll', ['device_uuid' => 'device-uuid-0000010', 'public_key' => $pem3, 'consent' => true])->assertCreated();
    }

    public function test_another_device_is_refused_as_a_mismatch_even_with_a_valid_key_of_its_own(): void
    {
        [$owner, $asha, , , $office] = $this->scene();

        $this->challenge($asha, $office, 'someone-elses-phone-1')->assertForbidden()->assertJsonPath('code', 'device_mismatch');

        $this->assertCount(1, $this->checks($owner, 'device_mismatch'));
        $this->assertSame(0, $this->sessions($owner));
    }

    public function test_the_salons_owner_does_not_start_work_either_only_the_staff_do(): void
    {
        [$owner, $asha, $key, , $office] = $this->scene();
        [, $pem] = $this->keys();

        $this->api($owner, 'POST', '/api/inventory/salon/attendance/device/enroll', ['device_uuid' => 'owner-phone-uuid-0001', 'public_key' => $pem, 'consent' => true])->assertForbidden()->assertJsonPath('code', 'admin_does_not_start_work');
        $this->api($owner, 'POST', '/api/inventory/salon/attendance/clock-in')->assertForbidden()->assertJsonPath('code', 'admin_does_not_start_work');
        $this->assertSame(0, $this->sessions($owner));
        $this->api($owner, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$office}/staff", ['user_ids' => [(string) $owner->id, (string) $asha->id]])->assertOk()->assertJsonPath('data.staff_ids', [(string) $asha->id]);
        $this->startWork($asha, $key, $office)->assertCreated();
    }

    public function test_a_device_is_registered_only_after_the_person_agreed_and_the_agreement_is_kept(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner);
        [, $pem] = $this->keys();
        $body = ['device_uuid' => 'device-uuid-0000001', 'public_key' => $pem, 'platform' => 'android'];

        // no agreement, or a "no": nothing is registered, and the message says what to do
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/device/enroll', $body)->assertStatus(422)->assertJsonValidationErrors('consent');
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/device/enroll', $body + ['consent' => false])->assertStatus(422)->assertJsonValidationErrors('consent');
        $this->assertNull($this->api($asha, 'GET', '/api/inventory/salon/attendance/device')->json('data.device'));

        // with it: registered, and when and to which wording is kept
        $device = $this->api($asha, 'POST', '/api/inventory/salon/attendance/device/enroll', $body + ['consent' => true])->assertCreated()->json('data');
        $this->assertNotNull($device['consent_at']);
        $this->assertSame('v1', TenantContext::runAs($owner, fn () => TenantContext::runInService('salon', fn () => DB::table('inventory_attendance_devices')->where('id', $device['id'])->value('consent_version'))));
    }

    public function test_a_different_device_is_kept_as_not_the_logged_in_device_with_both_ids_and_the_administrator_is_told_once(): void
    {
        [$owner, $asha, , , $office] = $this->scene();

        $this->api($asha, 'POST', '/api/inventory/salon/attendance/challenge', ['device_uuid' => 'someone-elses-phone-1', 'device_name' => 'Samsung A14', 'office_id' => $office, 'purpose' => 'in'])->assertForbidden()->assertJsonPath('code', 'device_mismatch');
        // a retry in the same spell is the same case: logged again, not announced again
        $this->challenge($asha, $office, 'someone-elses-phone-1')->assertForbidden();

        $rows = $this->checks($owner, 'device_mismatch');
        $this->assertCount(2, $rows);
        $row = collect($rows)->firstWhere('presented_device_name', 'Samsung A14');
        $this->assertTrue($row['flagged']);
        $this->assertSame('not_logged_in_device', $row['status']);
        $this->assertSame('device-uuid-0000001', $row['registered_device_uuid']);
        $this->assertSame('someone-elses-phone-1', $row['presented_device_uuid']);
        $this->assertNotEmpty($row['ip']);
        $this->assertSame((string) $asha->id, $row['user_id']);

        $told = collect($this->api($owner, 'GET', '/api/inventory/notifications')->json('data'))->where('type', 'salon_device_mismatch');
        $this->assertCount(1, $told);

        // the open count, then seen: the whole spell is marked, the lines stay
        $this->assertSame(2, $this->api($owner, 'GET', '/api/inventory/salon/attendance/admin/checks?flagged=1')->json('meta.flagged_open'));
        $this->api($owner, 'POST', '/api/inventory/salon/attendance/admin/checks/' . $row['id'] . '/acknowledge')->assertOk();
        $after = $this->api($owner, 'GET', '/api/inventory/salon/attendance/admin/checks?flagged=1')->assertOk();
        $this->assertSame(0, $after->json('meta.flagged_open'));
        $this->assertCount(2, $after->json('data'));
        $this->assertTrue($after->json('data.0.acknowledged'));
    }

    public function test_a_good_start_keeps_the_attendance_id_and_the_device_used(): void
    {
        [$owner, $asha, $key, , $office] = $this->scene();

        $id = $this->startWork($asha, $key, $office)->assertCreated()->json('data.id');

        $ok = $this->checks($owner, 'ok')[0];
        $this->assertSame($id, $ok['attendance_id']);
        $this->assertSame('verified', $ok['status']);
        $this->assertFalse($ok['flagged']);
        $this->assertSame($ok['registered_device_uuid'], $ok['presented_device_uuid']);
        $this->assertSame(0, $this->api($owner, 'GET', '/api/inventory/salon/attendance/admin/checks?flagged=1')->json('meta.flagged_open'));
    }

    public function test_a_wrong_signature_is_refused_logged_and_burns_the_challenge(): void
    {
        [$owner, $asha, , , $office] = $this->scene();
        [$other] = $this->keys();

        $c = $this->challenge($asha, $office)->assertOk()->json('data');
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/verify', ['challenge_id' => $c['challenge_id'], 'signature' => $this->sign($other, $c['payload'])])->assertForbidden()->assertJsonPath('code', 'signature_invalid');

        $this->assertCount(1, $this->checks($owner, 'signature_invalid'));
        $this->assertSame(0, $this->sessions($owner));
    }

    public function test_a_signature_over_something_else_is_refused(): void
    {
        [, $asha, $key, , $office] = $this->scene();

        $c = $this->challenge($asha, $office)->assertOk()->json('data');
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/verify', ['challenge_id' => $c['challenge_id'], 'signature' => $this->sign($key, str_replace('|in', '|out', $c['payload']))])->assertForbidden()->assertJsonPath('code', 'signature_invalid');
    }

    public function test_a_challenge_works_once_and_for_ninety_seconds(): void
    {
        [$owner, $asha, $key, , $office] = $this->scene();
        Carbon::setTestNow(Carbon::parse('2026-11-09 06:00:00', 'UTC'));

        $c = $this->challenge($asha, $office)->assertOk()->json('data');
        $signature = $this->sign($key, $c['payload']);
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/verify', ['challenge_id' => $c['challenge_id'], 'signature' => $signature])->assertCreated();
        // the same signed answer again (a replay) finds it used
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/verify', ['challenge_id' => $c['challenge_id'], 'signature' => $signature])->assertForbidden()->assertJsonPath('code', 'challenge_expired');

        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-out')->assertSuccessful(); // (the policy is off here: only to start again)
        $late = $this->challenge($asha, $office)->assertOk()->json('data');
        Carbon::setTestNow(Carbon::parse('2026-11-09 06:03:00', 'UTC'));
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/verify', ['challenge_id' => $late['challenge_id'], 'signature' => $this->sign($key, $late['payload'])])->assertForbidden()->assertJsonPath('code', 'challenge_expired');

        $this->assertSame(1, $this->sessions($owner), 'only the one good answer wrote attendance');
    }

    public function test_one_persons_challenge_is_not_anothers(): void
    {
        [$owner, $asha, , , $office] = $this->scene();
        $bahati = $this->person($owner, 'Bahati');
        [$key2, $pem2] = $this->keys();
        $d = $this->enroll($bahati, $pem2, 'device-uuid-0000002');
        $this->decide($owner, $d['id'], 'approve')->assertOk();

        $c = $this->challenge($asha, $office)->assertOk()->json('data');

        $this->api($bahati, 'POST', '/api/inventory/salon/attendance/verify', ['challenge_id' => $c['challenge_id'], 'signature' => $this->sign($key2, $c['payload'])])->assertForbidden();
        $this->assertSame(0, $this->sessions($owner));
    }

    // ------------------------------------------------------------------ the office and the place

    public function test_only_an_office_the_person_is_assigned_to_and_that_is_active_is_accepted(): void
    {
        [$owner, $asha, , , $office] = $this->scene();
        $elsewhere = $this->office($owner, ['name' => 'Mbezi'], []);

        $this->challenge($asha, $elsewhere)->assertForbidden()->assertJsonPath('code', 'office_not_authorized');
        $this->challenge($asha, 999999)->assertForbidden()->assertJsonPath('code', 'office_not_authorized');
        $this->challenge($asha, null)->assertForbidden()->assertJsonPath('code', 'office_not_authorized');

        $this->api($owner, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$office}", ['active' => false])->assertOk();
        $this->challenge($asha, $office)->assertForbidden()->assertJsonPath('code', 'office_not_authorized');
        $this->assertSame([], $this->api($asha, 'GET', '/api/inventory/salon/attendance/device')->json('data.offices'), 'an inactive office is not offered');
        $this->assertCount(3 + 1, $this->checks($owner, 'office_not_authorized'));
    }

    public function test_a_required_geofence_blocks_outside_and_without_a_location_but_a_circle_that_is_not_required_never_blocks(): void
    {
        [$owner, $asha, $key, , $office] = $this->scene(['latitude' => -6.8, 'longitude' => 39.27, 'radius_m' => 150, 'geofence_required' => true]);

        $this->startWork($asha, $key, $office)->assertForbidden()->assertJsonPath('code', 'location_out_of_range');
        $this->startWork($asha, $key, $office, ['latitude' => -6.9, 'longitude' => 39.27])->assertForbidden()->assertJsonPath('code', 'location_out_of_range');
        $this->assertSame(0, $this->sessions($owner));
        $this->startWork($asha, $key, $office, ['latitude' => -6.8004, 'longitude' => 39.2701, 'accuracy' => 18])->assertCreated();

        // an office that does not require it: far away is only recorded
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-out')->assertSuccessful();
        $this->api($owner, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$office}", ['geofence_required' => false])->assertOk();
        $this->startWork($asha, $key, $office, ['latitude' => -1.0, 'longitude' => 30.0])->assertCreated();
    }

    public function test_a_required_geofence_needs_a_centre(): void
    {
        $owner = $this->salon();

        $this->api($owner, 'POST', '/api/inventory/salon/attendance/admin/offices', ['name' => 'X', 'geofence_required' => true])->assertStatus(422);
    }

    // ------------------------------------------------------------------ one session at a time

    public function test_no_second_session_while_one_is_open_and_no_clock_out_without_one(): void
    {
        [$owner, $asha, $key, , $office] = $this->scene();

        $this->challenge($asha, null, purpose: 'out')->assertForbidden()->assertJsonPath('code', 'no_active_session');
        $this->startWork($asha, $key, $office)->assertCreated();
        $this->challenge($asha, $office)->assertForbidden()->assertJsonPath('code', 'already_clocked_in');
        $this->assertSame(1, $this->sessions($owner));
        $this->startWork($asha, $key, null, purpose: 'out')->assertOk();
    }

    // ------------------------------------------------------------------ replacing a device keeps the history

    public function test_a_reset_keeps_the_old_device_and_its_attendance_and_lets_a_new_one_be_approved(): void
    {
        [$owner, $asha, $key, , $office, $old] = $this->scene();
        $this->startWork($asha, $key, $office)->assertCreated();
        $this->startWork($asha, $key, null, purpose: 'out')->assertOk();

        $this->decide($owner, $old['id'], 'reset')->assertOk();
        $this->challenge($asha, $office)->assertForbidden()->assertJsonPath('code', 'device_not_registered');

        [$key2, $pem2] = $this->keys();
        $new = $this->enroll($asha, $pem2, 'device-uuid-0000099');
        $this->decide($owner, $new['id'], 'approve')->assertOk();

        // the old one is still there, as replaced, and the attendance it made is untouched
        $all = $this->api($owner, 'GET', '/api/inventory/salon/attendance/admin/devices')->json('data');
        $this->assertEqualsCanonicalizing(['approved', 'replaced'], array_column($all, 'status'));
        $this->assertSame(1, $this->sessions($owner));
        // the old phone can no longer sign in; the new one can
        $this->challenge($asha, $office)->assertForbidden()->assertJsonPath('code', 'device_mismatch');
        $this->challenge($asha, $office, 'device-uuid-0000099')->assertOk();
    }

    public function test_approving_a_new_device_puts_another_approved_one_away_instead_of_deleting_it(): void
    {
        [$owner, $asha, , , , $old] = $this->scene();
        $this->decide($owner, $old['id'], 'reject')->assertOk();
        [, $pem2] = $this->keys();
        $new = $this->enroll($asha, $pem2, 'device-uuid-0000050');

        $this->decide($owner, $new['id'], 'approve')->assertOk();

        $statuses = array_column($this->api($owner, 'GET', '/api/inventory/salon/attendance/admin/devices')->json('data'), 'status', 'id');
        $this->assertSame('approved', $statuses[$new['id']]);
        $this->assertSame('rejected', $statuses[$old['id']]);
    }

    // ------------------------------------------------------------------ rights and separation

    public function test_only_the_owner_and_those_given_the_right_manage_devices_offices_and_the_log(): void
    {
        [$owner, $asha, , , $office, $device] = $this->scene();

        foreach (['devices', 'checks', 'offices', 'policy'] as $page) {
            $this->api($asha, 'GET', "/api/inventory/salon/attendance/admin/{$page}")->assertForbidden();
        }
        $this->decide($asha, $device['id'], 'block')->assertForbidden();
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/admin/offices', ['name' => 'X'])->assertForbidden();
        foreach (['devices', 'checks', 'offices', 'policy'] as $page) {
            $this->api($owner, 'GET', "/api/inventory/salon/attendance/admin/{$page}")->assertOk();
        }

        $on = collect($this->api($owner, 'GET', "/api/admin/users/{$asha->id}/access")->json('data.modules'))->filter(fn ($m) => $m['on'])->pluck('key')->all();
        // each thing is its own right: the phones only
        $this->api($owner, 'PUT', "/api/admin/users/{$asha->id}/access", ['on' => array_merge($on, ['inv_salon_devices'])])->assertOk();
        $this->api($asha, 'GET', '/api/inventory/salon/attendance/admin/devices')->assertOk();
        foreach (['checks', 'offices', 'policy'] as $page) {
            $this->api($asha, 'GET', "/api/inventory/salon/attendance/admin/{$page}")->assertForbidden();
        }
        // then the offices and places only
        $this->api($owner, 'PUT', "/api/admin/users/{$asha->id}/access", ['on' => array_merge($on, ['inv_salon_offices'])])->assertOk();
        $this->api($asha, 'GET', '/api/inventory/salon/attendance/admin/offices')->assertOk();
        $this->api($asha, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$office}/staff/{$asha->id}/place", ['latitude' => -6.8, 'longitude' => 39.27, 'accuracy' => 8])->assertOk();
        $this->api($asha, 'GET', '/api/inventory/salon/attendance/admin/devices')->assertForbidden();
        $this->api($asha, 'PUT', '/api/inventory/salon/attendance/admin/policy', ['enabled' => true])->assertForbidden();
        // the log and the on/off switch
        $this->api($owner, 'PUT', "/api/admin/users/{$asha->id}/access", ['on' => array_merge($on, ['inv_salon_attendance_log', 'inv_salon_attendance_policy'])])->assertOk();
        $this->api($asha, 'GET', '/api/inventory/salon/attendance/admin/checks')->assertOk();
        $this->api($asha, 'PUT', '/api/inventory/salon/attendance/admin/policy', ['enabled' => true, 'timezone' => 'Africa/Dar_es_Salaam'])->assertOk();
        $this->api($asha, 'GET', '/api/inventory/salon/attendance/admin/offices')->assertForbidden();
    }

    public function test_the_four_attendance_switches_are_named_and_off_for_everyone_but_the_owner_until_the_owner_turns_them_on(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner);
        $manager = $this->person($owner, 'Mary', 'manager');

        // a stylist and even a manager start with all four OFF; the business admin decides to hand them out
        foreach ([$asha->id => false, $manager->id => false] as $id => $expected) {
            $state = collect($this->api($owner, 'GET', "/api/admin/users/{$id}/access")->json('data.modules'))->keyBy('key');
            foreach (['inv_salon_devices', 'inv_salon_offices', 'inv_salon_attendance_log', 'inv_salon_attendance_policy'] as $key) {
                $this->assertTrue($state->has($key), $key);
                $this->assertNotSame('', $state[$key]['sw']);
                $this->assertSame($expected, $state[$key]['on'], "{$key} for {$id}");
            }
        }
    }

    public function test_the_switch_is_named_and_starts_off_for_a_stylist(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner);
        $state = collect($this->api($owner, 'GET', "/api/admin/users/{$asha->id}/access")->json('data.modules'))->keyBy('key');

        $this->assertTrue($state->has('inv_salon_devices'));
        $this->assertFalse($state['inv_salon_devices']['on']);
        $this->assertNotSame('', $state['inv_salon_devices']['sw']);
    }

    public function test_one_businesss_devices_offices_and_log_are_not_anothers(): void
    {
        [$owner, , , , , $device] = $this->scene();
        $two = $this->salon('Two');

        $this->assertSame([], $this->api($two, 'GET', '/api/inventory/salon/attendance/admin/devices')->json('data'));
        $this->assertSame([], $this->api($two, 'GET', '/api/inventory/salon/attendance/admin/offices')->json('data'));
        $this->decide($two, $device['id'], 'block')->assertNotFound();
        $this->assertCount(1, $this->api($owner, 'GET', '/api/inventory/salon/attendance/admin/devices')->json('data'));
    }

    public function test_an_office_cannot_be_given_to_someone_from_another_business(): void
    {
        $owner = $this->salon();
        $stranger = $this->person($this->salon('Other'), 'Stranger');
        $id = (int) $this->api($owner, 'POST', '/api/inventory/salon/attendance/admin/offices', ['name' => 'Main'])->json('data.id');

        $kept = $this->api($owner, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$id}/staff", ['user_ids' => [(string) $stranger->id]])->assertOk()->json('data.staff_ids');

        $this->assertSame([], $kept);
    }

    public function test_an_office_can_be_a_branch_and_shows_its_name_and_address_even_after_a_rename(): void
    {
        $owner = $this->salon();
        $branch = (int) $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Kariakoo', 'address' => 'Mtaa wa Kongo'])->assertCreated()->json('data.id');

        $o = $this->api($owner, 'POST', '/api/inventory/salon/attendance/admin/offices', ['branch_id' => $branch])->assertCreated()->json('data');
        $this->assertSame($branch, $o['branch_id']);
        $this->assertSame('Kariakoo', $o['name']);
        $this->assertSame('Mtaa wa Kongo', $o['address']);

        $this->api($owner, 'PUT', "/api/inventory/salon/branches/{$branch}", ['name' => 'Kariakoo Mpya'])->assertSuccessful();
        $this->assertSame('Kariakoo Mpya', collect($this->api($owner, 'GET', '/api/inventory/salon/attendance/admin/offices')->json('data'))->firstWhere('id', $o['id'])['name']);
    }

    public function test_a_branch_has_one_office_and_must_be_the_businesss_own(): void
    {
        $owner = $this->salon();
        $branch = (int) $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertCreated()->json('data.id');
        $this->api($owner, 'POST', '/api/inventory/salon/attendance/admin/offices', ['branch_id' => $branch])->assertCreated();

        $this->api($owner, 'POST', '/api/inventory/salon/attendance/admin/offices', ['branch_id' => $branch])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/attendance/admin/offices', ['branch_id' => 999999])->assertStatus(422);
        $two = $this->salon('Two');
        $this->api($two, 'POST', '/api/inventory/salon/attendance/admin/offices', ['branch_id' => $branch])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/attendance/admin/offices', [])->assertStatus(422);
    }

    // ------------------------------------------------------------------ is the person really at work?

    private function lastCheck(User $owner, string $outcome = 'ok'): array
    {
        return $this->checks($owner, $outcome)[0];
    }

    public function test_every_start_keeps_the_distance_and_the_verdict_even_where_the_place_is_not_required(): void
    {
        [$owner, $asha, $key, , $office] = $this->scene(['latitude' => -6.8, 'longitude' => 39.27, 'radius_m' => 150, 'geofence_required' => false]);

        // ~111 m north of the office: inside the 150 m circle
        $near = $this->startWork($asha, $key, $office, ['latitude' => -6.799, 'longitude' => 39.27, 'accuracy' => 8])->assertCreated()->json('data.place');
        $this->assertSame('at_work', $near['status']);
        $this->assertSame('office', $near['reference']);
        $this->assertEqualsWithDelta(111.2, $near['distance_m'], 1.0);
        $this->assertSame(150, $near['radius_m']);
        $this->assertSame('at_work', $this->lastCheck($owner)['place_status']);

        $this->startWork($asha, $key, null, purpose: 'out')->assertOk();

        // ~1.1 km away: allowed (the office does not require it) but plainly recorded as away, with how far
        $far = $this->startWork($asha, $key, $office, ['latitude' => -6.79, 'longitude' => 39.27, 'accuracy' => 8])->assertCreated()->json('data.place');
        $this->assertSame('away', $far['status']);
        $this->assertEqualsWithDelta(1112.0, $far['distance_m'], 5.0);
        $row = TenantContext::runAs($owner, fn () => TenantContext::runInService('salon', fn () => DB::table('inventory_attendance')->orderByDesc('id')->first()));
        $this->assertSame('away', $row->place_status);
        $this->assertEqualsWithDelta(1112.0, (float) $row->distance_m, 5.0);
        $this->assertSame('office', $row->place_reference);
    }

    public function test_a_place_the_administrator_captured_for_one_person_wins_over_the_offices(): void
    {
        [$owner, $asha, $key, , $office] = $this->scene(['latitude' => -6.8, 'longitude' => 39.27, 'radius_m' => 150, 'geofence_required' => true]);
        // she works at a stall 2 km from the office: captured from the administrator's phone, for her
        $this->api($owner, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$office}/staff/{$asha->id}/place", ['latitude' => -6.782, 'longitude' => 39.27, 'accuracy' => 12, 'radius_m' => 100])->assertOk();

        $this->startWork($asha, $key, $office, ['latitude' => -6.8, 'longitude' => 39.27])->assertForbidden()->assertJsonPath('code', 'location_out_of_range');
        $ok = $this->startWork($asha, $key, $office, ['latitude' => -6.7821, 'longitude' => 39.27, 'accuracy' => 10])->assertCreated()->json('data.place');

        $this->assertSame('person', $ok['reference']);
        $this->assertSame(100, $ok['radius_m']);
        $listed = collect($this->api($owner, 'GET', '/api/inventory/salon/attendance/admin/offices')->json('data'))->firstWhere('id', $office);
        $this->assertEqualsWithDelta(-6.782, $listed['staff_places'][(string) $asha->id]['latitude'], 0.0001);

        $this->api($owner, 'DELETE', "/api/inventory/salon/attendance/admin/offices/{$office}/staff/{$asha->id}/place")->assertOk();
        $this->startWork($asha, $key, null, purpose: 'out')->assertOk();
        $this->assertSame('office', $this->startWork($asha, $key, $office, ['latitude' => -6.8, 'longitude' => 39.27])->assertCreated()->json('data.place.reference'));
    }

    public function test_capturing_a_place_needs_a_good_fix_and_an_assigned_person(): void
    {
        [$owner, $asha, , , $office] = $this->scene();
        $stranger = $this->person($owner, 'Bahati');

        $this->api($owner, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$office}/staff/{$asha->id}/place", ['latitude' => -6.8, 'longitude' => 39.27, 'accuracy' => 400])->assertStatus(422);
        $this->api($owner, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$office}/staff/{$stranger->id}/place", ['latitude' => -6.8, 'longitude' => 39.27, 'accuracy' => 10])->assertNotFound();
        $this->api($owner, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$office}", ['latitude' => -6.8, 'longitude' => 39.27, 'accuracy' => 400])->assertStatus(422);
        $this->api($owner, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$office}", ['latitude' => -6.8, 'longitude' => 39.27, 'accuracy' => 9])->assertOk();
        $this->api($asha, 'PUT', "/api/inventory/salon/attendance/admin/offices/{$office}/staff/{$asha->id}/place", ['latitude' => 0, 'longitude' => 0])->assertForbidden();
    }

    public function test_the_gps_uncertainty_is_allowed_for_but_a_weak_old_or_fake_fix_is_not_proof(): void
    {
        [$owner, $asha, $key, , $office] = $this->scene(['latitude' => -6.8, 'longitude' => 39.27, 'radius_m' => 150, 'geofence_required' => true]);

        // 167 m away is outside 150 m, but with a 30 m uncertainty she may well be inside: allowed
        $this->assertSame('at_work', $this->startWork($asha, $key, $office, ['latitude' => -6.7985, 'longitude' => 39.27, 'accuracy' => 30])->assertCreated()->json('data.place.status'));
        $this->startWork($asha, $key, null, purpose: 'out')->assertOk();
        // the same spot with a certain fix is away
        $this->startWork($asha, $key, $office, ['latitude' => -6.7985, 'longitude' => 39.27, 'accuracy' => 5])->assertForbidden()->assertJsonPath('code', 'location_out_of_range');
        // a fix that is too weak (±300 m) proves nothing, even right at the office
        $this->startWork($asha, $key, $office, ['latitude' => -6.8, 'longitude' => 39.27, 'accuracy' => 300])->assertForbidden();
        $this->assertSame('weak_signal', $this->lastCheck($owner, 'location_out_of_range')['place_status']);
        // an old fix (the phone's own timestamp, ten minutes ago)
        $this->startWork($asha, $key, $office, ['latitude' => -6.8, 'longitude' => 39.27, 'accuracy' => 5, 'location_at' => now()->subMinutes(10)->toIso8601String()])->assertForbidden();
        $this->assertSame('stale', $this->lastCheck($owner, 'location_out_of_range')['place_status']);
        // a fake-location app
        $this->startWork($asha, $key, $office, ['latitude' => -6.8, 'longitude' => 39.27, 'accuracy' => 5, 'mocked' => true])->assertForbidden()->assertJsonPath('code', 'location_out_of_range');
        $check = $this->lastCheck($owner, 'location_out_of_range');
        $this->assertSame('mocked', $check['place_status']);
        $this->assertTrue($check['mocked']);
        $this->assertSame(1, $this->sessions($owner), 'only the one good start wrote attendance');
    }

    public function test_finishing_work_is_never_blocked_by_the_place_but_is_measured(): void
    {
        [$owner, $asha, $key, , $office] = $this->scene(['latitude' => -6.8, 'longitude' => 39.27, 'radius_m' => 150, 'geofence_required' => true]);
        $this->startWork($asha, $key, $office, ['latitude' => -6.8, 'longitude' => 39.27, 'accuracy' => 5])->assertCreated();

        $out = $this->startWork($asha, $key, null, ['latitude' => -6.7, 'longitude' => 39.3], purpose: 'out')->assertOk()->json('data.place');

        $this->assertSame('away', $out['status']);
        $this->assertGreaterThan(10000, $out['distance_m']);
    }

    public function test_the_key_helpers_agree_with_each_other(): void
    {
        [$key, $pem] = $this->keys();
        openssl_sign('hello', $der, $key, OPENSSL_ALGO_SHA256);

        $this->assertTrue(DeviceAttendance::signatureValid($pem, 'hello', base64_encode($der)));
        $this->assertTrue(DeviceAttendance::signatureValid($pem, 'hello', base64_encode($this->derToRaw($der))));
        $this->assertFalse(DeviceAttendance::signatureValid($pem, 'hello!', base64_encode($der)));
        $this->assertFalse(DeviceAttendance::signatureValid($pem, 'hello', 'not base64 !!'));
        $this->assertEqualsWithDelta(111.2, DeviceAttendance::metres(0, 0, 0.001, 0), 0.5);
    }
}
