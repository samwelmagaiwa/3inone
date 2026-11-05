<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Access\Modules;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Deleting a sale and taking goods back are the owner's. The accountant does not hold either right (the owner can switch them on); they
 * write a request with a comment instead, which the owner reads on that sale and decides.
 */
class SalesRightsTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function salon(): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => 'Glow Owner', 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0727' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => 'Glow']);

        return $owner;
    }

    private function accountant(User $owner): User
    {
        return $this->givenServices(User::factory()->create(['name' => 'Ivan', 'role' => 'accountant', 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    /** A sale of one service, made by the accountant. Returns [sale id, product id]. */
    private function sale(User $as, User $owner): array
    {
        $product = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Braids', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 40000, 'duration_minutes' => 60])->assertCreated()->json('data.id');
        $sale = $this->api($as, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 40000, 'discount' => 0, 'tax' => 0, 'total' => 40000, 'paid_total' => 40000,
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => 40000]],
        ])->assertCreated()->json('data.id');

        return [$sale, $product];
    }

    public function test_the_accountant_starts_without_deleting_sales_or_returning_goods_and_the_owner_has_both(): void
    {
        $owner = $this->salon();
        $ivan = $this->accountant($owner);

        $this->assertFalse($ivan->hasInventoryPermission('inv_cancel_sales'));
        $this->assertFalse($ivan->hasInventoryPermission('inv_return_sales'));
        $this->assertContains('inv_manage_sales', $ivan->effectiveInventoryPermissions(), 'the rest of sales management is kept');
        $this->assertTrue($owner->hasInventoryPermission('inv_cancel_sales'));
        $this->assertTrue($owner->hasInventoryPermission('inv_return_sales'));
    }

    public function test_the_accountant_cannot_delete_a_sale_but_the_owner_can(): void
    {
        $owner = $this->salon();
        $ivan = $this->accountant($owner);
        [$sale] = $this->sale($ivan, $owner);

        $this->api($ivan, 'POST', "/api/inventory/sales/{$sale}/cancel", ['reason' => 'wrong'])->assertForbidden();
        $this->api($owner, 'POST', "/api/inventory/sales/{$sale}/cancel", ['reason' => 'Ivan said it was a mistake'])->assertSuccessful();
    }

    public function test_the_accountant_asks_with_a_comment_and_the_owner_decides(): void
    {
        $owner = $this->salon();
        $ivan = $this->accountant($owner);
        [$sale, $product] = $this->sale($ivan, $owner);
        $lines = [['product_id' => $product, 'quantity' => 1, 'unit_price' => 40000, 'restock' => true]];

        // No comment, no request: the owner has to be told why.
        $this->api($ivan, 'POST', '/api/inventory/returns', ['sale_id' => $sale, 'type' => 'cancellation', 'lines' => $lines])->assertStatus(422);
        $made = $this->api($ivan, 'POST', '/api/inventory/returns', ['sale_id' => $sale, 'type' => 'cancellation', 'reason' => 'Customer paid twice, please delete', 'lines' => $lines]);
        $made->assertSuccessful();

        $pending = $this->api($owner, 'GET', '/api/inventory/returns?status=pending')->assertOk()->json('data');
        $this->assertCount(1, $pending);
        $this->assertSame('Customer paid twice, please delete', $pending[0]['reason']);
        $this->assertSame('cancellation', $pending[0]['type']);

        // The accountant cannot approve it (not their right, and not their own request either); the owner can.
        $this->api($ivan, 'POST', "/api/inventory/returns/{$pending[0]['id']}/decide", ['decision' => 'approved'])->assertForbidden();
        $this->api($owner, 'POST', "/api/inventory/returns/{$pending[0]['id']}/decide", ['decision' => 'approved'])->assertSuccessful();

        // Approving a request to delete a sale deletes it: that is how the owner, who works on the phone, does it after reading the comment.
        $this->assertNotNull(\Illuminate\Support\Facades\DB::table('inventory_sales')->where('id', $sale)->value('cancelled_at'));
        $this->assertSame('Customer paid twice, please delete', \Illuminate\Support\Facades\DB::table('inventory_sales')->where('id', $sale)->value('cancellation_reason'));
    }

    public function test_the_owner_can_switch_either_right_on_for_the_accountant(): void
    {
        $owner = $this->salon();
        $ivan = $this->accountant($owner);
        [$sale] = $this->sale($ivan, $owner);

        $state = collect(Modules::stateFor($ivan, ['salon']))->keyBy('key');
        $this->assertFalse($state['inv_cancel_sales']['on']);
        $this->assertFalse($state['inv_return_sales']['on']);
        $this->assertSame('Kufuta mauzo', $state['inv_cancel_sales']['sw']);

        $ivan->forceFill(['permissions' => ['inv_cancel_sales']])->save();
        $this->api($ivan, 'POST', "/api/inventory/sales/{$sale}/cancel", ['reason' => 'The owner allowed me'])->assertSuccessful();
    }

    public function test_someone_given_sales_management_by_hand_keeps_cancelling_and_returns(): void
    {
        $owner = $this->salon();
        $officer = $this->givenServices(User::factory()->create(['name' => 'Joyce', 'role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id, 'permissions' => ['inv_manage_sales']]), 'salon');

        $this->assertTrue($officer->hasInventoryPermission('inv_cancel_sales'));
        $this->assertContains('inv_return_sales', $officer->effectiveInventoryPermissions());
    }
}
