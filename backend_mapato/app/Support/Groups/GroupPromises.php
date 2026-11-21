<?php

namespace App\Support\Groups;

use Illuminate\Support\Facades\DB;

/**
 * "I will pay 20,000 on the 30th." A promise is a note with a date: it never lowers what is owed -- only a verified payment does. Its state is
 * read, not stored: KEPT once the contribution it names is paid (or, for a general promise, once the member's verified payments since the
 * promise reach its amount), OVERDUE when its day has passed without that, otherwise DUE. A member or an officer can withdraw it (cancelled).
 */
final class GroupPromises
{
    /** @return array<string, mixed> */
    public static function payload(object $p, ?string $today = null): array
    {
        $today ??= now()->toDateString();

        return [
            'id' => (int) $p->id,
            'member_id' => (int) $p->member_id,
            'member_name' => $p->member_name ?? null,
            'obligation_id' => $p->obligation_id === null ? null : (int) $p->obligation_id,
            'obligation_label' => $p->obligation_label ?? null,
            'amount' => (float) $p->amount,
            'promised_on' => (string) $p->promised_on,
            'note' => $p->note,
            'state' => self::state($p, $today),
            'created_at' => (string) $p->created_at,
        ];
    }

    public static function state(object $p, string $today): string
    {
        if ($p->status === 'cancelled') {
            return 'cancelled';
        }
        if ($p->obligation_id !== null) {
            $kept = GroupContributions::remaining((int) $p->obligation_id) <= 0;
        } else {
            $paid = (float) DB::table('group_transactions')->where('member_id', $p->member_id)->where('status', GroupLedger::VERIFIED)
                ->where('direction', 'in')->where('verified_at', '>=', $p->created_at)->sum('amount');
            $kept = $paid + 0.001 >= (float) $p->amount;
        }
        if ($kept) {
            return 'kept';
        }

        return (string) $p->promised_on < $today ? 'overdue' : 'due';
    }

    /** Promises with the member's name and what they name. */
    public static function query(): \Illuminate\Database\Query\Builder
    {
        return DB::table('group_promises as p')
            ->join('group_members as m', 'm.id', '=', 'p.member_id')
            ->leftJoin('group_obligations as o', 'o.id', '=', 'p.obligation_id')
            ->leftJoin('group_contribution_types as c', 'c.id', '=', 'o.contribution_type_id')
            ->select('p.*', 'm.full_name as member_name', 'c.name as obligation_label');
    }
}
