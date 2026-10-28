<?php

namespace Tests\Feature;

use App\Models\Rental\Property;
use App\Models\User;
use App\Support\Tenancy\ServiceBranch;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Branches of a transport or rental business: made by the owner, kept apart per business and per service, assigned to the
 * records that carry them (drivers, vehicles, properties) and followed by every list when one is looked at.
 */
class TransportRentalBranchesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        ServiceBranch::forget();
    }

    private function admin(string $role, string $service): User
    {
        return $this->givenServices(User::factory()->create(['role' => $role, 'is_active' => true]), $service);
    }

    /** One request as a person, with the branch headers the app sends. */
    private function req(User $user, string $method, string $url, array $body = [], ?int $branch = null, ?string $service = null)
    {
        $this->app['auth']->forgetGuards();
        $this->flushHeaders(); // headers of an earlier call would stick
        ServiceBranch::forget();
        $headers = ['Authorization' => 'Bearer ' . $user->createToken('t')->plainTextToken];
        if ($branch !== null) {
            $headers['X-Branch'] = (string) $branch;
        }
        if ($service !== null) {
            $headers['X-Branch-Service'] = $service;
        }

        return $this->withHeaders($headers)->json($method, $url, $body);
    }

    private function branch(User $user, string $service, string $name): int
    {
        $prefix = $service === 'transport' ? '/api/admin/branches' : '/api/rental/branches';

        return (int) $this->req($user, 'POST', $prefix, ['name' => $name])->assertCreated()->json('data.id');
    }

    private function driver(User $owner, string $name, ?int $branch = null): string
    {
        $user = User::factory()->create(['name' => $name, 'role' => 'driver', 'is_active' => true, 'created_by' => $owner->id]);
        $id = (string) Str::uuid();
        DB::table('drivers')->insert([
            'id' => $id, 'user_id' => $user->id, 'owner_id' => $owner->id, 'license_number' => 'LIC-' . Str::random(8), 'branch_id' => $branch,
            'license_expiry' => now()->addYear()->toDateString(), 'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    private function names(User $owner, ?int $branch, ?string $service = 'transport'): array
    {
        return collect($this->req($owner, 'GET', '/api/admin/drivers?limit=100', [], $branch, $service)->assertOk()->json('data.data'))
            ->pluck('name')->sort()->values()->all();
    }

    public function test_the_owner_makes_lists_renames_and_switches_off_branches_of_the_service(): void
    {
        $owner = $this->admin('admin', 'transport');

        $yard = $this->branch($owner, 'transport', 'Dodoma yard');
        $this->req($owner, 'POST', '/api/admin/branches', ['name' => 'Dodoma yard'])->assertStatus(422); // no twin names
        $this->req($owner, 'PUT', "/api/admin/branches/{$yard}", ['address' => 'Area D'])->assertOk()->assertJsonPath('data.address', 'Area D');

        $this->assertSame(['Dodoma yard'], collect($this->req($owner, 'GET', '/api/admin/branches')->assertOk()->json('data'))->pluck('name')->all());

        $this->req($owner, 'PUT', "/api/admin/branches/{$yard}", ['active' => false])->assertOk()->assertJsonPath('data.active', false);
        $this->req($owner, 'DELETE', "/api/admin/branches/{$yard}")->assertOk(); // nothing in it yet
        $this->assertSame([], $this->req($owner, 'GET', '/api/admin/branches')->json('data'));
    }

    public function test_a_branch_that_has_records_cannot_be_deleted_only_switched_off(): void
    {
        $owner = $this->admin('admin', 'transport');
        $yard = $this->branch($owner, 'transport', 'Yard');
        $this->driver($owner, 'Juma', $yard);

        $this->req($owner, 'DELETE', "/api/admin/branches/{$yard}")->assertStatus(422);
        $this->assertSame(1, $this->req($owner, 'GET', '/api/admin/branches')->json('data.0.records'));
    }

    public function test_one_business_never_sees_or_touches_the_branches_of_another(): void
    {
        $a = $this->admin('admin', 'transport');
        $b = $this->admin('admin', 'transport');
        $mine = $this->branch($a, 'transport', 'Yard');

        $this->assertSame([], $this->req($b, 'GET', '/api/admin/branches')->json('data'));
        $this->req($b, 'PUT', "/api/admin/branches/{$mine}", ['name' => 'Stolen'])->assertNotFound();
        $this->req($b, 'DELETE', "/api/admin/branches/{$mine}")->assertNotFound();
        // the same name is fine in another business
        $this->branch($b, 'transport', 'Yard');
    }

    public function test_the_drivers_list_follows_the_branch_looked_at(): void
    {
        $owner = $this->admin('admin', 'transport');
        $north = $this->branch($owner, 'transport', 'North');
        $south = $this->branch($owner, 'transport', 'South');
        $this->driver($owner, 'Asha', $north);
        $this->driver($owner, 'Baraka', $south);
        $this->driver($owner, 'Chausiku');

        $this->assertSame(['Asha', 'Baraka', 'Chausiku'], $this->names($owner, null, null), 'no branch chosen: everyone');
        $this->assertSame(['Asha'], $this->names($owner, $north));
        $this->assertSame(['Baraka'], $this->names($owner, $south));
    }

    public function test_a_branch_of_another_business_or_service_or_with_no_service_named_is_ignored(): void
    {
        $owner = $this->admin('admin', 'transport');
        $other = $this->admin('admin', 'transport');
        $north = $this->branch($owner, 'transport', 'North');
        $theirs = $this->branch($other, 'transport', 'Theirs');
        $this->driver($owner, 'Asha', $north);
        $this->driver($owner, 'Baraka');

        $all = ['Asha', 'Baraka'];
        $this->assertSame($all, $this->names($owner, $theirs), 'another business\'s branch');
        $this->assertSame($all, $this->names($owner, $north, 'rental'), 'chosen in another service');
        $this->assertSame($all, $this->names($owner, $north, null), 'no service named');
        $this->req($owner, 'PUT', "/api/admin/branches/{$north}", ['active' => false])->assertOk();
        $this->assertSame($all, $this->names($owner, $north), 'a switched-off branch');
    }

    public function test_a_new_vehicle_takes_the_branch_named_or_the_one_looked_at(): void
    {
        $owner = $this->admin('admin', 'transport');
        $north = $this->branch($owner, 'transport', 'North');
        $south = $this->branch($owner, 'transport', 'South');
        $stranger = $this->branch($this->admin('admin', 'transport'), 'transport', 'Elsewhere');

        $named = $this->req($owner, 'POST', '/api/admin/vehicles', ['name' => 'Bajaji', 'type' => 'bajaji', 'plate_number' => 'T 111 AAA', 'branch_id' => $south])->assertCreated();
        $this->assertSame($south, (int) DB::table('devices')->where('plate_number', 'T 111 AAA')->value('branch_id'));
        $this->assertNotNull($named->json('data.id'));

        $this->req($owner, 'POST', '/api/admin/vehicles', ['name' => 'Bajaji', 'type' => 'bajaji', 'plate_number' => 'T 222 BBB'], $north, 'transport')->assertCreated();
        $this->assertSame($north, (int) DB::table('devices')->where('plate_number', 'T 222 BBB')->value('branch_id'), 'the branch in view');

        $this->req($owner, 'POST', '/api/admin/vehicles', ['name' => 'Bajaji', 'type' => 'bajaji', 'plate_number' => 'T 333 CCC', 'branch_id' => $stranger])->assertCreated();
        $this->assertNull(DB::table('devices')->where('plate_number', 'T 333 CCC')->value('branch_id'), 'another business\'s branch is not accepted');

        $this->assertSame(['T 222 BBB'], collect($this->req($owner, 'GET', '/api/admin/vehicles', [], $north, 'transport')->json('data.data'))->pluck('plate_number')->all());
    }

    public function test_properties_and_what_hangs_off_them_follow_the_branch_looked_at(): void
    {
        $landlord = $this->admin('landlord', 'rental');
        $town = $this->branch($landlord, 'rental', 'Town');
        $coast = $this->branch($landlord, 'rental', 'Coast');
        $a = Property::create(['owner_id' => $landlord->id, 'name' => 'Town flats', 'branch_id' => $town]);
        $b = Property::create(['owner_id' => $landlord->id, 'name' => 'Coast villas', 'branch_id' => $coast]);
        Property::create(['owner_id' => $landlord->id, 'name' => 'Unplaced']);

        $listed = function (?int $branch) use ($landlord) {
            $r = $this->req($landlord, 'GET', '/api/rental/properties?per_page=100', [], $branch, 'rental')->assertOk();
            $rows = $r->json('data.data') ?? $r->json('data');

            return collect($rows)->pluck('name')->sort()->values()->all();
        };

        $this->assertSame(['Coast villas', 'Town flats', 'Unplaced'], $listed(null));
        $this->assertSame(['Town flats'], $listed($town));
        $this->assertSame(['Coast villas'], $listed($coast));

        // one property of another branch cannot even be opened while looking at this one
        $this->req($landlord, 'GET', "/api/rental/properties/{$b->id}", [], null, 'rental')->assertOk();
        $this->req($landlord, 'GET', "/api/rental/properties/{$b->id}", [], $town, 'rental')->assertNotFound();
        $this->assertNotNull($a);
    }

    public function test_a_property_is_placed_in_a_branch_when_made_or_changed(): void
    {
        $landlord = $this->admin('landlord', 'rental');
        $town = $this->branch($landlord, 'rental', 'Town');
        $coast = $this->branch($landlord, 'rental', 'Coast');

        $made = $this->req($landlord, 'POST', '/api/rental/properties', [
            'name' => 'New block', 'property_type' => 'apartment', 'region' => 'Dodoma', 'district' => 'Dodoma', 'address' => 'Main st', 'billing_cycle' => 'monthly', 'branch_id' => $town,
        ]);
        $made->assertCreated();
        $id = $made->json('data.id');
        $this->assertSame($town, (int) DB::table('rental_properties')->where('id', $id)->value('branch_id'));

        $this->req($landlord, 'PUT', "/api/rental/properties/{$id}", ['branch_id' => $coast])->assertOk();
        $this->assertSame($coast, (int) DB::table('rental_properties')->where('id', $id)->value('branch_id'));

        $this->req($landlord, 'PUT', "/api/rental/properties/{$id}", ['branch_id' => null])->assertOk();
        $this->assertNull(DB::table('rental_properties')->where('id', $id)->value('branch_id'));
    }

    public function test_the_service_a_branch_belongs_to_is_the_only_door_to_it(): void
    {
        $owner = $this->admin('admin', 'transport');
        $this->givenServices($owner, 'rental');
        $yard = $this->branch($owner, 'transport', 'Yard');

        $this->assertSame([], $this->req($owner, 'GET', '/api/rental/branches')->json('data'), 'a transport branch is not a rental one');
        $this->req($owner, 'PUT', "/api/rental/branches/{$yard}", ['name' => 'X'])->assertNotFound();
    }
}
