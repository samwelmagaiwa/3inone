<?php

namespace App\Http\Controllers\API\Inventory;

use App\Services\Inventory\AuditTrail;
use App\Services\Inventory\CrateLedgerService;
use App\Services\Inventory\ProductUnits;
use App\Services\Inventory\StockLedger;
use App\Support\SqlDate;
use App\Support\ClientTime;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Routing\Controller;
use OpenApi\Attributes as OA;

#[OA\Tag(name: 'Inventory / Sales', description: 'POS checkout, sales history, and dashboard KPIs. Every list here is scoped to the caller\'s own sales unless they hold admin/super_admin/manager (see the officer_id filter).')]
class SalesController extends Controller
{
    public function __construct(
        private readonly StockLedger        $ledger,
        private readonly AuditTrail         $audit,
        private readonly CrateLedgerService $crateLedger,
        private readonly ProductUnits       $units,
    ) {
    }

    #[OA\Get(
        path: '/inventory/sales',
        summary: 'List sales (scoped to the caller, unless privileged)',
        description: 'A `sales_officer` always sees only their own sales. `admin`/`super_admin`/'
            . '`manager` see everything, or one specific officer via `officer_id`.',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Sales'],
        parameters: [
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string', enum: ['paid', 'debt', 'partial'])),
            new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
            new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
            new OA\Parameter(name: 'q', in: 'query', description: 'Search sale number/customer name/phone', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'officer_id', in: 'query', description: 'Admin/super_admin/manager only: filter to one sales officer', schema: new OA\Schema(type: 'string', format: 'uuid')),
            new OA\Parameter(name: 'page', in: 'query', schema: new OA\Schema(type: 'integer', default: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Paginated sales list', content: new OA\JsonContent(properties: [
                new OA\Property(property: 'data', type: 'array', items: new OA\Items(type: 'object')),
                new OA\Property(property: 'meta', ref: '#/components/schemas/PaginationMeta'),
            ], type: 'object')),
        ],
    )]
    #[OA\Get(
        path: '/sales',
        summary: 'List sales (scoped to the caller, unless privileged)',
        description: 'A `sales_officer` always sees only their own sales. `admin`/`super_admin`/'
            . '`manager` see everything, or one specific officer via `officer_id`.',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Sales'],
        parameters: [
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string', enum: ['paid', 'debt', 'partial'])),
            new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
            new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
            new OA\Parameter(name: 'q', in: 'query', description: 'Search sale number/customer name/phone', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'officer_id', in: 'query', description: 'Admin/super_admin/manager only: filter to one sales officer', schema: new OA\Schema(type: 'string', format: 'uuid')),
            new OA\Parameter(name: 'page', in: 'query', schema: new OA\Schema(type: 'integer', default: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Paginated sales list', content: new OA\JsonContent(properties: [
                new OA\Property(property: 'data', type: 'array', items: new OA\Items(type: 'object')),
                new OA\Property(property: 'meta', ref: '#/components/schemas/PaginationMeta'),
            ], type: 'object')),
        ],
    )]
    public function index(Request $request)
    {
        $status = $request->query('status');
        $from = $request->query('from');
        $to = $request->query('to');
        $q = $request->query('q');

        $query = $this->applyOfficerScope(
            DB::table('inventory_sales as s')
                ->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
                ->select(
                    's.*',
                    DB::raw("COALESCE(c.name,  s.customer_name_override)  as customer_name"),
                    DB::raw("COALESCE(c.phone, s.customer_phone_override) as customer_phone"),
                ),
            $request,
            's.created_by',
        )->orderByDesc('s.id');

        if ($status && in_array($status, ['paid', 'debt', 'partial'])) {
            $query->where('s.payment_status', $status);
        }

        if ($from) {
            $query->where('s.created_at', '>=', $from . ' 00:00:00');
        }

        if ($to) {
            $query->where('s.created_at', '<=', $to . ' 23:59:59');
        }

        if (!empty($q)) {
            $query->where(function ($sub) use ($q) {
                $sub->where('s.number', 'like', "%{$q}%")
                    ->orWhere('c.name', 'like', "%{$q}%")
                    ->orWhere('c.phone', 'like', "%{$q}%");
            });
        }

        $sales = $query->paginate(20);
        $saleIds = collect($sales->items())->pluck('id')->filter();

        $itemsBySale = [];
        if ($saleIds->isNotEmpty()) {
            $rawItems = DB::table('inventory_sale_items as si')
                ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
                ->whereIn('si.sale_id', $saleIds)
                ->select(
                    'si.*',
                    'p.name as product_name',
                    'p.sku as product_sku'
                )
                ->get()
                ->groupBy('sale_id');
            $itemsBySale = $rawItems;
        }

        // Also batch-load payments for these sales
        $paymentsBySale = [];
        if ($saleIds->isNotEmpty()) {
            $rawPayments = DB::table('inventory_sale_payments')
                ->whereIn('sale_id', $saleIds)
                ->orderBy('id')
                ->get()
                ->groupBy('sale_id');
            $paymentsBySale = $rawPayments;
        }

        $data = collect($sales->items())->map(function ($s) use ($itemsBySale, $paymentsBySale) {
            $sArray = (array) $s;
            $sArray['subtotal']   = (int) $s->subtotal;
            $sArray['discount']   = (int) $s->discount;
            $sArray['discount_reason'] = $s->discount_reason ?? null;
            $sArray['tax']        = (int) $s->tax;
            $sArray['total']      = (int) $s->total;
            $sArray['paid_total'] = (int) $s->paid_total;
            $sItems = $itemsBySale[$s->id] ?? collect();
            $sArray['items'] = $sItems->map(fn ($it) => $this->itemPayload($it))->values()->all();
            $sPayments = $paymentsBySale[$s->id] ?? collect();
            $sArray['payments'] = $sPayments->map(function ($p) {
                return [
                    'id' => (int) $p->id,
                    'amount' => (int) $p->amount,
                    'method' => $p->method_extended ?? $p->method,
                    'reference' => $p->reference,
                    'paid_at' => $p->paid_at,
                ];
            })->values()->all();
            return $sArray;
        });

        return response()->json([
            'data' => $data,
            'meta' => [
                'current_page' => $sales->currentPage(),
                'last_page' => $sales->lastPage(),
                'per_page' => $sales->perPage(),
                'total' => $sales->total(),
            ],
        ]);
    }

    #[OA\Get(

        path: '/inventory/sales/{id}',

        summary: 'Get a single resource',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Sales'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]
    #[OA\Get(
        path: '/sales/{id}',
        summary: 'Get a single resource',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Sales'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function show($id)
    {
        $sale = DB::table('inventory_sales as s')
            ->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->select(
                's.*',
                DB::raw("COALESCE(c.name,  s.customer_name_override)  as customer_name"),
                DB::raw("COALESCE(c.phone, s.customer_phone_override) as customer_phone"),
                'c.address as customer_address'
            )
            ->where('s.id', $id)
            ->first();

        if (!$sale) {
            return response()->json(['message' => 'Sale not found'], 404);
        }

        $saleArray = (array) $sale;

        $items = DB::table('inventory_sale_items as si')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->where('si.sale_id', $id)
            ->select('si.*', 'p.name as product_name', 'p.sku as product_sku')
            ->get();

        $saleArray['items'] = $items->map(fn ($it) => $this->itemPayload($it))->values()->all();

        // Cast sale-level decimals to int
        $saleArray['subtotal']   = (int) $sale->subtotal;
        $saleArray['discount']   = (int) $sale->discount;
        $saleArray['discount_reason'] = $sale->discount_reason ?? null;
        $saleArray['tax']        = (int) $sale->tax;
        $saleArray['total']      = (int) $sale->total;
        $saleArray['paid_total'] = (int) $sale->paid_total;

        $payments = DB::table('inventory_sale_payments')
            ->where('sale_id', $id)
            ->orderBy('id')
            ->get();

        $saleArray['payments'] = $payments->map(function ($p) {
            return [
                'id' => (int) $p->id,
                'amount' => (int) $p->amount,
                'method' => $p->method_extended ?? $p->method,
                'reference' => $p->reference,
                'paid_at' => $p->paid_at,
            ];
        })->values()->all();

        return response()->json(['data' => $saleArray]);
    }

    /**
     * GET /inventory/kpis
     * Lightweight dashboard summary — today's sales, profit and 7/30 day trend.
     */
    #[OA\Get(
        path: '/inventory/kpis',
        summary: 'Dashboard KPIs: today, 7/30-day trend, top products',
        description: 'Same officer-scoping as GET /inventory/sales -- pass `officer_id` (privileged '
            . 'roles only) to filter the whole dashboard to one sales officer.',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Sales'],
        parameters: [
            new OA\Parameter(name: 'officer_id', in: 'query', schema: new OA\Schema(type: 'string', format: 'uuid')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'KPI payload', content: new OA\JsonContent(properties: [
                new OA\Property(property: 'data', properties: [
                    new OA\Property(property: 'today', properties: [
                        new OA\Property(property: 'count', type: 'integer'),
                        new OA\Property(property: 'total', type: 'number'),
                        new OA\Property(property: 'paid', type: 'number'),
                        new OA\Property(property: 'profit', type: 'number'),
                        new OA\Property(property: 'cash', type: 'number'),
                        new OA\Property(property: 'expenses', type: 'number'),
                    ], type: 'object'),
                    new OA\Property(property: 'outstanding_debt', type: 'number'),
                    new OA\Property(property: 'week_trend', type: 'array', items: new OA\Items(type: 'object')),
                    new OA\Property(property: 'month_trend', type: 'array', items: new OA\Items(type: 'object')),
                    new OA\Property(property: 'top_products', type: 'array', items: new OA\Items(type: 'object')),
                ], type: 'object'),
            ], type: 'object')),
        ],
    )]
    public function kpis(Request $request)
    {
        $today = now()->toDateString();
        $weekAgo = now()->subDays(6)->toDateString();
        $monthAgo = now()->subDays(29)->toDateString();

        // Today's headline figures
        $todayRow = $this->applyOfficerScope(
            DB::table('inventory_sales')->whereDate('created_at', $today),
            $request,
        )->selectRaw('COUNT(*) as count, COALESCE(SUM(total),0) as total, COALESCE(SUM(paid_total),0) as paid')
            ->first();

        // Outstanding debt (credit)
        $debtTotal = (float) $this->applyOfficerScope(
            DB::table('inventory_sales')->whereIn('payment_status', ['debt', 'partial']),
            $request,
        )->sum(DB::raw('total - paid_total'));

        // Cash collected today (cash-method payments only)
        $cashToday = (float) $this->applyOfficerScope(
            DB::table('inventory_sale_payments as p')
                ->join('inventory_sales as s', 's.id', '=', 'p.sale_id')
                ->whereDate('p.paid_at', $today)
                ->where('p.method', 'cash'),
            $request,
            's.created_by',
        )->sum('p.amount');

        // Expenses incurred today (business-wide, not tied to a sales officer)
        $expensesToday = (float) DB::table('inventory_expenses')
            ->whereDate('expense_date', $today)
            ->sum('amount');

        // Profit today (revenue - cost from sale items)
        $profitToday = (float) $this->applyOfficerScope(
            DB::table('inventory_sale_items as si')
                ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
                ->whereDate('s.created_at', $today),
            $request,
            's.created_by',
        )->sum(DB::raw('si.total - (si.unit_cost_snapshot * si.quantity)'));

        // 7-day daily trend
        $weekTrend = $this->applyOfficerScope(
            DB::table('inventory_sales')->whereDate('created_at', '>=', $weekAgo),
            $request,
        )->groupBy(DB::raw('DATE(created_at)'))
            ->orderBy(DB::raw('DATE(created_at)'))
            ->get([
                DB::raw('DATE(created_at) as day'),
                DB::raw('COALESCE(SUM(total),0) as total'),
                DB::raw('COALESCE(SUM(paid_total),0) as paid'),
                DB::raw('COUNT(*) as count'),
            ]);

        // 30-day daily trend
        $monthTrend = $this->applyOfficerScope(
            DB::table('inventory_sales')->whereDate('created_at', '>=', $monthAgo),
            $request,
        )->groupBy(DB::raw('DATE(created_at)'))
            ->orderBy(DB::raw('DATE(created_at)'))
            ->get([
                DB::raw('DATE(created_at) as day'),
                DB::raw('COALESCE(SUM(total),0) as total'),
                DB::raw('COUNT(*) as count'),
            ]);

        // Top 5 products by revenue today
        $topProducts = $this->applyOfficerScope(
            DB::table('inventory_sale_items as si')
                ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
                ->join('inventory_products as p', 'p.id', '=', 'si.product_id')
                ->whereDate('s.created_at', $today),
            $request,
            's.created_by',
        )->groupBy('p.id', 'p.name')
            ->orderByDesc(DB::raw('SUM(si.total)'))
            ->limit(5)
            ->get([
                'p.name as product',
                DB::raw('SUM(si.quantity) as quantity'),
                DB::raw('SUM(si.total) as revenue'),
            ]);

        return response()->json(['data' => [
            'today' => [
                'count'   => (int) ($todayRow->count ?? 0),
                'total'   => (float) ($todayRow->total ?? 0),
                'paid'    => (float) ($todayRow->paid ?? 0),
                'profit'  => $profitToday,
                'cash'    => $cashToday,
                'expenses'=> $expensesToday,
            ],
            'outstanding_debt' => $debtTotal,
            'week_trend'       => $weekTrend,
            'month_trend'      => $monthTrend,
            'top_products'     => $topProducts,
        ]]);
    }

    /**
     * GET /inventory/sales/monthly-chart?year=2026&month=9
     * Returns per-day sales totals for a calendar month — used by the
     * dashboard chart so it always shows complete data, not just cached
     * page-1 sales that may not span the selected month.
     */
    #[OA\Get(
        path: '/inventory/sales/monthly-chart',
        summary: 'Monthly chart',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Sales'],
        parameters: [
            new OA\Parameter(name: 'year', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'month', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function monthlyChart(Request $request)
    {
        $year  = (int) ($request->query('year',  now()->year));
        $month = (int) ($request->query('month', now()->month));

        $daysInMonth = (int) now()->setDate($year, $month, 1)->daysInMonth;
        $from = sprintf('%04d-%02d-01', $year, $month);
        $to   = sprintf('%04d-%02d-%02d', $year, $month, $daysInMonth);

        $rows = $this->applyOfficerScope(
            DB::table('inventory_sales')
                ->whereDate('created_at', '>=', $from)
                ->whereDate('created_at', '<=', $to),
            $request,
        )->groupBy(DB::raw(SqlDate::day('created_at')))
            ->orderBy(DB::raw(SqlDate::day('created_at')))
            ->get([
                DB::raw(SqlDate::day('created_at') . ' as day'),
                DB::raw('COALESCE(SUM(total),0) as total'),
                DB::raw('COUNT(*) as count'),
            ]);

        // Build a full array indexed 1..daysInMonth so the chart never has gaps
        $daily = array_fill(1, $daysInMonth, ['day' => 0, 'total' => 0.0, 'count' => 0]);
        foreach ($rows as $row) {
            $daily[(int)$row->day] = [
                'day'   => (int) $row->day,
                'total' => (float) $row->total,
                'count' => (int) $row->count,
            ];
        }

        return response()->json([
            'data' => [
                'year'  => $year,
                'month' => $month,
                'days'  => array_values($daily),
            ],
        ]);
    }

    /**
     * POST /inventory/sales/{id}/payments
     * Record a payment against an existing debt or partial sale.
     * Updates paid_total and recalculates payment_status automatically.
     */
    #[OA\Post(
        path: '/inventory/sales/{id}/payments',
        summary: 'Record payment',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Sales'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['amount', 'method'],
                properties: [
                new OA\Property(property: 'amount', type: 'number'),
                new OA\Property(property: 'method', type: 'string', enum: ['cash', 'mobile_money', 'bank_transfer']),
                new OA\Property(property: 'reference', type: 'string', nullable: true),
                new OA\Property(property: 'paid_at', type: 'string', format: 'date', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function recordPayment(Request $request, int $id)
    {
        $v = Validator::make($request->all(), [
            'amount'    => 'required|numeric|min:0.01',
            'method'    => ['required', \Illuminate\Validation\Rule::in(\App\Support\PaymentChannels::all())],
            'reference' => 'nullable|string|max:100',
            'paid_at'   => 'nullable|date',
        ]);
        if ($v->fails()) {
            return response()->json(['message' => $v->errors()->first()], 422);
        }

        $response = DB::transaction(function () use ($request, $id) {
            $sale = DB::table('inventory_sales')->lockForUpdate()->find($id);
            if (!$sale) {
                return response()->json(['message' => 'Sale not found'], 404);
            }
            if (!empty($sale->cancelled_at)) {
                return response()->json(['message' => 'Cannot pay a cancelled sale'], 422);
            }
            if ($sale->payment_status === 'paid') {
                return response()->json(['message' => 'Sale is already fully paid'], 422);
            }

            $outstanding = (float) $sale->total - (float) $sale->paid_total;
            $amount = min((float) $request->amount, $outstanding); // never overpay

            [$method, $channel] = \App\Support\PaymentChannels::split($request->method);
            DB::table('inventory_sale_payments')->insert([
                'sale_id'    => $id,
                'amount'     => $amount,
                'method'     => $method,
                'method_extended' => $channel,
                'reference'  => $request->reference,
                'paid_at'    => ClientTime::parse($request->paid_at),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            $newPaid = (float) $sale->paid_total + $amount;
            $newStatus = $newPaid >= (float) $sale->total
                ? 'paid'
                : ($newPaid > 0 ? 'partial' : 'debt');

            DB::table('inventory_sales')->where('id', $id)->update([
                'paid_total'     => $newPaid,
                'payment_status' => $newStatus,
                'updated_at'     => now(),
            ]);

            if ($newStatus === 'paid') {
                \App\Support\Salon\SalonPerks::onPaid((int) $id, optional($request->user())->id === null ? null : (string) $request->user()->id);
            }

            // Close the reminder when fully settled
            if ($newStatus === 'paid') {
                DB::table('inventory_reminders')
                    ->where('type', 'payment_due')
                    ->where('related_id', $id)
                    ->where('status', 'open')
                    ->update(['status' => 'done', 'updated_at' => now()]);
            }

            $this->audit->record($request, 'sale_payment', $id, 'payment_recorded', null, [
                'amount'     => $amount,
                'method'     => $request->method,
                'new_status' => $newStatus,
                'paid_total' => $newPaid,
            ], $sale->number);

            return response()->json([
                'message' => 'Payment recorded',
                'data'    => [
                    'sale_id'        => $id,
                    'sale_number'    => $sale->number,
                    'amount_paid'    => $amount,
                    'new_paid_total' => $newPaid,
                    'balance'        => max(0, (float) $sale->total - $newPaid),
                    'payment_status' => $newStatus,
                ],
            ]);
        });

        // A debt paid off completes the visit: a salon asks the client how it went.
        if ($response->getStatusCode() === 200 && ($response->getData(true)['data']['payment_status'] ?? '') === 'paid') {
            \App\Support\Salon\SalonFeedback::afterPaid((int) $id);
        }

        return $response;
    }

    /**
     * POST /inventory/sales/{id}/cancel
     * Cancels a sale and returns all issued stock back to the ledger.
     * Only allowed on today's sales (configurable) and by managers.
     */
    #[OA\Post(
        path: '/inventory/sales/{id}/cancel',
        summary: 'Cancel',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Sales'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['reason'],
                properties: [
                new OA\Property(property: 'reason', type: 'string'),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function cancel(Request $request, int $id)
    {
        $data = $request->validate([
            'reason' => 'required|string|max:255',
        ]);

        return DB::transaction(function () use ($request, $id, $data) {
            $sale = DB::table('inventory_sales')->lockForUpdate()->find($id);
            if (!$sale) {
                return response()->json(['message' => 'Sale not found'], 404);
            }
            if (!empty($sale->cancelled_at)) {
                return response()->json(['message' => 'Sale already cancelled'], 422);
            }

            // Re-stock every line item
            $items = DB::table('inventory_sale_items')->where('sale_id', $id)->get();
            foreach ($items as $item) {
                if (!empty($item->is_service)) {
                    continue; // a service was never taken out of stock, so there is nothing to put back
                }
                try {
                    $this->ledger->receive(
                        (int) $item->product_id,
                        (int) $item->quantity,
                        'CANCEL-' . now()->format('Ymd'),
                        null,
                        (float) $item->unit_cost_snapshot,
                        $sale->number,
                        optional($request->user())->id,
                    );
                } catch (\Throwable $e) {
                    // Fallback: direct quantity add if ledger can't create batch
                    DB::table('inventory_products')
                        ->where('id', $item->product_id)
                        ->increment('quantity', (int) $item->quantity, ['updated_at' => now()]);
                }
            }

            DB::table('inventory_sales')->where('id', $id)->update([
                'cancelled_at'        => now(),
                'cancellation_reason' => $data['reason'],
                'updated_at'          => now(),
            ]);

            // A salon's points, voucher, package sessions and packages go back as they were.
            \App\Support\Salon\SalonPerks::onCancel($sale, optional($request->user())->id === null ? null : (string) $request->user()->id);

            // Close any open reminders for this sale
            DB::table('inventory_reminders')
                ->where('type', 'payment_due')
                ->where('related_id', $id)
                ->where('status', 'open')
                ->update(['status' => 'done', 'updated_at' => now()]);

            // ...and goods go back on the shelf of the branch they were sold from.
            if (!empty($sale->branch_id)) {
                foreach ($items as $returned) {
                    if (empty($returned->is_service)) {
                        \App\Support\Salon\SalonBranchStock::giveBack((int) $returned->product_id, (int) $sale->branch_id, (int) $returned->quantity);
                    }
                }
            }

            \App\Support\Salon\SalonMaterials::restore($this->ledger, (int) $id, (string) $sale->number, optional($request->user())->id);

            $this->audit->record($request, 'sale', $id, 'cancelled', [
                'payment_status' => $sale->payment_status,
                'total'          => $sale->total,
            ], ['reason' => $data['reason']], $sale->number);

            return response()->json(['message' => 'Sale cancelled and stock restored']);
        });
    }

    /**
     * GET /inventory/sales/summary
     * Aggregated totals for the same filters as index — used by the history tab summary bar.
     */
    #[OA\Get(
        path: '/inventory/sales/summary',
        summary: 'Summary',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Sales'],
        parameters: [
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'q', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function summary(Request $request)
    {
        $status = $request->query('status');
        $from   = $request->query('from');
        $to     = $request->query('to');
        $q      = $request->query('q');

        $query = $this->applyOfficerScope(
            DB::table('inventory_sales as s')
                ->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
                ->whereNull('s.cancelled_at'),
            $request,
            's.created_by',
        );

        if ($status && in_array($status, ['paid', 'debt', 'partial'])) {
            $query->where('s.payment_status', $status);
        }
        if ($from) {
            $query->whereDate('s.created_at', '>=', $from);
        }
        if ($to) {
            $query->whereDate('s.created_at', '<=', $to);
        }
        if (!empty($q)) {
            $query->where(function ($sub) use ($q) {
                $sub->where('s.number', 'like', "%{$q}%")
                    ->orWhere('c.name', 'like', "%{$q}%")
                    ->orWhere('c.phone', 'like', "%{$q}%");
            });
        }

        $row = (clone $query)->selectRaw(
            'COUNT(s.id) as count,
             COALESCE(SUM(s.total),0) as total,
             COALESCE(SUM(s.paid_total),0) as paid'
        )->first();

        $debt = max(0, (int)($row->total ?? 0) - (int)($row->paid ?? 0));

        return response()->json(['data' => [
            'count'  => (int)($row->count ?? 0),
            'total'  => (int)($row->total ?? 0),
            'paid'   => (int)($row->paid ?? 0),
            'debt'   => (int) $debt,
        ]]);
    }

    /**
     * GET /inventory/sales-officers
     * Users a privileged viewer (admin/super_admin/manager) can filter the
     * dashboard down to. Sales officers get an empty list -- they never see
     * the filter, their view is always their own data.
     */
    #[OA\Get(
        path: '/inventory/sales-officers',
        summary: 'Officers',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Sales'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function officers(Request $request)
    {
        if (!$this->isPrivileged($request)) {
            return response()->json(['data' => []]);
        }

        $viewer = $request->user();

        // `users` is shared by every business, so it is limited here by hand: a
        // business lists its own officers, never another's. (super_admin: all.)
        $officers = DB::table('users')
            ->whereIn('role', ['sales_officer', 'manager', 'operator'])
            ->when(!$viewer->seesAllAccounts(), fn ($q) => $q->whereIn('id', $viewer->accountMemberIds()))
            ->orderBy('name')
            ->get(['id', 'name', 'role']);

        return response()->json(['data' => $officers]);
    }

    /** Roles that may see every sales officer's data, not just their own. */
    private function isPrivileged(Request $request): bool
    {
        // (A salon's accountant works across everyone's sales; its stylists see only their own.)
        if (\App\Support\Tenancy\TenantContext::service() === 'salon' && $request->user() !== null) {
            return \App\Support\Salon\SalonAccess::isManager($request->user());
        }

        return in_array(optional($request->user())->role, ['admin', 'super_admin', 'manager', 'accountant']);
    }

    /**
     * Scope a sales-derived query to one sales officer:
     * - A non-privileged viewer (sales_officer etc.) is always locked to
     *   their own data -- the officer_id param is ignored for them.
     * - A privileged viewer (admin/super_admin/manager) sees everything,
     *   unless they pass ?officer_id= to filter the dashboard down to one
     *   specific officer.
     */
    private function applyOfficerScope($query, Request $request, string $column = 'created_by')
    {
        if (!$this->isPrivileged($request)) {
            return $query->where($column, optional($request->user())->id);
        }

        // User ids are UUID strings, not integers -- do not (int) cast this.
        $officerId = $request->query('officer_id');
        if ($officerId !== null && $officerId !== '') {
            $query->where($column, $officerId);
        }

        return $query;
    }

    #[OA\Post(
        path: '/inventory/sales',
        summary: 'Record a sale (POS checkout)',
        description: 'Issues stock FEFO via the batch ledger, records payments, and optionally '
            . 'posts a crate exchange -- all inside one transaction.',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Sales'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['items', 'payment_status', 'subtotal', 'total', 'paid_total'],
                properties: [
                    new OA\Property(property: 'customer_id', type: 'integer', nullable: true),
                    new OA\Property(property: 'customer_name_override', type: 'string', nullable: true),
                    new OA\Property(property: 'customer_phone', type: 'string', nullable: true),
                    new OA\Property(property: 'payment_status', type: 'string', enum: ['paid', 'debt', 'partial']),
                    new OA\Property(property: 'items', type: 'array', items: new OA\Items(properties: [
                        new OA\Property(property: 'product_id', type: 'integer'),
                        new OA\Property(property: 'quantity', type: 'integer'),
                        new OA\Property(property: 'unit_price', type: 'number'),
                    ], type: 'object')),
                    new OA\Property(property: 'payments', type: 'array', items: new OA\Items(properties: [
                        new OA\Property(property: 'amount', type: 'number'),
                        new OA\Property(property: 'method', type: 'string', enum: ['cash', 'mobile_money', 'bank_transfer']),
                    ], type: 'object')),
                    new OA\Property(property: 'subtotal', type: 'number'),
                    new OA\Property(property: 'discount', type: 'number', nullable: true),
                    new OA\Property(property: 'tax', type: 'number', nullable: true),
                    new OA\Property(property: 'total', type: 'number'),
                    new OA\Property(property: 'paid_total', type: 'number'),
                    new OA\Property(property: 'due_date', type: 'string', format: 'date', nullable: true),
                ],
            ),
        ),
        responses: [
            new OA\Response(response: 201, description: 'Sale created', content: new OA\JsonContent(properties: [
                new OA\Property(property: 'message', type: 'string'),
                new OA\Property(property: 'data', type: 'object'),
            ], type: 'object')),
            new OA\Response(response: 422, description: 'Validation failed', content: new OA\JsonContent(ref: '#/components/schemas/ValidationErrorResponse')),
        ],
    )]
    #[OA\Post(
        path: '/sales',
        summary: 'Record a sale (POS checkout)',
        description: 'Issues stock FEFO via the batch ledger, records payments, and optionally '
            . 'posts a crate exchange -- all inside one transaction.',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Sales'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['items', 'payment_status', 'subtotal', 'total', 'paid_total'],
                properties: [
                    new OA\Property(property: 'customer_id', type: 'integer', nullable: true),
                    new OA\Property(property: 'customer_name_override', type: 'string', nullable: true),
                    new OA\Property(property: 'customer_phone', type: 'string', nullable: true),
                    new OA\Property(property: 'payment_status', type: 'string', enum: ['paid', 'debt', 'partial']),
                    new OA\Property(property: 'items', type: 'array', items: new OA\Items(properties: [
                        new OA\Property(property: 'product_id', type: 'integer'),
                        new OA\Property(property: 'quantity', type: 'integer'),
                        new OA\Property(property: 'unit_price', type: 'number'),
                    ], type: 'object')),
                    new OA\Property(property: 'payments', type: 'array', items: new OA\Items(properties: [
                        new OA\Property(property: 'amount', type: 'number'),
                        new OA\Property(property: 'method', type: 'string', enum: ['cash', 'mobile_money', 'bank_transfer']),
                    ], type: 'object')),
                    new OA\Property(property: 'subtotal', type: 'number'),
                    new OA\Property(property: 'discount', type: 'number', nullable: true),
                    new OA\Property(property: 'tax', type: 'number', nullable: true),
                    new OA\Property(property: 'total', type: 'number'),
                    new OA\Property(property: 'paid_total', type: 'number'),
                    new OA\Property(property: 'due_date', type: 'string', format: 'date', nullable: true),
                ],
            ),
        ),
        responses: [
            new OA\Response(response: 201, description: 'Sale created', content: new OA\JsonContent(properties: [
                new OA\Property(property: 'message', type: 'string'),
                new OA\Property(property: 'data', type: 'object'),
            ], type: 'object')),
            new OA\Response(response: 422, description: 'Validation failed', content: new OA\JsonContent(ref: '#/components/schemas/ValidationErrorResponse')),
        ],
    )]
    public function store(Request $request)
    {
        $v = Validator::make($request->all(), [
            'customer_id' => 'nullable|exists:inventory_customers,id',
            'customer_name_override' => 'nullable|string|max:120',
            'customer_phone' => 'nullable|string|max:30',
            'payment_status' => 'required|in:paid,debt,partial',
            'subtotal' => 'required|numeric|min:0',
            'discount' => 'nullable|numeric|min:0',
            'discount_reason' => 'nullable|string|max:160',
            'tax' => 'nullable|numeric|min:0',
            'total' => 'required|numeric|min:0',
            'paid_total' => 'required|numeric|min:0',
            'due_date' => 'nullable|date',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|exists:inventory_products,id',
            'items.*.quantity' => 'required|integer|min:1',
            'items.*.unit_price' => 'nullable|numeric|min:0',
            'items.*.unit_cost_snapshot' => 'nullable|numeric|min:0',
            // Sold in a selling unit (crate, kg, ...): `quantity` is then a count of THAT unit, always whole.
            'items.*.unit_id' => 'nullable|integer',
            'items.*.tax_percent' => 'nullable|numeric|min:0|max:100',
            'items.*.tier' => 'nullable|in:retail,wholesale',
            // Salon: who served the client for this line (someone in this business, never a stranger's id).
            'items.*.staff_id' => ['nullable', new \App\Rules\UserInAccount($request->user())],
            'payments' => 'sometimes|array',
            'payments.*.amount' => 'required|numeric|min:0.01',
            'payments.*.method' => ['required', \Illuminate\Validation\Rule::in(\App\Support\PaymentChannels::all())],
            'payments.*.reference' => 'nullable|string',
            'payments.*.paid_at' => 'nullable|date',
            // Optional crate exchange — recorded atomically with the sale
            'crate_type_id'  => 'nullable|integer|exists:inventory_crate_types,id',
            'crate_qty'      => 'nullable|integer|min:1',
            'crate_direction'=> 'nullable|in:issued,returned',
        ]);

        if ($v->fails()) {
            return response()->json(['message' => $v->errors()->first()], 422);
        }

        if (in_array($request->payment_status, ['debt', 'partial']) && empty($request->customer_id)) {
            return response()->json(['message' => 'Customer required for debt/partial'], 422);
        }

        // A salon's vouchers, loyalty points and packages are checked before anything is written.
        $perksPlan = \App\Support\Salon\SalonPerks::check($request);
        if ($perksPlan['voucher'] !== null && trim((string) $request->discount_reason) === '') {
            $request->merge(['discount_reason' => 'Kuponi / Voucher ' . $perksPlan['voucher']->code]);
        } elseif ($perksPlan['points'] > 0 && trim((string) $request->discount_reason) === '') {
            $request->merge(['discount_reason' => 'Pointi / Loyalty points']);
        }

        // A salon records WHY a discount was given (the owner reads it when the takings are lower than expected).
        if (\App\Support\Tenancy\TenantContext::service() === 'salon' && (float) ($request->discount ?? 0) > 0 && trim((string) $request->discount_reason) === '') {
            return response()->json(['message' => 'Andika sababu ya punguzo. / Write the reason for the discount.'], 422);
        }

        // Each chosen selling unit must be an active unit of that very product.
        $units = [];
        foreach ($request->items as $index => $item) {
            if (empty($item['unit_id'])) {
                continue;
            }
            $unit = DB::table('inventory_product_units')
                ->where('id', (int) $item['unit_id'])
                ->where('product_id', (int) $item['product_id'])
                ->where('status', 'active')
                ->first();
            if (! $unit) {
                return response()->json(['message' => 'That unit is not available for this product'], 422);
            }
            $units[$index] = $unit;
        }

        $response = DB::transaction(function () use ($request, $units, $perksPlan) {
            // Never sell more than is in stock. Checked first, for the whole cart and under a row lock, so
            // the same product on two lines (or two tills at once) cannot slip past, and nothing is written
            // when it is short.
            if ($short = $this->stockShortfall($request->items, $units)) {
                return response()->json([
                    'message' => $short['message'],
                    'code' => 'insufficient_stock',
                    'errors' => ['items' => $short['lines']],
                ], 422);
            }

            // The business's own till settings: its VAT default, whether prices include VAT, which price level.
            $tillSettings = DB::table('inventory_settings')
                ->whereIn('key', ['tax_percent', 'prices_include_vat', 'sale_tier'])
                ->pluck('value', 'key')
                ->all();
            $taxTotal = 0.0;

            // Insert with a placeholder number first so we can derive the
            // number from the guaranteed-unique auto-increment ID, avoiding the
            // max(id)+1 race condition under concurrent checkouts.
            $saleId = DB::table('inventory_sales')->insertGetId([
                'number' => 'PENDING',
                'customer_id' => $request->customer_id,
                'customer_name_override' => $request->customer_id ? null : $request->customer_name_override,
                'customer_phone_override' => $request->customer_phone,
                'payment_status' => $request->payment_status,
                'subtotal' => $request->subtotal,
                'discount' => $request->discount ?? 0,
                ...(\Illuminate\Support\Facades\Schema::hasColumn('inventory_sales', 'discount_reason')
                    ? ['discount_reason' => (float) ($request->discount ?? 0) > 0 ? (trim((string) $request->discount_reason) ?: null) : null]
                    : []),
                'tax' => $request->tax ?? 0,
                'total' => $request->total,
                'paid_total' => $request->paid_total,
                'due_date' => $request->payment_status === 'paid' ? null : ($request->due_date ?? now()->addDays(7)),
                'created_by' => optional($request->user())->id ?? 1,
                ...(\Illuminate\Support\Facades\Schema::hasColumn('inventory_sales', 'branch_id') ? ['branch_id' => \App\Support\Salon\SalonBranch::forNew($request)] : []),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            $number = 'S-' . now()->format('Ymd') . '-' . str_pad((string) $saleId, 4, '0', STR_PAD_LEFT);
            DB::table('inventory_sales')->where('id', $saleId)->update(['number' => $number]);

            // Who served each line, by name as it is today: kept on the line, so a renamed or removed
            // account never rewrites an old receipt.
            $staffNames = \App\Models\User::query()
                ->whereIn('id', collect($request->items)->pluck('staff_id')->filter()->unique()->values())
                ->pluck('name', 'id');

            $insertedItems = [];
            foreach ($request->items as $index => $item) {
                $product = DB::table('inventory_products')->find($item['product_id']);
                if (!$product) {
                    throw new \RuntimeException('Product not found: ' . $item['product_id']);
                }

                // How many of the chosen selling unit were sold, and how many BASE units that takes out of stock.
                $unit = $units[$index] ?? null;
                $factor = $unit ? ProductUnits::factorOf($unit) : 1;
                $unitQty = (int) $item['quantity'];
                $qty = $unitQty * $factor;
                // A service costs no stock and carries no cost of goods: nothing leaves a shelf.
                $isService = !empty($product->is_service);
                $fallbackUnitCost = $isService ? 0.0 : (float) ($item['unit_cost_snapshot'] ?? $product->cost_price ?? 0);

                if ($isService) {
                    $allocations = [];
                } else {
                    try {
                        $allocations = $this->ledger->issue(
                            (int) $item['product_id'],
                            $qty,
                            $number,
                            'sale',
                            optional($request->user())->id ?? 1
                        );
                    } catch (\Illuminate\Database\QueryException $e) {
                        // Fallback to direct stock reduction if the batch ledger tables are not there. Only a
                        // database problem lands here: "Insufficient stock" (a RuntimeException) must stop the
                        // sale, never be swallowed into a sale that empties the shelf.
                        $allocations = [];
                        $newQty = max(0, (int) $product->quantity - $qty);
                        DB::table('inventory_products')
                            ->where('id', $item['product_id'])
                            ->update(['quantity' => $newQty, 'updated_at' => now()]);
                    }
                }

                $issuedQty = array_sum(array_column($allocations, 'quantity'));
                $issuedCost = 0.0;
                foreach ($allocations as $a) {
                    $issuedCost += $a['cost_price'] * $a['quantity'];
                }

                // The price is per SELLING unit (a crate, a kg), the way it is shown and rung up. A line with
                // no price asked for one is priced the way the till would: that unit's price for the tier,
                // else (a unit with no price yet) the base unit's price times what the unit holds.
                $unitPrice = isset($item['unit_price'])
                    ? (float) $item['unit_price']
                    : $this->defaultUnitPrice($product, $unit, $item, $tillSettings, $request->integer('customer_id', 0) ?: null);
                // A visit paid for in a package is free at the till (the package was the sale); the stylist still earns on
                // what the service is worth.
                $commissionBasis = null;
                if (isset($perksPlan['redemptions'][$index])) {
                    $commissionBasis = round((float) $product->selling_price * $unitQty, 2);
                    $unitPrice = 0.0;
                }
                $unitCost = $issuedQty > 0 ? ($issuedCost / $issuedQty) : $fallbackUnitCost;
                $lineTotal = round($unitPrice * $unitQty, 2);

                // VAT on this line: the rate the till sent, else the product's own, else the business's default.
                $rate = (float) ($item['tax_percent'] ?? $product->tax_percent ?? ($tillSettings['tax_percent'] ?? 0));
                $includesVat = ($tillSettings['prices_include_vat'] ?? '1') !== '0';
                $taxAmount = $rate > 0
                    ? round($includesVat ? $lineTotal * $rate / (100 + $rate) : $lineTotal * $rate / 100, 2)
                    : 0.0;
                $taxTotal += $taxAmount;

                $itemId = DB::table('inventory_sale_items')->insertGetId([
                    'sale_id' => (int) $saleId,
                    'product_id' => (int) $item['product_id'],
                    // `quantity` is always BASE units, so stock, cost and every report keep adding up.
                    'quantity' => $qty,
                    'unit_price' => $unitPrice,
                    'unit_cost_snapshot' => $unitCost,
                    'total' => $lineTotal,
                    'unit_id' => $unit?->id,
                    'unit_name' => $unit?->name,
                    'unit_factor' => $factor,
                    'unit_qty' => $unitQty,
                    'tax_percent' => $rate > 0 ? $rate : null,
                    'tax_amount' => $taxAmount,
                    'is_service' => $isService,
                    'staff_id' => $item['staff_id'] ?? null,
                    'staff_name' => isset($item['staff_id']) ? ($staffNames[$item['staff_id']] ?? null) : null,
                    // What the stylist earns on this line, fixed now: a later change of the rate does not rewrite it.
                    ...(\Illuminate\Support\Facades\Schema::hasColumn('inventory_sale_items', 'commission_amount')
                        ? ['commission_amount' => $this->commissionFor($product, $item['staff_id'] ?? null, $isService, (float) $lineTotal, (int) $unitQty, $commissionBasis)]
                        : []),
                    ...(isset($perksPlan['redemptions'][$index]) && \Illuminate\Support\Facades\Schema::hasColumn('inventory_sale_items', 'package_id')
                        ? ['package_id' => (int) $perksPlan['redemptions'][$index]->id]
                        : []),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                // Goods sold in a branch come off that branch's own shelf first.
                if (!$isService && \App\Support\Salon\SalonBranch::forNew($request) !== null) {
                    \App\Support\Salon\SalonBranchStock::take((int) $item['product_id'], (int) \App\Support\Salon\SalonBranch::forNew($request), (int) $qty);
                }

                // The goods a service uses up leave the shelf with it (never stopping the sale).
                if ($isService) {
                    \App\Support\Salon\SalonMaterials::consume($this->ledger, (int) $saleId, (int) $itemId, (int) $item['product_id'], (int) $unitQty, (string) $number, optional($request->user())->id ?? 1);
                }

                $insertedItems[] = [
                    'id' => (int) $itemId,
                    'product_id' => (int) $item['product_id'],
                    'product_name' => $product->name,
                    'quantity' => $unitQty,
                    'qty' => $unitQty,
                    'base_quantity' => $qty,
                    'unit_id' => $unit?->id,
                    'unit_name' => $unit?->name,
                    'unit_factor' => $factor,
                    'unit_price' => $unitPrice,
                    'unit_cost_snapshot' => $unitCost,
                    'tax_percent' => $rate > 0 ? $rate : null,
                    'tax_amount' => $taxAmount,
                    'total' => $lineTotal,
                    'is_service' => $isService,
                    'staff_id' => $item['staff_id'] ?? null,
                    'staff_name' => isset($item['staff_id']) ? ($staffNames[$item['staff_id']] ?? null) : null,
                ];
            }

            // The VAT the sale carries is what its lines say (not what a client added up).
            if ($taxTotal > 0) {
                DB::table('inventory_sales')->where('id', $saleId)->update(['tax' => $taxTotal, 'updated_at' => now()]);
            }

            if (is_array($request->payments)) {
                foreach ($request->payments as $p) {
                    [$method, $channel] = \App\Support\PaymentChannels::split($p['method'] ?? 'cash');
                    DB::table('inventory_sale_payments')->insert([
                        'sale_id' => (int) $saleId,
                        'amount' => (float) $p['amount'],
                        'method' => $method,
                        'method_extended' => $channel,
                        'reference' => $p['reference'] ?? null,
                        'paid_at' => ClientTime::parse($p['paid_at'] ?? null),
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }
            }

            // The salon's perks: the voucher and points spent, the packages sold or used, the points earned.
            \App\Support\Salon\SalonPerks::apply(
                (int) $saleId,
                $request->integer('customer_id', 0) ?: null,
                (string) $request->payment_status,
                (float) $request->total,
                $perksPlan,
                optional($request->user())->id === null ? null : (string) $request->user()->id,
            );

            if (in_array($request->payment_status, ['debt', 'partial'])) {
                DB::table('inventory_reminders')->insert([
                    'type' => 'payment_due',
                    'related_id' => (int) $saleId,
                    'title' => 'Payment Due',
                    'description' => 'Outstanding balance for sale ' . $number,
                    'due_at' => $request->due_date ?? now()->addDays(7),
                    'status' => 'open',
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            // Crate exchange — record atomically so a crash between checkout
            // and a separate API call cannot leave the ledger inconsistent.
            $crateTypeId  = $request->integer('crate_type_id', 0) ?: null;
            $crateQty     = $request->integer('crate_qty', 0) ?: null;
            $crateDir     = $request->input('crate_direction');
            $crateCustomer = $request->integer('customer_id', 0) ?: null;

            // For walk-in customers (no customer_id), auto-create a customer
            // record from the name/phone override so the crate debt is still
            // tracked and appears in the Crates & Empties screen.
            if ($crateTypeId && $crateQty && $crateDir && ! $crateCustomer) {
                $nameOverride  = trim((string) $request->input('customer_name_override', ''));
                $phoneOverride = trim((string) $request->input('customer_phone', ''));
                if ($nameOverride !== '' || $phoneOverride !== '') {
                    $crateCustomer = DB::table('inventory_customers')
                        ->where(function ($q) use ($phoneOverride, $nameOverride) {
                            if ($phoneOverride !== '') {
                                $q->where('phone', $phoneOverride);
                            } else {
                                $q->where('name', $nameOverride);
                            }
                        })
                        ->value('id');

                    if (! $crateCustomer) {
                        $crateCustomer = DB::table('inventory_customers')->insertGetId([
                            'name'       => $nameOverride ?: $phoneOverride,
                            'phone'      => $phoneOverride ?: null,
                            'created_at' => now(),
                            'updated_at' => now(),
                        ]);
                        // Link the sale to the newly created customer record.
                        DB::table('inventory_sales')
                            ->where('id', $saleId)
                            ->update(['customer_id' => $crateCustomer, 'customer_name_override' => null]);
                    }
                }
            }

            if ($crateTypeId && $crateQty && $crateDir && $crateCustomer) {
                $this->crateLedger->post(
                    crateTypeId: $crateTypeId,
                    movementType: $crateDir,
                    quantity: $crateQty,
                    customerId: $crateCustomer,
                    reference: $number,
                    note: $crateDir === 'issued'
                        ? 'Auto: crates owed from sale ' . $number . ' (customer did not bring empties back)'
                        : 'Auto: customer returned crates at sale ' . $number,
                    userId: optional($request->user())->id,
                );
            }

            $this->audit->record($request, 'sale', (int) $saleId, 'created', null, [
                'number' => $number,
                'total' => $request->total,
                'payment_status' => $request->payment_status,
                'items_count' => count($request->items),
            ], $number);

            return response()->json([
                'message' => 'Sale created successfully',
                'data' => [
                    'id' => (int) $saleId,
                    'number' => $number,
                    'customer_id' => $request->customer_id,
                    'payment_status' => $request->payment_status,
                    'subtotal' => (float) $request->subtotal,
                    'tax' => $taxTotal > 0 ? $taxTotal : (float) ($request->tax ?? 0),
                    'total' => (float) $request->total,
                    'paid_total' => (float) $request->paid_total,
                    'items' => $insertedItems,
                ],
            ], 201);
        });

        // A salon asks a client how the visit went, once the sale is made and paid (after it is safely saved).
        if ($response->getStatusCode() === 201 && (string) $request->payment_status === 'paid') {
            \App\Support\Salon\SalonFeedback::afterPaid((int) ($response->getData(true)['data']['id'] ?? 0));
        }

        return $response;
    }

    /**
     * The first thing stopping this cart from leaving the shelf, or null when every product has enough.
     * Lines are added up per product in BASE units (a crate counts as what it holds) and compared with the
     * product's stock under a row lock. Must run inside the checkout transaction.
     *
     * @param  array<int, array<string, mixed>>  $items
     * @param  array<int, object>                $units  chosen selling unit per cart line index
     * @return array{message: string, lines: array<int, array<string, mixed>>}|null
     */
    private function stockShortfall(array $items, array $units): ?array
    {
        $needed = [];
        foreach ($items as $index => $item) {
            $factor = isset($units[$index]) ? ProductUnits::factorOf($units[$index]) : 1;
            $productId = (int) $item['product_id'];
            $needed[$productId] = ($needed[$productId] ?? 0) + (int) $item['quantity'] * $factor;
        }

        $lines = [];
        foreach ($needed as $productId => $requested) {
            $product = DB::table('inventory_products')->lockForUpdate()->find($productId);
            $available = max(0, (int) ($product->quantity ?? 0));
            // A service (a hair braiding, a manicure) has no shelf: it can never run out.
            if ($product && empty($product->is_service) && $requested > $available) {
                $lines[] = [
                    'product_id' => $productId,
                    'product_name' => $product->name,
                    'available' => $available,
                    'requested' => $requested,
                ];
            }
        }

        if (!$lines) {
            return null;
        }

        $first = $lines[0];
        $more = count($lines) - 1;
        $sw = "Stock haitoshi kwa {$first['product_name']}: zilizopo {$first['available']}, unazouza {$first['requested']}.";
        $en = "Not enough stock for {$first['product_name']}: {$first['available']} available, {$first['requested']} requested.";
        if ($more > 0) {
            $sw .= " Na bidhaa nyingine {$more}.";
            $en .= " Plus {$more} more product(s).";
        }

        return ['message' => "{$sw} / {$en}", 'lines' => $lines];
    }

    /**
     * What the till would charge for one selling unit when the request did not say: that unit's price for the
     * tier (a customer's special price first), else -- for a unit with no price yet -- the base unit's price
     * times how many base units it holds. A line sold in the product's own unit with no unit chosen keeps the
     * product's selling price, exactly as before.
     *
     * @param  array<string, string>  $tillSettings
     */
    private function defaultUnitPrice(object $product, ?object $unit, array $item, array $tillSettings, ?int $customerId): float
    {
        if ($unit === null) {
            return (float) ($product->selling_price ?? 0);
        }

        $tier = $item['tier'] ?? (in_array($tillSettings['sale_tier'] ?? '', ['retail', 'wholesale'], true) ? $tillSettings['sale_tier'] : 'retail');

        return $this->units->priceFor((int) $product->id, (int) $unit->id, $tier, $customerId)
            ?? (float) ($product->selling_price ?? 0) * ProductUnits::factorOf($unit);
    }

    /**
     * One sale line as the apps read it. `quantity` and `unit_price` are in the unit the line was sold in, so
     * quantity x unit_price = total always holds; `base_quantity` is what left the stock. Lines from before
     * selling units existed read exactly as they did (their unit is the base unit).
     */
    private function itemPayload(object $it): array
    {
        $unitQty = isset($it->unit_qty) ? (int) $it->unit_qty : (int) $it->quantity;

        return [
            'id' => (int) $it->id,
            'product_id' => (int) $it->product_id,
            'product_name' => $it->product_name ?? 'Product #' . $it->product_id,
            'quantity' => $unitQty,
            'qty' => $unitQty,
            'base_quantity' => (int) $it->quantity,
            'unit_id' => isset($it->unit_id) ? (int) $it->unit_id : null,
            'unit_name' => $it->unit_name ?? null,
            'unit_factor' => (int) ($it->unit_factor ?? 1),
            'unit_price' => self::money($it->unit_price),
            'unit_cost_snapshot' => self::money($it->unit_cost_snapshot),
            'tax_percent' => isset($it->tax_percent) ? (float) $it->tax_percent : null,
            'tax_amount' => self::money($it->tax_amount ?? 0),
            'total' => self::money($it->total),
            'is_service' => (bool) ($it->is_service ?? false),
            'staff_id' => $it->staff_id ?? null,
            'staff_name' => $it->staff_name ?? null,
        ];
    }

    /** Whole amounts stay whole numbers (as the apps always received them); only real fractions are kept. */
    private static function money(mixed $value): int|float
    {
        $amount = (float) $value;

        return $amount == floor($amount) ? (int) $amount : $amount;
    }

    /**
     * What the stylist earns on a service line: a fixed amount each time when the service names one, else its percent
     * of the line, else the person's own rate. Fixed when the sale is made, so a later change of rate never rewrites
     * what was earned. Goods and lines with nobody named earn nobody anything.
     */
    private function commissionFor(object $product, ?string $staffId, bool $isService, float $lineTotal, int $unitQty, ?float $basis = null): ?float
    {
        if (!$isService || $staffId === null || $staffId === '') {
            return null;
        }

        $fixed = (float) ($product->commission_fixed ?? 0);
        if ($fixed > 0) {
            return round($fixed * max(1, $unitQty), 2);
        }

        $percent = (float) ($product->commission_percent ?? 0);
        if ($percent <= 0 && \Illuminate\Support\Facades\Schema::hasTable('inventory_staff_profiles')) {
            $percent = (float) DB::table('inventory_staff_profiles')->where('staff_id', $staffId)->value('commission_percent');
        }

        return $percent > 0 ? round(($basis ?? $lineTotal) * $percent / 100, 2) : null;
    }
}
