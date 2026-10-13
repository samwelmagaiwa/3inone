<?php

namespace Tests\Feature;

use App\Models\Rental\Block;
use App\Models\Rental\House;
use App\Models\Rental\MaintenanceRequest;
use App\Models\Rental\PreventiveMaintenance;
use App\Models\Rental\Property;
use App\Models\Rental\RentalAgreement;
use App\Models\Rental\RentalPayment;
use App\Models\Rental\RentalReceipt;
use App\Models\Rental\RentBill;
use App\Models\Rental\TenantProfile;
use App\Models\Rental\Vendor;
use App\Models\Rental\WorkOrder;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Who sees which Rental record, by role, checked on the MODELS -- so it holds no matter
 * what a controller remembers to filter. Two landlords each have the same set of records;
 * every role must see exactly its own slice and none of the other landlord's.
 *
 * Models are listed in the order of a lease's life:
 * property, block, house, lease, bill, payment, receipt, request, work order, plan, profile.
 */
class RentalAccessTest extends TestCase
{
    use RefreshDatabase;

    private const MODELS = [
        'property' => Property::class,
        'block' => Block::class,
        'house' => House::class,
        'lease' => RentalAgreement::class,
        'bill' => RentBill::class,
        'payment' => RentalPayment::class,
        'receipt' => RentalReceipt::class,
        'request' => MaintenanceRequest::class,
        'work order' => WorkOrder::class,
        'plan' => PreventiveMaintenance::class,
        'profile' => TenantProfile::class,
    ];

    /** @var array<string, User> */
    private array $who = [];

    protected function setUp(): void
    {
        parent::setUp();

        $l1 = $this->user('landlord', 'rental');
        $l2 = $this->user('landlord', 'rental');

        $caretaker = $this->user('caretaker', 'rental', $l1);
        $staff = $this->user('manager', 'rental', $l1);

        $parts1 = $this->portfolio($l1, $caretaker);
        $parts2 = $this->portfolio($l2, null);

        $this->who = [
            'landlord 1' => $l1, 'staff of landlord 1' => $staff, 'caretaker of property 1' => $caretaker,
            'tenant 1' => $parts1['tenant'], 'vendor 1' => $parts1['vendor'],
            'landlord 2' => $l2, 'tenant 2' => $parts2['tenant'], 'vendor 2' => $parts2['vendor'],
            'a driver' => $this->user('driver', 'transport'),
            'super admin' => User::factory()->create(['role' => 'super_admin', 'is_active' => true]),
        ];
    }

    private function user(string $role, string $service, ?User $creator = null): User
    {
        return $this->givenServices(User::factory()->create([
            'role' => $role, 'is_active' => true, 'created_by' => $creator?->id,
        ]), $service);
    }

    /** One of everything under a landlord. @return array{tenant: User, vendor: User} */
    private function portfolio(User $landlord, ?User $caretaker): array
    {
        $tenant = $this->user('tenant', 'rental', $landlord);
        $vendorUser = $this->user('vendor', 'rental');

        $property = Property::create(['owner_id' => $landlord->id, 'caretaker_id' => $caretaker?->id, 'name' => 'P ' . $landlord->id]);
        Block::create(['property_id' => $property->id, 'name' => 'Block']);
        $house = House::create(['property_id' => $property->id, 'house_number' => 'H1', 'rent_amount' => 100000]);
        $lease = RentalAgreement::create([
            'tenant_id' => $tenant->id, 'house_id' => $house->id, 'property_id' => $property->id,
            'start_date' => now()->toDateString(), 'rent_cycle' => 'monthly', 'rent_amount' => 100000, 'status' => 'active',
        ]);
        $bill = RentBill::create([
            'agreement_id' => $lease->id, 'month_year' => now()->format('m-Y'), 'amount_due' => 100000,
            'balance' => 50000, 'due_date' => now()->addDays(5)->toDateString(), 'status' => 'partial',
        ]);
        $payment = RentalPayment::create([
            'bill_id' => $bill->id, 'tenant_id' => $tenant->id, 'amount_paid' => 50000,
            'payment_date' => now()->toDateString(), 'payment_method' => 'cash', 'collector_id' => $landlord->id,
        ]);
        RentalReceipt::create(['payment_id' => $payment->id, 'receipt_number' => 'RCP-' . $landlord->id, 'details' => ['x' => 1]]);

        $request = MaintenanceRequest::create([
            'property_id' => $property->id, 'house_id' => $house->id, 'tenant_id' => $tenant->id,
            'category' => 'plumbing', 'priority' => 'high', 'description' => 'Leak', 'status' => 'open',
        ]);
        $vendor = Vendor::create(['user_id' => $vendorUser->id, 'name' => 'Fundi', 'phone' => '07' . random_int(10000000, 99999999), 'is_active' => true]);
        WorkOrder::create(['maintenance_request_id' => $request->id, 'vendor_id' => $vendor->id, 'title' => 'Fix the leak', 'status' => 'scheduled']);

        PreventiveMaintenance::create([
            'property_id' => $property->id, 'description' => 'Service the pump', 'frequency' => 'monthly',
            'next_run' => now()->addMonth()->toDateString(),
        ]);
        TenantProfile::create(['user_id' => $tenant->id]);

        return ['tenant' => $tenant, 'vendor' => $vendorUser];
    }

    /** How many of each model the person sees. @return array<string, int> */
    private function seenBy(string $who): array
    {
        return TenantContext::runAs($this->who[$who], function () {
            $counts = [];
            foreach (self::MODELS as $label => $class) {
                $counts[$label] = $class::query()->count();
            }

            return $counts;
        });
    }

    private function expect(array $overrides = [], int $default = 0): array
    {
        return array_merge(array_fill_keys(array_keys(self::MODELS), $default), $overrides);
    }

    public function test_an_owner_and_their_staff_see_their_whole_portfolio_and_nobody_elses(): void
    {
        $everything = $this->expect([], 1);

        $this->assertSame($everything, $this->seenBy('landlord 1'));
        $this->assertSame($everything, $this->seenBy('staff of landlord 1'));
        $this->assertSame($everything, $this->seenBy('landlord 2'));
    }

    public function test_a_caretaker_sees_the_properties_they_are_assigned_to(): void
    {
        $this->assertSame($this->expect([], 1), $this->seenBy('caretaker of property 1'));
    }

    public function test_a_tenant_sees_only_their_own_lease_and_what_hangs_off_it(): void
    {
        foreach (['tenant 1', 'tenant 2'] as $tenant) {
            $this->assertSame(
                $this->expect([
                    'property' => 1, 'block' => 1, 'house' => 1, 'lease' => 1, 'bill' => 1, 'payment' => 1,
                    'receipt' => 1, 'request' => 1, 'work order' => 1, 'profile' => 1,
                    'plan' => 0, // a landlord's maintenance plans are not for tenants
                ]),
                $this->seenBy($tenant),
                $tenant
            );
        }
    }

    public function test_a_vendor_sees_only_the_work_assigned_to_them(): void
    {
        foreach (['vendor 1', 'vendor 2'] as $vendor) {
            $this->assertSame(
                $this->expect([
                    'property' => 1, // so the job's address resolves
                    'house' => 1, 'request' => 1, 'work order' => 1,
                ]),
                $this->seenBy($vendor),
                $vendor . ' must not see leases, money, tenants or plans'
            );
        }
    }

    public function test_a_stranger_sees_nothing_and_the_platform_sees_everything(): void
    {
        $this->assertSame($this->expect(), $this->seenBy('a driver'));
        $this->assertSame($this->expect([], 2), $this->seenBy('super admin'));
    }

    public function test_a_landlord_can_delete_a_property_and_only_their_own_goes(): void
    {
        // Deleting a property soft-deletes its houses and blocks with a mass DELETE/UPDATE that
        // runs through the account scope. On MySQL that used to fail (error 1093: the scope reads
        // the table being changed); the whole suite run against MySQL is what proves it now works.
        $mine = TenantContext::withoutScope(fn () => Property::where('owner_id', $this->who['landlord 1']->id)->firstOrFail());
        $theirs = TenantContext::withoutScope(fn () => Property::where('owner_id', $this->who['landlord 2']->id)->firstOrFail());

        $token = $this->who['landlord 1']->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$token}")->deleteJson("/api/rental/properties/{$mine->id}")->assertOk();

        TenantContext::withoutScope(function () use ($mine, $theirs) {
            $this->assertNotNull(Property::withTrashed()->find($mine->id)->deleted_at, 'the property is gone');
            $this->assertSame(0, House::where('property_id', $mine->id)->count(), 'its houses went with it');
            $this->assertSame(1, House::withTrashed()->where('property_id', $mine->id)->onlyTrashed()->count());
            $this->assertSame(0, Block::where('property_id', $mine->id)->count(), 'and its blocks');

            $this->assertNull(Property::find($theirs->id)->deleted_at, 'the other landlord lost nothing');
            $this->assertSame(1, House::where('property_id', $theirs->id)->count());
        });
    }

    public function test_a_forgotten_filter_in_a_controller_cannot_leak_another_landlords_records(): void
    {
        $other = TenantContext::runAs($this->who['landlord 2'], fn () => Property::query()->firstOrFail());

        TenantContext::runAs($this->who['landlord 1'], function () use ($other) {
            $this->assertNull(Property::find($other->id));
            $this->assertNull(Property::withTrashed()->find($other->id), 'soft-deleted views are scoped too');
            $this->assertSame(0, Property::where('id', 'nothing')->orWhere('id', $other->id)->count(), 'an OR cannot widen the scope');
            $this->assertSame(0, House::where('property_id', $other->id)->count());
            $this->assertSame(0, Property::whereKey($other->id)->update(['name' => 'Hijacked']));
        });

        $this->assertNotSame('Hijacked', TenantContext::withoutScope(fn () => Property::find($other->id)->name));
    }
}
