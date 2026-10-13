<?php

namespace Tests\Feature;

use App\Models\BusinessRegistration;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The whole product flow, start to finish, through the real HTTP API only -- no model
 * shortcuts for the data -- for two businesses with DIFFERENT services:
 *
 *   1. an owner registers himself and cannot sign in yet;
 *   2. the super admin sees the registration details and assigns specific services;
 *   3. the owner signs in and is offered only those services (the server enforces it);
 *   4. the owner creates his own staff, only for those services;
 *   5. owner and staff create records; each business sees only its own;
 *   6. the super admin takes a service away and everything under that business loses it.
 */
class OnboardingFlowEndToEndTest extends TestCase
{
    use RefreshDatabase;

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

    private function register(string $name, string $email, string $phone, array $services): BusinessRegistration
    {
        $this->postJson('/api/auth/register', [
            'name' => "{$name} Owner", 'business_name' => "{$name} Ltd", 'email' => $email, 'phone_number' => $phone,
            'password' => 'owner-pass-1', 'password_confirmation' => 'owner-pass-1',
            'requested_services' => $services, 'region' => 'Dar es Salaam', 'district' => 'Ilala', 'address' => 'Kariakoo',
            // Whoever asks for inventory says what kind of stock business they run.
            'inventory_type' => in_array('inventory', $services, true) ? 'depot' : null,
        ])->assertCreated();

        // The applicant proves the phone is theirs with the code that was texted to it.
        $this->postJson('/api/auth/register/verify-phone', ['email' => $email, 'code' => $this->sms->lastCodeFor($phone)])->assertOk();

        return BusinessRegistration::whereHas('user', fn ($q) => $q->where('email', $email))->firstOrFail();
    }

    private function text($response): string
    {
        $json = $response->json() ?? [];
        $strings = [];
        array_walk_recursive($json, function ($value) use (&$strings) {
            if (is_scalar($value)) {
                $strings[] = (string) $value;
            }
        });

        return implode(' | ', $strings);
    }

    private function staffPayload(string $email, string $phone, string $role, array $services, array $permissions = []): array
    {
        return [
            'name' => ucfirst(strtok($email, '.')) . ' Staff', 'email' => $email, 'phone_number' => $phone,
            'password' => 'STAFFNEW1', 'password_confirmation' => 'STAFFNEW1',
            'role' => $role, 'service_types' => $services, 'permissions' => $permissions,
        ];
    }

    public function test_the_whole_flow_for_two_businesses_with_different_services(): void
    {
        $super = User::factory()->create(['role' => 'super_admin', 'is_active' => true, 'name' => 'Platform Admin']);

        // -------- 1. two owners register; neither can sign in yet
        $asha = $this->register('Asha', 'asha@example.test', '0743000001', ['inventory', 'rental', 'transport']);
        $juma = $this->register('Juma', 'juma@example.test', '0743000002', ['transport']);

        foreach ([['asha@example.test', '0743000001'], ['juma@example.test', '0743000002']] as [$email, $phone]) {
            $this->login($email, 'owner-pass-1', $phone)->assertForbidden()->assertJsonPath('errors.code', 'registration_pending');
        }

        // -------- 2. the super admin sees the details and decides the services
        $pending = $this->as($super, 'GET', '/api/admin/registrations')->assertOk();
        $this->assertSame(2, $pending->json('meta.counts.pending'));
        $ashaRow = collect($pending->json('data'))->firstWhere('business_name', 'Asha Ltd');
        $this->assertSame(['name' => 'Asha Owner', 'email' => 'asha@example.test', 'phone_number' => '0743000001'],
            collect($ashaRow['user'])->only(['name', 'email', 'phone_number'])->all());
        $this->assertSame('Kariakoo', $ashaRow['address']);

        // Asha asked for all three but is given two: the super admin decides.
        $this->as($super, 'POST', "/api/admin/registrations/{$asha->id}/approve", ['service_types' => ['inventory', 'rental']])->assertOk();
        $this->as($super, 'POST', "/api/admin/registrations/{$juma->id}/approve", ['service_types' => ['transport']])->assertOk();

        // -------- 3. each owner signs in and is offered only what they were given
        $this->login('asha@example.test', 'owner-pass-1', '0743000001')->assertOk();
        $this->login('juma@example.test', 'owner-pass-1', '0743000002')->assertOk();
        $ashaUser = User::where('email', 'asha@example.test')->firstOrFail();
        $jumaUser = User::where('email', 'juma@example.test')->firstOrFail();

        $this->assertEqualsCanonicalizing(['inventory', 'rental'], $this->as($ashaUser, 'GET', '/api/auth/user/services')->json('services'));
        $this->assertSame(['transport'], $this->as($jumaUser, 'GET', '/api/auth/user/services')->json('services'));

        $this->as($ashaUser, 'GET', '/api/admin/vehicles')->assertForbidden()->assertJsonPath('code', 'service_not_assigned'); // what she was NOT given
        $this->as($jumaUser, 'GET', '/api/inventory/customers')->assertForbidden()->assertJsonPath('code', 'service_not_assigned');
        $this->as($jumaUser, 'GET', '/api/rental/properties')->assertForbidden();

        // -------- 4. Asha creates her own staff, only for her services
        $this->as($ashaUser, 'POST', '/api/admin/users', $this->staffPayload('transport.staff@example.test', '0711000001', 'manager', ['transport']))
            ->assertForbidden(); // a service she does not hold
        $this->as($ashaUser, 'POST', '/api/admin/users', $this->staffPayload('boss.staff@example.test', '0711000002', 'admin', ['rental']))
            ->assertForbidden(); // owners are made by registration, not by staff creation

        $this->as($ashaUser, 'POST', '/api/admin/users', $this->staffPayload('officer.staff@example.test', '0711000003', 'sales_officer', ['inventory']))->assertCreated();
        $this->as($ashaUser, 'POST', '/api/admin/users', $this->staffPayload('manager.staff@example.test', '0711000004', 'manager', ['rental'], ['manage_properties_rental']))->assertCreated();

        $officer = User::where('email', 'officer.staff@example.test')->firstOrFail();
        $manager = User::where('email', 'manager.staff@example.test')->firstOrFail();
        $this->assertSame((string) $ashaUser->id, $officer->accountHeadId());
        $this->assertSame((string) $ashaUser->id, $manager->accountHeadId());

        // New staff sign in with the temporary password and are told to choose their own.
        $this->login('officer.staff@example.test', 'STAFFNEW1', '0711000003')->assertOk()->assertJsonPath('data.user.must_change_password', true);

        // -------- 5. records created through the API belong to the creating business
        $this->as($officer, 'POST', '/api/inventory/customers', ['name' => 'Asha Duka', 'phone' => '0799000001'])->assertCreated();
        $this->as($manager, 'POST', '/api/rental/properties', [
            'name' => 'Asha Plaza', 'property_type' => 'apartment', 'region' => 'Dar', 'district' => 'Ilala',
            'address' => 'Street 1', 'billing_cycle' => 'monthly',
        ])->assertCreated();
        $this->as($jumaUser, 'POST', '/api/admin/vehicles', ['name' => 'Juma Bajaji', 'type' => 'bajaji', 'plate_number' => 'JUM-001'])->assertCreated();

        $driverPayload = [
            'name' => 'Juma Driver', 'email' => 'driver@example.test', 'phone_number' => '0755000001',
            'license_number' => 'LIC-E2E-1', 'license_expiry' => now()->addYear()->toDateString(),
            'address' => 'Dar', 'emergency_contact' => '0755000002',
        ];
        $temporary = $this->as($jumaUser, 'POST', '/api/admin/drivers', $driverPayload)->assertCreated()->json('data.temporary_password');
        $driver = User::where('email', 'driver@example.test')->firstOrFail();
        $this->assertSame((string) $jumaUser->id, (string) $driver->created_by);
        $this->login('driver@example.test', $temporary, '0755000001')->assertOk()->assertJsonPath('data.user.must_change_password', true);

        // Each business sees its own, and nobody else's.
        $this->assertStringContainsString('Asha Duka', $this->text($this->as($ashaUser, 'GET', '/api/inventory/customers')->assertOk()));
        $this->assertStringContainsString('Asha Duka', $this->text($this->as($officer, 'GET', '/api/inventory/customers')->assertOk()), 'staff see the business\'s data');
        $this->assertStringContainsString('Asha Plaza', $this->text($this->as($ashaUser, 'GET', '/api/rental/properties')->assertOk()), 'the owner sees what staff created');
        $this->assertStringContainsString('Asha Plaza', $this->text($this->as($manager, 'GET', '/api/rental/properties')->assertOk()));

        $jumaVehicles = $this->text($this->as($jumaUser, 'GET', '/api/admin/vehicles')->assertOk());
        $this->assertStringContainsString('Juma Bajaji', $jumaVehicles);
        $this->assertStringNotContainsString('Asha', $jumaVehicles);
        $this->assertStringContainsString('Juma Driver', $this->text($this->as($jumaUser, 'GET', '/api/admin/drivers')->assertOk()));

        // Staff stay inside their own service, even within their own business.
        $this->as($officer, 'GET', '/api/rental/properties')->assertForbidden();
        $this->as($manager, 'GET', '/api/inventory/customers')->assertForbidden();
        $this->as($manager, 'GET', '/api/admin/vehicles')->assertForbidden();

        // The users list shows each owner only their own people.
        $ashaPeople = $this->text($this->as($ashaUser, 'GET', '/api/admin/users/mine')->assertOk());
        $this->assertStringContainsString('officer.staff@example.test', $ashaPeople);
        $this->assertStringNotContainsString('driver@example.test', $ashaPeople);
        $this->assertStringNotContainsString('juma@example.test', $ashaPeople);

        // -------- 6. the super admin takes rental from Asha: it goes for her whole business
        $this->as($super, 'PUT', "/api/admin/users/{$ashaUser->id}/services", ['service_types' => ['inventory']])->assertOk();

        $this->as($ashaUser->fresh(), 'GET', '/api/rental/properties')->assertForbidden();
        $this->as($manager->fresh(), 'GET', '/api/rental/properties')->assertForbidden()->assertJsonPath('code', 'service_not_assigned');
        $this->assertSame(['inventory'], $this->as($ashaUser->fresh(), 'GET', '/api/auth/user/services')->json('services'));
        $this->as($officer->fresh(), 'GET', '/api/inventory/customers')->assertOk(); // inventory is untouched

        // And the platform still sees everything.
        $this->assertStringContainsString('Asha Plaza', $this->text($this->as($super, 'GET', '/api/rental/properties')->assertOk()));
    }
}
