<?php

namespace App\Services\Inventory;

use Illuminate\Support\Facades\DB;

/**
 * Selling units of a product and their prices, in one place.
 *
 * A product is STOCKED in one base unit (a whole number of them) and may be SOLD in several units, each
 * holding a fixed number of base units: a crate of 24 bottles, a kilogram of 1,000 grams. Nothing here ever
 * produces a fractional quantity: to sell 2.5 kg you sell 2,500 g.
 *
 * Every price write goes through writePrice(), the only code allowed to touch inventory_product_prices, so
 * the append-only change log can never be bypassed.
 */
class ProductUnits
{
    /** What the base unit of each kind of goods is, and the bigger units it is usually sold in. */
    public const MEASURES = [
        'count' => ['base' => null, 'bigger' => []],
        'weight' => ['base' => 'g', 'bigger' => ['kg' => 1000]],
        'volume' => ['base' => 'ml', 'bigger' => ['litre' => 1000]],
    ];

    /** How many base units one selling unit holds (the base unit itself holds one). */
    public static function factorOf(object $unit): int
    {
        return $unit->is_base ? 1 : max(1, (int) $unit->factor);
    }

    /**
     * Add a selling unit to a product, with its prices. Returns the new unit's id.
     * Call inside a transaction.
     *
     * @param  array{name: string, factor?: int, barcode?: ?string, retail_price?: ?float, wholesale_price?: ?float}  $unit
     */
    public function add(int $productId, array $unit, int|string|null $userId, string $reason = 'Unit created'): int
    {
        $unitId = DB::table('inventory_product_units')->insertGetId([
            'product_id' => $productId,
            'name' => $unit['name'],
            'factor' => max(1, (int) ($unit['factor'] ?? 1)),
            'is_base' => false,
            'barcode' => $unit['barcode'] ?? null,
            'status' => 'active',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        foreach (['retail' => 'retail_price', 'wholesale' => 'wholesale_price'] as $tier => $field) {
            if (isset($unit[$field]) && $unit[$field] !== '') {
                $this->writePrice($unitId, $tier, null, (float) $unit[$field], $reason, $userId);
            }
        }

        return $unitId;
    }

    /**
     * Upsert the current price and append to the immutable change log.
     * Must be called inside a transaction.
     */
    public function writePrice(
        int $unitId,
        string $tier,
        ?int $customerId,
        float $price,
        ?string $reason,
        int|string|null $userId,
        ?string $effectiveFrom = null,
    ): void {
        $current = DB::table('inventory_product_prices')
            ->where('product_unit_id', $unitId)
            ->where('tier', $tier)
            ->where(fn ($w) => $customerId === null
                ? $w->whereNull('customer_id')
                : $w->where('customer_id', $customerId))
            ->first();

        if ($current && (float) $current->price === $price) {
            return; // nothing changed, keep the log clean
        }

        $payload = [
            'price' => $price,
            'effective_from' => $effectiveFrom ?? now()->toDateString(),
            'created_by' => $userId,
            'updated_at' => now(),
        ];

        if ($current) {
            DB::table('inventory_product_prices')->where('id', $current->id)->update($payload);
        } else {
            DB::table('inventory_product_prices')->insert(array_merge($payload, [
                'product_unit_id' => $unitId,
                'tier' => $tier,
                'customer_id' => $customerId,
                'created_at' => now(),
            ]));
        }

        DB::table('inventory_price_changes')->insert([
            'product_unit_id' => $unitId,
            'tier' => $tier,
            'customer_id' => $customerId,
            'old_price' => $current->price ?? null,
            'new_price' => $price,
            'reason' => $reason,
            'changed_by' => $userId,
            'created_at' => now(),
        ]);
    }

    /**
     * The price of one selling unit for a tier, the way the till reads it:
     *   a customer's special price, else that tier's price, else the other tier's, else -- for a unit that
     *   has no price yet -- the base unit's price times how many base units this unit holds.
     * Returns null only when the product has no price at all.
     */
    public function priceFor(int $productId, int $unitId, string $tier = 'retail', ?int $customerId = null): ?float
    {
        $unit = DB::table('inventory_product_units')->where('id', $unitId)->where('product_id', $productId)->first();
        if ($unit === null) {
            return null;
        }

        $prices = DB::table('inventory_product_prices')->where('product_unit_id', $unitId)->get();
        $find = fn (string $t, ?int $c = null) => $prices->first(fn ($p) => $p->tier === $t && ($c === null ? $p->customer_id === null : (int) $p->customer_id === $c));

        $other = $tier === 'wholesale' ? 'retail' : 'wholesale';
        $hit = ($customerId !== null ? $find('special', $customerId) : null) ?? $find($tier) ?? $find($other);
        if ($hit !== null) {
            return (float) $hit->price;
        }

        if ($unit->is_base) {
            $selling = DB::table('inventory_products')->where('id', $productId)->value('selling_price');

            return $selling === null ? null : (float) $selling;
        }

        $base = DB::table('inventory_product_units')->where('product_id', $productId)->where('is_base', true)->first();
        $basePrice = $base ? $this->priceFor($productId, (int) $base->id, $tier, $customerId) : null;

        return $basePrice === null ? null : round($basePrice * self::factorOf($unit), 2);
    }
}
