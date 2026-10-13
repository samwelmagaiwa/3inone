<?php

namespace Tests\Feature;

use App\Models\Device;
use App\Models\Driver;
use App\Models\Rental\House;
use App\Models\Rental\Property;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * A plate number, a licence number and a phone number are unique inside ONE business, not across
 * every business on the platform: two businesses each have their own "T123ABC", a driver who changed
 * employer keeps their number, and one business can neither be blocked by -- nor learn about --
 * another's records. The email is the sign-in name and stays unique across the platform.
 */
class PerBusinessUniquenessTest extends TestCase
{
    use RefreshDatabase;

    private User $alpha;
    private User $bravo;

    protected function setUp(): void
    {
        parent::setUp();
        $this->alpha = $this->owner('Alpha', '0722000001');
        $this->bravo = $this->owner('Bravo', '0722000002');
    }

    private function owner(string $label, string $phone): User
    {
        return $this->givenServices(User::factory()->create([
            'name' => "{$label} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => $phone,
        ]), 'transport', 'rental', 'inventory');
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function vehicle(User $by, string $plate, string $name = 'Boda')
    {
        return $this->as($by, 'POST', '/api/admin/vehicles', ['name' => $name, 'type' => 'pikipiki', 'plate_number' => $plate]);
    }

    private function driverPayload(string $email, string $phone, string $licence): array
    {
        return [
            'name' => 'Juma Driver', 'email' => $email, 'phone_number' => $phone,
            'license_number' => $licence, 'license_expiry' => now()->addYear()->toDateString(),
            'address' => 'Dar es Salaam', 'emergency_contact' => '0755999888',
        ];
    }

    private function staffPayload(string $email, string $phone, array $extra = []): array
    {
        return array_merge([
            'name' => 'Staff Member', 'email' => $email, 'phone_number' => $phone,
            'password' => 'Staff-pass-1', 'password_confirmation' => 'Staff-pass-1',
            'role' => 'sales_officer', 'service_types' => ['inventory'],
        ], $extra);
    }

    private function unscoped(callable $fn)
    {
        return TenantContext::withoutScope($fn);
    }

    /** Every `plate_number` anywhere in a response. */
    private function plates(array $json): array
    {
        $found = [];
        array_walk_recursive($json, function ($value, $key) use (&$found) {
            if ($key === 'plate_number') {
                $found[] = $value;
            }
        });

        return $found;
    }

    // ------------------------------------------------------------- vehicles

    public function test_two_businesses_can_each_register_a_vehicle_with_the_same_plate(): void
    {
        $a = $this->vehicle($this->alpha, 'T123ABC')->assertCreated();
        $b = $this->vehicle($this->bravo, 'T123ABC')->assertCreated();

        $this->assertNotSame($a->json('data.id'), $b->json('data.id'));

        // Each sees only its own, and the row says which business it is.
        $this->assertSame(['T123ABC'], $this->plates($this->as($this->alpha, 'GET', '/api/admin/vehicles')->assertOk()->json()));
        $this->assertSame(['T123ABC'], $this->plates($this->as($this->bravo, 'GET', '/api/admin/vehicles')->assertOk()->json()));
        $owners = $this->unscoped(fn () => Device::query()->orderBy('created_at')->pluck('owner_id')->sort()->values()->all());
        $this->assertEqualsCanonicalizing([(string) $this->alpha->id, (string) $this->bravo->id], $owners);
    }

    public function test_a_business_cannot_repeat_its_own_plate_in_any_case(): void
    {
        $this->vehicle($this->alpha, 'T123ABC')->assertCreated();

        $this->vehicle($this->alpha, 'T123ABC')->assertStatus(422)->assertJsonValidationErrors('plate_number');
        $this->vehicle($this->alpha, ' t123abc ')->assertStatus(422)->assertJsonValidationErrors('plate_number');

        // Another business is still free to have it, and is not told that anyone else does.
        $this->vehicle($this->bravo, 't123abc')->assertCreated()->assertJsonPath('data.plate_number', 'T123ABC');
    }

    public function test_staff_create_vehicles_for_their_business_and_its_plates_are_checked_together(): void
    {
        $staff = $this->givenServices(User::factory()->create([
            'role' => 'manager', 'is_active' => true, 'created_by' => $this->alpha->id, 'permissions' => ['manage_vehicles_transport'],
        ]), 'transport');

        $this->vehicle($this->alpha, 'T777AAA')->assertCreated();

        // The staff member's vehicle belongs to the BUSINESS, so the owner's plate clashes with it.
        $this->vehicle($staff, 'T777AAA')->assertStatus(422)->assertJsonValidationErrors('plate_number');
        $created = $this->vehicle($staff, 'T888BBB')->assertCreated()->json('data.id');
        $this->assertSame((string) $this->alpha->id, (string) $this->unscoped(fn () => Device::find($created)->owner_id));
    }

    public function test_editing_a_plate_is_checked_inside_the_vehicles_own_business(): void
    {
        $mine = $this->vehicle($this->alpha, 'T111AAA')->assertCreated()->json('data.id');
        $this->vehicle($this->alpha, 'T222BBB')->assertCreated();
        $this->vehicle($this->bravo, 'T333CCC')->assertCreated();

        // To another business's plate: fine. To one of its own other vehicles: refused.
        $this->as($this->alpha, 'PUT', "/api/admin/vehicles/{$mine}", ['plate_number' => 'T333CCC'])->assertOk();
        $this->as($this->alpha, 'PUT', "/api/admin/vehicles/{$mine}", ['plate_number' => 'T222BBB'])->assertStatus(422);
        // Saving the vehicle with its own plate is not a clash with itself.
        $this->as($this->alpha, 'PUT', "/api/admin/vehicles/{$mine}", ['plate_number' => 'T333CCC', 'name' => 'Renamed'])->assertOk();
    }

    public function test_the_database_enforces_it_per_business_and_lets_unowned_legacy_rows_alone(): void
    {
        $row = fn (?string $owner, string $plate) => [
            'id' => (string) Str::uuid(), 'owner_id' => $owner, 'name' => 'x', 'type' => 'pikipiki',
            'plate_number' => $plate, 'is_active' => true, 'created_at' => now(), 'updated_at' => now(),
        ];

        DB::table('devices')->insert($row((string) $this->alpha->id, 'DB 1'));
        DB::table('devices')->insert($row((string) $this->bravo->id, 'DB 1')); // another business: allowed

        // The same business repeating it is refused by the database itself, not just by validation.
        $this->expectException(QueryException::class);
        DB::table('devices')->insert($row((string) $this->alpha->id, 'DB 1'));
    }

    public function test_rows_with_no_known_business_are_not_deduplicated_against_each_other(): void
    {
        $row = fn (string $plate) => [
            'id' => (string) Str::uuid(), 'owner_id' => null, 'name' => 'x', 'type' => 'pikipiki',
            'plate_number' => $plate, 'is_active' => true, 'created_at' => now(), 'updated_at' => now(),
        ];

        DB::table('devices')->insert($row('OLD 1'));
        DB::table('devices')->insert($row('OLD 1'));

        $this->assertSame(2, DB::table('devices')->where('plate_number', 'OLD 1')->count());
    }

    // -------------------------------------------------------------- drivers

    public function test_two_businesses_can_each_have_a_driver_with_the_same_licence_and_phone(): void
    {
        $this->as($this->alpha, 'POST', '/api/admin/drivers', $this->driverPayload('d1@example.test', '0755111222', 'LIC-1'))->assertCreated();
        $this->as($this->bravo, 'POST', '/api/admin/drivers', $this->driverPayload('d2@example.test', '0755111222', 'LIC-1'))->assertCreated();

        $owners = $this->unscoped(fn () => Driver::query()->where('license_number', 'LIC-1')->pluck('owner_id')->all());
        $this->assertEqualsCanonicalizing([(string) $this->alpha->id, (string) $this->bravo->id], $owners);
    }

    public function test_a_business_cannot_repeat_a_licence_or_a_phone_of_its_own(): void
    {
        $this->as($this->alpha, 'POST', '/api/admin/drivers', $this->driverPayload('d1@example.test', '0755111222', 'LIC-1'))->assertCreated();

        $this->as($this->alpha, 'POST', '/api/admin/drivers', $this->driverPayload('d2@example.test', '0755333444', 'LIC-1'))
            ->assertStatus(422)->assertJsonValidationErrors('license_number');
        // The same phone written the other way is the same phone.
        $this->as($this->alpha, 'POST', '/api/admin/drivers', $this->driverPayload('d3@example.test', '+255755111222', 'LIC-3'))
            ->assertStatus(422)->assertJsonValidationErrors('phone_number');
    }

    public function test_the_email_stays_unique_across_the_platform_because_it_is_the_sign_in_name(): void
    {
        $this->as($this->alpha, 'POST', '/api/admin/drivers', $this->driverPayload('same@example.test', '0755111222', 'LIC-1'))->assertCreated();

        $this->as($this->bravo, 'POST', '/api/admin/drivers', $this->driverPayload('same@example.test', '0755333444', 'LIC-9'))
            ->assertStatus(422)->assertJsonValidationErrors('email');
    }

    public function test_a_drivers_new_licence_and_phone_are_checked_inside_their_business(): void
    {
        $this->as($this->alpha, 'POST', '/api/admin/drivers', $this->driverPayload('d1@example.test', '0755111222', 'LIC-1'))->assertCreated();
        $this->as($this->alpha, 'POST', '/api/admin/drivers', $this->driverPayload('d2@example.test', '0755333444', 'LIC-2'))->assertCreated();
        $this->as($this->bravo, 'POST', '/api/admin/drivers', $this->driverPayload('d3@example.test', '0755555666', 'LIC-3'))->assertCreated();

        $d1 = $this->unscoped(fn () => User::where('email', 'd1@example.test')->firstOrFail());

        $this->as($this->alpha, 'PUT', "/api/admin/drivers/{$d1->id}", ['license_number' => 'LIC-3', 'phone' => '0755555666'])->assertOk();
        $this->as($this->alpha, 'PUT', "/api/admin/drivers/{$d1->id}", ['license_number' => 'LIC-2'])->assertStatus(422)->assertJsonValidationErrors('license_number');
        $this->as($this->alpha, 'PUT', "/api/admin/drivers/{$d1->id}", ['phone' => '0755333444'])->assertStatus(422)->assertJsonValidationErrors('phone');
    }

    // ---------------------------------------------------------- staff phones

    public function test_staff_in_two_businesses_may_share_a_phone_but_not_inside_one(): void
    {
        $this->as($this->alpha, 'POST', '/api/admin/users', $this->staffPayload('a1@example.test', '0711000001'))->assertCreated();
        $this->as($this->bravo, 'POST', '/api/admin/users', $this->staffPayload('b1@example.test', '0711000001'))->assertCreated();

        $this->as($this->alpha, 'POST', '/api/admin/users', $this->staffPayload('a2@example.test', '+255711000001'))
            ->assertStatus(422)->assertJsonValidationErrors('phone_number');
        // The owner's own number counts too: it is a person of the business.
        $this->as($this->alpha, 'POST', '/api/admin/users', $this->staffPayload('a3@example.test', '0722000001'))
            ->assertStatus(422)->assertJsonValidationErrors('phone_number');
        // The email is still platform-wide.
        $this->as($this->bravo, 'POST', '/api/admin/users', $this->staffPayload('a1@example.test', '0711000009'))
            ->assertStatus(422)->assertJsonValidationErrors('email');
    }

    public function test_editing_a_staff_phone_is_checked_inside_their_business(): void
    {
        $a1 = $this->as($this->alpha, 'POST', '/api/admin/users', $this->staffPayload('a1@example.test', '0711000001'))->assertCreated()->json('data.user.id');
        $this->as($this->alpha, 'POST', '/api/admin/users', $this->staffPayload('a2@example.test', '0711000002'))->assertCreated();
        $this->as($this->bravo, 'POST', '/api/admin/users', $this->staffPayload('b1@example.test', '0711000003'))->assertCreated();

        $this->as($this->alpha, 'PUT', "/api/admin/users/{$a1}", ['phone_number' => '0711000003'])->assertOk();   // another business's number
        $this->as($this->alpha, 'PUT', "/api/admin/users/{$a1}", ['phone_number' => '0711000002'])->assertStatus(422); // a colleague's
        $this->as($this->alpha, 'PUT', "/api/admin/users/{$a1}", ['phone_number' => '0711000003', 'name' => 'Same phone, new name'])->assertOk(); // its own
    }

    public function test_a_super_admin_placing_staff_in_a_business_is_checked_against_that_business(): void
    {
        $super = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
        $this->as($this->alpha, 'POST', '/api/admin/users', $this->staffPayload('a1@example.test', '0711000001'))->assertCreated();
        $this->as($this->bravo, 'POST', '/api/admin/users', $this->staffPayload('b1@example.test', '0711000002'))->assertCreated();

        $into = fn (User $business, string $email, string $phone) => $this->as($super, 'POST', '/api/admin/users',
            $this->staffPayload($email, $phone, ['business_owner_id' => $business->id]));

        $into($this->alpha, 'x1@example.test', '0711000001')->assertStatus(422)->assertJsonValidationErrors('phone_number'); // alpha already has it
        $into($this->alpha, 'x2@example.test', '0711000002')->assertCreated();                                                 // only bravo has it
    }

    public function test_a_caretaker_phone_is_unique_inside_the_landlords_business(): void
    {
        $l1 = $this->givenServices(User::factory()->create(['role' => 'landlord', 'is_active' => true]), 'rental');
        $l2 = $this->givenServices(User::factory()->create(['role' => 'landlord', 'is_active' => true]), 'rental');
        $body = fn (string $email) => ['name' => 'Musa', 'phone_number' => '0766111222', 'email' => $email];

        $this->as($l1, 'POST', '/api/rental/caretakers', $body('c1@example.test'))->assertCreated();
        $this->as($l2, 'POST', '/api/rental/caretakers', $body('c2@example.test'))->assertCreated();
        $this->as($l1, 'POST', '/api/rental/caretakers', $body('c3@example.test'))->assertStatus(422)->assertJsonValidationErrors('phone_number');
    }

    // ------------------------------------------------- people found by phone

    private function landlordWithHouse(string $label): array
    {
        $landlord = $this->givenServices(User::factory()->create([
            'name' => "{$label} Landlord", 'role' => 'landlord', 'is_active' => true,
        ]), 'rental');
        $property = Property::create(['owner_id' => $landlord->id, 'name' => "{$label} Plot"]);
        $house = House::create(['property_id' => $property->id, 'house_number' => "{$label}1", 'rent_amount' => 100000]);

        return [$landlord, $house];
    }

    private function onboard(User $landlord, House $house, string $email, string $phone, string $first = 'Tenant')
    {
        return $this->as($landlord, 'POST', '/api/rental/tenants/onboard', [
            'first_name' => $first, 'last_name' => 'One', 'email' => $email, 'phone' => $phone,
            'rental_house_id' => $house->id, 'rent_amount' => 100000,
        ]);
    }

    public function test_a_tenant_is_not_confused_with_someone_in_another_business_who_has_the_same_phone(): void
    {
        [$l1, $h1] = $this->landlordWithHouse('One');
        [$l2, $h2] = $this->landlordWithHouse('Two');

        $this->onboard($l1, $h1, 'asha@example.test', '0712000111', 'Asha')->assertCreated();
        // A different person, in another business, on the same number: a NEW tenant, not Asha.
        $this->onboard($l2, $h2, 'bob@example.test', '0712000111', 'Bob')->assertCreated();

        $asha = $this->unscoped(fn () => User::where('email', 'asha@example.test')->firstOrFail());
        $bob = $this->unscoped(fn () => User::where('email', 'bob@example.test')->firstOrFail());
        $this->assertNotSame($asha->id, $bob->id);
        $this->assertSame((string) $l1->id, (string) $asha->created_by);
        $this->assertSame((string) $l2->id, (string) $bob->created_by);
    }

    public function test_the_same_email_is_still_the_same_tenant_across_landlords(): void
    {
        [$l1, $h1] = $this->landlordWithHouse('One');
        [$l2, $h2] = $this->landlordWithHouse('Two');

        $this->onboard($l1, $h1, 'asha@example.test', '0712000111', 'Asha')->assertCreated();
        $this->onboard($l2, $h2, 'asha@example.test', '0712000999', 'Asha')->assertCreated();

        $this->assertSame(1, $this->unscoped(fn () => User::where('email', 'asha@example.test')->count()), 'one person, one login');
    }

    public function test_a_phone_that_belongs_to_a_colleague_in_the_same_business_is_still_refused(): void
    {
        [$landlord, $house] = $this->landlordWithHouse('One');
        $this->as($landlord, 'POST', '/api/rental/caretakers', ['name' => 'Musa', 'phone_number' => '0766111222', 'email' => 'musa@example.test'])->assertCreated();

        // The caretaker is not a tenant: the number is theirs, inside this business.
        $this->onboard($landlord, $house, 'new@example.test', '0766111222')->assertStatus(422);
    }

    public function test_a_fundi_is_never_matched_to_a_driver_who_shares_the_number(): void
    {
        $this->as($this->alpha, 'POST', '/api/admin/drivers', $this->driverPayload('d1@example.test', '0777111222', 'LIC-1'))->assertCreated();
        $driver = $this->unscoped(fn () => User::where('email', 'd1@example.test')->firstOrFail());
        [$landlord] = $this->landlordWithHouse('One');

        $this->as($landlord, 'POST', '/api/rental/maintenance/vendors', ['name' => 'Fundi Bomba', 'phone' => '0777111222', 'specialty' => 'plumbing'])->assertCreated();

        $fundi = $this->unscoped(fn () => User::where('role', 'vendor')->where('phone_number', '0777111222')->first());
        $this->assertNotNull($fundi, 'the fundi got a login of their own');
        $this->assertNotSame($driver->id, $fundi->id);
        $this->assertSame('driver', $this->unscoped(fn () => $driver->fresh()->role), 'the driver was not turned into a fundi');
    }

    // ------------------------------------------------------------- receipts

    /** A driver created through the API (so it carries its business) with one completed payment. */
    private function paymentFor(User $owner, string $email): int
    {
        $this->as($owner, 'POST', '/api/admin/drivers', $this->driverPayload($email, '07' . random_int(10000000, 99999999), 'LIC-' . Str::random(6)))->assertCreated();
        $driverId = $this->unscoped(fn () => Driver::query()->whereHas('user', fn ($u) => $u->where('email', $email))->value('id'));

        return DB::table('payments')->insertGetId([
            'reference_number' => 'PAY-' . Str::random(10), 'driver_id' => $driverId, 'amount' => 5000,
            'covers_days' => json_encode(['2026-03-01']), 'status' => 'completed', 'receipt_status' => 'pending',
            'payment_date' => now(), 'recorded_by' => $owner->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    public function test_two_businesses_can_each_issue_receipt_number_one_on_the_same_day(): void
    {
        // Each business numbers its own receipts from 0001. With one global index the second business's
        // first receipt of the day collided with the first business's and failed with a 500.
        $a = $this->as($this->alpha, 'POST', '/api/payment-receipts/generate', ['payment_id' => $this->paymentFor($this->alpha, 'a.d@example.test')])->assertCreated();
        $b = $this->as($this->bravo, 'POST', '/api/payment-receipts/generate', ['payment_id' => $this->paymentFor($this->bravo, 'b.d@example.test')])->assertCreated();

        $this->assertSame($a->json('data.receipt_number'), $b->json('data.receipt_number'), 'both are number 0001 of their own business');
        $this->assertStringEndsWith('0001', $a->json('data.receipt_number'));

        // The business's own next receipt carries on from its own count, and each row says whose it is.
        $second = $this->as($this->alpha, 'POST', '/api/payment-receipts/generate', ['payment_id' => $this->paymentFor($this->alpha, 'a.d2@example.test')])->assertCreated();
        $this->assertStringEndsWith('0002', $second->json('data.receipt_number'));

        $owners = $this->unscoped(fn () => DB::table('payment_receipts')->orderBy('id')->pluck('owner_id')->all());
        $this->assertSame([(string) $this->alpha->id, (string) $this->bravo->id, (string) $this->alpha->id], array_map('strval', $owners));
    }

    public function test_the_database_refuses_a_business_repeating_its_own_receipt_number(): void
    {
        $paymentId = $this->paymentFor($this->alpha, 'a.d@example.test');
        $this->as($this->alpha, 'POST', '/api/payment-receipts/generate', ['payment_id' => $paymentId])->assertCreated();

        $row = $this->unscoped(fn () => (array) DB::table('payment_receipts')->first());
        unset($row['id']);

        // Another business may use the number; the same business may not.
        DB::table('payment_receipts')->insert(array_merge($row, ['owner_id' => (string) $this->bravo->id]));
        $this->expectException(QueryException::class);
        DB::table('payment_receipts')->insert($row);
    }
}
