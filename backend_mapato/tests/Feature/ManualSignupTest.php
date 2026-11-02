<?php

namespace Tests\Feature;

use App\Models\BusinessRegistration;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Signing up by email: email + phone + password, a text code confirms the phone, the person signs in again with email and password
 * only and is told to fill in the business details (no phone asked again), which creates the registration a super admin approves.
 */
class ManualSignupTest extends TestCase
{
    use RefreshDatabase;

    private const EMAIL = 'asha@example.test';
    private const PHONE = '0743519100';
    private const PASS = 'secret-pass-1';

    private function signup(array $over = [])
    {
        return $this->postJson('/api/auth/signup', $over + [
            'email' => self::EMAIL, 'phone_number' => self::PHONE, 'password' => self::PASS, 'password_confirmation' => self::PASS,
        ]);
    }

    private function confirm(): void
    {
        $this->postJson('/api/auth/register/verify-phone', ['email' => self::EMAIL, 'code' => $this->sms->lastCodeFor(self::PHONE) ?? '000000'])->assertOk();
    }

    private function login(array $over = [])
    {
        return $this->postJson('/api/auth/login', $over + ['email' => self::EMAIL, 'password' => self::PASS]);
    }

    private function details(array $over = []): array
    {
        return $over + [
            'name' => 'Asha Owner', 'business_name' => 'Asha Shop', 'email' => self::EMAIL, 'current_password' => self::PASS,
            'requested_services' => ['inventory'], 'inventory_type' => 'retail',
        ];
    }

    public function test_signing_up_makes_an_inactive_applicant_and_texts_a_code(): void
    {
        $this->signup()->assertCreated()->assertJsonPath('data.phone_verification_required', true);

        $user = User::where('email', self::EMAIL)->firstOrFail();
        $this->assertTrue((bool) $user->is_applicant);
        $this->assertFalse((bool) $user->is_active);
        $this->assertFalse((bool) $user->phone_verified);
        $this->assertNull($user->registration);
        $this->assertNotNull($this->sms->lastCodeFor(self::PHONE), 'the code went to the number given');
    }

    public function test_the_phone_must_be_confirmed_before_anything_else_and_sign_in_needs_no_phone(): void
    {
        $this->signup()->assertCreated();

        $this->login()->assertStatus(403)->assertJsonPath('errors.code', 'phone_not_verified');

        $this->confirm();
        $r = $this->login()->assertOk();
        $this->assertSame('needs_business_details', $r->json('data.status'));
        $this->assertNull($r->json('data.token'), 'no sign-in yet: the business details come first');
    }

    public function test_the_business_details_create_the_registration_without_asking_for_the_phone_again(): void
    {
        $this->signup()->assertCreated();
        $this->confirm();

        $this->postJson('/api/auth/register', $this->details())->assertCreated();

        $user = User::where('email', self::EMAIL)->firstOrFail();
        $this->assertFalse((bool) $user->is_applicant);
        $this->assertSame(self::PHONE, $user->phone_number, 'the phone given at sign-up is kept');
        $this->assertTrue((bool) $user->phone_verified);
        $this->assertSame(BusinessRegistration::PENDING, $user->registration->status);
        $this->assertSame('Asha Owner', $user->name);

        // now it waits for approval, and says so
        $this->login()->assertStatus(403)->assertJsonPath('errors.code', 'registration_pending');
    }

    public function test_the_details_need_the_password_they_signed_up_with(): void
    {
        $this->signup()->assertCreated();
        $this->confirm();

        $this->postJson('/api/auth/register', $this->details(['current_password' => 'not-the-password']))->assertStatus(422);
        $this->assertNull(User::where('email', self::EMAIL)->first()->registration);
    }

    public function test_an_email_already_in_use_cannot_sign_up_again_with_another_password(): void
    {
        $this->signup()->assertCreated();

        $this->signup(['password' => 'another-pass-9', 'password_confirmation' => 'another-pass-9'])->assertStatus(422);
        $this->assertCheckPassword();
    }

    private function assertCheckPassword(): void
    {
        $this->assertTrue(\Illuminate\Support\Facades\Hash::check(self::PASS, User::where('email', self::EMAIL)->value('password')), 'the first password still stands');
    }

    public function test_signing_up_again_with_the_same_details_sends_a_fresh_code_and_keeps_one_account(): void
    {
        $this->signup()->assertCreated();
        $this->signup()->assertCreated();

        $this->assertSame(1, User::where('email', self::EMAIL)->count());
    }

    public function test_an_ordinary_account_still_signs_in_with_email_and_password_only(): void
    {
        User::factory()->create(['email' => 'staff@example.test', 'password' => bcrypt('staff-pass-1'), 'role' => 'sales_officer', 'is_active' => true, 'phone_number' => '0712999888']);

        $this->postJson('/api/auth/login', ['email' => 'staff@example.test', 'password' => 'staff-pass-1'])->assertOk()->assertJsonStructure(['data' => ['token']]);
    }

    public function test_the_old_form_with_a_phone_still_works_and_a_wrong_phone_is_still_refused(): void
    {
        User::factory()->create(['email' => 'staff@example.test', 'password' => bcrypt('staff-pass-1'), 'role' => 'sales_officer', 'is_active' => true, 'phone_number' => '0712999888']);

        $this->postJson('/api/auth/login', ['email' => 'staff@example.test', 'password' => 'staff-pass-1', 'phone_number' => '0712999888'])->assertOk();
        $this->postJson('/api/auth/login', ['email' => 'staff@example.test', 'password' => 'staff-pass-1', 'phone_number' => '0755000111'])->assertStatus(400);
    }

    public function test_a_turned_down_person_applies_again_with_just_their_password(): void
    {
        $this->signup()->assertCreated();
        $this->confirm();
        $this->postJson('/api/auth/register', $this->details())->assertCreated();
        $user = User::where('email', self::EMAIL)->firstOrFail();
        $user->registration->update(['status' => BusinessRegistration::REJECTED, 'rejection_reason' => 'Incomplete']);

        $this->postJson('/api/auth/register', $this->details(['business_name' => 'Asha Shop 2']))->assertCreated();

        $this->assertSame(BusinessRegistration::PENDING, $user->fresh()->registration->status);
        $this->assertSame(self::PHONE, $user->fresh()->phone_number);
    }

    public function test_someone_who_signed_up_by_email_can_carry_on_with_google(): void
    {
        $this->signup()->assertCreated();
        $this->confirm();
        $applicant = User::where('email', self::EMAIL)->firstOrFail();

        // Google vouches for the same email: they are sent on to the form, not refused as a password account
        \Illuminate\Support\Facades\Http::swap(new \Illuminate\Http\Client\Factory());
        \Illuminate\Support\Facades\Http::fake(['oauth2.googleapis.com/*' => \Illuminate\Support\Facades\Http::response([
            'iss' => 'https://accounts.google.com', 'aud' => '427281190551-t67r5mg72ccnso67epg96srp3jkn36cg.apps.googleusercontent.com',
            'sub' => '777', 'email' => self::EMAIL, 'email_verified' => 'true', 'name' => 'Asha', 'exp' => (string) (time() + 3600),
        ])]);

        $r = $this->postJson('/api/auth/google', ['id_token' => 'x'])->assertOk();
        $this->assertSame('new_user', $r->json('data.status'));

        $this->postJson('/api/auth/register', [
            'name' => 'Asha', 'business_name' => 'Asha Shop', 'google_token' => $r->json('data.signup_token'),
            'requested_services' => ['inventory'], 'inventory_type' => 'retail',
        ])->assertCreated();
        $this->assertSame('777', $applicant->fresh()->google_id);
        $this->assertNotNull($applicant->fresh()->registration);
    }
}
