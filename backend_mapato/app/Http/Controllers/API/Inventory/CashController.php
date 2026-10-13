<?php

namespace App\Http\Controllers\API\Inventory;

use App\Services\Inventory\AuditTrail;
use App\Support\ClientTime;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Area 7 — customer payments, allocation to invoices, and the daily cash
 * reconciliation each staff member does at the end of their shift.
 */
class CashController extends Controller
{
    public function __construct(private readonly AuditTrail $audit)
    {
    }

    /**
     * Take a payment and spread it across the customer's unpaid sales,
     * oldest first, unless specific allocations are supplied.
     */
    #[OA\Post(
        path: '/inventory/payments',
        summary: 'Receive payment',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Cash'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['customer_id', 'amount', 'method'],
                properties: [
                new OA\Property(property: 'customer_id', type: 'integer'),
                new OA\Property(property: 'amount', type: 'number'),
                new OA\Property(property: 'method', type: 'string', enum: ['cash', 'mobile_money', 'bank_transfer', 'cheque']),
                new OA\Property(property: 'reference', type: 'string', nullable: true),
                new OA\Property(property: 'paid_at', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'allocations', type: 'array', items: new OA\Items(type: 'string'), nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function receivePayment(Request $request)
    {
        $data = $request->validate([
            'customer_id' => 'required|integer|exists:inventory_customers,id',
            'amount' => 'required|numeric|min:0.01',
            'method' => 'required|in:cash,mobile_money,bank_transfer,cheque',
            'reference' => 'nullable|string|max:255',
            'paid_at' => 'nullable|date',
            'allocations' => 'nullable|array',
            'allocations.*.sale_id' => 'required|integer|exists:inventory_sales,id',
            'allocations.*.amount' => 'required|numeric|min:0.01',
        ]);

        $result = DB::transaction(function () use ($data, $request) {
            $targets = ! empty($data['allocations'])
                ? collect($data['allocations'])->map(fn ($a) => [
                    'sale_id' => (int) $a['sale_id'],
                    'amount' => (float) $a['amount'],
                ])->all()
                : $this->autoAllocate((int) $data['customer_id'], (float) $data['amount']);

            $applied = [];
            foreach ($targets as $target) {
                $sale = DB::table('inventory_sales')->lockForUpdate()->find($target['sale_id']);
                if (! $sale) {
                    continue;
                }

                $outstanding = (float) $sale->total - (float) $sale->paid_total;
                $amount = min($target['amount'], $outstanding);
                if ($amount <= 0) {
                    continue;
                }

                // The payment row belongs to the sale it settles, so existing
                // sale reporting keeps working unchanged.
                $paymentId = DB::table('inventory_sale_payments')->insertGetId([
                    'sale_id' => $sale->id,
                    'amount' => $amount,
                    // The legacy enum has no cheque; keep it valid and record
                    // the real method alongside.
                    'method' => $data['method'] === 'cheque' ? 'bank_transfer' : $data['method'],
                    'method_extended' => $data['method'],
                    'reference' => $data['reference'] ?? null,
                    'paid_at' => ClientTime::parse($data['paid_at'] ?? null),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                DB::table('inventory_payment_allocations')->insert([
                    'sale_payment_id' => $paymentId,
                    'sale_id' => $sale->id,
                    'amount' => $amount,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                $paidTotal = (float) $sale->paid_total + $amount;
                DB::table('inventory_sales')->where('id', $sale->id)->update([
                    'paid_total' => $paidTotal,
                    'payment_status' => $paidTotal >= (float) $sale->total ? 'paid' : 'partial',
                    'updated_at' => now(),
                ]);

                if ($paidTotal >= (float) $sale->total) {
                    DB::table('inventory_reminders')
                        ->where('type', 'payment_due')
                        ->where('related_id', $sale->id)
                        ->update(['status' => 'done', 'updated_at' => now()]);
                }

                $applied[] = ['sale_id' => (int) $sale->id, 'amount' => $amount];
            }

            return $applied;
        });

        $this->audit->record($request, 'customer_payment', (int) $data['customer_id'], 'received', null, $data);

        $allocated = array_sum(array_column($result, 'amount'));

        return response()->json([
            'message' => 'Payment recorded',
            'data' => [
                'allocations' => $result,
                'allocated' => $allocated,
                'unallocated' => round((float) $data['amount'] - $allocated, 2),
            ],
        ], 201);
    }

    /** Oldest unpaid sale first, until the money runs out. */
    private function autoAllocate(int $customerId, float $amount): array
    {
        $sales = DB::table('inventory_sales')
            ->where('customer_id', $customerId)
            ->whereIn('payment_status', ['debt', 'partial'])
            ->orderBy('created_at')
            ->get(['id', 'total', 'paid_total']);

        $left = $amount;
        $targets = [];

        foreach ($sales as $sale) {
            if ($left <= 0) {
                break;
            }
            $outstanding = (float) $sale->total - (float) $sale->paid_total;
            if ($outstanding <= 0) {
                continue;
            }
            $take = min($left, $outstanding);
            $targets[] = ['sale_id' => (int) $sale->id, 'amount' => $take];
            $left -= $take;
        }

        return $targets;
    }

    // ------------------------------------------------------- cash sessions

    #[OA\Get(

        path: '/inventory/cash-sessions',

        summary: 'Sessions',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Cash'],
        parameters: [
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'date', in: 'query', schema: new OA\Schema(type: 'string')),
        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function sessions(Request $request)
    {
        $query = DB::table('inventory_cash_sessions as cs')
            ->leftJoin('users as u', 'u.id', '=', 'cs.user_id')
            ->select('cs.*', 'u.name as user_name');

        if ($status = $request->query('status')) {
            $query->where('cs.status', $status);
        }
        if ($date = $request->query('date')) {
            $query->whereDate('cs.business_date', $date);
        }
        if ($request->boolean('mine')) {
            $query->where('cs.user_id', optional($request->user())->id);
        }

        return response()->json(['data' => $query->orderByDesc('cs.id')->limit(100)->get()]);
    }

    #[OA\Post(

        path: '/inventory/cash-sessions',

        summary: 'Open session',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Cash'],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'opening_float', type: 'number', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function openSession(Request $request)
    {
        $userId = optional($request->user())->id;

        $existing = DB::table('inventory_cash_sessions')
            ->where('user_id', $userId)
            ->where('status', 'open')
            ->first();
        if ($existing) {
            return response()->json([
                'message' => 'You already have an open session',
                'data' => ['id' => (int) $existing->id],
            ], 422);
        }

        $data = $request->validate(['opening_float' => 'nullable|numeric|min:0']);

        $id = DB::table('inventory_cash_sessions')->insertGetId([
            'reference' => 'CS-' . now()->format('Ymd-His'),
            'user_id' => $userId,
            'business_date' => now()->toDateString(),
            'opening_float' => $data['opening_float'] ?? 0,
            'status' => 'open',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Session opened', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Post(

        path: '/inventory/cash-sessions/{id}/expenses',

        summary: 'Add expense',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Cash'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['description', 'amount'],
                properties: [
                new OA\Property(property: 'description', type: 'string'),
                new OA\Property(property: 'amount', type: 'number'),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function addExpense(Request $request, int $id)
    {
        $session = DB::table('inventory_cash_sessions')->find($id);
        if (! $session) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($session->status !== 'open') {
            return response()->json(['message' => 'Session is closed'], 422);
        }

        $data = $request->validate([
            'description' => 'required|string|max:255',
            'amount' => 'required|numeric|min:0.01',
        ]);

        DB::transaction(function () use ($id, $data, $request) {
            DB::table('inventory_cash_expenses')->insert([
                'cash_session_id' => $id,
                'description' => $data['description'],
                'amount' => $data['amount'],
                'created_by' => optional($request->user())->id,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            DB::table('inventory_cash_sessions')->where('id', $id)->update([
                'expenses_total' => DB::table('inventory_cash_expenses')
                    ->where('cash_session_id', $id)->sum('amount'),
                'updated_at' => now(),
            ]);
        });

        return response()->json(['message' => 'Expense recorded'], 201);
    }

    /** What the drawer should hold right now, and what it actually holds. */
    #[OA\Get(
        path: '/inventory/cash-sessions/{id}',
        summary: 'Session summary',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Cash'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function sessionSummary(int $id)
    {
        $session = DB::table('inventory_cash_sessions')->find($id);
        if (! $session) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $expected = $this->expectedCash($session);

        $session->expenses = DB::table('inventory_cash_expenses')
            ->where('cash_session_id', $id)
            ->orderByDesc('id')
            ->get();
        $session->computed_expected_cash = $expected;

        return response()->json(['data' => $session]);
    }

    /**
     * Opening float + cash taken during the shift − expenses paid out.
     * Only cash counts: mobile money and bank never reach the drawer.
     */
    private function expectedCash(object $session): float
    {
        $cashIn = (float) DB::table('inventory_sale_payments')
            ->where('method', 'cash')
            ->whereDate('paid_at', $session->business_date)
            ->sum('amount');

        $expenses = (float) DB::table('inventory_cash_expenses')
            ->where('cash_session_id', $session->id)
            ->sum('amount');

        return (float) $session->opening_float + $cashIn - $expenses;
    }

    #[OA\Post(

        path: '/inventory/cash-sessions/{id}/close',

        summary: 'Close session',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Cash'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['counted_cash'],
                properties: [
                new OA\Property(property: 'counted_cash', type: 'number'),
                new OA\Property(property: 'difference_reason', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function closeSession(Request $request, int $id)
    {
        $session = DB::table('inventory_cash_sessions')->find($id);
        if (! $session) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($session->status !== 'open') {
            return response()->json(['message' => 'Session is already closed'], 422);
        }

        // Only the session owner or a manager/admin may close a cash session.
        $user = $request->user();
        $role = strtolower($user->role ?? '');
        $isManager = in_array($role, ['admin', 'super_admin', 'manager'], true) || $user->full_access;
        if (!$isManager && (int) $session->user_id !== (int) $user->id) {
            return response()->json(['message' => 'You can only close your own cash session.'], 403);
        }

        $data = $request->validate([
            'counted_cash' => 'required|numeric|min:0',
            'difference_reason' => 'nullable|string|max:255',
        ]);

        $expected = $this->expectedCash($session);
        $difference = (float) $data['counted_cash'] - $expected;

        // A shortage or surplus must be explained before the shift can close.
        if (abs($difference) > 0.009 && empty($data['difference_reason'])) {
            return response()->json([
                'message' => 'Explain the difference of ' . number_format($difference, 2),
                'data' => ['expected_cash' => $expected, 'difference' => $difference],
            ], 422);
        }

        DB::table('inventory_cash_sessions')->where('id', $id)->update([
            'expected_cash' => $expected,
            'counted_cash' => $data['counted_cash'],
            'difference' => $difference,
            'difference_reason' => $data['difference_reason'] ?? null,
            'status' => 'closed',
            'closed_at' => now(),
            'updated_at' => now(),
        ]);

        $this->audit->record(
            $request, 'cash_session', $id, 'closed', null,
            ['expected' => $expected, 'counted' => $data['counted_cash'], 'difference' => $difference],
            $session->reference,
        );

        return response()->json([
            'message' => 'Session closed',
            'data' => [
                'expected_cash' => $expected,
                'counted_cash' => (float) $data['counted_cash'],
                'difference' => $difference,
            ],
        ]);
    }
}
