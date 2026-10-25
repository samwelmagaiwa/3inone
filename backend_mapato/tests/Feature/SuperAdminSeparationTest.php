<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The platform's super admin runs the platform; a business's products, sales and receipts stay private to that business. */
class SuperAdminSeparationTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function owner(string $name): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => 'admin', 'is_active' => true, 'phone_number' => '0729' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    public function test_a_super_admin_sees_no_product_sale_or_receipt_of_any_business_and_each_owner_sees_only_their_own(): void
    {
        $a = $this->owner('Business A');
        $b = $this->owner('Business B');
        $super = User::factory()->create(['name' => 'Super', 'role' => 'super_admin', 'is_active' => true, 'full_access' => true, 'phone_number' => '0729999999']);

        $pid = $this->api($a, 'POST', '/api/inventory/products', ['name' => 'Soda A', 'quantity' => 10, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 500, 'selling_price' => 1000])->assertCreated()->json('data.id');
        $this->api($a, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 1000, 'discount' => 0, 'tax' => 0, 'total' => 1000, 'paid_total' => 1000,
            'items' => [['product_id' => $pid, 'quantity' => 1, 'unit_price' => 1000]],
        ])->assertCreated();

        $this->assertCount(1, $this->api($a, 'GET', '/api/inventory/products')->json('data'));
        foreach (['products', 'sales'] as $list) {
            $this->assertCount(0, $this->api($b, 'GET', "/api/inventory/{$list}")->json('data') ?? [], "business B must not see A's {$list}");
            $this->assertCount(0, $this->api($super, 'GET', "/api/inventory/{$list}")->json('data') ?? [], "the super admin must not see A's {$list}");
        }
        $this->api($super, 'GET', "/api/inventory/products/{$pid}")->assertNotFound();
        $this->api($b, 'GET', "/api/inventory/products/{$pid}")->assertNotFound();
    }

    public function test_a_super_admin_without_a_business_is_not_shown_a_depot(): void
    {
        $super = User::factory()->create(['name' => 'Super', 'role' => 'super_admin', 'is_active' => true, 'full_access' => true, 'phone_number' => '0729999998']);

        $settings = $this->api($super, 'GET', '/api/inventory/settings')->assertOk()->json('data');

        $this->assertSame('retail', $settings['inventory_type']);
        $this->assertSame('0', $settings['use_crates'], 'no crates, no depot screens');
    }
}
