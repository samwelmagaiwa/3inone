<?php

namespace App\Support\Inventory;

use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Everything the owner reads for a month, in one place: the figures, how they compare with the month before, where the
 * business stands (stock, debts, capital), the profit target and how close the month got, and the products and customers
 * behind the numbers. {@see MonthlyFigures} says how each number is worked out.
 */
final class MonthlyReport
{
    /** @return array<string, mixed> */
    public static function build(string $month): array
    {
        $current = MonthlyFigures::currentMonth();
        $isCurrent = $month === $current;
        $isFuture = $month > $current;
        [$first, $last] = MonthlyFigures::bounds($month);
        $today = Carbon::now(MonthlyFigures::TIMEZONE);

        $figures = MonthlyFigures::for($month);
        $prevMonth = MonthlyFigures::previousMonth($month);
        $prevFull = MonthlyFigures::for($prevMonth);
        // A month in progress is compared with the same days of the month before, so it is not "down" only because it is young.
        $elapsed = $isCurrent ? $today->day : null;
        $prevSame = $isCurrent ? MonthlyFigures::for($prevMonth, $elapsed) : $prevFull;

        $compare = [
            'sales' => MonthlyFigures::compare($figures['sales'], $prevSame['sales']),
            'gross_profit' => MonthlyFigures::compare($figures['gross_profit'], $prevSame['gross_profit']),
            'expenses' => MonthlyFigures::compare($figures['expenses'], $prevSame['expenses']),
            'net_profit' => MonthlyFigures::compare($figures['net_profit'], $prevSame['net_profit']),
        ];
        // For spending, "down" is good: the app says so with `good`, so the screen does not have to know.
        foreach ($compare as $k => &$c) {
            $c['good'] = $k === 'expenses' ? $c['direction'] !== 'up' : $c['direction'] !== 'down';
        }
        unset($c);

        // Where the business stands: live for this month (and remembered), as remembered for a past one.
        if ($isCurrent) {
            MonthlyFigures::remember($month);
        }
        $position = $isCurrent ? MonthlyFigures::position() : MonthlyFigures::remembered($month);
        $opening = MonthlyFigures::remembered($prevMonth);
        $capital = $position !== null && $opening !== null
            ? MonthlyFigures::compare((float) $position['capital'], (float) $opening['capital'])
            : null;

        return [
            'month' => $month,
            'is_current' => $isCurrent,
            'is_future' => $isFuture,
            'days_elapsed' => $isCurrent ? $today->day : ($isFuture ? 0 : $first->daysInMonth),
            'days_in_month' => $first->daysInMonth,
            'figures' => $figures,
            'previous' => ['month' => $prevMonth, 'like_for_like' => $isCurrent, 'figures' => $prevSame, 'full' => $prevFull],
            'compare' => $compare,
            'overall' => self::overall($compare['net_profit'], $compare['sales']),
            'position' => $position === null ? null : $position + ['as_of' => $isCurrent ? $today->toDateString() : $last->toDateString()],
            'opening_position' => $opening,
            'capital_change' => $capital,
            'target' => self::target($month, (float) $figures['net_profit'], $isCurrent, $isFuture, $first->daysInMonth, $isCurrent ? $today->day : null),
            'top_products' => self::topProducts($first, $last),
            'top_customers' => self::topCustomers($first, $last),
            'slow_stock' => self::slowStock(),
            'debtors' => self::debtors(),
            'creditors' => OpeningDebts::list(OpeningDebts::PAYABLE)->take(8)->all(),
        ];
    }

    /** The headline: did the month do better, the same, or worse than the one before, and by how much. */
    private static function overall(array $profit, array $sales): array
    {
        $lead = abs($profit['before']) > 0.005 || abs($profit['now']) > 0.005 ? $profit : $sales;

        return ['direction' => $lead['direction'], 'percent' => $lead['percent'], 'based_on' => $lead === $profit ? 'profit' : 'sales'];
    }

    /** @return array<string, mixed>|null */
    private static function target(string $month, float $profit, bool $isCurrent, bool $isFuture, int $daysInMonth, ?int $day): ?array
    {
        $row = Schema::hasTable('inventory_targets') ? DB::table('inventory_targets')->where('month', $month)->first() : null;
        if ($row === null) {
            return null;
        }
        $target = (float) $row->profit_target;
        $progress = $target > 0 ? round($profit / $target * 100, 1) : null;
        // What the month should have earned by today if the target is met evenly.
        $expected = $isCurrent && $day !== null ? round($target * $day / $daysInMonth, 2) : ($isFuture ? 0.0 : $target);
        $status = match (true) {
            $profit >= $target => 'reached',
            $isFuture => 'not_started',
            !$isCurrent => 'missed',
            $profit >= $expected => 'on_track',
            default => 'behind',
        };

        return [
            'profit_target' => round($target, 2),
            'profit' => round($profit, 2),
            'progress_percent' => $progress,
            'left' => round(max(0, $target - $profit), 2),
            'over_by' => round(max(0, $profit - $target), 2),
            'expected_by_today' => $expected,
            'days_left' => $isCurrent && $day !== null ? $daysInMonth - $day : 0,
            'status' => $status,
        ];
    }

    /** @return array<int, array<string, mixed>> */
    public static function topProducts(Carbon $first, Carbon $last, int $limit = 5): array
    {
        $from = $first->copy()->startOfDay()->utc()->format('Y-m-d H:i:s');
        $to = $last->copy()->endOfDay()->utc()->format('Y-m-d H:i:s');

        return DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->join('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')
            ->whereBetween('s.created_at', [$from, $to])
            ->groupBy('p.id', 'p.name')
            ->orderByRaw('SUM(si.total - si.unit_cost_snapshot * si.quantity) DESC')
            ->limit($limit)
            ->get(['p.name', DB::raw('SUM(COALESCE(si.unit_qty, si.quantity)) as qty'), DB::raw('SUM(si.total) as sales'), DB::raw('SUM(si.total - si.unit_cost_snapshot * si.quantity) as profit')])
            ->map(fn ($r) => ['name' => $r->name, 'qty' => (int) $r->qty, 'sales' => round((float) $r->sales, 2), 'profit' => round((float) $r->profit, 2)])->all();
    }

    /** @return array<int, array<string, mixed>> */
    public static function topCustomers(Carbon $first, Carbon $last, int $limit = 5): array
    {
        $from = $first->copy()->startOfDay()->utc()->format('Y-m-d H:i:s');
        $to = $last->copy()->endOfDay()->utc()->format('Y-m-d H:i:s');

        return DB::table('inventory_sales as s')
            ->join('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')
            ->whereBetween('s.created_at', [$from, $to])
            ->groupBy('c.id', 'c.name')
            ->orderByRaw('SUM(s.total) DESC')
            ->limit($limit)
            ->get(['c.name', DB::raw('COUNT(*) as visits'), DB::raw('SUM(s.total) as spent')])
            ->map(fn ($r) => ['name' => $r->name, 'purchases' => (int) $r->visits, 'spent' => round((float) $r->spent, 2)])->all();
    }

    /**
     * Goods on the shelf that have not sold for 30 days, with the money tied up in them: where stock is sleeping.
     *
     * @return array<int, array<string, mixed>>
     */
    public static function slowStock(int $limit = 6): array
    {
        $since = now()->subDays(30)->format('Y-m-d H:i:s');
        $sold = DB::table('inventory_sale_items as si')->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->whereNull('s.cancelled_at')->where('s.created_at', '>=', $since)->select('si.product_id');

        return DB::table('inventory_products as p')
            ->where('p.is_service', false)->where('p.quantity', '>', 0)
            ->whereNotIn('p.id', $sold)
            ->orderByRaw('p.quantity * p.cost_price DESC')
            ->limit($limit)
            ->get(['p.name', 'p.quantity', DB::raw('p.quantity * p.cost_price as value')])
            ->map(fn ($r) => ['name' => $r->name, 'quantity' => (int) $r->quantity, 'value' => round((float) $r->value, 2)])->all();
    }

    /**
     * Who owes the business most, by name: customers' credit sales and the old debts together.
     *
     * @return array<int, array<string, mixed>>
     */
    public static function debtors(int $limit = 8): array
    {
        $rows = [];
        foreach (DB::table('inventory_sales as s')->join('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->whereNull('s.cancelled_at')->whereIn('s.payment_status', ['debt', 'partial'])
            ->groupBy('c.id', 'c.name')
            ->get(['c.id', 'c.name', DB::raw('SUM(s.total - s.paid_total) as owed'), DB::raw('MIN(s.created_at) as since')]) as $r) {
            $rows[(int) $r->id] = ['name' => $r->name, 'owed' => (float) $r->owed, 'since' => (string) $r->since];
        }
        foreach (OpeningDebts::list(OpeningDebts::RECEIVABLE) as $d) {
            $id = $d['customer_id'] ?? (-1 * $d['id']);
            $rows[$id] = [
                'name' => $d['name'],
                'owed' => ($rows[$id]['owed'] ?? 0) + $d['left'],
                'since' => min($rows[$id]['since'] ?? $d['started_on'], $d['started_on']),
            ];
        }
        $today = Carbon::now(MonthlyFigures::TIMEZONE)->startOfDay();

        return collect($rows)->filter(fn ($r) => $r['owed'] > 0)->sortByDesc('owed')->take($limit)->map(fn ($r) => [
            'name' => $r['name'], 'owed' => round($r['owed'], 2),
            'days' => max(0, (int) Carbon::parse($r['since'], MonthlyFigures::TIMEZONE)->startOfDay()->diffInDays($today)),
        ])->values()->all();
    }
}
