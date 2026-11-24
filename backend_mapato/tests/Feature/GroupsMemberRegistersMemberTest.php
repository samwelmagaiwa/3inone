<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Groups (Vikundi): a member registers a new member. The new person is tied to whoever registered them (the tree), gets a sign-in at once and a
 * one-time password by SMS to the phone number entered for them (the registrar never sees it); signing in with it forces a new password of 8 or
 * more characters and a fresh sign-in.
 */
class GroupsMemberRegistersMemberTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    /** @var array<string, User> */
    private array $people = [];

    /** @var array<string, int> */
    private array $ids = [];

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'MEG Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG Group']);
        foreach ([['asha', '0713000001'], ['juma', '0713000002']] as [$key, $phone]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, '/api/groups' . $uri, $body);
    }

    private function otpTo(string $phone): ?string
    {
        $messages = $this->sms->to($phone);
        for ($i = count($messages) - 1; $i >= 0; $i--) {
            if (preg_match('/nenosiri la muda: ([A-Za-z0-9]+)\./', $messages[$i]['message'], $m) === 1) {
                return $m[1];
            }
        }

        return null;
    }

    private function login(string $phone, string $password)
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->postJson('/api/auth/login', ['email' => $phone, 'password' => $password]);
    }

    private function newMember(User $by, string $phone = '0715000111', string $name = 'Neema New')
    {
        return $this->api($by, 'POST', '/members/register', ['full_name' => $name, 'phone' => $phone, 'gender' => 'female', 'region' => 'Dar es Salaam']);
    }

    public function test_a_member_registers_a_new_member_who_is_tied_to_them_and_gets_a_one_time_password_by_sms(): void
    {
        $res = $this->newMember($this->people['asha'])->assertCreated();
        $id = (int) $res->json('data.member.id');
        $res->assertJsonPath('data.sms_sent', true)->assertJsonPath('data.member.status', 'submitted');

        // Tied to the member who brought them in, so the tree is complete.
        $this->assertSame($this->ids['asha'], (int) DB::table('group_members')->where('id', $id)->value('referrer_id'));
        $this->assertSame('member', DB::table('group_members')->where('id', $id)->value('source'));
        $this->api($this->people['asha'], 'GET', '/me/referrals')->assertOk();

        // The text went to the number entered for the new person, under the group's name, with the password in it.
        $otp = $this->otpTo('0715000111');
        $this->assertNotNull($otp);
        $this->assertGreaterThanOrEqual(8, strlen($otp));
        $message = $this->sms->to('0715000111')[0]['message'];
        $this->assertStringContainsString('MEG Group', $message);
        $this->assertStringContainsString('Asha Member', $message);

        // The registrar is never shown it.
        $this->assertStringNotContainsString($otp, json_encode($res->json()));
        $account = User::query()->withoutGlobalScopes()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        $this->assertSame(User::GROUP_MEMBER_ROLE, $account->role);
        $this->assertTrue((bool) $account->must_change_password);
    }

    public function test_the_new_member_signs_in_with_the_one_time_password_then_must_choose_a_new_one_of_8_characters_and_sign_in_again(): void
    {
        $this->newMember($this->people['asha'])->assertCreated();
        $otp = (string) $this->otpTo('0715000111');

        $login = $this->login('0715000111', $otp)->assertOk();
        $this->assertTrue((bool) $login->json('data.user.must_change_password'), 'the app shows the first-login screen');
        $token = $login->json('data.token') ?? $login->json('data.access_token') ?? $login->json('token');
        $this->assertNotEmpty($token);

        // Too short is refused; the one-time password again is refused; 8 characters pass.
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $change = fn (array $b) => $this->withHeader('Authorization', "Bearer {$token}")->postJson('/api/auth/change-password', $b);
        $change(['current_password' => $otp, 'new_password' => 'short1', 'new_password_confirmation' => 'short1'])->assertStatus(422);
        $change(['current_password' => $otp, 'new_password' => $otp, 'new_password_confirmation' => $otp])->assertStatus(422);
        $change(['current_password' => 'wrong-one', 'new_password' => 'Brand-new-9', 'new_password_confirmation' => 'Brand-new-9'])->assertStatus(422);
        $change(['current_password' => $otp, 'new_password' => 'Brand-new-9', 'new_password_confirmation' => 'Brand-new-9'])->assertOk();

        // The one-time password no longer works; the new one does, and nothing forces another change.
        $this->login('0715000111', $otp)->assertStatus(401);
        $again = $this->login('0715000111', 'Brand-new-9')->assertOk();
        $this->assertFalse((bool) $again->json('data.user.must_change_password'));
    }

    public function test_a_phone_that_belongs_to_someone_already_is_refused_and_nothing_is_sent(): void
    {
        $this->newMember($this->people['asha'], '0713000002', 'Another Juma')->assertStatus(422)->assertJsonPath('code', 'duplicate_phone');
        $this->assertCount(0, $this->sms->to('0713000002'));
        $this->newMember($this->people['asha'], '0715000111')->assertCreated();
        $this->newMember($this->people['juma'], '0715000111', 'Same Phone')->assertStatus(422);
    }

    public function test_a_person_who_is_not_an_active_member_cannot_register_anyone(): void
    {
        $this->newMember($this->people['asha'])->assertCreated();
        $applicant = User::query()->withoutGlobalScopes()->find(DB::table('group_members')->where('phone', '0715000111')->value('user_id'));
        $this->newMember($applicant, '0716000222', 'By Applicant')->assertStatus(403)->assertJsonPath('code', 'not_a_member');
        $this->assertSame(0, DB::table('group_members')->where('phone', '0716000222')->count());
    }

    public function test_the_text_can_be_asked_for_again_by_whoever_registered_them_until_they_choose_their_own_password(): void
    {
        $this->newMember($this->people['asha'])->assertCreated();
        $id = (int) DB::table('group_members')->where('phone', '0715000111')->value('id');
        $first = (string) $this->otpTo('0715000111');

        // Someone else cannot; the registrar can; the registrar is not shown it; the old one-time password stops working.
        $this->api($this->people['juma'], 'POST', "/members/{$id}/resend-otp")->assertForbidden();
        $res = $this->api($this->people['asha'], 'POST', "/members/{$id}/resend-otp")->assertOk()->assertJsonPath('data.sms_sent', true);
        $second = (string) $this->otpTo('0715000111');
        $this->assertNotSame($first, $second);
        $this->assertStringNotContainsString($second, json_encode($res->json()));
        $this->login('0715000111', $first)->assertStatus(401);
        $login = $this->login('0715000111', $second)->assertOk();

        // After they choose their own password there is nothing to resend.
        $token = $login->json('data.token') ?? $login->json('data.access_token') ?? $login->json('token');
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $this->withHeader('Authorization', "Bearer {$token}")->postJson('/api/auth/change-password', ['current_password' => $second, 'new_password' => 'Chosen-pass-1', 'new_password_confirmation' => 'Chosen-pass-1'])->assertOk();
        $this->api($this->people['asha'], 'POST', "/members/{$id}/resend-otp")->assertStatus(409)->assertJsonPath('code', 'already_set');
    }

    public function test_when_the_text_cannot_be_sent_the_registration_still_stands_and_says_so(): void
    {
        $this->sms->refuseAll();
        $res = $this->newMember($this->people['asha'])->assertCreated();
        $res->assertJsonPath('data.sms_sent', false);
        $this->assertSame(1, DB::table('group_members')->where('phone', '0715000111')->count());
        $this->assertNull($this->otpTo('0715000111'));
    }

    public function test_the_people_a_member_brought_in_are_tied_to_them_and_join_their_branch_of_the_tree_once_approved(): void
    {
        $first = (int) $this->newMember($this->people['asha'], '0715000111', 'First Brought')->assertCreated()->json('data.member.id');
        $this->newMember($this->people['asha'], '0715000222', 'Second Brought')->assertCreated();

        // From the first moment the leaders see who brought them in (an application is not part of the tree until it is approved).
        $file = $this->api($this->owner, 'GET', "/members/{$first}")->assertOk();
        $this->assertSame('Asha Member', $file->json('data.member.referrer_name'));
        $ashaFile = $this->api($this->owner, 'GET', "/members/{$this->ids['asha']}")->assertOk();
        $this->assertSame(['First Brought', 'Second Brought'], collect($ashaFile->json('data.referrals'))->pluck('full_name')->sort()->values()->all());
        $this->assertStringNotContainsString('First Brought', json_encode($this->api($this->people['asha'], 'GET', '/me/referrals')->json()));

        // Approved, they appear in the branch of the member who brought them in, and not in anyone else's.
        $this->api($this->owner, 'POST', "/members/{$first}/status", ['action' => 'approve'])->assertOk();
        $this->assertStringContainsString('First Brought', json_encode($this->api($this->people['asha'], 'GET', '/me/referrals')->json()));
        $this->assertStringNotContainsString('First Brought', json_encode($this->api($this->people['juma'], 'GET', '/me/referrals')->json()));
    }
}
