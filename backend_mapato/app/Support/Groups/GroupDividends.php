<?php

namespace App\Support\Groups;

use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

/**
 * Dividends, by the formula the group chooses for each run (nothing is assumed):
 *
 *   base    closing  each member's savings (dividends included) at the end of the period
 *           average  their average savings over the period, day by day (a deposit late in the year counts for less)
 *   method  rate     rate% of the base (MEG's "2% of savings"); refused if the total would pass the approved profit
 *           share    the approved profit shared out in proportion to the base
 *
 * Only members active at the end of the period, who joined by then, take part. A run is PREPARED (a draft, every line shown) by whoever
 * prepares dividends, and APPROVED AND POSTED by someone else who approves them: each line becomes a verified `dividend` credit to that
 * member's savings, kept apart from deposits. A period is never paid twice: a run overlapping a posted one is refused.
 */
final class GroupDividends
{
    /**
     * Every member's savings movements (verified savings and dividends, in minus out) by day.
     *
     * @param  array<int, int>  $memberIds
     * @return array<int, array<string, float>> member id => [Y-m-d => change that day]
     */
    private static function movements(array $memberIds): array
    {
        $out = [];
        $rows = DB::table('group_transactions')->whereIn('member_id', $memberIds)->whereIn('category', ['savings', 'dividend'])
            ->where('status', GroupLedger::VERIFIED)->get(['member_id', 'direction', 'amount', 'verified_at']);
        foreach ($rows as $r) {
            $day = Carbon::parse((string) $r->verified_at)->toDateString();
            $out[(int) $r->member_id][$day] = ($out[(int) $r->member_id][$day] ?? 0) + ($r->direction === 'in' ? (float) $r->amount : -(float) $r->amount);
        }

        return $out;
    }

    /** The base of one member: closing balance at [to], or the average balance over [from]..[to]. @param array<string, float> $days */
    private static function base(array $days, string $from, string $to, string $base): float
    {
        ksort($days);
        if ($base === 'closing') {
            return round(array_sum(array_filter($days, fn ($d) => $d <= $to, ARRAY_FILTER_USE_KEY)), 2);
        }
        $balance = array_sum(array_filter($days, fn ($d) => $d < $from, ARRAY_FILTER_USE_KEY));
        $total = 0.0;
        $count = 0;
        for ($day = Carbon::parse($from); $day->toDateString() <= $to; $day->addDay()) {
            $balance += $days[$day->toDateString()] ?? 0;
            $total += $balance;
            $count++;
        }

        return $count === 0 ? 0.0 : round($total / $count, 2);
    }

    /** A posted run that overlaps [from]..[to], if any. */
    public static function overlapping(string $from, string $to, ?int $except = null): ?object
    {
        return DB::table('group_dividend_runs')->where('status', 'posted')->where('period_from', '<=', $to)->where('period_to', '>=', $from)
            ->when($except !== null, fn ($q) => $q->where('id', '!=', $except))->first();
    }

    /**
     * Work out a run and keep it as a draft with every member's line.
     *
     * @param  array{period_from: string, period_to: string, profit_pool: float, base: string, method: string, rate?: ?float, note?: ?string}  $d
     * @return int the run's id
     */
    public static function prepare(array $d, string $by): int
    {
        if (self::overlapping($d['period_from'], $d['period_to']) !== null) {
            throw new InvalidArgumentException('period_paid');
        }
        $members = DB::table('group_members')->where('status', GroupMembers::ACTIVE)
            ->where(fn ($q) => $q->whereNull('joined_on')->orWhere('joined_on', '<=', $d['period_to']))->pluck('id')->map(fn ($id) => (int) $id)->all();
        $moves = self::movements($members);
        $bases = [];
        foreach ($members as $m) {
            $b = self::base($moves[$m] ?? [], $d['period_from'], $d['period_to'], $d['base']);
            if ($b > 0) {
                $bases[$m] = $b;
            }
        }
        $pool = round((float) $d['profit_pool'], 2);
        $sum = array_sum($bases);
        $lines = [];
        foreach ($bases as $m => $b) {
            $amount = $d['method'] === 'rate'
                ? floor($b * (float) $d['rate'] / 100 * 100) / 100
                : ($sum > 0 ? floor($pool * $b / $sum * 100) / 100 : 0.0);
            $lines[$m] = ['base' => $b, 'amount' => $amount];
        }
        $total = round(array_sum(array_column($lines, 'amount')), 2);
        if ($total > $pool + 0.001) {
            throw new InvalidArgumentException('over_pool:' . $total);
        }

        return DB::transaction(function () use ($d, $by, $lines, $total, $pool) {
            $id = (int) DB::table('group_dividend_runs')->insertGetId([
                'period_from' => $d['period_from'], 'period_to' => $d['period_to'], 'profit_pool' => $pool, 'base' => $d['base'], 'method' => $d['method'],
                'rate' => $d['method'] === 'rate' ? (float) $d['rate'] : null, 'total' => $total, 'status' => 'draft', 'note' => $d['note'] ?? null,
                'prepared_by' => $by, 'created_at' => now(), 'updated_at' => now(),
            ]);
            foreach (array_chunk(array_map(fn ($m, $l) => ['run_id' => $id, 'member_id' => $m, 'base' => $l['base'], 'amount' => $l['amount']], array_keys($lines), $lines), 200) as $chunk) {
                DB::table('group_dividend_lines')->insert($chunk);
            }

            return $id;
        });
    }

    /** Approve and post a draft: each line becomes a verified dividend credit to that member's savings. */
    public static function post(object $run, string $by): void
    {
        if ($run->status !== 'draft') {
            throw new InvalidArgumentException('not_draft');
        }
        if ((string) $run->prepared_by === $by) {
            throw new InvalidArgumentException('own_run');
        }
        if (self::overlapping((string) $run->period_from, (string) $run->period_to, (int) $run->id) !== null) {
            throw new InvalidArgumentException('period_paid');
        }
        DB::transaction(function () use ($run, $by) {
            $done = DB::table('group_dividend_runs')->where('id', $run->id)->where('status', 'draft')->update([
                'status' => 'posted', 'approved_by' => $by, 'posted_at' => now(), 'updated_at' => now(),
            ]);
            if ($done === 0) {
                throw new InvalidArgumentException('not_draft');
            }
            $note = 'Dividend ' . $run->period_from . '..' . $run->period_to;
            foreach (DB::table('group_dividend_lines')->where('run_id', $run->id)->where('amount', '>', 0)->get() as $line) {
                $tx = (int) DB::table('group_transactions')->insertGetId([
                    'reference' => 'DIV-' . strtoupper(Str::random(8)),
                    'member_id' => (int) $line->member_id,
                    'category' => 'dividend',
                    'direction' => 'in',
                    'amount' => $line->amount,
                    'method' => 'other',
                    'paid_on' => now()->toDateString(),
                    'status' => GroupLedger::VERIFIED,
                    'note' => $note,
                    'submitted_by' => $run->prepared_by,
                    'submitted_at' => now(),
                    'verified_by' => $by,
                    'verified_at' => now(),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
                DB::table('group_dividend_lines')->where('id', $line->id)->update(['transaction_id' => $tx]);
            }
        });
    }

    /** @return array<string, mixed> */
    public static function payload(object $run, bool $lines = false): array
    {
        $out = [
            'id' => (int) $run->id,
            'period_from' => (string) $run->period_from,
            'period_to' => (string) $run->period_to,
            'profit_pool' => (float) $run->profit_pool,
            'base' => $run->base,
            'method' => $run->method,
            'rate' => $run->rate === null ? null : (float) $run->rate,
            'total' => (float) $run->total,
            'status' => $run->status,
            'note' => $run->note,
            'prepared_by_name' => $run->prepared_by_name ?? null,
            'approved_by_name' => $run->approved_by_name ?? null,
            'posted_at' => $run->posted_at === null ? null : (string) $run->posted_at,
        ];
        if ($lines) {
            $out['lines'] = DB::table('group_dividend_lines as l')->join('group_members as m', 'm.id', '=', 'l.member_id')->where('l.run_id', $run->id)
                ->orderByDesc('l.amount')->get(['l.member_id', 'm.full_name as name', 'm.member_number', 'l.base', 'l.amount'])
                ->map(fn ($l) => ['member_id' => (int) $l->member_id, 'name' => $l->name, 'member_number' => $l->member_number, 'base' => (float) $l->base, 'amount' => (float) $l->amount])
                ->values()->all();
        }

        return $out;
    }

    public static function query(): \Illuminate\Database\Query\Builder
    {
        return DB::table('group_dividend_runs as r')->leftJoin('users as p', 'p.id', '=', 'r.prepared_by')->leftJoin('users as a', 'a.id', '=', 'r.approved_by')
            ->select('r.*', 'p.name as prepared_by_name', 'a.name as approved_by_name');
    }
}
