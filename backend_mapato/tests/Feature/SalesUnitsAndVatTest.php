<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The till sells in the unit the customer asks for (a crate, a kilogram), takes WHOLE base units out of
 * stock, prices the line the way the till would, and works out the VAT the product carries.
 *
 * Quantities are whole numbers throughout: 2.5 kg of sugar is 2,500 g.
 */
class SalesUnitsAndVatTest extends TestCase
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

    private function rows(callable $fn)
    {
        return TenantContext::runAs($this->owner, $fn);
    }

    /** Cola: stocked as 100 bottles, also sold by the crate of 24 (and a pack of 6 with no price yet). */
    private function cola(array $overrides = []): array
    {
        $id = $this->api('POST', '/api/inventory/products', array_merge([
            'name' => 'Cola', 'unit' => 'bottle', 'quantity' => 100, 'min_stock' => 5, 'status' => 'active',
            'cost_price' => 700, 'selling_price' => 1000,
            'units' => [
                ['name' => 'crate', 'factor' => 24, 'retail_price' => 22000, 'wholesale_price' => 20000],
                ['name' => 'pack', 'factor' => 6],
            ],
        ], $overrides))->assertCreated()->json('data.id');

        $units = $this->rows(fn () => DB::table('inventory_product_units')->where('product_id', $id)->get()->keyBy('name')->all());

        return ['id' => $id, 'bottle' => $units['bottle']->id, 'crate' => ($units['crate'] ?? null)?->id, 'pack' => ($units['pack'] ?? null)?->id];
    }

    /** Sugar: stocked in grams (50 kg), sold in grams or kilograms. */
    private function sugar(array $overrides = []): array
    {
        $id = $this->api('POST', '/api/inventory/products', array_merge([
            'name' => 'Sugar', 'measure' => 'weight', 'quantity' => 50000, 'min_stock' => 1000, 'status' => 'active',
            'cost_price' => 1.5, 'selling_price' => 2,
            'units' => [['name' => 'kg', 'factor' => 1000, 'retail_price' => 2200, 'wholesale_price' => 2000]],
        ], $overrides))->assertCreated()->json('data.id');

        $units = $this->rows(fn () => DB::table('inventory_product_units')->where('product_id', $id)->get()->keyBy('name')->all());

        return ['id' => $id, 'g' => $units['g']->id, 'kg' => $units['kg']->id];
    }

    private function stock(int $productId): int
    {
        return (int) $this->rows(fn () => DB::table('inventory_products')->where('id', $productId)->value('quantity'));
    }

    /** Ring up a cash sale; totals are added up here the way the app does. */
    private function sell(array $items, array $extra = [])
    {
        $subtotal = array_sum(array_map(fn ($i) => ($i['unit_price'] ?? 0) * $i['quantity'], $items));

        return $this->api('POST', '/api/inventory/sales', array_merge([
            'payment_status' => 'paid', 'subtotal' => $subtotal, 'discount' => 0, 'tax' => 0,
            'total' => $subtotal, 'paid_total' => $subtotal, 'items' => $items,
        ], $extra));
    }

    private function item(int $saleId): object
    {
        return $this->rows(fn () => DB::table('inventory_sale_items')->where('sale_id', $saleId)->orderBy('id')->first());
    }

    // ---------------------------------------------------------- selling in units

    public function test_selling_in_a_unit_takes_whole_base_units_out_of_stock(): void
    {
        $p = $this->cola();

        $saleId = $this->sell([['product_id' => $p['id'], 'unit_id' => $p['crate'], 'quantity' => 2, 'unit_price' => 22000]])
            ->assertCreated()->json('data.id');

        $this->assertSame(100 - 48, $this->stock($p['id']), '2 crates = 48 bottles');

        $row = $this->item($saleId);
        $this->assertSame(48, (int) $row->quantity, '`quantity` is always base units');
        $this->assertSame(2, (int) $row->unit_qty);
        $this->assertSame('crate', $row->unit_name);
        $this->assertSame(24, (int) $row->unit_factor);
        $this->assertSame(22000.0, (float) $row->unit_price, 'the price is per selling unit');
        $this->assertSame(44000.0, (float) $row->total);

        // The apps read the line in its own unit: quantity x price = total.
        $line = $this->api('GET', "/api/inventory/sales/{$saleId}")->assertOk()->json('data.items.0');
        $this->assertSame(2, $line['quantity']);
        $this->assertSame(48, $line['base_quantity']);
        $this->assertSame('crate', $line['unit_name']);
        $this->assertSame(22000, $line['unit_price']);
        $this->assertSame(44000, $line['total']);
    }

    public function test_one_sale_can_mix_units_of_the_same_product(): void
    {
        $p = $this->cola();

        $this->sell([
            ['product_id' => $p['id'], 'unit_id' => $p['crate'], 'quantity' => 1, 'unit_price' => 22000],
            ['product_id' => $p['id'], 'quantity' => 3, 'unit_price' => 1000],            // loose bottles: no unit chosen
        ])->assertCreated();

        $this->assertSame(100 - 24 - 3, $this->stock($p['id']));
    }

    public function test_goods_by_weight_are_sold_in_kilograms_or_grams(): void
    {
        $s = $this->sugar();

        $saleId = $this->sell([
            ['product_id' => $s['id'], 'unit_id' => $s['kg'], 'quantity' => 2, 'unit_price' => 2200],   // 2 kg
            ['product_id' => $s['id'], 'unit_id' => $s['g'], 'quantity' => 500, 'unit_price' => 2],     // 500 g
        ])->assertCreated()->json('data.id');

        $this->assertSame(50000 - 2000 - 500, $this->stock($s['id']), '2 kg + 500 g = 2,500 g, every figure a whole number');

        $items = $this->api('GET', "/api/inventory/sales/{$saleId}")->assertOk()->json('data.items');
        $this->assertSame([2, 500], [$items[0]['quantity'], $items[1]['quantity']]);
        $this->assertSame([4400, 1000], [$items[0]['total'], $items[1]['total']]);
        $this->assertSame([2000, 500], [$items[0]['base_quantity'], $items[1]['base_quantity']]);
    }

    public function test_a_quantity_is_never_a_fraction(): void
    {
        $p = $this->cola();

        $this->sell([['product_id' => $p['id'], 'unit_id' => $p['crate'], 'quantity' => 1.5, 'unit_price' => 22000]])
            ->assertStatus(422);
        $this->sell([['product_id' => $p['id'], 'quantity' => 0.5, 'unit_price' => 1000]])
            ->assertStatus(422);

        $this->assertSame(100, $this->stock($p['id']), 'nothing was sold');
    }

    public function test_a_unit_must_be_an_active_unit_of_that_product(): void
    {
        $cola = $this->cola();
        $sugar = $this->sugar();

        // Another product's unit.
        $this->sell([['product_id' => $cola['id'], 'unit_id' => $sugar['kg'], 'quantity' => 1, 'unit_price' => 1]])
            ->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'This unit is not available for this product'));

        // A unit switched off.
        $this->rows(fn () => DB::table('inventory_product_units')->where('id', $cola['crate'])->update(['status' => 'inactive']));
        $this->sell([['product_id' => $cola['id'], 'unit_id' => $cola['crate'], 'quantity' => 1, 'unit_price' => 22000]])->assertStatus(422);

        $this->assertSame(100, $this->stock($cola['id']));
        $this->assertSame(0, $this->rows(fn () => DB::table('inventory_sales')->count()), 'no half-made sale');
    }

    public function test_another_business_cannot_sell_through_my_units(): void
    {
        $mine = $this->cola();
        $other = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');

        // To the other business the product (and so its unit) does not exist.
        $this->api('POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 1, 'total' => 1, 'paid_total' => 1,
            'items' => [['product_id' => $mine['id'], 'unit_id' => $mine['crate'], 'quantity' => 1, 'unit_price' => 1]],
        ], $other)->assertStatus(422);
    }

    public function test_cancelling_a_sale_puts_the_base_units_back(): void
    {
        $p = $this->cola();
        $saleId = $this->sell([['product_id' => $p['id'], 'unit_id' => $p['crate'], 'quantity' => 2, 'unit_price' => 22000]])->assertCreated()->json('data.id');
        $this->assertSame(52, $this->stock($p['id']));

        $this->api('POST', "/api/inventory/sales/{$saleId}/cancel", ['reason' => 'Customer changed their mind'])->assertOk();

        $this->assertSame(100, $this->stock($p['id']));
    }

    public function test_profit_counts_base_units_so_a_crate_sale_is_costed_per_bottle(): void
    {
        $p = $this->cola();
        $this->sell([['product_id' => $p['id'], 'unit_id' => $p['crate'], 'quantity' => 2, 'unit_price' => 22000]])->assertCreated();

        // revenue 44,000 - cost 48 bottles x 700 = 33,600
        $this->assertSame(10400.0, (float) $this->api('GET', '/api/inventory/kpis')->assertOk()->json('data.today.profit'));
    }

    // ----------------------------------------------------- how a line is priced

    public function test_a_line_with_no_price_is_priced_the_way_the_till_would(): void
    {
        // Plenty of stock: this test is about prices, and the sales below add up to more than 100 bottles.
        $p = $this->cola(['quantity' => 500]);
        $price = fn (array $item, array $extra = []) => (float) $this->rows(fn () => DB::table('inventory_sale_items')
            ->where('sale_id', $this->sell([$item], $extra)->assertCreated()->json('data.id'))->value('unit_price'));

        // The default level is retail; a business that sells wholesale says so once, in its settings.
        $this->assertSame(22000.0, $price(['product_id' => $p['id'], 'unit_id' => $p['crate'], 'quantity' => 1]));
        $this->assertSame(20000.0, $price(['product_id' => $p['id'], 'unit_id' => $p['crate'], 'quantity' => 1, 'tier' => 'wholesale']));

        $this->api('PUT', '/api/inventory/settings', ['sale_tier' => 'wholesale'])->assertOk();
        $this->assertSame(20000.0, $price(['product_id' => $p['id'], 'unit_id' => $p['crate'], 'quantity' => 1]));
        $this->assertSame(22000.0, $price(['product_id' => $p['id'], 'unit_id' => $p['crate'], 'quantity' => 1, 'tier' => 'retail']), 'a line can still ask for retail');

        // A unit with no price yet is the base price times what it holds: 6 x 1,000.
        $this->assertSame(6000.0, $price(['product_id' => $p['id'], 'unit_id' => $p['pack'], 'quantity' => 1]));

        // No unit chosen at all: the product's own price, as it has always been.
        $this->assertSame(1000.0, $price(['product_id' => $p['id'], 'quantity' => 1]));
    }

    public function test_a_customer_with_a_special_price_gets_it(): void
    {
        $p = $this->cola();
        $customer = $this->rows(fn () => DB::table('inventory_customers')->insertGetId(['name' => 'Mama Anna', 'phone' => '0712000000', 'created_at' => now(), 'updated_at' => now()]));
        $this->api('POST', "/api/inventory/products/{$p['id']}/units/{$p['crate']}/price", ['tier' => 'special', 'customer_id' => $customer, 'price' => 19000])->assertOk();

        $saleId = $this->sell([['product_id' => $p['id'], 'unit_id' => $p['crate'], 'quantity' => 1]], ['customer_id' => $customer])->assertCreated()->json('data.id');
        $this->assertSame(19000.0, (float) $this->item($saleId)->unit_price);

        $walkIn = $this->sell([['product_id' => $p['id'], 'unit_id' => $p['crate'], 'quantity' => 1]])->assertCreated()->json('data.id');
        $this->assertSame(22000.0, (float) $this->item($walkIn)->unit_price, 'everyone else pays the normal price');
    }

    public function test_sales_from_before_units_existed_read_exactly_as_they_did(): void
    {
        $p = $this->cola();
        $saleId = $this->sell([['product_id' => $p['id'], 'quantity' => 4, 'unit_price' => 1000]])->assertCreated()->json('data.id');

        $line = $this->api('GET', "/api/inventory/sales/{$saleId}")->assertOk()->json('data.items.0');
        $this->assertSame(4, $line['quantity']);
        $this->assertSame(4, $line['base_quantity']);
        $this->assertNull($line['unit_name']);
        $this->assertSame(1000, $line['unit_price']);
        $this->assertSame(4000, $line['total']);

        // A row written before the new columns existed (no unit, no quantity in units) reads the same way.
        $this->rows(fn () => DB::table('inventory_sale_items')->where('sale_id', $saleId)->update(['unit_qty' => null, 'unit_id' => null, 'unit_name' => null]));
        $old = $this->api('GET', "/api/inventory/sales/{$saleId}")->assertOk()->json('data.items.0');
        $this->assertSame(4, $old['quantity']);
    }

    // ----------------------------------------------------------------------- VAT

    public function test_a_product_with_vat_carries_it_on_the_line_and_on_the_sale(): void
    {
        $taxed = $this->cola(['name' => 'Taxed', 'tax_percent' => 18, 'units' => []]);

        // Prices include VAT (the default): 11,800 contains 1,800 of VAT.
        $saleId = $this->sell([['product_id' => $taxed['id'], 'quantity' => 1, 'unit_price' => 11800]])->assertCreated()->json('data.id');

        $row = $this->item($saleId);
        $this->assertSame(18.0, (float) $row->tax_percent);
        $this->assertSame(1800.0, (float) $row->tax_amount);
        $this->assertSame(11800.0, (float) $row->total, 'the total is untouched: the price already had VAT in it');
        $this->assertSame(1800.0, (float) $this->rows(fn () => DB::table('inventory_sales')->where('id', $saleId)->value('tax')));
        $this->assertSame(1800, $this->api('GET', "/api/inventory/sales/{$saleId}")->json('data.tax'));
    }

    public function test_when_prices_do_not_include_vat_it_is_added_on_top(): void
    {
        $this->api('PUT', '/api/inventory/settings', ['prices_include_vat' => '0'])->assertOk();
        $taxed = $this->cola(['name' => 'Taxed', 'tax_percent' => 18, 'units' => []]);

        // 10,000 + 18% = 11,800; the till sends the total it added up.
        $saleId = $this->sell([['product_id' => $taxed['id'], 'quantity' => 1, 'unit_price' => 10000]], ['tax' => 1800, 'total' => 11800, 'paid_total' => 11800])
            ->assertCreated()->json('data.id');

        $this->assertSame(1800.0, (float) $this->item($saleId)->tax_amount);
        $this->assertSame(10000.0, (float) $this->item($saleId)->total, 'the line is the price without VAT');
        $this->assertSame(1800.0, (float) $this->rows(fn () => DB::table('inventory_sales')->where('id', $saleId)->value('tax')));
    }

    public function test_a_product_without_a_rate_uses_the_business_default_and_zero_means_exempt(): void
    {
        $this->api('PUT', '/api/inventory/settings', ['tax_percent' => '16'])->assertOk();
        $default = $this->cola(['name' => 'Default VAT', 'units' => []]);
        $exempt = $this->cola(['name' => 'Exempt', 'tax_percent' => 0, 'units' => []]);
        $custom = $this->cola(['name' => 'Custom', 'tax_percent' => 18, 'units' => []]);

        $saleId = $this->sell([
            ['product_id' => $default['id'], 'quantity' => 1, 'unit_price' => 11600],
            ['product_id' => $exempt['id'], 'quantity' => 1, 'unit_price' => 5000],
            ['product_id' => $custom['id'], 'quantity' => 1, 'unit_price' => 11800],
        ])->assertCreated()->json('data.id');

        $tax = $this->rows(fn () => DB::table('inventory_sale_items')->where('sale_id', $saleId)->orderBy('id')->pluck('tax_amount')->map(fn ($t) => (float) $t)->all());
        $this->assertSame([1600.0, 0.0, 1800.0], $tax);
        $this->assertSame(3400.0, (float) $this->rows(fn () => DB::table('inventory_sales')->where('id', $saleId)->value('tax')), 'the sale carries what its lines say');
    }

    public function test_with_no_vat_anywhere_nothing_changes(): void
    {
        $p = $this->cola();
        $saleId = $this->sell([['product_id' => $p['id'], 'quantity' => 2, 'unit_price' => 1000]], ['tax' => 0])->assertCreated()->json('data.id');

        $this->assertSame(0.0, (float) $this->item($saleId)->tax_amount);
        $this->assertNull($this->item($saleId)->tax_percent);
        $this->assertSame(0.0, (float) $this->rows(fn () => DB::table('inventory_sales')->where('id', $saleId)->value('tax')));
    }

    public function test_vat_works_on_a_sale_in_a_unit(): void
    {
        $sugar = $this->sugar(['tax_percent' => 18]);

        $saleId = $this->sell([['product_id' => $sugar['id'], 'unit_id' => $sugar['kg'], 'quantity' => 5, 'unit_price' => 2360]])->assertCreated()->json('data.id');

        $this->assertSame(1800.0, (float) $this->item($saleId)->tax_amount, '5 kg x 2,360 = 11,800 including 1,800 VAT');
    }

    // ------------------------------------------------------------------- returns

    private function approver(): User
    {
        return $this->givenServices(User::factory()->create(['role' => 'manager', 'is_active' => true, 'created_by' => $this->owner->id]), 'inventory');
    }

    public function test_a_return_in_a_unit_refunds_that_unit_and_restocks_base_units(): void
    {
        $s = $this->sugar();
        $saleId = $this->sell([['product_id' => $s['id'], 'unit_id' => $s['kg'], 'quantity' => 2, 'unit_price' => 2200]])->assertCreated()->json('data.id');
        $this->assertSame(48000, $this->stock($s['id']));

        $returnId = $this->api('POST', '/api/inventory/returns', [
            'sale_id' => $saleId, 'type' => 'return', 'reason' => 'Damp',
            'lines' => [['product_id' => $s['id'], 'unit_id' => $s['kg'], 'quantity' => 1, 'unit_price' => 2200]],
        ])->assertCreated()->json('data.id');

        $return = $this->rows(fn () => DB::table('inventory_sale_returns')->find($returnId));
        $this->assertSame(2200.0, (float) $return->amount, '1 kg x 2,200');
        $line = $this->rows(fn () => DB::table('inventory_sale_return_lines')->where('sale_return_id', $returnId)->first());
        $this->assertSame(1000, (int) $line->quantity, 'base units');
        $this->assertSame(1, (int) $line->unit_qty);
        $this->assertSame('kg', $line->unit_name);

        $this->api('POST', "/api/inventory/returns/{$returnId}/decide", ['decision' => 'approved'], $this->approver())->assertOk();

        $this->assertSame(49000, $this->stock($s['id']), '1,000 g went back on the shelf');
        $this->assertSame(4400.0 - 2200.0, (float) $this->rows(fn () => DB::table('inventory_sales')->where('id', $saleId)->value('total')));
    }

    public function test_a_return_can_never_exceed_what_was_sold_whatever_the_unit(): void
    {
        $s = $this->sugar();
        $saleId = $this->sell([['product_id' => $s['id'], 'unit_id' => $s['kg'], 'quantity' => 2, 'unit_price' => 2200]])->assertCreated()->json('data.id');

        $this->api('POST', '/api/inventory/returns', [
            'sale_id' => $saleId, 'type' => 'return',
            'lines' => [['product_id' => $s['id'], 'unit_id' => $s['kg'], 'quantity' => 3, 'unit_price' => 2200]],
        ])->assertStatus(422);

        // 2,000 g were sold: 2,001 g is too many, 2,000 g is fine.
        $this->api('POST', '/api/inventory/returns', [
            'sale_id' => $saleId, 'type' => 'return',
            'lines' => [['product_id' => $s['id'], 'unit_id' => $s['g'], 'quantity' => 2001, 'unit_price' => 2]],
        ])->assertStatus(422);
        $this->api('POST', '/api/inventory/returns', [
            'sale_id' => $saleId, 'type' => 'return',
            'lines' => [['product_id' => $s['id'], 'unit_id' => $s['g'], 'quantity' => 2000, 'unit_price' => 2]],
        ])->assertCreated();
    }

    public function test_when_prices_exclude_vat_a_refund_gives_the_vat_back_too(): void
    {
        $this->api('PUT', '/api/inventory/settings', ['prices_include_vat' => '0'])->assertOk();
        $taxed = $this->cola(['name' => 'Taxed', 'tax_percent' => 18, 'units' => []]);
        $saleId = $this->sell([['product_id' => $taxed['id'], 'quantity' => 2, 'unit_price' => 10000]], ['tax' => 3600, 'total' => 23600, 'paid_total' => 23600])
            ->assertCreated()->json('data.id');

        $returnId = $this->api('POST', '/api/inventory/returns', [
            'sale_id' => $saleId, 'type' => 'return',
            'lines' => [['product_id' => $taxed['id'], 'quantity' => 1, 'unit_price' => 10000]],
        ])->assertCreated()->json('data.id');

        $this->assertSame(11800.0, (float) $this->rows(fn () => DB::table('inventory_sale_returns')->find($returnId))->amount, '10,000 + 18%');
    }
}
