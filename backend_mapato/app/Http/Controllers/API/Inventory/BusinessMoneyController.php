<?php

namespace App\Http\Controllers\API\Inventory;

use App\Support\Inventory\BusinessAdvisor;
use App\Support\Inventory\MonthlyFigures;
use App\Support\Inventory\MonthlyReport;
use App\Support\Inventory\OpeningDebts;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * The owner's money tools: debts from before the app (owed to the business and owed by it), the monthly report with its
 * comparison and profit target, and advice on where to do better.
 */
#[OA\Tag(name: 'Inventory / Money', description: 'Old debts, monthly report, targets and advice')]
class BusinessMoneyController extends Controller
{
    // ------------------------------------------------------------------ old debts

    #[OA\Get(path: '/inventory/opening-debts', summary: 'Debts from before the app, of one kind', security: [['bearerAuth' => []]], tags: ['Inventory / Money'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function debts(Request $request): JsonResponse
    {
        $data = $request->validate(['kind' => ['required', Rule::in([OpeningDebts::RECEIVABLE, OpeningDebts::PAYABLE])], 'paid' => 'sometimes|boolean']);
        $position = MonthlyFigures::position();

        return response()->json(['data' => [
            'kind' => $data['kind'],
            'debts' => OpeningDebts::list($data['kind'], (bool) ($data['paid'] ?? false)),
            // The whole of what is owed, with the part that came from before the app and the part from sales or invoices.
            'total' => $data['kind'] === OpeningDebts::RECEIVABLE ? $position['receivable'] : $position['payable'],
            'old' => $data['kind'] === OpeningDebts::RECEIVABLE ? $position['owed_old'] : $position['payable_old'],
            'from_records' => $data['kind'] === OpeningDebts::RECEIVABLE ? $position['owed_by_sales'] : $position['payable_invoices'],
        ]]);
    }

    #[OA\Post(path: '/inventory/opening-debts', summary: 'Write down a debt from before the app', security: [['bearerAuth' => []]], tags: ['Inventory / Money'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function addDebt(Request $request): JsonResponse
    {
        $data = $request->validate([
            'kind' => ['required', Rule::in([OpeningDebts::RECEIVABLE, OpeningDebts::PAYABLE])],
            'name' => 'nullable|string|max:160',
            'phone' => 'nullable|string|max:40',
            'customer_id' => 'nullable|integer',
            'supplier_id' => 'nullable|integer',
            'amount' => 'required|numeric|min:1|max:100000000000',
            'started_on' => 'nullable|date_format:Y-m-d',
            'due_on' => 'nullable|date_format:Y-m-d|after_or_equal:started_on',
            'note' => 'nullable|string|max:255',
        ]);
        $id = OpeningDebts::add($data['kind'], $data, (string) optional($request->user())->id);

        return response()->json(['message' => 'Saved', 'data' => ['id' => $id]], 201);
    }

    #[OA\Post(path: '/inventory/opening-debts/{id}/payments', summary: 'Take or make a payment on an old debt', security: [['bearerAuth' => []]], tags: ['Inventory / Money'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function payDebt(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'amount' => 'required|numeric|min:0.01',
            'method' => ['nullable', Rule::in(\App\Support\PaymentChannels::all())],
            'paid_on' => 'nullable|date_format:Y-m-d',
            'note' => 'nullable|string|max:255',
        ]);
        $result = OpeningDebts::pay($id, (float) $data['amount'], $data['method'] ?? null, $data['paid_on'] ?? null, $data['note'] ?? null, (string) optional($request->user())->id);

        return response()->json(['message' => 'Saved', 'data' => $result]);
    }

    #[OA\Get(path: '/inventory/opening-debts/{id}/payments', summary: 'The payments made on an old debt', security: [['bearerAuth' => []]], tags: ['Inventory / Money'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function debtPayments(int $id): JsonResponse
    {
        abort_if(DB::table('inventory_opening_debts')->where('id', $id)->doesntExist(), 404, 'Not found');
        $rows = DB::table('inventory_opening_payments')->where('debt_id', $id)->orderByDesc('paid_on')->orderByDesc('id')
            ->get(['id', 'amount', 'method', 'paid_on', 'note'])->map(fn ($p) => ['id' => (int) $p->id, 'amount' => (float) $p->amount, 'method' => $p->method, 'paid_on' => (string) $p->paid_on, 'note' => $p->note])->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Delete(path: '/inventory/opening-debts/{id}', summary: 'Remove a wrongly written old debt (only one with no payments)', security: [['bearerAuth' => []]], tags: ['Inventory / Money'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function deleteDebt(Request $request, int $id): JsonResponse
    {
        OpeningDebts::assertDeletable($id);
        \App\Support\Inventory\RecordTrash::trash($request, 'debts', $id, $request->input('reason', $request->query('reason')));

        return response()->json(['message' => 'Moved to the Trash']);
    }

    #[OA\Put(path: '/inventory/opening-debts/{id}', summary: 'Correct a debt from before the app', security: [['bearerAuth' => []]], tags: ['Inventory / Money'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function updateDebt(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'name' => 'sometimes|required|string|max:160',
            'phone' => 'sometimes|nullable|string|max:40',
            'amount' => 'sometimes|required|numeric|min:1|max:100000000000',
            'started_on' => 'sometimes|required|date_format:Y-m-d',
            'due_on' => 'sometimes|nullable|date_format:Y-m-d',
            'note' => 'sometimes|nullable|string|max:255',
        ]);
        $before = DB::table('inventory_opening_debts')->where('id', $id)->first();
        OpeningDebts::update($id, $data);
        app(\App\Services\Inventory\AuditTrail::class)->record($request, 'opening_debt', $id, 'updated', $before ? (array) $before : null, $data, $before->party_name ?? null);

        return response()->json(['message' => 'Saved']);
    }

    // ------------------------------------------------------------------ the monthly report

    private function month(Request $request): string
    {
        $month = (string) $request->query('month', MonthlyFigures::currentMonth());
        if (!MonthlyFigures::valid($month)) {
            throw ValidationException::withMessages(['month' => ['Mwezi si sahihi (mfano 2026-11). / The month is not valid (for example 2026-11).']]);
        }

        return $month;
    }

    #[OA\Get(path: '/inventory/monthly-report', summary: 'A month in full: profit, stock, debts, capital, spending, comparison and target', security: [['bearerAuth' => []]], tags: ['Inventory / Money'], parameters: [new OA\Parameter(name: 'month', in: 'query', schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function report(Request $request): JsonResponse
    {
        return response()->json(['data' => MonthlyReport::build($this->month($request), \App\Support\Salon\SalonBranch::selected($request))]);
    }

    #[OA\Put(path: '/inventory/monthly-target', summary: 'Set (or clear, with 0) the profit target of a month', security: [['bearerAuth' => []]], tags: ['Inventory / Money'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function setTarget(Request $request): JsonResponse
    {
        $data = $request->validate(['month' => ['required', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'], 'profit_target' => 'required|numeric|min:0|max:100000000000']);
        if ($data['month'] < MonthlyFigures::currentMonth()) {
            throw ValidationException::withMessages(['month' => ['Huwezi kuweka lengo la mwezi uliopita. / A target cannot be set for a month that has passed.']]);
        }
        if ((float) $data['profit_target'] <= 0) {
            DB::table('inventory_targets')->where('month', $data['month'])->delete();

            return response()->json(['message' => 'Cleared', 'data' => MonthlyReport::build($data['month'])['target']]);
        }
        $exists = DB::table('inventory_targets')->where('month', $data['month'])->exists();
        if ($exists) {
            // A changed target is to be judged again at the end of its month.
            DB::table('inventory_targets')->where('month', $data['month'])->update(['profit_target' => round((float) $data['profit_target'], 2), 'judged_at' => null, 'updated_at' => now()]);
        } else {
            DB::table('inventory_targets')->insert(['month' => $data['month'], 'profit_target' => round((float) $data['profit_target'], 2), 'created_by' => (string) optional($request->user())->id, 'created_at' => now(), 'updated_at' => now()]);
        }

        return response()->json(['message' => 'Saved', 'data' => MonthlyReport::build($data['month'])['target']]);
    }

    // ------------------------------------------------------------------ payment references

    #[OA\Get(path: '/inventory/payment-references', summary: 'Every payment that came with a reference number (mobile money, bank), oldest first', security: [['bearerAuth' => []]], tags: ['Inventory / Money'], parameters: [new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string')), new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string')), new OA\Parameter(name: 'q', in: 'query', schema: new OA\Schema(type: 'string')), new OA\Parameter(name: 'channel', in: 'query', schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function paymentReferences(Request $request): JsonResponse
    {
        $data = $request->validate([
            'from' => 'nullable|date_format:Y-m-d',
            'to' => 'nullable|date_format:Y-m-d|after_or_equal:from',
            'q' => 'nullable|string|max:100',
            'channel' => ['nullable', Rule::in(\App\Support\PaymentChannels::all())],
            'page' => 'nullable|integer|min:1',
            'per_page' => 'nullable|integer|min:1|max:200',
        ]);

        $base = DB::table('inventory_sale_payments as p')
            ->join('inventory_sales as s', 's.id', '=', 'p.sale_id')
            ->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->whereNotNull('p.reference')->where('p.reference', '!=', '');

        // A salon looking at one branch sees that branch's payments only.
        $branch = \App\Support\Salon\SalonBranch::selected($request);
        if ($branch !== null) {
            $base->where('s.branch_id', $branch);
        }
        if (!empty($data['from'])) {
            $base->where('p.paid_at', '>=', $data['from'] . ' 00:00:00');
        }
        if (!empty($data['to'])) {
            $base->where('p.paid_at', '<=', $data['to'] . ' 23:59:59');
        }
        if (!empty($data['channel'])) {
            [$method, $channel] = \App\Support\PaymentChannels::split($data['channel']);
            $channel !== null ? $base->where('p.method_extended', $channel) : $base->where('p.method', $method);
        }
        if (($needle = trim((string) ($data['q'] ?? ''))) !== '') {
            $like = '%' . str_replace(['%', '_'], ['\%', '\_'], $needle) . '%';
            $base->where(fn ($w) => $w->where('p.reference', 'like', $like)->orWhere('s.number', 'like', $like)
                ->orWhere('c.name', 'like', $like)->orWhere('s.customer_name_override', 'like', $like));
        }

        $totals = (clone $base)->selectRaw('COUNT(*) as n, COALESCE(SUM(p.amount), 0) as amount')->first();
        $page = $base->select(
            'p.id', 'p.sale_id', 'p.amount', 'p.method', 'p.method_extended', 'p.reference', 'p.paid_at',
            's.number as sale_number', 's.total as sale_total', 's.payment_status', 's.cancelled_at',
            DB::raw('COALESCE(c.name, s.customer_name_override) as customer_name'),
        )->orderBy('p.paid_at')->orderBy('p.id')->paginate((int) ($data['per_page'] ?? 50));

        return response()->json([
            'data' => collect($page->items())->map(fn ($r) => [
                'id' => (int) $r->id,
                'sale_id' => (int) $r->sale_id,
                'sale_number' => $r->sale_number,
                'reference' => (string) $r->reference,
                'channel' => $r->method_extended ?? $r->method,
                'amount' => (float) $r->amount,
                'paid_at' => $r->paid_at,
                'customer_name' => $r->customer_name,
                'sale_total' => (float) $r->sale_total,
                'payment_status' => $r->payment_status,
                'cancelled' => !empty($r->cancelled_at),
            ])->values(),
            'summary' => ['count' => (int) $totals->n, 'amount' => (float) $totals->amount],
            'meta' => ['current_page' => $page->currentPage(), 'last_page' => $page->lastPage(), 'per_page' => $page->perPage(), 'total' => $page->total()],
        ]);
    }

    // ------------------------------------------------------------------ advice

    #[OA\Get(path: '/inventory/advice', summary: 'Where to do better: advice written from the month\'s numbers (by AI when it is switched on)', security: [['bearerAuth' => []]], tags: ['Inventory / Money'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function advice(Request $request): JsonResponse
    {
        $lang = $request->query('lang') === 'sw' ? 'sw' : 'en';
        $result = BusinessAdvisor::advise($this->month($request), $lang, $request->boolean('refresh'));
        unset($result['facts']);

        return response()->json(['data' => $result + ['ai_available' => BusinessAdvisor::aiKey() !== '']]);
    }
}
