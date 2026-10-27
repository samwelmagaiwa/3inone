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

    /**
     * Each tool names its service and what opens it: Inventory/Salon tools by the inv_* rights (`any`), Transport and Rental tools
     * by the roles the matching routes admit (`roles`) or an explicit grant (`grants`), exactly as the route middleware decides.
     *
     * @return array<string, array<string, mixed>>
     */
    public static function catalog(): array
    {
        $month = ['month' => ['type' => 'STRING', 'description' => 'YYYY-MM; the current month when omitted']];
        $limit = ['limit' => ['type' => 'INTEGER', 'description' => 'How many, at most 15']];

        return [
            // ---- Shop / depot / salon (the sales engine)
            'business_report' => ['service' => 'inventory', 'any' => ['inv_view_reports'], 'params' => $month,
                'description' => 'Sales, profit, expenses, money position, what the business owes suppliers, and best products/customers for one month, compared with the month before.'],
            'customers_who_owe' => ['service' => 'inventory', 'any' => ['inv_view_credit'], 'params' => $limit,
                'description' => 'Customers who owe the business money (credit sales and old debts), biggest first, with how many days.'],
            'find_customer' => ['service' => 'inventory', 'any' => ['inv_manage_products', 'inv_create_sales', 'inv_view_credit'],
                'params' => ['name' => ['type' => 'STRING', 'description' => 'Part of the customer name']],
                'description' => 'Look a customer up by name: what they bought and, when allowed, what they owe.'],
            'customer_report' => ['service' => 'inventory', 'any' => ['inv_view_credit'],
                'params' => [
                    'name' => ['type' => 'STRING', 'description' => 'Part of the customer name'],
                    'period' => ['type' => 'STRING', 'description' => 'week, month (default) or year'],
                ],
                'description' => 'One customer: for a week, month or year, how much they bought and paid, the profit they brought (only for people who may see profit), what they buy most and what they owe now.'],
            'find_products' => ['service' => 'inventory', 'any' => ['inv_view_products'],
                'params' => ['search' => ['type' => 'STRING', 'description' => 'Part of the product name'], 'low_stock_only' => ['type' => 'BOOLEAN', 'description' => 'Only goods at or under their minimum stock']],
                'description' => 'Goods or services with stock and price; can list only what is low on stock.'],
            'recent_sales' => ['service' => 'inventory', 'any' => ['inv_create_sales'],
                'params' => ['days' => ['type' => 'INTEGER', 'description' => 'Look back this many days, at most 31'], 'status' => ['type' => 'STRING', 'description' => 'paid, debt or partial']],
                'description' => 'Recent sales with customer, items, total, paid amount and status.'],
            'expenses_summary' => ['service' => 'inventory', 'any' => ['inv_view_expenses'], 'params' => $month,
                'description' => 'Business spending by kind for one month.'],
            'staff_sales' => ['service' => 'inventory', 'any' => ['inv_view_reports'], 'params' => $month,
                'description' => 'Sales by staff member for a month (for a salon: how much each stylist earned the business, with how many services).'],
            // ---- Transport
            'transport_overview' => ['service' => 'transport', 'roles' => ['admin'], 'grants' => ['view_reports_transport', 'manage_drivers_transport', 'manage_vehicles_transport', 'manage_payments_transport', 'manage_debts_transport'], 'params' => [],
                'description' => 'Transport business at a glance: drivers, vehicles, money collected this month, unpaid driver debt.'],
            'transport_drivers' => ['service' => 'transport', 'roles' => ['admin'], 'grants' => ['manage_drivers_transport', 'manage_vehicles_transport'],
                'params' => ['search' => ['type' => 'STRING', 'description' => 'Part of the driver name']],
                'description' => 'Drivers with their vehicles and licence expiry.'],
            'transport_debts' => ['service' => 'transport', 'roles' => ['admin', 'driver'], 'grants' => ['manage_debts_transport'], 'params' => $limit,
                'description' => 'Drivers who owe the business (unpaid daily targets), biggest first, with days overdue. A driver sees only their own.'],
            'transport_payments' => ['service' => 'transport', 'roles' => ['admin', 'driver'], 'grants' => ['manage_payments_transport'],
                'params' => ['days' => ['type' => 'INTEGER', 'description' => 'Look back this many days, at most 31']],
                'description' => 'Recent driver payments with amount, date and channel. A driver sees only their own.'],
            // ---- Rental
            'rental_overview' => ['service' => 'rental', 'roles' => ['admin', 'landlord'], 'grants' => ['view_reports_rental', 'manage_properties_rental', 'manage_houses_rental', 'manage_billing_rental'], 'params' => [],
                'description' => 'Rental business at a glance: properties, houses occupied/vacant, rent collected this month, rent owed, open maintenance.'],
            'rental_arrears' => ['service' => 'rental', 'roles' => ['admin', 'landlord', 'tenant'], 'grants' => ['manage_billing_rental'], 'params' => $limit,
                'description' => 'Tenants who owe rent, biggest first, with house and number of unpaid bills. A tenant sees only their own.'],
            'rental_houses' => ['service' => 'rental', 'roles' => ['admin', 'landlord'], 'grants' => ['manage_houses_rental', 'manage_properties_rental'],
                'params' => ['status' => ['type' => 'STRING', 'description' => 'vacant, occupied or maintenance'], 'search' => ['type' => 'STRING', 'description' => 'Part of the house number']],
                'description' => 'Houses with property, status and monthly rent.'],
            'rental_maintenance' => ['service' => 'rental', 'roles' => ['admin', 'landlord', 'caretaker', 'tenant', 'vendor'], 'grants' => ['manage_maintenance_rental'], 'params' => [],
                'description' => 'Open maintenance requests with house, category and priority (each person sees only theirs).'],
        ];
    }

    /** Whether one tool is open to this user: the business has the service, and the person holds the right the matching screen needs. */
    private static function opens(array $tool, User $user): bool
    {
        // The platform owner runs businesses, they are not one: no business data through the assistant.
        if ($user->seesAllAccounts()) {
            return false;
        }

        if ($tool['service'] === 'inventory') {
            if (!$user->canUseService('inventory') && !$user->canUseService('salon')) {
                return false;
            }
            foreach ($tool['any'] as $right) {
                if ($user->hasInventoryPermission($right)) {
                    return true;
                }
            }

            return false;
        }

        if (!$user->canUseService($tool['service'])) {
            return false;
        }
        if (in_array(strtolower((string) $user->role), $tool['roles'], true)) {
            return true;
        }
        foreach ($tool['grants'] as $grant) {
            if ($user->hasExplicitGrant($grant)) {
                return true;
            }
        }

        return false;
    }

    /** @return array<string, array<string, mixed>> the catalog entries this user's rights open */
    public static function allowedFor(User $user): array
    {
        return array_filter(self::catalog(), fn (array $tool) => self::opens($tool, $user));
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
            'customer_report' => self::customerReport($args, $user),
            'find_products' => self::findProducts($args, $user),
            'recent_sales' => self::recentSales($args, $user),
            'expenses_summary' => self::expensesSummary($args),
            'staff_sales' => self::staffSales($args),
            'transport_overview' => TransportTools::overview(),
            'transport_drivers' => TransportTools::drivers($args),
            'transport_debts' => TransportTools::debts($args),
            'transport_payments' => TransportTools::payments($args),
            'rental_overview' => RentalTools::overview(),
            'rental_arrears' => RentalTools::arrears($args),
            'rental_houses' => RentalTools::houses($args),
            'rental_maintenance' => RentalTools::maintenance($args),
        };
    }

    private static function staffSales(array $args): array
    {
        $month = self::month($args);
        [$first, $last] = MonthlyFigures::bounds($month);
        $rows = DB::table('inventory_sale_items as si')->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->whereNull('s.cancelled_at')->whereNotNull('si.staff_name')->where('si.staff_name', '!=', '')
            ->whereBetween('s.created_at', [$first->copy()->startOfDay()->utc()->format('Y-m-d H:i:s'), $last->copy()->endOfDay()->utc()->format('Y-m-d H:i:s')])
            ->groupBy('si.staff_name')->orderByRaw('SUM(si.total) DESC')->limit(self::MAX_ROWS)
            ->get(['si.staff_name', DB::raw('COUNT(*) as services'), DB::raw('SUM(si.total) as sales')])
            ->map(fn ($r) => ['staff' => $r->staff_name, 'items_sold' => (int) $r->services, 'sales' => round((float) $r->sales, 2)])->all();

        return ['data' => ['month' => $month, 'currency' => 'TSh', 'staff' => $rows], 'card' => $rows === [] ? null : ['type' => 'rows', 'title' => 'Staff ' . $month, 'rows' => array_map(
            fn ($r) => ['title' => $r['staff'], 'value' => self::tsh($r['sales']), 'note' => $r['items_sold'] . ' items'], $rows
        )]];
    }

    /**
     * One-tap questions for this person: each one the tools they hold can answer, plus "how do I..." questions for the services they have.
     * A suggestion with a `tool` is answered in ONE AI call (the server reads the data first), which is what makes it fast.
     *
     * @return array<int, array{id: string, en: string, sw: string, tool: ?string, args: array<string, mixed>}>
     */
    public static function suggestionsFor(User $user): array
    {
        $tools = self::allowedFor($user);
        $all = [
            ['sg_owe', 'Who owes me?', 'Nani ananidai?', 'customers_who_owe', []],
            ['sg_month', 'How is the business this month?', 'Biashara inaendeleaje mwezi huu?', 'business_report', []],
            ['sg_low', 'Which goods are running low?', 'Bidhaa gani zinaisha?', 'find_products', ['low_stock_only' => true]],
            ['sg_sales', 'Sales this week', 'Mauzo ya wiki hii', 'recent_sales', ['days' => 7]],
            ['sg_spend', 'Spending this month', 'Matumizi ya mwezi huu', 'expenses_summary', []],
            ['sg_staff', 'How did each staff member do this month?', 'Kila mhudumu amefanyaje mwezi huu?', 'staff_sales', []],
            ['sg_t_over', 'How is my transport business?', 'Biashara yangu ya usafiri inaendeleaje?', 'transport_overview', []],
            ['sg_t_debt', 'Which drivers owe me?', 'Madereva gani wananidai?', 'transport_debts', []],
            ['sg_t_pay', 'Driver payments this week', 'Malipo ya madereva wiki hii', 'transport_payments', ['days' => 7]],
            ['sg_r_over', 'How is my rental business?', 'Biashara yangu ya kupangisha inaendeleaje?', 'rental_overview', []],
            ['sg_r_owe', 'Which tenants owe rent?', 'Wapangaji gani wanadaiwa kodi?', 'rental_arrears', []],
            ['sg_r_vac', 'Which houses are vacant?', 'Nyumba gani ziko wazi?', 'rental_houses', ['status' => 'vacant']],
            ['sg_r_fix', 'Open repair requests', 'Maombi ya matengenezo yaliyo wazi', 'rental_maintenance', []],
        ];
        $out = [];
        foreach ($all as [$id, $en, $sw, $tool, $args]) {
            if (isset($tools[$tool])) {
                $out[] = ['id' => $id, 'en' => $en, 'sw' => $sw, 'tool' => $tool, 'args' => $args];
            }
        }
        // How-to questions need no data, so every signed-in person gets them, for the services they have.
        foreach (AppGuide::suggestionsFor($user) as $s) {
            $out[] = $s + ['tool' => null, 'args' => []];
        }

        return $out;
    }

    /** Find one suggestion by id for this user, or null when it is not one of theirs. */
    public static function suggestion(User $user, string $id): ?array
    {
        foreach (self::suggestionsFor($user) as $s) {
            if ($s['id'] === $id) {
                return $s;
            }
        }

        return null;
    }

    // ------------------------------------------------------------------ the tools

    private static function businessReport(array $args): array
    {
        $month = self::month($args);
        $r = MonthlyReport::build($month, \App\Support\Salon\SalonBranch::selected());

        return ['data' => [
            'month' => $month, 'currency' => 'TSh', 'figures' => $r['figures'], 'compared_with' => $r['previous']['month'],
            'change' => collect($r['compare'])->map(fn ($c) => ['now' => $c['now'], 'before' => $c['before'], 'percent' => $c['percent']])->all(),
            'position' => $r['position'], 'profit_target' => $r['target'],
            'business_owes' => array_map(fn ($d) => ['name' => $d['name'], 'left' => $d['left'], 'days_late' => $d['days_late']], $r['creditors']),
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

    private static function customerReport(array $args, User $user): array
    {
        $needle = self::text($args['name'] ?? '', 60);
        if ($needle === '') {
            return ['data' => ['error' => 'Give a customer name.'], 'card' => null];
        }
        $customer = DB::table('inventory_customers')->where('name', 'like', '%' . self::like($needle) . '%')->orderBy('name')->first(['id', 'name']);
        if ($customer === null) {
            return ['data' => ['error' => 'No customer with that name.'], 'card' => null];
        }
        $today = now(MonthlyFigures::TIMEZONE);
        $period = in_array($args['period'] ?? '', ['week', 'year'], true) ? $args['period'] : 'month';
        $from = match ($period) {
            'week' => $today->copy()->startOfWeek(\Carbon\Carbon::MONDAY),
            'year' => $today->copy()->startOfYear(),
            default => $today->copy()->startOfMonth(),
        };
        $r = \App\Support\Inventory\CustomerReport::build((int) $customer->id, $from->toDateString(), $today->toDateString(), $period === 'year' ? 'month' : ($period === 'week' ? 'day' : 'week'), $user);
        // The AI reads names and numbers only; the phone is shown on the card, from the record.
        $data = ['currency' => 'TSh', 'customer' => $r['customer']['name'], 'period' => $period, 'from' => $r['from'], 'to' => $r['to'], 'totals' => $r['totals'], 'owes_now' => $r['debt'], 'lifetime' => $r['lifetime'], 'top_products' => $r['top_products']];
        $rows = [
            ['title' => 'Bought', 'value' => self::tsh($r['totals']['sales']), 'note' => $r['totals']['purchases'] . ' purchases'],
            ['title' => 'Paid', 'value' => self::tsh($r['totals']['paid'])],
        ];
        if ($r['profit_visible']) {
            $rows[] = ['title' => 'Profit brought', 'value' => self::tsh((float) $r['totals']['profit'])];
        }
        $rows[] = ['title' => 'Owes now', 'value' => self::tsh($r['debt']['owes_now'])];

        return ['data' => $data, 'card' => ['type' => 'rows', 'title' => $customer->name . ' (' . $period . ')', 'rows' => $rows]];
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
        $f = MonthlyFigures::for($month, null, \App\Support\Salon\SalonBranch::selected());

        return ['data' => ['month' => $month, 'currency' => 'TSh', 'total' => $f['expenses'], 'by_kind' => $f['expenses_by_category']], 'card' => ['type' => 'rows', 'title' => 'Expenses ' . $month, 'rows' => array_map(
            fn ($c) => ['title' => (string) $c['category'], 'value' => self::tsh((float) $c['total'])], $f['expenses_by_category']
        )]];
    }

    // ------------------------------------------------------------------ small helpers

    public static function month(array $args): string
    {
        $m = (string) ($args['month'] ?? '');

        return MonthlyFigures::valid($m) ? $m : MonthlyFigures::currentMonth();
    }

    public static function limit(array $args): int
    {
        return max(1, min(self::MAX_ROWS, (int) ($args['limit'] ?? 10)));
    }

    public static function text(mixed $v, int $max): string
    {
        return mb_substr(trim(is_scalar($v) ? (string) $v : ''), 0, $max);
    }

    /** Escape the LIKE wildcards so a name search cannot match everything. */
    public static function like(string $s): string
    {
        return addcslashes($s, '%_\\');
    }

    public static function tsh(float|int|string $n): string
    {
        return 'TSh ' . number_format(round((float) $n), 0, '.', ',');
    }
}
