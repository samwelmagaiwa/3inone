<?php

namespace App\Support\Groups;

/**
 * A member's statement: every verified movement of their money in order, with the balance of its kind after it, what is still owed, and
 * the totals. Pending and turned-down payments are listed apart: they never changed a balance.
 */
final class GroupStatement
{
    /** @return array<string, mixed> */
    public static function for(int $memberId): array
    {
        $running = array_fill_keys(GroupLedger::BALANCE_CATEGORIES, 0.0);
        $lines = [];
        $rows = GroupLedger::listQuery()->where('t.member_id', $memberId)->where('t.status', GroupLedger::VERIFIED)
            ->orderBy('t.verified_at')->orderBy('t.id')->get();
        foreach ($rows as $r) {
            $signed = $r->direction === 'in' ? (float) $r->amount : -(float) $r->amount;
            $kind = $r->category === 'dividend' ? 'savings' : $r->category;
            if (array_key_exists($kind, $running)) {
                $running[$kind] = round($running[$kind] + $signed, 2);
            }
            $lines[] = GroupLedger::payload($r) + ['balance_after' => $running[$kind] ?? null];
        }

        $today = now()->toDateString();
        $owing = self::owing($memberId);

        $waiting = GroupLedger::listQuery()->where('t.member_id', $memberId)->where('t.status', GroupLedger::PENDING)->orderBy('t.id')->get()
            ->map(fn ($r) => GroupLedger::payload($r))->values()->all();

        return [
            'lines' => array_reverse($lines),
            'balances' => $running,
            'owing' => $owing,
            'owing_total' => round(array_sum(array_column($owing, 'remaining')), 2),
            'waiting' => $waiting,
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
