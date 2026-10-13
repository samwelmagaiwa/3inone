<?php

namespace App\Http\Controllers\API\Inventory;

use App\Services\Inventory\ProductUnits;
use App\Services\Inventory\AuditTrail;
use App\Services\Inventory\InventoryNotifier;
use App\Services\Inventory\StockLedger;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use OpenApi\Attributes as OA;

/**
 * Area 5 — parked sales, returns and cancellations, discount limits.
 */
class PosController extends Controller
{
    public function __construct(
        private readonly StockLedger $ledger,
        private readonly AuditTrail $audit,
        private readonly InventoryNotifier $notifier,
    ) {
    }

    // -------------------------------------------------------- parked sales

    #[OA\Get(

        path: '/inventory/parked-sales',

        summary: 'Parked sales',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / POS'],
        parameters: [
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string', default: 'parked')),
        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function parkedSales(Request $request)
    {
        $rows = DB::table('inventory_parked_sales as ps')
            ->leftJoin('inventory_customers as c', 'c.id', '=', 'ps.customer_id')
            ->leftJoin('users as u', 'u.id', '=', 'ps.parked_by')
            ->where('ps.status', $request->query('status', 'parked'))
            ->select('ps.*', 'c.name as customer_name', 'u.name as parked_by_name')
            ->orderByDesc('ps.id')
            ->limit(100)
            ->get();

        return response()->json(['data' => $rows]);
    }

    #[OA\Post(

        path: '/inventory/parked-sales',

        summary: 'Park sale',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / POS'],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['cart', 'total'],
                properties: [
                new OA\Property(property: 'customer_id', type: 'integer', nullable: true),
                new OA\Property(property: 'cart', type: 'array', items: new OA\Items(type: 'string')),
                new OA\Property(property: 'total', type: 'number'),
                new OA\Property(property: 'note', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function parkSale(Request $request)
    {
        $data = $request->validate([
            'customer_id' => 'nullable|integer|exists:inventory_customers,id',
            'cart' => 'required|array|min:1',
            'total' => 'required|numeric|min:0',
            'note' => 'nullable|string|max:255',
        ]);

        $id = DB::table('inventory_parked_sales')->insertGetId([
            'reference' => 'PK-' . now()->format('Ymd-His'),
            'customer_id' => $data['customer_id'] ?? null,
            'cart' => json_encode($data['cart']),
            'total' => $data['total'],
            'note' => $data['note'] ?? null,
            'parked_by' => optional($request->user())->id,
            'status' => 'parked',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Sale parked', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Post(

        path: '/inventory/parked-sales/{id}/resume',

        summary: 'Resume parked sale',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / POS'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function resumeParkedSale(int $id)
    {
        $parked = DB::table('inventory_parked_sales')->find($id);
        if (! $parked) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($parked->status !== 'parked') {
            return response()->json(['message' => 'Already ' . $parked->status], 422);
        }

        DB::table('inventory_parked_sales')->where('id', $id)
            ->update(['status' => 'resumed', 'updated_at' => now()]);

        $parked->cart = json_decode($parked->cart, true);

        return response()->json(['data' => $parked]);
    }

    #[OA\Delete(

        path: '/inventory/parked-sales/{id}',

        summary: 'Discard parked sale',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / POS'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function discardParkedSale(int $id)
    {
        $updated = DB::table('inventory_parked_sales')
            ->where('id', $id)->where('status', 'parked')
            ->update(['status' => 'discarded', 'updated_at' => now()]);

        return $updated
            ? response()->json(['message' => 'Parked sale discarded'])
            : response()->json(['message' => 'Not found'], 404);
    }

    // ------------------------------------------------ returns/cancellations

    #[OA\Get(

        path: '/inventory/returns',

        summary: 'Returns',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / POS'],
        parameters: [
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function returns(Request $request)
    {
        $query = DB::table('inventory_sale_returns as r')
            ->join('inventory_sales as s', 's.id', '=', 'r.sale_id')
            ->leftJoin('users as ru', 'ru.id', '=', 'r.requested_by')
            ->select('r.*', 's.number as sale_number', 'ru.name as requested_by_name');

        if ($status = $request->query('status')) {
            $query->where('r.status', $status);
        }

        return response()->json(['data' => $query->orderByDesc('r.id')->limit(200)->get()]);
    }

    #[OA\Post(

        path: '/inventory/returns',

        summary: 'Store return',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / POS'],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['sale_id', 'type', 'lines'],
                properties: [
                new OA\Property(property: 'sale_id', type: 'integer'),
                new OA\Property(property: 'type', type: 'string', enum: ['return', 'cancellation']),
                new OA\Property(property: 'reason', type: 'string', nullable: true),
                new OA\Property(property: 'lines', type: 'array', items: new OA\Items(type: 'string')),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function storeReturn(Request $request)
    {
        $data = $request->validate([
            'sale_id' => 'required|integer|exists:inventory_sales,id',
            'type' => 'required|in:return,cancellation',
            'reason' => 'nullable|string|max:255',
            'lines' => 'required|array|min:1',
            'lines.*.product_id' => 'required|integer|exists:inventory_products,id',
            'lines.*.quantity' => 'required|integer|min:1',
            'lines.*.unit_price' => 'required|numeric|min:0',
            'lines.*.restock' => 'nullable|boolean',
            // Returned in the unit it was sold in: `quantity` is then a count of that unit (whole numbers).
            'lines.*.unit_id' => 'nullable|integer',
        ]);

        // A line may be returned in a selling unit (a kg, a crate); stock and the "never more than sold" check
        // always count BASE units, so a return of 2 kg is 2,000 g.
        $lineUnits = [];
        foreach ($data['lines'] as $i => $line) {
            if (empty($line['unit_id'])) {
                continue;
            }
            $unit = DB::table('inventory_product_units')
                ->where('id', (int) $line['unit_id'])
                ->where('product_id', (int) $line['product_id'])
                ->first();
            if (! $unit) {
                return response()->json(['message' => 'That unit is not available for this product'], 422);
            }
            $lineUnits[$i] = $unit;
        }

        // Never return more of a product than the sale actually contained.
        foreach ($data['lines'] as $i => $line) {
            $baseQty = (int) $line['quantity'] * (isset($lineUnits[$i]) ? ProductUnits::factorOf($lineUnits[$i]) : 1);
            $sold = (int) DB::table('inventory_sale_items')
                ->where('sale_id', $data['sale_id'])
                ->where('product_id', $line['product_id'])
                ->sum('quantity');
            $already = (int) DB::table('inventory_sale_return_lines as rl')
                ->join('inventory_sale_returns as r', 'r.id', '=', 'rl.sale_return_id')
                ->where('r.sale_id', $data['sale_id'])
                ->where('r.status', '!=', 'rejected')
                ->where('rl.product_id', $line['product_id'])
                ->sum('rl.quantity');

            if ($already + $baseQty > $sold) {
                return response()->json([
                    'message' => 'Return exceeds what was sold for one of the products',
                ], 422);
            }
        }

        $requestedBy = optional($request->user())->id;
        $reference = 'RET-' . now()->format('Ymd-His');

        // When prices do not include VAT, a refund has to give back the VAT that was added on top.
        $vatOnTop = DB::table('inventory_settings')->where('key', 'prices_include_vat')->value('value') === '0';

        $id = DB::transaction(function () use ($data, $requestedBy, $reference, $lineUnits, $vatOnTop) {
            $amount = 0.0;
            foreach ($data['lines'] as $line) {
                $lineAmount = (float) $line['unit_price'] * (int) $line['quantity'];
                if ($vatOnTop) {
                    $rate = (float) DB::table('inventory_sale_items')
                        ->where('sale_id', $data['sale_id'])->where('product_id', $line['product_id'])->value('tax_percent');
                    $lineAmount += round($lineAmount * $rate / 100, 2);
                }
                $amount += $lineAmount;
            }

            $returnId = DB::table('inventory_sale_returns')->insertGetId([
                'reference' => $reference,
                'sale_id' => $data['sale_id'],
                'type' => $data['type'],
                'amount' => $amount,
                'reason' => $data['reason'] ?? null,
                'status' => 'pending',
                'requested_by' => $requestedBy,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            foreach ($data['lines'] as $i => $line) {
                $unit = $lineUnits[$i] ?? null;
                DB::table('inventory_sale_return_lines')->insert([
                    'sale_return_id' => $returnId,
                    'product_id' => $line['product_id'],
                    // `quantity` is BASE units (what goes back into stock); the unit it was returned in is kept beside it.
                    'quantity' => (int) $line['quantity'] * ($unit ? ProductUnits::factorOf($unit) : 1),
                    'unit_price' => $line['unit_price'],
                    'unit_id' => $unit?->id,
                    'unit_name' => $unit?->name,
                    'unit_qty' => $unit ? (int) $line['quantity'] : null,
                    'restock' => $line['restock'] ?? true,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            return $returnId;
        });

        $sale = DB::table('inventory_sales')->where('id', $data['sale_id'])->first(['number']);
        $this->notifier->notifyByPermission(
            permissions: ['inv_manage_sales'],
            type: 'return_pending',
            title: ucfirst($data['type']) . ' awaiting approval',
            body: trim('Sale ' . ($sale->number ?? $data['sale_id']) . ' — ' . $reference),
            data: ['sale_return_id' => (int) $id, 'reference' => $reference],
            excludeUserId: $requestedBy,
        );

        return response()->json([
            'message' => 'Return submitted for approval',
            'data' => ['id' => (int) $id],
        ], 201);
    }

    /** Approving puts restockable goods back and credits the sale. */
    #[OA\Post(
        path: '/inventory/returns/{id}/decide',
        summary: 'Decide return',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / POS'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['decision'],
                properties: [
                new OA\Property(property: 'decision', type: 'string', enum: ['approved', 'rejected']),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function decideReturn(Request $request, int $id)
    {
        $return = DB::table('inventory_sale_returns')->find($id);
        if (! $return) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($return->status !== 'pending') {
            return response()->json(['message' => 'Already ' . $return->status], 422);
        }

        $data = $request->validate(['decision' => 'required|in:approved,rejected']);
        $userId = optional($request->user())->id;

        // Segregation of duties, matching write-off approval: the person
        // who requested the return cannot also approve it themselves.
        if ($return->requested_by !== null && $userId !== null
            && (string) $return->requested_by === (string) $userId) {
            return response()->json([
                'message' => 'You cannot approve your own return request',
            ], 403);
        }

        try {
            DB::transaction(function () use ($return, $data, $userId, $id) {
                if ($data['decision'] === 'approved') {
                    $lines = DB::table('inventory_sale_return_lines')
                        ->where('sale_return_id', $id)->get();

                    foreach ($lines as $line) {
                        if (! $line->restock) {
                            continue;
                        }
                        // Returned goods re-enter as their own batch so they
                        // stay distinguishable from fresh stock.
                        $this->ledger->receive(
                            (int) $line->product_id,
                            (int) $line->quantity,
                            'RETURN-' . now()->format('Ymd'),
                            null,
                            null,
                            $return->reference,
                            $userId,
                        );
                    }

                    $sale = DB::table('inventory_sales')->lockForUpdate()->find($return->sale_id);
                    $newTotal = max(0, (float) $sale->total - (float) $return->amount);
                    DB::table('inventory_sales')->where('id', $sale->id)->update([
                        'total' => $newTotal,
                        'payment_status' => (float) $sale->paid_total >= $newTotal
                            ? 'paid'
                            : $sale->payment_status,
                        'updated_at' => now(),
                    ]);
                }

                DB::table('inventory_sale_returns')->where('id', $id)->update([
                    'status' => $data['decision'],
                    'approved_by' => $userId,
                    'approved_at' => now(),
                    'updated_at' => now(),
                ]);
            });
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        $this->audit->record($request, 'sale_return', $id, $data['decision'], null, null, $return->reference);

        $this->notifier->notifyUser(
            userId: $return->requested_by,
            type: 'return_decided',
            title: 'Return ' . $data['decision'],
            body: $return->reference . ' was ' . $data['decision'],
            data: ['sale_return_id' => $id, 'reference' => $return->reference, 'decision' => $data['decision']],
        );

        return response()->json(['message' => 'Return ' . $data['decision']]);
    }

    /**
     * Whether a discount is inside the configured limit.
     * Anything above `max_discount_percent` needs a manager.
     */
    #[OA\Get(
        path: '/inventory/discount-check',
        summary: 'Check discount',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / POS'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function checkDiscount(Request $request)
    {
        $data = $request->validate([
            'subtotal' => 'required|numeric|min:0',
            'discount' => 'required|numeric|min:0',
        ]);

        $settings = DB::table('inventory_settings')
            ->whereIn('key', ['max_discount_percent', 'large_discount_percent'])
            ->pluck('value', 'key');

        $max = (float) ($settings['max_discount_percent'] ?? 10);
        $large = (float) ($settings['large_discount_percent'] ?? 15);
        $subtotal = (float) $data['subtotal'];
        $percent = $subtotal > 0 ? ((float) $data['discount'] / $subtotal) * 100 : 0.0;

        return response()->json(['data' => [
            'percent' => round($percent, 2),
            'max_percent' => $max,
            'allowed' => $percent <= $max,
            'needs_approval' => $percent > $max,
            'is_large' => $percent >= $large,
        ]]);
    }
}
