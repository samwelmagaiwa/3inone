<?php

namespace App\Support\Salon;

use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The salon's money for a period, worked out in one place so the profit and loss page, the dashboard and the reports
 * all say the same thing. Runs for ONE business's salon (the tenant grammar limits every query to its rows).
 *
 * Words used here, and kept apart on purpose:
 *  - REVENUE is what the lines were sold for AFTER the sale's discount (each line carries its share of it).
 *  - COMMISSION is what stylists earn on their services (fixed on each sale line when it was sold).
 *  - COLLECTIONS are the payments received in the period, by how they were paid: they are money in hand, not revenue,
 *    and they include old debts being paid; the cash a stylist has handed over is yet another figure (see cash).
 */
final class SalonFinance
{
    /** A sale line's value after its share of the sale's discount. */
    private const NET = 'si.total - COALESCE(s.discount * si.total / NULLIF(s.subtotal, 0), 0)';

    private const SHARE = 'COALESCE(s.discount * si.total / NULLIF(s.subtotal, 0), 0)';

    /** @return array<string, mixed> */
    public static function summary(Carbon $from, Carbon $to): array
    {
        $f = $from->toDateString();
        $t = $to->toDateString();

        $lines = DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->whereNull('s.cancelled_at')
            ->whereDate('s.created_at', '>=', $f)
            ->whereDate('s.created_at', '<=', $t)
            ->groupBy('si.is_service')
            ->selectRaw('si.is_service as is_service, COALESCE(SUM(' . self::NET . '), 0) as net, COALESCE(SUM(' . self::SHARE . '), 0) as discount, '
                . 'COALESCE(SUM(si.unit_cost_snapshot * si.quantity), 0) as cost')
            ->get()
            ->keyBy(fn ($r) => (int) $r->is_service ? 'service' : 'goods');

        $serviceRevenue = (float) ($lines['service']->net ?? 0);
        $goodsRevenue = (float) ($lines['goods']->net ?? 0);
        $discounts = (float) ($lines['service']->discount ?? 0) + (float) ($lines['goods']->discount ?? 0);
        // Only goods cost something to give: a service takes no stock (its cost snapshot is zero anyway).
        $costOfGoods = (float) ($lines['goods']->cost ?? 0);
        $gross = $serviceRevenue + $goodsRevenue - $costOfGoods;

        $expenses = self::expensesBetween($f, $t);
        $commissions = Schema::hasColumn('inventory_sale_items', 'commission_amount')
            ? (float) DB::table('inventory_sale_items as si')
                ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
                ->whereNull('s.cancelled_at')
                ->whereDate('s.created_at', '>=', $f)
                ->whereDate('s.created_at', '<=', $t)
                ->sum('si.commission_amount')
            : 0.0;
        $salaries = Schema::hasTable('inventory_staff_payouts')
            ? (float) DB::table('inventory_staff_payouts')->where('kind', 'salary')->whereBetween('paid_on', [$f, $t])->sum('amount')
            : 0.0;
        $operating = $expenses['total'] + $commissions + $salaries;

        $collections = DB::table('inventory_sale_payments as p')
            ->join('inventory_sales as s', 's.id', '=', 'p.sale_id')
            ->whereNull('s.cancelled_at')
            ->whereDate('p.paid_at', '>=', $f)
            ->whereDate('p.paid_at', '<=', $t)
            ->groupBy(DB::raw('COALESCE(p.method_extended, p.method)'))
            ->selectRaw('COALESCE(p.method_extended, p.method) as method, SUM(p.amount) as amount')
            ->orderByRaw('SUM(p.amount) DESC')
            ->get()
            ->map(fn ($r) => ['method' => (string) $r->method, 'amount' => self::money($r->amount)])
            ->values();

        $sales = DB::table('inventory_sales')
            ->whereNull('cancelled_at')
            ->whereDate('created_at', '>=', $f)
            ->whereDate('created_at', '<=', $t);
        $outstanding = (float) ((clone $sales)->whereIn('payment_status', ['debt', 'partial'])->selectRaw('COALESCE(SUM(total - paid_total), 0) as due')->first()->due ?? 0);
        $cancelled = DB::table('inventory_sales')
            ->whereNotNull('cancelled_at')
            ->whereDate('created_at', '>=', $f)
            ->whereDate('created_at', '<=', $t)
            ->selectRaw('COUNT(*) as n, COALESCE(SUM(total), 0) as total')
            ->first();

        // Clients served: each different client once, plus each walk-in sale (nobody to count twice).
        $servedSales = DB::table('inventory_sales as s')
            ->whereNull('s.cancelled_at')
            ->whereDate('s.created_at', '>=', $f)
            ->whereDate('s.created_at', '<=', $t)
            ->whereExists(fn ($q) => $q->select(DB::raw(1))->from('inventory_sale_items as si')->whereColumn('si.sale_id', 's.id')->where('si.is_service', true));
        $clients = (int) (clone $servedSales)->whereNotNull('s.customer_id')->distinct()->count('s.customer_id')
            + (int) (clone $servedSales)->whereNull('s.customer_id')->count();

        return [
            'from' => $f,
            'to' => $t,
            'service_revenue' => self::money($serviceRevenue),
            'goods_revenue' => self::money($goodsRevenue),
            'revenue' => self::money($serviceRevenue + $goodsRevenue),
            'discounts' => self::money($discounts),
            'cost_of_goods' => self::money($costOfGoods),
            'gross_profit' => self::money($gross),
            'expenses' => self::money($expenses['total']),
            'expenses_by_category' => $expenses['by_category'],
            'commissions' => self::money($commissions),
            'salaries' => self::money($salaries),
            'operating_costs' => self::money($operating),
            'net_profit' => self::money($gross - $operating),
            'collections' => $collections,
            'collected' => self::money($collections->sum('amount')),
            'outstanding' => self::money($outstanding),
            'cancelled' => ['count' => (int) ($cancelled->n ?? 0), 'total' => self::money($cancelled->total ?? 0)],
            'sales' => (int) (clone $sales)->count(),
            'clients' => $clients,
        ];
    }

    /**
     * What the dashboard shows: the same figures for today, this week, this month and this year, who earned the
     * most, what sells best, and the day's diary.
     *
     * @return array<string, mixed>
     */
    public static function overview(Carbon $today): array
    {
        $periods = [
            'today' => [$today->copy()->startOfDay(), $today],
            'week' => [$today->copy()->startOfWeek(), $today],
            'month' => [$today->copy()->startOfMonth(), $today],
            'year' => [$today->copy()->startOfYear(), $today],
        ];
        $out = [];
        foreach ($periods as $name => [$from, $to]) {
            $s = self::summary($from, $to);
            $out[$name] = [
                'revenue' => $s['revenue'],
                'expenses' => $s['expenses'],
                'net_profit' => $s['net_profit'],
                'clients' => $s['clients'],
                'sales' => $s['sales'],
            ];
        }

        $month = self::summary($periods['month'][0], $today);
        $monthFrom = $periods['month'][0]->toDateString();
        $monthTo = $today->toDateString();

        $topServices = DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->whereNull('s.cancelled_at')
            ->where('si.is_service', true)
            ->whereDate('s.created_at', '>=', $monthFrom)
            ->whereDate('s.created_at', '<=', $monthTo)
            ->groupBy('si.product_id', 'p.name')
            ->selectRaw('p.name as name, SUM(COALESCE(si.unit_qty, si.quantity)) as times, SUM(' . self::NET . ') as revenue')
            ->orderByRaw('SUM(' . self::NET . ') DESC')
            ->limit(5)
            ->get()
            ->map(fn ($r) => ['name' => (string) ($r->name ?? ''), 'times' => (int) $r->times, 'revenue' => self::money($r->revenue)])
            ->values();

        $topStaff = DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->whereNull('s.cancelled_at')
            ->where('si.is_service', true)
            ->whereDate('s.created_at', '>=', $monthFrom)
            ->whereDate('s.created_at', '<=', $monthTo)
            ->groupBy('si.staff_id')
            ->selectRaw('si.staff_id as staff_id, MAX(si.staff_name) as name, SUM(' . self::NET . ') as revenue')
            ->orderByRaw('SUM(' . self::NET . ') DESC')
            ->limit(5)
            ->get()
            ->map(fn ($r) => ['staff_id' => $r->staff_id, 'name' => $r->name, 'revenue' => self::money($r->revenue)])
            ->values();

        $diary = ['today' => 0, 'upcoming' => 0];
        if (Schema::hasTable('inventory_appointments')) {
            $now = Carbon::now(AppointmentPlanner::TIMEZONE);
            $diary['today'] = (int) DB::table('inventory_appointments')
                ->whereIn('status', AppointmentPlanner::ACTIVE)
                ->whereBetween('starts_at', [$now->toDateString() . ' 00:00:00', $now->toDateString() . ' 23:59:59'])
                ->count();
            $diary['upcoming'] = (int) DB::table('inventory_appointments')
                ->whereIn('status', AppointmentPlanner::ACTIVE)
                ->where('starts_at', '>', $now->toDateString() . ' 23:59:59')
                ->count();
        }

        return [
            'periods' => $out,
            'month' => [
                'collections' => $month['collections'],
                'outstanding' => $month['outstanding'],
                'discounts' => $month['discounts'],
            ],
            'top_services' => $topServices,
            'top_staff' => $topStaff,
            'bookings' => $diary,
        ];
    }

    /** @return array{total: float, by_category: array<int, array{category: string, total: int|float, count: int}>} */
    private static function expensesBetween(string $from, string $to): array
    {
        $q = DB::table('inventory_expenses')->whereBetween('expense_date', [$from, $to]);
        if (Schema::hasColumn('inventory_expenses', 'status')) {
            // Waiting for approval or turned down is not yet a cost.
            $q->where('status', 'approved');
        }
        $rows = $q->groupBy('category')
            ->orderByRaw('SUM(amount) DESC')
            ->selectRaw('category, SUM(amount) as total, COUNT(*) as n')
            ->get();

        return [
            'total' => (float) $rows->sum('total'),
            'by_category' => $rows->map(fn ($r) => ['category' => (string) $r->category, 'total' => self::money($r->total), 'count' => (int) $r->n])->values()->all(),
        ];
    }

    public static function money(mixed $v): int|float
    {
        $f = round((float) $v, 2);

        return $f == floor($f) ? (int) $f : $f;
    }
}
