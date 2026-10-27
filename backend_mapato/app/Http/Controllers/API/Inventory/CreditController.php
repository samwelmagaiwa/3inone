<?php

namespace App\Http\Controllers\API\Inventory;

use App\Services\Inventory\AuditTrail;
use App\Support\Inventory\OpeningDebts;
use App\Support\GroupColumns;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Area 6 — customer credit limits, statements and debtor ageing.
 */
class CreditController extends Controller
{
    public function __construct(private readonly AuditTrail $audit)
    {
    }

    /** Customers with what they owe and how much room is left on the limit. */
    #[OA\Get(
        path: '/inventory/credit/customers',
        summary: 'Customers',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Credit'],
        parameters: [
            new OA\Parameter(name: 'q', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function customers(Request $request)
    {
        $query = DB::table('inventory_customers as c')
            ->leftJoin('inventory_sales as s', function ($join) {
                $join->on('s.customer_id', '=', 'c.id')
                    ->whereIn('s.payment_status', ['debt', 'partial']);
            })
            ->select(
                'c.*',
                DB::raw('COALESCE(SUM(s.total - s.paid_total), 0) as balance'),
            )
            ->groupBy(GroupColumns::of('inventory_customers', 'c'));

        if ($q = $request->query('q')) {
            $query->where(function ($w) use ($q) {
                $w->where('c.name', 'like', "%{$q}%")
                    ->orWhere('c.phone', 'like', "%{$q}%");
            });
        }
        if ($request->boolean('over_limit')) {
            $query->havingRaw('COALESCE(SUM(s.total - s.paid_total), 0) > c.credit_limit')
                ->where('c.credit_limit', '>', 0);
        }

        $rows = $query->orderBy('c.name')->get();
        // What a customer owed before the app is part of what they owe now.
        $old = OpeningDebts::active()
            ? DB::table('inventory_opening_debts')->where('kind', OpeningDebts::RECEIVABLE)->whereNotNull('customer_id')->groupBy('customer_id')->pluck(DB::raw('SUM(amount - paid_amount)'), 'customer_id')
            : collect();
        foreach ($rows as $row) {
            $row->old_balance = round((float) ($old[$row->id] ?? 0), 2);
            $row->balance = round((float) $row->balance + $row->old_balance, 2);
        }

        return response()->json(['data' => $rows]);
    }

    #[OA\Put(

        path: '/inventory/credit/customers/{id}',

        summary: 'Update credit',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Credit'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['credit_limit', 'payment_terms_days', 'is_blocked'],
                properties: [
                new OA\Property(property: 'credit_limit', type: 'number'),
                new OA\Property(property: 'payment_terms_days', type: 'integer'),
                new OA\Property(property: 'is_blocked', type: 'boolean'),
                new OA\Property(property: 'block_reason', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function updateCredit(Request $request, int $id)
    {
        $before = DB::table('inventory_customers')->find($id);
        if (! $before) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'credit_limit' => 'sometimes|required|numeric|min:0',
            'payment_terms_days' => 'sometimes|required|integer|min:0|max:365',
            'is_blocked' => 'sometimes|required|boolean',
            'block_reason' => 'nullable|string|max:255',
        ]);

        DB::table('inventory_customers')->where('id', $id)
            ->update(array_merge($data, ['updated_at' => now()]));

        $this->audit->record(
            $request, 'customer_credit', $id, 'updated',
            (array) $before, $data, $before->name,
        );

        return response()->json(['message' => 'Credit settings saved']);
    }

    /**
     * Whether this customer may take on more credit right now.
     * The POS calls this before allowing a debt or partial sale.
     */
    #[OA\Get(
        path: '/inventory/credit/customers/{id}/check',
        summary: 'Credit check',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Credit'],
        parameters: [
            new OA\Parameter(name: 'amount', in: 'query', schema: new OA\Schema(type: 'string', default: '0')),
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function creditCheck(Request $request, int $id)
    {
        $customer = DB::table('inventory_customers')->find($id);
        if (! $customer) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $balance = (float) DB::table('inventory_sales')
            ->where('customer_id', $id)
            ->whereIn('payment_status', ['debt', 'partial'])
            ->sum(DB::raw('total - paid_total'));
        $balance += OpeningDebts::customerOwes($id);

        $amount = (float) $request->query('amount', 0);
        $limit = (float) $customer->credit_limit;
        $projected = $balance + $amount;

        $blocked = (bool) $customer->is_blocked;
        $overLimit = $limit > 0 && $projected > $limit;
        // Within 10% of the limit is a warning, not a block.
        $nearLimit = ! $overLimit && $limit > 0 && $projected >= $limit * 0.9;

        return response()->json(['data' => [
            'customer_id' => $id,
            'balance' => $balance,
            'credit_limit' => $limit,
            'available' => $limit > 0 ? max(0, $limit - $balance) : null,
            'projected_balance' => $projected,
            'is_blocked' => $blocked,
            'over_limit' => $overLimit,
            'near_limit' => $nearLimit,
            'allowed' => ! $blocked && ! $overLimit,
            'reason' => $blocked
                ? ($customer->block_reason ?: 'Customer is blocked')
                : ($overLimit ? 'Credit limit reached' : null),
        ]]);
    }

    /** Opening balance, the period's transactions, closing balance. */
    #[OA\Get(
        path: '/inventory/credit/customers/{id}/statement',
        summary: 'Statement',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Credit'],
        parameters: [
            new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function statement(Request $request, int $id)
    {
        $customer = DB::table('inventory_customers')->find($id);
        if (! $customer) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $from = $request->query('from', now()->startOfMonth()->toDateString());
        $to = $request->query('to', now()->toDateString());

        $openingCharges = (float) DB::table('inventory_sales')
            ->where('customer_id', $id)
            ->whereDate('created_at', '<', $from)
            ->sum('total');
        $openingPaid = (float) DB::table('inventory_sales')
            ->where('customer_id', $id)
            ->whereDate('created_at', '<', $from)
            ->sum('paid_total');

        $sales = DB::table('inventory_sales')
            ->where('customer_id', $id)
            ->whereDate('created_at', '>=', $from)
            ->whereDate('created_at', '<=', $to)
            ->orderBy('created_at')
            ->get(['id', 'number', 'total', 'paid_total', 'payment_status', 'due_date', 'created_at']);

        $payments = DB::table('inventory_sale_payments as p')
            ->join('inventory_sales as s', 's.id', '=', 'p.sale_id')
            ->where('s.customer_id', $id)
            ->whereDate('p.paid_at', '>=', $from)
            ->whereDate('p.paid_at', '<=', $to)
            ->orderBy('p.paid_at')
            ->get(['p.id', 'p.amount', 'p.method', 'p.reference', 'p.paid_at', 's.number as sale_number']);

        $periodCharges = (float) $sales->sum('total');
        $periodPaid = (float) $payments->sum('amount');
        // What was owed from before the app is where the statement starts.
        $oldDebt = OpeningDebts::customerOwes($id);
        $opening = $openingCharges - $openingPaid + $oldDebt;

        return response()->json(['data' => [
            'customer' => $customer,
            'from' => $from,
            'to' => $to,
            'opening_balance' => $opening,
            'old_debt' => $oldDebt,
            'period_charges' => $periodCharges,
            'period_payments' => $periodPaid,
            'closing_balance' => $opening + $periodCharges - $periodPaid,
            'sales' => $sales,
            'payments' => $payments,
        ]]);
    }

    /**
     * One customer's story for a period: purchases, profit, what they paid, what they owe, what they buy, week by week or month by month.
     */
    #[OA\Get(
        path: '/inventory/credit/customers/{id}/report',
        summary: 'One customer: purchases, profit and debt for a period',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Credit'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function report(Request $request, int $id)
    {
        if (! DB::table('inventory_customers')->where('id', $id)->exists()) {
            return response()->json(['message' => 'Not found'], 404);
        }
        $data = $request->validate([
            'from' => 'nullable|date_format:Y-m-d',
            'to' => 'nullable|date_format:Y-m-d|after_or_equal:from',
            'group' => 'nullable|in:day,week,month',
        ]);
        $tz = \App\Support\Inventory\MonthlyFigures::TIMEZONE;
        $to = $data['to'] ?? now($tz)->toDateString();
        $from = $data['from'] ?? now($tz)->startOfMonth()->toDateString();

        return response()->json(['data' => \App\Support\Inventory\CustomerReport::build($id, $from, $to, $data['group'] ?? 'month', $request->user())]);
    }

    /** Who owes what, bucketed by how long it has been outstanding. */
    #[OA\Get(
        path: '/inventory/credit/debtors-ageing',
        summary: 'Debtors ageing',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Credit'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function debtorsAgeing()
    {
        $rows = DB::table('inventory_sales as s')
            ->join('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->whereIn('s.payment_status', ['debt', 'partial'])
            ->select(
                'c.id as customer_id',
                'c.name as customer_name',
                'c.phone as customer_phone',
                'c.credit_limit',
                's.total',
                's.paid_total',
                's.due_date',
                's.created_at',
            )
            ->get();

        // Old debts age like any other, from the date they are due (or began).
        if (OpeningDebts::active()) {
            $old = DB::table('inventory_opening_debts as d')
                ->join('inventory_customers as c', 'c.id', '=', 'd.customer_id')
                ->where('d.kind', OpeningDebts::RECEIVABLE)->whereRaw('d.amount - d.paid_amount > 0')
                ->get(['c.id as customer_id', 'c.name as customer_name', 'c.phone as customer_phone', 'c.credit_limit', 'd.amount as total', 'd.paid_amount as paid_total', 'd.due_on as due_date', 'd.started_on as created_at']);
            $rows = $rows->concat($old);
        }

        $today = now()->startOfDay();
        $buckets = [];

        foreach ($rows as $row) {
            $outstanding = (float) $row->total - (float) $row->paid_total;
            if ($outstanding <= 0) {
                continue;
            }

            $reference = $row->due_date ?? $row->created_at;
            $age = $today->diffInDays(\Illuminate\Support\Carbon::parse($reference), false) * -1;
            $bucket = match (true) {
                $age <= 30 => 'current',
                $age <= 60 => 'days_31_60',
                $age <= 90 => 'days_61_90',
                default => 'days_90_plus',
            };

            $id = (int) $row->customer_id;
            $buckets[$id] ??= [
                'customer_id' => $id,
                'customer_name' => $row->customer_name,
                'customer_phone' => $row->customer_phone,
                'credit_limit' => (float) $row->credit_limit,
                'current' => 0.0,
                'days_31_60' => 0.0,
                'days_61_90' => 0.0,
                'days_90_plus' => 0.0,
                'total' => 0.0,
                'oldest_days' => 0,
            ];

            $buckets[$id][$bucket] += $outstanding;
            $buckets[$id]['total'] += $outstanding;
            $buckets[$id]['oldest_days'] = max($buckets[$id]['oldest_days'], (int) $age);
        }

        $data = array_values($buckets);
        usort($data, fn ($a, $b) => $b['total'] <=> $a['total']);

        return response()->json([
            'data' => $data,
            'meta' => [
                'grand_total' => array_sum(array_column($data, 'total')),
                'current' => array_sum(array_column($data, 'current')),
                'days_31_60' => array_sum(array_column($data, 'days_31_60')),
                'days_61_90' => array_sum(array_column($data, 'days_61_90')),
                'days_90_plus' => array_sum(array_column($data, 'days_90_plus')),
            ],
        ]);
    }
}
