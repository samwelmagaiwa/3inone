<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\SessionPolicy;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * One account can be signed in on any number of devices at the same time, every one of them
 * keeps working, and nobody is signed out as a side effect:
 *
 *  - signing in somewhere new never ends another device;
 *  - there is no cap on how many devices;
 *  - a device does not expire because days passed since it signed in (only after a very long
 *    time with no use at all, measured from its last use);
 *  - renewing a token on one device cannot touch another's, and the old token survives long
 *    enough for a phone that was offline when the answer got lost.
 *
 * The few things that DO end a session are deliberate: signing out, an administrator
 * deactivating the account, a forgotten-password reset, and changing the password (which
 * signs out the OTHER devices, never the one it was changed on).
 */
class SessionsTest extends TestCase
{
    use RefreshDatabase;

    private const PASSWORD = 'Secret123!';

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::factory()->create([
            'email' => 'shared@example.test',
            'password' => self::PASSWORD,
            'phone_number' => '0712345678',
            'role' => 'sales_officer',
            'is_active' => true,
        ]);
        $this->user->services()->create(['service_type' => 'inventory']);
    }

    /** Sign in as a new device; returns the bearer token the app would store. */
    private function signIn(): string
    {
        $this->app['auth']->forgetGuards();

        return $this->postJson('/api/auth/login', [
            'email' => 'shared@example.test',
            'password' => self::PASSWORD,
            'phone_number' => '0712345678',
        ])->assertOk()->json('data.token');
    }

    private function statusFor(string $token, string $method = 'GET', string $uri = '/api/auth/user'): int
    {
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri)->status();
    }

    private function tokenRow(string $plainTextToken): ?object
    {
        [$id] = explode('|', $plainTextToken);

        return DB::table('personal_access_tokens')->where('id', $id)->first();
    }

    // ---------------------------------------------------- many devices at once

    public function test_signing_in_on_a_second_device_keeps_the_first_signed_in(): void
    {
        $phone = $this->signIn();
        $emulator = $this->signIn();

        $this->assertSame(200, $this->statusFor($phone));
        $this->assertSame(200, $this->statusFor($emulator));
    }

    public function test_there_is_no_limit_on_how_many_devices_stay_signed_in(): void
    {
        $this->assertSame(0, (int) config('sanctum.max_sessions'), 'no cap by default');

        $devices = [];
        for ($i = 0; $i < 12; $i++) {
            // Devices sign in at different times. (Logins are rate-limited per account and address
            // to stop password guessing -- a separate protection from any cap on devices.)
            if ($i > 0 && $i % 5 === 0) {
                $this->travel(61)->seconds();
            }
            $devices[] = $this->signIn();
        }

        foreach ($devices as $i => $token) {
            $this->assertSame(200, $this->statusFor($token), "device #{$i} was signed out");
        }
        $this->assertSame(12, $this->user->tokens()->count());
    }

    public function test_every_device_works_properly_at_the_same_time(): void
    {
        $phone = $this->signIn();
        $tablet = $this->signIn();

        // Interleaved real requests from both, as two people-at-one-account would make them.
        for ($round = 0; $round < 3; $round++) {
            $this->assertSame(200, $this->statusFor($phone, 'GET', '/api/inventory/customers'));
            $this->assertSame(200, $this->statusFor($tablet, 'GET', '/api/inventory/customers'));
            $this->assertSame(200, $this->statusFor($phone, 'GET', '/api/auth/user/services'));
            $this->assertSame(200, $this->statusFor($tablet, 'GET', '/api/auth/user/services'));
        }
    }

    public function test_signing_out_on_one_device_leaves_the_others_signed_in(): void
    {
        $phone = $this->signIn();
        $tablet = $this->signIn();

        $this->assertSame(200, $this->statusFor($phone, 'POST', '/api/auth/logout'));

        $this->assertSame(401, $this->statusFor($phone));
        $this->assertSame(200, $this->statusFor($tablet));
    }

    public function test_the_same_device_signing_in_again_does_not_end_the_others(): void
    {
        $phone = $this->signIn();
        $tablet = $this->signIn();

        $phoneAgain = $this->signIn(); // e.g. the app was reinstalled on the phone

        $this->assertSame(200, $this->statusFor($tablet));
        $this->assertSame(200, $this->statusFor($phoneAgain));
        $this->assertSame(200, $this->statusFor($phone), 'the earlier token is not touched either');
    }

    // ------------------------------------------------- an optional cap, if wanted

    public function test_a_cap_is_still_available_when_someone_configures_one(): void
    {
        config(['sanctum.max_sessions' => 3]);

        $tokens = [];
        for ($i = 0; $i < 4; $i++) {
            $tokens[] = $this->signIn();
        }

        $this->assertSame(401, $this->statusFor($tokens[0]), 'with a cap of 3 the oldest session goes');
        foreach (array_slice($tokens, 1) as $token) {
            $this->assertSame(200, $this->statusFor($token));
        }
        $this->assertSame(3, $this->user->tokens()->count());
    }

    public function test_retired_and_expired_tokens_neither_count_nor_push_a_real_session_out(): void
    {
        config(['sanctum.max_sessions' => 4]);

        // 3 genuine sessions: exactly one slot is still free.
        $real = [];
        for ($i = 0; $i < 3; $i++) {
            $real[] = $this->user->createToken('device')->plainTextToken;
        }

        // Rows /auth/refresh retired (grace window still open)...
        for ($i = 0; $i < 3; $i++) {
            $this->user->createToken('retired')->accessToken->forceFill(['expires_at' => now()->addMinutes(5)])->save();
        }
        // ...and one that already lapsed.
        $this->user->createToken('lapsed')->accessToken->forceFill(['expires_at' => now()->subMinute()])->save();

        $newest = $this->signIn();

        foreach ($real as $token) {
            $this->assertSame(200, $this->statusFor($token), 'a real session was pushed out by non-session rows');
        }
        $this->assertSame(200, $this->statusFor($newest));
        $this->assertDatabaseMissing('personal_access_tokens', ['name' => 'lapsed']);
        $this->assertSame(3, $this->user->tokens()->where('name', 'retired')->count(), 'grace-window rows are left alone');
    }

    // ------------------------------------------ a device is not timed out by age

    public function test_a_device_is_not_signed_out_just_because_days_have_passed_since_it_signed_in(): void
    {
        $this->assertNull(config('sanctum.expiration'), 'no fixed lifetime by default');
        $token = $this->signIn();

        // Used every few weeks for most of a year: never asked to sign in again.
        foreach ([29, 31, 60, 90, 90, 90] as $days) {
            $this->travel($days)->days();
            $this->assertSame(200, $this->statusFor($token), 'signed out after being used again within a year');
        }
    }

    public function test_a_device_nobody_has_touched_for_a_very_long_time_is_dropped_but_use_keeps_it_alive(): void
    {
        $this->assertSame(365, SessionPolicy::idleDays());
        $unused = $this->signIn();
        $used = $this->signIn();

        $this->travel(200)->days();
        $this->assertSame(200, $this->statusFor($used)); // used: its clock restarts
        $this->travel(200)->days();                      // 400 days since sign-in, 200 since the last use
        $this->assertSame(200, $this->statusFor($used), 'a device in regular use outlives the idle limit');
        $this->assertSame(401, $this->statusFor($unused), 'only the device nobody touched for over a year is dropped');
    }

    public function test_the_idle_limit_can_be_switched_off(): void
    {
        config(['sanctum.idle_days' => 0]);
        $token = $this->signIn();

        $this->travel(900)->days();

        $this->assertSame(200, $this->statusFor($token));
    }

    public function test_idle_device_rows_are_tidied_away_without_touching_busy_ones(): void
    {
        $busy = $this->signIn();
        $idle = $this->signIn();
        $this->travel(200)->days();
        $this->assertSame(200, $this->statusFor($busy)); // in use part-way through
        $this->travel(166)->days();                       // 366 days after both signed in
        $this->assertSame(200, $this->statusFor($busy)); // still in regular use
        $neverUsed = $this->user->createToken('never-used')->plainTextToken;
        DB::table('personal_access_tokens')->where('name', 'never-used')->update(['created_at' => now()->subDays(400)]);

        $removed = SessionPolicy::pruneIdle();

        $this->assertSame(2, $removed, 'the idle device and the one never used for over a year');
        $this->assertNotNull($this->tokenRow($busy));
        $this->assertNull($this->tokenRow($idle));
        $this->assertNull($this->tokenRow($neverUsed));
    }

    // ------------------------------------------------------ renewing a token

    public function test_renewing_on_one_device_does_not_touch_the_others(): void
    {
        $phone = $this->signIn();
        $tablet = $this->signIn();

        $this->app['auth']->forgetGuards();
        $newPhone = $this->withHeader('Authorization', "Bearer {$phone}")->postJson('/api/auth/refresh')->assertOk()->json('data.token');

        $this->assertNull($this->tokenRow($tablet)->expires_at, 'the tablet\'s token was not retired');
        $this->assertSame(200, $this->statusFor($tablet));
        $this->assertSame(200, $this->statusFor($newPhone));
    }

    public function test_two_devices_renewing_at_the_same_time_both_carry_on(): void
    {
        $phone = $this->signIn();
        $tablet = $this->signIn();

        $this->app['auth']->forgetGuards();
        $newPhone = $this->withHeader('Authorization', "Bearer {$phone}")->postJson('/api/auth/refresh')->assertOk()->json('data.token');
        $this->app['auth']->forgetGuards();
        $newTablet = $this->withHeader('Authorization', "Bearer {$tablet}")->postJson('/api/auth/refresh')->assertOk()->json('data.token');

        foreach ([$newPhone, $newTablet] as $token) {
            $this->assertSame(200, $this->statusFor($token));
        }
    }

    public function test_a_phone_that_missed_the_renewal_answer_is_not_signed_out_for_days(): void
    {
        $old = $this->signIn();

        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$old}")->postJson('/api/auth/refresh')->assertOk(); // the answer is "lost"

        // The phone only comes back online days later and still holds the old token.
        $this->travel(5)->days();
        $this->assertSame(200, $this->statusFor($old));

        // The grace is generous but finite, so retired tokens do not pile up for ever.
        $this->travel(3)->days();
        $this->assertSame(401, $this->statusFor($old));
    }

    // ----------------------------------------- the deliberate ways a session ends

    public function test_changing_the_password_keeps_this_device_and_signs_out_the_others(): void
    {
        $phone = $this->signIn();
        $tablet = $this->signIn();

        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$phone}")->postJson('/api/auth/change-password', [
            'current_password' => self::PASSWORD,
            'new_password' => 'BrandNewPass99',
            'new_password_confirmation' => 'BrandNewPass99',
        ])->assertOk();

        $this->assertSame(200, $this->statusFor($phone), 'the device it was changed on stays signed in');
        $this->assertSame(401, $this->statusFor($tablet), 'a device that may have been using the old password does not');
    }

    public function test_the_other_devices_can_be_left_signed_in_when_configured(): void
    {
        config(['sanctum.revoke_other_devices_on_password_change' => false]);
        $phone = $this->signIn();
        $tablet = $this->signIn();

        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$phone}")->postJson('/api/auth/change-password', [
            'current_password' => self::PASSWORD,
            'new_password' => 'BrandNewPass99',
            'new_password_confirmation' => 'BrandNewPass99',
        ])->assertOk();

        $this->assertSame(200, $this->statusFor($phone));
        $this->assertSame(200, $this->statusFor($tablet));
    }

    public function test_deactivating_the_account_still_ends_every_device(): void
    {
        $phone = $this->signIn();
        $tablet = $this->signIn();

        $this->user->forceFill(['is_active' => false])->save();

        $this->assertSame(401, $this->statusFor($phone));
        $this->assertSame(401, $this->statusFor($tablet));
    }
}
