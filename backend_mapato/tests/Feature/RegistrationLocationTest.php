<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\BusinessRegistration;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** Where a business is, to the ward and the street or village: kept on the registration, shown to the super admin, and on the business record. */
class RegistrationLocationTest extends TestCase
{
    use RefreshDatabase;

    private function payload(array $over = []): array
    {
        return $over + [
            'name' => 'Asha Owner', 'business_name' => 'Asha Shop', 'email' => 'asha@example.test', 'phone_number' => '0743519100',
            'password' => 'secret-pass-1', 'password_confirmation' => 'secret-pass-1', 'requested_services' => ['rental'],
        ];
    }

    public function test_the_ward_and_street_are_kept_and_the_business_address_names_the_whole_place(): void
    {
        $this->postJson('/api/auth/register', $this->payload([
            'region' => 'Dar es Salaam', 'district' => 'Kinondoni', 'ward' => 'Mikocheni', 'street' => 'Mikocheni B', 'address' => 'Plot 12',
        ]))->assertCreated();

        $registration = BusinessRegistration::firstOrFail();
        $this->assertSame(['Dar es Salaam', 'Kinondoni', 'Mikocheni', 'Mikocheni B'], [$registration->region, $registration->district, $registration->ward, $registration->street]);

        $owner = User::where('email', 'asha@example.test')->firstOrFail();
        $this->assertSame('Plot 12, Mikocheni B, Mikocheni, Kinondoni, Dar es Salaam', Business::forOwnerId($owner->id)->address);
    }

    public function test_the_super_admin_sees_the_ward_and_street(): void
    {
        $this->postJson('/api/auth/register', $this->payload(['region' => 'Arusha', 'district' => 'Arusha CBD', 'ward' => 'Kati', 'street' => 'Mrombo']))->assertCreated();
        $admin = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
        $token = $admin->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();

        $row = $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/admin/registrations')->assertOk()->json('data.0')
            ?? $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/admin/registrations')->json('data.data.0');

        $this->assertSame(['Kati', 'Mrombo'], [$row['ward'], $row['street']]);
    }

    public function test_a_place_typed_by_hand_is_accepted_like_a_chosen_one_and_every_part_is_optional(): void
    {
        $this->postJson('/api/auth/register', $this->payload(['region' => 'Dodoma', 'street' => 'Kijiji cha Mfano']))->assertCreated();

        $registration = BusinessRegistration::firstOrFail();
        $this->assertSame('Kijiji cha Mfano', $registration->street);
        $this->assertNull($registration->ward);
    }

    public function test_a_part_that_is_too_long_is_refused(): void
    {
        $this->postJson('/api/auth/register', $this->payload(['ward' => str_repeat('a', 101)]))->assertStatus(422);
    }
}
