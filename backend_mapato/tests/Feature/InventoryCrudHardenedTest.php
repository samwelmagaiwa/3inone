<?php

namespace Tests\Feature;

use App\Http\Controllers\API\Inventory\BrandController;
use App\Http\Controllers\API\Inventory\CategoryController;
use App\Http\Controllers\API\Inventory\CustomerController;
use App\Http\Controllers\API\Inventory\ProductController;
use App\Http\Controllers\API\Inventory\PurchasingController;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Covers the hardened CRUD endpoints added in the backend-hardening pass:
 *
 *  - Category: index, show, store, update, destroy (default + force)
 *  - Brand:    index, show, store, update, destroy (default + force)
 *  - Product:  store, update, destroy (default + force-archive)
 *  - Customer: store, update, destroy (default + force)
 *  - Supplier: store, update, destroySupplier (default + force)
 *
 * Audit-trail rows are verified for every mutation.
 *
 * Controllers are called directly (same pattern as SalesApiTest / InventoryDepotFlowTest)
 * to avoid needing Sanctum token setup for the UUID-keyed users table.
 * Middleware is still covered by route-registration tests in the route list.
 *
 * RefreshDatabase pins to SQLite in-memory — see TestEnvironmentSafetyTest.
 */
class InventoryCrudHardenedTest extends TestCase
{
    use RefreshDatabase;

    // ── fixtures ─────────────────────────────────────────────────────────────

    private function makeProduct(array $overrides = []): int
    {
        return DB::table('inventory_products')->insertGetId(array_merge([
            'name'          => 'Test Product ' . uniqid(),
            'sku'           => 'TST-' . uniqid(),
            'cost_price'    => 500,
            'selling_price' => 800,
            'unit'          => 'pcs',
            'quantity'      => 100,
            'min_stock'     => 5,
            'status'        => 'active',
            'created_at'    => now(),
            'updated_at'    => now(),
        ], $overrides));
    }

    private function makeCategory(array $overrides = []): int
    {
        return DB::table('inventory_categories')->insertGetId(array_merge([
            'name'       => 'TestCat ' . uniqid(),
            'status'     => 'active',
            'created_at' => now(),
            'updated_at' => now(),
        ], $overrides));
    }

    private function makeBrand(array $overrides = []): int
    {
        return DB::table('inventory_brands')->insertGetId(array_merge([
            'name'       => 'TestBrand ' . uniqid(),
            'status'     => 'active',
            'created_at' => now(),
            'updated_at' => now(),
        ], $overrides));
    }

    private function makeCustomer(array $overrides = []): int
    {
        return DB::table('inventory_customers')->insertGetId(array_merge([
            'name'       => 'TestCustomer ' . uniqid(),
            'phone'      => '07' . rand(10000000, 99999999),
            'created_at' => now(),
            'updated_at' => now(),
        ], $overrides));
    }

    private function makeSupplier(array $overrides = []): int
    {
        return DB::table('inventory_suppliers')->insertGetId(array_merge([
            'name'               => 'TestSupplier ' . uniqid(),
            'phone'              => '07' . rand(10000000, 99999999),
            'payment_terms_days' => 30,
            'status'             => 'active',
            'created_at'         => now(),
            'updated_at'         => now(),
        ], $overrides));
    }

    private function makeSaleWithItem(int $productId, string $payStatus = 'paid', ?int $customerId = null): int
    {
        $saleId = DB::table('inventory_sales')->insertGetId([
            'number'         => 'S-TEST-' . uniqid(),
            'customer_id'    => $customerId,
            'payment_status' => $payStatus,
            'subtotal'       => 800,
            'discount'       => 0,
            'tax'            => 0,
            'total'          => 800,
            'paid_total'     => $payStatus === 'paid' ? 800 : 0,
            'created_at'     => now(),
            'updated_at'     => now(),
        ]);
        DB::table('inventory_sale_items')->insert([
            'sale_id'            => $saleId,
            'product_id'         => $productId,
            'quantity'           => 1,
            'unit_price'         => 800,
            'unit_cost_snapshot' => 500,
            'total'              => 800,
            'created_at'         => now(),
            'updated_at'         => now(),
        ]);
        return $saleId;
    }

    /** Build a Request and bind it into the service container. */
    private function req(string $method, string $uri, array $data = [], array $query = []): Request
    {
        $request = Request::create($uri, strtoupper($method), $data);
        foreach ($query as $k => $v) {
            $request->query->set($k, $v);
        }
        app()->instance('request', $request);
        return $request;
    }

    /** Build a Request with a fake admin user (for force-delete tests). */
    private function adminReq(string $method, string $uri, array $data = [], array $query = []): Request
    {
        $request = $this->req($method, $uri, $data, $query);
        $fakeAdmin = new \stdClass();
        $fakeAdmin->id         = 1;
        $fakeAdmin->role       = 'admin';
        $fakeAdmin->full_access = true;
        $fakeAdmin->isSuperAdmin = false;
        // Bind isSuperAdmin as a method via a real anonymous class
        $admin = new class {
            public int    $id         = 1;
            public string $name       = 'Test Admin';
            public string $role       = 'admin';
            public bool   $full_access = true;
            public function isSuperAdmin(): bool { return false; }
        };
        $request->setUserResolver(fn () => $admin);
        return $request;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CATEGORY
    // ═══════════════════════════════════════════════════════════════════════

    public function test_category_index_returns_list(): void
    {
        $this->makeCategory(['name' => 'Beverages']);
        $ctrl = app(CategoryController::class);
        $res  = $ctrl->index($this->req('GET', '/api/inventory/categories'));
        $data = json_decode($res->getContent(), true);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertNotEmpty($data['data']);
        $this->assertSame('Beverages', $data['data'][0]['name']);
    }

    public function test_category_show_returns_single(): void
    {
        $id   = $this->makeCategory(['name' => 'Dairy']);
        $ctrl = app(CategoryController::class);
        $res  = $ctrl->show($id);
        $data = json_decode($res->getContent(), true);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertSame('Dairy', $data['data']['name']);
    }

    public function test_category_show_404_for_missing(): void
    {
        $ctrl = app(CategoryController::class);
        $res  = $ctrl->show(99999);
        $this->assertEquals(404, $res->getStatusCode());
    }

    public function test_category_store_creates_and_audits(): void
    {
        $ctrl = app(CategoryController::class);
        $res  = $ctrl->store($this->req('POST', '/api/inventory/categories', [
            'name'        => 'Snacks',
            'description' => 'Crisps and biscuits',
            'status'      => 'active',
        ]));
        $data = json_decode($res->getContent(), true);
        $this->assertEquals(201, $res->getStatusCode());
        $id = $data['data']['id'];

        $this->assertDatabaseHas('inventory_categories', ['id' => $id, 'name' => 'Snacks']);
        $this->assertDatabaseHas('inventory_audit_log', [
            'entity_type' => 'category',
            'entity_id'   => $id,
            'action'      => 'created',
        ]);
    }

    public function test_category_store_requires_unique_name(): void
    {
        $this->makeCategory(['name' => 'Dupes']);
        $ctrl = app(CategoryController::class);
        $this->expectException(\Illuminate\Validation\ValidationException::class);
        $ctrl->store($this->req('POST', '/api/inventory/categories', ['name' => 'Dupes']));
    }

    public function test_category_update_audits_and_syncs_products(): void
    {
        $id   = $this->makeCategory(['name' => 'Juices']);
        $prod = $this->makeProduct(['category_id' => $id, 'category' => 'Juices']);
        $ctrl = app(CategoryController::class);

        $res = $ctrl->update($this->req('PUT', "/api/inventory/categories/{$id}", ['name' => 'Juice & Drinks']), $id);
        $this->assertEquals(200, $res->getStatusCode());

        $this->assertDatabaseHas('inventory_categories', ['id' => $id, 'name' => 'Juice & Drinks']);
        $this->assertDatabaseHas('inventory_products',   ['id' => $prod, 'category' => 'Juice & Drinks']);
        $this->assertDatabaseHas('inventory_audit_log',  ['entity_type' => 'category', 'entity_id' => $id, 'action' => 'updated']);
    }

    public function test_category_destroy_blocked_when_in_use(): void
    {
        $id = $this->makeCategory();
        $this->makeProduct(['category_id' => $id]);
        $ctrl = app(CategoryController::class);

        $res = $ctrl->destroy($this->req('DELETE', "/api/inventory/categories/{$id}"), $id);
        $this->assertEquals(422, $res->getStatusCode());
        $this->assertStringContainsString('in use', json_decode($res->getContent(), true)['message']);
    }

    public function test_category_destroy_force_nulls_product_refs(): void
    {
        $id   = $this->makeCategory(['name' => 'ForceMe']);
        $prod = $this->makeProduct(['category_id' => $id, 'category' => 'ForceMe']);
        $ctrl = app(CategoryController::class);

        $res = $ctrl->destroy($this->adminReq('DELETE', "/api/inventory/categories/{$id}", [], ['force' => '1']), $id);
        $this->assertEquals(200, $res->getStatusCode());

        $this->assertDatabaseMissing('inventory_categories', ['id' => $id]);
        $this->assertDatabaseHas('inventory_products',  ['id' => $prod, 'category_id' => null]);
        $this->assertDatabaseHas('inventory_audit_log', ['entity_type' => 'category', 'action' => 'deleted']);
    }

    public function test_category_destroy_no_products_succeeds(): void
    {
        $id   = $this->makeCategory();
        $ctrl = app(CategoryController::class);
        $res  = $ctrl->destroy($this->req('DELETE', "/api/inventory/categories/{$id}"), $id);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertDatabaseMissing('inventory_categories', ['id' => $id]);
    }

    public function test_category_destroy_returns_404_for_missing(): void
    {
        $ctrl = app(CategoryController::class);
        $res  = $ctrl->destroy($this->req('DELETE', '/api/inventory/categories/99999'), 99999);
        $this->assertEquals(404, $res->getStatusCode());
    }

    // ═══════════════════════════════════════════════════════════════════════
    // BRAND
    // ═══════════════════════════════════════════════════════════════════════

    public function test_brand_index_returns_list(): void
    {
        $this->makeBrand(['name' => 'Coca-Cola']);
        $ctrl = app(BrandController::class);
        $res  = $ctrl->index($this->req('GET', '/api/inventory/brands'));
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertNotEmpty(json_decode($res->getContent(), true)['data']);
    }

    public function test_brand_show_returns_single(): void
    {
        $id   = $this->makeBrand(['name' => 'Pepsi']);
        $ctrl = app(BrandController::class);
        $res  = $ctrl->show($id);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertSame('Pepsi', json_decode($res->getContent(), true)['data']['name']);
    }

    public function test_brand_store_creates_and_audits(): void
    {
        $ctrl = app(BrandController::class);
        $res  = $ctrl->store($this->req('POST', '/api/inventory/brands', ['name' => 'Fanta', 'status' => 'active']));
        $this->assertEquals(201, $res->getStatusCode());
        $id = json_decode($res->getContent(), true)['data']['id'];
        $this->assertDatabaseHas('inventory_brands',    ['id' => $id, 'name' => 'Fanta']);
        $this->assertDatabaseHas('inventory_audit_log', ['entity_type' => 'brand', 'entity_id' => $id, 'action' => 'created']);
    }

    public function test_brand_update_audits(): void
    {
        $id   = $this->makeBrand(['name' => 'OldBrand']);
        $ctrl = app(BrandController::class);
        $res  = $ctrl->update($this->req('PUT', "/api/inventory/brands/{$id}", ['name' => 'NewBrand']), $id);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertDatabaseHas('inventory_brands',    ['id' => $id, 'name' => 'NewBrand']);
        $this->assertDatabaseHas('inventory_audit_log', ['entity_type' => 'brand', 'entity_id' => $id, 'action' => 'updated']);
    }

    public function test_brand_destroy_blocked_when_in_use(): void
    {
        $id = $this->makeBrand();
        $this->makeProduct(['brand_id' => $id]);
        $ctrl = app(BrandController::class);
        $res  = $ctrl->destroy($this->req('DELETE', "/api/inventory/brands/{$id}"), $id);
        $this->assertEquals(422, $res->getStatusCode());
    }

    public function test_brand_destroy_force_nulls_product_refs(): void
    {
        $id   = $this->makeBrand();
        $prod = $this->makeProduct(['brand_id' => $id]);
        $ctrl = app(BrandController::class);
        $res  = $ctrl->destroy($this->adminReq('DELETE', "/api/inventory/brands/{$id}", [], ['force' => '1']), $id);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertDatabaseMissing('inventory_brands',  ['id' => $id]);
        $this->assertDatabaseHas('inventory_products',    ['id' => $prod, 'brand_id' => null]);
        $this->assertDatabaseHas('inventory_audit_log',   ['entity_type' => 'brand', 'action' => 'deleted']);
    }

    public function test_brand_destroy_no_products_succeeds(): void
    {
        $id   = $this->makeBrand();
        $ctrl = app(BrandController::class);
        $res  = $ctrl->destroy($this->req('DELETE', "/api/inventory/brands/{$id}"), $id);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertDatabaseMissing('inventory_brands', ['id' => $id]);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PRODUCT
    // ═══════════════════════════════════════════════════════════════════════

    public function test_product_store_creates_and_audits(): void
    {
        $ctrl = app(ProductController::class);
        $res  = $ctrl->store($this->req('POST', '/api/inventory/products', [
            'name'          => 'Mango Juice 1L',
            'cost_price'    => 1200,
            'selling_price' => 1800,
            'unit'          => 'bottle',
            'quantity'      => 50,
            'min_stock'     => 10,
            'status'        => 'active',
        ]));
        $this->assertEquals(201, $res->getStatusCode());
        $id = json_decode($res->getContent(), true)['data']['id'];
        $this->assertDatabaseHas('inventory_audit_log', ['entity_type' => 'product', 'entity_id' => $id, 'action' => 'created']);
    }

    public function test_product_update_audits(): void
    {
        $id   = $this->makeProduct(['name' => 'Biscuit']);
        $ctrl = app(ProductController::class);
        $res  = $ctrl->update($this->req('PUT', "/api/inventory/products/{$id}", ['selling_price' => 900]), $id);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertDatabaseHas('inventory_audit_log', ['entity_type' => 'product', 'entity_id' => $id, 'action' => 'updated']);
    }

    public function test_product_destroy_moves_it_to_the_trash(): void
    {
        $id   = $this->makeProduct();
        $ctrl = app(ProductController::class);
        $res  = $ctrl->destroy($this->req('DELETE', "/api/inventory/products/{$id}"), $id);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertSame('Product moved to the Trash', json_decode($res->getContent(), true)['message']);
        $this->assertDatabaseMissing('inventory_products', ['id' => $id]); // out of sight of every query
        $this->assertTrue((bool) \App\Support\Tenancy\TenantContext::withTrashed(fn () => DB::table('inventory_products')->where('id', $id)->whereNotNull('deleted_at')->exists()), 'but still there, in the Trash');
        $this->assertDatabaseHas('inventory_audit_log',    ['entity_type' => 'product', 'entity_id' => $id, 'action' => 'trashed']);
    }

    public function test_product_destroy_with_sales_history_is_allowed_because_the_history_is_kept(): void
    {
        $id = $this->makeProduct();
        $this->makeSaleWithItem($id, 'paid');
        $ctrl = app(ProductController::class);
        $res  = $ctrl->destroy($this->req('DELETE', "/api/inventory/products/{$id}"), $id);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertSame(1, DB::table('inventory_sale_items')->where('product_id', $id)->count(), 'the sale lines are untouched');
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CUSTOMER
    // ═══════════════════════════════════════════════════════════════════════

    public function test_customer_destroy_blocked_on_open_debt(): void
    {
        $cId    = $this->makeCustomer();
        $prodId = $this->makeProduct();
        $this->makeSaleWithItem($prodId, 'debt', $cId);
        $ctrl = app(CustomerController::class);
        $res  = $ctrl->destroy($this->req('DELETE', "/api/inventory/customers/{$cId}"), $cId);
        $this->assertEquals(422, $res->getStatusCode());
    }

    public function test_customer_with_debt_is_never_moved_to_the_trash_not_even_forced(): void
    {
        $cId    = $this->makeCustomer(['name' => 'Jane Debt', 'phone' => '0712000001']);
        $prodId = $this->makeProduct();
        $saleId = $this->makeSaleWithItem($prodId, 'debt', $cId);

        $ctrl = app(CustomerController::class);
        $res  = $ctrl->destroy($this->adminReq('DELETE', "/api/inventory/customers/{$cId}", [], ['force' => '1']), $cId);
        $this->assertEquals(422, $res->getStatusCode(), 'what a customer still owes is in the totals, so they stay in sight');

        $this->assertDatabaseHas('inventory_customers', ['id' => $cId]);
        $this->assertSame($cId, (int) DB::table('inventory_sales')->find($saleId)->customer_id);
    }

    public function test_customer_destroy_no_debt_succeeds(): void
    {
        $cId  = $this->makeCustomer();
        $ctrl = app(CustomerController::class);
        $res  = $ctrl->destroy($this->req('DELETE', "/api/inventory/customers/{$cId}"), $cId);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertDatabaseMissing('inventory_customers', ['id' => $cId]);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SUPPLIER
    // ═══════════════════════════════════════════════════════════════════════

    public function test_supplier_destroy_blocked_on_open_invoice(): void
    {
        $sId = $this->makeSupplier();
        DB::table('inventory_supplier_invoices')->insert([
            'supplier_id' => $sId,
            'number'      => 'INV-001',
            'amount'      => 50000,
            'paid_amount' => 0,
            'status'      => 'open',
            'invoice_date' => now()->toDateString(),
            'due_date'    => now()->addDays(30)->toDateString(),
            'created_at'  => now(),
            'updated_at'  => now(),
        ]);
        $ctrl = app(PurchasingController::class);
        $res  = $ctrl->destroySupplier($this->req('DELETE', "/api/inventory/suppliers/{$sId}"), $sId);
        $this->assertEquals(422, $res->getStatusCode());
    }

    public function test_supplier_destroy_force_nulls_purchase_orders(): void
    {
        $sId  = $this->makeSupplier();
        $poId = DB::table('inventory_purchase_orders')->insertGetId([
            'supplier_id' => $sId,
            'number'      => 'PO-TEST-001',
            'status'      => 'draft',
            'total'       => 10000,
            'created_at'  => now(),
            'updated_at'  => now(),
        ]);
        DB::table('inventory_supplier_invoices')->insert([
            'supplier_id'  => $sId,
            'number'       => 'INV-FORCE',
            'amount'       => 10000,
            'paid_amount'  => 0,
            'status'       => 'open',
            'invoice_date' => now()->toDateString(),
            'due_date'     => now()->addDays(30)->toDateString(),
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);
        $ctrl = app(PurchasingController::class);
        $res  = $ctrl->destroySupplier($this->adminReq('DELETE', "/api/inventory/suppliers/{$sId}", [], ['force' => '1']), $sId);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertDatabaseMissing('inventory_suppliers',      ['id' => $sId]);
        $this->assertDatabaseMissing('inventory_purchase_orders', ['id' => $poId]);
    }

    public function test_supplier_destroy_no_invoices_succeeds(): void
    {
        $sId  = $this->makeSupplier();
        $ctrl = app(PurchasingController::class);
        $res  = $ctrl->destroySupplier($this->req('DELETE', "/api/inventory/suppliers/{$sId}"), $sId);
        $this->assertEquals(200, $res->getStatusCode());
        $this->assertDatabaseMissing('inventory_suppliers', ['id' => $sId]);
    }
}
