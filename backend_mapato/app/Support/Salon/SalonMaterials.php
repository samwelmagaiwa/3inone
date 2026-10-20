<?php

namespace App\Support\Salon;

use App\Services\Inventory\StockLedger;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The goods a service uses up. When a service line is sold, the goods it is set up to use leave the shelf (a haircut is
 * never stopped because the shampoo ran out: what is there is taken, and the line says so) and what they cost is kept
 * against the sale; cancelling the sale puts them back.
 */
final class SalonMaterials
{
    public static function active(): bool
    {
        return Schema::hasTable('inventory_service_materials') && Schema::hasTable('inventory_service_usage');
    }

    /** Take the goods one service line uses (for `$unitQty` of the service). Never throws: the sale must go on. */
    public static function consume(StockLedger $ledger, int $saleId, int $itemId, int $serviceProductId, int $unitQty, string $reference, int|string|null $userId): void
    {
        if (!self::active()) {
            return;
        }
        $materials = DB::table('inventory_service_materials')->where('service_product_id', $serviceProductId)->get();
        foreach ($materials as $m) {
            $product = DB::table('inventory_products')->where('id', $m->material_product_id)->first();
            if ($product === null) {
                continue;
            }
            $take = min((int) $m->quantity * $unitQty, (int) $product->quantity);
            if ($take < 1) {
                continue;
            }
            $cost = (float) $product->cost_price;
            try {
                $allocations = $ledger->issue((int) $m->material_product_id, $take, $reference, 'service_use', $userId);
                $issued = array_sum(array_column($allocations, 'quantity'));
                if ($issued > 0) {
                    $cost = array_sum(array_map(fn ($a) => $a['cost_price'] * $a['quantity'], $allocations)) / $issued;
                }
            } catch (\Throwable) {
                continue;
            }
            DB::table('inventory_service_usage')->insert([
                'sale_id' => $saleId, 'sale_item_id' => $itemId, 'material_product_id' => (int) $m->material_product_id,
                'quantity' => $take, 'unit_cost' => round($cost, 2), 'created_at' => now(),
            ]);
        }
    }

    /** A cancelled sale: put back what its services used. */
    public static function restore(StockLedger $ledger, int $saleId, string $number, int|string|null $userId): void
    {
        if (!self::active()) {
            return;
        }
        foreach (DB::table('inventory_service_usage')->where('sale_id', $saleId)->get() as $u) {
            try {
                $ledger->receive((int) $u->material_product_id, (int) $u->quantity, 'CANCEL-' . now()->format('Ymd'), null, (float) $u->unit_cost, $number, $userId);
            } catch (\Throwable) {
                DB::table('inventory_products')->where('id', $u->material_product_id)->increment('quantity', (int) $u->quantity, ['updated_at' => now()]);
            }
        }
    }

    /** What the services used up cost in a period (sales not cancelled). */
    public static function cost(string $from, string $to, ?int $branch = null): float
    {
        if (!self::active()) {
            return 0.0;
        }
        $q = DB::table('inventory_service_usage as u')->join('inventory_sales as s', 's.id', '=', 'u.sale_id')
            ->whereNull('s.cancelled_at')
            ->whereDate('s.created_at', '>=', $from)->whereDate('s.created_at', '<=', $to);
        if ($branch !== null && Schema::hasColumn('inventory_sales', 'branch_id')) {
            $q->where('s.branch_id', $branch);
        }

        return (float) $q->sum(DB::raw('u.quantity * u.unit_cost'));
    }
}
