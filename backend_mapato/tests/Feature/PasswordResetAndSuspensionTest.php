<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Sms\SmsCodes;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Two gaps closed together:
 *
 *  - Password reset used to hand the reset token straight back to anyone who knew an
 *    account's email and phone number. The proof now has to arrive BY SMS, on the phone.
 *  - Deactivating a business owner now shuts out their whole business, without deleting
 *    a single account or record; re-activating the owner opens it again.
 */
class PasswordResetAndSuspensionTest extends TestCase
{
    use RefreshDatabase;

    private function owner(array $extra = []): User
    {
        return User::factory()->create(array_merge([
            'role' => 'admin', 'is_active' => true, 'email' => 'owner@example.test',
            'phone_number' => '0743519100', 'password' => 'old-password-1',
        ], $extra));
    }

    private function forgot(string $email = 'owner@example.test', string $phone = '0743519100')
    {
        return $this->postJson('/api/auth/forgot-password', ['email' => $email, 'phone_number' => $phone]);
    }

    private function reset(string $code, string $password = 'brand-new-pass-1', string $email = 'owner@example.test')
    {
        return $this->postJson('/api/auth/reset-password', [
            'email' => $email, 'code' => $code, 'password' => $password, 'password_confirmation' => $password,
        ]);
    }

    private function login(string $email, string $password, string $phone)
    {
        $this->app['auth']->forgetGuards();

        return $this->postJson('/api/auth/login', ['email' => $email, 'password' => $password, 'phone_number' => $phone]);
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    // ------------------------------------------------------ password reset

    public function test_the_proof_is_texted_to_the_phone_and_never_returned_to_the_caller(): void
    {
        $this->owner();

        $response = $this->forgot()->assertOk();

        $this->assertArrayNotHasKey('reset_token', $response->json('data') ?? []);
        $this->assertStringNotContainsString($this->sms->lastCodeFor('0743519100'), $response->getContent(), 'the code is not in the response');
        $sent = $this->sms->to('0743519100');
        $this->assertCount(1, $sent);
        $this->assertTrue($sent[0]['sensitive'], 'a code is marked sensitive, so production logs never hold it');
        $this->assertMatchesRegularExpression('/\b\d{6}\b/', $sent[0]['message']);
    }

    public function test_the_answer_is_the_same_whoever_asks_so_nothing_can_be_probed(): void
    {
        $this->owner();
        $this->owner(['email' => 'gone@example.test', 'phone_number' => '0711000222', 'is_active' => false]);

        $real = $this->forgot()->assertOk()->json();
        $wrongPhone = $this->forgot('owner@example.test', '0788999000')->assertOk()->json();
        $unknown = $this->forgot('nobody@example.test', '0743519100')->assertOk()->json();
        $inactive = $this->forgot('gone@example.test', '0711000222')->assertOk()->json();

        $this->assertSame($real, $wrongPhone);
        $this->assertSame($real, $unknown);
        $this->assertSame($real, $inactive);
        $this->assertCount(1, $this->sms->sent, 'only the real owner of the real phone got a text');
    }

    public function test_the_right_code_changes_the_password_and_signs_every_device_out(): void
    {
        $owner = $this->owner(['must_change_password' => true]);
        $owner->createToken('phone');
        $this->forgot()->assertOk();

        $this->reset($this->sms->lastCodeFor('0743519100'))->assertOk();

        $owner->refresh();
        $this->assertTrue(Hash::check('brand-new-pass-1', $owner->password));
        $this->assertFalse($owner->must_change_password, 'they chose it themselves');
        $this->assertSame(0, $owner->tokens()->count(), 'every device is signed out');
        $this->login('owner@example.test', 'old-password-1', '0743519100')->assertStatus(401);
        $this->login('owner@example.test', 'brand-new-pass-1', '0743519100')->assertOk();
    }

    public function test_a_code_works_once_and_a_wrong_one_does_not_work_at_all(): void
    {
        $owner = $this->owner();
        $this->forgot()->assertOk();
        $code = $this->sms->lastCodeFor('0743519100');
        $wrong = $code === '123456' ? '654321' : '123456';

        $this->reset($wrong)->assertStatus(422);
        $this->reset($code, email: 'someone.else@example.test')->assertStatus(422);
        $this->assertTrue(Hash::check('old-password-1', $owner->fresh()->password), 'a wrong try changed nothing');

        $this->reset($code)->assertOk();
        $this->reset($code, 'another-pass-22')->assertStatus(422); // already used
        $this->assertTrue(Hash::check('brand-new-pass-1', $owner->fresh()->password));
    }

    public function test_five_wrong_tries_destroy_the_code(): void
    {
        // Straight at the service: the route's own rate limit would stop a sixth call
        // within a minute, which is a separate protection (tested below).
        $owner = $this->owner();
        $codes = app(SmsCodes::class);
        $this->assertSame(SmsCodes::SENT, $codes->issue($owner, SmsCodes::PASSWORD_RESET, 'Code :code'));
        $code = $this->sms->lastCodeFor('0743519100');
        $wrong = $code === '123456' ? '654321' : '123456';

        for ($i = 0; $i < 5; $i++) {
            $this->assertFalse($codes->verify($owner, SmsCodes::PASSWORD_RESET, $wrong));
        }

        $this->assertFalse($codes->verify($owner, SmsCodes::PASSWORD_RESET, $code), 'the right code is too late');
    }

    public function test_guessing_codes_over_http_is_rate_limited_too(): void
    {
        $this->owner();
        $this->forgot()->assertOk();

        $statuses = [];
        for ($i = 0; $i < 7; $i++) {
            $statuses[] = $this->reset('000000')->status();
        }

        $this->assertContains(429, $statuses, 'after a handful of tries the route says slow down');
    }

    public function test_a_code_expires_after_ten_minutes(): void
    {
        $this->owner();
        $this->forgot()->assertOk();
        $code = $this->sms->lastCodeFor('0743519100');

        $this->travel(11)->minutes();

        $this->reset($code)->assertStatus(422);
    }

    public function test_a_new_code_cannot_be_requested_every_second_and_replaces_the_old_one(): void
    {
        $this->owner();
        $this->forgot()->assertOk();
        $first = $this->sms->lastCodeFor('0743519100');

        $this->forgot()->assertOk();
        $this->assertCount(1, $this->sms->to('0743519100'), 'asking again straight away sends nothing more');

        $this->travel(61)->seconds();
        $this->forgot()->assertOk();
        $this->assertCount(2, $this->sms->to('0743519100'));
        $second = $this->sms->lastCodeFor('0743519100');

        if ($first !== $second) {
            $this->reset($first)->assertStatus(422); // the old code died when the new one was made
        }
        $this->reset($second)->assertOk();
    }

    public function test_without_a_working_sms_provider_production_refuses_instead_of_pretending(): void
    {
        $this->owner();
        $this->sms->delivering = false;
        $this->app['env'] = 'production';

        $this->forgot()->assertStatus(503)->assertJsonPath('errors.code', 'sms_unavailable');
        $this->assertCount(0, $this->sms->sent);
        $this->assertSame(0, DB::table('sms_codes')->count(), 'no code was created that nobody could receive');
    }

    public function test_a_failing_provider_leaves_no_code_behind(): void
    {
        $this->owner();
        $this->sms->refuseAll();

        $this->forgot()->assertOk(); // same answer: the caller learns nothing

        $this->assertSame(0, DB::table('sms_codes')->count());
    }

    public function test_the_reset_token_of_the_old_flow_is_gone(): void
    {
        $this->owner();
        $this->postJson('/api/auth/reset-password', [
            'email' => 'owner@example.test', 'reset_token' => str_repeat('a', 64),
            'password' => 'brand-new-pass-1', 'password_confirmation' => 'brand-new-pass-1',
        ])->assertStatus(422);
    }

    // ------------------------------------------------- a suspended business

    private function businessWithStaff(): array
    {
        $owner = $this->owner(['email' => 'boss@example.test']);
        $this->givenServices($owner, 'inventory');
        $staff = User::factory()->create([
            'role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id,
            'email' => 'officer@example.test', 'phone_number' => '0711555666', 'password' => 'staff-pass-1',
        ]);
        $this->givenServices($staff, 'inventory');

        return [$owner, $staff];
    }

    public function test_deactivating_the_owner_shuts_the_whole_business_but_deletes_nothing(): void
    {
        [$owner, $staff] = $this->businessWithStaff();
        $this->as($staff, 'GET', '/api/inventory/customers')->assertOk();
        $token = $staff->createToken('device')->plainTextToken;

        $owner->forceFill(['is_active' => false])->save();

        // The staff member's own account is untouched and active -- but the business is shut.
        $this->assertTrue((bool) $staff->fresh()->is_active);
        $this->login('officer@example.test', 'staff-pass-1', '0711555666')
            ->assertForbidden()->assertJsonPath('errors.code', 'business_suspended');
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/inventory/customers')->assertUnauthorized();
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/auth/user')->assertUnauthorized();

        // Nothing was removed.
        $this->assertSame(2, User::whereIn('email', ['boss@example.test', 'officer@example.test'])->count());
    }

    public function test_reactivating_the_owner_opens_the_business_again(): void
    {
        [$owner, $staff] = $this->businessWithStaff();
        $owner->forceFill(['is_active' => false])->save();
        $this->login('officer@example.test', 'staff-pass-1', '0711555666')->assertForbidden();

        $owner->forceFill(['is_active' => true])->save();

        $this->login('officer@example.test', 'staff-pass-1', '0711555666')->assertOk();
        $this->as($staff->fresh(), 'GET', '/api/inventory/customers')->assertOk();
    }

    public function test_a_suspended_business_cannot_reset_its_way_back_in(): void
    {
        [$owner] = $this->businessWithStaff();
        $owner->forceFill(['is_active' => false])->save();

        $this->forgot('officer@example.test', '0711555666')->assertOk();

        $this->assertCount(0, $this->sms->to('0711555666'), 'no code for a suspended business');
    }

    public function test_one_business_being_suspended_does_not_touch_another(): void
    {
        [$owner] = $this->businessWithStaff();
        $other = User::factory()->create(['role' => 'admin', 'is_active' => true, 'email' => 'other@example.test', 'phone_number' => '0755000999', 'password' => 'other-pass-1']);
        $this->givenServices($other, 'inventory');

        $owner->forceFill(['is_active' => false])->save();

        $this->login('other@example.test', 'other-pass-1', '0755000999')->assertOk();
    }
}
