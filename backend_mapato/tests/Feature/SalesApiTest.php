<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class SalesApiTest extends TestCase
{
    use RefreshDatabase;

    private int $productId;
    private int $customerId;

    protected function setUp(): void
    {
        parent::setUp();

        $this->productId = DB::table('inventory_products')->insertGetId([
            'name' => 'Kili Water 1.5L',
            'sku' => 'WATER-15L-' . uniqid(),
            'cost_price' => 700,
            'selling_price' => 1000,
            'unit' => 'bottle',
            'quantity' => 100,
            'min_stock' => 10,
            'status' => 'active',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->customerId = DB::table('inventory_customers')->insertGetId([
            'name' => 'Happy Tails',
            'phone' => '0788123456',
            'address' => 'Mikocheni B',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function test_can_create_cash_sale_and_eager_load_in_index(): void
    {
        $payload = [
            'customer_id' => $this->customerId,
            'payment_status' => 'paid',
            'subtotal' => 50000,
            'discount' => 0,
            'tax' => 0,
            'total' => 50000,
            'paid_total' => 50000,
            'items' => [
                [
                    'product_id' => $this->productId,
                    'quantity' => 50,
                    'unit_price' => 1000,
                    'unit_cost_snapshot' => 700,
                ],
            ],
            'payments' => [
                [
                    'amount' => 50000,
                    'method' => 'cash',
                    'paid_at' => now()->toIso8601String(),
                ],
            ],
        ];

        $controller = app(\App\Http\Controllers\API\Inventory\SalesController::class);
        // Sales lists are scoped to the caller, so act as a privileged user.
        $admin = User::factory()->create(['role' => 'admin']);
        $request = \Illuminate\Http\Request::create('/api/inventory/sales', 'POST', $payload);
        $request->setUserResolver(fn () => $admin);
        $response = $controller->store($request);

        $this->assertEquals(201, $response->getStatusCode());
        $responseData = json_decode($response->getContent(), true);

        $this->assertArrayHasKey('data', $responseData);
        $this->assertNotNull($responseData['data']['number']);
        $saleId = $responseData['data']['id'];

        // Verify product stock deduction
        $productQty = DB::table('inventory_products')->where('id', $this->productId)->value('quantity');
        $this->assertEquals(50, (int) $productQty);

        // Test Index with Eager Loading
        $indexRequest = \Illuminate\Http\Request::create('/api/inventory/sales', 'GET');
        $indexRequest->setUserResolver(fn () => $admin);
        $indexResponse = $controller->index($indexRequest);

        $this->assertEquals(200, $indexResponse->getStatusCode());
        $indexData = json_decode($indexResponse->getContent(), true);

        $this->assertNotEmpty($indexData['data']);
        $firstSale = $indexData['data'][0];

        $this->assertEquals('Happy Tails', $firstSale['customer_name']);
        $this->assertNotEmpty($firstSale['items']);
        $this->assertEquals('Kili Water 1.5L', $firstSale['items'][0]['product_name']);
        $this->assertEquals(50, $firstSale['items'][0]['quantity']);

        // Test Show endpoint
        $showResponse = $controller->show($saleId);
        $this->assertEquals(200, $showResponse->getStatusCode());
        $showData = json_decode($showResponse->getContent(), true);

        $this->assertEquals('Happy Tails', $showData['data']['customer_name']);
        $this->assertEquals(50000, $showData['data']['total']);
        $this->assertNotEmpty($showData['data']['payments']);
    }

    private function checkout(array $items, ?User $user = null): \Illuminate\Http\JsonResponse
    {
        $total = array_sum(array_map(fn ($i) => $i['quantity'] * 1000, $items));
        $request = \Illuminate\Http\Request::create('/api/inventory/sales', 'POST', [
            'payment_status' => 'paid',
            'subtotal' => $total,
            'total' => $total,
            'paid_total' => $total,
            'items' => array_map(fn ($i) => $i + ['unit_price' => 1000], $items),
        ]);
        $request->setUserResolver(fn () => $user ?? User::factory()->create(['role' => 'admin']));

        return app(\App\Http\Controllers\API\Inventory\SalesController::class)->store($request);
    }

    public function test_cannot_sell_more_than_is_in_stock(): void
    {
        $response = $this->checkout([['product_id' => $this->productId, 'quantity' => 300]]);

        $this->assertEquals(422, $response->getStatusCode());
        $body = json_decode($response->getContent(), true);
        $this->assertEquals('insufficient_stock', $body['code']);
        $this->assertStringContainsString('Kili Water 1.5L', $body['message']);
        $this->assertEquals(100, $body['errors']['items'][0]['available']);
        $this->assertEquals(300, $body['errors']['items'][0]['requested']);

        // Nothing was written: no sale, and the stock is untouched.
        $this->assertEquals(0, DB::table('inventory_sales')->count());
        $this->assertEquals(0, DB::table('inventory_sale_items')->count());
        $this->assertEquals(100, (int) DB::table('inventory_products')->where('id', $this->productId)->value('quantity'));
    }

    public function test_stock_is_checked_across_all_lines_of_the_same_product(): void
    {
        // 60 + 60 is more than the 100 in stock, even though each line alone would fit.
        $response = $this->checkout([
            ['product_id' => $this->productId, 'quantity' => 60],
            ['product_id' => $this->productId, 'quantity' => 60],
        ]);

        $this->assertEquals(422, $response->getStatusCode());
        $this->assertEquals(0, DB::table('inventory_sales')->count());
        $this->assertEquals(100, (int) DB::table('inventory_products')->where('id', $this->productId)->value('quantity'));
    }

    public function test_can_sell_exactly_what_is_in_stock(): void
    {
        $response = $this->checkout([['product_id' => $this->productId, 'quantity' => 100]]);

        $this->assertEquals(201, $response->getStatusCode());
        $this->assertEquals(0, (int) DB::table('inventory_products')->where('id', $this->productId)->value('quantity'));
    }

    public function test_debt_sale_requires_customer_and_creates_reminder(): void
    {
        $payload = [
            'payment_status' => 'debt',
            'subtotal' => 30000,
            'total' => 30000,
            'paid_total' => 0,
            'items' => [
                [
                    'product_id' => $this->productId,
                    'quantity' => 30,
                    'unit_price' => 1000,
                    'unit_cost_snapshot' => 700,
                ],
            ],
        ];

        $controller = app(\App\Http\Controllers\API\Inventory\SalesController::class);

        // Missing customer for debt -> 422
        $requestFail = \Illuminate\Http\Request::create('/api/inventory/sales', 'POST', $payload);
        $resFail = $controller->store($requestFail);
        $this->assertEquals(422, $resFail->getStatusCode());

        // With customer -> succeeds and creates reminder
        $payload['customer_id'] = $this->customerId;
        $requestOk = \Illuminate\Http\Request::create('/api/inventory/sales', 'POST', $payload);
        $resOk = $controller->store($requestOk);

        $this->assertEquals(201, $resOk->getStatusCode());
        $resData = json_decode($resOk->getContent(), true);
        $saleId = $resData['data']['id'];

        $reminder = DB::table('inventory_reminders')
            ->where('related_id', $saleId)
            ->where('type', 'payment_due')
            ->first();

        $this->assertNotNull($reminder);
        $this->assertEquals('open', $reminder->status);
    }
}
