<?php

namespace App\Support\Salon;

use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * How each stylist did, worked out in one place: what their services brought in (after the share of the sale's discount each carried),
 * how many visits, services and clients, what a visit is worth on average, how many of their clients had been before, how they rank, and how
 * they did against the period just before and against the target the owner set for the month. The results page, the export and the
 * assistant read the same figures.
 */
final class StylistPerformance
{
    /**
     * One period, per stylist.
     *
     * @return array<string, array<string, mixed>> by staff id
     */
    public static function period(string $from, string $to, ?string $onlyStaff = null, ?int $branch = null): array
    {
        $commission = Schema::hasColumn('inventory_sale_items', 'commission_amount') ? 'si.commission_amount' : '0';
        $rows = self::lines($from, $to, $branch)
            ->when($onlyStaff !== null, fn ($q) => $q->where('si.staff_id', $onlyStaff))
            ->groupBy('si.staff_id')
            ->selectRaw(
                'si.staff_id as staff_id,
                 MAX(si.staff_name) as staff_name,
                 SUM(COALESCE(si.unit_qty, si.quantity)) as services,
                 COALESCE(SUM(si.total - COALESCE(s.discount * si.total / NULLIF(s.subtotal, 0), 0)), 0) as revenue,
                 COALESCE(SUM(COALESCE(s.discount * si.total / NULLIF(s.subtotal, 0), 0)), 0) as discount,
                 COALESCE(SUM(' . $commission . '), 0) as commission,
                 COUNT(DISTINCT s.id) as visits,
                 COUNT(DISTINCT s.customer_id) as clients'
            )
            ->get();

        $out = [];
        foreach ($rows as $r) {
            $revenue = round((float) $r->revenue, 2);
            $visits = (int) $r->visits;
            // A service with no stylist named is kept as a line of its own (no id, no name), as it always was.
            $out[(string) $r->staff_id] = [
                'staff_id' => $r->staff_id === null ? null : (string) $r->staff_id,
                'name' => $r->staff_name === null ? null : (string) $r->staff_name,
                'services' => (int) $r->services,
                'revenue' => $revenue,
                'discount' => round((float) $r->discount, 2),
                'commission' => round((float) $r->commission, 2),
                'visits' => $visits,
                'clients' => (int) $r->clients,
                'avg_ticket' => $visits > 0 ? round($revenue / $visits, 2) : 0.0,
                'return_rate' => self::returnRate((string) $r->staff_id, $from, $to, $branch),
            ];
        }

        return $out;
    }

    /**
     * The share of this stylist's named clients, in the period, who had had a service before it started (with anyone): how many of
     * them come back. Null when nobody was named, so there is nothing to say.
     */
    private static function returnRate(string $staffId, string $from, string $to, ?int $branch): ?float
    {
        $clients = self::lines($from, $to, $branch)->where('si.staff_id', $staffId)->whereNotNull('s.customer_id')->distinct()->pluck('s.customer_id')->all();
        if ($clients === []) {
            return null;
        }
        $before = DB::table('inventory_sale_items as si')->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->whereNull('s.cancelled_at')->where('si.is_service', true)
            ->whereIn('s.customer_id', $clients)->whereDate('s.created_at', '<', $from)
            ->distinct()->pluck('s.customer_id')->count();

        return round($before / count($clients) * 100, 1);
    }

    private static function lines(string $from, string $to, ?int $branch)
    {
        return DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->whereNull('s.cancelled_at')
            ->where('si.is_service', true)
            ->whereDate('s.created_at', '>=', $from)
            ->whereDate('s.created_at', '<=', $to)
            ->when($branch !== null, fn ($q) => $q->where('s.branch_id', $branch));
    }

    /** The period of the same length that ends the day before [from]. @return array{0: string, 1: string} */
    public static function before(string $from, string $to): array
    {
        $start = Carbon::parse($from)->startOfDay();
        $days = (int) round(abs($start->diffInDays(Carbon::parse($to)->startOfDay()))) + 1;

        return [$start->copy()->subDays($days)->toDateString(), $start->copy()->subDay()->toDateString()];
    }

    /** Percent change from [before] to [now]; null when there was nothing before to compare with. */
    public static function change(float|int|null $now, float|int|null $before): ?float
    {
        if ($before === null || (float) $before == 0.0) {
            return null;
        }

        return round(((float) $now - (float) $before) / abs((float) $before) * 100, 1);
    }

    /**
     * The results for a period, with the one before it, the changes, the ranking and each person's target.
     *
     * @return array<string, mixed>
     */
    public static function report(string $from, string $to, bool $everyone, ?string $viewerId, ?int $branch, ?string $today = null): array
    {
        $only = $everyone ? null : $viewerId;
        [$pFrom, $pTo] = self::before($from, $to);
        $now = self::period($from, $to, $only, $branch);
        $then = self::period($pFrom, $pTo, $only, $branch);

        // Someone who worked before but not in this period still has a line (a drop to nothing is worth seeing).
        $ids = array_values(array_unique(array_merge(array_keys($now), array_keys($then))));
        $targetMonth = Carbon::parse($to)->format('Y-m');
        $targets = self::targets($targetMonth, $today ?? $to);

        $zero = ['services' => 0, 'revenue' => 0.0, 'discount' => 0.0, 'commission' => 0.0, 'visits' => 0, 'clients' => 0, 'avg_ticket' => 0.0, 'return_rate' => null];
        $rows = [];
        foreach ($ids as $id) {
            $row = ($now[$id] ?? ['staff_id' => $then[$id]['staff_id'] ?? null, 'name' => $then[$id]['name'] ?? null] + $zero);
            $prev = $then[$id] ?? ($zero + ['staff_id' => $row['staff_id'], 'name' => $row['name']]);
            $row['previous'] = ['revenue' => $prev['revenue'], 'visits' => $prev['visits'], 'services' => $prev['services'], 'clients' => $prev['clients'], 'avg_ticket' => $prev['avg_ticket']];
            $row['change'] = [
                'revenue' => self::change($row['revenue'], $prev['revenue']),
                'visits' => self::change($row['visits'], $prev['visits']),
                'services' => self::change($row['services'], $prev['services']),
                'clients' => self::change($row['clients'], $prev['clients']),
                'avg_ticket' => self::change($row['avg_ticket'], $prev['avg_ticket']),
            ];
            $row['target'] = $targets[$id] ?? null;
            $rows[] = $row;
        }

        usort($rows, fn ($a, $b) => $b['revenue'] <=> $a['revenue'] ?: strcmp((string) $a['name'], (string) $b['name']));
        $total = array_sum(array_column($rows, 'revenue'));
        foreach ($rows as $i => &$row) {
            // The ranking compares everyone, so someone who sees only their own line has nobody to be ranked against.
            $row['rank'] = $everyone && $row['revenue'] > 0 ? $i + 1 : null;
            $row['share'] = $total > 0 ? round($row['revenue'] / $total * 100, 1) : 0.0;
        }
        unset($row);

        $sum = fn (string $k, array $set) => array_sum(array_column($set, $k));
        $prevRows = array_values($then);
        $visits = $sum('visits', $rows);
        $revenue = $sum('revenue', $rows);
        $prevVisits = $sum('visits', $prevRows);
        $prevRevenue = $sum('revenue', $prevRows);
        $avg = $visits > 0 ? round($revenue / $visits, 2) : 0.0;
        $prevAvg = $prevVisits > 0 ? round($prevRevenue / $prevVisits, 2) : 0.0;

        return [
            'from' => $from, 'to' => $to, 'previous_from' => $pFrom, 'previous_to' => $pTo, 'target_month' => $targetMonth,
            'totals' => [
                'services' => (int) $sum('services', $rows),
                'revenue' => round($revenue, 2),
                'commission' => round($sum('commission', $rows), 2),
                'discount' => round($sum('discount', $rows), 2),
                'visits' => (int) $visits,
                'avg_ticket' => $avg,
                'previous' => ['revenue' => round($prevRevenue, 2), 'visits' => (int) $prevVisits, 'services' => (int) $sum('services', $prevRows), 'avg_ticket' => $prevAvg],
                'change' => ['revenue' => self::change($revenue, $prevRevenue), 'visits' => self::change($visits, $prevVisits), 'services' => self::change($sum('services', $rows), $sum('services', $prevRows)), 'avg_ticket' => self::change($avg, $prevAvg)],
            ],
            'stylists' => $rows,
        ];
    }

    /**
     * What each person was set to bring in for the month, how much they have brought in so far, and whether that is ahead of or behind
     * the pace of the month (the share of the target reached against the share of the days gone).
     *
     * @return array<string, array<string, mixed>> by staff id
     */
    public static function targets(string $month, ?string $today = null): array
    {
        if (!Schema::hasTable('inventory_staff_targets')) {
            return [];
        }
        $set = DB::table('inventory_staff_targets')->where('month', $month)->get(['staff_id', 'revenue_target']);
        if ($set->isEmpty()) {
            return [];
        }
        $first = Carbon::createFromFormat('!Y-m', $month);
        $last = $first->copy()->endOfMonth();
        $asOf = Carbon::parse($today ?? $last->toDateString())->startOfDay();
        $through = $asOf->lt($last) ? $asOf : $last->copy()->startOfDay();
        $days = $first->daysInMonth;
        $gone = $through->lt($first) ? 0 : (int) round(abs($first->copy()->startOfDay()->diffInDays($through))) + 1;
        $expected = round(min($gone, $days) / $days * 100, 1);
        $done = self::period($first->toDateString(), $through->toDateString());

        $out = [];
        foreach ($set as $t) {
            $amount = round((float) $t->revenue_target, 2);
            $achieved = $done[(string) $t->staff_id]['revenue'] ?? 0.0;
            $percent = $amount > 0 ? round($achieved / $amount * 100, 1) : 0.0;
            $out[(string) $t->staff_id] = [
                'month' => $month, 'amount' => $amount, 'achieved' => $achieved, 'percent' => $percent, 'expected_percent' => $expected,
                // ahead: more than the days gone say it should be; behind: well short of it.
                'pace' => $percent >= 100 ? 'reached' : ($percent >= $expected ? 'ahead' : ($percent >= $expected * 0.85 ? 'on_track' : 'behind')),
            ];
        }

        return $out;
    }
}
