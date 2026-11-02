<?php

namespace Tests\Feature;

use App\Models\BusinessRegistration;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * Sign in with Google: a new person is sent to register (with no password), registers, waits for approval, and then signs in with
 * Google alone. Forged or foreign tokens are refused, and Google is never tied to staff or the super admin by email.
 */
class GoogleSignInTest extends TestCase
{
    use RefreshDatabase;

    private const WEB = '427281190551-t67r5mg72ccnso67epg96srp3jkn36cg.apps.googleusercontent.com';

    private function google(array $claims = []): void
    {
        Http::swap(new \Illuminate\Http\Client\Factory());
        Http::fake(['oauth2.googleapis.com/*' => Http::response($claims + [
            'iss' => 'https://accounts.google.com', 'aud' => self::WEB, 'sub' => '1100', 'email' => 'neema@gmail.com',
            'email_verified' => 'true', 'name' => 'Neema Mushi', 'exp' => (string) (time() + 3600),
        ])]);
    }

    private function signIn()
    {
        return $this->postJson('/api/auth/google', ['id_token' => 'any-token']);
    }

    private function register(string $signup, array $extra = [])
    {
        return $this->postJson('/api/auth/register', $extra + [
            'name' => 'Neema Mushi', 'business_name' => 'Neema Shop', 'phone_number' => '0712000111', 'google_token' => $signup,
            'requested_services' => ['inventory'], 'inventory_type' => 'retail',
        ]);
    }

    public function test_a_new_person_is_sent_to_register_and_no_account_exists_yet(): void
    {
        $this->google();

        $r = $this->signIn()->assertOk();

        $this->assertSame('new_user', $r->json('data.status'));
        $this->assertSame('neema@gmail.com', $r->json('data.email'));
        $this->assertNotEmpty($r->json('data.signup_token'));
        $this->assertDatabaseMissing('users', ['email' => 'neema@gmail.com']);
    }

    public function test_registering_with_google_needs_no_password_and_waits_for_approval_then_signs_in_with_google(): void
    {
        $this->google();
        $signup = $this->signIn()->json('data.signup_token');

        $this->register($signup)->assertCreated();

        $user = User::where('email', 'neema@gmail.com')->firstOrFail();
        $this->assertSame('1100', $user->google_id);
        $this->assertFalse((bool) $user->is_active);
        $this->assertSame(BusinessRegistration::PENDING, $user->registration->status);

        // second time, before approval: told to wait
        $this->signIn()->assertStatus(403)->assertJsonPath('errors.code', 'registration_pending');

        // approved: signs in with Google alone
        $user->is_active = true;
        $user->save();
        $this->signIn()->assertOk()->assertJsonStructure(['data' => ['token', 'user']]);
    }

    public function test_a_token_for_another_app_or_an_unverified_email_is_refused(): void
    {
        $this->google(['aud' => 'someone-elses-app.apps.googleusercontent.com']);
        $this->signIn()->assertStatus(401);

        $this->google(['email_verified' => 'false']);
        $this->signIn()->assertStatus(401);

        $this->google(['exp' => (string) (time() - 10)]);
        $this->signIn()->assertStatus(401);
    }

    public function test_a_forged_sign_up_token_cannot_register(): void
    {
        $this->register('forged-token')->assertStatus(422)->assertJsonPath('errors.code', 'google_token_invalid');
        $this->assertDatabaseMissing('users', ['phone_number' => '0712000111']);
    }

    public function test_the_email_comes_from_google_not_from_the_request(): void
    {
        $this->google();
        $signup = $this->signIn()->json('data.signup_token');

        $this->register($signup, ['email' => 'someone.else@gmail.com'])->assertCreated();

        $this->assertDatabaseHas('users', ['email' => 'neema@gmail.com']);
        $this->assertDatabaseMissing('users', ['email' => 'someone.else@gmail.com']);
    }

    public function test_google_is_not_tied_to_staff_or_the_super_admin_by_their_email(): void
    {
        $staff = User::factory()->create(['email' => 'neema@gmail.com', 'role' => 'sales_officer', 'is_active' => true, 'phone_number' => '0712000222']);
        $this->google();

        $this->signIn()->assertStatus(403)->assertJsonPath('errors.code', 'password_account');
        $this->assertNull($staff->fresh()->google_id);
    }

    public function test_a_turned_down_application_can_be_sent_again_with_google(): void
    {
        $this->google();
        $signup = $this->signIn()->json('data.signup_token');
        $this->register($signup)->assertCreated();
        $user = User::where('email', 'neema@gmail.com')->firstOrFail();
        $user->registration->update(['status' => BusinessRegistration::REJECTED, 'rejection_reason' => 'Incomplete']);

        // signing in again offers the form again, with a fresh sign-up token
        $again = $this->signIn()->assertOk();
        $this->assertSame('new_user', $again->json('data.status'));

        $this->register($again->json('data.signup_token'), ['business_name' => 'Neema Shop 2'])->assertCreated();
        $this->assertSame(BusinessRegistration::PENDING, $user->fresh()->registration->status);
    }

    public function test_an_existing_owner_is_tied_to_google_on_first_use_and_then_only_that_google_account_works(): void
    {
        $owner = User::factory()->create(['email' => 'neema@gmail.com', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0712000333']);
        BusinessRegistration::create(['user_id' => $owner->id, 'business_name' => 'Old Shop', 'requested_services' => ['inventory'], 'status' => BusinessRegistration::APPROVED]);
        $this->google();

        $this->signIn()->assertOk()->assertJsonStructure(['data' => ['token']]);
        $this->assertSame('1100', $owner->fresh()->google_id);

        $this->google(['sub' => '9999']);
        $this->signIn()->assertStatus(403)->assertJsonPath('errors.code', 'google_account_mismatch');
    }
}
