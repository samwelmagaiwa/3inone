<?php

namespace Tests\Feature;

use App\Models\Rental\Block;
use App\Models\Rental\House;
use App\Models\Rental\MaintenanceRequest;
use App\Models\Rental\Property;
use App\Models\Rental\RentalAgreement;
use App\Models\Rental\RentalPayment;
use App\Models\Rental\RentalReceipt;
use App\Models\Rental\RentBill;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Every account sees its own data and nobody else's.
 *
 * An account is one head (an admin or a landlord) plus everything they, or the
 * staff they created, created. These tests drive the real HTTP API as real
 * bearer-token users and check three things: an account never reads another's
 * records, never changes another's records, and its staff work on the head's
 * data rather than on an empty view of their own.
 *
 * Seeding goes through DB::table / unscoped models and assertions on scoped
 * tables go through DB::table too, because after an HTTP call the app still
 * holds the last user's token and Eloquent scopes would silently filter.
 */
class AccountIsolationTest extends TestCase
{
    use RefreshDatabase;

    // ------------------------------------------------------------ helpers

    private function make(string $role, ?User $creator = null, array $grants = [], array $extra = [], array $services = []): User
    {
        $user = User::factory()->create(array_merge([
            'role' => $role,
            'is_active' => true,
            'permissions' => $grants,
            'created_by' => $creator?->id,
        ], $extra));

        return $this->givenServices($user, ...$services);
    }

    /** One request as $user's own bearer token, with a fresh auth guard. */
    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    /**
     * Read as the platform, not as whoever made the last request: after an HTTP call the
     * app still holds that user's token, so model reads would run inside their business.
     * Used to check that a refused request really changed nothing.
     */
    private function unscoped(callable $read)
    {
        return TenantContext::withoutScope($read);
    }

    /** @return array{0: User, 1: string} the driver's login and the drivers.id */
    private function driverFor(User $owner, string $name): array
    {
        $user = $this->make('driver', $owner, [], ['name' => $name]);
        $driverId = (string) Str::uuid();
        DB::table('drivers')->insert([
            'id' => $driverId, 'user_id' => $user->id, 'license_number' => 'LIC-' . Str::random(8),
            'license_expiry' => now()->addYear()->toDateString(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        return [$user, $driverId];
    }

    private function vehicle(?string $driverId, ?User $creator, string $plate): string
    {
        $id = (string) Str::uuid();
        DB::table('devices')->insert([
            'id' => $id, 'driver_id' => $driverId, 'created_by' => $creator?->id, 'name' => $plate,
            'type' => 'pikipiki', 'plate_number' => $plate, 'is_active' => 1,
            'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    private function payment(string $driverId, User $by, float $amount): int
    {
        return DB::table('payments')->insertGetId([
            'reference_number' => 'PAY-' . Str::random(10), 'driver_id' => $driverId, 'amount' => $amount,
            'payment_channel' => 'cash', 'status' => 'completed', 'payment_date' => now(),
            'recorded_by' => $by->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function debt(string $driverId, float $expected = 10000): int
    {
        return DB::table('debt_records')->insertGetId([
            'driver_id' => $driverId, 'earning_date' => now()->toDateString(), 'expected_amount' => $expected,
            'paid_amount' => 0, 'is_paid' => false, 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    /**
     * Two transport accounts with distinct sizes so a leak shows up as a wrong
     * count: A has 1 driver, 2 vehicles (one spare), 1 payment, 1 debt;
     * B has 2 drivers, 2 vehicles (one spare), 2 payments, 2 debts.
     */
    private function transportAccounts(): array
    {
        $a = $this->make('admin', null, [], ['name' => 'Admin A'], ['transport']);
        $b = $this->make('admin', null, [], ['name' => 'Admin B'], ['transport']);

        [$dAUser, $dA] = $this->driverFor($a, 'Driver A');
        [$dB1User, $dB1] = $this->driverFor($b, 'Driver B1');
        [$dB2User, $dB2] = $this->driverFor($b, 'Driver B2');

        $vA = $this->vehicle($dA, $a, 'A-ASSIGNED');
        $uA = $this->vehicle(null, $a, 'A-SPARE');
        $vB = $this->vehicle($dB1, $b, 'B-ASSIGNED');
        $uB = $this->vehicle(null, $b, 'B-SPARE');

        return [
            'a' => $a, 'b' => $b,
            'dAUser' => $dAUser, 'dA' => $dA, 'dB1User' => $dB1User, 'dB1' => $dB1, 'dB2' => $dB2,
            'vA' => $vA, 'uA' => $uA, 'vB' => $vB, 'uB' => $uB,
            'pA' => $this->payment($dA, $a, 10000),
            'pB1' => $this->payment($dB1, $b, 20000),
            'pB2' => $this->payment($dB2, $b, 30000),
            'debtA' => $this->debt($dA),
            'debtB1' => $this->debt($dB1),
            'debtB2' => $this->debt($dB2),
        ];
    }

    // --------------------------------------------------- account helpers

    public function test_an_account_is_the_head_and_the_staff_they_created(): void
    {
        $super = $this->make('super_admin');
        $head = $this->make('admin', $super);
        $manager = $this->make('manager', $head);
        $deputy = $this->make('sales_officer', $manager);           // staff of staff
        $driver = $this->make('driver', $manager);                  // a counterparty, not staff
        $landlord = $this->make('landlord', $head);                 // runs their own account
        $stray = $this->make('manager', $super);                    // no admin above them

        $this->assertSame((string) $head->id, $head->accountHeadId());
        $this->assertSame((string) $head->id, $manager->accountHeadId());
        $this->assertSame((string) $head->id, $deputy->accountHeadId());
        $this->assertSame((string) $head->id, $driver->accountHeadId());
        $this->assertSame((string) $landlord->id, $landlord->accountHeadId(), 'a landlord heads their own account');
        $this->assertSame((string) $stray->id, $stray->accountHeadId(), 'with no admin above, a user is their own account');

        $members = $head->accountMemberIds();
        $this->assertEqualsCanonicalizing([(string) $head->id, (string) $manager->id, (string) $deputy->id], $members);
        $this->assertNotContains((string) $driver->id, $members, 'drivers are counterparties, not staff');
        $this->assertNotContains((string) $landlord->id, $members, 'another account head is not staff');
    }

    // ------------------------------------------------------------ transport

    public function test_an_admin_sees_only_their_own_drivers_and_vehicles(): void
    {
        $t = $this->transportAccounts();

        $drivers = collect($this->as($t['a'], 'GET', '/api/admin/drivers')->assertOk()->json('data.data'))->pluck('name')->all();
        $this->assertSame(['Driver A'], $drivers);

        $plates = collect($this->as($t['a'], 'GET', '/api/admin/vehicles')->assertOk()->json('data.data'))
            ->pluck('plate_number')->sort()->values()->all();
        $this->assertSame(['A-ASSIGNED', 'A-SPARE'], $plates, "another admin's spare vehicle must not appear");

        $bPlates = collect($this->as($t['b'], 'GET', '/api/admin/vehicles')->assertOk()->json('data.data'))
            ->pluck('plate_number')->sort()->values()->all();
        $this->assertSame(['B-ASSIGNED', 'B-SPARE'], $bPlates);
    }

    public function test_super_admin_sees_every_account(): void
    {
        $t = $this->transportAccounts();
        $super = $this->make('super_admin');

        $drivers = collect($this->as($super, 'GET', '/api/admin/drivers?limit=50')->assertOk()->json('data.data'))->pluck('name')->sort()->values()->all();
        $this->assertSame(['Driver A', 'Driver B1', 'Driver B2'], $drivers);

        $this->assertCount(4, $this->as($super, 'GET', '/api/admin/vehicles')->assertOk()->json('data.data'));
    }

    public function test_another_accounts_vehicle_cannot_be_edited_deleted_or_assigned(): void
    {
        $t = $this->transportAccounts();

        foreach (['vB', 'uB'] as $key) {
            $this->as($t['a'], 'PUT', "/api/admin/vehicles/{$t[$key]}", ['name' => 'hijacked'])->assertNotFound();
            $this->as($t['a'], 'DELETE', "/api/admin/vehicles/{$t[$key]}")->assertNotFound();
        }
        $this->assertSame(2, DB::table('devices')->whereIn('id', [$t['vB'], $t['uB']])->where('name', '!=', 'hijacked')->count());

        // Pointing my own vehicle at someone else's driver is refused...
        $this->as($t['a'], 'PUT', "/api/admin/vehicles/{$t['vA']}", ['driver_id' => $t['dB1']])->assertStatus(422);
        $this->assertSame($t['dA'], DB::table('devices')->where('id', $t['vA'])->value('driver_id'));

        // ...and so is assigning across accounts in either direction.
        $this->as($t['a'], 'POST', '/api/admin/assign-driver', ['driver_id' => $t['dB1User']->id, 'vehicle_id' => $t['vA']])->assertNotFound();
        $this->as($t['a'], 'POST', '/api/admin/assign-driver', ['driver_id' => $t['dAUser']->id, 'vehicle_id' => $t['uB']])->assertNotFound();
        $this->assertNull(DB::table('devices')->where('id', $t['uB'])->value('driver_id'));
    }

    public function test_dashboard_totals_count_only_the_callers_account(): void
    {
        $t = $this->transportAccounts();

        $a = $this->as($t['a'], 'GET', '/api/admin/dashboard')->assertOk();
        $this->assertSame(1, $a->json('data.total_drivers'));
        $this->assertSame(2, $a->json('data.total_vehicles'));
        $this->assertEquals(10000, $a->json('data.payments_today'));

        $b = $this->as($t['b'], 'GET', '/api/admin/dashboard')->assertOk();
        $this->assertSame(2, $b->json('data.total_drivers'));
        $this->assertEquals(50000, $b->json('data.payments_today'));

        // The dashboard cards (the combined /dashboard-data query uses MySQL-only YEAR(), so it cannot run on SQLite).
        $this->assertSame(1, $this->as($t['a'], 'GET', '/api/admin/dashboard/active-drivers-count')->assertOk()->json('data.count'));
        $this->assertSame(1, $this->as($t['a'], 'GET', '/api/admin/dashboard/unpaid-debts-count')->assertOk()->json('data.count'), "B's debts must not be added in");
        $this->assertEquals(10000, $this->as($t['a'], 'GET', '/api/admin/dashboard/daily-revenue')->assertOk()->json('data.payment_revenue'));
        $this->assertSame(2, $this->as($t['b'], 'GET', '/api/admin/dashboard/unpaid-debts-count')->assertOk()->json('data.count'));
    }

    public function test_payments_and_debts_of_another_account_are_invisible_and_untouchable(): void
    {
        $t = $this->transportAccounts();

        $debtors = collect($this->as($t['a'], 'GET', '/api/admin/payments/drivers-with-debts')->assertOk()->json('data.drivers'))
            ->pluck('name')->all();
        $this->assertSame(['Driver A'], $debtors);

        $this->assertSame(1, $this->as($t['a'], 'GET', '/api/admin/payments/history')->assertOk()->json('data.pagination.total'));

        // Integer ids are guessable, so every one of these must be a plain not-found.
        $this->as($t['a'], 'PUT', "/api/admin/payments/{$t['pB1']}", ['remarks' => 'tampered'])->assertNotFound();
        $this->as($t['a'], 'DELETE', "/api/admin/payments/{$t['pB1']}")->assertNotFound();
        $this->as($t['a'], 'PUT', "/api/admin/debts/records/{$t['debtB1']}", ['paid_amount' => 1])->assertNotFound();
        $this->as($t['a'], 'DELETE', "/api/admin/debts/records/{$t['debtB1']}")->assertNotFound();
        $this->assertSame(1, DB::table('payments')->where('id', $t['pB1'])->count());
        $this->assertSame(1, DB::table('debt_records')->where('id', $t['debtB1'])->count());

        // Recording a payment against someone else's driver is a validation error, not a write.
        $before = DB::table('payments')->count();
        $this->as($t['a'], 'POST', '/api/admin/payments/record', [
            'driver_id' => $t['dB1'], 'amount' => 5000, 'payment_channel' => 'cash',
            'covers_days' => [now()->addDay()->toDateString()],
        ])->assertStatus(422);
        $this->assertSame($before, DB::table('payments')->count());
        $this->assertSame(0, DB::table('debt_records')->where('driver_id', $t['dB1'])->where('earning_date', now()->addDay()->toDateString())->count());
    }

    public function test_staff_work_on_the_heads_data(): void
    {
        $t = $this->transportAccounts();
        $staff = $this->make('manager', $t['a'], [
            'manage_drivers_transport', 'manage_vehicles_transport', 'manage_payments_transport',
        ], [], ['transport']);

        $drivers = collect($this->as($staff, 'GET', '/api/admin/drivers')->assertOk()->json('data.data'))->pluck('name')->all();
        $this->assertSame(['Driver A'], $drivers, 'staff see the head\'s drivers, not an empty list and not B\'s');

        $plates = collect($this->as($staff, 'GET', '/api/admin/vehicles')->assertOk()->json('data.data'))
            ->pluck('plate_number')->sort()->values()->all();
        $this->assertSame(['A-ASSIGNED', 'A-SPARE'], $plates);

        // A vehicle the staff member adds belongs to the account: the head sees it, the other account does not.
        $this->as($staff, 'POST', '/api/admin/vehicles', ['name' => 'Staff bike', 'type' => 'pikipiki', 'plate_number' => 'STAFF-1'])->assertCreated();
        $this->assertContains('STAFF-1', collect($this->as($t['a'], 'GET', '/api/admin/vehicles')->json('data.data'))->pluck('plate_number')->all());
        $this->assertNotContains('STAFF-1', collect($this->as($t['b'], 'GET', '/api/admin/vehicles')->json('data.data'))->pluck('plate_number')->all());
    }

    public function test_a_driver_still_reaches_only_their_own_records(): void
    {
        $t = $this->transportAccounts();

        $profile = $this->as($t['dAUser'], 'GET', '/api/driver/profile')->assertOk();
        $this->assertSame('Driver A', $profile->json('data.name'));

        $payments = $this->as($t['dAUser'], 'GET', '/api/driver/payments')->assertOk();
        $this->assertSame(1, $payments->json('data.pagination.total'), 'only their own payment');

        // They are not an admin, so the admin API stays closed to them.
        $this->as($t['dAUser'], 'GET', '/api/admin/drivers')->assertForbidden();
    }

    public function test_the_user_directory_lists_only_the_callers_account(): void
    {
        $t = $this->transportAccounts();
        $staffA = $this->make('manager', $t['a'], [], ['name' => 'Staff A']);
        $staffB = $this->make('manager', $t['b'], [], ['name' => 'Staff B']);
        // Both admins share the transport service: that must not merge their users.
        foreach ([$t['a'], $t['b'], $staffA, $staffB] as $u) {
            $this->givenServices($u, 'transport');
        }

        $names = collect($this->as($t['a'], 'GET', '/api/admin/users/mine?limit=100')->assertOk()->json('data.users'))
            ->pluck('name')->sort()->values()->all();
        $this->assertSame(['Admin A', 'Driver A', 'Staff A'], $names);

        $all = collect($this->as($this->make('super_admin'), 'GET', '/api/admin/users/mine?limit=100')->assertOk()->json('data.users'))
            ->pluck('name')->all();
        $this->assertContains('Staff B', $all);
    }

    // --------------------------------------------------------------- rental

    /**
     * Two landlords, each with one property / house / tenant / lease / bill,
     * a paid receipt for L2, and a maintenance request on each property.
     */
    private function rentalAccounts(): array
    {
        $l1 = $this->make('landlord', null, [], ['name' => 'Landlord 1']);
        $l2 = $this->make('landlord', null, [], ['name' => 'Landlord 2']);
        $staff = $this->make('manager', $l1, [
            'manage_properties_rental', 'manage_houses_rental', 'onboard_tenants_rental',
            'manage_agreements_rental', 'manage_billing_rental', 'view_reports_rental', 'manage_maintenance_rental',
        ], [], ['rental']);
        $caretaker = $this->make('caretaker', $l1, [], ['name' => 'Caretaker 1']);

        $out = ['l1' => $l1, 'l2' => $l2, 'staff' => $staff, 'caretaker' => $caretaker];

        foreach ([1 => $l1, 2 => $l2] as $n => $landlord) {
            $property = Property::create([
                'owner_id' => $landlord->id, 'name' => "Property {$n}",
                'caretaker_id' => $n === 1 ? $caretaker->id : null,
            ]);
            $block = Block::create(['property_id' => $property->id, 'name' => "Block {$n}"]);
            $house = House::create(['property_id' => $property->id, 'house_number' => "H{$n}", 'rent_amount' => 100000]);
            $tenant = $this->make('tenant', $landlord, [], ['name' => "Tenant {$n}"]);
            $lease = RentalAgreement::create([
                'tenant_id' => $tenant->id, 'house_id' => $house->id, 'property_id' => $property->id,
                'start_date' => now()->toDateString(), 'rent_cycle' => 'monthly', 'rent_amount' => 100000, 'status' => 'active',
            ]);
            $bill = RentBill::create([
                'agreement_id' => $lease->id, 'month_year' => now()->format('m-Y'),
                'amount_due' => 100000, 'balance' => 100000, 'due_date' => now()->addDays(5)->toDateString(), 'status' => 'unpaid',
            ]);
            $request = MaintenanceRequest::create([
                'property_id' => $property->id, 'house_id' => $house->id, 'tenant_id' => $tenant->id,
                'category' => 'plumbing', 'priority' => 'high', 'description' => "Leak {$n}", 'status' => 'open',
            ]);

            $out["p{$n}"] = $property;
            $out["block{$n}"] = $block;
            $out["house{$n}"] = $house;
            $out["tenant{$n}"] = $tenant;
            $out["bill{$n}"] = $bill;
            $out["mr{$n}"] = $request;
        }

        $payment = RentalPayment::create([
            'bill_id' => $out['bill2']->id, 'tenant_id' => $out['tenant2']->id, 'amount_paid' => 50000,
            'payment_date' => now()->toDateString(), 'payment_method' => 'cash', 'collector_id' => $l2->id,
        ]);
        $out['receipt2'] = RentalReceipt::create([
            'payment_id' => $payment->id, 'receipt_number' => 'RCP-TEST0002', 'details' => ['tenant_name' => 'Tenant 2'],
        ]);

        return $out;
    }

    public function test_a_landlord_and_their_staff_see_only_that_landlords_properties(): void
    {
        $r = $this->rentalAccounts();

        foreach (['l1', 'staff'] as $who) {
            $names = collect($this->as($r[$who], 'GET', '/api/rental/properties')->assertOk()->json('data'))->pluck('name')->all();
            $this->assertSame(['Property 1'], $names, "{$who} should see Landlord 1's portfolio only");
        }

        $this->as($r['l1'], 'GET', "/api/rental/properties/{$r['p2']->id}")->assertNotFound();
        $this->as($r['staff'], 'GET', "/api/rental/properties/{$r['p2']->id}")->assertNotFound();
    }

    public function test_blocks_of_another_landlords_property_are_untouchable(): void
    {
        $r = $this->rentalAccounts();

        $this->as($r['l1'], 'GET', "/api/rental/blocks/{$r['p2']->id}")->assertNotFound();
        $this->as($r['l1'], 'POST', "/api/rental/blocks/{$r['p2']->id}", ['name' => 'Injected'])->assertNotFound();
        $this->as($r['l1'], 'GET', "/api/rental/blocks/block/{$r['block2']->id}")->assertNotFound();
        $this->as($r['l1'], 'PUT', "/api/rental/blocks/block/{$r['block2']->id}", ['name' => 'Renamed'])->assertNotFound();
        $this->as($r['l1'], 'DELETE', "/api/rental/blocks/block/{$r['block2']->id}")->assertNotFound();

        $this->assertSame('Block 2', $this->unscoped(fn () => Block::find($r['block2']->id)->name));
        $this->assertSame(0, $this->unscoped(fn () => Block::where('name', 'Injected')->count()));

        // Their own block still works.
        $this->as($r['l1'], 'GET', "/api/rental/blocks/block/{$r['block1']->id}")->assertOk();
    }

    public function test_receipts_and_payments_of_another_landlord_are_not_reachable(): void
    {
        $r = $this->rentalAccounts();
        $rentalAdmin = $this->make('admin', null, [], [], ['rental']);   // an admin is an account too -- not a platform bypass

        foreach (['l1', 'staff'] as $who) {
            $this->as($r[$who], 'GET', "/api/rental/receipts/{$r['receipt2']->id}")->assertNotFound();
        }
        $this->as($rentalAdmin, 'GET', "/api/rental/receipts/{$r['receipt2']->id}")->assertNotFound();
        $this->as($rentalAdmin, 'POST', "/api/rental/receipts/{$r['receipt2']->id}/dispatch")->assertNotFound();
        $this->assertFalse((bool) $this->unscoped(fn () => RentalReceipt::find($r['receipt2']->id)->is_dispatched));

        // The owner still can.
        $this->as($r['l2'], 'GET', "/api/rental/receipts/{$r['receipt2']->id}")->assertOk();

        // Money cannot be recorded against a bill on someone else's property.
        $this->as($r['l1'], 'POST', '/api/rental/payments/record', [
            'bill_id' => $r['bill2']->id, 'amount_paid' => 1000, 'payment_method' => 'cash',
        ])->assertNotFound();
        $this->as($rentalAdmin, 'POST', '/api/rental/payments/record', [
            'bill_id' => $r['bill2']->id, 'amount_paid' => 1000, 'payment_method' => 'cash',
        ])->assertNotFound();
        $this->assertEquals(100000, $this->unscoped(fn () => RentBill::find($r['bill2']->id)->balance));
    }

    public function test_bills_are_shown_by_role_within_the_account(): void
    {
        $r = $this->rentalAccounts();
        $rentalAdmin = $this->make('admin', null, [], [], ['rental']);

        foreach (['l1' => 1, 'staff' => 1, 'tenant1' => 1, 'caretaker' => 1] as $who => $expected) {
            $user = $who === 'tenant1' ? $r['tenant1'] : $r[$who];
            $bills = $this->as($user, 'GET', '/api/rental/billing/bills')->assertOk()->json('data');
            $this->assertCount($expected, $bills, "{$who} should see exactly their account's bill");
            $this->assertSame($r['bill1']->id, $bills[0]['id']);
        }

        $this->assertCount(0, $this->as($rentalAdmin, 'GET', '/api/rental/billing/bills')->assertOk()->json('data'));
        $this->assertCount(1, $this->as($r['l2'], 'GET', '/api/rental/billing/bills')->assertOk()->json('data'));
    }

    public function test_onboarding_is_limited_to_houses_the_account_owns_and_never_demotes_anyone(): void
    {
        $r = $this->rentalAccounts();

        $payload = fn (string $email, string $houseId) => [
            'first_name' => 'New', 'last_name' => 'Tenant', 'email' => $email, 'phone' => '0712000111',
            'rental_house_id' => $houseId, 'rent_amount' => 100000,
        ];

        // Another landlord's house.
        $this->as($r['l1'], 'POST', '/api/rental/tenants/onboard', $payload('new@example.test', $r['house2']->id))->assertNotFound();
        $this->assertSame(0, User::where('email', 'new@example.test')->count());

        // An email that already belongs to a landlord must not turn them into a tenant.
        $this->as($r['l1'], 'POST', '/api/rental/tenants/onboard', $payload($r['l2']->email, $r['house1']->id))->assertStatus(422);
        $this->assertSame('landlord', $r['l2']->fresh()->role);
    }

    public function test_a_tenant_onboarded_by_a_landlord_belongs_to_that_landlords_account(): void
    {
        $r = $this->rentalAccounts();

        $this->as($r['l1'], 'POST', '/api/rental/tenants/onboard', [
            'first_name' => 'Fresh', 'last_name' => 'Tenant', 'email' => 'fresh@example.test', 'phone' => '0712000999',
            'rental_house_id' => $r['house1']->id, 'rent_amount' => 100000,
        ])->assertCreated();

        $tenant = User::where('email', 'fresh@example.test')->firstOrFail();
        $this->assertSame('tenant', $tenant->role);
        $this->assertSame((string) $r['l1']->id, (string) $tenant->created_by, 'recorded against whoever onboarded them');
    }

    public function test_maintenance_requests_follow_the_account_and_the_role(): void
    {
        $r = $this->rentalAccounts();
        $rentalAdmin = $this->make('admin', null, [], [], ['rental']);

        $ids = fn (User $u) => collect($this->as($u, 'GET', '/api/rental/maintenance/requests')->assertOk()->json('data'))->pluck('id')->all();

        $this->assertSame([$r['mr1']->id], $ids($r['l1']));
        $this->assertSame([$r['mr1']->id], $ids($r['staff']));
        $this->assertSame([$r['mr1']->id], $ids($r['caretaker']), 'a caretaker sees the properties assigned to them');
        $this->assertSame([$r['mr1']->id], $ids($r['tenant1']));
        $this->assertSame([], $ids($rentalAdmin), 'an admin sees their own account, not every landlord\'s requests');

        // Opening, assigning or closing another account's request is a plain not-found.
        $this->as($r['l1'], 'GET', "/api/rental/maintenance/requests/{$r['mr2']->id}")->assertNotFound();
        $this->as($r['l1'], 'PUT', "/api/rental/maintenance/requests/{$r['mr2']->id}/status", ['status' => 'resolved'])->assertNotFound();
        $this->assertSame('open', $this->unscoped(fn () => MaintenanceRequest::find($r['mr2']->id)->status));
    }

    public function test_a_tenant_can_only_raise_requests_on_the_property_they_rent(): void
    {
        $r = $this->rentalAccounts();

        $this->as($r['tenant1'], 'POST', '/api/rental/maintenance/requests', [
            'property_id' => $r['p2']->id, 'category' => 'electrical', 'priority' => 'low', 'description' => 'wrong property',
        ])->assertNotFound();
        $this->assertSame(0, $this->unscoped(fn () => MaintenanceRequest::where('description', 'wrong property')->count()));

        $this->as($r['tenant1'], 'POST', '/api/rental/maintenance/requests', [
            'property_id' => $r['p1']->id, 'category' => 'electrical', 'priority' => 'low', 'description' => 'right property',
        ])->assertCreated();
    }

    public function test_a_house_cannot_be_filed_under_another_landlords_block(): void
    {
        $r = $this->rentalAccounts();

        $this->as($r['l1'], 'POST', "/api/rental/properties/{$r['p1']->id}/houses", [
            'house_number' => 'X1', 'rent_amount' => 1000, 'block_id' => $r['block2']->id,
        ])->assertStatus(422)->assertJsonValidationErrors('block_id');

        $this->as($r['l1'], 'PUT', "/api/rental/houses/{$r['house1']->id}", ['block_id' => $r['block2']->id])
            ->assertStatus(422)->assertJsonValidationErrors('block_id');
        $this->assertNull($this->unscoped(fn () => House::find($r['house1']->id)->block_id));
    }

    public function test_a_caretaker_must_belong_to_the_landlords_own_account(): void
    {
        $r = $this->rentalAccounts();
        $stranger = $this->make('caretaker', $r['l2']);

        $this->as($r['l1'], 'PUT', "/api/rental/properties/{$r['p1']->id}", ['caretaker_id' => $stranger->id])
            ->assertStatus(422)->assertJsonValidationErrors('caretaker_id');
        $this->assertSame((string) $r['caretaker']->id, (string) $this->unscoped(fn () => Property::find($r['p1']->id)->caretaker_id));

        // Their own caretaker -- and re-sending the current one -- is fine.
        $this->as($r['l1'], 'PUT', "/api/rental/properties/{$r['p1']->id}", ['caretaker_id' => $r['caretaker']->id])
            ->assertJsonMissingValidationErrors('caretaker_id');
    }

    public function test_adding_a_vendor_never_overwrites_another_landlords_vendor(): void
    {
        $r = $this->rentalAccounts();

        $this->as($r['l2'], 'POST', '/api/rental/maintenance/vendors', ['name' => 'Fundi Original', 'phone' => '0755123456'])->assertCreated();
        $vendorId = DB::table('rental_vendors')->where('phone', '0755123456')->value('id');
        $this->assertSame((string) $r['l2']->id, (string) DB::table('rental_vendors')->where('id', $vendorId)->value('created_by'));

        $this->as($r['l1'], 'POST', '/api/rental/maintenance/vendors', ['name' => 'Hijacked Name', 'phone' => '0755123456'])->assertOk();

        $row = DB::table('rental_vendors')->where('id', $vendorId)->first();
        $this->assertSame('Fundi Original', $row->name, 'the existing vendor record must not be rewritten');
        $this->assertSame((string) $r['l2']->id, (string) $row->created_by, 'and must keep its original creator');
        $this->assertSame(1, DB::table('rental_vendors')->where('phone', '0755123456')->count());

        // L1 simply gained it on their roster -- and their staff share that roster.
        $this->assertContains($vendorId, collect($this->as($r['l1'], 'GET', '/api/rental/maintenance/vendors')->assertOk()->json('data'))->pluck('id')->all());
        $this->assertContains($vendorId, collect($this->as($r['staff'], 'GET', '/api/rental/maintenance/vendors')->assertOk()->json('data'))->pluck('id')->all());
    }
}
