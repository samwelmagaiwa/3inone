<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Inventory\StockLedger;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Real HTTP coverage for Reports, Alerts, Daily cash, Dispatch and Returns -
 * the five areas that previously had only hand-reviewed logic, not an
 * executed test. Every request goes through Sanctum as a real admin user, so
 * the role_any middleware and validation are exercised, not just the
 * underlying queries.
 */
class InventoryDepotOperationsTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;
    private int $productId;
    private int $customerId;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = $this->actAsBusiness(
            $this->givenServices(User::factory()->create(['role' => 'admin']), 'inventory')
        );

        $this->productId = DB::table('inventory_products')->insertGetId([
            'name' => 'Test Soda 500ml',
            'sku' => 'OPS-SODA-' . uniqid(),
            'cost_price' => 500,
            'selling_price' => 800,
            'unit' => 'bottle',
            'quantity' => 0,
            'min_stock' => 5,
            'status' => 'active',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->customerId = DB::table('inventory_customers')->insertGetId([
            'name' => 'Test Duka',
            'phone' => '0711111111',
            'credit_limit' => 500000,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        app(StockLedger::class)->receive($this->productId, 100, 'OPS-BATCH', null, 500, 'seed');
    }

    private function actingAsAdmin(): self
    {
        $this->actingAs($this->admin, 'sanctum');

        return $this;
    }

    // ---------------------------------------------------------------- Reports

    public function test_reports_index_lists_all_twelve_reports(): void
    {
        $response = $this->actingAsAdmin()->getJson('/api/inventory/reports');

        $response->assertOk();
        $this->assertCount(12, $response->json('data'));
        $this->assertContains('daily_sales', array_column($response->json('data'), 'key'));
    }

    public function test_daily_sales_report_reflects_a_real_sale(): void
    {
        $this->postSaleOf(3, unitPrice: 800);

        $response = $this->actingAsAdmin()->getJson(
            '/api/inventory/reports/daily_sales?from=' . now()->toDateString()
            . '&to=' . now()->toDateString(),
        );

        $response->assertOk();
        $rows = $response->json('data.rows');
        $this->assertNotEmpty($rows);
        $this->assertSame(2400.0, (float) $rows[0]['total']);
    }

    public function test_stock_valuation_report_matches_batch_cost(): void
    {
        $response = $this->actingAsAdmin()->getJson('/api/inventory/reports/stock_valuation');

        $response->assertOk();
        $rows = $response->json('data.rows');
        $this->assertSame(100, (int) $rows[0]['quantity']);
        $this->assertSame(50000.0, (float) $rows[0]['value']); // 100 * 500
    }

    public function test_unknown_report_key_returns_404(): void
    {
        $this->actingAsAdmin()
            ->getJson('/api/inventory/reports/not_a_real_report')
            ->assertNotFound();
    }

    // ---------------------------------------------------------------- Alerts

    public function test_alerts_flag_low_stock_and_clear_once_restocked(): void
    {
        app(StockLedger::class)->issue($this->productId, 98, 'test', 'sale');

        $response = $this->actingAsAdmin()->getJson('/api/inventory/alerts');
        $response->assertOk();
        $types = array_column($response->json('data'), 'type');
        $this->assertContains('low_stock', $types);

        app(StockLedger::class)->receive($this->productId, 50, 'OPS-BATCH', null, 500, 'restock');

        $after = $this->actingAsAdmin()->getJson('/api/inventory/alerts');
        $this->assertNotContains('low_stock', array_column($after->json('data'), 'type'));
    }

    public function test_alerts_flag_customer_over_credit_limit(): void
    {
        DB::table('inventory_sales')->insert([
            'number' => 'OPS-S-1',
            'customer_id' => $this->customerId,
            'payment_status' => 'debt',
            'subtotal' => 600000,
            'total' => 600000,
            'paid_total' => 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $response = $this->actingAsAdmin()->getJson('/api/inventory/alerts');
        $response->assertOk();

        $overLimit = collect($response->json('data'))
            ->firstWhere('type', 'over_credit_limit');
        $this->assertNotNull($overLimit, 'expected an over_credit_limit alert');
        $this->assertSame('critical', $overLimit['severity']);
    }

    public function test_acknowledging_an_alert_removes_it_from_the_open_list(): void
    {
        app(StockLedger::class)->issue($this->productId, 98, 'test', 'sale');
        $this->actingAsAdmin()->getJson('/api/inventory/alerts'); // triggers rebuild

        $alertId = DB::table('inventory_alerts')->where('type', 'low_stock')->value('id');
        $this->assertNotNull($alertId);

        $this->actingAsAdmin()
            ->postJson("/api/inventory/alerts/{$alertId}/acknowledge")
            ->assertOk();

        $status = DB::table('inventory_alerts')->where('id', $alertId)->value('status');
        $this->assertSame('acknowledged', $status);
    }

    // ------------------------------------------------------------ Daily cash

    public function test_cash_session_lifecycle_open_expense_close(): void
    {
        $open = $this->actingAsAdmin()->postJson('/api/inventory/cash-sessions', [
            'opening_float' => 50000,
        ]);
        $open->assertCreated();
        $sessionId = $open->json('data.id');

        $this->actingAsAdmin()
            ->postJson("/api/inventory/cash-sessions/{$sessionId}/expenses", [
                'description' => 'Fuel',
                'amount' => 5000,
            ])
            ->assertCreated();

        $summary = $this->actingAsAdmin()->getJson("/api/inventory/cash-sessions/{$sessionId}");
        $summary->assertOk();
        // opening float only, since no cash sale payments were recorded today.
        $this->assertSame(45000.0, (float) $summary->json('data.computed_expected_cash'));

        $close = $this->actingAsAdmin()->postJson("/api/inventory/cash-sessions/{$sessionId}/close", [
            'counted_cash' => 45000,
        ]);
        $close->assertOk();
        $this->assertSame(0.0, (float) $close->json('data.difference'));
    }

    public function test_closing_a_session_with_an_unexplained_difference_is_rejected(): void
    {
        $open = $this->actingAsAdmin()->postJson('/api/inventory/cash-sessions', [
            'opening_float' => 50000,
        ]);
        $sessionId = $open->json('data.id');

        $this->actingAsAdmin()
            ->postJson("/api/inventory/cash-sessions/{$sessionId}/close", ['counted_cash' => 40000])
            ->assertStatus(422);

        $this->actingAsAdmin()
            ->postJson("/api/inventory/cash-sessions/{$sessionId}/close", [
                'counted_cash' => 40000,
                'difference_reason' => 'Gave change from a torn note',
            ])
            ->assertOk();
    }

    public function test_a_second_open_session_for_the_same_user_is_refused(): void
    {
        $this->actingAsAdmin()->postJson('/api/inventory/cash-sessions', ['opening_float' => 0])
            ->assertCreated();

        $this->actingAsAdmin()->postJson('/api/inventory/cash-sessions', ['opening_float' => 0])
            ->assertStatus(422);
    }

    public function test_customer_payment_settles_the_oldest_invoice_first(): void
    {
        $oldSaleId = DB::table('inventory_sales')->insertGetId([
            'number' => 'OPS-OLD', 'customer_id' => $this->customerId,
            'payment_status' => 'debt', 'subtotal' => 10000, 'total' => 10000,
            'paid_total' => 0, 'created_at' => now()->subDays(5), 'updated_at' => now(),
        ]);
        DB::table('inventory_sales')->insertGetId([
            'number' => 'OPS-NEW', 'customer_id' => $this->customerId,
            'payment_status' => 'debt', 'subtotal' => 10000, 'total' => 10000,
            'paid_total' => 0, 'created_at' => now(), 'updated_at' => now(),
        ]);

        $response = $this->actingAsAdmin()->postJson('/api/inventory/payments', [
            'customer_id' => $this->customerId,
            'amount' => 10000,
            'method' => 'cash',
        ]);

        $response->assertCreated();
        $this->assertSame($oldSaleId, $response->json('data.allocations.0.sale_id'));
        $this->assertSame('paid', DB::table('inventory_sales')->find($oldSaleId)->payment_status);
    }

    // ------------------------------------------------------------- Dispatch

    public function test_loading_a_vehicle_issues_stock_and_reconciling_returns_the_unsold_balance(): void
    {
        $load = $this->actingAsAdmin()->postJson('/api/inventory/dispatches', [
            'vehicle' => 'T 123 ABC',
            'route' => 'Kariakoo',
            'lines' => [
                ['product_id' => $this->productId, 'quantity' => 20, 'unit_price' => 1000],
            ],
        ]);
        $load->assertCreated();
        $dispatchId = $load->json('data.id');

        $this->assertSame(80, (int) DB::table('inventory_products')->find($this->productId)->quantity);

        $show = $this->actingAsAdmin()->getJson("/api/inventory/dispatches/{$dispatchId}");
        $lineId = $show->json('data.lines.0.id');

        $reconcile = $this->actingAsAdmin()->postJson(
            "/api/inventory/dispatches/{$dispatchId}/reconcile",
            [
                'cash_returned' => 15000,
                'lines' => [['line_id' => $lineId, 'returned_quantity' => 5]],
            ],
        );

        $reconcile->assertOk();
        // 15 sold at 1000 = 15000 expected; 15000 returned -> balanced.
        $this->assertSame(0.0, (float) $reconcile->json('data.difference'));
        // 5 unsold crates return to the depot: 80 + 5 = 85.
        $this->assertSame(85, (int) DB::table('inventory_products')->find($this->productId)->quantity);
    }

    public function test_dispatch_cannot_load_more_than_is_in_stock(): void
    {
        $this->actingAsAdmin()->postJson('/api/inventory/dispatches', [
            'lines' => [
                ['product_id' => $this->productId, 'quantity' => 999, 'unit_price' => 1000],
            ],
        ])->assertStatus(422);
    }

    // -------------------------------------------------------------- Returns

    public function test_approved_return_restocks_and_credits_the_sale(): void
    {
        $saleId = $this->postSaleOf(10, unitPrice: 800, returnResponse: false);

        $returnRes = $this->actingAsAdmin()->postJson('/api/inventory/returns', [
            'sale_id' => $saleId,
            'type' => 'return',
            'reason' => 'Wrong flavour delivered',
            'lines' => [
                ['product_id' => $this->productId, 'quantity' => 2, 'unit_price' => 800, 'restock' => true],
            ],
        ]);
        $returnRes->assertCreated();
        $returnId = $returnRes->json('data.id');

        $qtyBeforeApproval = DB::table('inventory_products')->find($this->productId)->quantity;

        // The requester may not approve their own return, so a second person in the same
        // business decides: a manager the owner created.
        $manager = $this->givenServices(
            User::factory()->create(['role' => 'manager', 'created_by' => $this->admin->id]),
            'inventory'
        );
        $this->actingAs($manager, 'sanctum')
            ->postJson("/api/inventory/returns/{$returnId}/decide", ['decision' => 'approved'])
            ->assertOk();

        $sale = DB::table('inventory_sales')->find($saleId);
        $this->assertSame(6400.0, (float) $sale->total); // 8000 sale - 2*800 refunded
        $qtyAfter = DB::table('inventory_products')->find($this->productId)->quantity;
        $this->assertSame($qtyBeforeApproval + 2, $qtyAfter);
    }

    public function test_return_cannot_exceed_what_the_sale_contained(): void
    {
        $saleId = $this->postSaleOf(3, unitPrice: 800, returnResponse: false);

        $this->actingAsAdmin()->postJson('/api/inventory/returns', [
            'sale_id' => $saleId,
            'type' => 'return',
            'lines' => [
                ['product_id' => $this->productId, 'quantity' => 5, 'unit_price' => 800],
            ],
        ])->assertStatus(422);
    }

    public function test_parked_sale_can_be_resumed(): void
    {
        $park = $this->actingAsAdmin()->postJson('/api/inventory/parked-sales', [
            'customer_id' => $this->customerId,
            'total' => 4000,
            'cart' => [['product_id' => $this->productId, 'quantity' => 5, 'unit_price' => 800]],
        ]);
        $park->assertCreated();
        $id = $park->json('data.id');

        $resumed = $this->actingAsAdmin()->postJson("/api/inventory/parked-sales/{$id}/resume");
        $resumed->assertOk();
        $this->assertSame('resumed', DB::table('inventory_parked_sales')->find($id)->status);

        // Once resumed it is no longer parked, so discarding it is refused -
        // there is nothing left in the "parked" queue to discard.
        $this->actingAsAdmin()
            ->deleteJson("/api/inventory/parked-sales/{$id}")
            ->assertNotFound();
    }

    public function test_parked_sale_can_be_discarded_without_resuming(): void
    {
        $park = $this->actingAsAdmin()->postJson('/api/inventory/parked-sales', [
            'customer_id' => $this->customerId,
            'total' => 4000,
            'cart' => [['product_id' => $this->productId, 'quantity' => 5, 'unit_price' => 800]],
        ]);
        $id = $park->json('data.id');

        $this->actingAsAdmin()
            ->deleteJson("/api/inventory/parked-sales/{$id}")
            ->assertOk();

        $this->assertSame('discarded', DB::table('inventory_parked_sales')->find($id)->status);
    }

    // --------------------------------------------------------------- helpers

    /**
     * Post a sale via the same endpoint the POS uses, so these tests exercise
     * the real FEFO + validation path rather than inserting rows directly.
     */
    private function postSaleOf(int $quantity, float $unitPrice, bool $returnResponse = false): int|\Illuminate\Testing\TestResponse
    {
        $total = $quantity * $unitPrice;
        $response = $this->actingAsAdmin()->postJson('/api/inventory/sales', [
            'payment_status' => 'paid',
            'subtotal' => $total,
            'total' => $total,
            'paid_total' => $total,
            'items' => [[
                'product_id' => $this->productId,
                'quantity' => $quantity,
                'unit_price' => $unitPrice,
                'unit_cost_snapshot' => 500,
            ]],
        ]);
        $response->assertCreated();

        return $returnResponse ? $response : (int) $response->json('data.id');
    }
}
