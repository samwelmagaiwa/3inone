<?php

namespace App\Support\Groups;

use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

/**
 * The group's money records. Each category of money is kept apart (a joining fee is never savings), and a payment changes nothing until
 * it is verified:
 *
 *   submit   a member (or a leader for them) says a payment was made, with how and its reference      -> pending
 *   verify   the treasurer checks it against the evidence (never their own)                              -> verified, receipt number
 *   reject   the treasurer turns it down, with the reason                                                -> rejected (changes nothing)
 *   reverse  a verified payment that was wrong is put right by a new verified row the other way, linked to it; the original is
 *            never changed or deleted
 *
 * A balance is the sum of the verified rows, in minus out, so every figure can be traced to the rows behind it.
 */
final class GroupLedger
{
    public const PENDING = 'pending';
    public const VERIFIED = 'verified';
    public const REJECTED = 'rejected';

    /**
     * The kinds of money, never mixed: joining fees, project shares, savings (in, and withdrawals out), contributions (each tied to what a
     * member owes), the group's own expenses (out, to a payee, no member), loans (the disbursement out and the repayments in, each tied to
     * its loan), welfare payouts (out, tied to an approved request) and hire charges (in, tied to the hire). Dividends come last.
     */
    public const CATEGORIES = ['joining_fee', 'shares', 'savings', 'contribution', 'expense', 'loan_disbursement', 'loan_repayment', 'welfare', 'hire', 'dividend'];

    /** What a member can pay for themself (never money out). */
    public const MEMBER_CATEGORIES = ['joining_fee', 'shares', 'savings', 'contribution', 'loan_repayment', 'hire'];

    /** What a member holds or has paid in, as their balances show it (a loan repayment is the loan's, not a balance). */
    public const BALANCE_CATEGORIES = ['joining_fee', 'shares', 'savings', 'contribution'];

    /** The kinds that only ever go out. */
    public const OUT_CATEGORIES = ['expense', 'loan_disbursement', 'welfare'];

    /** How a payment can be made (the same words the rest of the app uses). */
    public const METHODS = ['cash', 'mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer', 'other'];

    /** Money from (or to) [loanId] in [category] that is pending, or pending and verified, leaving [except] out. */
    private static function linked(string $column, int $id, string $category, array $statuses, ?int $except): float
    {
        return (float) DB::table('group_transactions')->where($column, $id)->where('category', $category)->whereIn('status', $statuses)
            ->when($except !== null, fn ($q) => $q->where('id', '!=', $except))->sum('amount');
    }

    /**
     * Is [t] possible as things stand? Checked when it is sent and again when it is verified, because what it depends on (a balance, what is
     * owed, a decision) may have moved in between. Throws with the code of what is wrong.
     *
     * @param  array{category: string, direction: string, amount: float, member_id: ?int, obligation_id?: ?int, loan_id?: ?int, benefit_id?: ?int, expense_id?: ?int}  $t
     */
    public static function check(array $t, ?int $except = null): void
    {
        $category = $t['category'];
        $direction = $t['direction'];
        $amount = (float) $t['amount'];
        $memberId = $t['member_id'] ?? null;
        $sending = $except === null;
        if ($direction === 'out' && !in_array($category, array_merge(['savings'], self::OUT_CATEGORIES), true)) {
            throw new InvalidArgumentException('cannot_pay_out');
        }
        if (in_array($category, self::OUT_CATEGORIES, true) && $direction !== 'out') {
            throw new InvalidArgumentException('cannot_pay_out');
        }
        if ($category === 'contribution') {
            $obligationId = $t['obligation_id'] ?? null;
            $o = $obligationId === null ? null : DB::table('group_obligations')->where('id', $obligationId)->first();
            if ($o === null || (int) $o->member_id !== (int) $memberId) {
                throw new InvalidArgumentException('obligation_required');
            }
            $waiting = $sending ? (float) DB::table('group_transactions')->where('obligation_id', $obligationId)->where('status', self::PENDING)->sum('amount') : 0.0;
            if ($amount > GroupContributions::remaining((int) $obligationId) - $waiting + 0.001) {
                throw new InvalidArgumentException('more_than_owed');
            }
        }
        if ($category === 'savings' && $direction === 'out') {
            $waitingOut = (float) DB::table('group_transactions')->where('member_id', $memberId)->where('category', 'savings')
                ->where('direction', 'out')->where('status', self::PENDING)->when($except !== null, fn ($q) => $q->where('id', '!=', $except))->sum('amount');
            if ($amount > (self::balances((int) $memberId)['savings'] ?? 0) - $waitingOut + 0.001) {
                throw new InvalidArgumentException('more_than_savings');
            }
        }
        if ($category === 'loan_disbursement' || $category === 'loan_repayment') {
            $loanId = $t['loan_id'] ?? null;
            $loan = $loanId === null ? null : DB::table('group_loans')->where('id', $loanId)->first();
            if ($loan === null || (int) $loan->member_id !== (int) $memberId) {
                throw new InvalidArgumentException('loan_required');
            }
            if ($category === 'loan_disbursement') {
                // Paid out once, in full, and only once approved.
                if ($loan->status !== 'approved' || self::linked('loan_id', (int) $loanId, $category, [self::PENDING, self::VERIFIED], $except) > 0) {
                    throw new InvalidArgumentException('loan_not_ready');
                }
                if (abs($amount - (float) $loan->amount_approved) > 0.001) {
                    throw new InvalidArgumentException('amount_not_approved');
                }
            } else {
                if ($loan->status !== 'active') {
                    throw new InvalidArgumentException('loan_not_running');
                }
                $waiting = $sending ? self::linked('loan_id', (int) $loanId, $category, [self::PENDING], null) : 0.0;
                if ($amount > GroupLoans::position($loan)['outstanding'] - $waiting + 0.001) {
                    throw new InvalidArgumentException('more_than_loan');
                }
            }
        }
        if ($category === 'hire') {
            $hireId = $t['hire_id'] ?? null;
            $hire = $hireId === null ? null : DB::table('group_hires')->where('id', $hireId)->first();
            if ($hire === null || ($hire->member_id === null ? $memberId !== null : (int) $hire->member_id !== (int) $memberId)) {
                throw new InvalidArgumentException('hire_required');
            }
            if (!in_array($hire->status, ['approved', 'issued', 'returned'], true)) {
                throw new InvalidArgumentException('hire_not_open');
            }
            $waiting = $sending ? self::linked('hire_id', (int) $hireId, $category, [self::PENDING], null) : 0.0;
            if ($amount > GroupHires::total($hire) - GroupHires::paid((int) $hireId) - $waiting + 0.001) {
                throw new InvalidArgumentException('more_than_hire');
            }
        }
        if ($category === 'expense' && ($t['expense_id'] ?? null) !== null) {
            $req = DB::table('group_expense_requests')->where('id', (int) $t['expense_id'])->first();
            $live = $req === null ? 0 : DB::table('group_transactions')->where('expense_id', $req->id)->where('direction', 'out')->whereIn('status', [self::PENDING, self::VERIFIED])
                ->whereNull('reversed_by_id')->whereNull('reverses_id')->when($except !== null, fn ($q) => $q->where('id', '!=', $except))->count();
            if ($req === null || $req->status !== 'approved' || $live > 0) {
                throw new InvalidArgumentException('expense_not_ready');
            }
            if (abs($amount - (float) $req->amount_approved) > 0.001) {
                throw new InvalidArgumentException('amount_not_approved');
            }
        }
        if ($category === 'welfare') {
            $benefitId = $t['benefit_id'] ?? null;
            $request = $benefitId === null ? null : DB::table('group_benefit_requests')->where('id', $benefitId)->first();
            if ($request === null || (int) $request->member_id !== (int) $memberId) {
                throw new InvalidArgumentException('benefit_required');
            }
            if ($request->status !== 'approved' || self::linked('benefit_id', (int) $benefitId, $category, [self::PENDING, self::VERIFIED], $except) > 0) {
                throw new InvalidArgumentException('benefit_not_ready');
            }
            if (abs($amount - (float) $request->amount_approved) > 0.001) {
                throw new InvalidArgumentException('amount_not_approved');
            }
        }
    }

    /**
     * @param  array{member_id: ?int, category: string, amount: float|int|string, method: string, direction?: string, obligation_id?: ?int, loan_id?: ?int, benefit_id?: ?int, payee?: ?string, external_ref?: ?string, paid_on?: ?string, note?: ?string}  $data
     * @return int the new transaction's id
     */
    public static function submit(array $data, string $by): int
    {
        $method = (string) $data['method'];
        // Once the group has chosen its payment methods, money is recorded only by those (in or out).
        if (!GroupPaymentMethods::permits($method)) {
            throw new InvalidArgumentException('method_not_authorized');
        }
        $ref = trim((string) ($data['external_ref'] ?? ''));
        $category = (string) $data['category'];
        $direction = in_array($category, self::OUT_CATEGORIES, true) ? 'out' : (string) ($data['direction'] ?? 'in');
        $memberId = isset($data['member_id']) ? (int) $data['member_id'] : null;
        $link = [
            'obligation_id' => $category === 'contribution' && isset($data['obligation_id']) ? (int) $data['obligation_id'] : null,
            'loan_id' => in_array($category, ['loan_disbursement', 'loan_repayment'], true) && isset($data['loan_id']) ? (int) $data['loan_id'] : null,
            'benefit_id' => $category === 'welfare' && isset($data['benefit_id']) ? (int) $data['benefit_id'] : null,
            'hire_id' => $category === 'hire' && isset($data['hire_id']) ? (int) $data['hire_id'] : null,
            'expense_id' => $category === 'expense' && isset($data['expense_id']) ? (int) $data['expense_id'] : null,
        ];
        // Money paid IN by mobile money or bank must say its reference; money the group pays OUT is the group's own record.
        if ($direction === 'in' && $method !== 'cash' && $ref === '') {
            throw new InvalidArgumentException('reference_required');
        }
        if ($ref !== '' && self::duplicateOf($method, $ref) !== null) {
            throw new InvalidArgumentException('duplicate_reference');
        }
        if ($category === 'expense' && trim((string) ($data['payee'] ?? '')) === '') {
            throw new InvalidArgumentException('payee_required');
        }
        self::check(['category' => $category, 'direction' => $direction, 'amount' => (float) $data['amount'], 'member_id' => $memberId] + $link);

        for ($try = 0; $try < 5; $try++) {
            try {
                return (int) DB::table('group_transactions')->insertGetId($link + [
                    'reference' => 'TRX-' . strtoupper(Str::random(8)),
                    'member_id' => $memberId,
                    'payee' => $category === 'expense' ? trim((string) $data['payee']) : null,
                    'category' => $category,
                    'direction' => $direction,
                    'amount' => round((float) $data['amount'], 2),
                    'method' => $method,
                    'external_ref' => $ref === '' ? null : $ref,
                    'paid_on' => $data['paid_on'] ?? now()->toDateString(),
                    'status' => self::PENDING,
                    'note' => $data['note'] ?? null,
                    'submitted_by' => $by,
                    'submitted_at' => now(),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            } catch (QueryException) {
                continue; // the random reference was taken: draw another
            }
        }
        throw new InvalidArgumentException('try_again');
    }

    /** A live (pending or verified) payment with the same method and reference, if any: the same money must not be counted twice. */
    public static function duplicateOf(string $method, string $ref, ?int $except = null): ?object
    {
        return DB::table('group_transactions')
            ->where('method', $method)->where('external_ref', $ref)
            ->whereIn('status', [self::PENDING, self::VERIFIED])
            ->when($except !== null, fn ($q) => $q->where('id', '!=', $except))
            ->first(['id', 'reference', 'status']);
    }

    /**
     * May [userId] (whose own member row is [memberId], if any) verify [tx]? Never a payment they submitted or one that is theirs.
     */
    public static function selfCheck(object $tx, string $userId, ?int $memberId): ?string
    {
        if ((string) $tx->submitted_by === $userId) {
            return 'own_submission';
        }
        if ($memberId !== null && (int) $tx->member_id === $memberId) {
            return 'own_payment';
        }

        return null;
    }

    public static function verify(object $tx, string $by): string
    {
        // The balance it depends on may have moved since it was sent (another withdrawal, another payment to the same contribution).
        self::check([
            'category' => (string) $tx->category, 'direction' => (string) $tx->direction, 'amount' => (float) $tx->amount,
            'member_id' => $tx->member_id === null ? null : (int) $tx->member_id,
            'obligation_id' => $tx->obligation_id === null ? null : (int) $tx->obligation_id,
            'loan_id' => ($tx->loan_id ?? null) === null ? null : (int) $tx->loan_id,
            'benefit_id' => ($tx->benefit_id ?? null) === null ? null : (int) $tx->benefit_id,
            'hire_id' => ($tx->hire_id ?? null) === null ? null : (int) $tx->hire_id,
            'expense_id' => ($tx->expense_id ?? null) === null ? null : (int) $tx->expense_id,
        ], (int) $tx->id);
        $receipt = self::nextReceipt();
        for ($try = 0; $try < 5; $try++) {
            try {
                $done = DB::table('group_transactions')->where('id', $tx->id)->where('status', self::PENDING)->update([
                    'status' => self::VERIFIED, 'verified_by' => $by, 'verified_at' => now(), 'receipt_number' => $receipt, 'updated_at' => now(),
                ]);
                if ($done === 0) {
                    throw new InvalidArgumentException('not_pending');
                }
                if ($tx->category === 'loan_disbursement' && ($tx->loan_id ?? null) !== null) {
                    GroupLoans::activate((int) $tx->loan_id, now()->toDateString());
                }

                return $receipt;
            } catch (QueryException) {
                $receipt = self::nextReceipt();
            }
        }
        throw new InvalidArgumentException('try_again');
    }

    public static function reject(object $tx, string $by, string $reason): void
    {
        $done = DB::table('group_transactions')->where('id', $tx->id)->where('status', self::PENDING)->update([
            'status' => self::REJECTED, 'verified_by' => $by, 'verified_at' => now(), 'reject_reason' => $reason, 'updated_at' => now(),
        ]);
        if ($done === 0) {
            throw new InvalidArgumentException('not_pending');
        }
    }

    /** Put a verified payment right: a new verified row for the same amount the other way, linked both ways. Returns the new row's id. */
    public static function reverse(object $tx, string $by, string $reason): int
    {
        if ($tx->status !== self::VERIFIED || $tx->reversed_by_id !== null || $tx->reverses_id !== null) {
            throw new InvalidArgumentException('cannot_reverse');
        }
        if ($tx->category === 'loan_disbursement' && GroupLoans::repaid((int) $tx->loan_id) > 0) {
            throw new InvalidArgumentException('loan_has_repayments');
        }

        return DB::transaction(function () use ($tx, $by, $reason) {
            $id = (int) DB::table('group_transactions')->insertGetId([
                'reference' => 'REV-' . strtoupper(Str::random(8)),
                'receipt_number' => self::nextReceipt(),
                'member_id' => $tx->member_id,
                'obligation_id' => $tx->obligation_id,
                'loan_id' => $tx->loan_id ?? null,
                'benefit_id' => $tx->benefit_id ?? null,
                'hire_id' => $tx->hire_id ?? null,
                'expense_id' => $tx->expense_id ?? null,
                'payee' => $tx->payee,
                'category' => $tx->category,
                'direction' => $tx->direction === 'in' ? 'out' : 'in',
                'amount' => $tx->amount,
                'method' => $tx->method,
                'paid_on' => now()->toDateString(),
                'status' => self::VERIFIED,
                'note' => mb_substr($reason, 0, 255),
                'submitted_by' => $by,
                'submitted_at' => now(),
                'verified_by' => $by,
                'verified_at' => now(),
                'reverses_id' => $tx->id,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            // Only the link is written on the original: its amount, status and evidence stay exactly as they were.
            $linked = DB::table('group_transactions')->where('id', $tx->id)->whereNull('reversed_by_id')->update(['reversed_by_id' => $id]);
            if ($linked === 0) {
                throw new InvalidArgumentException('cannot_reverse');
            }
            if ($tx->category === 'loan_disbursement') {
                GroupLoans::undoDisbursement((int) $tx->loan_id);
            }

            return $id;
        });
    }

    /** SQL that joins strings: SQLite (tests) has ||, MySQL / MariaDB have CONCAT. */
    private static function concat(string ...$parts): string
    {
        return DB::connection()->getDriverName() === 'sqlite' ? implode(' || ', $parts) : 'CONCAT(' . implode(', ', $parts) . ')';
    }

    /** RC-000001, RC-000002, ... within the group. */
    private static function nextReceipt(): string
    {
        $highest = 0;
        foreach (DB::table('group_transactions')->whereNotNull('receipt_number')->pluck('receipt_number') as $n) {
            $tail = substr((string) $n, 3);
            if (ctype_digit($tail)) {
                $highest = max($highest, (int) $tail);
            }
        }

        return 'RC-' . str_pad((string) ($highest + 1), 6, '0', STR_PAD_LEFT);
    }

    /**
     * What a member has paid in, per category, counting verified rows only (in minus out).
     *
     * @return array<string, float>
     */
    public static function balances(int $memberId): array
    {
        $out = array_fill_keys(self::BALANCE_CATEGORIES, 0.0);
        $rows = DB::table('group_transactions')->where('member_id', $memberId)->where('status', self::VERIFIED)
            ->selectRaw("category, SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END) as total")
            ->groupBy('category')->get();
        $dividends = 0.0;
        foreach ($rows as $r) {
            if (array_key_exists($r->category, $out)) {
                $out[$r->category] = round((float) $r->total, 2);
            }
            if ($r->category === 'dividend') {
                $dividends += (float) $r->total;
            }
        }
        // A dividend is credited to savings: kept as its own kind of row (never mixed with deposits), counted in the savings balance.
        $out['savings'] = round($out['savings'] + $dividends, 2);

        return $out;
    }

    /**
     * A transaction as the app shows it.
     *
     * @return array<string, mixed>
     */
    public static function payload(object $r): array
    {
        return [
            'id' => (int) $r->id,
            'reference' => $r->reference,
            'receipt_number' => $r->receipt_number,
            'member_id' => $r->member_id === null ? null : (int) $r->member_id,
            'obligation_id' => ($r->obligation_id ?? null) === null ? null : (int) $r->obligation_id,
            'obligation_label' => $r->obligation_label ?? null,
            'payee' => $r->payee ?? null,
            'loan_id' => ($r->loan_id ?? null) === null ? null : (int) $r->loan_id,
            'benefit_id' => ($r->benefit_id ?? null) === null ? null : (int) $r->benefit_id,
            'hire_id' => ($r->hire_id ?? null) === null ? null : (int) $r->hire_id,
            'expense_id' => ($r->expense_id ?? null) === null ? null : (int) $r->expense_id,
            'member_name' => $r->member_name ?? null,
            'member_number' => $r->member_number ?? null,
            'category' => $r->category,
            'direction' => $r->direction,
            'amount' => (float) $r->amount,
            'method' => $r->method,
            'external_ref' => $r->external_ref,
            'paid_on' => (string) $r->paid_on,
            'status' => $r->status,
            'note' => $r->note,
            'reject_reason' => $r->reject_reason,
            'submitted_by_name' => $r->submitted_by_name ?? null,
            'verified_by_name' => $r->verified_by_name ?? null,
            'submitted_at' => $r->submitted_at === null ? null : (string) $r->submitted_at,
            'verified_at' => $r->verified_at === null ? null : (string) $r->verified_at,
            'reverses_id' => $r->reverses_id === null ? null : (int) $r->reverses_id,
            'reversed_by_id' => $r->reversed_by_id === null ? null : (int) $r->reversed_by_id,
        ];
    }

    /** The query the lists read from: the transaction with the member's name and number and who submitted and verified it. */
    public static function listQuery(): \Illuminate\Database\Query\Builder
    {
        return DB::table('group_transactions as t')
            ->leftJoin('group_members as m', 'm.id', '=', 't.member_id')
            ->leftJoin('users as su', 'su.id', '=', 't.submitted_by')
            ->leftJoin('users as vu', 'vu.id', '=', 't.verified_by')
            ->leftJoin('group_obligations as o', 'o.id', '=', 't.obligation_id')
            ->leftJoin('group_contribution_types as c', 'c.id', '=', 'o.contribution_type_id')
            ->select('t.*', 'm.full_name as member_name', 'm.member_number', 'su.name as submitted_by_name', 'vu.name as verified_by_name')
            ->selectRaw("CASE WHEN c.name IS NULL THEN NULL ELSE " . self::concat("c.name", "' · '", "COALESCE(o.label, o.period)") . " END as obligation_label");
    }
}
