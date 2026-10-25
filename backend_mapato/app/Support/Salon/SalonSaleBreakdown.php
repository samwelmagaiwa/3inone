<?php

namespace App\Support\Salon;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * What one salon sale really earned, line by line, so the goods and the service are never mixed up:
 *
 *   - each SERVICE: what it brought in (after its share of any discount), the stylist's commission, the goods it used up
 *     (set on the service: shampoo, dye, towels) with their cost, and so its profit;
 *   - each GOODS line sold (extensions, oil): what it brought in, what it cost, and so its profit;
 *   - the totals of the two, and of the sale.
 */
final class SalonSaleBreakdown
{
    /** @return array<string, mixed> */
    public static function for(int $saleId): array
    {
        $sale = DB::table('inventory_sales')->where('id', $saleId)->first(['subtotal', 'discount']);
        $share = $sale !== null && (float) $sale->subtotal > 0 ? (float) $sale->discount / (float) $sale->subtotal : 0.0;

        $items = DB::table('inventory_sale_items as si')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->where('si.sale_id', $saleId)->orderBy('si.id')
            ->get(['si.id', 'si.is_service', 'si.total', 'si.quantity', 'si.unit_qty', 'si.unit_cost_snapshot', 'si.staff_name', 'si.commission_amount', 'p.name']);

        $used = Schema::hasTable('inventory_service_usage')
            ? DB::table('inventory_service_usage as u')->leftJoin('inventory_products as m', 'm.id', '=', 'u.material_product_id')
                ->where('u.sale_id', $saleId)->get(['u.sale_item_id', 'u.quantity', 'u.unit_cost', 'm.name'])->groupBy('sale_item_id')
            : collect();

        $services = [];
        $goods = [];
        foreach ($items as $i) {
            $revenue = round((float) $i->total * (1 - $share), 2);
            $qty = (int) ($i->unit_qty ?? $i->quantity);
            if ((bool) $i->is_service) {
                $materials = ($used[$i->id] ?? collect())->map(fn ($u) => ['name' => (string) $u->name, 'quantity' => (int) $u->quantity, 'cost' => SalonFinance::money((int) $u->quantity * (float) $u->unit_cost)])->values();
                $materialsCost = (float) $materials->sum('cost');
                $commission = (float) ($i->commission_amount ?? 0);
                $services[] = [
                    'name' => (string) $i->name, 'quantity' => $qty, 'stylist' => $i->staff_name,
                    'revenue' => SalonFinance::money($revenue), 'commission' => SalonFinance::money($commission),
                    'materials' => $materials->all(), 'materials_cost' => SalonFinance::money($materialsCost),
                    'profit' => SalonFinance::money($revenue - $commission - $materialsCost),
                ];
            } else {
                $cost = (float) $i->unit_cost_snapshot * (int) $i->quantity;
                $goods[] = [
                    'name' => (string) $i->name, 'quantity' => $qty,
                    'revenue' => SalonFinance::money($revenue), 'cost' => SalonFinance::money($cost), 'profit' => SalonFinance::money($revenue - $cost),
                ];
            }
        }

        $serviceProfit = array_sum(array_column($services, 'profit'));
        $goodsProfit = array_sum(array_column($goods, 'profit'));

        return [
            'services' => $services,
            'goods' => $goods,
            'service_profit' => SalonFinance::money($serviceProfit),
            'goods_profit' => SalonFinance::money($goodsProfit),
            'profit' => SalonFinance::money($serviceProfit + $goodsProfit),
        ];
    }
}
