<?php

namespace App\Support\Groups;

use Illuminate\Database\Query\Builder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

/**
 * What a group expects its members to pay in turn, and where each member stands.
 *
 * A contribution TYPE says how much and how often (monthly on a day, once, or when an event is called). Raising a period creates one
 * OBLIGATION per active member: "Asha owes 10,000 of JAMII for 2026-11, due on the 5th". What has been paid is never stored on it: it is
 * read from the verified payments that name it, so it cannot drift from the money records. An obligation is closed by being paid, or by
 * an approved exemption (udhuru) with its reason.
 */
final class GroupContributions
{
    public const FREQUENCIES = ['monthly', 'one_time', 'event'];

    public const OPEN = 'open';
    public const EXEMPT = 'exempt';
    public const CANCELLED = 'cancelled';

    /** @return array<string, mixed> */
    public static function typePayload(object $t): array
    {
        return [
            'id' => (int) $t->id,
            'name' => $t->name,
            'description' => $t->description,
            'amount' => (float) $t->amount,
            'frequency' => $t->frequency,
            'due_day' => $t->due_day === null ? null : (int) $t->due_day,
            'mandatory' => (bool) $t->mandatory,
            'starts_on' => (string) $t->starts_on,
            'ends_on' => $t->ends_on === null ? null : (string) $t->ends_on,
            'active' => (bool) $t->active,
        ];
    }

    /** The day a monthly contribution falls due in [month] (2026-02 with due day 30 is the 28th). */
    public static function dueDateIn(int $dueDay, string $month): string
    {
        $start = Carbon::createFromFormat('Y-m-d', $month . '-01')->startOfDay();

        return $start->copy()->day(min(max(1, $dueDay), $start->daysInMonth))->toDateString();
    }

    /**
     * Raise a period of a contribution: one obligation for every active member that does not have one for it yet. Safe to repeat.
     *
     * @return int how many obligations were created
     */
    public static function raise(object $type, string $period, string $dueDate, ?string $label = null): int
    {
        $members = DB::table('group_members')->where('status', GroupMembers::ACTIVE)->pluck('id');
        $have = DB::table('group_obligations')->where('contribution_type_id', $type->id)->where('period', $period)->pluck('member_id')
            ->map(fn ($id) => (int) $id)->all();
        $rows = [];
        foreach ($members as $memberId) {
            if (in_array((int) $memberId, $have, true)) {
                continue;
            }
            $rows[] = [
                'member_id' => (int) $memberId,
                'contribution_type_id' => (int) $type->id,
                'period' => $period,
                'label' => $label,
                'amount_due' => $type->amount,
                'due_date' => $dueDate,
                'status' => self::OPEN,
                'created_at' => now(),
                'updated_at' => now(),
            ];
        }
        foreach (array_chunk($rows, 200) as $chunk) {
            DB::table('group_obligations')->insertOrIgnore($chunk);
        }

        return count($rows);
    }

    /** Raise [month] (2026-11) of every active monthly contribution that runs in it. Returns how many obligations were created. */
    public static function raiseMonth(string $month): int
    {
        $start = $month . '-01';
        $end = Carbon::parse($start)->endOfMonth()->toDateString();
        $created = 0;
        $types = DB::table('group_contribution_types')->where('active', true)->where('frequency', 'monthly')
            ->where('starts_on', '<=', $end)
            ->where(fn ($q) => $q->whereNull('ends_on')->orWhere('ends_on', '>=', $start))
            ->get();
        foreach ($types as $type) {
            $created += self::raise($type, $month, self::dueDateIn((int) ($type->due_day ?? 1), $month));
        }

        return $created;
    }

    /** A new period name for an event call of [type]: E20261122-1, E20261122-2, ... */
    public static function eventPeriod(object $type, string $dueDate): string
    {
        $base = 'E' . str_replace('-', '', $dueDate);
        $n = DB::table('group_obligations')->where('contribution_type_id', $type->id)->where('period', 'like', $base . '-%')->distinct()->count('period');

        return $base . '-' . ($n + 1);
    }

    /** The verified money that went to each obligation (in minus out), as a sub-query to join. */
    public static function paidSub(): Builder
    {
        return DB::table('group_transactions')->where('status', GroupLedger::VERIFIED)->whereNotNull('obligation_id')
            ->selectRaw("obligation_id, SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END) as paid")
            ->groupBy('obligation_id');
    }

    /** Obligations with the member, the contribution and what was paid (column `paid`). */
    public static function query(): Builder
    {
        return DB::table('group_obligations as o')
            ->join('group_members as m', 'm.id', '=', 'o.member_id')
            ->join('group_contribution_types as c', 'c.id', '=', 'o.contribution_type_id')
            ->leftJoinSub(self::paidSub(), 'p', 'p.obligation_id', '=', 'o.id')
            ->select('o.*', 'm.full_name as member_name', 'm.member_number', 'm.phone as member_phone', 'c.name as type_name', 'c.mandatory')
            ->selectRaw('COALESCE(p.paid, 0) as paid');
    }

    /** Limit [q] to obligations still owed (open and not fully paid). */
    public static function owing(Builder $q): Builder
    {
        return $q->where('o.status', self::OPEN)->whereRaw('COALESCE(p.paid, 0) < o.amount_due');
    }

    /** paid | exempt | cancelled | overdue | due, as of [today]. */
    public static function state(object $o, string $today): string
    {
        if ($o->status === self::EXEMPT) {
            return 'exempt';
        }
        if ($o->status === self::CANCELLED) {
            return 'cancelled';
        }
        if ((float) $o->paid + 0.001 >= (float) $o->amount_due) {
            return 'paid';
        }

        return (string) $o->due_date < $today ? 'overdue' : 'due';
    }

    /** @return array<string, mixed> */
    public static function payload(object $o, ?string $today = null): array
    {
        $today ??= now()->toDateString();
        $remaining = max(0, round((float) $o->amount_due - (float) $o->paid, 2));

        return [
            'id' => (int) $o->id,
            'member_id' => (int) $o->member_id,
            'member_name' => $o->member_name ?? null,
            'member_number' => $o->member_number ?? null,
            'contribution_type_id' => (int) $o->contribution_type_id,
            'type_name' => $o->type_name ?? null,
            'period' => $o->period,
            'label' => $o->label,
            'amount_due' => (float) $o->amount_due,
            'paid' => round((float) $o->paid, 2),
            'remaining' => $o->status === self::OPEN ? $remaining : 0.0,
            'due_date' => (string) $o->due_date,
            'state' => self::state($o, $today),
            'days_overdue' => self::state($o, $today) === 'overdue' ? Carbon::parse((string) $o->due_date)->diffInDays(Carbon::parse($today)) : 0,
            'exempt_reason' => $o->exempt_reason,
        ];
    }

    /** What is still owed on [obligationId] (0 when exempt, cancelled or paid). */
    public static function remaining(int $obligationId): float
    {
        $o = self::query()->where('o.id', $obligationId)->first();
        if ($o === null || $o->status !== self::OPEN) {
            return 0.0;
        }

        return max(0, round((float) $o->amount_due - (float) $o->paid, 2));
    }

    /** Excuse a member from an obligation (udhuru). Only an open one that is not yet paid in full. */
    public static function exempt(int $obligationId, string $by, string $reason): void
    {
        if (self::remaining($obligationId) <= 0) {
            throw new InvalidArgumentException('not_owing');
        }
        DB::table('group_obligations')->where('id', $obligationId)->where('status', self::OPEN)->update([
            'status' => self::EXEMPT, 'exempt_reason' => $reason, 'exempted_by' => $by, 'exempted_at' => now(), 'updated_at' => now(),
        ]);
    }

    /**
     * The group's position for [month]: what was expected (due in the month, not excused), what of it was paid, and everything overdue.
     *
     * @return array<string, float|int>
     */
    public static function position(string $month, string $today): array
    {
        $start = $month . '-01';
        $end = Carbon::parse($start)->endOfMonth()->toDateString();
        $inMonth = self::query()->where('o.status', self::OPEN)->whereBetween('o.due_date', [$start, $end])->get();
        $overdue = self::owing(self::query())->where('o.due_date', '<', $today)->get();

        return [
            'expected' => round($inMonth->sum(fn ($o) => (float) $o->amount_due), 2),
            'collected' => round($inMonth->sum(fn ($o) => min((float) $o->paid, (float) $o->amount_due)), 2),
            'overdue_amount' => round($overdue->sum(fn ($o) => (float) $o->amount_due - (float) $o->paid), 2),
            'overdue_members' => $overdue->pluck('member_id')->unique()->count(),
            'overdue_count' => $overdue->count(),
        ];
    }
}
