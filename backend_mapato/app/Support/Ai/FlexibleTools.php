<?php

namespace App\Support\Ai;

use App\Models\User;
use App\Support\Inventory\MonthlyFigures;
use App\Support\Inventory\SalesVisibility;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The open-ended tools of the assistant: instead of one canned report per question, the person (through the AI) picks the period, what to
 * group by and what to look for, so "which product sold most on Fridays last quarter" or "compare October with September" can be worked out
 * from the records. They read through the same rules as the fixed tools: the business scope, the sales a person may see, and profit and cost
 * only for those who may see reports.
 */
final class FlexibleTools
{
    private const MAX_ROWS = 40;

    private const MAX_DAYS = 400;

    /** @return array{0: Carbon, 1: Carbon} the local first and last day asked for (this month so far when nothing is said), at most MAX_DAYS long */
    private static function range(array $args, string $from = 'from', string $to = 'to'): array
    {
        $today = now(MonthlyFigures::TIMEZONE)->startOfDay();
        $date = function (mixed $v, Carbon $else) {
            $v = is_string($v) ? trim($v) : '';
            try {
                return preg_match('/^\d{4}-\d{2}-\d{2}$/', $v) === 1 ? Carbon::createFromFormat('!Y-m-d', $v, MonthlyFigures::TIMEZONE) : $else;
            } catch (\Throwable) {
                return $else;
            }
        };
        $end = $date($args[$to] ?? null, $today)->startOfDay();
        $start = $date($args[$from] ?? null, $today->copy()->startOfMonth())->startOfDay();
        if ($start->gt($end)) {
            [$start, $end] = [$end, $start];
        }
        if ($start->diffInDays($end) > self::MAX_DAYS) {
            $start = $end->copy()->subDays(self::MAX_DAYS);
        }

        return [$start, $end];
    }

    private static function utc(Carbon $day, bool $endOfDay): string
    {
        return ($endOfDay ? $day->copy()->endOfDay() : $day->copy()->startOfDay())->utc()->format('Y-m-d H:i:s');
    }

    private static function limit(array $args): int
    {
        return max(1, min(self::MAX_ROWS, (int) ($args['limit'] ?? 15)));
    }

    private static function seesProfit(User $user): bool
    {
        return $user->hasInventoryPermission('inv_view_reports');
    }

    /** Sales (and what was sold), grouped the way the question needs, for any dates. */
    public static function salesAnalysis(array $args, User $user): array
    {
        [$start, $end] = self::range($args);
        $group = in_array($args['group_by'] ?? '', ['product', 'customer', 'day', 'weekday', 'month', 'staff', 'branch', 'payment_status', 'category', 'seller'], true) ? $args['group_by'] : 'product';
        $profit = self::seesProfit($user);

        $q = DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')
            ->whereBetween('s.created_at', [self::utc($start, false), self::utc($end, true)]);
        if (!SalesVisibility::seesAll($user)) {
            $q->where('s.created_by', $user->id);
        }

        $product = AssistantTools::text($args['product'] ?? '', 60);
        if ($product !== '') {
            $q->where('p.name', 'like', '%' . AssistantTools::like($product) . '%');
        }
        $customer = AssistantTools::text($args['customer'] ?? '', 60);
        if ($customer !== '') {
            $q->leftJoin('inventory_customers as cf', 'cf.id', '=', 's.customer_id')
                ->where(fn ($w) => $w->where('cf.name', 'like', '%' . AssistantTools::like($customer) . '%')->orWhere('s.customer_name_override', 'like', '%' . AssistantTools::like($customer) . '%'));
        }
        if (in_array($args['status'] ?? '', ['paid', 'debt', 'partial'], true)) {
            $q->where('s.payment_status', $args['status']);
        }

        // Local (Tanzanian) day for the day, weekday and month groupings: the records are kept in UTC.
        $local = DB::connection()->getDriverName() === 'sqlite' ? "datetime(s.created_at, '+3 hours')" : "DATE_ADD(s.created_at, INTERVAL 3 HOUR)";
        $sqlite = DB::connection()->getDriverName() === 'sqlite';
        $label = match ($group) {
            'product' => "COALESCE(p.name, '?')",
            'customer' => "COALESCE((SELECT c.name FROM inventory_customers c WHERE c.id = s.customer_id), s.customer_name_override, 'Walk-in')",
            'day' => ($sqlite ? "date({$local})" : "DATE({$local})"),
            'weekday' => ($sqlite ? "strftime('%w', {$local})" : "DAYOFWEEK({$local})"),
            'month' => ($sqlite ? "strftime('%Y-%m', {$local})" : "DATE_FORMAT({$local}, '%Y-%m')"),
            'staff' => "COALESCE(NULLIF(si.staff_name, ''), '-')",
            'branch' => "COALESCE((SELECT b.name FROM inventory_branches b WHERE b.id = s.branch_id), 'Main')",
            'payment_status' => 's.payment_status',
            'seller' => "COALESCE((SELECT u.name FROM users u WHERE u.id = s.created_by), '?')",
            default => "COALESCE((SELECT k.name FROM inventory_categories k WHERE k.id = p.category_id), p.category, '-')",
        };

        $select = [DB::raw('(' . $label . ') as label'), DB::raw('SUM(si.total) as sales'), DB::raw('SUM(si.quantity) as quantity'), DB::raw('COUNT(DISTINCT s.id) as sales_count')];
        if ($profit) {
            $select[] = DB::raw('SUM(si.total - si.unit_cost_snapshot * si.quantity) as profit');
        }
        $ordered = in_array($group, ['day', 'month', 'weekday'], true);
        $rows = $q->groupBy('label')
            ->when($ordered, fn ($x) => $x->orderBy('label'), fn ($x) => $x->orderByRaw($profit && ($args['sort_by'] ?? '') === 'profit' ? 'SUM(si.total - si.unit_cost_snapshot * si.quantity) DESC' : (($args['sort_by'] ?? '') === 'quantity' ? 'SUM(si.quantity) DESC' : 'SUM(si.total) DESC')))
            ->limit($ordered ? 400 : self::limit($args))->get($select);

        $names = [1 => 'Sunday', 2 => 'Monday', 3 => 'Tuesday', 4 => 'Wednesday', 5 => 'Thursday', 6 => 'Friday', 7 => 'Saturday'];
        $data = $rows->map(function ($r) use ($group, $profit, $names, $sqlite) {
            $label = (string) $r->label;
            if ($group === 'weekday') {
                $n = $sqlite ? ((int) $label) + 1 : (int) $label;
                $label = $names[$n] ?? $label;
            }
            $row = ['name' => $label, 'sales' => round((float) $r->sales, 2), 'quantity' => (int) $r->quantity, 'number_of_sales' => (int) $r->sales_count];

            return $profit ? $row + ['profit' => round((float) $r->profit, 2)] : $row;
        })->all();
        $totals = ['sales' => round(array_sum(array_column($data, 'sales')), 2), 'quantity' => array_sum(array_column($data, 'quantity'))];
        if ($profit) {
            $totals['profit'] = round(array_sum(array_column($data, 'profit')), 2);
        }

        return [
            'data' => ['currency' => 'TSh', 'from' => $start->toDateString(), 'to' => $end->toDateString(), 'grouped_by' => $group, 'totals_of_rows_shown' => $totals, 'rows' => $data, 'profit_hidden' => !$profit],
            'card' => $data === [] || $ordered ? null : ['type' => 'rows', 'title' => ucfirst($group) . ' ' . $start->toDateString() . ' - ' . $end->toDateString(), 'rows' => array_map(
                fn ($r) => ['title' => $r['name'], 'value' => AssistantTools::tsh($r['sales']), 'note' => $r['quantity'] . ' sold'], array_slice($data, 0, 10)
            )],
        ];
    }

    /** Two periods side by side: sales, cost, spending and profit for each, with the change. */
    public static function comparePeriods(array $args, User $user): array
    {
        [$a1, $a2] = self::range($args, 'from', 'to');
        [$b1, $b2] = self::range($args, 'compare_from', 'compare_to');
        if (empty($args['compare_from']) || empty($args['compare_to'])) {
            $days = $a1->diffInDays($a2) + 1;
            $b2 = $a1->copy()->subDay();
            $b1 = $b2->copy()->subDays($days - 1);
        }
        $profit = self::seesProfit($user);
        $one = function (Carbon $from, Carbon $to) use ($user, $profit) {
            $s = DB::table('inventory_sales as s')->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')
                ->whereBetween('s.created_at', [self::utc($from, false), self::utc($to, true)]);
            if (!SalesVisibility::seesAll($user)) {
                $s->where('s.created_by', $user->id);
            }
            $sales = (float) (clone $s)->sum('s.total');
            $out = ['from' => $from->toDateString(), 'to' => $to->toDateString(), 'sales' => round($sales, 2), 'number_of_sales' => (int) (clone $s)->count()];
            if ($profit) {
                $cost = (float) DB::table('inventory_sale_items as si')->join('inventory_sales as s', 's.id', '=', 'si.sale_id')->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')
                    ->whereBetween('s.created_at', [self::utc($from, false), self::utc($to, true)])->sum(DB::raw('si.unit_cost_snapshot * si.quantity'));
                $exp = (float) DB::table('inventory_expenses')->whereBetween('expense_date', [$from->toDateString(), $to->toDateString()])
                    ->when(Schema::hasColumn('inventory_expenses', 'status'), fn ($q) => $q->where('status', 'approved'))
                    ->when(Schema::hasColumn('inventory_expenses', 'is_personal'), fn ($q) => $q->where('is_personal', false))->sum('amount');
                $out += ['cost_of_goods' => round($cost, 2), 'gross_profit' => round($sales - $cost, 2), 'expenses' => round($exp, 2), 'profit_after_expenses' => round($sales - $cost - $exp, 2)];
            }

            return $out;
        };
        $now = $one($a1, $a2);
        $before = $one($b1, $b2);
        $change = [];
        foreach ($now as $k => $v) {
            if (is_numeric($v) && isset($before[$k]) && !in_array($k, ['from', 'to'], true)) {
                $change[$k] = ['now' => $v, 'before' => $before[$k], 'percent' => $before[$k] != 0 ? round(($v - $before[$k]) / abs($before[$k]) * 100, 1) : null];
            }
        }

        return ['data' => ['currency' => 'TSh', 'period' => $now, 'compared_with' => $before, 'change' => $change, 'profit_hidden' => !$profit], 'card' => ['type' => 'rows', 'title' => 'Sales', 'rows' => [
            ['title' => $now['from'] . ' - ' . $now['to'], 'value' => AssistantTools::tsh($now['sales'])],
            ['title' => $before['from'] . ' - ' . $before['to'], 'value' => AssistantTools::tsh($before['sales'])],
        ]]];
    }

    /** Stock questions: low, sleeping (not sold for N days), what is worth most on the shelf, what moves fastest. */
    public static function stockReport(array $args, User $user): array
    {
        $kind = in_array($args['kind'] ?? '', ['low', 'sleeping', 'value', 'fast_moving', 'out_of_stock'], true) ? $args['kind'] : 'sleeping';
        $days = max(7, min(365, (int) ($args['days'] ?? 60)));
        $cost = $user->hasInventoryPermission('inv_view_reports') || $user->hasInventoryPermission('inv_manage_products');
        $limit = self::limit($args);
        $since = now()->subDays($days)->format('Y-m-d H:i:s');

        $goods = DB::table('inventory_products as p')->where('p.status', 'active')->where('p.is_service', false);
        $sold = fn () => DB::table('inventory_sale_items as si')->join('inventory_sales as s', 's.id', '=', 'si.sale_id')->whereNull('s.cancelled_at')->where('s.created_at', '>=', $since);

        if ($kind === 'fast_moving') {
            $rows = $sold()->join('inventory_products as p', 'p.id', '=', 'si.product_id')->where('p.is_service', false)->groupBy('p.id', 'p.name', 'p.quantity', 'p.unit')
                ->orderByRaw('SUM(si.quantity) DESC')->limit($limit)->get(['p.name', 'p.unit', 'p.quantity', DB::raw('SUM(si.quantity) as sold')])
                ->map(fn ($r) => ['name' => $r->name, 'sold_in_period' => (int) $r->sold, 'in_stock' => (int) $r->quantity, 'unit' => $r->unit, 'days_of_stock_left' => $r->sold > 0 ? round($r->quantity / ($r->sold / $days), 1) : null])->all();
        } else {
            if ($kind === 'low') {
                $goods->whereColumn('p.quantity', '<=', 'p.min_stock')->where('p.quantity', '>', 0);
            } elseif ($kind === 'out_of_stock') {
                $goods->where('p.quantity', '<=', 0);
            } elseif ($kind === 'sleeping') {
                $goods->where('p.quantity', '>', 0)->whereNotIn('p.id', $sold()->select('si.product_id'));
            } else {
                $goods->where('p.quantity', '>', 0);
            }
            $order = $kind === 'value' && $cost ? 'p.quantity * p.cost_price DESC' : 'p.quantity DESC';
            $rows = $goods->orderByRaw($order)->limit($limit)->get(['p.name', 'p.unit', 'p.quantity', 'p.min_stock', 'p.selling_price', 'p.cost_price'])->map(function ($p) use ($cost) {
                $row = ['name' => $p->name, 'in_stock' => (int) $p->quantity, 'unit' => $p->unit, 'minimum_stock' => (int) $p->min_stock, 'selling_price' => round((float) $p->selling_price, 2)];

                return $cost ? $row + ['cost_price' => round((float) $p->cost_price, 2), 'value_at_cost' => round($p->quantity * (float) $p->cost_price, 2)] : $row;
            })->all();
        }

        return ['data' => ['kind' => $kind, 'days_looked_back' => $days, 'currency' => 'TSh', 'products' => $rows, 'cost_hidden' => !$cost], 'card' => $rows === [] ? null : ['type' => 'rows', 'title' => 'Stock: ' . $kind, 'rows' => array_map(
            fn ($r) => ['title' => $r['name'], 'value' => $r['in_stock'] . ' ' . ($r['unit'] ?? ''), 'note' => isset($r['sold_in_period']) ? $r['sold_in_period'] . ' sold' : (isset($r['value_at_cost']) ? AssistantTools::tsh($r['value_at_cost']) : '')], array_slice($rows, 0, 10)
        )]];
    }

    /** Spending for any dates: by kind, or the single entries, with a word to look for. */
    public static function expensesDetail(array $args): array
    {
        [$start, $end] = self::range($args);
        $q = DB::table('inventory_expenses')->whereBetween('expense_date', [$start->toDateString(), $end->toDateString()])
            ->when(Schema::hasColumn('inventory_expenses', 'status'), fn ($x) => $x->where('status', 'approved'))
            ->when(Schema::hasColumn('inventory_expenses', 'is_personal'), fn ($x) => $x->where('is_personal', !empty($args['personal'])));
        $search = AssistantTools::text($args['search'] ?? '', 60);
        if ($search !== '') {
            $q->where(fn ($w) => $w->where('category', 'like', '%' . AssistantTools::like($search) . '%')->orWhere('description', 'like', '%' . AssistantTools::like($search) . '%'));
        }
        $total = round((float) (clone $q)->sum('amount'), 2);
        $byKind = (clone $q)->groupBy('category')->orderByRaw('SUM(amount) DESC')->limit(self::MAX_ROWS)->get(['category', DB::raw('SUM(amount) as total'), DB::raw('COUNT(*) as entries')])
            ->map(fn ($r) => ['kind' => (string) $r->category, 'total' => round((float) $r->total, 2), 'entries' => (int) $r->entries])->all();
        $latest = (clone $q)->orderByDesc('expense_date')->orderByDesc('id')->limit(self::limit($args))->get(['expense_date', 'category', 'description', 'amount'])
            ->map(fn ($r) => ['date' => (string) $r->expense_date, 'kind' => (string) $r->category, 'note' => AssistantTools::text($r->description ?? '', 80), 'amount' => round((float) $r->amount, 2)])->all();

        return ['data' => ['currency' => 'TSh', 'from' => $start->toDateString(), 'to' => $end->toDateString(), 'personal_spending' => !empty($args['personal']), 'total' => $total, 'by_kind' => $byKind, 'latest_entries' => $latest], 'card' => $byKind === [] ? null : ['type' => 'rows', 'title' => 'Spending', 'rows' => array_map(
            fn ($r) => ['title' => $r['kind'], 'value' => AssistantTools::tsh($r['total']), 'note' => $r['entries'] . ' entries'], array_slice($byKind, 0, 10)
        )]];
    }
}
