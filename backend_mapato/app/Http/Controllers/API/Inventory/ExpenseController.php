<?php

namespace App\Http\Controllers\API\Inventory;

use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

class ExpenseController extends Controller
{
    private const CATEGORIES = [
        'rent', 'salaries', 'transport', 'utilities',
        'supplies', 'maintenance', 'marketing', 'licences', 'other',
    ];

    /** Is the signed-in person the owner or a manager (who may approve, and whose own spending needs no approval)? */
    private function isManager(Request $request): bool
    {
        $user = $request->user();
        $role = strtolower($user->role ?? '');

        return in_array($role, ['admin', 'super_admin', 'manager', 'accountant'], true) || (bool) $user->full_access;
    }

    /** An expense as the app reads it: the receipt photo is a short-lived signed link, never the stored path. */
    private function present(object $row): object
    {
        $row->receipt_url = \App\Support\PrivateFile::url($row->receipt_path ?? null);
        unset($row->receipt_path);

        return $row;
    }

    /** Only approved spending counts in the totals (everything the shop records is approved). */
    private function counted($query, string $column = 'status')
    {
        return \Illuminate\Support\Facades\Schema::hasColumn('inventory_expenses', 'status') ? $query->where($column, 'approved') : $query;
    }

    /** GET /inventory/expenses */
    #[OA\Get(
        path: '/inventory/expenses',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Expense'],
        parameters: [
            new OA\Parameter(name: 'period', in: 'query', schema: new OA\Schema(type: 'string', default: 'today')),
            new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function index(Request $request)
    {
        [$from, $to] = $this->dateRange($request);

        $rows = DB::table('inventory_expenses as e')
            ->leftJoin('users as u', 'u.id', '=', 'e.created_by')
            ->whereBetween('e.expense_date', [$from, $to])
            ->orderByDesc('e.expense_date')
            ->orderByDesc('e.id')
            ->select('e.*', 'u.name as created_by_name')
            ->get()
            ->map(fn ($r) => $this->present($r))
            ->values();

        return response()->json(['data' => $rows]);
    }

    /** POST /inventory/expenses */
    #[OA\Post(
        path: '/inventory/expenses',
        summary: 'Create a resource',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Expense'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['description', 'amount', 'expense_date'],
                properties: [
                new OA\Property(property: 'description', type: 'string'),
                new OA\Property(property: 'amount', type: 'number'),
                new OA\Property(property: 'expense_date', type: 'string'),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function store(Request $request)
    {
        $data = $request->validate([
            'category'     => 'required|string|in:' . implode(',', self::CATEGORIES),
            'description'  => 'required|string|max:255',
            'amount'       => 'required|numeric|min:0.01',
            'expense_date' => 'required|date_format:Y-m-d',
            'supplier'     => 'nullable|string|max:120',
            'payment_method' => ['nullable', \Illuminate\Validation\Rule::in(\App\Support\PaymentChannels::all())],
        ]);

        $hasExtras = \Illuminate\Support\Facades\Schema::hasColumn('inventory_expenses', 'status');
        // In a salon, what the owner or a manager spends is approved at once; what anyone else records waits for them.
        $status = \App\Support\Tenancy\TenantContext::service() === 'salon' && !$this->isManager($request) ? 'pending' : 'approved';

        $id = DB::table('inventory_expenses')->insertGetId([
            'category'     => $data['category'],
            'description'  => $data['description'],
            'amount'       => $data['amount'],
            'expense_date' => $data['expense_date'],
            'created_by'   => optional($request->user())->id,
            'created_at'   => now(),
            'updated_at'   => now(),
        ] + ($hasExtras ? [
            'supplier'       => !empty($data['supplier']) ? trim($data['supplier']) : null,
            'payment_method' => $data['payment_method'] ?? null,
            'status'         => $status,
            'approved_by'    => $status === 'approved' ? optional($request->user())->id : null,
            'approved_at'    => $status === 'approved' ? now() : null,
        ] : []));

        // Spending that waits tells the people who can approve it (never the one who recorded it).
        if ($status === 'pending') {
            app(\App\Services\Inventory\InventoryNotifier::class)->notifyByPermission(
                ['inv_view_reports'],
                'salon_expense_pending',
                'Matumizi yanasubiri idhini / An expense is waiting for approval',
                "{$data['description']}: " . number_format((float) $data['amount']) . ' TSh',
                ['expense_id' => (int) $id],
                excludeUserId: (string) optional($request->user())->id,
            );
        }

        return response()->json([
            'message' => 'Expense recorded',
            'data'    => $this->present(DB::table('inventory_expenses')->find($id)),
        ], 201);
    }

    /** PUT /inventory/expenses/{id} */
    #[OA\Put(
        path: '/inventory/expenses/{id}',
        summary: 'Update a resource',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Expense'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'description', type: 'string', nullable: true),
                new OA\Property(property: 'amount', type: 'number', nullable: true),
                new OA\Property(property: 'expense_date', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function update(Request $request, int $id)
    {
        $expense = DB::table('inventory_expenses')->find($id);
        if (! $expense) {
            return response()->json(['message' => 'Not found'], 404);
        }

        // Only the creator or a manager/admin may edit an expense.
        $user = $request->user();
        $role = strtolower($user->role ?? '');
        $isManager = in_array($role, ['admin', 'super_admin', 'manager'], true) || $user->full_access;
        if (!$isManager && (int) $expense->created_by !== (int) $user->id) {
            return response()->json(['message' => 'You can only edit your own expenses.'], 403);
        }

        $data = $request->validate([
            'category'     => 'sometimes|string|in:' . implode(',', self::CATEGORIES),
            'description'  => 'sometimes|string|max:255',
            'amount'       => 'sometimes|numeric|min:0.01',
            'expense_date' => 'sometimes|date_format:Y-m-d',
            'supplier'     => 'sometimes|nullable|string|max:120',
            'payment_method' => ['sometimes', 'nullable', \Illuminate\Validation\Rule::in(\App\Support\PaymentChannels::all())],
        ]);
        if (!\Illuminate\Support\Facades\Schema::hasColumn('inventory_expenses', 'status')) {
            unset($data['supplier'], $data['payment_method']);
        }

        // What was approved and then changed by someone who is not a manager (an amount, a date) needs approving again.
        $extra = [];
        if (\App\Support\Tenancy\TenantContext::service() === 'salon' && !$this->isManager($request) && array_intersect_key($data, array_flip(['amount', 'category', 'expense_date']))) {
            $extra = ['status' => 'pending', 'approved_by' => null, 'approved_at' => null];
        }

        DB::table('inventory_expenses')->where('id', $id)->update(
            array_merge($data, $extra, ['updated_at' => now()])
        );

        return response()->json(['data' => $this->present(DB::table('inventory_expenses')->find($id))]);
    }

    /** DELETE /inventory/expenses/{id} */
    #[OA\Delete(
        path: '/inventory/expenses/{id}',
        summary: 'Delete a resource',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Expense'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function destroy(Request $request, int $id)
    {
        $expense = DB::table('inventory_expenses')->find($id);
        if (! $expense) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $user = $request->user();
        $role = strtolower($user->role ?? '');
        $isManager = in_array($role, ['admin', 'super_admin', 'manager'], true) || $user->full_access;
        if (!$isManager && (int) $expense->created_by !== (int) $user->id) {
            return response()->json(['message' => 'You can only delete your own expenses.'], 403);
        }

        DB::table('inventory_expenses')->where('id', $id)->delete();
        return response()->json(['message' => 'Deleted']);
    }

    /**
     * GET /inventory/expenses/summary
     * Returns per-category totals AND revenue-vs-expense for the period.
     */
    #[OA\Get(
        path: '/inventory/expenses/summary',
        summary: 'Summary',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Expense'],
        parameters: [
            new OA\Parameter(name: 'period', in: 'query', schema: new OA\Schema(type: 'string', default: 'today')),
            new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function summary(Request $request)
    {
        [$from, $to] = $this->dateRange($request);

        // Expenses by category
        $byCategory = $this->counted(DB::table('inventory_expenses')
            ->whereBetween('expense_date', [$from, $to]))
            ->groupBy('category')
            ->orderByRaw('SUM(amount) DESC')
            ->select('category', DB::raw('SUM(amount) as total'), DB::raw('COUNT(*) as count'))
            ->get();

        $totalExpenses = $byCategory->sum('total');

        // Revenue = sum of paid_total from sales in range
        $revenue = (float) DB::table('inventory_sales')
            ->whereBetween(DB::raw('DATE(created_at)'), [$from, $to])
            ->whereNotIn('payment_status', ['cancelled'])
            ->sum('paid_total');

        // COGS = sum of (unit_cost_snapshot × quantity) from sale items in range
        $cogs = (float) DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->whereBetween(DB::raw('DATE(s.created_at)'), [$from, $to])
            ->whereNotIn('s.payment_status', ['cancelled'])
            ->selectRaw('SUM(si.unit_cost_snapshot * si.quantity) as cogs')
            ->value('cogs') ?? 0;

        $grossProfit    = $revenue - $cogs;
        $netProfit      = $grossProfit - (float) $totalExpenses;
        $expenseRatio   = $revenue > 0 ? round(($totalExpenses / $revenue) * 100, 1) : 0;

        return response()->json([
            'data' => [
                'from'           => $from,
                'to'             => $to,
                'revenue'        => round($revenue, 2),
                'cogs'           => round($cogs, 2),
                'gross_profit'   => round($grossProfit, 2),
                'total_expenses' => round((float) $totalExpenses, 2),
                'net_profit'     => round($netProfit, 2),
                'expense_ratio'  => $expenseRatio,   // % of revenue
                'by_category'    => $byCategory,
            ],
        ]);
    }

    /** POST /inventory/expenses/{id}/approval: the owner or a manager approves or turns down spending that waits. */
    #[OA\Post(
        path: '/inventory/expenses/{id}/approval',
        summary: 'Approve or reject an expense that is waiting',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Expense'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function approval(Request $request, int $id)
    {
        if (!$this->isManager($request)) {
            return response()->json(['message' => 'Ni mmiliki au meneja tu anayeweza kuidhinisha. / Only the owner or a manager can approve.'], 403);
        }
        $data = $request->validate(['decision' => 'required|in:approve,reject']);
        $expense = DB::table('inventory_expenses')->find($id);
        if (!$expense) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if (($expense->status ?? 'approved') !== 'pending') {
            return response()->json(['message' => 'Hii haisubiri idhini. / This one is not waiting for approval.'], 422);
        }

        $approved = $data['decision'] === 'approve';
        DB::table('inventory_expenses')->where('id', $id)->update([
            'status' => $approved ? 'approved' : 'rejected',
            'approved_by' => optional($request->user())->id,
            'approved_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['message' => $approved ? 'Approved' : 'Rejected', 'data' => $this->present(DB::table('inventory_expenses')->find($id))]);
    }

    /** POST /inventory/expenses/{id}/receipt: a photo of the receipt (kept privately). */
    #[OA\Post(
        path: '/inventory/expenses/{id}/receipt',
        summary: 'Attach a photo of the receipt',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Expense'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function receipt(Request $request, int $id)
    {
        $expense = DB::table('inventory_expenses')->find($id);
        if (!$expense) {
            return response()->json(['message' => 'Not found'], 404);
        }
        $user = $request->user();
        if (!$this->isManager($request) && (string) $expense->created_by !== (string) $user->id) {
            return response()->json(['message' => 'You can only attach a receipt to your own expense.'], 403);
        }
        $request->validate(['photo' => 'required|file|image|mimes:jpg,jpeg,png|max:5120']);

        if (!empty($expense->receipt_path)) {
            \Illuminate\Support\Facades\Storage::disk(\App\Support\PrivateFile::DISK)->delete($expense->receipt_path);
        }
        $path = \App\Support\PrivateFile::store($request->file('photo'), 'salon_receipts');
        DB::table('inventory_expenses')->where('id', $id)->update(['receipt_path' => $path, 'updated_at' => now()]);

        return response()->json(['message' => 'Receipt saved', 'data' => $this->present(DB::table('inventory_expenses')->find($id))]);
    }

    /** GET /inventory/expenses/categories */
    #[OA\Get(
        path: '/inventory/expenses/categories',
        summary: 'Categories',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Expense'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function categories()
    {
        return response()->json(['data' => self::CATEGORIES]);
    }

    private function dateRange(Request $request): array
    {
        $period = $request->query('period', 'today');
        $from   = $request->query('from');
        $to     = $request->query('to');

        // Validate that any caller-supplied dates are real calendar dates
        // before they reach a whereBetween() clause.
        if ($from && $to) {
            $from = \Carbon\Carbon::hasFormat($from, 'Y-m-d') ? $from : now()->toDateString();
            $to   = \Carbon\Carbon::hasFormat($to,   'Y-m-d') ? $to   : now()->toDateString();
            return [$from, $to];
        }

        $now = now();
        return match ($period) {
            'week'  => [$now->copy()->startOfWeek()->toDateString(), $now->toDateString()],
            'month' => [$now->copy()->startOfMonth()->toDateString(), $now->toDateString()],
            'year'  => [$now->copy()->startOfYear()->toDateString(), $now->toDateString()],
            default => [$now->toDateString(), $now->toDateString()], // today
        };
    }
}
