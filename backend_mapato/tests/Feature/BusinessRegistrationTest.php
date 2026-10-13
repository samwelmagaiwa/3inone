<?php

namespace Tests\Feature;

use App\Models\BusinessRegistration;
use App\Models\Rental\Property;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * A business owner registers; a super admin reviews the details and assigns the
 * services; the owner then signs in, sees only those services, and creates their
 * own staff for them. Everything here goes through the real HTTP API.
 */
class BusinessRegistrationTest extends TestCase
{
    use RefreshDatabase;

    private function superAdmin(): User
    {
        return User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
    }

    private function payload(array $overrides = []): array
    {
        $payload = array_merge([
            'name' => 'Asha Owner',
            'business_name' => 'Asha Rentals',
            'email' => 'asha@example.test',
            'phone_number' => '0743519100',
            'password' => 'secret-pass-1',
            'password_confirmation' => 'secret-pass-1',
            'requested_services' => ['rental'],
            'region' => 'Dar es Salaam',
            'district' => 'Kinondoni',
            'address' => 'Mikocheni B',
            'id_number' => '19900101-12345-00001-1',
            'notes' => 'Two apartment blocks',
        ], $overrides);

        // Asking for inventory means saying what kind of stock business it is (see InventoryTypeTest).
        if (in_array('inventory', $payload['requested_services'], true) && ! array_key_exists('inventory_type', $payload)) {
            $payload['inventory_type'] = 'depot';
        }

        return $payload;
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function login(string $email, string $password, string $phone)
    {
        $this->app['auth']->forgetGuards();

        return $this->postJson('/api/auth/login', ['email' => $email, 'password' => $password, 'phone_number' => $phone]);
    }

    /**
     * Register, confirm the phone with the code that was texted (as a real applicant does),
     * and return the BusinessRegistration.
     */
    private function register(array $overrides = []): BusinessRegistration
    {
        $payload = $this->payload($overrides);
        $this->postJson('/api/auth/register', $payload)->assertCreated();
        $this->confirmPhone($payload['email'], $payload['phone_number']);

        return BusinessRegistration::whereHas('user', fn ($q) => $q->where('email', $payload['email']))->firstOrFail();
    }

    /** Enter the latest code texted to $phone. */
    private function confirmPhone(string $email, string $phone)
    {
        return $this->postJson('/api/auth/register/verify-phone', [
            'email' => $email, 'code' => $this->sms->lastCodeFor($phone) ?? '000000',
        ]);
    }

    private function approve(BusinessRegistration $registration, array $services)
    {
        return $this->as($this->superAdmin(), 'POST', "/api/admin/registrations/{$registration->id}/approve", ['service_types' => $services]);
    }

    // ------------------------------------------------------- registering

    public function test_a_business_registers_and_waits_for_approval(): void
    {
        $response = $this->postJson('/api/auth/register', $this->payload())->assertCreated();
        $this->assertSame('pending', $response->json('data.status'));
        $this->assertNull($response->json('data.token'), 'registering never signs anyone in');

        $user = User::where('email', 'asha@example.test')->firstOrFail();
        $this->assertSame('admin', $user->role, 'the role they are applying for');
        $this->assertFalse((bool) $user->is_active, 'nothing works until a super admin approves');
        $this->assertSame(0, $user->services()->count(), 'no service is assigned by registering');

        $registration = BusinessRegistration::firstOrFail();
        $this->assertSame('Asha Rentals', $registration->business_name);
        $this->assertSame(['rental'], $registration->requested_services);
        $this->assertSame('pending', $registration->status);

        $login = $this->login('asha@example.test', 'secret-pass-1', '0743519100')->assertForbidden();
        $this->assertSame('registration_pending', $login->json('errors.code'));
        $this->assertSame(0, DB::table('personal_access_tokens')->count(), 'and no token was issued');
    }

    // ------------------------------------------- proving the phone is theirs

    public function test_registering_texts_a_code_and_the_super_admin_sees_whether_it_was_confirmed(): void
    {
        $response = $this->postJson('/api/auth/register', $this->payload())->assertCreated();
        $this->assertTrue($response->json('data.phone_verification_required'));
        $this->assertTrue($response->json('data.code_sent'));
        $this->assertNotNull($this->sms->lastCodeFor('0743519100'), 'the code went to the number they gave');
        $this->assertFalse((bool) User::where('email', 'asha@example.test')->value('phone_verified'));

        $super = $this->superAdmin();
        $registration = BusinessRegistration::firstOrFail();
        $row = fn () => $this->as($super, 'GET', "/api/admin/registrations/{$registration->id}")->json('data.user.phone_verified');
        $this->assertFalse($row());

        $this->confirmPhone('asha@example.test', '0743519100')->assertOk()->assertJsonPath('data.phone_verified', true);
        $this->assertTrue($row());
    }

    public function test_a_wrong_or_used_code_does_not_confirm_the_phone(): void
    {
        $this->postJson('/api/auth/register', $this->payload())->assertCreated();
        $code = $this->sms->lastCodeFor('0743519100');
        $wrong = $code === '111111' ? '222222' : '111111';

        $this->postJson('/api/auth/register/verify-phone', ['email' => 'asha@example.test', 'code' => $wrong])->assertStatus(422);
        $this->postJson('/api/auth/register/verify-phone', ['email' => 'nobody@example.test', 'code' => $code])->assertStatus(422);
        $this->assertFalse((bool) User::where('email', 'asha@example.test')->value('phone_verified'));

        // Five wrong tries kill the code, even for the right answer afterwards.
        for ($i = 0; $i < 4; $i++) {
            $this->postJson('/api/auth/register/verify-phone', ['email' => 'asha@example.test', 'code' => $wrong])->assertStatus(422);
        }
        $this->postJson('/api/auth/register/verify-phone', ['email' => 'asha@example.test', 'code' => $code])->assertStatus(422);
        $this->assertFalse((bool) User::where('email', 'asha@example.test')->value('phone_verified'));
    }

    public function test_approval_needs_a_confirmed_phone_unless_the_super_admin_overrides_on_purpose(): void
    {
        $this->postJson('/api/auth/register', $this->payload())->assertCreated();
        $registration = BusinessRegistration::firstOrFail();
        $super = $this->superAdmin();

        $this->as($super, 'POST', "/api/admin/registrations/{$registration->id}/approve", ['service_types' => ['rental']])
            ->assertStatus(422)->assertJsonPath('errors.code', 'phone_not_verified');
        $this->assertSame('pending', $registration->fresh()->status);
        $this->assertFalse((bool) User::where('email', 'asha@example.test')->value('is_active'));

        $this->as($super, 'POST', "/api/admin/registrations/{$registration->id}/approve", ['service_types' => ['rental'], 'allow_unverified' => true])
            ->assertOk();
        $this->assertSame('approved', $registration->fresh()->status);
    }

    public function test_a_new_code_can_be_requested_but_not_in_quick_succession(): void
    {
        // Registering also texts a "we received your application" note; count only the codes.
        $codes = fn () => array_filter($this->sms->to('0743519100'), fn (array $m) => $m['sensitive']);

        $this->postJson('/api/auth/register', $this->payload())->assertCreated();
        $this->assertCount(1, $codes());

        // Too soon: the answer is the same, but no second code goes out.
        $this->postJson('/api/auth/register/resend-code', ['email' => 'asha@example.test'])->assertOk();
        $this->assertCount(1, $codes());

        $this->travel(61)->seconds();
        $this->postJson('/api/auth/register/resend-code', ['email' => 'asha@example.test'])->assertOk();
        $this->assertCount(2, $codes());

        // An unknown email gets the same answer and nothing is sent anywhere.
        $before = count($this->sms->sent);
        $this->postJson('/api/auth/register/resend-code', ['email' => 'nobody@example.test'])->assertOk()->assertJsonPath('data.code_sent', true);
        $this->assertCount($before, $this->sms->sent);
    }

    // --------------------------------- nobody can take over a registration

    public function test_knowing_the_email_and_phone_is_not_enough_to_take_over_a_rejected_registration(): void
    {
        $registration = $this->register();
        $this->as($this->superAdmin(), 'POST', "/api/admin/registrations/{$registration->id}/reject", ['reason' => 'Unclear'])->assertOk();
        $hashBefore = User::where('email', 'asha@example.test')->value('password');

        // An outsider who knows both the email and the phone, but not the password.
        $this->postJson('/api/auth/register', $this->payload(['password' => 'attacker-pass-9', 'password_confirmation' => 'attacker-pass-9', 'business_name' => 'Hijacked Ltd']))
            ->assertStatus(422);

        $this->assertSame($hashBefore, User::where('email', 'asha@example.test')->value('password'), 'the password was not overwritten');
        $this->assertSame('rejected', $registration->fresh()->status);
        $this->assertSame('Asha Rentals', $registration->fresh()->business_name);
        $this->login('asha@example.test', 'secret-pass-1', '0743519100')->assertForbidden(); // still the original, still rejected
    }

    public function test_a_stranger_is_not_told_that_someone_elses_registration_is_pending(): void
    {
        $this->register();

        // The owner, who knows the password, is told it is pending...
        $this->postJson('/api/auth/register', $this->payload())->assertStatus(409)->assertJsonPath('errors.code', 'registration_pending');
        // ...anyone else just gets "already registered".
        $this->postJson('/api/auth/register', $this->payload(['password' => 'guess-guess-9', 'password_confirmation' => 'guess-guess-9']))
            ->assertStatus(422)->assertJsonValidationErrors('email');
    }

    public function test_a_phone_number_is_not_an_identity_so_it_can_never_take_over_a_registration(): void
    {
        $first = $this->register();
        $hash = User::where('email', 'asha@example.test')->value('password');

        // Someone else applies with the SAME phone but their own email: businesses are separate,
        // so that is simply another registration. Matching on the phone would have let them
        // overwrite the first applicant's pending registration; it must leave it exactly as it was.
        $this->postJson('/api/auth/register', $this->payload([
            'email' => 'other@example.test', 'business_name' => 'Other Traders',
            'password' => 'guess-guess-9', 'password_confirmation' => 'guess-guess-9',
        ]))->assertCreated();

        $this->assertSame(2, BusinessRegistration::count());
        $this->assertSame($hash, User::where('email', 'asha@example.test')->value('password'));
        $this->assertSame('Asha Rentals', $first->fresh()->business_name);
        $this->assertSame('pending', $first->fresh()->status);
        $this->assertSame('Other Traders', BusinessRegistration::whereHas('user', fn ($u) => $u->where('email', 'other@example.test'))->value('business_name'));
    }

    public function test_registration_is_validated(): void
    {
        $registration = $this->register();

        // While the first registration is still pending, a second attempt for the same person
        // is a conflict, not a validation error (see test_duplicate_pending_registration_returns_conflict).
        // Once it is approved the account exists, and these are validation errors:
        $this->approve($registration, ['rental'])->assertOk();

        // The email is the sign-in name: the same one cannot register twice, whatever the phone.
        $this->postJson('/api/auth/register', $this->payload(['phone_number' => '0712000000']))
            ->assertStatus(422)->assertJsonValidationErrors('email');

        $fresh = ['email' => 'new@example.test', 'phone_number' => '0755111222'];
        $this->postJson('/api/auth/register', $this->payload($fresh + ['requested_services' => []]))
            ->assertStatus(422)->assertJsonValidationErrors('requested_services');
        $this->postJson('/api/auth/register', $this->payload($fresh + ['requested_services' => ['payroll']]))
            ->assertStatus(422)->assertJsonValidationErrors('requested_services.0');
        $this->postJson('/api/auth/register', $this->payload($fresh + ['password' => 'short', 'password_confirmation' => 'short']))
            ->assertStatus(422)->assertJsonValidationErrors('password');
        $this->postJson('/api/auth/register', $this->payload($fresh + ['password_confirmation' => 'different-pass']))
            ->assertStatus(422)->assertJsonValidationErrors('password');
        $this->postJson('/api/auth/register', $this->payload($fresh + ['business_name' => '']))
            ->assertStatus(422)->assertJsonValidationErrors('business_name');

        $this->assertSame(1, User::where('role', 'admin')->count(), 'invalid attempts create nothing');
    }

    // ------------------------------------------------- the super admin's view

    public function test_only_a_super_admin_reviews_registrations(): void
    {
        $registration = $this->register();
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'rental');

        $this->getJson('/api/admin/registrations')->assertUnauthorized();
        foreach ([
            ['GET', '/api/admin/registrations'],
            ['GET', "/api/admin/registrations/{$registration->id}"],
            ['POST', "/api/admin/registrations/{$registration->id}/approve"],
            ['POST', "/api/admin/registrations/{$registration->id}/reject"],
        ] as [$method, $uri]) {
            $this->as($owner, $method, $uri, ['service_types' => ['rental'], 'reason' => 'x'])->assertForbidden();
        }
        $this->assertSame('pending', $registration->fresh()->status, 'nothing a non-super-admin sent had any effect');
    }

    public function test_the_super_admin_sees_the_registration_details(): void
    {
        $registration = $this->register(['requested_services' => ['rental', 'transport']]);
        $this->register(['email' => 'juma@example.test', 'phone_number' => '0755000111', 'business_name' => 'Juma Transport', 'name' => 'Juma']);
        $super = $this->superAdmin();

        $list = $this->as($super, 'GET', '/api/admin/registrations')->assertOk();
        $this->assertSame(['pending' => 2, 'approved' => 0, 'rejected' => 0], $list->json('meta.counts'));
        $this->assertCount(2, $list->json('data'));

        $one = collect($list->json('data'))->firstWhere('business_name', 'Asha Rentals');
        $this->assertSame('pending', $one['status']);
        $this->assertSame(['rental', 'transport'], $one['requested_services']);
        $this->assertSame('Dar es Salaam', $one['region']);
        $this->assertSame('Mikocheni B', $one['address']);
        $this->assertSame('19900101-12345-00001-1', $one['id_number']);
        $this->assertSame('Two apartment blocks', $one['notes']);
        $this->assertNotEmpty($one['submitted_at']);
        $this->assertSame(
            ['name' => 'Asha Owner', 'email' => 'asha@example.test', 'phone_number' => '0743519100'],
            collect($one['user'])->only(['name', 'email', 'phone_number'])->all()
        );
        $this->assertArrayNotHasKey('password', $one['user']);

        $this->as($super, 'GET', "/api/admin/registrations/{$registration->id}")->assertOk()
            ->assertJsonPath('data.business_name', 'Asha Rentals');

        $this->assertCount(1, $this->as($super, 'GET', '/api/admin/registrations?q=Juma')->json('data'));
        $this->assertCount(0, $this->as($super, 'GET', '/api/admin/registrations?status=approved')->json('data'));
        $this->assertCount(2, $this->as($super, 'GET', '/api/admin/registrations?status=all')->json('data'));
    }

    // ------------------------------------------------ approving and rejecting

    public function test_approving_assigns_the_services_and_lets_the_owner_in(): void
    {
        $registration = $this->register(['requested_services' => ['rental', 'transport', 'inventory']]);

        // The super admin gives them what they decide -- not necessarily what was asked for.
        $this->approve($registration, ['rental', 'transport'])->assertOk()
            ->assertJsonPath('data.status', 'approved')
            ->assertJsonPath('data.assigned_services', ['rental', 'transport']);

        $registration->refresh();
        $this->assertSame('approved', $registration->status);
        $this->assertNotNull($registration->reviewed_at);
        $this->assertNotNull($registration->reviewed_by);

        $login = $this->login('asha@example.test', 'secret-pass-1', '0743519100')->assertOk();
        $token = $login->json('data.token');
        $this->assertNotEmpty($token);

        $this->app['auth']->forgetGuards();
        $services = $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/auth/user/services')->assertOk();
        $this->assertEqualsCanonicalizing(['rental', 'transport'], $services->json('services'));
        $this->assertFalse($services->json('is_unbound'));

        // ...and the server enforces it, not just the app.
        $owner = User::where('email', 'asha@example.test')->firstOrFail();
        $this->assertNotSame(403, $this->as($owner, 'GET', '/api/rental/properties')->status());
        $this->assertNotSame(403, $this->as($owner, 'GET', '/api/admin/vehicles')->status());
        $this->as($owner, 'GET', '/api/inventory/products')->assertForbidden()->assertJsonPath('code', 'service_not_assigned');
    }

    public function test_a_rejected_registration_stays_locked_out_and_can_be_approved_later(): void
    {
        $registration = $this->register();
        $super = $this->superAdmin();

        $this->as($super, 'POST', "/api/admin/registrations/{$registration->id}/reject")->assertStatus(422);
        $this->as($super, 'POST', "/api/admin/registrations/{$registration->id}/reject", ['reason' => 'Documents unclear'])
            ->assertOk()->assertJsonPath('data.status', 'rejected');

        $login = $this->login('asha@example.test', 'secret-pass-1', '0743519100')->assertForbidden();
        $this->assertSame('registration_rejected', $login->json('errors.code'));
        $this->assertStringContainsString('Documents unclear', $login->json('message'));

        // A super admin can change their mind.
        $this->approve($registration, ['rental'])->assertOk();
        $this->login('asha@example.test', 'secret-pass-1', '0743519100')->assertOk();
    }

    public function test_a_rejected_registration_can_reapply_and_be_reviewed(): void
    {
        $registration = $this->register();
        $super = $this->superAdmin();

        $this->as($super, 'POST', "/api/admin/registrations/{$registration->id}/reject", ['reason' => 'Clearer ID required'])->assertOk();
        $this->assertSame('rejected', $registration->fresh()->status);

        // Re-applying with updated details succeeds and revives the registration
        $reapply = $this->postJson('/api/auth/register', $this->payload([
            'business_name' => 'Asha Rentals Revised',
            'notes' => 'New clear ID attached',
            'requested_services' => ['rental', 'inventory'],
        ]))->assertCreated();

        $this->assertTrue($reapply->json('data.is_reapplication'));
        $this->assertSame('pending', $reapply->json('data.status'));

        $fresh = $registration->fresh();
        $this->assertSame('pending', $fresh->status);
        $this->assertSame('Asha Rentals Revised', $fresh->business_name);
        $this->assertSame('New clear ID attached', $fresh->notes);
        $this->assertNull($fresh->rejection_reason);
        $this->assertNull($fresh->reviewed_by);
        $this->assertNull($fresh->reviewed_at);

        // Login now reports pending rather than rejected
        $login = $this->login('asha@example.test', 'secret-pass-1', '0743519100')->assertForbidden();
        $this->assertSame('registration_pending', $login->json('errors.code'));

        // Super admin now sees the updated application and approves it
        $this->approve($fresh, ['rental', 'inventory'])->assertOk();
        $this->login('asha@example.test', 'secret-pass-1', '0743519100')->assertOk();
    }

    public function test_duplicate_pending_registration_returns_conflict(): void
    {
        $this->register();
        $this->postJson('/api/auth/register', $this->payload())
            ->assertStatus(409)
            ->assertJsonPath('errors.code', 'registration_pending');
    }

    public function test_approval_needs_services_and_cannot_be_repeated(): void
    {
        $registration = $this->register();
        $super = $this->superAdmin();

        $this->as($super, 'POST', "/api/admin/registrations/{$registration->id}/approve", ['service_types' => []])->assertStatus(422);
        $this->as($super, 'POST', "/api/admin/registrations/{$registration->id}/approve", ['service_types' => ['payroll']])->assertStatus(422);
        $this->assertSame('pending', $registration->fresh()->status);

        $this->approve($registration, ['rental'])->assertOk();
        $this->approve($registration, ['transport'])->assertStatus(409)->assertJsonPath('errors.code', 'already_approved');
        $this->as($super, 'POST', "/api/admin/registrations/{$registration->id}/reject", ['reason' => 'no'])->assertStatus(409);
        $this->assertSame(['rental'], User::where('email', 'asha@example.test')->first()->services()->pluck('service_type')->all());
    }

    // ----------------------------------------------- the owner and their staff

    public function test_an_approved_owner_creates_staff_only_for_their_own_services(): void
    {
        $registration = $this->register(['requested_services' => ['rental']]);
        $this->approve($registration, ['rental'])->assertOk();
        $owner = User::where('email', 'asha@example.test')->firstOrFail();

        $staff = fn(array $o = []) => array_merge([
            'name' => 'Rental Manager',
            'email' => 'mgr@example.test',
            'phone_number' => '0711222333',
            'password' => 'STAFFNEW1',
            'password_confirmation' => 'STAFFNEW1',
            'role' => 'manager',
            'service_types' => ['rental'],
            'permissions' => ['manage_properties_rental'],
        ], $o);

        // A service the owner was not given, and another owner's role, are both refused.
        $this->as($owner, 'POST', '/api/admin/users', $staff(['service_types' => ['inventory'], 'permissions' => []]))->assertForbidden();
        $this->as($owner, 'POST', '/api/admin/users', $staff(['role' => 'landlord']))->assertForbidden();
        $this->as($owner, 'POST', '/api/admin/users', $staff(['role' => 'admin']))->assertForbidden();
        $this->assertSame(0, User::where('email', 'mgr@example.test')->count());

        $this->as($owner, 'POST', '/api/admin/users', $staff())->assertCreated();
        $manager = User::where('email', 'mgr@example.test')->firstOrFail();
        $this->assertSame((string) $owner->id, (string) $manager->created_by, 'the staff belongs to the owner\'s business');
        $this->assertSame((string) $owner->id, $manager->accountHeadId());

        // The staff member works the owner's data, in the owner's services only.
        Property::create(['owner_id' => $owner->id, 'name' => 'Asha Plaza']);
        $names = collect($this->as($manager, 'GET', '/api/rental/properties')->assertOk()->json('data'))->pluck('name')->all();
        $this->assertSame(['Asha Plaza'], $names);
        $this->as($manager, 'GET', '/api/admin/vehicles')->assertForbidden();

        // The owner lists their own staff.
        $mine = collect($this->as($owner, 'GET', '/api/admin/users/mine')->assertOk()->json('data.users'))->pluck('email')->all();
        $this->assertContains('mgr@example.test', $mine);
    }

    public function test_staff_lose_a_service_when_their_business_loses_it(): void
    {
        $registration = $this->register();
        $this->approve($registration, ['rental', 'transport'])->assertOk();
        $owner = User::where('email', 'asha@example.test')->firstOrFail();

        $this->as($owner, 'POST', '/api/admin/users', [
            'name' => 'Both',
            'email' => 'both@example.test',
            'phone_number' => '0711999888',
            'password' => 'STAFFNEW1',
            'password_confirmation' => 'STAFFNEW1',
            'role' => 'manager',
            'service_types' => ['rental', 'transport'],
            'permissions' => ['manage_properties_rental'],
        ])->assertCreated();
        $staff = User::where('email', 'both@example.test')->firstOrFail();
        $this->assertNotSame(403, $this->as($staff, 'GET', '/api/rental/properties')->status());

        // The super admin takes rental away from the business.
        $this->as($this->superAdmin(), 'PUT', "/api/admin/users/{$owner->id}/services", ['service_types' => ['transport']])->assertOk();

        $this->as($staff->fresh(), 'GET', '/api/rental/properties')->assertForbidden()->assertJsonPath('code', 'service_not_assigned');
        $this->as($owner->fresh(), 'GET', '/api/rental/properties')->assertForbidden();

        $token = $staff->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $services = $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/auth/user/services')->json('services');
        $this->assertSame(['transport'], $services, 'the picker offers only what the API will still serve: what the staff were given AND the business still has');
    }

    public function test_two_registered_businesses_never_see_each_other(): void
    {
        $a = $this->register(['email' => 'a@example.test', 'phone_number' => '0711000001', 'business_name' => 'A Ltd']);
        $b = $this->register(['email' => 'b@example.test', 'phone_number' => '0711000002', 'business_name' => 'B Ltd']);
        $this->approve($a, ['rental'])->assertOk();
        $this->approve($b, ['rental'])->assertOk();
        $ownerA = User::where('email', 'a@example.test')->firstOrFail();
        $ownerB = User::where('email', 'b@example.test')->firstOrFail();

        Property::create(['owner_id' => $ownerA->id, 'name' => 'A Tower']);
        Property::create(['owner_id' => $ownerB->id, 'name' => 'B Court']);

        $this->assertSame(['A Tower'], collect($this->as($ownerA, 'GET', '/api/rental/properties')->json('data'))->pluck('name')->all());
        $this->assertSame(['B Court'], collect($this->as($ownerB, 'GET', '/api/rental/properties')->json('data'))->pluck('name')->all());
        $this->assertNotContains('b@example.test', collect($this->as($ownerA, 'GET', '/api/admin/users/mine')->json('data.users'))->pluck('email')->all());
    }

    // ------------------------------------------------ inventory per business

    public function test_a_second_business_can_be_given_inventory_and_starts_with_its_own_defaults(): void
    {
        $depot = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');
        TenantContext::runAs($depot, fn() => DB::table('inventory_settings')->where('key', 'depot_name')->update(['value' => 'Old Depot']));

        $registration = $this->register(['requested_services' => ['inventory', 'rental']]);
        $this->approve($registration, ['inventory'])->assertOk();
        $second = User::where('email', 'asha@example.test')->firstOrFail();

        // The new business was given its own settings and default crate types...
        $own = TenantContext::runAs($second, fn() => [
            'settings' => DB::table('inventory_settings')->count(),
            'crates' => DB::table('inventory_crate_types')->pluck('name')->sort()->values()->all(),
            'depot_name' => DB::table('inventory_settings')->where('key', 'depot_name')->value('value'),
        ]);
        $this->assertSame(count(\App\Support\InventoryDefaults::SETTINGS), $own['settings']);
        $this->assertSame(['Crate', 'Empty bottle'], $own['crates']);
        // ...carrying ITS OWN name (from the registration form), not the first depot's edited
        // settings and not the platform's "Beverage Depot" placeholder.
        $this->assertSame('Asha Rentals', $own['depot_name']);

        // ...and the first business's own rows are untouched and still its own.
        $this->assertSame('Old Depot', TenantContext::runAs($depot, fn() => DB::table('inventory_settings')->where('key', 'depot_name')->value('value')));
        $this->assertSame(2, TenantContext::runAs($depot, fn() => DB::table('inventory_crate_types')->count()));

        // Editing the services of an existing owner seeds them the same way.
        $third = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'rental');
        $this->as($this->superAdmin(), 'PUT', "/api/admin/users/{$third->id}/services", ['service_types' => ['inventory']])->assertOk();
        $this->assertSame(2, TenantContext::runAs($third, fn() => DB::table('inventory_crate_types')->count()));
    }

    // ------------------------------------------------- legacy accounts

    public function test_the_backfill_keeps_existing_admins_working_but_invents_nothing(): void
    {
        $uses = User::factory()->create(['role' => 'admin', 'is_active' => true]);
        $bound = User::factory()->create(['role' => 'admin', 'is_active' => true]);
        $this->givenServices($bound, 'rental');
        $empty = User::factory()->create(['role' => 'admin', 'is_active' => true]);

        // $uses runs transport (a driver), rental (a property) and inventory (a sales officer).
        User::factory()->create(['role' => 'driver', 'created_by' => $uses->id]);
        Property::create(['owner_id' => $uses->id, 'name' => 'Legacy plot']);
        User::factory()->create(['role' => 'sales_officer', 'created_by' => $uses->id]);
        // $bound already has a binding and also owns data for another service.
        DB::table('devices')->insert([
            'id' => (string) Str::uuid(),
            'created_by' => $bound->id,
            'name' => 'x',
            'type' => 'pikipiki',
            'plate_number' => 'LEG 1',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        (require database_path('migrations/2026_10_12_000300_backfill_services_for_unbound_admins.php'))->up();

        $services = fn(User $u) => $u->services()->pluck('service_type')->sort()->values()->all();
        $this->assertSame(['inventory', 'rental', 'transport'], $services($uses));
        $this->assertSame(['rental'], $services($bound), 'an admin who already has a binding is left alone');
        $this->assertSame([], $services($empty), 'no data, no invented access: a super admin assigns them');

        // Running it again changes nothing.
        (require database_path('migrations/2026_10_12_000300_backfill_services_for_unbound_admins.php'))->up();
        $this->assertSame(['inventory', 'rental', 'transport'], $services($uses));
    }
}
