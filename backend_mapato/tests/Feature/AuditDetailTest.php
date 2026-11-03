<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The audit trail keeps what a change was: old next to new, for whoever did it, and hands it to the app as records. */
class AuditDetailTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function shop(): User
    {
        return $this->givenServices(User::factory()->create(['name' => 'Julius Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    public function test_a_settings_change_keeps_the_old_and_the_new_value_and_names_what_changed(): void
    {
        $owner = $this->shop();
        $this->api($owner, 'PUT', '/api/inventory/settings', ['depot_name' => 'First Name'])->assertOk();
        $this->api($owner, 'PUT', '/api/inventory/settings', ['depot_name' => 'Second Name', 'depot_phone' => '0700111222'])->assertOk();

        $rows = $this->api($owner, 'GET', '/api/inventory/audit-log?entity_type=settings')->assertOk()->json('data');

        $latest = $rows[0];
        $this->assertSame('updated', $latest['action']);
        $this->assertSame('First Name', $latest['before']['depot_name']);
        $this->assertSame('Second Name', $latest['after']['depot_name']);
        $this->assertSame('0700111222', $latest['after']['depot_phone']);
        $this->assertStringContainsString('depot_name', $latest['summary'], 'the row says what was changed');
        $this->assertSame((string) $owner->id, (string) $latest['user_id']);
        $this->assertSame('Julius Owner', $latest['user_name']);
    }

    public function test_the_before_and_after_come_as_records_not_as_json_text(): void
    {
        $owner = $this->shop();
        $id = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Soda', 'sku' => 'SOD1', 'quantity' => 5, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 100, 'selling_price' => 500])->assertCreated()->json('data.id');
        $this->api($owner, 'PUT', "/api/inventory/products/{$id}", ['selling_price' => 650])->assertOk();

        $rows = $this->api($owner, 'GET', "/api/inventory/audit-log?entity_type=product&entity_id={$id}")->assertOk()->json('data');

        $update = collect($rows)->firstWhere('action', 'updated');
        $this->assertIsArray($update['before']);
        $this->assertIsArray($update['after']);
        $this->assertEquals(500, $update['before']['selling_price']);
        $this->assertEquals(650, $update['after']['selling_price']);
    }

    public function test_one_persons_activity_can_be_asked_for_on_its_own(): void
    {
        $owner = $this->shop();
        $this->api($owner, 'PUT', '/api/inventory/settings', ['depot_name' => 'Mine'])->assertOk();

        $mine = $this->api($owner, 'GET', '/api/inventory/audit-log?user_id=' . $owner->id)->assertOk()->json('data');
        $nobody = $this->api($owner, 'GET', '/api/inventory/audit-log?user_id=999999')->assertOk()->json('data');

        $this->assertNotEmpty($mine);
        $this->assertSame([], $nobody);
    }
}
