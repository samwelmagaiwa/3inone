<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\ServiceBranch;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A branch says where it is: region, district, ward and street or village (chosen from the Tanzania locations, or typed), with the free
 * address (building, landmark) kept as before. All of it is optional, so a branch made without a place still works.
 */
class BranchPlaceTest extends TestCase
{
    use RefreshDatabase;

    private User $shop;

    protected function setUp(): void
    {
        parent::setUp();
        ServiceBranch::forget();
        $this->shop = $this->givenServices(User::factory()->create(['name' => 'Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0724000001']), 'inventory');
        Business::forOwnerId($this->shop->id)->update(['name' => 'Mama Shop']);
    }

    private function api(User $as, string $method, string $uri, array $body = [], string $service = 'inventory')
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        ServiceBranch::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', $service)->json($method, $uri, $body);
    }

    public function test_a_shop_branch_keeps_its_whole_place(): void
    {
        $id = $this->api($this->shop, 'POST', '/api/inventory/branches', [
            'name' => 'Kariakoo', 'region' => 'Dar es Salaam', 'district' => 'Ilala', 'ward' => 'Kariakoo', 'street' => 'Mtaa wa Msimbazi', 'address' => 'Karibu na soko', 'phone' => '0711000111',
        ])->assertCreated()->json('data.id');

        $row = collect($this->api($this->shop, 'GET', '/api/inventory/branches')->assertOk()->json('data'))->firstWhere('id', $id);

        $this->assertSame(['Dar es Salaam', 'Ilala', 'Kariakoo', 'Mtaa wa Msimbazi', 'Karibu na soko'], [$row['region'], $row['district'], $row['ward'], $row['street'], $row['address']]);
    }

    public function test_a_branch_with_no_place_still_works_and_shows_empty_parts(): void
    {
        $id = $this->api($this->shop, 'POST', '/api/inventory/branches', ['name' => 'Plain'])->assertCreated()->json('data.id');

        $row = collect($this->api($this->shop, 'GET', '/api/inventory/branches')->json('data'))->firstWhere('id', $id);

        $this->assertSame([null, null, null, null], [$row['region'], $row['district'], $row['ward'], $row['street']]);
    }

    public function test_the_place_can_be_changed_and_cleared(): void
    {
        $id = $this->api($this->shop, 'POST', '/api/inventory/branches', ['name' => 'Kariakoo', 'region' => 'Dar es Salaam', 'district' => 'Ilala'])->assertCreated()->json('data.id');

        $this->api($this->shop, 'PUT', "/api/inventory/branches/{$id}", ['district' => 'Kinondoni', 'ward' => 'Mikocheni'])->assertOk();
        $row = collect($this->api($this->shop, 'GET', '/api/inventory/branches')->json('data'))->firstWhere('id', $id);
        $this->assertSame(['Dar es Salaam', 'Kinondoni', 'Mikocheni'], [$row['region'], $row['district'], $row['ward']], 'only what was sent changed');

        $this->api($this->shop, 'PUT', "/api/inventory/branches/{$id}", ['ward' => ''])->assertOk();
        $row = collect($this->api($this->shop, 'GET', '/api/inventory/branches')->json('data'))->firstWhere('id', $id);
        $this->assertNull($row['ward'], 'an empty value clears it');
    }

    public function test_a_place_typed_by_hand_is_kept_as_typed_and_a_too_long_one_is_refused(): void
    {
        $id = $this->api($this->shop, 'POST', '/api/inventory/branches', ['name' => 'Remote', 'region' => 'Songwe', 'district' => 'Songwe', 'ward' => 'Kijiji kipya (kilichoandikwa kwa mkono)', 'street' => '  Kitongoji cha Mlima  '])->assertCreated()->json('data.id');
        $row = collect($this->api($this->shop, 'GET', '/api/inventory/branches')->json('data'))->firstWhere('id', $id);

        $this->assertSame('Kijiji kipya (kilichoandikwa kwa mkono)', $row['ward']);
        $this->assertSame('Kitongoji cha Mlima', $row['street'], 'spaces are trimmed');
        $this->api($this->shop, 'POST', '/api/inventory/branches', ['name' => 'Long', 'region' => str_repeat('x', 81)])->assertStatus(422);
    }

    public function test_the_branch_of_a_transport_or_rental_business_has_a_place_too(): void
    {
        $transport = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'transport');
        $created = $this->api($transport, 'POST', '/api/admin/branches', ['name' => 'Yard', 'region' => 'Mwanza', 'district' => 'Nyamagana', 'ward' => 'Pasiansi', 'street' => 'Isamilo'], 'transport')->assertCreated()->json('data');

        $this->assertSame(['Mwanza', 'Nyamagana', 'Pasiansi', 'Isamilo'], [$created['region'], $created['district'], $created['ward'], $created['street']]);

        $this->api($transport, 'PUT', '/api/admin/branches/' . $created['id'], ['ward' => 'Igoma'], 'transport')->assertOk()->assertJsonPath('data.ward', 'Igoma');
        $listed = $this->api($transport, 'GET', '/api/admin/branches', [], 'transport')->assertOk()->json('data.0');
        $this->assertSame(['Mwanza', 'Nyamagana', 'Igoma', 'Isamilo'], [$listed['region'], $listed['district'], $listed['ward'], $listed['street']]);
    }
}
