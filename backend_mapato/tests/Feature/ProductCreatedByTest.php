<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * "Who created this product" is recorded by the server from the signed-in user, not typed or sent by the app.
 * The product page used to show a read-only "Created by" box; it no longer does, and these tests keep the
 * recording itself honest: the page can leave the field out and the creator is still on the record.
 */
class ProductCreatedByTest extends TestCase
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

    /** What the product page sends: no "created_by" anywhere in it. */
    private function product(array $overrides = [], ?User $as = null)
    {
        return $this->api('POST', '/api/inventory/products', array_merge([
            'name' => 'Soda', 'cost_price' => 500, 'selling_price' => 800, 'quantity' => 40, 'min_stock' => 5, 'status' => 'active',
        ], $overrides), $as);
    }

    /** Raw rows, read as a business (the tables are tenant-scoped). */
    private function rows(callable $fn, ?User $as = null)
    {
        return TenantContext::runAs($as ?? $this->owner, $fn);
    }

    private function productRow(int $id, ?User $as = null): object
    {
        return $this->rows(fn () => DB::table('inventory_products')->where('id', $id)->first(), $as);
    }

    public function test_a_product_records_who_created_it_although_the_page_sends_nothing_about_it(): void
    {
        $id = $this->product(['name' => 'Cola'])->assertCreated()->json('data.id');

        $this->assertSame($this->owner->id, $this->productRow($id)->created_by);
    }

    public function test_so_do_its_first_price_and_the_price_history(): void
    {
        $id = $this->product(['name' => 'Cola'])->assertCreated()->json('data.id');

        [$prices, $changes] = $this->rows(function () use ($id) {
            $unitIds = DB::table('inventory_product_units')->where('product_id', $id)->pluck('id');

            return [
                DB::table('inventory_product_prices')->whereIn('product_unit_id', $unitIds)->pluck('created_by')->all(),
                DB::table('inventory_price_changes')->whereIn('product_unit_id', $unitIds)->pluck('changed_by')->all(),
            ];
        });

        $this->assertNotEmpty($prices);
        $this->assertNotEmpty($changes);
        $this->assertSame([$this->owner->id], array_values(array_unique($prices)));
        $this->assertSame([$this->owner->id], array_values(array_unique($changes)));
    }

    public function test_the_request_cannot_name_someone_else_as_the_creator(): void
    {
        $someoneElse = User::factory()->create(['role' => 'admin', 'is_active' => true]);

        $id = $this->product(['name' => 'Cola', 'created_by' => $someoneElse->id])->assertCreated()->json('data.id');

        $this->assertSame($this->owner->id, $this->productRow($id)->created_by, 'the signed-in user, whatever the body says');
    }

    public function test_each_user_is_recorded_on_their_own_products(): void
    {
        $other = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');

        $mine = $this->product(['name' => 'Mine'])->assertCreated()->json('data.id');
        $theirs = $this->product(['name' => 'Theirs'], $other)->assertCreated()->json('data.id');

        $this->assertSame($this->owner->id, $this->productRow($mine)->created_by);
        $this->assertSame($other->id, $this->productRow($theirs, $other)->created_by);
    }

    public function test_every_size_or_colour_carries_the_creator_too(): void
    {
        $ids = $this->product([
            'name' => 'T-Shirt', 'sku' => 'TSHIRT',
            'variants' => [['label' => 'M / Red', 'quantity' => 10], ['label' => 'L / Red', 'quantity' => 6]],
        ])->assertCreated()->json('data.ids');

        $this->assertCount(2, $ids);
        foreach ($ids as $id) {
            $this->assertSame($this->owner->id, $this->productRow($id)->created_by, "variant {$id}");
        }
    }

    public function test_the_creator_is_still_in_what_the_api_returns(): void
    {
        $id = $this->product(['name' => 'Cola'])->assertCreated()->json('data.id');

        $listed = collect($this->api('GET', '/api/inventory/products')->assertOk()->json('data'))->firstWhere('id', $id);

        $this->assertNotNull($listed, 'the new product is in the list');
        $this->assertSame($this->owner->id, $listed['created_by']);
    }
}
