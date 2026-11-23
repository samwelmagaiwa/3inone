<?php

namespace App\Support\Groups;

use Illuminate\Support\Facades\DB;

/**
 * A member's statement: who they are, their account (what the group holds for them: savings and shares), every verified movement of their
 * money in order with the balance of its kind after it, what is still owed, their loans, and the totals of a chosen period. Pending and
 * turned-down payments are listed apart: they never changed a balance.
 */
final class GroupStatement
{
    /** What the group holds for a member: the balances that are theirs (savings, with dividends, and shares). */
    private const ACCOUNT_KINDS = ['savings', 'shares'];

    /**
     * @param  string|null  $from  first day of the period shown (the whole history when null)
     * @param  string|null  $to  last day of the period shown (today when null)
     * @return array<string, mixed>
     */
    public static function for(int $memberId, ?string $from = null, ?string $to = null): array
    {
        $running = array_fill_keys(GroupLedger::BALANCE_CATEGORIES, 0.0);
        $lines = [];
        $opening = 0.0;
        $closing = 0.0;
        $in = 0.0;
        $out = 0.0;
        $rows = GroupLedger::listQuery()->where('t.member_id', $memberId)->where('t.status', GroupLedger::VERIFIED)
            ->orderBy('t.verified_at')->orderBy('t.id')->get();
        foreach ($rows as $r) {
            $signed = $r->direction === 'in' ? (float) $r->amount : -(float) $r->amount;
            $kind = $r->category === 'dividend' ? 'savings' : $r->category;
            if (array_key_exists($kind, $running)) {
                $running[$kind] = round($running[$kind] + $signed, 2);
            }
            $account = round(array_sum(array_intersect_key($running, array_flip(self::ACCOUNT_KINDS))), 2);
            $day = substr((string) ($r->verified_at ?? $r->paid_on), 0, 10);
            if ($from !== null && $day < $from) {
                $opening = $account;
            }
            if ($to !== null && $day > $to) {
                continue;
            }
            $closing = $account;
            if ($from !== null && $day < $from) {
                continue;
            }
            $r->direction === 'in' ? $in += (float) $r->amount : $out += (float) $r->amount;
            $lines[] = GroupLedger::payload($r) + ['balance_after' => $running[$kind] ?? null, 'account_after' => $account, 'date' => $day];
        }
        if ($from === null) {
            $opening = 0.0;
        }

        $today = now()->toDateString();
        $owing = self::owing($memberId);

        $waiting = GroupLedger::listQuery()->where('t.member_id', $memberId)->where('t.status', GroupLedger::PENDING)->orderBy('t.id')->get()
            ->map(fn ($r) => GroupLedger::payload($r))->values()->all();
        $declined = GroupLedger::listQuery()->where('t.member_id', $memberId)->where('t.status', GroupLedger::REJECTED)->orderByDesc('t.id')->limit(50)->get()
            ->map(fn ($r) => GroupLedger::payload($r))->values()->all();

        $member = DB::table('group_members')->where('id', $memberId)->first();
        $balances = array_fill_keys(GroupLedger::BALANCE_CATEGORIES, 0.0);
        foreach (GroupLedger::balances($memberId) as $kind => $value) {
            $balances[$kind] = $value;
        }

        return [
            'member' => $member === null ? null : [
                'id' => (int) $member->id,
                'full_name' => $member->full_name,
                'member_number' => $member->member_number,
                'application_ref' => $member->application_ref,
                'phone' => $member->phone,
                'status' => $member->status,
                'office' => $member->office,
                'joined_on' => $member->joined_on === null ? null : (string) $member->joined_on,
            ],
            'lines' => array_reverse($lines),
            // What the group holds for them now (kept apart from the fees and contributions they have paid to the group).
            'account' => round(array_sum(array_intersect_key($balances, array_flip(self::ACCOUNT_KINDS))), 2),
            'balances' => $balances,
            'period' => [
                'from' => $from,
                'to' => $to,
                'opening' => $opening,
                'closing' => $closing,
                'in' => round($in, 2),
                'out' => round($out, 2),
                'count' => count($lines),
            ],
            'owing' => $owing,
            'owing_total' => round(array_sum(array_column($owing, 'remaining')), 2),
            'waiting' => $waiting,
            'declined' => $declined,
            'loans' => GroupLoans::query()->where('l.member_id', $memberId)->orderByDesc('l.id')->get()->map(fn ($l) => GroupLoans::payload($l))->values()->all(),
            'promises' => GroupPromises::query()->where('p.member_id', $memberId)->where('p.status', 'open')->orderBy('p.promised_on')->get()
                ->map(fn ($p) => GroupPromises::payload($p, $today))->values()->all(),
        ];
    }

    /** The open obligations of one member (for the payment form's choice). @return array<int, array<string, mixed>> */
    public static function owing(int $memberId): array
    {
        $today = now()->toDateString();

        return GroupContributions::owing(GroupContributions::query())->where('o.member_id', $memberId)->orderBy('o.due_date')->get()
            ->map(fn ($o) => GroupContributions::payload($o, $today))->values()->all();
    }
}
