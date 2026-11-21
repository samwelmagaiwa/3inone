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
 *   submit   a member (or an officer for them) says a payment was made, with how and its reference      -> pending
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
     * member owes) and the group's own expenses (out, to a payee, no member). Later phases add loans, welfare, rental and dividends.
     */
    public const CATEGORIES = ['joining_fee', 'shares', 'savings', 'contribution', 'expense'];

    /** What a member can pay for themself (never money out). */
    public const MEMBER_CATEGORIES = ['joining_fee', 'shares', 'savings', 'contribution'];

    /** How a payment can be made (the same words the rest of the app uses). */
    public const METHODS = ['cash', 'mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer', 'other'];

    /**
     * Is a payment of [amount] in [category] ([direction]) possible as things stand? Checked when it is sent and again when it is verified,
     * because the balance it depends on may have moved in between. Throws with the code of what is wrong.
     */
    public static function check(string $category, string $direction, float $amount, ?int $memberId, ?int $obligationId, ?int $except = null): void
    {
        if ($direction === 'out' && !in_array($category, ['savings', 'expense'], true)) {
            throw new InvalidArgumentException('cannot_pay_out');
        }
        if ($category === 'expense' && $direction !== 'out') {
            throw new InvalidArgumentException('cannot_pay_out');
        }
        if ($category === 'contribution') {
            $o = $obligationId === null ? null : DB::table('group_obligations')->where('id', $obligationId)->first();
            if ($o === null || (int) $o->member_id !== (int) $memberId) {
                throw new InvalidArgumentException('obligation_required');
            }
            $waiting = (float) DB::table('group_transactions')->where('obligation_id', $obligationId)->where('status', self::PENDING)
                ->when($except !== null, fn ($q) => $q->where('id', '!=', $except))->sum('amount');
            if ($amount > GroupContributions::remaining($obligationId) - ($except === null ? $waiting : 0) + 0.001) {
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
    }

    /**
     * @param  array{member_id: ?int, category: string, amount: float|int|string, method: string, direction?: string, obligation_id?: ?int, payee?: ?string, external_ref?: ?string, paid_on?: ?string, note?: ?string}  $data
     * @return int the new transaction's id
     */
    public static function submit(array $data, string $by): int
    {
        $method = (string) $data['method'];
        $ref = trim((string) ($data['external_ref'] ?? ''));
        $direction = (string) ($data['direction'] ?? 'in');
        $memberId = isset($data['member_id']) ? (int) $data['member_id'] : null;
        $obligationId = isset($data['obligation_id']) ? (int) $data['obligation_id'] : null;
        // Money paid IN by mobile money or bank must say its reference; money the group pays OUT is the group's own record.
        if ($direction === 'in' && $method !== 'cash' && $ref === '') {
            throw new InvalidArgumentException('reference_required');
        }
        if ($ref !== '' && self::duplicateOf($method, $ref) !== null) {
            throw new InvalidArgumentException('duplicate_reference');
        }
        if ($data['category'] === 'expense' && trim((string) ($data['payee'] ?? '')) === '') {
            throw new InvalidArgumentException('payee_required');
        }
        self::check((string) $data['category'], $direction, (float) $data['amount'], $memberId, $obligationId);

        for ($try = 0; $try < 5; $try++) {
            try {
                return (int) DB::table('group_transactions')->insertGetId([
                    'reference' => 'TRX-' . strtoupper(Str::random(8)),
                    'member_id' => $memberId,
                    'obligation_id' => $data['category'] === 'contribution' ? $obligationId : null,
                    'payee' => $data['category'] === 'expense' ? trim((string) $data['payee']) : null,
                    'category' => (string) $data['category'],
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
        self::check((string) $tx->category, (string) $tx->direction, (float) $tx->amount, $tx->member_id === null ? null : (int) $tx->member_id,
            $tx->obligation_id === null ? null : (int) $tx->obligation_id, (int) $tx->id);
        $receipt = self::nextReceipt();
        for ($try = 0; $try < 5; $try++) {
            try {
                $done = DB::table('group_transactions')->where('id', $tx->id)->where('status', self::PENDING)->update([
                    'status' => self::VERIFIED, 'verified_by' => $by, 'verified_at' => now(), 'receipt_number' => $receipt, 'updated_at' => now(),
                ]);
                if ($done === 0) {
                    throw new InvalidArgumentException('not_pending');
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

        return DB::transaction(function () use ($tx, $by, $reason) {
            $id = (int) DB::table('group_transactions')->insertGetId([
                'reference' => 'REV-' . strtoupper(Str::random(8)),
                'receipt_number' => self::nextReceipt(),
                'member_id' => $tx->member_id,
                'obligation_id' => $tx->obligation_id,
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
        $out = array_fill_keys(self::MEMBER_CATEGORIES, 0.0);
        $rows = DB::table('group_transactions')->where('member_id', $memberId)->where('status', self::VERIFIED)
            ->selectRaw("category, SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END) as total")
            ->groupBy('category')->get();
        foreach ($rows as $r) {
            if (array_key_exists($r->category, $out)) {
                $out[$r->category] = round((float) $r->total, 2);
            }
        }

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
