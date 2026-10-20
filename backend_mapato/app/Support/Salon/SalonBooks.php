<?php

namespace App\Support\Salon;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The salon's cashbook: for each place money is kept (cash, mobile money, bank) what came in, what went out and what
 * should be held at the end of each day, from the books the app already keeps.
 *
 * In: what clients paid (sale payments), deposits the salon kept, and what the owner put in (and the opening balance).
 * Out: approved expenses, salaries/commission/advances paid to staff, approved refunds (assumed paid in cash: a refund does
 * not say how) and what the owner took out. A deposit held for a coming visit is not here until it is settled.
 */
final class SalonBooks
{
    public const BUCKETS = ['cash', 'mobile', 'bank'];

    /** Cash, mobile money (M-Pesa, Mixx, Airtel, HaloPesa...) or bank. */
    public static function bucket(?string $method): string
    {
        $m = strtolower(trim((string) $method));
        if ($m === '' || $m === 'cash') {
            return 'cash';
        }

        return in_array($m, ['bank', 'bank_transfer', 'cheque'], true) ? 'bank' : 'mobile';
    }

    /**
     * Money in and out per day and place between two days (inclusive).
     *
     * @return array<string, array<string, array{in: float, out: float}>> [date][bucket]
     */
    public static function daily(string $from, string $to): array
    {
        $days = [];
        $add = function (?string $date, ?string $method, string $dir, float $amount) use (&$days) {
            if ($date === null || $amount == 0.0) {
                return;
            }
            $d = substr($date, 0, 10);
            $b = self::bucket($method);
            $days[$d][$b] ??= ['in' => 0.0, 'out' => 0.0];
            $days[$d][$b][$dir] += $amount;
        };

        DB::table('inventory_sale_payments as p')
            ->join('inventory_sales as s', 's.id', '=', 'p.sale_id')
            ->whereNull('s.cancelled_at')
            ->whereDate('p.paid_at', '>=', $from)->whereDate('p.paid_at', '<=', $to)
            ->groupBy(DB::raw('DATE(p.paid_at)'), DB::raw('COALESCE(p.method_extended, p.method)'))
            ->selectRaw('DATE(p.paid_at) as d, COALESCE(p.method_extended, p.method) as m, SUM(p.amount) as a')
            ->get()->each(fn ($r) => $add((string) $r->d, $r->m, 'in', (float) $r->a));

        if (Schema::hasColumn('inventory_appointments', 'deposit_status')) {
            DB::table('inventory_appointments')->where('deposit_status', 'forfeited')
                ->whereDate('deposit_resolved_at', '>=', $from)->whereDate('deposit_resolved_at', '<=', $to)
                ->groupBy(DB::raw('DATE(deposit_resolved_at)'), 'deposit_method')
                ->selectRaw('DATE(deposit_resolved_at) as d, deposit_method as m, SUM(deposit_amount) as a')
                ->get()->each(fn ($r) => $add((string) $r->d, $r->m, 'in', (float) $r->a));
        }

        $expenses = DB::table('inventory_expenses')->whereBetween('expense_date', [$from, $to]);
        if (Schema::hasColumn('inventory_expenses', 'status')) {
            $expenses->where('status', 'approved');
        }
        $payCol = Schema::hasColumn('inventory_expenses', 'payment_method') ? 'payment_method' : null;
        $expenses->get()->each(fn ($r) => $add((string) $r->expense_date, $payCol ? $r->{$payCol} : 'cash', 'out', (float) $r->amount));

        if (Schema::hasTable('inventory_staff_payouts')) {
            DB::table('inventory_staff_payouts')->whereBetween('paid_on', [$from, $to])
                ->get()->each(fn ($r) => $add((string) $r->paid_on, $r->method, 'out', (float) $r->amount));
        }

        if (Schema::hasTable('inventory_sale_returns')) {
            DB::table('inventory_sale_returns')->where('status', 'approved')->where('type', 'return')
                ->whereDate('approved_at', '>=', $from)->whereDate('approved_at', '<=', $to)
                ->get()->each(fn ($r) => $add((string) $r->approved_at, 'cash', 'out', (float) $r->amount));
        }

        DB::table('inventory_cash_moves')->whereBetween('moved_on', [$from, $to])->get()->each(
            fn ($r) => $add((string) $r->moved_on, $r->method, $r->kind === 'owner_withdrawal' ? 'out' : 'in', (float) $r->amount)
        );

        ksort($days);

        return $days;
    }

    /**
     * The book for a period: per place the opening balance, in, out and closing, and each day with money moving.
     *
     * @return array{from: string, to: string, places: array<string, array<string, mixed>>, total: array<string, float>}
     */
    public static function book(string $from, string $to): array
    {
        $before = date('Y-m-d', strtotime($from . ' -1 day'));
        $opening = array_fill_keys(self::BUCKETS, 0.0);
        foreach (self::daily('1970-01-01', $before) as $perPlace) {
            foreach ($perPlace as $b => $v) {
                $opening[$b] += $v['in'] - $v['out'];
            }
        }

        $counts = DB::table('inventory_cash_counts')->whereBetween('counted_on', [$from, $to])->orderBy('id')->get();
        $daily = self::daily($from, $to);

        $places = [];
        foreach (self::BUCKETS as $b) {
            $running = $opening[$b];
            $in = $out = 0.0;
            $rows = [];
            $dates = array_unique(array_merge(
                array_keys(array_filter($daily, fn ($d) => isset($d[$b]))),
                $counts->where('method', $b)->map(fn ($c) => substr((string) $c->counted_on, 0, 10))->all()
            ));
            sort($dates);
            foreach ($dates as $d) {
                $m = $daily[$d][$b] ?? ['in' => 0.0, 'out' => 0.0];
                $running += $m['in'] - $m['out'];
                $in += $m['in'];
                $out += $m['out'];
                $count = $counts->where('method', $b)->filter(fn ($c) => substr((string) $c->counted_on, 0, 10) === $d)->last();
                $rows[] = [
                    'date' => $d,
                    'in' => SalonFinance::money($m['in']),
                    'out' => SalonFinance::money($m['out']),
                    'closing' => SalonFinance::money($running),
                    'count' => $count === null ? null : [
                        'counted' => SalonFinance::money($count->counted),
                        'expected' => SalonFinance::money($count->expected),
                        'difference' => SalonFinance::money($count->difference),
                        'note' => $count->note,
                    ],
                ];
            }
            $places[$b] = [
                'opening' => SalonFinance::money($opening[$b]),
                'in' => SalonFinance::money($in),
                'out' => SalonFinance::money($out),
                'closing' => SalonFinance::money($opening[$b] + $in - $out),
                'days' => $rows,
            ];
        }

        return [
            'from' => $from,
            'to' => $to,
            'places' => $places,
            'total' => [
                'opening' => SalonFinance::money(array_sum($opening)),
                'closing' => SalonFinance::money(array_sum(array_map(fn ($p) => $p['closing'], $places))),
            ],
        ];
    }
}
