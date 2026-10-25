<?php

namespace Tests\Feature;

use App\Models\Rental\Property;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * One contract, three services.
 *
 * Transport, Rental and Inventory are different code (Eloquent scopes, controller checks
 * and a query-level scope respectively), so the only way to know they behave the same is
 * to run the same scenarios against each. Each scenario below runs once per service, through
 * a small adapter that says how that service creates a record, lists it, reaches it by id and
 * lets staff create one. If a service ever drifts from the others, its case fails.
 *
 *  1. A business sees its own records and never another business's.
 *  2. Its staff see the same records (they work for the business).
 *  3. Another business reaching a record by id gets "not found", and nothing changes.
 *  4. A record a staff member creates belongs to the business, not to the staff member alone.
 *  5. A business that was not given the service is refused, with the code the app acts on.
 *  6. The platform (super_admin) sees every business.
 *  7. A record can only be created in the signed-in business, whatever the request says.
 */
class TenancyContractTest extends TestCase
{
    use RefreshDatabase;

    /** @return array<string, array{0: string}> */
    public static function services(): array
    {
        return ['transport' => ['transport'], 'rental' => ['rental'], 'inventory' => ['inventory']];
    }

    // --------------------------------------------------------------- adapters

    private function business(string $service, string $label): User
    {
        return $this->givenServices(User::factory()->create([
            'name' => "{$label} Owner", 'role' => 'admin', 'is_active' => true,
        ]), $service);
    }

    private function staff(string $service, User $owner, string $label): User
    {
        [$role, $grants] = match ($service) {
            'transport' => ['manager', ['manage_vehicles_transport']],
            'rental' => ['manager', ['manage_properties_rental']],
            'inventory' => ['sales_officer', []],
        };

        return $this->givenServices(User::factory()->create([
            'name' => "{$label} Staff", 'role' => $role, 'permissions' => $grants,
            'is_active' => true, 'created_by' => $owner->id,
        ]), $service);
    }

    /** Create one record owned by $owner, text starting with $label. Returns its id. */
    private function record(string $service, User $owner, string $label): string|int
    {
        return match ($service) {
            'transport' => $this->insertVehicle($owner, $label),
            'rental' => Property::create(['owner_id' => $owner->id, 'name' => "{$label} plot"])->id,
            'inventory' => TenantContext::runAs($owner, fn () => DB::table('inventory_products')->insertGetId([
                'name' => "{$label} soda", 'sku' => "{$label}-SKU", 'cost_price' => 1, 'selling_price' => 2,
                'unit' => 'bottle', 'quantity' => 0, 'min_stock' => 0, 'status' => 'active',
                'created_at' => now(), 'updated_at' => now(),
            ])),
        };
    }

    private function insertVehicle(User $owner, string $label): string
    {
        $id = (string) \Illuminate\Support\Str::uuid();
        DB::table('devices')->insert([
            'id' => $id, 'created_by' => $owner->id, 'name' => "{$label} bike", 'type' => 'pikipiki',
            'plate_number' => "{$label}-PLATE", 'is_active' => 1, 'created_at' => now(), 'updated_at' => now(),
        ]);

        return $id;
    }

    private function listUri(string $service): string
    {
        return match ($service) {
            'transport' => '/api/admin/vehicles',
            'rental' => '/api/rental/properties',
            'inventory' => '/api/inventory/products',
        };
    }

    /** A request that changes or reads one record by id. @return array{0: string, 1: string, 2: array} */
    private function byId(string $service, string|int $id): array
    {
        return match ($service) {
            'transport' => ['PUT', "/api/admin/vehicles/{$id}", ['name' => 'Hijacked']],
            'rental' => ['GET', "/api/rental/properties/{$id}", []],
            'inventory' => ['PUT', "/api/inventory/products/{$id}", [
                'name' => 'Hijacked', 'cost_price' => 1, 'selling_price' => 2, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active',
            ]],
        };
    }

    /** A request that creates a record named with $label, and the list that shows it. @return array{0: string, 1: array, 2: string} */
    private function create(string $service, string $label): array
    {
        return match ($service) {
            'transport' => ['/api/admin/vehicles', ['name' => "{$label} new", 'type' => 'pikipiki', 'plate_number' => "{$label}-NEW"], '/api/admin/vehicles'],
            'rental' => ['/api/rental/properties', [
                'name' => "{$label} new", 'property_type' => 'apartment', 'region' => 'Dar', 'district' => 'Ilala',
                'address' => 'Street 1', 'billing_cycle' => 'monthly',
            ], '/api/rental/properties'],
            'inventory' => ['/api/inventory/customers', ['name' => "{$label} new", 'phone' => '0799' . random_int(100000, 999999)], '/api/inventory/customers'],
        };
    }

    // ---------------------------------------------------------------- helpers

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
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

    private function listText(User $as, string $service, ?string $uri = null): string
    {
        return $this->text($this->as($as, 'GET', $uri ?? $this->listUri($service))->assertOk());
    }

    // -------------------------------------------------------------- scenarios

    #[DataProvider('services')]
    public function test_a_business_sees_its_own_records_and_never_anothers(string $service): void
    {
        $alpha = $this->business($service, 'Alpha');
        $bravo = $this->business($service, 'Bravo');
        $this->record($service, $alpha, 'Alpha');
        $this->record($service, $bravo, 'Bravo');

        $this->assertStringContainsString('Alpha', $this->listText($alpha, $service));
        $this->assertStringNotContainsString('Bravo', $this->listText($alpha, $service), "{$service}: Alpha saw Bravo");
        $this->assertStringContainsString('Bravo', $this->listText($bravo, $service));
        $this->assertStringNotContainsString('Alpha', $this->listText($bravo, $service), "{$service}: Bravo saw Alpha");
    }

    #[DataProvider('services')]
    public function test_staff_see_what_their_business_sees(string $service): void
    {
        $alpha = $this->business($service, 'Alpha');
        $bravo = $this->business($service, 'Bravo');
        $this->record($service, $alpha, 'Alpha');
        $this->record($service, $bravo, 'Bravo');

        $staff = $this->staff($service, $alpha, 'Alpha');

        $text = $this->listText($staff, $service);
        $this->assertStringContainsString('Alpha', $text, "{$service}: staff see their business's records");
        $this->assertStringNotContainsString('Bravo', $text, "{$service}: staff must not see another business");
    }

    #[DataProvider('services')]
    public function test_another_business_reaching_a_record_by_id_gets_not_found_and_changes_nothing(string $service): void
    {
        $alpha = $this->business($service, 'Alpha');
        $bravo = $this->business($service, 'Bravo');
        $id = $this->record($service, $alpha, 'Alpha');

        [$method, $uri, $body] = $this->byId($service, $id);
        $this->as($bravo, $method, $uri, $body)->assertNotFound();

        // The owner still reaches it, and it is unchanged.
        $this->assertStringContainsString('Alpha', $this->listText($alpha, $service));
        $this->assertStringNotContainsString('Hijacked', $this->listText($alpha, $service));
    }

    #[DataProvider('services')]
    public function test_a_record_a_staff_member_creates_belongs_to_the_business(string $service): void
    {
        $alpha = $this->business($service, 'Alpha');
        $bravo = $this->business($service, 'Bravo');
        $staff = $this->staff($service, $alpha, 'Alpha');

        [$uri, $body, $listUri] = $this->create($service, 'Alpha');
        $this->as($staff, 'POST', $uri, $body)->assertCreated();

        $this->assertStringContainsString('Alpha new', $this->listText($alpha, $service, $listUri), "{$service}: the owner sees what their staff created");
        $this->assertStringContainsString('Alpha new', $this->listText($staff, $service, $listUri));
        $this->assertStringNotContainsString('Alpha new', $this->listText($bravo, $service, $listUri), "{$service}: another business must not");
    }

    #[DataProvider('services')]
    public function test_a_business_without_the_service_is_refused_with_the_code_the_app_acts_on(string $service): void
    {
        $others = array_values(array_diff(['transport', 'rental', 'inventory'], [$service]));
        $business = $this->business($others[0], 'Gamma');

        $this->as($business, 'GET', $this->listUri($service))
            ->assertForbidden()
            ->assertJsonPath('code', 'service_not_assigned');

        // Their own staff do not get round it either.
        $staff = $this->staff($others[0], $business, 'Gamma');
        $this->as($staff, 'GET', $this->listUri($service))->assertForbidden();
    }

    #[DataProvider('services')]
    public function test_the_platform_sees_every_business_except_inside_their_stock(string $service): void
    {
        $alpha = $this->business($service, 'Alpha');
        $bravo = $this->business($service, 'Bravo');
        $this->record($service, $alpha, 'Alpha');
        $this->record($service, $bravo, 'Bravo');

        $super = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
        $text = $this->listText($super, $service);

        if ($service === 'inventory') {
            // Stock, sales and clients are a business's own: the platform owner never reads them.
            $this->assertStringNotContainsString('Alpha', $text);
            $this->assertStringNotContainsString('Bravo', $text);

            return;
        }

        $this->assertStringContainsString('Alpha', $text);
        $this->assertStringContainsString('Bravo', $text);
    }

    #[DataProvider('services')]
    public function test_a_record_is_created_in_the_signed_in_business_whatever_the_request_says(string $service): void
    {
        $alpha = $this->business($service, 'Alpha');
        $bravo = $this->business($service, 'Bravo');

        [$uri, $body, $listUri] = $this->create($service, 'Bravo');
        // A hostile client names the other business as the owner.
        $body['owner_id'] = (string) $alpha->id;
        $body['created_by'] = (string) $alpha->id;
        $this->as($bravo, 'POST', $uri, $body)->assertCreated();

        $this->assertStringContainsString('Bravo new', $this->listText($bravo, $service, $listUri));
        $this->assertStringNotContainsString('Bravo new', $this->listText($alpha, $service, $listUri), "{$service}: the client chose the owner");
    }
}
