<?php

namespace App\Http\Controllers\API\Inventory;

use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use App\Http\Controllers\API\Inventory\CrateController;
use OpenApi\Attributes as OA;

/**
 * Area 11 — the 12 standard reports.
 *
 * Every report returns the same envelope — `columns`, `rows`, `meta` — so the
 * app renders any of them with one table widget and one export path.
 */
class ReportController extends Controller
{
    private const REPORTS = [
        'daily_sales' => 'Daily sales',
        'sales_detail' => 'Sales detail',
        'product_profitability' => 'Product profitability',
        'stock_valuation' => 'Stock valuation',
        'stock_movements' => 'Stock movements',
        'stock_count_variance' => 'Stock count variance',
        'damages' => 'Damages & write-offs',
        'debtors_ageing' => 'Debtors ageing',
        'collections' => 'Collections',
        'crates_position' => 'Crates position',
        'purchases' => 'Purchases',
        'cash_reconciliation' => 'Cash reconciliation',
    ];

    #[OA\Get(

        path: '/inventory/reports',

        summary: 'List resources',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Report'],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function index()
    {
        $data = [];
        foreach (self::REPORTS as $key => $title) {
            $data[] = ['key' => $key, 'title' => $title];
        }

        return response()->json(['data' => $data]);
    }

    #[OA\Get(

        path: '/inventory/reports/{key}',

        summary: 'Get a single resource',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Report'],

        parameters: [
            new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string')),

            new OA\Parameter(name: 'key', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function show(Request $request, string $key)
    {
        if (! isset(self::REPORTS[$key])) {
            return response()->json(['message' => 'Unknown report'], 404);
        }

        $from = \Carbon\Carbon::hasFormat($request->query('from', ''), 'Y-m-d')
            ? $request->query('from')
            : now()->startOfMonth()->toDateString();
        $to = \Carbon\Carbon::hasFormat($request->query('to', ''), 'Y-m-d')
            ? $request->query('to')
            : now()->toDateString();

        [$columns, $rows, $meta] = match ($key) {
            'daily_sales' => $this->dailySales($from, $to),
            'sales_detail' => $this->salesDetail($from, $to),
            'product_profitability' => $this->productProfitability($from, $to),
            'stock_valuation' => $this->stockValuation(),
            'stock_movements' => $this->stockMovements($from, $to),
            'stock_count_variance' => $this->stockCountVariance($from, $to),
            'damages' => $this->damages($from, $to),
            'debtors_ageing' => $this->debtorsAgeing(),
            'collections' => $this->collections($from, $to),
            'crates_position' => $this->cratesPosition(),
            'purchases' => $this->purchases($from, $to),
            'cash_reconciliation' => $this->cashReconciliation($from, $to),
        };

        return response()->json([
            'data' => [
                'key' => $key,
                'title' => self::REPORTS[$key],
                'from' => $from,
                'to' => $to,
                'columns' => $columns,
                'rows' => $rows,
                'meta' => $meta,
            ],
        ]);
    }

    private function dailySales(string $from, string $to): array
    {
        $rows = DB::table('inventory_sales')
            ->where('created_at', '>=', $from . ' 00:00:00')
            ->where('created_at', '<=', $to   . ' 23:59:59')
            ->groupBy(DB::raw('DATE(created_at)'))
            ->orderBy(DB::raw('DATE(created_at)'))
            ->limit(500)
            ->get([
                DB::raw('DATE(created_at) as day'),
                DB::raw('COUNT(*) as sales_count'),
                DB::raw('SUM(total) as total'),
                DB::raw('SUM(paid_total) as paid'),
                DB::raw('SUM(total - paid_total) as outstanding'),
            ]);

        return [
            ['day' => 'Date', 'sales_count' => 'Sales', 'total' => 'Total',
                'paid' => 'Paid', 'outstanding' => 'Outstanding'],
            $rows,
            ['total' => $rows->sum('total'), 'paid' => $rows->sum('paid')],
        ];
    }

    private function salesDetail(string $from, string $to): array
    {
        $rows = DB::table('inventory_sale_items as i')
            ->join('inventory_sales as s', 's.id', '=', 'i.sale_id')
            ->join('inventory_products as p', 'p.id', '=', 'i.product_id')
            ->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->where('s.created_at', '>=', $from . ' 00:00:00')
            ->where('s.created_at', '<=', $to   . ' 23:59:59')
            ->orderByDesc('s.created_at')
            ->limit(1000)
            ->get([
                's.number', 's.created_at as date', 'c.name as customer',
                'p.name as product', DB::raw('COALESCE(i.unit_qty, i.quantity) as quantity'),
                DB::raw('i.unit_name as unit'), 'i.unit_price', 'i.total',
            ]);

        return [
            ['number' => 'Sale', 'date' => 'Date', 'customer' => 'Customer',
                'product' => 'Product', 'quantity' => 'Qty', 'unit' => 'Unit',
                'unit_price' => 'Price', 'total' => 'Total'],
            $rows,
            ['total' => $rows->sum('total')],
        ];
    }

    private function productProfitability(string $from, string $to): array
    {
        $rows = DB::table('inventory_sale_items as i')
            ->join('inventory_sales as s', 's.id', '=', 'i.sale_id')
            ->join('inventory_products as p', 'p.id', '=', 'i.product_id')
            ->where('s.created_at', '>=', $from . ' 00:00:00')
            ->where('s.created_at', '<=', $to   . ' 23:59:59')
            ->groupBy('p.id', 'p.name', 'p.sku')
            ->orderByDesc(DB::raw('SUM(i.total - (i.unit_cost_snapshot * i.quantity))'))
            ->get([
                'p.name as product', 'p.sku',
                DB::raw('SUM(i.quantity) as quantity'),
                DB::raw('SUM(i.total) as revenue'),
                DB::raw('SUM(i.unit_cost_snapshot * i.quantity) as cost'),
                DB::raw('SUM(i.total - (i.unit_cost_snapshot * i.quantity)) as profit'),
            ]);

        return [
            ['product' => 'Product', 'sku' => 'SKU', 'quantity' => 'Qty',
                'revenue' => 'Revenue', 'cost' => 'Cost', 'profit' => 'Profit'],
            $rows,
            ['revenue' => $rows->sum('revenue'), 'profit' => $rows->sum('profit')],
        ];
    }

    private function stockValuation(): array
    {
        $rows = DB::table('inventory_batches as b')
            ->join('inventory_products as p', 'p.id', '=', 'b.product_id')
            ->where('b.quantity', '>', 0)
            ->groupBy('p.id', 'p.name', 'p.sku', 'p.unit')
            ->orderByDesc(DB::raw('SUM(b.quantity * b.cost_price)'))
            ->get([
                'p.name as product', 'p.sku', 'p.unit',
                DB::raw('SUM(b.quantity) as quantity'),
                DB::raw('SUM(b.quantity * b.cost_price) as value'),
            ]);

        return [
            ['product' => 'Product', 'sku' => 'SKU', 'unit' => 'Unit',
                'quantity' => 'Qty', 'value' => 'Value'],
            $rows,
            ['value' => $rows->sum('value')],
        ];
    }

    private function stockMovements(string $from, string $to): array
    {
        $rows = DB::table('inventory_stock_movements as m')
            ->join('inventory_products as p', 'p.id', '=', 'm.product_id')
            ->leftJoin('inventory_batches as b', 'b.id', '=', 'm.batch_id')
            ->leftJoin('users as u', 'u.id', '=', 'm.user_id')
            ->where('m.created_at', '>=', $from . ' 00:00:00')
            ->where('m.created_at', '<=', $to   . ' 23:59:59')
            ->orderByDesc('m.id')
            ->limit(1000)
            ->get([
                'm.created_at as date', 'p.name as product', 'b.batch_number as batch',
                'm.type', 'm.quantity', 'm.reason', 'm.reference', 'u.name as user',
            ]);

        return [
            ['date' => 'Date', 'product' => 'Product', 'batch' => 'Batch',
                'type' => 'Type', 'quantity' => 'Qty', 'reason' => 'Reason',
                'reference' => 'Reference', 'user' => 'User'],
            $rows,
            ['count' => $rows->count()],
        ];
    }

    private function stockCountVariance(string $from, string $to): array
    {
        $rows = DB::table('inventory_stock_count_lines as l')
            ->join('inventory_stock_counts as c', 'c.id', '=', 'l.stock_count_id')
            ->join('inventory_products as p', 'p.id', '=', 'l.product_id')
            ->where('c.created_at', '>=', $from . ' 00:00:00')
            ->where('c.created_at', '<=', $to   . ' 23:59:59')
            ->where('l.variance', '!=', 0)
            ->orderByDesc('c.id')
            ->get([
                'c.reference', 'c.status', 'p.name as product',
                'l.system_quantity', 'l.counted_quantity', 'l.variance',
            ]);

        return [
            ['reference' => 'Count', 'status' => 'Status', 'product' => 'Product',
                'system_quantity' => 'System', 'counted_quantity' => 'Counted',
                'variance' => 'Variance'],
            $rows,
            ['net_variance' => $rows->sum('variance')],
        ];
    }

    private function damages(string $from, string $to): array
    {
        $rows = DB::table('inventory_write_offs as w')
            ->join('inventory_products as p', 'p.id', '=', 'w.product_id')
            ->where('w.created_at', '>=', $from . ' 00:00:00')
            ->where('w.created_at', '<=', $to   . ' 23:59:59')
            ->orderByDesc('w.id')
            ->get([
                'w.reference', 'w.created_at as date', 'p.name as product',
                'w.reason', 'w.quantity', 'w.cost_value', 'w.status',
            ]);

        return [
            ['reference' => 'Ref', 'date' => 'Date', 'product' => 'Product',
                'reason' => 'Reason', 'quantity' => 'Qty',
                'cost_value' => 'Value', 'status' => 'Status'],
            $rows,
            ['value' => $rows->where('status', 'approved')->sum('cost_value')],
        ];
    }

    private function debtorsAgeing(): array
    {
        $response = app(CreditController::class)->debtorsAgeing();
        $payload = $response->getData(true);

        return [
            ['customer_name' => 'Customer', 'current' => '0-30',
                'days_31_60' => '31-60', 'days_61_90' => '61-90',
                'days_90_plus' => '90+', 'total' => 'Total'],
            $payload['data'],
            $payload['meta'],
        ];
    }

    private function collections(string $from, string $to): array
    {
        $rows = DB::table('inventory_sale_payments as p')
            ->join('inventory_sales as s', 's.id', '=', 'p.sale_id')
            ->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->where('p.paid_at', '>=', $from . ' 00:00:00')
            ->where('p.paid_at', '<=', $to   . ' 23:59:59')
            ->orderByDesc('p.paid_at')
            ->limit(1000)
            ->get([
                'p.paid_at as date', 's.number as sale', 'c.name as customer',
                'p.amount', DB::raw('COALESCE(p.method_extended, p.method) as method'),
                'p.reference',
            ]);

        return [
            ['date' => 'Date', 'sale' => 'Sale', 'customer' => 'Customer',
                'amount' => 'Amount', 'method' => 'Method', 'reference' => 'Ref'],
            $rows,
            ['total' => $rows->sum('amount')],
        ];
    }

    private function cratesPosition(): array
    {
        $response = app(CrateController::class)->depotPosition();
        $payload = $response->getData(true);

        return [
            ['crate_type_name' => 'Crate type', 'issued' => 'Issued',
                'returned' => 'Returned', 'broken' => 'Broken',
                'out_with_customers' => 'Out', 'deposit_at_risk' => 'Deposit'],
            $payload['data'],
            $payload['meta'],
        ];
    }

    private function purchases(string $from, string $to): array
    {
        $rows = DB::table('inventory_goods_receipt_lines as l')
            ->join('inventory_goods_receipts as g', 'g.id', '=', 'l.goods_receipt_id')
            ->join('inventory_suppliers as s', 's.id', '=', 'g.supplier_id')
            ->join('inventory_products as p', 'p.id', '=', 'l.product_id')
            ->where('g.received_on', '>=', $from)
            ->where('g.received_on', '<=', $to)
            ->orderByDesc('g.id')
            ->limit(1000)
            ->get([
                'g.reference', 'g.received_on as date', 's.name as supplier',
                'p.name as product', 'l.quantity', 'l.unit_cost', 'l.total',
            ]);

        return [
            ['reference' => 'GRN', 'date' => 'Date', 'supplier' => 'Supplier',
                'product' => 'Product', 'quantity' => 'Qty',
                'unit_cost' => 'Cost', 'total' => 'Total'],
            $rows,
            ['total' => $rows->sum('total')],
        ];
    }

    private function cashReconciliation(string $from, string $to): array
    {
        $rows = DB::table('inventory_cash_sessions as cs')
            ->leftJoin('users as u', 'u.id', '=', 'cs.user_id')
            ->where('cs.business_date', '>=', $from)
            ->where('cs.business_date', '<=', $to)
            ->orderByDesc('cs.id')
            ->limit(500)
            ->get([
                'cs.reference', 'cs.business_date as date', 'u.name as user',
                'cs.opening_float', 'cs.expected_cash', 'cs.counted_cash',
                'cs.expenses_total', 'cs.difference', 'cs.difference_reason',
                'cs.status',
            ]);

        return [
            ['reference' => 'Session', 'date' => 'Date', 'user' => 'Staff',
                'expected_cash' => 'Expected', 'counted_cash' => 'Counted',
                'expenses_total' => 'Expenses', 'difference' => 'Difference',
                'status' => 'Status'],
            $rows,
            ['net_difference' => $rows->sum('difference')],
        ];
    }
}
