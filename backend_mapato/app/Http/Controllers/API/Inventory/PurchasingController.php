<?php

namespace App\Http\Controllers\API\Inventory;

use App\Services\Inventory\AuditTrail;
use App\Services\Inventory\StockLedger;
use App\Support\GroupColumns;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use RuntimeException;
use OpenApi\Attributes as OA;

/**
 * Area 4 — suppliers, purchase orders, goods receiving and supplier balances.
 */
class PurchasingController extends Controller
{
    public function __construct(
        private readonly StockLedger $ledger,
        private readonly AuditTrail $audit,
    ) {
    }

    // ------------------------------------------------------------ suppliers

    #[OA\Get(

        path: '/inventory/suppliers',

        summary: 'Suppliers',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Purchasing'],
        parameters: [
            new OA\Parameter(name: 'q', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function suppliers(Request $request)
    {
        $query = DB::table('inventory_suppliers as s')
            ->leftJoin('inventory_supplier_invoices as i', function ($join) {
                $join->on('i.supplier_id', '=', 's.id')
                    ->whereIn('i.status', ['open', 'part_paid']);
            })
            ->select(
                's.*',
                DB::raw('COALESCE(SUM(i.amount - i.paid_amount), 0) as balance'),
            )
            ->groupBy(GroupColumns::of('inventory_suppliers', 's'));

        if ($q = $request->query('q')) {
            $query->where(function ($w) use ($q) {
                $w->where('s.name', 'like', "%{$q}%")
                    ->orWhere('s.phone', 'like', "%{$q}%");
            });
        }
        if ($status = $request->query('status')) {
            $query->where('s.status', $status);
        }

        return response()->json(['data' => $query->orderBy('s.name')->get()]);
    }

    #[OA\Post(

        path: '/inventory/suppliers',

        summary: 'Store supplier',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Purchasing'],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['name'],
                properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'phone', type: 'string', nullable: true),
                new OA\Property(property: 'email', type: 'string', format: 'email', nullable: true),
                new OA\Property(property: 'address', type: 'string', nullable: true),
                new OA\Property(property: 'contact_person', type: 'string', nullable: true),
                new OA\Property(property: 'payment_terms_days', type: 'integer', nullable: true),
                new OA\Property(property: 'status', type: 'string', enum: ['active', 'inactive'], nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function storeSupplier(Request $request)
    {
        $data = $request->validate([
            'name' => 'required|string|max:255',
            'phone' => 'nullable|string|max:32',
            'email' => 'nullable|email|max:255',
            'address' => 'nullable|string|max:255',
            'contact_person' => 'nullable|string|max:255',
            'payment_terms_days' => 'nullable|integer|min:0|max:365',
            'status' => 'nullable|in:active,inactive',
        ]);

        $id = DB::table('inventory_suppliers')->insertGetId(array_merge($data, [
            'payment_terms_days' => $data['payment_terms_days'] ?? 0,
            'status' => $data['status'] ?? 'active',
            'created_by' => optional($request->user())->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]));

        $this->audit->record($request, 'supplier', (int) $id, 'created', null, $data, $data['name']);

        return response()->json(['message' => 'Supplier created', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Put(

        path: '/inventory/suppliers/{id}',

        summary: 'Update supplier',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Purchasing'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['name', 'status'],
                properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'phone', type: 'string', nullable: true),
                new OA\Property(property: 'email', type: 'string', format: 'email', nullable: true),
                new OA\Property(property: 'address', type: 'string', nullable: true),
                new OA\Property(property: 'contact_person', type: 'string', nullable: true),
                new OA\Property(property: 'payment_terms_days', type: 'integer', nullable: true),
                new OA\Property(property: 'status', type: 'string', enum: ['active', 'inactive']),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function updateSupplier(Request $request, int $id)
    {
        $before = DB::table('inventory_suppliers')->find($id);
        if (! $before) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'name' => 'sometimes|required|string|max:255',
            'phone' => 'nullable|string|max:32',
            'email' => 'nullable|email|max:255',
            'address' => 'nullable|string|max:255',
            'contact_person' => 'nullable|string|max:255',
            'payment_terms_days' => 'nullable|integer|min:0|max:365',
            'status' => 'sometimes|required|in:active,inactive',
        ]);

        DB::table('inventory_suppliers')->where('id', $id)
            ->update(array_merge($data, ['updated_at' => now()]));

        $this->audit->record($request, 'supplier', $id, 'updated', (array) $before, $data, $before->name);

        return response()->json(['message' => 'Supplier updated']);
    }

    /**
     * DELETE /inventory/suppliers/{id}
     *
     * Blocked if the supplier has unpaid invoices.
     * Pass ?force=1 (admin-only) to override and anonymise FK references.
     */
    #[OA\Delete(
        path: '/inventory/suppliers/{id}',
        summary: 'Destroy supplier',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Purchasing'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function destroySupplier(Request $request, int $id)
    {
        $existing = DB::table('inventory_suppliers')->where('id', $id)->first();
        if (! $existing) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $force    = filter_var($request->query('force', false), FILTER_VALIDATE_BOOLEAN);
        $hasDebt  = DB::table('inventory_supplier_invoices')
            ->where('supplier_id', $id)
            ->whereIn('status', ['open', 'part_paid'])
            ->exists();

        if ($hasDebt && ! $force) {
            return response()->json([
                'message' => 'Supplier has unpaid invoices. Settle them first, or pass ?force=1.',
            ], 422);
        }

        if ($force) {
            $user = $request->user();
            if (! $user || ! ($user->isSuperAdmin() || in_array($user->role, ['admin', 'manager']) || $user->full_access)) {
                return response()->json(['message' => 'Only admins may force-delete a supplier with open invoices.'], 403);
            }
        }

        // Four tables reference inventory_suppliers with restrictOnDelete.
        // Delete child rows in safe FK order so the supplier row can be removed.
        DB::table('inventory_supplier_payments')->where('supplier_id', $id)->delete();
        DB::table('inventory_supplier_invoices')->where('supplier_id', $id)->delete();
        // goods_receipts and purchase_orders reference each other; delete lines first.
        $poIds = DB::table('inventory_purchase_orders')
            ->where('supplier_id', $id)->pluck('id');
        if ($poIds->isNotEmpty()) {
            DB::table('inventory_purchase_order_lines')
                ->whereIn('purchase_order_id', $poIds)->delete();
            $grIds = DB::table('inventory_goods_receipts')
                ->where('supplier_id', $id)->pluck('id');
            if ($grIds->isNotEmpty()) {
                DB::table('inventory_goods_receipt_lines')
                    ->whereIn('goods_receipt_id', $grIds)->delete();
                DB::table('inventory_goods_receipts')->where('supplier_id', $id)->delete();
            }
            DB::table('inventory_purchase_orders')->where('supplier_id', $id)->delete();
        }
        DB::table('inventory_suppliers')->where('id', $id)->delete();

        $this->audit->record($request, 'supplier', $id, 'deleted', (array) $existing, null, $existing->name);

        return response()->json(['message' => 'Supplier deleted']);
    }

    // ------------------------------------------------------- purchase orders

    #[OA\Get(

        path: '/inventory/purchase-orders',

        summary: 'Purchase orders',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Purchasing'],
        parameters: [
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'supplier_id', in: 'query', schema: new OA\Schema(type: 'string')),
        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function purchaseOrders(Request $request)
    {
        $query = DB::table('inventory_purchase_orders as po')
            ->join('inventory_suppliers as s', 's.id', '=', 'po.supplier_id')
            ->select('po.*', 's.name as supplier_name');

        if ($status = $request->query('status')) {
            $query->where('po.status', $status);
        }
        if ($supplierId = $request->query('supplier_id')) {
            $query->where('po.supplier_id', (int) $supplierId);
        }

        return response()->json(['data' => $query->orderByDesc('po.id')->limit(200)->get()]);
    }

    #[OA\Get(

        path: '/inventory/purchase-orders/{id}',

        summary: 'Show purchase order',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Purchasing'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function showPurchaseOrder(int $id)
    {
        $order = DB::table('inventory_purchase_orders as po')
            ->join('inventory_suppliers as s', 's.id', '=', 'po.supplier_id')
            ->where('po.id', $id)
            ->select('po.*', 's.name as supplier_name')
            ->first();

        if (! $order) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $order->lines = DB::table('inventory_purchase_order_lines as l')
            ->join('inventory_products as p', 'p.id', '=', 'l.product_id')
            ->where('l.purchase_order_id', $id)
            ->select('l.*', 'p.name as product_name', 'p.sku as product_sku', 'p.unit as product_unit')
            ->get();

        return response()->json(['data' => $order]);
    }

    #[OA\Post(

        path: '/inventory/purchase-orders',

        summary: 'Store purchase order',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Purchasing'],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['supplier_id', 'lines'],
                properties: [
                new OA\Property(property: 'supplier_id', type: 'integer'),
                new OA\Property(property: 'expected_at', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'note', type: 'string', nullable: true),
                new OA\Property(property: 'lines', type: 'array', items: new OA\Items(type: 'string')),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function storePurchaseOrder(Request $request)
    {
        $data = $request->validate([
            'supplier_id' => 'required|integer|exists:inventory_suppliers,id',
            'expected_at' => 'nullable|date',
            'note' => 'nullable|string|max:255',
            'lines' => 'required|array|min:1',
            'lines.*.product_id' => 'required|integer|exists:inventory_products,id',
            'lines.*.quantity' => 'required|integer|min:1',
            'lines.*.unit_cost' => 'required|numeric|min:0',
        ]);

        $id = DB::transaction(function () use ($data, $request) {
            $number = 'PO-' . now()->format('Ymd-His');
            $total = 0.0;
            foreach ($data['lines'] as $line) {
                $total += (float) $line['unit_cost'] * (int) $line['quantity'];
            }

            $orderId = DB::table('inventory_purchase_orders')->insertGetId([
                'number' => $number,
                'supplier_id' => $data['supplier_id'],
                'status' => 'draft',
                'expected_at' => $data['expected_at'] ?? null,
                'total' => $total,
                'note' => $data['note'] ?? null,
                'created_by' => optional($request->user())->id,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            foreach ($data['lines'] as $line) {
                DB::table('inventory_purchase_order_lines')->insert([
                    'purchase_order_id' => $orderId,
                    'product_id' => $line['product_id'],
                    'quantity' => $line['quantity'],
                    'unit_cost' => $line['unit_cost'],
                    'total' => (float) $line['unit_cost'] * (int) $line['quantity'],
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            return $orderId;
        });

        $this->audit->record($request, 'purchase_order', (int) $id, 'created', null, $data);

        return response()->json(['message' => 'Purchase order created', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Post(

        path: '/inventory/purchase-orders/{id}/status',

        summary: 'Set purchase order status',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Purchasing'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['status'],
                properties: [
                new OA\Property(property: 'status', type: 'string', enum: ['draft', 'sent', 'cancelled']),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function setPurchaseOrderStatus(Request $request, int $id)
    {
        $order = DB::table('inventory_purchase_orders')->find($id);
        if (! $order) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate(['status' => 'required|in:draft,sent,cancelled']);

        DB::table('inventory_purchase_orders')->where('id', $id)
            ->update(['status' => $data['status'], 'updated_at' => now()]);

        $this->audit->record($request, 'purchase_order', $id, $data['status'], null, null, $order->number);

        return response()->json(['message' => 'Purchase order updated']);
    }

    // ------------------------------------------------------- goods receiving

    /**
     * Receive goods, optionally against a purchase order, capturing batch,
     * expiry and buying cost per line. Stock lands through the ledger.
     */
    #[OA\Post(
        path: '/inventory/goods-receipts',
        summary: 'Receive goods',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Purchasing'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['supplier_id', 'lines'],
                properties: [
                new OA\Property(property: 'supplier_id', type: 'integer'),
                new OA\Property(property: 'purchase_order_id', type: 'integer', nullable: true),
                new OA\Property(property: 'received_on', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'note', type: 'string', nullable: true),
                new OA\Property(property: 'invoice_number', type: 'string', nullable: true),
                new OA\Property(property: 'invoice_due_date', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'lines', type: 'array', items: new OA\Items(type: 'string')),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function receiveGoods(Request $request)
    {
        $data = $request->validate([
            'supplier_id' => 'required|integer|exists:inventory_suppliers,id',
            'purchase_order_id' => 'nullable|integer|exists:inventory_purchase_orders,id',
            'received_on' => 'nullable|date',
            'note' => 'nullable|string|max:255',
            'invoice_number' => 'nullable|string|max:64',
            'invoice_due_date' => 'nullable|date',
            'lines' => 'required|array|min:1',
            'lines.*.product_id' => 'required|integer|exists:inventory_products,id',
            'lines.*.quantity' => 'required|integer|min:1',
            'lines.*.unit_cost' => 'required|numeric|min:0',
            'lines.*.batch_number' => 'nullable|string|max:64',
            'lines.*.expiry_date' => 'nullable|date',
        ]);

        $userId = optional($request->user())->id;

        try {
            $receiptId = DB::transaction(function () use ($data, $userId) {
                $reference = 'GRN-' . now()->format('Ymd-His');
                $receivedOn = $data['received_on'] ?? now()->toDateString();

                $total = 0.0;
                foreach ($data['lines'] as $line) {
                    $total += (float) $line['unit_cost'] * (int) $line['quantity'];
                }

                $receiptId = DB::table('inventory_goods_receipts')->insertGetId([
                    'reference' => $reference,
                    'purchase_order_id' => $data['purchase_order_id'] ?? null,
                    'supplier_id' => $data['supplier_id'],
                    'received_on' => $receivedOn,
                    'total_cost' => $total,
                    'note' => $data['note'] ?? null,
                    'received_by' => $userId,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                foreach ($data['lines'] as $line) {
                    $batchId = $this->ledger->receive(
                        (int) $line['product_id'],
                        (int) $line['quantity'],
                        $line['batch_number'] ?? null,
                        $line['expiry_date'] ?? null,
                        (float) $line['unit_cost'],
                        $reference,
                        $userId,
                    );

                    DB::table('inventory_goods_receipt_lines')->insert([
                        'goods_receipt_id' => $receiptId,
                        'product_id' => $line['product_id'],
                        'batch_id' => $batchId,
                        'quantity' => $line['quantity'],
                        'unit_cost' => $line['unit_cost'],
                        'total' => (float) $line['unit_cost'] * (int) $line['quantity'],
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);

                    if (! empty($data['purchase_order_id'])) {
                        DB::table('inventory_purchase_order_lines')
                            ->where('purchase_order_id', $data['purchase_order_id'])
                            ->where('product_id', $line['product_id'])
                            ->increment('received_quantity', (int) $line['quantity']);
                    }
                }

                if (! empty($data['purchase_order_id'])) {
                    $this->refreshPurchaseOrderStatus((int) $data['purchase_order_id']);
                }

                if (! empty($data['invoice_number'])) {
                    DB::table('inventory_supplier_invoices')->insert([
                        'number' => $data['invoice_number'],
                        'supplier_id' => $data['supplier_id'],
                        'goods_receipt_id' => $receiptId,
                        'invoice_date' => $receivedOn,
                        'due_date' => $data['invoice_due_date'] ?? null,
                        'amount' => $total,
                        'paid_amount' => 0,
                        'status' => 'open',
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }

                return $receiptId;
            });
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        $this->audit->record($request, 'goods_receipt', (int) $receiptId, 'received', null, $data);

        return response()->json([
            'message' => 'Goods received',
            'data' => ['id' => (int) $receiptId],
        ], 201);
    }

    /** Fully / partly received drives the order's status. */
    private function refreshPurchaseOrderStatus(int $orderId): void
    {
        $lines = DB::table('inventory_purchase_order_lines')
            ->where('purchase_order_id', $orderId)
            ->get(['quantity', 'received_quantity']);

        $allDone = $lines->every(fn ($l) => $l->received_quantity >= $l->quantity);
        $anyDone = $lines->contains(fn ($l) => $l->received_quantity > 0);

        DB::table('inventory_purchase_orders')->where('id', $orderId)->update([
            'status' => $allDone ? 'received' : ($anyDone ? 'partial' : 'sent'),
            'updated_at' => now(),
        ]);
    }

    #[OA\Get(

        path: '/inventory/goods-receipts',

        summary: 'Goods receipts',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Purchasing'],
        parameters: [
            new OA\Parameter(name: 'supplier_id', in: 'query', schema: new OA\Schema(type: 'string')),
        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function goodsReceipts(Request $request)
    {
        $query = DB::table('inventory_goods_receipts as g')
            ->join('inventory_suppliers as s', 's.id', '=', 'g.supplier_id')
            ->leftJoin('inventory_purchase_orders as po', 'po.id', '=', 'g.purchase_order_id')
            ->select('g.*', 's.name as supplier_name', 'po.number as purchase_order_number');

        if ($supplierId = $request->query('supplier_id')) {
            $query->where('g.supplier_id', (int) $supplierId);
        }

        return response()->json(['data' => $query->orderByDesc('g.id')->limit(200)->get()]);
    }

    // ---------------------------------------------------- supplier invoices

    #[OA\Get(

        path: '/inventory/supplier-invoices',

        summary: 'Supplier invoices',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Purchasing'],
        parameters: [
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'supplier_id', in: 'query', schema: new OA\Schema(type: 'string')),
        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function supplierInvoices(Request $request)
    {
        $query = DB::table('inventory_supplier_invoices as i')
            ->join('inventory_suppliers as s', 's.id', '=', 'i.supplier_id')
            ->select('i.*', 's.name as supplier_name',
                DB::raw('(i.amount - i.paid_amount) as balance'));

        if ($status = $request->query('status')) {
            $query->where('i.status', $status);
        }
        if ($supplierId = $request->query('supplier_id')) {
            $query->where('i.supplier_id', (int) $supplierId);
        }

        return response()->json(['data' => $query->orderByDesc('i.id')->limit(200)->get()]);
    }

    #[OA\Post(

        path: '/inventory/supplier-payments',

        summary: 'Pay supplier',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Purchasing'],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['supplier_id', 'amount', 'method'],
                properties: [
                new OA\Property(property: 'supplier_id', type: 'integer'),
                new OA\Property(property: 'supplier_invoice_id', type: 'integer', nullable: true),
                new OA\Property(property: 'amount', type: 'number'),
                new OA\Property(property: 'method', type: 'string', enum: ['cash', 'mobile_money', 'bank_transfer', 'cheque']),
                new OA\Property(property: 'reference', type: 'string', nullable: true),
                new OA\Property(property: 'paid_on', type: 'string', format: 'date', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function paySupplier(Request $request)
    {
        $data = $request->validate([
            'supplier_id' => 'required|integer|exists:inventory_suppliers,id',
            'supplier_invoice_id' => 'nullable|integer|exists:inventory_supplier_invoices,id',
            'amount' => 'required|numeric|min:0.01',
            'method' => 'required|in:cash,mobile_money,bank_transfer,cheque',
            'reference' => 'nullable|string|max:255',
            'paid_on' => 'nullable|date',
        ]);

        DB::transaction(function () use ($data, $request) {
            DB::table('inventory_supplier_payments')->insert([
                'supplier_id' => $data['supplier_id'],
                'supplier_invoice_id' => $data['supplier_invoice_id'] ?? null,
                'amount' => $data['amount'],
                'method' => $data['method'],
                'reference' => $data['reference'] ?? null,
                'paid_on' => $data['paid_on'] ?? now()->toDateString(),
                'created_by' => optional($request->user())->id,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            if (! empty($data['supplier_invoice_id'])) {
                $invoice = DB::table('inventory_supplier_invoices')
                    ->lockForUpdate()->find($data['supplier_invoice_id']);
                $paid = (float) $invoice->paid_amount + (float) $data['amount'];

                DB::table('inventory_supplier_invoices')->where('id', $invoice->id)->update([
                    'paid_amount' => $paid,
                    'status' => $paid >= (float) $invoice->amount ? 'paid' : 'part_paid',
                    'updated_at' => now(),
                ]);
            }
        });

        $this->audit->record($request, 'supplier_payment', (int) $data['supplier_id'], 'paid', null, $data);

        return response()->json(['message' => 'Payment recorded'], 201);
    }
}
