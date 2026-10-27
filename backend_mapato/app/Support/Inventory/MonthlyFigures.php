<?php

namespace App\Support\Inventory;

use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * One month of the business in numbers, worked out the same way everywhere (the monthly report, the target, the advice):
 *
 *   sales            what was billed on sales that were not cancelled (cash or on credit)
 *   cost of goods    what the goods sold had cost
 *   expenses         business spending only; personal spending (family, drawings) is listed apart and never lowers the profit
 *   write-offs       approved damages, expiry and theft, at cost
 *   net profit       sales - cost of goods - business expenses - write-offs
 *   capital          stock at cost + money customers owe - money owed to suppliers and lenders
 *
 * Months are Tanzanian calendar months. Profit and spending for a past month are always recomputed from the records; the
 * balances (stock, debts, capital) are remembered at each month end ({@see self::remember()}) because the past cannot be
 * recomputed from today's stock.
 */
final class MonthlyFigures
{
    public const TIMEZONE = 'Africa/Dar_es_Salaam';

    /** @return array{0: Carbon, 1: Carbon} first and last day of the month, local time */
    public static function bounds(string $month): array
    {
        $start = Carbon::createFromFormat('!Y-m', $month, self::TIMEZONE)->startOfMonth();

        return [$start, $start->copy()->endOfMonth()];
    }

    public static function valid(string $month): bool
    {
        return preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $month) === 1;
    }

    public static function currentMonth(): string
    {
        return Carbon::now(self::TIMEZONE)->format('Y-m');
    }

    public static function previousMonth(string $month): string
    {
        return self::bounds($month)[0]->copy()->subMonthNoOverflow()->format('Y-m');
    }

    /**
     * The month's figures. `$throughDay` limits it to the first N days (to compare a month in progress with the same days
     * of the month before); null = the whole month.
     *
     * @return array<string, mixed>
     */
    public static function for(string $month, ?int $throughDay = null, ?int $branch = null): array
    {
        [$first, $last] = self::bounds($month);
        $end = $throughDay === null ? $last->copy() : $first->copy()->addDays(max(1, min($throughDay, $first->daysInMonth)) - 1);
        $fromUtc = $first->copy()->startOfDay()->utc()->format('Y-m-d H:i:s');
        $toUtc = $end->copy()->endOfDay()->utc()->format('Y-m-d H:i:s');

        $sales = fn () => DB::table('inventory_sales as s')
            ->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')
            ->whereBetween('s.created_at', [$fromUtc, $toUtc])
            ->when($branch !== null, fn ($q) => $q->where('s.branch_id', $branch));

        $revenue = (float) $sales()->sum('s.total');
        $count = (int) $sales()->count();
        $cogs = (float) DB::table('inventory_sale_items as si')->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')
            ->whereBetween('s.created_at', [$fromUtc, $toUtc])
            ->when($branch !== null, fn ($q) => $q->where('s.branch_id', $branch))
            ->sum(DB::raw('si.unit_cost_snapshot * si.quantity'));

        $expenseQuery = fn () => DB::table('inventory_expenses')->whereBetween('expense_date', [$first->toDateString(), $end->toDateString()])
            ->when(Schema::hasColumn('inventory_expenses', 'status'), fn ($q) => $q->where('status', 'approved'))
            ->when($branch !== null, fn ($q) => $q->where('branch_id', $branch));
        $hasPersonal = Schema::hasColumn('inventory_expenses', 'is_personal');
        $business = $expenseQuery()->when($hasPersonal, fn ($q) => $q->where('is_personal', false));
        $byCategory = (clone $business)->groupBy('category')->orderByRaw('SUM(amount) DESC')
            ->get(['category', DB::raw('SUM(amount) as total')])->map(fn ($r) => ['category' => $r->category, 'total' => round((float) $r->total, 2)])->values()->all();
        $expenses = round((float) (clone $business)->sum('amount'), 2);
        $personal = $hasPersonal ? round((float) $expenseQuery()->where('is_personal', true)->sum('amount'), 2) : 0.0;

        // A write-off belongs to the whole business, not to one branch.
        $writeOffs = $branch === null && Schema::hasTable('inventory_write_offs')
            ? round((float) DB::table('inventory_write_offs')->where('status', 'approved')->whereBetween('approved_at', [$fromUtc, $toUtc])->sum('cost_value'), 2)
            : 0.0;

        $gross = $revenue - $cogs;
        $net = $gross - $expenses - $writeOffs;

        return [
            'month' => $month,
            'from' => $first->toDateString(),
            'to' => $end->toDateString(),
            'days' => $end->day,
            'sales' => round($revenue, 2),
            'sales_count' => $count,
            'cost_of_goods' => round($cogs, 2),
            'gross_profit' => round($gross, 2),
            'margin_percent' => $revenue > 0 ? round($gross / $revenue * 100, 1) : null,
            'expenses' => $expenses,
            'expenses_by_category' => $byCategory,
            'personal_spending' => $personal,
            'write_offs' => $writeOffs,
            'net_profit' => round($net, 2),
        ];
    }

    /**
     * Where the business stands right now.
     *
     * @return array{stock_value: float, receivable: float, payable: float, capital: float, owed_by_sales: float, owed_old: float, payable_invoices: float, payable_old: float}
     */
    public static function position(): array
    {
        // The goods on the shelf at what they cost: the product's own count is the truth (batches exist only for goods that came in on a receipt).
        $stock = round((float) DB::table('inventory_products')->where('is_service', false)->where('quantity', '>', 0)->sum(DB::raw('quantity * cost_price')), 2);
        $salesDebt = round((float) DB::table('inventory_sales')->whereNull('cancelled_at')->whereIn('payment_status', ['debt', 'partial'])->sum(DB::raw('total - paid_total')), 2);
        $oldReceivable = OpeningDebts::outstanding(OpeningDebts::RECEIVABLE);
        $invoices = round((float) DB::table('inventory_supplier_invoices')->whereIn('status', ['open', 'part_paid'])->sum(DB::raw('amount - paid_amount')), 2);
        $oldPayable = OpeningDebts::outstanding(OpeningDebts::PAYABLE);

        $receivable = round($salesDebt + $oldReceivable, 2);
        $payable = round($invoices + $oldPayable, 2);

        return [
            'stock_value' => $stock,
            'receivable' => $receivable,
            'payable' => $payable,
            'capital' => round($stock + $receivable - $payable, 2),
            'owed_by_sales' => $salesDebt,
            'owed_old' => $oldReceivable,
            'payable_invoices' => $invoices,
            'payable_old' => $oldPayable,
        ];
    }

    /** Remember where the business stands for this month (the last time it is called in the month is what stays). */
    public static function remember(string $month): void
    {
        if (!Schema::hasTable('inventory_month_snapshots')) {
            return;
        }
        $p = self::position();
        DB::table('inventory_month_snapshots')->updateOrInsert(
            ['month' => $month],
            ['stock_value' => $p['stock_value'], 'receivable' => $p['receivable'], 'payable' => $p['payable'], 'capital' => $p['capital'], 'updated_at' => now(), 'created_at' => now()],
        );
    }

    /** What was remembered at the end of a month, or null when the app was not yet watching then. */
    public static function remembered(string $month): ?array
    {
        if (!Schema::hasTable('inventory_month_snapshots')) {
            return null;
        }
        $row = DB::table('inventory_month_snapshots')->where('month', $month)->first();

        return $row === null ? null : [
            'stock_value' => (float) $row->stock_value, 'receivable' => (float) $row->receivable,
            'payable' => (float) $row->payable, 'capital' => (float) $row->capital,
        ];
    }

    /** How a figure moved: the change in percent, and whether it is up, down or the same (within one percent). */
    public static function compare(float $now, float $before): array
    {
        $percent = abs($before) < 0.005 ? null : round(($now - $before) / abs($before) * 100, 1);
        $direction = $percent === null ? ($now > 0.005 ? 'up' : ($now < -0.005 ? 'down' : 'same')) : ($percent > 1 ? 'up' : ($percent < -1 ? 'down' : 'same'));

        return ['now' => round($now, 2), 'before' => round($before, 2), 'change' => round($now - $before, 2), 'percent' => $percent, 'direction' => $direction];
    }
}
