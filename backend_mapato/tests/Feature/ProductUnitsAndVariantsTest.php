<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * One product page for every kind of business: a product is stocked in a base unit and can be SOLD in more
 * units (a crate of 24, a kilogram of 1,000 g), comes in sizes / colours as separate stock, and may carry a VAT
 * rate. Quantities are whole numbers everywhere -- goods by weight or volume are stocked in grams / millilitres.
 */
class ProductUnitsAndVariantsTest extends TestCase
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

    private function product(array $overrides = [], ?User $as = null)
    {
        return $this->api('POST', '/api/inventory/products', array_merge([
            'name' => 'Soda', 'cost_price' => 500, 'selling_price' => 800, 'quantity' => 40, 'min_stock' => 5, 'status' => 'active',
        ], $overrides), $as);
    }

    /** Read raw rows as a business (the tables are tenant-scoped). */
    private function rows(callable $fn, ?User $as = null)
    {
        return TenantContext::runAs($as ?? $this->owner, $fn);
    }

    private function units(int $productId, ?User $as = null): array
    {
        return $this->rows(fn () => DB::table('inventory_product_units')->where('product_id', $productId)->orderBy('id')->get()->all(), $as);
    }

    private function price(int $unitId, string $tier): ?float
    {
        $p = $this->rows(fn () => DB::table('inventory_product_prices')->where('product_unit_id', $unitId)->where('tier', $tier)->whereNull('customer_id')->value('price'));

        return $p === null ? null : (float) $p;
    }

    // ------------------------------------------------------------ selling units

    public function test_a_product_is_created_with_its_selling_units_and_their_prices(): void
    {
        $id = $this->product([
            'name' => 'Cola', 'unit' => 'bottle', 'selling_price' => 1000,
            'units' => [
                ['name' => 'crate', 'factor' => 24, 'retail_price' => 22000, 'wholesale_price' => 20000],
                ['name' => 'pack of 6', 'factor' => 6, 'retail_price' => 5800],
            ],
        ])->assertCreated()->json('data.id');

        $units = $this->units($id);
        $this->assertSame(['bottle', 'crate', 'pack of 6'], array_map(fn ($u) => $u->name, $units));
        $this->assertTrue((bool) $units[0]->is_base);
        $this->assertSame([24, 6], [(int) $units[1]->factor, (int) $units[2]->factor]);
        $this->assertSame(22000.0, $this->price($units[1]->id, 'retail'));
        $this->assertSame(20000.0, $this->price($units[1]->id, 'wholesale'));
        $this->assertSame(5800.0, $this->price($units[2]->id, 'retail'));
        $this->assertNull($this->price($units[2]->id, 'wholesale'), 'a price that was not given is not invented');

        // Every price written leaves its row in the change log.
        $this->assertSame(4, $this->rows(fn () => DB::table('inventory_price_changes')->count()), 'base price + three unit prices');
    }

    public function test_the_products_own_unit_can_carry_both_price_levels(): void
    {
        $retail = $this->product(['name' => 'Soap', 'selling_price' => 1500, 'other_price' => 1200])->assertCreated()->json('data.id');
        $unit = $this->units($retail)[0];
        $this->assertSame(1500.0, $this->price($unit->id, 'retail'), 'the price entered is at the product\'s own level (retail)');
        $this->assertSame(1200.0, $this->price($unit->id, 'wholesale'), 'other_price is the same unit at the other level');

        $wholesale = $this->product(['name' => 'Soap box', 'price_tier' => 'wholesale', 'selling_price' => 1200, 'other_price' => 1500])->assertCreated()->json('data.id');
        $unit = $this->units($wholesale)[0];
        $this->assertSame(1200.0, $this->price($unit->id, 'wholesale'));
        $this->assertSame(1500.0, $this->price($unit->id, 'retail'));

        $plain = $this->units($this->product(['name' => 'Plain'])->assertCreated()->json('data.id'))[0];
        $this->assertNull($this->price($plain->id, 'wholesale'), 'no other price given, none invented');
    }

    public function test_a_unit_may_not_reuse_the_base_units_name_or_another_units(): void
    {
        $this->product(['unit' => 'bottle', 'units' => [['name' => 'Bottle', 'factor' => 2]]])
            ->assertStatus(422)->assertJsonValidationErrors('units.0.name');
        $this->product(['units' => [['name' => 'crate', 'factor' => 24], ['name' => 'crate', 'factor' => 12]]])
            ->assertStatus(422);
        $this->assertSame(0, $this->rows(fn () => DB::table('inventory_products')->count()), 'nothing half-created');
    }

    // ----------------------------------------------------- weight and volume

    public function test_goods_by_weight_are_stocked_in_grams_and_sold_in_grams_or_kilograms(): void
    {
        $id = $this->product([
            'name' => 'Sugar', 'measure' => 'weight', 'quantity' => 50000, 'selling_price' => 2, 'cost_price' => 1.5,
            'units' => [['name' => 'kg', 'factor' => 1000, 'retail_price' => 2200, 'wholesale_price' => 2000]],
        ])->assertCreated()->json('data.id');

        $row = $this->rows(fn () => DB::table('inventory_products')->find($id));
        $this->assertSame('g', $row->unit, 'no unit given: grams for weighed goods');
        $this->assertSame('weight', $row->measure);
        $this->assertSame(50000, (int) $row->quantity, '50 kg = 50,000 g, a whole number');
        $this->assertSame(['g', 'kg'], array_map(fn ($u) => $u->name, $this->units($id)));
    }

    public function test_goods_by_volume_default_to_millilitres(): void
    {
        $id = $this->product(['name' => 'Cooking oil', 'measure' => 'volume', 'quantity' => 20000, 'units' => [['name' => 'litre', 'factor' => 1000]]])
            ->assertCreated()->json('data.id');

        $this->assertSame('ml', $this->rows(fn () => DB::table('inventory_products')->find($id))->unit);
    }

    public function test_quantities_are_never_fractions(): void
    {
        $this->product(['quantity' => 2.5])->assertStatus(422)->assertJsonValidationErrors('quantity');
        $this->product(['min_stock' => 0.5])->assertStatus(422)->assertJsonValidationErrors('min_stock');
        $this->product(['units' => [['name' => 'kg', 'factor' => 1.5]]])->assertStatus(422);

        $id = $this->product()->assertCreated()->json('data.id');
        $this->api('PUT', "/api/inventory/products/{$id}", ['quantity' => 7.25])->assertStatus(422)->assertJsonValidationErrors('quantity');
        $this->assertSame(40, (int) $this->rows(fn () => DB::table('inventory_products')->find($id))->quantity);
    }

    // ------------------------------------------------------------------- VAT

    public function test_vat_is_optional_per_product_and_can_be_changed_or_cleared(): void
    {
        $plain = $this->product()->assertCreated()->json('data.id');
        $this->assertNull($this->rows(fn () => DB::table('inventory_products')->find($plain))->tax_percent, 'left out = the business default');

        $taxed = $this->product(['name' => 'Taxed', 'tax_percent' => 18])->assertCreated()->json('data.id');
        $this->assertSame(18.0, (float) $this->rows(fn () => DB::table('inventory_products')->find($taxed))->tax_percent);

        $this->api('PUT', "/api/inventory/products/{$taxed}", ['tax_percent' => 0])->assertOk();
        $this->assertSame(0.0, (float) $this->rows(fn () => DB::table('inventory_products')->find($taxed))->tax_percent, '0 = exempt, which is not the same as "not set"');

        $this->api('PUT', "/api/inventory/products/{$taxed}", ['tax_percent' => null])->assertOk();
        $this->assertNull($this->rows(fn () => DB::table('inventory_products')->find($taxed))->tax_percent);

        $this->product(['tax_percent' => 120])->assertStatus(422)->assertJsonValidationErrors('tax_percent');
        $this->product(['tax_percent' => -1])->assertStatus(422)->assertJsonValidationErrors('tax_percent');
    }

    // ---------------------------------------------------------------- variants

    public function test_sizes_and_colours_are_created_together_as_separate_stock(): void
    {
        $response = $this->product([
            'name' => 'T-Shirt', 'selling_price' => 15000, 'cost_price' => 9000, 'sku' => 'TSHIRT',
            'variants' => [
                ['label' => 'M / Red', 'quantity' => 10],
                ['label' => 'L / Red', 'quantity' => 6, 'selling_price' => 16000],
                ['label' => 'M / Blue', 'quantity' => 0, 'barcode' => '6001234567890'],
            ],
        ])->assertCreated();

        $ids = $response->json('data.ids');
        $this->assertCount(3, $ids);
        $this->assertSame($ids[0], $response->json('data.id'));

        $rows = $this->rows(fn () => DB::table('inventory_products')->whereIn('id', $ids)->orderBy('id')->get()->all());
        $this->assertSame(['T-Shirt — M / Red', 'T-Shirt — L / Red', 'T-Shirt — M / Blue'], array_map(fn ($r) => $r->name, $rows));
        $this->assertSame(['M / Red', 'L / Red', 'M / Blue'], array_map(fn ($r) => $r->variant_label, $rows));
        $this->assertSame([10, 6, 0], array_map(fn ($r) => (int) $r->quantity, $rows), 'each has its own stock');
        $this->assertSame([15000.0, 16000.0, 15000.0], array_map(fn ($r) => (float) $r->selling_price, $rows), 'own price, else the parent\'s');
        $this->assertSame(['TSHIRT-M-RED', 'TSHIRT-L-RED', 'TSHIRT-M-BLUE'], array_map(fn ($r) => $r->sku, $rows));
        $this->assertSame('6001234567890', $rows[2]->barcode);
        $this->assertCount(1, array_unique(array_map(fn ($r) => $r->family_id, $rows)));
        $this->assertSame($ids[0], (int) $rows[0]->family_id);

        // Each one can be found, priced and sold on its own: it has its base unit and price.
        foreach ($rows as $row) {
            $this->assertCount(1, $this->units($row->id));
        }
    }

    public function test_every_variant_carries_the_same_selling_units(): void
    {
        $ids = $this->product([
            'name' => 'Rice', 'variants' => [['label' => 'Pishori'], ['label' => 'Basmati']],
            'units' => [['name' => 'sack', 'factor' => 50, 'retail_price' => 90000]],
        ])->assertCreated()->json('data.ids');

        foreach ($ids as $id) {
            $units = $this->units($id);
            $this->assertSame(['pcs', 'sack'], array_map(fn ($u) => $u->name, $units));
            $this->assertSame(90000.0, $this->price($units[1]->id, 'retail'));
        }
    }

    public function test_variant_labels_and_skus_must_be_unique(): void
    {
        $this->product(['name' => 'Shoe', 'variants' => [['label' => '42'], ['label' => '42']]])->assertStatus(422);

        $this->product(['name' => 'Shoe', 'sku' => 'SHOE', 'variants' => [['label' => '42']]])->assertCreated();
        $this->product(['name' => 'Boot', 'variants' => [['label' => '43', 'sku' => 'SHOE-42']]])->assertStatus(422);
        $this->assertSame(1, $this->rows(fn () => DB::table('inventory_products')->count()), 'the failed one created nothing');
    }

    public function test_more_sizes_can_be_added_to_an_existing_product(): void
    {
        $id = $this->product(['name' => 'Cap', 'sku' => 'CAP', 'selling_price' => 7000, 'quantity' => 12, 'units' => [['name' => 'dozen', 'factor' => 12, 'retail_price' => 80000]]])
            ->assertCreated()->json('data.id');

        $created = $this->api('POST', "/api/inventory/products/{$id}/variants", [
            'variants' => [['label' => 'Black', 'quantity' => 5], ['label' => 'White', 'quantity' => 8, 'selling_price' => 7500]],
        ])->assertCreated();

        $ids = $created->json('data.ids');
        $this->assertSame($id, $created->json('data.family_id'), 'the product itself starts the family');
        $this->assertSame($id, (int) $this->rows(fn () => DB::table('inventory_products')->find($id))->family_id);

        $rows = $this->rows(fn () => DB::table('inventory_products')->whereIn('id', $ids)->orderBy('id')->get()->all());
        $this->assertSame(['Cap — Black', 'Cap — White'], array_map(fn ($r) => $r->name, $rows));
        $this->assertSame(['CAP-BLACK', 'CAP-WHITE'], array_map(fn ($r) => $r->sku, $rows));
        $this->assertSame([7000.0, 7500.0], array_map(fn ($r) => (float) $r->selling_price, $rows));
        $this->assertSame(['pcs', 'dozen'], array_map(fn ($u) => $u->name, $this->units($ids[0])), 'copies the selling units');
        $this->assertSame(80000.0, $this->price($this->units($ids[0])[1]->id, 'retail'));

        // The list can show a family together.
        $family = $this->api('GET', "/api/inventory/products?family_id={$id}")->assertOk()->json('data');
        $this->assertCount(3, $family);
    }

    public function test_adding_to_a_variant_names_the_new_ones_after_the_product_not_the_variant(): void
    {
        $ids = $this->product(['name' => 'Shirt', 'sku' => 'SHIRT', 'variants' => [['label' => 'M']]])->assertCreated()->json('data.ids');

        $new = $this->api('POST', "/api/inventory/products/{$ids[0]}/variants", ['variants' => [['label' => 'L']]])->assertCreated()->json('data.ids');

        $row = $this->rows(fn () => DB::table('inventory_products')->find($new[0]));
        $this->assertSame('Shirt — L', $row->name);
        $this->assertSame('SHIRT-L', $row->sku);
        $this->assertSame($ids[0], (int) $row->family_id);
    }

    public function test_a_size_that_already_exists_is_refused(): void
    {
        $ids = $this->product(['name' => 'Shirt', 'variants' => [['label' => 'M'], ['label' => 'L']]])->assertCreated()->json('data.ids');

        $this->api('POST', "/api/inventory/products/{$ids[0]}/variants", ['variants' => [['label' => ' m ']]])->assertStatus(422);
        $this->assertSame(2, $this->rows(fn () => DB::table('inventory_products')->count()));
    }

    public function test_renaming_a_variant_renames_the_product_unless_the_name_was_changed_too(): void
    {
        $ids = $this->product(['name' => 'Shirt', 'variants' => [['label' => 'M']]])->assertCreated()->json('data.ids');
        $name = fn () => $this->rows(fn () => DB::table('inventory_products')->find($ids[0]))->name;

        $this->api('PUT', "/api/inventory/products/{$ids[0]}", ['variant_label' => 'Medium'])->assertOk();
        $this->assertSame('Shirt — Medium', $name());

        $this->api('PUT', "/api/inventory/products/{$ids[0]}", ['variant_label' => 'XL', 'name' => 'My own name'])->assertOk();
        $this->assertSame('My own name', $name(), 'a name typed on purpose wins');
    }

    // --------------------------------------------------------------- isolation

    public function test_another_business_can_neither_see_nor_extend_a_product_family(): void
    {
        $other = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');
        $ids = $this->product(['name' => 'Shirt', 'sku' => 'SHIRT', 'variants' => [['label' => 'M']]])->assertCreated()->json('data.ids');

        $this->api('POST', "/api/inventory/products/{$ids[0]}/variants", ['variants' => [['label' => 'L']]], $other)->assertNotFound();
        $this->assertSame([], $this->api('GET', "/api/inventory/products?family_id={$ids[0]}", [], $other)->assertOk()->json('data'));

        // ... and both can have a "SHIRT-M": SKUs are unique per business, not across the platform.
        $this->product(['name' => 'Shirt', 'sku' => 'SHIRT', 'variants' => [['label' => 'M']]], $other)->assertCreated();
        $this->assertSame(1, $this->rows(fn () => DB::table('inventory_products')->count(), $other));
        $this->assertSame(1, $this->rows(fn () => DB::table('inventory_products')->count()));
    }

    public function test_the_product_list_can_carry_each_products_units_and_prices(): void
    {
        $this->product([
            'name' => 'Cola', 'unit' => 'bottle',
            'units' => [['name' => 'crate', 'factor' => 24, 'retail_price' => 22000, 'wholesale_price' => 20000]],
        ])->assertCreated();

        // Without the flag the list is as it always was.
        $this->assertArrayNotHasKey('units', $this->api('GET', '/api/inventory/products')->assertOk()->json('data.0'));

        $row = $this->api('GET', '/api/inventory/products?with_units=1')->assertOk()->json('data.0');
        $this->assertSame(['bottle', 'crate'], array_column($row['units'], 'name'), 'the base unit first');
        $this->assertSame(24, (int) $row['units'][1]['factor']);
        $prices = collect($row['units'][1]['prices'])->pluck('price', 'tier')->map(fn ($p) => (float) $p)->all();
        $this->assertSame(['retail' => 22000.0, 'wholesale' => 20000.0], $prices);
    }

    public function test_creating_with_variants_needs_no_product_level_quantity(): void
    {
        $this->api('POST', '/api/inventory/products', [
            'name' => 'Dress', 'cost_price' => 1, 'selling_price' => 2, 'min_stock' => 0, 'status' => 'active',
            'variants' => [['label' => 'S', 'quantity' => 3]],
        ])->assertCreated();

        // Without variants the quantity is still required.
        $this->api('POST', '/api/inventory/products', [
            'name' => 'Dress', 'cost_price' => 1, 'selling_price' => 2, 'min_stock' => 0, 'status' => 'active',
        ])->assertStatus(422)->assertJsonValidationErrors('quantity');
    }
}
