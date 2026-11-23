<?php

namespace App\Support\Groups;

use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * A group's loans: who may borrow and how much, the instalments, and where each loan stands.
 *
 *   awaiting_guarantors -> under_review -> recommended -> approved -> active (when its disbursement is verified)
 *   any of the first four -> rejected (with the reason) or cancelled (by the borrower)
 *
 * Eligibility: an active member; the project shares paid when the group asks for them before borrowing; the group's loan terms set (rate
 * and method are never assumed). The ceiling is the member's savings x the group's multiplier, less what they still owe on other loans;
 * the screens show the sum, and an approval can only lower the amount.
 *
 * What was repaid is never stored on the loan: it is the verified repayments (in minus out), applied interest first then principal,
 * instalment by instalment. So a loan is REPAID when nothing is left, OVERDUE when an instalment past its date is not covered.
 */
final class GroupLoans
{
    public const OPEN_STATUSES = ['awaiting_guarantors', 'under_review', 'recommended', 'approved'];

    /** How often a loan is repaid. `custom` is every N days (the group sets N). */
    public const REPAYMENTS = ['daily', 'weekly', 'every_2_weeks', 'monthly', 'every_2_months', 'quarterly', 'every_6_months', 'custom'];

    /** More instalments than this is a mistake (a year of daily payments is 365). */
    public const MAX_INSTALMENTS = 400;

    public static function newReference(): string
    {
        do {
            $ref = 'LN-' . strtoupper(Str::random(6));
        } while (DB::table('group_loans')->where('reference', $ref)->exists());

        return $ref;
    }

    /** @return array{rate: ?float, method: ?string, max_months: int, guarantors: int, repayment: string, repayment_days: int} the group's loan terms now */
    public static function terms(): array
    {
        $s = GroupSettings::all();

        return [
            'rate' => $s['loan_interest_rate'] === '' ? null : (float) $s['loan_interest_rate'],
            'method' => $s['loan_interest_method'] === '' ? null : $s['loan_interest_method'],
            'max_months' => (int) $s['loan_max_months'],
            'guarantors' => (int) $s['loan_guarantors'],
            'repayment' => $s['loan_repayment'],
            'repayment_days' => (int) $s['loan_repayment_days'],
        ];
    }

    /**
     * The length of one repayment period: whole months for the month-based rhythms, days for the others.
     *
     * @return array{months: int, days: int} one of the two is 0
     */
    public static function period(string $every, ?int $days = null): array
    {
        return match ($every) {
            'daily' => ['months' => 0, 'days' => 1],
            'weekly' => ['months' => 0, 'days' => 7],
            'every_2_weeks' => ['months' => 0, 'days' => 14],
            'every_2_months' => ['months' => 2, 'days' => 0],
            'quarterly' => ['months' => 3, 'days' => 0],
            'every_6_months' => ['months' => 6, 'days' => 0],
            'custom' => ['months' => 0, 'days' => max(1, min(365, (int) ($days ?? 30)))],
            default => ['months' => 1, 'days' => 0],
        };
    }

    /** How many instalments a loan of [months] has at this rhythm. */
    public static function instalmentCount(int $months, string $every = 'monthly', ?int $days = null, ?string $start = null): int
    {
        $p = self::period($every, $days);
        if ($p['months'] > 0) {
            return max(1, intdiv($months, $p['months']));
        }
        $from = Carbon::parse($start ?? now()->toDateString());
        $total = (int) $from->diffInDays($from->copy()->addMonthsNoOverflow($months));

        return max(1, intdiv($total, $p['days']));
    }

    /**
     * Can [memberId] borrow, and up to how much? Reasons are codes the app words.
     *
     * @return array<string, mixed>
     */
    public static function eligibility(int $memberId, ?int $exceptLoan = null): array
    {
        $member = DB::table('group_members')->where('id', $memberId)->first();
        $balances = GroupLedger::balances($memberId);
        $multiplier = (float) GroupSettings::get('loan_multiplier');
        $savings = max(0, (float) ($balances['savings'] ?? 0));
        $owed = 0.0;
        foreach (DB::table('group_loans')->where('member_id', $memberId)->where('status', 'active')->when($exceptLoan, fn ($q) => $q->where('id', '!=', $exceptLoan))->get() as $loan) {
            $owed += self::position($loan)['outstanding_principal'];
        }
        $terms = self::terms();
        $shareRule = GroupSettings::get('shares_required_for');
        $sharesNeeded = in_array($shareRule, ['loans', 'membership'], true) ? GroupSettings::money('share_amount') : 0.0;

        $reasons = [];
        if ($member === null || $member->status !== GroupMembers::ACTIVE) {
            $reasons[] = 'not_active';
        }
        if ($terms['rate'] === null || $terms['method'] === null) {
            $reasons[] = 'terms_not_set';
        }
        if (($balances['shares'] ?? 0) + 0.001 < $sharesNeeded) {
            $reasons[] = 'shares_unpaid';
        }
        $ceiling = max(0, round($savings * $multiplier - $owed, 2));
        if ($ceiling <= 0) {
            $reasons[] = 'no_ceiling';
        }

        return [
            'savings' => $savings,
            'multiplier' => $multiplier,
            'other_loans' => round($owed, 2),
            'ceiling' => $ceiling,
            'shares_paid' => (float) ($balances['shares'] ?? 0),
            'shares_needed' => $sharesNeeded,
            'terms' => $terms,
            'eligible' => $reasons === [],
            'reasons' => $reasons,
        ];
    }

    /**
     * The instalments of [principal] over [months] at [rate]% a month, one every [every] (daily, weekly, ... or every N days): flat (the same
     * share of the whole interest each time) or reducing (equal instalments; interest on what is still owed, for the length of the period).
     * The first instalment falls one period after [start] (a daily loan taken today is first paid tomorrow); the last falls on the day the loan
     * ends and takes the rounding. The interest of a loan is its rate for its months, whatever the rhythm.
     *
     * @return array<int, array{number: int, due_date: string, principal_due: float, interest_due: float}>
     */
    public static function schedule(float $principal, float $rate, string $method, int $months, string $start, string $every = 'monthly', ?int $days = null): array
    {
        $r = $rate / 100;
        $p = self::period($every, $days);
        $from = Carbon::parse($start);
        $end = $from->copy()->addMonthsNoOverflow($months);
        $n = self::instalmentCount($months, $every, $days, $start);
        // One period, in months, for the rate of a reducing loan.
        $periodMonths = $p['months'] > 0 ? (float) $p['months'] : $p['days'] / 30;
        $rp = $r * $periodMonths;
        $instalment = $method === 'reducing' && $rp > 0 ? $principal * $rp / (1 - (1 + $rp) ** (-$n)) : null;
        $flatInterest = round($principal * $r * $months, 2);
        $rows = [];
        $left = $principal;
        $interestLeft = $flatInterest;
        for ($k = 1; $k <= $n; $k++) {
            if ($method === 'reducing') {
                $interest = round($left * $rp, 2);
            } else {
                $interest = $k === $n ? round($interestLeft, 2) : round($flatInterest / $n, 2);
                $interestLeft = round($interestLeft - $interest, 2);
            }
            $capital = $k === $n ? $left : round($instalment === null ? $principal / $n : $instalment - $left * $rp, 2);
            $left = round($left - $capital, 2);
            $due = $k === $n ? $end : ($p['months'] > 0 ? $from->copy()->addMonthsNoOverflow($k * $p['months']) : $from->copy()->addDays($k * $p['days']));
            $rows[] = ['number' => $k, 'due_date' => $due->toDateString(), 'principal_due' => round($capital, 2), 'interest_due' => $interest];
        }

        return $rows;
    }

    /** The disbursement was verified: the loan is running, its first instalment falls one period (a day, a week, a month ...) after [on]. */
    public static function activate(int $loanId, string $on): void
    {
        $loan = DB::table('group_loans')->where('id', $loanId)->first();
        if ($loan === null || $loan->status !== 'approved') {
            return;
        }
        DB::transaction(function () use ($loan, $on) {
            DB::table('group_loan_schedule')->where('loan_id', $loan->id)->delete();
            foreach (self::schedule((float) $loan->amount_approved, (float) $loan->interest_rate, $loan->interest_method, (int) $loan->term_months, $on, (string) ($loan->repayment_every ?? 'monthly'), $loan->repayment_days === null ? null : (int) $loan->repayment_days) as $row) {
                DB::table('group_loan_schedule')->insert($row + ['loan_id' => $loan->id]);
            }
            DB::table('group_loans')->where('id', $loan->id)->update(['status' => 'active', 'disbursed_on' => $on, 'updated_at' => now()]);
        });
    }

    /** The disbursement was reversed before anything was repaid: the loan goes back to approved, waiting to be paid out again. */
    public static function undoDisbursement(int $loanId): void
    {
        DB::transaction(function () use ($loanId) {
            DB::table('group_loan_schedule')->where('loan_id', $loanId)->delete();
            DB::table('group_loans')->where('id', $loanId)->where('status', 'active')->update(['status' => 'approved', 'disbursed_on' => null, 'updated_at' => now()]);
        });
    }

    /** Verified repayments on [loanId], in minus out. */
    public static function repaid(int $loanId): float
    {
        return round((float) DB::table('group_transactions')->where('loan_id', $loanId)->where('category', 'loan_repayment')->where('status', GroupLedger::VERIFIED)
            ->selectRaw("COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END), 0) as t")->value('t'), 2);
    }

    /**
     * Where a running loan stands: repayments applied interest first then principal, instalment by instalment.
     *
     * @return array<string, mixed>
     */
    public static function position(object $loan, ?string $today = null): array
    {
        $today ??= now()->toDateString();
        $rows = DB::table('group_loan_schedule')->where('loan_id', $loan->id)->orderBy('number')->get();
        $pool = self::repaid((int) $loan->id);
        $instalments = [];
        $principalPaid = $interestPaid = $arrears = 0.0;
        $next = null;
        foreach ($rows as $row) {
            $toInterest = min($pool, (float) $row->interest_due);
            $pool -= $toInterest;
            $toPrincipal = min($pool, (float) $row->principal_due);
            $pool -= $toPrincipal;
            $interestPaid += $toInterest;
            $principalPaid += $toPrincipal;
            $left = round((float) $row->interest_due + (float) $row->principal_due - $toInterest - $toPrincipal, 2);
            if ($left > 0 && (string) $row->due_date < $today) {
                $arrears += $left;
            }
            if ($left > 0 && $next === null) {
                $next = ['number' => (int) $row->number, 'due_date' => (string) $row->due_date, 'amount' => $left];
            }
            $instalments[] = [
                'number' => (int) $row->number,
                'due_date' => (string) $row->due_date,
                'principal_due' => (float) $row->principal_due,
                'interest_due' => (float) $row->interest_due,
                'paid' => round($toInterest + $toPrincipal, 2),
                'left' => $left,
                'state' => $left <= 0 ? 'paid' : ((string) $row->due_date < $today ? 'overdue' : 'due'),
            ];
        }
        $totalPrincipal = (float) $rows->sum('principal_due');
        $totalInterest = (float) $rows->sum('interest_due');

        return [
            'instalments' => $instalments,
            'total_principal' => round($totalPrincipal, 2),
            'total_interest' => round($totalInterest, 2),
            'principal_paid' => round($principalPaid, 2),
            'interest_paid' => round($interestPaid, 2),
            'outstanding_principal' => round($totalPrincipal - $principalPaid, 2),
            'outstanding_interest' => round($totalInterest - $interestPaid, 2),
            'outstanding' => round($totalPrincipal + $totalInterest - $principalPaid - $interestPaid, 2),
            'arrears' => round($arrears, 2),
            'next' => $next,
        ];
    }

    /** What a loan's state reads as: its status, or for a running loan repaid / overdue / active. */
    public static function state(object $loan, ?array $position = null): string
    {
        if ($loan->status !== 'active') {
            return $loan->status;
        }
        $position ??= self::position($loan);
        if ($position['outstanding'] <= 0) {
            return 'repaid';
        }

        return $position['arrears'] > 0 ? 'overdue' : 'active';
    }

    /** Loans with the borrower's name and number. */
    public static function query(): \Illuminate\Database\Query\Builder
    {
        return DB::table('group_loans as l')->join('group_members as m', 'm.id', '=', 'l.member_id')
            ->select('l.*', 'm.full_name as member_name', 'm.member_number');
    }

    /**
     * A loan as the app shows it; [full] adds the guarantors and the instalments.
     *
     * @return array<string, mixed>
     */
    public static function payload(object $loan, bool $full = false): array
    {
        $position = $loan->status === 'active' ? self::position($loan) : null;
        $out = [
            'id' => (int) $loan->id,
            'reference' => $loan->reference,
            'member_id' => (int) $loan->member_id,
            'member_name' => $loan->member_name ?? null,
            'member_number' => $loan->member_number ?? null,
            'amount_requested' => (float) $loan->amount_requested,
            'amount_approved' => $loan->amount_approved === null ? null : (float) $loan->amount_approved,
            'purpose' => $loan->purpose,
            'term_months' => (int) $loan->term_months,
            'repayment_every' => (string) ($loan->repayment_every ?? 'monthly'),
            'repayment_days' => $loan->repayment_days === null ? null : (int) $loan->repayment_days,
            'interest_rate' => (float) $loan->interest_rate,
            'interest_method' => $loan->interest_method,
            'ceiling' => $loan->ceiling === null ? null : (float) $loan->ceiling,
            'status' => $loan->status,
            'state' => self::state($loan, $position),
            'recommendation' => $loan->recommendation,
            'reject_reason' => $loan->reject_reason,
            'disbursed_on' => $loan->disbursed_on === null ? null : (string) $loan->disbursed_on,
            'created_at' => (string) $loan->created_at,
            'outstanding' => $position['outstanding'] ?? null,
            'arrears' => $position['arrears'] ?? null,
            'next' => $position['next'] ?? null,
        ];
        if ($full) {
            $out['guarantors'] = DB::table('group_loan_guarantors as g')->join('group_members as m', 'm.id', '=', 'g.member_id')
                ->where('g.loan_id', $loan->id)->orderBy('g.id')
                ->get(['g.id', 'g.member_id', 'm.full_name as name', 'g.status', 'g.note', 'g.responded_at'])
                ->map(fn ($g) => (array) $g)->all();
            $out['position'] = $position;
            // What it would look like, before it is paid out: the instalments it would have from today.
            if ($position === null && in_array($loan->status, self::OPEN_STATUSES, true)) {
                $amount = (float) ($loan->amount_approved ?? $loan->amount_requested);
                $preview = self::schedule($amount, (float) $loan->interest_rate, $loan->interest_method, (int) $loan->term_months, now()->toDateString(), (string) ($loan->repayment_every ?? 'monthly'), $loan->repayment_days === null ? null : (int) $loan->repayment_days);
                $out['preview'] = [
                    'instalments' => $preview,
                    'total_interest' => round(array_sum(array_column($preview, 'interest_due')), 2),
                    'total' => round($amount + array_sum(array_column($preview, 'interest_due')), 2),
                ];
            }
        }

        return $out;
    }
}
