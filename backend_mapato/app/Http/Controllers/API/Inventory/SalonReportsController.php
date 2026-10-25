<?php

namespace App\Http\Controllers\API\Inventory;

use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\SalonAccess;
use App\Support\Salon\SalonBranch;
use App\Support\Salon\SalonFinance;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use OpenApi\Attributes as OA;

/**
 * The salon's reports in one page for a period: takings by service, by stylist, by way of payment and by branch;
 * spending by category; how the diary went (booked, done, no-shows, cancelled, booked online); the clients (new, returning,
 * the best spenders, those who stopped coming, birthdays); what clients still owe; and what the goods on the shelves are
 * worth. Whoever holds the "reports" right (the owner and the accountant by default).
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Salon reports')]
class SalonReportsController extends Controller
{
    /** A client who has not been for this many weeks has "stopped coming". */
    private const INACTIVE_WEEKS = 8;

    #[OA\Get(path: '/inventory/salon/reports', summary: 'All the salon\'s reports for a period', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function index(Request $request): JsonResponse
    {
        abort_unless(SalonAccess::isManager($request->user()), 403, 'Ni mmiliki au mhasibu tu. / Only the owner or the accountant.');
        $data = $request->validate(['from' => 'nullable|date_format:Y-m-d', 'to' => 'nullable|date_format:Y-m-d|after_or_equal:from']);
        $tz = AppointmentPlanner::TIMEZONE;
        $today = Carbon::now($tz)->startOfDay();
        $from = Carbon::parse($data['from'] ?? $today->copy()->startOfMonth()->toDateString(), $tz)->startOfDay();
        $to = Carbon::parse($data['to'] ?? $today->toDateString(), $tz)->startOfDay();
        $branch = SalonBranch::selected($request);
        $f = $from->toDateString();
        $t = $to->toDateString();
        $hasBranch = $branch !== null && Schema::hasColumn('inventory_sales', 'branch_id');

        $summary = SalonFinance::summary($from, $to, $branch);

        // ---- takings by service and by stylist (revenue is what the line sold for after its share of the discount)
        $lines = fn () => DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->whereNull('s.cancelled_at')
            ->whereDate('s.created_at', '>=', $f)->whereDate('s.created_at', '<=', $t)
            ->when($hasBranch, fn ($q) => $q->where('s.branch_id', $branch));
        $net = 'SUM(si.total - COALESCE(s.discount * si.total / NULLIF(s.subtotal, 0), 0))';

        // What each service's goods cost (shampoo, dye, towels set on the service), so a service's profit is its own.
        $materials = Schema::hasTable('inventory_service_usage')
            ? DB::table('inventory_service_usage as u')
                ->join('inventory_sale_items as si', 'si.id', '=', 'u.sale_item_id')
                ->join('inventory_sales as s', 's.id', '=', 'u.sale_id')
                ->whereNull('s.cancelled_at')
                ->whereDate('s.created_at', '>=', $f)->whereDate('s.created_at', '<=', $t)
                ->when($hasBranch, fn ($q) => $q->where('s.branch_id', $branch))
                ->groupBy('si.product_id')->selectRaw('si.product_id as id, SUM(u.quantity * u.unit_cost) as cost')->pluck('cost', 'id')
            : collect();

        $byService = $lines()->where('si.is_service', true)->groupBy('si.product_id', 'p.name')
            ->selectRaw("si.product_id as id, p.name as name, SUM(COALESCE(si.unit_qty, si.quantity)) as times, {$net} as revenue, SUM(COALESCE(si.commission_amount, 0)) as commission")
            ->orderByRaw("{$net} DESC")->limit(30)->get()
            ->map(fn ($r) => [
                'name' => (string) $r->name, 'times' => (int) $r->times, 'revenue' => SalonFinance::money($r->revenue),
                'commission' => SalonFinance::money($r->commission), 'materials_cost' => SalonFinance::money($materials[$r->id] ?? 0),
                'profit' => SalonFinance::money((float) $r->revenue - (float) $r->commission - (float) ($materials[$r->id] ?? 0)),
            ])->values();

        $byStylist = $lines()->where('si.is_service', true)->groupBy('si.staff_id')
            ->selectRaw("MAX(si.staff_name) as name, COUNT(*) as services, COUNT(DISTINCT s.customer_id) as clients, {$net} as revenue")
            ->orderByRaw("{$net} DESC")->get()
            ->map(fn ($r) => ['name' => $r->name ?: '—', 'services' => (int) $r->services, 'clients' => (int) $r->clients, 'revenue' => SalonFinance::money($r->revenue)])->values();

        $goods = $lines()->where(fn ($q) => $q->where('si.is_service', false)->orWhereNull('si.is_service'))->groupBy('si.product_id', 'p.name')
            ->selectRaw("p.name as name, SUM(COALESCE(si.unit_qty, si.quantity)) as qty, {$net} as revenue, SUM(si.unit_cost_snapshot * si.quantity) as cost")
            ->orderByRaw("{$net} DESC")->limit(15)->get()
            ->map(fn ($r) => ['name' => (string) $r->name, 'qty' => (int) $r->qty, 'revenue' => SalonFinance::money($r->revenue), 'cost' => SalonFinance::money($r->cost), 'profit' => SalonFinance::money((float) $r->revenue - (float) $r->cost)])->values();

        // ---- by branch (only when the salon has branches; one number per branch)
        $byBranch = [];
        if ($branch === null && Schema::hasTable('inventory_branches') && Schema::hasColumn('inventory_sales', 'branch_id')) {
            foreach (DB::table('inventory_branches')->orderBy('name')->get(['id', 'name']) as $b) {
                $s = SalonFinance::summary($from, $to, (int) $b->id);
                $byBranch[] = ['name' => $b->name, 'revenue' => $s['revenue'], 'sales' => $s['sales'], 'net_profit' => $s['net_profit']];
            }
        }

        return response()->json(['data' => [
            'from' => $f,
            'to' => $t,
            'summary' => [
                'revenue' => $summary['revenue'], 'service_revenue' => $summary['service_revenue'], 'goods_revenue' => $summary['goods_revenue'],
                'discounts' => $summary['discounts'], 'expenses' => $summary['expenses'], 'commissions' => $summary['commissions'],
                'net_profit' => $summary['net_profit'], 'sales' => $summary['sales'], 'clients' => $summary['clients'], 'collected' => $summary['collected'],
            ],
            'by_service' => $byService,
            'by_stylist' => $byStylist,
            'goods_sold' => $goods,
            'by_method' => $summary['collections'],
            'by_branch' => $byBranch,
            'expenses_by_category' => $summary['expenses_by_category'],
            'diary' => $this->diary($f, $t, $hasBranch ? $branch : null),
            'clients' => $this->clients($from, $to, $today, $hasBranch ? $branch : null),
            'owed' => $this->owed($today, $hasBranch ? $branch : null),
            'stock' => $this->stock(),
        ]]);
    }

    /** How the diary went: what was booked for the period and how each booking ended. */
    private function diary(string $f, string $t, ?int $branch): array
    {
        $rows = DB::table('inventory_appointments')->whereDate('starts_at', '>=', $f)->whereDate('starts_at', '<=', $t)
            ->when($branch !== null && Schema::hasColumn('inventory_appointments', 'branch_id'), fn ($q) => $q->where('branch_id', $branch))
            ->get(['status', 'source', 'deposit_status', 'deposit_amount']);
        $by = fn (string $s) => $rows->where('status', $s)->count();
        $total = $rows->count();
        $ended = $by('done') + $by('no_show') + $by('cancelled');

        return [
            'booked' => $total,
            'done' => $by('done'),
            'no_show' => $by('no_show'),
            'cancelled' => $by('cancelled'),
            'still_open' => $total - $ended,
            'online' => $rows->where('source', 'online')->count(),
            'no_show_rate' => $ended === 0 ? null : round($by('no_show') * 100 / $ended, 1),
            'deposits_kept' => SalonFinance::money($rows->where('deposit_status', 'forfeited')->sum('deposit_amount')),
        ];
    }

    /** New and returning clients, the best spenders, those who stopped coming and birthdays this month. */
    private function clients(Carbon $from, Carbon $to, Carbon $today, ?int $branch): array
    {
        $tz = AppointmentPlanner::TIMEZONE;
        $visits = DB::table('inventory_sales as s')
            ->join('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->whereNull('s.cancelled_at')
            ->whereExists(fn ($q) => $q->select(DB::raw(1))->from('inventory_sale_items as si')->whereColumn('si.sale_id', 's.id')->where('si.is_service', true))
            ->when($branch !== null, fn ($q) => $q->where('s.branch_id', $branch))
            ->orderBy('s.created_at')
            ->get(['s.customer_id', 's.total', 's.created_at', 'c.name'])
            ->map(fn ($v) => ['id' => (int) $v->customer_id, 'name' => $v->name, 'total' => (float) $v->total, 'at' => Carbon::parse($v->created_at, 'UTC')->setTimezone($tz)]);

        $first = [];
        $last = [];
        foreach ($visits as $v) {
            $first[$v['id']] ??= $v['at'];
            $last[$v['id']] = $v['at'];
        }
        $inPeriod = $visits->filter(fn ($v) => $v['at']->gte($from) && $v['at']->lte($to->copy()->endOfDay()));
        $active = $inPeriod->pluck('id')->unique();
        $new = $active->filter(fn ($id) => $first[$id]->gte($from))->count();

        $top = $inPeriod->groupBy('id')->map(fn ($g) => ['name' => (string) $g->first()['name'], 'visits' => $g->count(), 'spent' => SalonFinance::money($g->sum('total'))])
            ->sortByDesc('spent')->take(10)->values();

        $cut = $today->copy()->subWeeks(self::INACTIVE_WEEKS);
        $inactive = collect($last)->filter(fn ($at) => $at->lt($cut))->count();

        $birthdays = Schema::hasColumn('inventory_customers', 'birthday')
            ? DB::table('inventory_customers')->whereNotNull('birthday')->get(['birthday'])->filter(fn ($c) => (int) Carbon::parse($c->birthday)->format('n') === (int) $today->format('n'))->count()
            : 0;

        return [
            'active' => $active->count(),
            'new' => $new,
            'returning' => $active->count() - $new,
            'top_spenders' => $top,
            'stopped_coming' => $inactive,
            'stopped_after_weeks' => self::INACTIVE_WEEKS,
            'birthdays_this_month' => $birthdays,
        ];
    }

    /** What clients still owe (all time, oldest first), as the owner's chase list. */
    private function owed(Carbon $today, ?int $branch): array
    {
        $rows = DB::table('inventory_sales as s')
            ->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->whereNull('s.cancelled_at')->whereIn('s.payment_status', ['debt', 'partial'])
            ->when($branch !== null, fn ($q) => $q->where('s.branch_id', $branch))
            ->orderBy('s.created_at')
            ->get(['s.number', 's.total', 's.paid_total', 's.created_at', 's.customer_name_override', 'c.name', 'c.phone']);

        return [
            'total' => SalonFinance::money($rows->sum(fn ($r) => (float) $r->total - (float) $r->paid_total)),
            'count' => $rows->count(),
            'list' => $rows->take(20)->map(fn ($r) => [
                'number' => $r->number,
                'client' => $r->name ?: ($r->customer_name_override ?: '—'),
                'phone' => $r->phone,
                'due' => SalonFinance::money((float) $r->total - (float) $r->paid_total),
                'days' => (int) Carbon::parse($r->created_at)->startOfDay()->diffInDays($today),
            ])->values(),
        ];
    }

    /** What the goods on the shelves are worth at cost and at selling price, and how many are low. */
    private function stock(): array
    {
        $goods = DB::table('inventory_products')->where(fn ($q) => $q->where('is_service', false)->orWhereNull('is_service'))->where('status', 'active')
            ->get(['quantity', 'cost_price', 'selling_price', 'min_stock']);

        return [
            'items' => $goods->count(),
            'at_cost' => SalonFinance::money($goods->sum(fn ($g) => (int) $g->quantity * (float) $g->cost_price)),
            'at_price' => SalonFinance::money($goods->sum(fn ($g) => (int) $g->quantity * (float) $g->selling_price)),
            'low' => $goods->filter(fn ($g) => (int) $g->min_stock > 0 && (int) $g->quantity <= (int) $g->min_stock)->count(),
        ];
    }
}
