<?php

namespace App\Support\Ai;

use App\Models\User;
use App\Support\Inventory\MonthlyFigures;
use App\Support\Inventory\MonthlyReport;
use App\Support\Inventory\SalesVisibility;
use Illuminate\Support\Facades\DB;

/**
 * The only things the AI assistant can look at. Each tool names the rights that open it -- the same inv_* rights that guard the
 * matching screens and routes -- and a user's assistant is handed only the tools their rights open, so it cannot be talked into
 * reading what the person could not open themselves. Every query runs inside the business (tenant) scope, and sales are limited
 * to the user's own unless their role sees everyone's ({@see SalesVisibility}).
 *
 * A tool returns `data` (what the AI reads: names and numbers only, never a phone number) and optionally `card` (what the app
 * shows the person, built here from the records themselves so names and amounts are never retyped by the AI).
 */
final class AssistantTools
{
    private const MAX_ROWS = 15;

    /** @return array<string, array{description: string, params: array<string, array<string, mixed>>, any: array<int, string>}> */
    public static function catalog(): array
    {
        return [
            'business_report' => [
                'description' => 'Sales, profit, expenses, money position and best products/customers for one month, compared with the month before.',
                'params' => ['month' => ['type' => 'STRING', 'description' => 'YYYY-MM; the current month when omitted']],
                'any' => ['inv_view_reports'],
            ],
            'customers_who_owe' => [
                'description' => 'Customers who owe the business money (credit sales and old debts), biggest first, with how many days.',
                'params' => ['limit' => ['type' => 'INTEGER', 'description' => 'How many, at most 15']],
                'any' => ['inv_view_credit'],
            ],
            'find_customer' => [
                'description' => 'Look a customer up by name: what they bought and, when allowed, what they owe.',
                'params' => ['name' => ['type' => 'STRING', 'description' => 'Part of the customer name']],
                'any' => ['inv_manage_products', 'inv_create_sales', 'inv_view_credit'],
            ],
            'find_products' => [
                'description' => 'Goods or services with stock and price; can list only what is low on stock.',
                'params' => [
                    'search' => ['type' => 'STRING', 'description' => 'Part of the product name'],
                    'low_stock_only' => ['type' => 'BOOLEAN', 'description' => 'Only goods at or under their minimum stock'],
                ],
                'any' => ['inv_view_products'],
            ],
            'recent_sales' => [
                'description' => 'Recent sales with customer, items, total, paid amount and status.',
                'params' => [
                    'days' => ['type' => 'INTEGER', 'description' => 'Look back this many days, at most 31'],
                    'status' => ['type' => 'STRING', 'description' => 'paid, debt or partial'],
                ],
                'any' => ['inv_create_sales'],
            ],
            'expenses_summary' => [
                'description' => 'Business spending by kind for one month.',
                'params' => ['month' => ['type' => 'STRING', 'description' => 'YYYY-MM; the current month when omitted']],
                'any' => ['inv_view_expenses'],
            ],
        ];
    }

    /** @return array<string, array<string, mixed>> the catalog entries this user's rights open */
    public static function allowedFor(User $user): array
    {
        return array_filter(self::catalog(), function (array $tool) use ($user) {
            foreach ($tool['any'] as $right) {
                if ($user->hasInventoryPermission($right)) {
                    return true;
                }
            }

            return false;
        });
    }

    /**
     * Run one tool for a user. A tool the user's rights do not open answers with an error the AI can relay, never with data.
     *
     * @param  array<string, mixed>  $args
     * @return array{data: array<string, mixed>, card: ?array<string, mixed>}
     */
    public static function run(string $name, array $args, User $user): array
    {
        if (!array_key_exists($name, self::allowedFor($user))) {
            return ['data' => ['error' => 'Not allowed: this person does not have the right to see that.'], 'card' => null];
        }

        return match ($name) {
            'business_report' => self::businessReport($args),
            'customers_who_owe' => self::customersWhoOwe($args),
            'find_customer' => self::findCustomer($args, $user),
            'find_products' => self::findProducts($args, $user),
            'recent_sales' => self::recentSales($args, $user),
            'expenses_summary' => self::expensesSummary($args),
        };
    }

    // ------------------------------------------------------------------ the tools

    private static function businessReport(array $args): array
    {
        $month = self::month($args);
        $r = MonthlyReport::build($month);

        return ['data' => [
            'month' => $month, 'currency' => 'TSh', 'figures' => $r['figures'], 'compared_with' => $r['previous']['month'],
            'change' => collect($r['compare'])->map(fn ($c) => ['now' => $c['now'], 'before' => $c['before'], 'percent' => $c['percent']])->all(),
            'position' => $r['position'], 'profit_target' => $r['target'],
            'best_products_by_profit' => $r['top_products'], 'best_customers' => $r['top_customers'],
        ], 'card' => ['type' => 'rows', 'title' => $month, 'rows' => [
            ['title' => 'Sales', 'value' => self::tsh($r['figures']['sales'])],
            ['title' => 'Expenses', 'value' => self::tsh($r['figures']['expenses'])],
            ['title' => 'Profit', 'value' => self::tsh($r['figures']['net_profit'])],
        ]]];
    }

    private static function customersWhoOwe(array $args): array
    {
        $rows = MonthlyReport::debtors(self::limit($args));

        return ['data' => ['currency' => 'TSh', 'customers' => $rows], 'card' => $rows === [] ? null : ['type' => 'rows', 'title' => 'Owe the business', 'rows' => array_map(
            fn ($d) => ['title' => $d['name'], 'value' => self::tsh($d['owed']), 'note' => $d['days'] . ' days'], $rows
        )]];
    }

    private static function findCustomer(array $args, User $user): array
    {
        $needle = self::text($args['name'] ?? '', 60);
        if ($needle === '') {
            return ['data' => ['error' => 'Give a customer name.'], 'card' => null];
        }
        $customers = DB::table('inventory_customers')->where('name', 'like', '%' . self::like($needle) . '%')->orderBy('name')->limit(8)->get(['id', 'name', 'phone', 'address']);
        $sees = SalesVisibility::seesAll($user);
        $mayOwe = $user->hasInventoryPermission('inv_view_credit');

        $data = [];
        $cards = [];
        foreach ($customers as $c) {
            $sales = DB::table('inventory_sales')->where('customer_id', $c->id)->whereNull('cancelled_at');
            if (!$sees) {
                $sales->where('created_by', $user->id);
            }
            $sum = (clone $sales)->selectRaw('COUNT(*) as n, COALESCE(SUM(total),0) as spent, MAX(created_at) as last_at')->first();
            $row = ['name' => $c->name, 'purchases' => (int) $sum->n, 'spent' => round((float) $sum->spent, 2), 'last_purchase' => $sum->last_at];
            $note = $sum->n . ' purchases, ' . self::tsh((float) $sum->spent);
            if ($mayOwe) {
                $owed = (float) (clone $sales)->whereIn('payment_status', ['debt', 'partial'])->selectRaw('COALESCE(SUM(total - paid_total),0) as o')->value('o');
                $row['owes'] = round($owed, 2);
                $note .= $owed > 0 ? ', owes ' . self::tsh($owed) : ', owes nothing';
            }
            $data[] = $row;
            $cards[] = ['title' => $c->name, 'value' => (string) $c->phone, 'note' => $note];
        }

        return ['data' => ['currency' => 'TSh', 'customers' => $data, 'found' => count($data)], 'card' => $cards === [] ? null : ['type' => 'rows', 'title' => 'Customers', 'rows' => $cards]];
    }

    private static function findProducts(array $args, User $user): array
    {
        $q = DB::table('inventory_products')->where('status', 'active')->orderBy('name')->limit(self::MAX_ROWS);
        $search = self::text($args['search'] ?? '', 60);
        if ($search !== '') {
            $q->where('name', 'like', '%' . self::like($search) . '%');
        }
        if (!empty($args['low_stock_only'])) {
            $q->where('is_service', false)->whereColumn('quantity', '<=', 'min_stock');
        }
        $showCost = $user->hasInventoryPermission('inv_view_reports') || $user->hasInventoryPermission('inv_manage_products');
        $rows = $q->get(['name', 'unit', 'quantity', 'min_stock', 'selling_price', 'cost_price', 'is_service']);

        $data = $rows->map(function ($p) use ($showCost) {
            $row = ['name' => $p->name, 'selling_price' => round((float) $p->selling_price, 2)] + ($p->is_service ? ['kind' => 'service'] : ['unit' => $p->unit, 'in_stock' => (int) $p->quantity, 'minimum_stock' => (int) $p->min_stock]);

            return $showCost ? $row + ['cost_price' => round((float) $p->cost_price, 2)] : $row;
        })->all();

        return ['data' => ['currency' => 'TSh', 'products' => $data], 'card' => $rows->isEmpty() ? null : ['type' => 'rows', 'title' => 'Products', 'rows' => $rows->map(fn ($p) => [
            'title' => $p->name, 'value' => self::tsh((float) $p->selling_price), 'note' => $p->is_service ? 'service' : $p->quantity . ' ' . $p->unit . ' in stock',
        ])->all()]];
    }

    private static function recentSales(array $args, User $user): array
    {
        $days = max(1, min(31, (int) ($args['days'] ?? 7)));
        $q = DB::table('inventory_sales as s')->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->whereNull('s.cancelled_at')->where('s.created_at', '>=', now()->subDays($days)->format('Y-m-d H:i:s'))
            ->orderByDesc('s.id')->limit(self::MAX_ROWS);
        if (!SalesVisibility::seesAll($user)) {
            $q->where('s.created_by', $user->id);
        }
        if (in_array($args['status'] ?? '', ['paid', 'debt', 'partial'], true)) {
            $q->where('s.payment_status', $args['status']);
        }
        $sales = $q->get(['s.id', 's.number', 's.total', 's.paid_total', 's.payment_status', 's.created_at', DB::raw('COALESCE(c.name, s.customer_name_override) as customer')]);
        $items = $sales->isEmpty() ? collect() : DB::table('inventory_sale_items as si')->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->whereIn('si.sale_id', $sales->pluck('id'))->get(['si.sale_id', 'p.name', 'si.quantity'])->groupBy('sale_id');

        $data = $sales->map(fn ($s) => [
            'number' => $s->number, 'date' => substr((string) $s->created_at, 0, 10), 'customer' => $s->customer ?: 'Walk-in',
            'items' => ($items[$s->id] ?? collect())->map(fn ($i) => $i->name . ' x' . (int) $i->quantity)->implode(', '),
            'total' => round((float) $s->total, 2), 'paid' => round((float) $s->paid_total, 2), 'status' => $s->payment_status,
        ])->all();

        return ['data' => ['currency' => 'TSh', 'days' => $days, 'sales' => $data], 'card' => $data === [] ? null : ['type' => 'rows', 'title' => 'Sales', 'rows' => array_map(fn ($s) => [
            'title' => $s['customer'], 'value' => self::tsh($s['total']), 'note' => $s['date'] . ' · ' . $s['status'],
        ], $data)]];
    }

    private static function expensesSummary(array $args): array
    {
        $month = self::month($args);
        $f = MonthlyFigures::for($month);

        return ['data' => ['month' => $month, 'currency' => 'TSh', 'total' => $f['expenses'], 'by_kind' => $f['expenses_by_category']], 'card' => ['type' => 'rows', 'title' => 'Expenses ' . $month, 'rows' => array_map(
            fn ($c) => ['title' => (string) $c['category'], 'value' => self::tsh((float) $c['total'])], $f['expenses_by_category']
        )]];
    }

    // ------------------------------------------------------------------ small helpers

    private static function month(array $args): string
    {
        $m = (string) ($args['month'] ?? '');

        return MonthlyFigures::valid($m) ? $m : MonthlyFigures::currentMonth();
    }

    private static function limit(array $args): int
    {
        return max(1, min(self::MAX_ROWS, (int) ($args['limit'] ?? 10)));
    }

    private static function text(mixed $v, int $max): string
    {
        return mb_substr(trim(is_scalar($v) ? (string) $v : ''), 0, $max);
    }

    /** Escape the LIKE wildcards so a name search cannot match everything. */
    private static function like(string $s): string
    {
        return addcslashes($s, '%_\\');
    }

    private static function tsh(float|int|string $n): string
    {
        return 'TSh ' . number_format(round((float) $n), 0, '.', ',');
    }
}
