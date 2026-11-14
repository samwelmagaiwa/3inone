<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * A client asks for a discount after the sale (the goods did not satisfy them). It comes off the sale's total with a reason; what is still
 * owed shrinks first, and what was already paid beyond the new total goes back as a refund. The owner's right (the one that deletes a sale).
 */
class SaleDiscountAfterTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');
    }

    private function api(string $method, string $uri, array $body = [], ?User $as = null)
    {
        $token = ($as ?? $this->owner)->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function row(string $table, int $id): object
    {
        return TenantContext::runAs($this->owner, fn () => DB::table($table)->where('id', $id)->first());
    }

    /** A sale of 10 bottles at 1,000 (cost 700), paid [$paid] of the 10,000. Returns the sale id. */
    private function sale(float $paid, string $status): int
    {
        $p = $this->api('POST', '/api/inventory/products', ['name' => 'Cola', 'unit' => 'bottle', 'quantity' => 100, 'min_stock' => 5, 'status' => 'active', 'cost_price' => 700, 'selling_price' => 1000])->assertCreated()->json('data.id');
        $customer = $this->api('POST', '/api/inventory/customers', ['name' => 'Asha', 'phone' => '0754111222'])->assertCreated()->json('data.id');

        return $this->api('POST', '/api/inventory/sales', [
            'customer_id' => $customer, 'payment_status' => $status, 'subtotal' => 10000, 'discount' => 0, 'tax' => 0, 'total' => 10000, 'paid_total' => $paid,
            'payments' => $paid > 0 ? [['amount' => $paid, 'method' => 'cash']] : [],
            'items' => [['product_id' => $p, 'quantity' => 10, 'unit_price' => 1000]],
        ])->assertCreated()->json('data.id');
    }

    public function test_a_paid_sale_gives_the_difference_back_as_a_refund(): void
    {
        $id = $this->sale(10000, 'paid');

        $r = $this->api('POST', "/api/inventory/sales/{$id}/discount", ['amount' => 2000, 'reason' => 'Goods not as good as shown'])->assertOk()->json('data');

        $this->assertEquals(8000, $r['new_total']);
        $this->assertEquals(2000, $r['refund']);
        $this->assertSame('paid', $r['payment_status']);
        $sale = $this->row('inventory_sales', $id);
        $this->assertEquals(2000, $sale->discount);
        $this->assertEquals(8000, $sale->total);
        $this->assertEquals(8000, $sale->paid_total);
        $this->assertSame('Goods not as good as shown', $sale->discount_reason);
        $net = TenantContext::runAs($this->owner, fn () => (float) DB::table('inventory_sale_payments')->where('sale_id', $id)->sum('amount'));
        $this->assertEquals(8000, $net, 'the cash taken is net of what was given back');
    }

    public function test_a_sale_paid_later_just_owes_less(): void
    {
        $id = $this->sale(0, 'debt');

        $r = $this->api('POST', "/api/inventory/sales/{$id}/discount", ['amount' => 3000, 'reason' => 'Damaged boxes'])->assertOk()->json('data');

        $this->assertEquals(7000, $r['new_total']);
        $this->assertEquals(0, $r['refund']);
        $this->assertEquals(7000, $r['balance']);
        $this->assertSame('debt', $r['payment_status']);
        $this->assertSame(0, TenantContext::runAs($this->owner, fn () => DB::table('inventory_sale_payments')->where('sale_id', $id)->where('amount', '<', 0)->count()));
    }

    public function test_a_part_paid_sale_takes_the_discount_off_what_is_left_and_can_become_paid(): void
    {
        $id = $this->sale(3000, 'partial');

        $first = $this->api('POST', "/api/inventory/sales/{$id}/discount", ['amount' => 4000, 'reason' => 'Late delivery'])->assertOk()->json('data');
        $this->assertEquals(6000, $first['new_total']);
        $this->assertEquals(0, $first['refund']);
        $this->assertEquals(3000, $first['balance']);
        $this->assertSame('partial', $first['payment_status']);

        // another discount that covers all that is still owed settles the sale; both reasons are kept
        $second = $this->api('POST', "/api/inventory/sales/{$id}/discount", ['amount' => 3000, 'reason' => 'Goodwill'])->assertOk()->json('data');
        $this->assertEquals(3000, $second['new_total']);
        $this->assertEquals(0, $second['refund']);
        $this->assertSame('paid', $second['payment_status']);
        $this->assertSame('Late delivery; Goodwill', $this->row('inventory_sales', $id)->discount_reason);
    }

    public function test_it_must_have_a_reason_a_sensible_amount_and_a_live_sale(): void
    {
        $id = $this->sale(10000, 'paid');

        $this->api('POST', "/api/inventory/sales/{$id}/discount", ['amount' => 500])->assertStatus(422);
        $this->api('POST', "/api/inventory/sales/{$id}/discount", ['amount' => 0, 'reason' => 'x y z'])->assertStatus(422);
        $this->api('POST', "/api/inventory/sales/{$id}/discount", ['amount' => 10001, 'reason' => 'too much'])->assertStatus(422);
        $this->assertEquals(10000, $this->row('inventory_sales', $id)->total, 'nothing changed');

        $this->api('POST', "/api/inventory/sales/{$id}/cancel", ['reason' => 'mistake'])->assertOk();
        $this->api('POST', "/api/inventory/sales/{$id}/discount", ['amount' => 500, 'reason' => 'after cancel'])->assertStatus(422);
    }

    public function test_the_accountant_cannot_but_the_owner_can_and_the_dashboard_profit_drops(): void
    {
        $id = $this->sale(10000, 'paid');
        $accountant = $this->givenServices(User::factory()->create(['role' => 'accountant', 'is_active' => true, 'created_by' => $this->owner->id]), 'inventory');

        $this->api('POST', "/api/inventory/sales/{$id}/discount", ['amount' => 1000, 'reason' => 'pls'], $accountant)->assertForbidden();

        // revenue 10,000 - cost 7,000 = 3,000 before; 2,500 after a 500 discount
        $this->assertEquals(3000, $this->api('GET', '/api/inventory/kpis')->assertOk()->json('data.today.profit'));
        $this->api('POST', "/api/inventory/sales/{$id}/discount", ['amount' => 500, 'reason' => 'Small scratch'])->assertOk();
        $this->assertEquals(2500, $this->api('GET', '/api/inventory/kpis')->assertOk()->json('data.today.profit'));
    }

    public function test_the_sale_shows_its_discount_and_why(): void
    {
        $id = $this->sale(0, 'debt');
        $this->api('POST', "/api/inventory/sales/{$id}/discount", ['amount' => 1500, 'reason' => 'Short on weight'])->assertOk();

        $shown = $this->api('GET', "/api/inventory/sales/{$id}")->assertOk()->json('data');
        $this->assertEquals(1500, $shown['discount']);
        $this->assertSame('Short on weight', $shown['discount_reason']);
        $this->assertEquals(8500, $shown['total']);
    }
}
