<?php

namespace App\Support\Inventory;

use Illuminate\Database\Query\Builder;
use Illuminate\Support\Facades\DB;

/**
 * What one customer owes, in the three parts a shop owner reads it in:
 *
 *  - the OLD debt: what they owed before the app (the entries kept apart from sales), how much of it they have paid, and what is left;
 *  - the NEW debt: what they took on credit since (sales not paid in full when made), how much of it they have paid, and what is left;
 *  - the TOTAL of both: all that was owed, all that was paid so far, and all that is left.
 *
 * A cancelled sale was never owed, so it is in none of them. A credit sale that has been paid off stays in the new debt's "billed" and
 * "paid" (the money is on record), and drops out of what is left.
 */
final class CustomerDebt
{
    /** The sales on credit that still have something to pay: not cancelled, not paid off. */
    public static function openSales(int $customerId): Builder
    {
        return DB::table('inventory_sales')
            ->where('customer_id', $customerId)
            ->whereNull('cancelled_at')
            ->whereIn('payment_status', ['debt', 'partial']);
    }

    /** Every sale that was ever on credit (open ones, and ones since paid off), not cancelled. */
    private static function creditSales(int $customerId): Builder
    {
        return DB::table('inventory_sales as s')
            ->where('s.customer_id', $customerId)
            ->whereNull('s.cancelled_at')
            ->where(function ($q) {
                $q->whereIn('s.payment_status', ['debt', 'partial'])
                    ->orWhereNotNull('s.due_date')
                    // paid off later through "receive payment": it was on credit
                    ->orWhereExists(fn ($e) => $e->select(DB::raw(1))->from('inventory_payment_allocations as a')->whereColumn('a.sale_id', 's.id'));
            });
    }

    /**
     * @return array{old: array<string, mixed>, new: array<string, mixed>, total: array<string, float>}
     */
    public static function summary(int $customerId): array
    {
        $entries = OpeningDebts::active()
            ? DB::table('inventory_opening_debts')->where('kind', OpeningDebts::RECEIVABLE)->where('customer_id', $customerId)->orderBy('started_on')->orderBy('id')->get()
            : collect();
        $oldEntries = $entries->map(fn ($d) => [
            'id' => (int) $d->id,
            'amount' => (float) $d->amount,
            'paid' => (float) $d->paid_amount,
            'left' => round((float) $d->amount - (float) $d->paid_amount, 2),
            'started_on' => (string) $d->started_on,
            'due_on' => $d->due_on === null ? null : (string) $d->due_on,
            'note' => $d->note,
        ])->values()->all();
        $oldOriginal = round((float) $entries->sum('amount'), 2);
        $oldPaid = round((float) $entries->sum('paid_amount'), 2);

        $billed = round((float) self::creditSales($customerId)->sum('s.total'), 2);
        $paid = round((float) self::creditSales($customerId)->sum('s.paid_total'), 2);
        $open = self::openSales($customerId)->orderBy('created_at')->orderBy('id')
            ->get(['id', 'number', 'total', 'paid_total', 'payment_status', 'due_date', 'created_at'])
            ->map(fn ($s) => [
                'id' => (int) $s->id,
                'number' => (string) $s->number,
                'total' => (float) $s->total,
                'paid' => (float) $s->paid_total,
                'left' => round((float) $s->total - (float) $s->paid_total, 2),
                'payment_status' => (string) $s->payment_status,
                'due_date' => $s->due_date === null ? null : (string) $s->due_date,
                'created_at' => (string) $s->created_at,
            ])->values()->all();
        $newLeft = round(array_sum(array_column($open, 'left')), 2);

        return [
            'old' => ['entries' => $oldEntries, 'original' => $oldOriginal, 'paid' => $oldPaid, 'left' => round($oldOriginal - $oldPaid, 2)],
            'new' => ['sales' => $open, 'billed' => $billed, 'paid' => $paid, 'left' => $newLeft],
            'total' => [
                'owed' => round($oldOriginal + $billed, 2),
                'paid' => round($oldPaid + $paid, 2),
                'left' => round(($oldOriginal - $oldPaid) + $newLeft, 2),
            ],
        ];
    }

    /**
     * The whole account of one customer: the three-part summary, every old debt with the payments made on it, every credit sale (open or
     * paid off, not cancelled) with the payments made on it, and ONE list of all the payments, old and new together, newest first.
     *
     * @return array<string, mixed>
     */
    public static function account(int $customerId): array
    {
        $oldRows = OpeningDebts::active()
            ? DB::table('inventory_opening_debts')->where('kind', OpeningDebts::RECEIVABLE)->where('customer_id', $customerId)->orderBy('started_on')->orderBy('id')->get()
            : collect();
        $oldPayments = $oldRows->isEmpty() ? collect() : DB::table('inventory_opening_payments')->whereIn('debt_id', $oldRows->pluck('id'))->orderBy('paid_on')->orderBy('id')->get()->groupBy('debt_id');

        $saleRows = self::creditSales($customerId)->orderBy('s.created_at')->orderBy('s.id')
            ->get(['s.id', 's.number', 's.total', 's.paid_total', 's.payment_status', 's.due_date', 's.created_at']);
        $salePayments = $saleRows->isEmpty() ? collect() : DB::table('inventory_sale_payments')->whereIn('sale_id', $saleRows->pluck('id'))->orderBy('paid_at')->orderBy('id')->get()->groupBy('sale_id');

        $timeline = [];
        $oldDebts = $oldRows->map(function ($d) use ($oldPayments, &$timeline) {
            $payments = ($oldPayments[$d->id] ?? collect())->map(function ($p) use ($d, &$timeline) {
                $row = ['id' => (int) $p->id, 'amount' => (float) $p->amount, 'method' => $p->method, 'reference' => $p->note, 'paid_on' => (string) $p->paid_on];
                $timeline[] = $row + ['kind' => 'old', 'label' => $d->note ?: 'Old debt'];

                return $row;
            })->values()->all();

            return [
                'id' => (int) $d->id, 'amount' => (float) $d->amount, 'paid' => (float) $d->paid_amount,
                'left' => round((float) $d->amount - (float) $d->paid_amount, 2),
                'started_on' => (string) $d->started_on, 'due_on' => $d->due_on === null ? null : (string) $d->due_on,
                'note' => $d->note, 'payments' => $payments,
            ];
        })->values()->all();

        $creditSales = $saleRows->map(function ($s) use ($salePayments, &$timeline) {
            $payments = ($salePayments[$s->id] ?? collect())->map(function ($p) use ($s, &$timeline) {
                $row = ['id' => (int) $p->id, 'amount' => (float) $p->amount, 'method' => $p->method_extended ?: $p->method, 'reference' => $p->reference, 'paid_on' => substr((string) $p->paid_at, 0, 10)];
                $timeline[] = $row + ['kind' => 'new', 'label' => (string) $s->number];

                return $row;
            })->values()->all();

            return [
                'id' => (int) $s->id, 'number' => (string) $s->number, 'total' => (float) $s->total, 'paid' => (float) $s->paid_total,
                'left' => round((float) $s->total - (float) $s->paid_total, 2), 'payment_status' => (string) $s->payment_status,
                'due_date' => $s->due_date === null ? null : (string) $s->due_date, 'created_at' => (string) $s->created_at, 'payments' => $payments,
            ];
        })->values()->all();

        usort($timeline, fn ($a, $b) => [$b['paid_on'], $b['id']] <=> [$a['paid_on'], $a['id']]);
        $paidOld = round((float) array_sum(array_column(array_filter($timeline, fn ($p) => $p['kind'] === 'old'), 'amount')), 2);
        $paidNew = round((float) array_sum(array_column(array_filter($timeline, fn ($p) => $p['kind'] === 'new'), 'amount')), 2);

        return [
            'debt' => self::summary($customerId),
            'old_debts' => $oldDebts,
            'credit_sales' => $creditSales,
            'payments' => $timeline,
            'paid_by_payments' => ['old' => $paidOld, 'new' => $paidNew, 'all' => round($paidOld + $paidNew, 2)],
        ];
    }

    /** All that is left to pay, old and new together. */
    public static function left(int $customerId): float
    {
        return self::summary($customerId)['total']['left'];
    }
}
