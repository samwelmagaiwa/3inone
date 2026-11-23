<?php

namespace App\Support\Groups;

use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Hiring the group's things out (chairs, tents ...), from request to closed:
 *
 *   requested -> approved (the keeper or an officer confirms they are there) or declined
 *   approved  -> issued (handed over: how many, in what condition)
 *   issued    -> returned (how many came back, damaged, missing; a late charge if the group set a late rate)
 *   returned  -> closed (everything back or settled, every shilling paid)
 *
 * The charge is units x rate x days, worked out when it is asked for (the rate of that day is kept); days count both the collection and the
 * return day unless the group chose "only the nights between". Money is paid like everything else (a `hire` payment, verified by someone
 * else); a hire is CONFIRMED once it is approved AND its charge is paid. A damage or loss charge is never automatic: whoever decides hire
 * charges sets it (it may be 0) with a note.
 */
final class GroupHires
{
    public const LIVE = ['approved', 'issued'];

    public static function newReference(): string
    {
        do {
            $ref = 'HR-' . strtoupper(Str::random(6));
        } while (DB::table('group_hires')->where('reference', $ref)->exists());

        return $ref;
    }

    /** How many days [from]..[to] are charged, by the group's rule. */
    public static function days(string $from, string $to): int
    {
        $diff = (int) Carbon::parse($from)->diffInDays(Carbon::parse($to));

        return GroupSettings::get('hire_days_rule') === 'between' ? max(1, $diff) : $diff + 1;
    }

    /**
     * How many of [asset] are free over [from]..[to]: its usable count, less what approved or handed-over hires hold then (a hire not yet
     * back holds its things until today, whatever its end date said).
     */
    public static function available(object $asset, string $from, string $to, ?int $exceptHire = null): int
    {
        $today = now()->toDateString();
        $held = DB::table('group_hires')->where('asset_id', $asset->id)->whereIn('status', self::LIVE)
            ->when($exceptHire !== null, fn ($q) => $q->where('id', '!=', $exceptHire))
            ->where('start_date', '<=', $to)
            // Overlaps when it ends on or after [from]; a hire still out past its end overlaps any range that starts by today.
            ->where(fn ($q) => $q->where('end_date', '>=', $from)->when($today >= $from, fn ($w) => $w->orWhere('status', 'issued')))
            ->sum(DB::raw('COALESCE(issued_quantity, quantity)'));

        return max(0, (int) $asset->quantity - (int) $held);
    }

    /** Verified money paid for [hireId], in minus out. */
    public static function paid(int $hireId): float
    {
        return round((float) DB::table('group_transactions')->where('hire_id', $hireId)->where('status', GroupLedger::VERIFIED)
            ->selectRaw("COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END), 0) as t")->value('t'), 2);
    }

    /** What [hire] costs in all: the charge, plus late and damage charges. */
    public static function total(object $hire): float
    {
        return round((float) $hire->amount + (float) $hire->late_charge + (float) $hire->damage_charge, 2);
    }

    /**
     * The nights a hire has run past its return day by [on]: the first is the night after the return date ended. Nothing before that.
     */
    public static function lateNights(object $hire, string $on): int
    {
        return max(0, (int) Carbon::parse((string) $hire->end_date)->diffInDays(Carbon::parse($on), false));
    }

    /**
     * The late charge if [hire] comes back on [on]: every night past the return date x the late rate x the units out. An asset with no late
     * rate of its own is charged its normal hire rate for each extra night (a late rate of 0 means no charge for lateness at all).
     */
    public static function lateCharge(object $hire, object $asset, string $on): float
    {
        $nights = self::lateNights($hire, $on);
        $rate = $asset->late_rate ?? $asset->hire_rate;
        if ($nights <= 0 || $rate === null) {
            return 0.0;
        }

        return round($nights * (float) $rate * (int) ($hire->issued_quantity ?? $hire->quantity), 2);
    }

    /** Where it stands, read rather than stored: waiting_payment / confirmed / out / overdue / returned / closed / ... */
    public static function state(object $hire, ?string $today = null): string
    {
        $today ??= now()->toDateString();
        $paid = self::paid((int) $hire->id);

        return match ($hire->status) {
            'approved' => $paid + 0.001 >= (float) $hire->amount ? 'confirmed' : 'waiting_payment',
            'issued' => (string) $hire->end_date < $today ? 'overdue' : 'out',
            'returned' => $hire->damage_status === 'pending' ? 'damage_pending' : ($paid + 0.001 >= self::total($hire) ? 'settled' : 'balance_due'),
            default => (string) $hire->status,
        };
    }

    /** May [user] handle hires of [asset]: whoever manages assets, or the member who keeps that asset. */
    public static function canHandle(?User $user, object $asset): bool
    {
        if (GroupAccess::can($user, 'manage_assets')) {
            return true;
        }
        $me = GroupAccess::member($user);

        return $me !== null && $me['status'] === GroupMembers::ACTIVE && $asset->custodian_id !== null && (int) $asset->custodian_id === (int) $me['id'];
    }

    public static function query(): \Illuminate\Database\Query\Builder
    {
        return DB::table('group_hires as h')->join('group_assets as a', 'a.id', '=', 'h.asset_id')->leftJoin('group_members as m', 'm.id', '=', 'h.member_id')
            ->select('h.*', 'a.name as asset_name', 'a.custodian_id', 'a.late_rate as asset_late_rate', 'a.hire_rate as asset_hire_rate', 'm.full_name as member_name', 'm.phone as member_phone');
    }

    /** @return array<string, mixed> */
    public static function payload(object $h): array
    {
        $paid = self::paid((int) $h->id);

        return [
            'id' => (int) $h->id,
            'reference' => $h->reference,
            'asset_id' => (int) $h->asset_id,
            'asset_name' => $h->asset_name ?? null,
            'member_id' => $h->member_id === null ? null : (int) $h->member_id,
            'who' => $h->member_name ?? $h->customer_name,
            'phone' => $h->member_phone ?? $h->customer_phone,
            'purpose' => $h->purpose,
            'quantity' => (int) $h->quantity,
            'start_date' => (string) $h->start_date,
            'end_date' => (string) $h->end_date,
            'days' => (int) $h->days,
            'rate' => (float) $h->rate,
            'amount' => (float) $h->amount,
            'late_charge' => (float) $h->late_charge,
            // While it is still out past its return day: the nights so far and what they come to now (settled when it comes back).
            'late_nights' => $h->status === 'issued' ? self::lateNights($h, now()->toDateString()) : (($h->returned_on ?? null) === null ? 0 : self::lateNights($h, (string) $h->returned_on)),
            'late_charge_now' => $h->status === 'issued' ? self::lateCharge($h, (object) ['late_rate' => $h->asset_late_rate ?? null, 'hire_rate' => $h->asset_hire_rate ?? $h->rate], now()->toDateString()) : (float) $h->late_charge,
            'damage_charge' => (float) $h->damage_charge,
            'damage_note' => $h->damage_note,
            'total' => self::total($h),
            'paid' => $paid,
            'balance' => round(max(0, self::total($h) - $paid), 2),
            'status' => $h->status,
            'state' => self::state($h),
            'decision_note' => $h->decision_note,
            'issued_quantity' => $h->issued_quantity === null ? null : (int) $h->issued_quantity,
            'issued_condition' => $h->issued_condition,
            'returned_quantity' => $h->returned_quantity === null ? null : (int) $h->returned_quantity,
            'damaged_quantity' => $h->damaged_quantity === null ? null : (int) $h->damaged_quantity,
            'missing_quantity' => $h->missing_quantity === null ? null : (int) $h->missing_quantity,
            'return_note' => $h->return_note,
            'returned_on' => $h->returned_on === null ? null : (string) $h->returned_on,
        ];
    }

    /** Record a change to an asset (never edited). */
    public static function event(int $assetId, string $kind, ?int $quantity, ?string $note, ?string $by, ?float $cost = null, ?int $hireId = null): void
    {
        DB::table('group_asset_events')->insert([
            'asset_id' => $assetId, 'kind' => $kind, 'quantity' => $quantity, 'cost' => $cost, 'note' => $note, 'hire_id' => $hireId, 'by_user' => $by, 'created_at' => now(),
        ]);
    }
}
