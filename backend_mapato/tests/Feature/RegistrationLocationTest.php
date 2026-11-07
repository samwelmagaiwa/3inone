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

    public function test_the_point_captured_at_the_business_is_kept_and_the_super_admin_gets_it_with_a_map_link(): void
    {
        $this->postJson('/api/auth/register', $this->payload(['latitude' => -6.7923, 'longitude' => 39.2083, 'location_accuracy' => 9.5]))->assertCreated();

        $registration = BusinessRegistration::firstOrFail();
        $this->assertEqualsWithDelta(-6.7923, (float) $registration->latitude, 0.00001);
        $this->assertNotNull($registration->location_captured_at);

        $admin = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
        $token = $admin->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $res = $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/admin/registrations')->assertOk();
        $row = $res->json('data.0') ?? $res->json('data.data.0');

        $this->assertEqualsWithDelta(-6.7923, $row['latitude'], 0.00001);
        $this->assertEqualsWithDelta(9.5, $row['location_accuracy_m'], 0.01);
        $this->assertSame('https://www.google.com/maps?q=-6.7923,39.2083', $row['map_url']);
    }

    public function test_where_the_requirement_is_off_a_point_is_optional_but_never_half_of_one_or_out_of_the_world(): void
    {
        $this->postJson('/api/auth/register', $this->payload())->assertCreated();
        $this->assertNull(BusinessRegistration::firstOrFail()->latitude);

        $this->postJson('/api/auth/register', $this->payload(['email' => 'b@example.test', 'phone_number' => '0743519101', 'latitude' => -6.8]))->assertStatus(422);
        $this->postJson('/api/auth/register', $this->payload(['email' => 'c@example.test', 'phone_number' => '0743519102', 'latitude' => 123, 'longitude' => 39]))->assertStatus(422);
    }

    public function test_the_business_location_is_required_to_ask_for_the_system(): void
    {
        config(['registration.require_location' => true]);

        // without it: refused, in words that say what to do
        $res = $this->postJson('/api/auth/register', $this->payload())->assertStatus(422);
        $this->assertStringContainsString('Capture my current location', json_encode($res->json()));
        $this->assertSame(0, BusinessRegistration::count());

        // half of it, or a reading too weak to pin the business down: refused
        $this->postJson('/api/auth/register', $this->payload(['latitude' => -6.8]))->assertStatus(422);
        $this->postJson('/api/auth/register', $this->payload(['latitude' => -6.8, 'longitude' => 39.2, 'location_accuracy' => 250]))->assertStatus(422);
        $this->assertSame(0, BusinessRegistration::count());

        // with a good reading: accepted
        $this->postJson('/api/auth/register', $this->payload(['latitude' => -6.8, 'longitude' => 39.2, 'location_accuracy' => 12]))->assertCreated();
        $this->assertSame(1, BusinessRegistration::count());
    }
}
