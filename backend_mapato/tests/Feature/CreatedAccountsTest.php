<?php

namespace Tests\Feature;

use App\Models\Rental\House;
use App\Models\Rental\Property;
use App\Models\Rental\RentalAgreement;
use App\Models\Rental\RentBill;
use App\Models\User;
use App\Support\SqlDate;
use App\Support\TemporaryPassword;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * Accounts that somebody else creates (tenant, driver, fundi, caretaker) no longer share a
 * fixed default password; and the other loose ends from the tenancy work: caretaker
 * assignment, the payment text sent once, and the dashboard SQL that only ran on MySQL.
 */
class CreatedAccountsTest extends TestCase
{
    use RefreshDatabase;

    private function user(string $role, string $service, array $extra = []): User
    {
        return $this->givenServices(User::factory()->create(array_merge([
            'role' => $role, 'is_active' => true,
        ], $extra)), $service);
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function unscoped(callable $fn)
    {
        return TenantContext::withoutScope($fn);
    }

    /** A landlord with one house, ready to onboard a tenant into. @return array{0: User, 1: Property, 2: House} */
    private function landlordWithHouse(): array
    {
        $landlord = $this->user('landlord', 'rental');
        $property = Property::create(['owner_id' => $landlord->id, 'name' => 'Plot A']);
        $house = House::create(['property_id' => $property->id, 'house_number' => 'A1', 'rent_amount' => 100000]);

        return [$landlord, $property, $house];
    }

    private function onboardPayload(House $house, array $overrides = []): array
    {
        return array_merge([
            'first_name' => 'Asha', 'last_name' => 'Juma', 'email' => 'asha.tenant@example.test',
            'phone' => '0712000111', 'rental_house_id' => $house->id, 'rent_amount' => 100000,
        ], $overrides);
    }

    // ------------------------------------------------------- the generator

    public function test_a_temporary_password_is_random_readable_and_never_a_known_default(): void
    {
        $seen = [];
        for ($i = 0; $i < 200; $i++) {
            $password = TemporaryPassword::generate();
            $seen[$password] = true;

            $this->assertSame(TemporaryPassword::LENGTH, strlen($password));
            $this->assertMatchesRegularExpression('/[A-Z]/', $password);
            $this->assertMatchesRegularExpression('/[a-z]/', $password);
            $this->assertMatchesRegularExpression('/[0-9]/', $password);
            $this->assertDoesNotMatchRegularExpression('/[01OIl]/', $password, 'no look-alike characters');
            $this->assertNotContains($password, TemporaryPassword::RETIRED_DEFAULTS);
        }

        $this->assertCount(200, $seen, 'every password is different');
    }

    // ------------------------------------------------- the four creation flows

    public function test_a_tenant_gets_a_one_time_password_not_tenant123(): void
    {
        [$landlord, , $house] = $this->landlordWithHouse();

        $response = $this->as($landlord, 'POST', '/api/rental/tenants/onboard', $this->onboardPayload($house))->assertCreated();
        $temporary = $response->json('data.temporary_password');

        $this->assertIsString($temporary);
        $tenant = $this->unscoped(fn () => User::where('email', 'asha.tenant@example.test')->firstOrFail());
        $this->assertTrue(Hash::check($temporary, $tenant->password), 'the password handed back is the one that works');
        $this->assertFalse(Hash::check('tenant123', $tenant->password), 'the old shared default does not');
        $this->assertTrue($tenant->must_change_password, 'and it must be replaced at first sign-in');

        // The tenant can sign in with it, and the app is told to ask for a new one.
        $this->postJson('/api/auth/login', ['email' => 'asha.tenant@example.test', 'password' => $temporary, 'phone_number' => '0712000111'])
            ->assertOk()
            ->assertJsonPath('data.user.must_change_password', true);
        $this->assertNotSame(200, $this->postJson('/api/auth/login', ['email' => 'asha.tenant@example.test', 'password' => 'tenant123', 'phone_number' => '0712000111'])->status());
    }

    public function test_a_landlord_can_choose_the_tenants_password_and_an_existing_tenant_is_left_alone(): void
    {
        [$landlord, $property, $house] = $this->landlordWithHouse();
        $second = House::create(['property_id' => $property->id, 'house_number' => 'A2', 'rent_amount' => 90000]);

        $first = $this->as($landlord, 'POST', '/api/rental/tenants/onboard', $this->onboardPayload($house, ['password' => 'ChosenByLandlord9']))->assertCreated();
        $this->assertNull($first->json('data.temporary_password'), 'nothing to hand over: the landlord chose it');
        $tenant = $this->unscoped(fn () => User::where('email', 'asha.tenant@example.test')->firstOrFail());
        $this->assertTrue(Hash::check('ChosenByLandlord9', $tenant->password));
        $this->assertTrue($tenant->must_change_password);

        // The same tenant takes a second house: their account, and the password they may have set since, stay.
        $tenant->forceFill(['password' => 'TheirOwnChoice7', 'must_change_password' => false])->save();
        $again = $this->as($landlord, 'POST', '/api/rental/tenants/onboard', $this->onboardPayload($second))->assertCreated();

        $this->assertNull($again->json('data.temporary_password'));
        $fresh = $this->unscoped(fn () => $tenant->fresh());
        $this->assertTrue(Hash::check('TheirOwnChoice7', $fresh->password), 'an existing account is never given a new password');
        $this->assertFalse($fresh->must_change_password);
    }

    public function test_a_driver_gets_a_one_time_password_not_password123(): void
    {
        $admin = $this->user('admin', 'transport');
        $payload = [
            'name' => 'Juma Driver', 'email' => 'juma.driver@example.test', 'phone_number' => '0755111222',
            'license_number' => 'LIC-1001', 'license_expiry' => now()->addYear()->toDateString(),
            'address' => 'Dar es Salaam', 'emergency_contact' => '0755999888',
        ];

        $response = $this->as($admin, 'POST', '/api/admin/drivers', $payload)->assertCreated();
        $temporary = $response->json('data.temporary_password');

        $driver = $this->unscoped(fn () => User::where('email', 'juma.driver@example.test')->firstOrFail());
        $this->assertIsString($temporary);
        $this->assertTrue(Hash::check($temporary, $driver->password));
        $this->assertFalse(Hash::check('password123', $driver->password));
        $this->assertTrue($driver->must_change_password);
        $this->assertSame((string) $admin->id, (string) $driver->created_by, 'and the driver belongs to the admin who added them');

        // A password the admin chose is honoured and nothing is handed back.
        $chosen = $this->as($admin, 'POST', '/api/admin/drivers', array_merge($payload, [
            'email' => 'second.driver@example.test', 'phone_number' => '0755333444', 'license_number' => 'LIC-1002', 'password' => 'AdminChose88',
        ]))->assertCreated();
        $this->assertNull($chosen->json('data.temporary_password'));
        $second = $this->unscoped(fn () => User::where('email', 'second.driver@example.test')->firstOrFail());
        $this->assertTrue(Hash::check('AdminChose88', $second->password));
        $this->assertTrue($second->must_change_password);
    }

    public function test_a_caretaker_gets_a_one_time_password_not_caretaker123(): void
    {
        $landlord = $this->user('landlord', 'rental');

        $response = $this->as($landlord, 'POST', '/api/rental/caretakers', [
            'name' => 'Musa Caretaker', 'phone_number' => '0766111222', 'email' => 'musa.caretaker@example.test',
        ])->assertCreated();
        $temporary = $response->json('data.temporary_password');

        $caretaker = $this->unscoped(fn () => User::where('email', 'musa.caretaker@example.test')->firstOrFail());
        $this->assertTrue(Hash::check($temporary, $caretaker->password));
        $this->assertFalse(Hash::check('caretaker123', $caretaker->password));
        $this->assertTrue($caretaker->must_change_password);
        $this->assertSame((string) $landlord->id, (string) $caretaker->created_by);
        $this->assertArrayNotHasKey('password', $response->json('data'), 'the hash is never returned');
    }

    public function test_a_caretaker_needs_an_email_because_that_is_how_they_sign_in(): void
    {
        $landlord = $this->user('landlord', 'rental');

        // This used to reach the database and fail with a 500.
        $this->as($landlord, 'POST', '/api/rental/caretakers', ['name' => 'Musa', 'phone_number' => '0766000333'])
            ->assertStatus(422)->assertJsonValidationErrors('email');
    }

    public function test_a_fundi_gets_a_one_time_password_not_12345678(): void
    {
        $landlord = $this->user('landlord', 'rental');

        $response = $this->as($landlord, 'POST', '/api/rental/maintenance/vendors', [
            'name' => 'Fundi Bomba', 'phone' => '0777111222', 'specialty' => 'plumbing',
        ])->assertCreated();
        $temporary = $response->json('data.temporary_password');

        $fundi = $this->unscoped(fn () => User::where('phone_number', '0777111222')->firstOrFail());
        $this->assertSame('vendor', $fundi->role);
        $this->assertTrue(Hash::check($temporary, $fundi->password));
        $this->assertFalse(Hash::check('12345678', $fundi->password));
        $this->assertTrue($fundi->must_change_password);

        // Adding the same fundi again reuses them and hands out nothing.
        $again = $this->as($landlord, 'POST', '/api/rental/maintenance/vendors', ['name' => 'Fundi Bomba', 'phone' => '0777111222'])->assertOk();
        $this->assertArrayNotHasKey('temporary_password', $again->json('data') ?? []);
    }

    // ------------------------------------------------- accounts that already exist

    public function test_accounts_still_on_a_retired_default_are_made_to_choose_their_own(): void
    {
        $stuck = [];
        foreach (TemporaryPassword::RETIRED_DEFAULTS as $i => $default) {
            $stuck[$default] = User::factory()->create(['email' => "stuck{$i}@example.test", 'password' => $default, 'must_change_password' => false]);
        }
        $fine = User::factory()->create(['email' => 'fine@example.test', 'password' => 'SomethingPersonal5', 'must_change_password' => false]);
        $before = $stuck['tenant123']->fresh()->password;

        // A preview names them and changes nothing.
        $this->artisan('users:flag-default-passwords', ['--dry-run' => true])->assertSuccessful();
        foreach ($stuck as $user) {
            $this->assertFalse($user->fresh()->must_change_password);
        }

        $this->artisan('users:flag-default-passwords')->assertSuccessful();

        foreach ($stuck as $default => $user) {
            $this->assertTrue($user->fresh()->must_change_password, "{$default} must be replaced");
            $this->assertTrue(Hash::check($default, $user->fresh()->password), 'nobody is locked out: the password itself is unchanged');
        }
        $this->assertFalse($fine->fresh()->must_change_password, 'a personal password is left alone');
        $this->assertSame($before, $stuck['tenant123']->fresh()->password);

        $this->artisan('users:flag-default-passwords')->assertSuccessful(); // safe to run again
    }

    // -------------------------------------------------------- caretaker assignment

    public function test_assigning_properties_to_a_caretaker_really_gives_them_access(): void
    {
        $landlord = $this->user('landlord', 'rental');
        $other = $this->user('landlord', 'rental');
        $p1 = Property::create(['owner_id' => $landlord->id, 'name' => 'P1']);
        $p2 = Property::create(['owner_id' => $landlord->id, 'name' => 'P2']);
        $foreign = Property::create(['owner_id' => $other->id, 'name' => 'Q1']);

        $caretakerId = $this->as($landlord, 'POST', '/api/rental/caretakers', [
            'name' => 'Musa', 'phone_number' => '0766000111', 'email' => 'musa.assign@example.test',
        ])->assertCreated()->json('data.id');
        $caretaker = $this->unscoped(fn () => User::findOrFail($caretakerId));

        $assign = fn (array $ids) => $this->as($landlord, 'POST', "/api/rental/caretakers/{$caretakerId}/assign", ['property_ids' => $ids]);
        $sees = fn () => TenantContext::runAs($caretaker, fn () => Property::orderBy('name')->pluck('name')->all());

        $this->assertSame([], $sees(), 'a new caretaker looks after nothing');

        $assign([$p1->id])->assertOk()->assertJsonPath('data.property_ids', [$p1->id]);
        $this->assertSame(['P1'], $sees());

        $assign([$p1->id, $p2->id])->assertOk();
        $this->assertSame(['P1', 'P2'], $sees());

        $assign([$p2->id])->assertOk();
        $this->assertSame(['P2'], $sees(), 'the list replaces the old one: P1 is released');
        $this->assertNull($this->unscoped(fn () => Property::find($p1->id)->caretaker_id));

        // Another business's property cannot be given to this caretaker, and nothing changes.
        $assign([$p2->id, $foreign->id])->assertStatus(422)->assertJsonValidationErrors('property_ids.1');
        $this->assertSame(['P2'], $sees());
        $this->assertNull($this->unscoped(fn () => Property::find($foreign->id)->caretaker_id));

        $assign([])->assertOk();
        $this->assertSame([], $sees(), 'an empty list takes every property away');
    }

    public function test_a_caretaker_cannot_be_assigned_by_or_into_another_business(): void
    {
        $landlord = $this->user('landlord', 'rental');
        $other = $this->user('landlord', 'rental');
        $mine = Property::create(['owner_id' => $landlord->id, 'name' => 'Mine']);
        $theirs = Property::create(['owner_id' => $other->id, 'name' => 'Theirs']);

        $caretakerId = $this->as($landlord, 'POST', '/api/rental/caretakers', [
            'name' => 'Musa', 'phone_number' => '0766000222', 'email' => 'musa.other@example.test',
        ])->assertCreated()->json('data.id');

        // Another landlord cannot even find the caretaker.
        $this->as($other, 'POST', "/api/rental/caretakers/{$caretakerId}/assign", ['property_ids' => [$theirs->id]])->assertNotFound();

        // A super admin sees every business, but still cannot mix two of them.
        $super = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
        $this->as($super, 'POST', "/api/rental/caretakers/{$caretakerId}/assign", ['property_ids' => [$theirs->id]])
            ->assertStatus(422)->assertJsonValidationErrors('property_ids');
        $this->assertNull($this->unscoped(fn () => Property::find($theirs->id)->caretaker_id));

        $this->as($super, 'POST', "/api/rental/caretakers/{$caretakerId}/assign", ['property_ids' => [$mine->id]])->assertOk();
        $this->assertSame($caretakerId, (string) $this->unscoped(fn () => Property::find($mine->id)->caretaker_id));
    }

    // ------------------------------------------------------ the payment text

    /** A bill with 100,000 owing, on a landlord's house, for a tenant they onboarded. @return array{0: User, 1: RentBill} */
    private function unpaidBill(): array
    {
        [$landlord, $property, $house] = $this->landlordWithHouse();
        $tenant = $this->user('tenant', 'rental', ['created_by' => $landlord->id, 'phone_number' => '0712555666']);
        $lease = RentalAgreement::create([
            'tenant_id' => $tenant->id, 'house_id' => $house->id, 'property_id' => $property->id,
            'start_date' => now()->toDateString(), 'rent_cycle' => 'monthly', 'rent_amount' => 100000, 'status' => 'active',
        ]);
        $bill = RentBill::create([
            'agreement_id' => $lease->id, 'month_year' => now()->format('m-Y'), 'amount_due' => 100000,
            'balance' => 100000, 'due_date' => now()->addDays(5)->toDateString(), 'status' => 'unpaid',
        ]);

        return [$landlord, $bill];
    }

    public function test_the_tenant_is_texted_once_when_a_payment_is_recorded(): void
    {
        [$landlord, $bill] = $this->unpaidBill();

        $this->as($landlord, 'POST', '/api/rental/payments/record', [
            'bill_id' => $bill->id, 'amount_paid' => 40000, 'payment_method' => 'cash',
        ])->assertOk();

        $received = $this->sms->to('0712555666');
        $this->assertCount(1, $received, 'one text, not two');
        $this->assertStringContainsString('payment of TZS 40,000', $received[0]['message']);
        $this->assertSame(60000.0, (float) $this->unscoped(fn () => $bill->fresh()->balance));
    }

    public function test_a_failing_text_message_never_undoes_a_recorded_payment(): void
    {
        [$landlord, $bill] = $this->unpaidBill();
        $this->sms->failWith(new \RuntimeException('SMS provider is down'));

        $response = $this->as($landlord, 'POST', '/api/rental/payments/record', [
            'bill_id' => $bill->id, 'amount_paid' => 25000, 'payment_method' => 'cash',
        ]);
        $this->assertSame(200, $response->status(), $response->getContent());

        $this->assertSame(75000.0, (float) $this->unscoped(fn () => $bill->fresh()->balance), 'the money was taken');
        $this->assertSame(1, $this->unscoped(fn () => DB::table('rental_payments')->count()));
    }

    // ------------------------------------------------------ dates in raw SQL

    public function test_date_parts_in_raw_sql_work_on_the_database_the_tests_use(): void
    {
        $row = DB::selectOne(
            'select ' . SqlDate::year('d') . ' as y, ' . SqlDate::month('d') . ' as m, ' . SqlDate::day('d') . ' as day, '
            . SqlDate::yearWeek('d') . " as yw from (select '2026-10-05 13:45:00' as d) t"
        );

        $this->assertSame(2026, (int) $row->y);
        $this->assertSame(10, (int) $row->m);
        $this->assertSame(5, (int) $row->day);
        $this->assertSame('2026', substr((string) $row->yw, 0, 4));
    }

    public function test_the_transport_dashboard_loads(): void
    {
        $admin = $this->user('admin', 'transport');

        $this->as($admin, 'GET', '/api/admin/dashboard-data')->assertOk()->assertJsonPath('status', 'success');
    }
}
