<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The owner of any business can change how an item is counted: a different label (pcs, pack, box...) at any time, and a different KIND of
 * measure (pieces, weight, volume: "it was kg, make it pieces") while no stock is held, so no stored quantity changes its meaning. The
 * selling units are rebuilt to fit, and what cannot be changed safely is refused with the reason.
 */
class ProductMeasureChangeTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;
    private User $owner;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0728000001']), 'inventory');
        Business::forOwnerId($this->owner->id)->update(['name' => 'Unit Shop']);
    }

    private function api(string $method, string $uri, array $body = [])
    {
        $token = $this->owner->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    private function rows(callable $fn)
    {
        return TenantContext::runAs($this->owner, fn () => TenantContext::runInService('inventory', $fn));
    }

    private function counted(string $unit = 'pcs', int $qty = 0): int
    {
        return $this->api('POST', '/api/inventory/products', ['name' => 'Item ' . ++$this->seq, 'sku' => 'IT' . $this->seq, 'quantity' => $qty, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 600, 'selling_price' => 1000, 'unit' => $unit, 'measure' => 'count'])->assertCreated()->json('data.id');
    }

    /** Rice by weight: stocked in grams, sold by the kg too. */
    private function weighed(int $grams = 0): int
    {
        return $this->api('POST', '/api/inventory/products', [
            'name' => 'Rice ' . ++$this->seq, 'sku' => 'RC' . $this->seq, 'quantity' => $grams, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 1.5, 'selling_price' => 2.2,
            'measure' => 'weight', 'unit' => 'g', 'units' => [['name' => 'kg', 'factor' => 1000, 'retail_price' => 2200]],
        ])->assertCreated()->json('data.id');
    }

    private function product(int $id): object
    {
        return $this->rows(fn () => DB::table('inventory_products')->where('id', $id)->first());
    }

    private function units(int $id): array
    {
        return $this->rows(fn () => DB::table('inventory_product_units')->where('product_id', $id)->orderBy('id')->get(['name', 'factor', 'is_base'])->map(fn ($u) => [$u->name, (int) $u->factor, (bool) $u->is_base])->all());
    }

    // ------------------------------------------------------------------ a different label

    public function test_a_counted_item_can_take_another_label_at_any_time_even_with_stock(): void
    {
        $id = $this->counted('pcs', 40);

        $this->api('PUT', "/api/inventory/products/{$id}", ['unit' => 'pack'])->assertOk();

        $p = $this->product($id);
        $this->assertSame(['pack', 40], [$p->unit, (int) $p->quantity], 'the stock is untouched');
        $this->assertSame([['pack', 1, true]], $this->units($id), 'the base selling unit follows the label');
    }

    // ------------------------------------------------------------------ kg -> something else

    public function test_an_item_by_weight_can_become_counted_while_no_stock_is_held(): void
    {
        $id = $this->weighed(0);
        $this->assertSame([['g', 1, true], ['kg', 1000, false]], $this->units($id));

        $this->api('PUT', "/api/inventory/products/{$id}", ['measure' => 'count', 'unit' => 'bag', 'cost_price' => 1500, 'selling_price' => 2200])->assertOk();

        $p = $this->product($id);
        $this->assertSame(['count', 'bag', 1, 0], [$p->measure, $p->unit, (int) $p->unit_factor, (int) $p->quantity]);
        $this->assertSame([['bag', 1, true]], $this->units($id), 'the kg selling unit no longer means anything and is gone');
        $this->assertEquals(2200, $p->selling_price);
    }

    public function test_a_counted_item_can_become_weighed_and_gets_its_kg_unit_with_the_price(): void
    {
        $id = $this->counted('pcs', 0);

        $this->api('PUT', "/api/inventory/products/{$id}", ['measure' => 'weight', 'cost_price' => 1.5, 'selling_price' => 2.2])->assertOk();

        $p = $this->product($id);
        $this->assertSame(['weight', 'g', 1], [$p->measure, $p->unit, (int) $p->unit_factor]);
        $this->assertSame([['g', 1, true], ['kg', 1000, false]], $this->units($id));
        $price = $this->rows(fn () => DB::table('inventory_product_prices as pr')->join('inventory_product_units as u', 'u.id', '=', 'pr.product_unit_id')->where('u.product_id', $id)->where('u.name', 'kg')->where('pr.tier', 'retail')->value('pr.price'));
        $this->assertEquals(2200, $price, 'a kg costs 1,000 grams');
    }

    public function test_by_volume_gets_litres(): void
    {
        $id = $this->counted('bottle', 0);

        $this->api('PUT', "/api/inventory/products/{$id}", ['measure' => 'volume', 'selling_price' => 3])->assertOk();

        $this->assertSame([['ml', 1, true], ['litre', 1000, false]], $this->units($id));
        $this->assertSame('ml', $this->product($id)->unit);
    }

    public function test_the_unit_of_weighed_goods_stays_grams_whatever_the_app_sends(): void
    {
        $id = $this->weighed(5000);

        $this->api('PUT', "/api/inventory/products/{$id}", ['unit' => 'kg', 'name' => 'Rice renamed'])->assertOk();

        $p = $this->product($id);
        $this->assertSame(['Rice renamed', 'g', 5000], [$p->name, $p->unit, (int) $p->quantity]);
    }

    // ------------------------------------------------------------------ what is refused

    public function test_the_measure_cannot_change_while_stock_is_held(): void
    {
        $id = $this->weighed(5000);

        $r = $this->api('PUT', "/api/inventory/products/{$id}", ['measure' => 'count', 'unit' => 'bag'])->assertStatus(422);

        $this->assertStringContainsString('stock', $r->json('message'));
        $p = $this->product($id);
        $this->assertSame(['weight', 'g', 5000], [$p->measure, $p->unit, (int) $p->quantity], 'nothing moved');
        $this->assertCount(2, $this->units($id));
    }

    public function test_a_size_or_colour_cannot_change_how_it_is_measured(): void
    {
        $id = $this->counted('pcs', 0);
        $this->rows(fn () => DB::table('inventory_products')->where('id', $id)->update(['family_id' => $id, 'variant_label' => 'M']));

        $this->api('PUT', "/api/inventory/products/{$id}", ['measure' => 'weight'])->assertStatus(422);

        $this->assertSame('count', $this->product($id)->measure);
    }

    public function test_a_selling_unit_already_used_on_a_sale_keeps_the_measure_as_it_is(): void
    {
        $id = $this->weighed(5000);
        $kg = $this->rows(fn () => DB::table('inventory_product_units')->where('product_id', $id)->where('name', 'kg')->value('id'));
        $this->api('POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 11000, 'discount' => 0, 'tax' => 0, 'total' => 11000, 'paid_total' => 11000,
            'items' => [['product_id' => $id, 'quantity' => 5, 'unit_id' => $kg, 'unit_price' => 2200, 'unit_cost_snapshot' => 1.5]],
        ])->assertCreated();
        $this->assertSame(0, (int) $this->product($id)->quantity, 'all five kilograms are sold');

        $this->api('PUT', "/api/inventory/products/{$id}", ['measure' => 'count', 'unit' => 'bag'])->assertStatus(422);

        $this->assertSame('weight', $this->product($id)->measure);
    }

    public function test_a_sold_out_item_whose_sales_used_only_its_base_unit_may_change(): void
    {
        $id = $this->counted('pcs', 3);
        $this->api('POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 3000, 'discount' => 0, 'tax' => 0, 'total' => 3000, 'paid_total' => 3000,
            'items' => [['product_id' => $id, 'quantity' => 3, 'unit_price' => 1000, 'unit_cost_snapshot' => 600]],
        ])->assertCreated();

        $this->api('PUT', "/api/inventory/products/{$id}", ['measure' => 'weight', 'selling_price' => 2])->assertOk();

        $this->assertSame('weight', $this->product($id)->measure);
        $line = $this->rows(fn () => DB::table('inventory_sale_items')->where('product_id', $id)->first());
        $this->assertSame(3, (int) $line->quantity, 'what was sold is on record as it was');
    }

    public function test_changing_nothing_about_the_measure_is_never_refused_for_stock(): void
    {
        $id = $this->weighed(5000);

        $this->api('PUT', "/api/inventory/products/{$id}", ['measure' => 'weight', 'selling_price' => 2.5])->assertOk();

        $this->assertSame(5000, (int) $this->product($id)->quantity);
    }
}
