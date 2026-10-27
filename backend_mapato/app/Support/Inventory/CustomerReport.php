<?php

namespace App\Support\Inventory;

use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * One customer's whole story with the business, for any period: how many times they bought, how much, what they paid, what they
 * still owe, how much profit they brought, what they buy most, and how that moved week by week or month by month.
 *
 * Days are Tanzania days (the same as the monthly report). Profit is sales less what the goods cost; it is only worked out for
 * people who may see profit (the reports right), so a till operator sees purchases and debts but never costs. A person who sees
 * only their own sales (a sales officer) sees this customer's sales made by themselves; the customer's debt is the customer's own
 * and is shown whole, as it is on the credit screen.
 */
final class CustomerReport
{
    public const GROUPS = ['day', 'week', 'month'];

    /**
     * @return array<string, mixed>
     */
    public static function build(int $customerId, string $from, string $to, string $group, User $viewer): array
    {
        $group = in_array($group, self::GROUPS, true) ? $group : 'month';
        $tz = MonthlyFigures::TIMEZONE;
        $fromUtc = Carbon::parse($from, $tz)->startOfDay()->utc()->format('Y-m-d H:i:s');
        $toUtc = Carbon::parse($to, $tz)->endOfDay()->utc()->format('Y-m-d H:i:s');
        $profitVisible = $viewer->hasInventoryPermission('inv_view_reports');
        $seesAll = SalesVisibility::seesAll($viewer);

        $sales = fn () => DB::table('inventory_sales as s')
            ->where('s.customer_id', $customerId)
            ->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')
            ->when(!$seesAll, fn ($q) => $q->where('s.created_by', (string) $viewer->id));

        $in = fn () => $sales()->whereBetween('s.created_at', [$fromUtc, $toUtc]);
        $costOf = fn ($query) => (float) $query->join('inventory_sale_items as si', 'si.sale_id', '=', 's.id')->sum(DB::raw('si.unit_cost_snapshot * si.quantity'));

        $rows = $in()->orderBy('s.created_at')->get(['s.id', 's.number', 's.total', 's.paid_total', 's.payment_status', 's.created_at']);
        $costBySale = $profitVisible && $rows->isNotEmpty()
            ? DB::table('inventory_sale_items')->whereIn('sale_id', $rows->pluck('id'))->groupBy('sale_id')->pluck(DB::raw('SUM(unit_cost_snapshot * quantity)'), 'sale_id')
            : collect();

        $salesValue = (float) $rows->sum('total');
        $paid = (float) $rows->sum('paid_total');
        $cost = $profitVisible ? (float) $costBySale->sum() : null;

        // Week by week, month by month, or day by day: each period with what was sold in it (and the profit, where it may be seen).
        $periods = [];
        foreach ($rows as $r) {
            $local = Carbon::parse($r->created_at, 'UTC')->setTimezone($tz);
            [$key, $label] = match ($group) {
                'day' => [$local->format('Y-m-d'), $local->format('Y-m-d')],
                'week' => [$local->copy()->startOfWeek(Carbon::MONDAY)->format('Y-m-d'), $local->copy()->startOfWeek(Carbon::MONDAY)->format('Y-m-d')],
                default => [$local->format('Y-m'), $local->format('Y-m')],
            };
            $periods[$key] ??= ['period' => $label, 'purchases' => 0, 'sales' => 0.0, 'paid' => 0.0, 'profit' => $profitVisible ? 0.0 : null];
            $periods[$key]['purchases']++;
            $periods[$key]['sales'] += (float) $r->total;
            $periods[$key]['paid'] += (float) $r->paid_total;
            if ($profitVisible) {
                $periods[$key]['profit'] += (float) $r->total - (float) ($costBySale[$r->id] ?? 0);
            }
        }
        ksort($periods);

        $products = DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->join('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->where('s.customer_id', $customerId)->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')
            ->when(!$seesAll, fn ($q) => $q->where('s.created_by', (string) $viewer->id))
            ->whereBetween('s.created_at', [$fromUtc, $toUtc])
            ->groupBy('p.id', 'p.name')->orderByRaw('SUM(si.total) DESC')->limit(10)
            ->get(['p.name', DB::raw('SUM(COALESCE(si.unit_qty, si.quantity)) as qty'), DB::raw('SUM(si.total) as sales'), DB::raw('SUM(si.total - si.unit_cost_snapshot * si.quantity) as profit')])
            ->map(fn ($r) => ['name' => $r->name, 'qty' => round((float) $r->qty, 2), 'sales' => round((float) $r->sales, 2), 'profit' => $profitVisible ? round((float) $r->profit, 2) : null])->all();

        // Everything this customer has ever bought, and what they owe now (whatever the period).
        $lifetime = $sales()->selectRaw('COUNT(*) as n, COALESCE(SUM(s.total), 0) as value, MIN(s.created_at) as first_at, MAX(s.created_at) as last_at')->first();
        $lifetimeCost = $profitVisible ? $costOf($sales()) : null;
        // The customer's debt belongs to the customer, whoever made the sales: the credit screen shows it whole, so this does too.
        $owesSales = (float) DB::table('inventory_sales')->where('customer_id', $customerId)->whereNull('cancelled_at')->whereIn('payment_status', ['debt', 'partial'])->sum(DB::raw('total - paid_total'));
        $oldDebt = OpeningDebts::customerOwes($customerId);

        $customer = DB::table('inventory_customers')->where('id', $customerId)->first(['id', 'name', 'phone', 'address', 'credit_limit']);
        $local = fn (?string $utc) => $utc === null ? null : Carbon::parse($utc, 'UTC')->setTimezone($tz)->format('Y-m-d H:i');

        return [
            'customer' => ['id' => (int) $customer->id, 'name' => $customer->name, 'phone' => $customer->phone, 'address' => $customer->address, 'credit_limit' => round((float) ($customer->credit_limit ?? 0), 2)],
            'from' => $from, 'to' => $to, 'group' => $group, 'profit_visible' => $profitVisible,
            'totals' => [
                'purchases' => $rows->count(),
                'sales' => round($salesValue, 2),
                'paid' => round($paid, 2),
                'unpaid_in_period' => round(max(0, $salesValue - $paid), 2),
                'cost' => $cost === null ? null : round($cost, 2),
                'profit' => $cost === null ? null : round($salesValue - $cost, 2),
                'margin_percent' => $cost === null || $salesValue <= 0 ? null : round(($salesValue - $cost) / $salesValue * 100, 1),
                'average_purchase' => $rows->count() > 0 ? round($salesValue / $rows->count(), 2) : 0.0,
            ],
            'debt' => ['owes_now' => round($owesSales + $oldDebt, 2), 'from_sales' => round($owesSales, 2), 'from_before_app' => round($oldDebt, 2)],
            'lifetime' => [
                'purchases' => (int) $lifetime->n, 'sales' => round((float) $lifetime->value, 2),
                'profit' => $lifetimeCost === null ? null : round((float) $lifetime->value - $lifetimeCost, 2),
                'first_purchase' => $local($lifetime->first_at), 'last_purchase' => $local($lifetime->last_at),
            ],
            'by_period' => array_values(array_map(fn ($p) => [
                'period' => $p['period'], 'purchases' => $p['purchases'], 'sales' => round($p['sales'], 2), 'paid' => round($p['paid'], 2),
                'profit' => $p['profit'] === null ? null : round($p['profit'], 2),
            ], $periods)),
            'top_products' => $products,
            'recent_sales' => $rows->reverse()->take(20)->map(fn ($r) => [
                'id' => (int) $r->id, 'number' => $r->number, 'at' => $local($r->created_at), 'total' => round((float) $r->total, 2), 'paid' => round((float) $r->paid_total, 2), 'status' => $r->payment_status,
            ])->values()->all(),
        ];
    }
}
