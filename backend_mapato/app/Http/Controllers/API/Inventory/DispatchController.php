<?php

namespace App\Http\Controllers\API\Inventory;

use App\Services\Inventory\AuditTrail;
use App\Services\Inventory\StockLedger;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use OpenApi\Attributes as OA;

/**
 * Area 9 — loading a vehicle, the route, and reconciling on return.
 *
 * Loading issues stock out of the depot immediately; whatever comes back is
 * received again at reconciliation, so depot stock is always truthful.
 */
class DispatchController extends Controller
{
    public function __construct(
        private readonly StockLedger $ledger,
        private readonly AuditTrail $audit,
    ) {
    }

    #[OA\Get(

        path: '/inventory/dispatches',

        summary: 'List resources',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Dispatch'],
        parameters: [
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function index(Request $request)
    {
        $query = DB::table('inventory_dispatches as d')
            ->leftJoin('users as u', 'u.id', '=', 'd.agent_id')
            ->leftJoin('inventory_dispatch_lines as l', 'l.dispatch_id', '=', 'd.id')
            ->select(
                'd.*',
                'u.name as agent_name',
                DB::raw('COUNT(l.id) as lines_count'),
                DB::raw('COALESCE(SUM(l.loaded_quantity), 0) as total_loaded'),
            )
            ->groupBy(
                'd.id', 'd.reference', 'd.vehicle', 'd.agent_id', 'd.route',
                'd.dispatch_date', 'd.status', 'd.cash_expected', 'd.cash_returned',
                'd.note', 'd.created_by', 'd.reconciled_at', 'd.created_at',
                'd.updated_at', 'u.name',
            );

        if ($status = $request->query('status')) {
            $query->where('d.status', $status);
        }

        return response()->json(['data' => $query->orderByDesc('d.id')->limit(100)->get()]);
    }

    #[OA\Get(

        path: '/inventory/dispatches/{id}',

        summary: 'Get a single resource',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Dispatch'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function show(int $id)
    {
        $dispatch = DB::table('inventory_dispatches as d')
            ->leftJoin('users as u', 'u.id', '=', 'd.agent_id')
            ->where('d.id', $id)
            ->select('d.*', 'u.name as agent_name')
            ->first();

        if (! $dispatch) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $dispatch->lines = DB::table('inventory_dispatch_lines as l')
            ->join('inventory_products as p', 'p.id', '=', 'l.product_id')
            ->leftJoin('inventory_batches as b', 'b.id', '=', 'l.batch_id')
            ->where('l.dispatch_id', $id)
            ->select('l.*', 'p.name as product_name', 'p.unit as product_unit', 'b.batch_number')
            ->get();

        return response()->json(['data' => $dispatch]);
    }

    /** Load a vehicle: stock leaves the depot now. */
    #[OA\Post(
        path: '/inventory/dispatches',
        summary: 'Create a resource',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Dispatch'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['lines'],
                properties: [
                new OA\Property(property: 'vehicle', type: 'string', nullable: true),
                new OA\Property(property: 'agent_id', type: 'integer', nullable: true),
                new OA\Property(property: 'route', type: 'string', nullable: true),
                new OA\Property(property: 'dispatch_date', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'note', type: 'string', nullable: true),
                new OA\Property(property: 'lines', type: 'array', items: new OA\Items(type: 'string')),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function store(Request $request)
    {
        $data = $request->validate([
            'vehicle' => 'nullable|string|max:64',
            // `exists:users` would accept any business's user; the agent must be in this one.
            'agent_id' => ['nullable', 'integer', new \App\Rules\UserInAccount($request->user())],
            'route' => 'nullable|string|max:255',
            'dispatch_date' => 'nullable|date',
            'note' => 'nullable|string|max:255',
            'lines' => 'required|array|min:1',
            'lines.*.product_id' => 'required|integer|exists:inventory_products,id',
            'lines.*.quantity' => 'required|integer|min:1',
            'lines.*.unit_price' => 'nullable|numeric|min:0',
        ]);

        $userId = optional($request->user())->id;

        try {
            $id = DB::transaction(function () use ($data, $userId) {
                $reference = 'DSP-' . now()->format('Ymd-His');

                $dispatchId = DB::table('inventory_dispatches')->insertGetId([
                    'reference' => $reference,
                    'vehicle' => $data['vehicle'] ?? null,
                    'agent_id' => $data['agent_id'] ?? null,
                    'route' => $data['route'] ?? null,
                    'dispatch_date' => $data['dispatch_date'] ?? now()->toDateString(),
                    'status' => 'on_route',
                    'note' => $data['note'] ?? null,
                    'created_by' => $userId,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                foreach ($data['lines'] as $line) {
                    $allocations = $this->ledger->issue(
                        (int) $line['product_id'],
                        (int) $line['quantity'],
                        $reference,
                        'dispatch',
                        $userId,
                    );

                    DB::table('inventory_dispatch_lines')->insert([
                        'dispatch_id' => $dispatchId,
                        'product_id' => $line['product_id'],
                        'batch_id' => $allocations[0]['batch_id'] ?: null,
                        'loaded_quantity' => $line['quantity'],
                        'unit_price' => $line['unit_price'] ?? 0,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }

                return $dispatchId;
            });
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        $this->audit->record($request, 'dispatch', (int) $id, 'loaded', null, $data);

        return response()->json(['message' => 'Vehicle loaded', 'data' => ['id' => (int) $id]], 201);
    }

    /**
     * The vehicle is back: record what came back, what was sold, and the cash.
     * Unsold stock returns to the depot.
     */
    #[OA\Post(
        path: '/inventory/dispatches/{id}/reconcile',
        summary: 'Reconcile',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Dispatch'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['cash_returned', 'lines'],
                properties: [
                new OA\Property(property: 'cash_returned', type: 'number'),
                new OA\Property(property: 'note', type: 'string', nullable: true),
                new OA\Property(property: 'lines', type: 'array', items: new OA\Items(type: 'string')),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function reconcile(Request $request, int $id)
    {
        $dispatch = DB::table('inventory_dispatches')->find($id);
        if (! $dispatch) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($dispatch->status === 'reconciled') {
            return response()->json(['message' => 'Already reconciled'], 422);
        }

        $data = $request->validate([
            'cash_returned' => 'required|numeric|min:0',
            'note' => 'nullable|string|max:255',
            'lines' => 'required|array|min:1',
            'lines.*.line_id' => 'required|integer|exists:inventory_dispatch_lines,id',
            'lines.*.returned_quantity' => 'required|integer|min:0',
        ]);

        $userId = optional($request->user())->id;

        try {
            $summary = DB::transaction(function () use ($data, $dispatch, $userId, $id) {
                $cashExpected = 0.0;

                foreach ($data['lines'] as $input) {
                    $line = DB::table('inventory_dispatch_lines')
                        ->where('id', $input['line_id'])
                        ->where('dispatch_id', $id)
                        ->first();
                    if (! $line) {
                        continue;
                    }

                    $returned = (int) $input['returned_quantity'];
                    if ($returned > (int) $line->loaded_quantity) {
                        throw new RuntimeException(
                            'Returned more than was loaded on one of the lines',
                        );
                    }

                    $sold = (int) $line->loaded_quantity - $returned;
                    $cashExpected += $sold * (float) $line->unit_price;

                    if ($returned > 0) {
                        $this->ledger->receive(
                            (int) $line->product_id,
                            $returned,
                            'DSP-RETURN-' . now()->format('Ymd'),
                            null,
                            null,
                            $dispatch->reference,
                            $userId,
                        );
                    }

                    DB::table('inventory_dispatch_lines')->where('id', $line->id)->update([
                        'returned_quantity' => $returned,
                        'sold_quantity' => $sold,
                        'updated_at' => now(),
                    ]);
                }

                DB::table('inventory_dispatches')->where('id', $id)->update([
                    'status' => 'reconciled',
                    'cash_expected' => $cashExpected,
                    'cash_returned' => $data['cash_returned'],
                    'note' => $data['note'] ?? $dispatch->note,
                    'reconciled_at' => now(),
                    'updated_at' => now(),
                ]);

                return [
                    'cash_expected' => $cashExpected,
                    'cash_returned' => (float) $data['cash_returned'],
                    'difference' => (float) $data['cash_returned'] - $cashExpected,
                ];
            });
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        $this->audit->record($request, 'dispatch', $id, 'reconciled', null, $summary, $dispatch->reference);

        return response()->json(['message' => 'Dispatch reconciled', 'data' => $summary]);
    }
}
