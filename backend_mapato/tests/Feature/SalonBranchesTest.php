<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** Branches: records carry their branch, figures can be of one branch, and a single-branch salon sees no change. */
class SalonBranchesTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function salon(string $name = 'Glow'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0724' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [], array $headers = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->withHeaders($headers)->json($method, $uri, $body);
    }

    private function sell(User $as, int $product, int $price, array $headers = [])
    {
        return $this->api($as, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => $price, 'discount' => 0, 'tax' => 0, 'total' => $price, 'paid_total' => $price,
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => $price]],
            'payments' => [['amount' => $price, 'method' => 'cash']],
        ], $headers)->assertCreated();
    }

    private function product(User $as): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => 'Braids', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 10000, 'duration_minutes' => 60])->assertCreated()->json('data.id');
    }

    public function test_figures_follow_the_chosen_branch(): void
    {
        $owner = $this->salon();
        $a = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Kariakoo'])->assertCreated()->json('data.id');
        $b = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Mikocheni'])->assertCreated()->json('data.id');
        $p = $this->product($owner);
        $this->sell($owner, $p, 10000, ['X-Branch' => (string) $a]);
        $this->sell($owner, $p, 10000, ['X-Branch' => (string) $a]);
        $this->sell($owner, $p, 5000, ['X-Branch' => (string) $b]);

        $this->api($owner, 'POST', '/api/inventory/expenses', ['description' => 'Rent', 'category' => 'rent', 'amount' => 3000, 'expense_date' => now()->toDateString()], ['X-Branch' => (string) $b])->assertSuccessful();

        $all = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?period=today')->assertOk()->json('data');
        $this->assertEquals(25000, $all['revenue']['total'] ?? $all['revenue'] ?? null);

        $ka = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?period=today', [], ['X-Branch' => (string) $a])->assertOk()->json('data');
        $this->assertEquals(20000, $ka['revenue']['total'] ?? $ka['revenue']);

        $mi = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?period=today', [], ['X-Branch' => (string) $b])->assertOk()->json('data');
        $this->assertEquals(5000, $mi['revenue']['total'] ?? $mi['revenue']);
    }

    public function test_no_branches_means_nothing_changes_and_bad_header_is_ignored(): void
    {
        $owner = $this->salon();
        $p = $this->product($owner);
        $this->sell($owner, $p, 10000, ['X-Branch' => '999']);
        $this->assertNull(\DB::table('inventory_sales')->value('branch_id'));
        $d = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?period=today', [], ['X-Branch' => '999'])->assertOk()->json('data');
        $this->assertEquals(10000, $d['revenue']['total'] ?? $d['revenue']);
    }

    public function test_only_managers_change_branches_and_used_ones_cannot_be_deleted(): void
    {
        $owner = $this->salon();
        $stylist = $this->givenServices(User::factory()->create(['name' => 'S', 'role' => 'hair_stylist', 'is_active' => true, 'created_by' => $owner->id]), 'salon');
        $this->api($stylist, 'POST', '/api/inventory/salon/branches', ['name' => 'X'])->assertForbidden();
        $id = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertCreated()->json('data.id');
        $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertStatus(422);
        $this->api($stylist, 'GET', '/api/inventory/salon/branches')->assertOk()->assertJsonCount(1, 'data');
        $this->sell($owner, $this->product($owner), 1000, ['X-Branch' => (string) $id]);
        $this->api($owner, 'DELETE', "/api/inventory/salon/branches/{$id}")->assertStatus(422);
        $this->api($owner, 'PUT', "/api/inventory/salon/branches/{$id}", ['active' => false])->assertOk();
        $this->api($stylist, 'GET', '/api/inventory/salon/branches')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_another_salon_never_sees_these_branches(): void
    {
        $one = $this->salon('One');
        $two = $this->salon('Two');
        $this->api($one, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertCreated();
        $this->api($two, 'GET', '/api/inventory/salon/branches')->assertOk()->assertJsonCount(0, 'data');
        $this->api($two, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertCreated();
    }
}
