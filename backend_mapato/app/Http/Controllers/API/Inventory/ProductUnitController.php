<?php

namespace App\Http\Controllers\API\Inventory;

use App\Services\Inventory\ProductUnits;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Area 2 — selling units (bottle / pack / crate) and their tiered prices.
 *
 * Every price write goes through setPrice(), which is the only place allowed to
 * touch inventory_product_prices, so the change log can never be bypassed.
 */
class ProductUnitController extends Controller
{
    public function __construct(private readonly ProductUnits $units)
    {
    }

    /** All units of one product, each with its retail / wholesale / special prices. */
    #[OA\Get(
        path: '/inventory/products/{productId}/units',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Product Unit'],
        parameters: [
            new OA\Parameter(name: 'productId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function index(int $productId)
    {
        if (! DB::table('inventory_products')->where('id', $productId)->exists()) {
            return response()->json(['message' => 'Product not found'], 404);
        }

        $units = DB::table('inventory_product_units')
            ->where('product_id', $productId)
            ->orderByDesc('is_base')
            ->orderBy('factor')
            ->get();

        $prices = DB::table('inventory_product_prices')
            ->whereIn('product_unit_id', $units->pluck('id'))
            ->get()
            ->groupBy('product_unit_id');

        $data = $units->map(function ($unit) use ($prices) {
            $unit->prices = array_values(($prices[$unit->id] ?? collect())->all());

            return $unit;
        });

        return response()->json(['data' => $data]);
    }

    #[OA\Post(

        path: '/inventory/products/{productId}/units',

        summary: 'Create a resource',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Product Unit'],

        parameters: [

            new OA\Parameter(name: 'productId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['name', 'factor'],
                properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'factor', type: 'integer'),
                new OA\Property(property: 'is_base', type: 'boolean', nullable: true),
                new OA\Property(property: 'barcode', type: 'string', nullable: true),
                new OA\Property(property: 'status', type: 'string', enum: ['active', 'inactive'], nullable: true),
                new OA\Property(property: 'retail_price', type: 'number', nullable: true),
                new OA\Property(property: 'wholesale_price', type: 'number', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function store(Request $request, int $productId)
    {
        if (! DB::table('inventory_products')->where('id', $productId)->exists()) {
            return response()->json(['message' => 'Product not found'], 404);
        }

        $data = $request->validate([
            'name' => 'required|string|max:32',
            'factor' => 'required|integer|min:1',
            'is_base' => 'nullable|boolean',
            'barcode' => 'nullable|string|max:255',
            'status' => 'nullable|in:active,inactive',
            'retail_price' => 'nullable|numeric|min:0',
            'wholesale_price' => 'nullable|numeric|min:0',
        ]);

        $duplicate = DB::table('inventory_product_units')
            ->where('product_id', $productId)
            ->where('name', $data['name'])
            ->exists();
        if ($duplicate) {
            return response()->json(['message' => 'That unit already exists for this product'], 422);
        }

        $userId = optional($request->user())->id;

        $unitId = DB::transaction(function () use ($productId, $data, $userId) {
            $isBase = (bool) ($data['is_base'] ?? false);
            if ($isBase) {
                DB::table('inventory_product_units')
                    ->where('product_id', $productId)
                    ->update(['is_base' => false, 'updated_at' => now()]);
            }

            $unitId = DB::table('inventory_product_units')->insertGetId([
                'product_id' => $productId,
                'name' => $data['name'],
                'factor' => $isBase ? 1 : $data['factor'],
                'is_base' => $isBase,
                'barcode' => $data['barcode'] ?? null,
                'status' => $data['status'] ?? 'active',
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            foreach (['retail' => 'retail_price', 'wholesale' => 'wholesale_price'] as $tier => $field) {
                if (isset($data[$field])) {
                    $this->units->writePrice($unitId, $tier, null, (float) $data[$field], 'Unit created', $userId);
                }
            }

            return $unitId;
        });

        return response()->json(['message' => 'Unit created', 'data' => ['id' => (int) $unitId]], 201);
    }

    #[OA\Put(

        path: '/inventory/products/{productId}/units/{unitId}',

        summary: 'Update a resource',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Product Unit'],

        parameters: [

            new OA\Parameter(name: 'productId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

            new OA\Parameter(name: 'unitId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['name', 'factor', 'status'],
                properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'factor', type: 'integer'),
                new OA\Property(property: 'barcode', type: 'string', nullable: true),
                new OA\Property(property: 'status', type: 'string', enum: ['active', 'inactive']),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function update(Request $request, int $productId, int $unitId)
    {
        $unit = DB::table('inventory_product_units')
            ->where('id', $unitId)->where('product_id', $productId)->first();
        if (! $unit) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'name' => 'sometimes|required|string|max:32',
            'factor' => 'sometimes|required|integer|min:1',
            'barcode' => 'nullable|string|max:255',
            'status' => 'sometimes|required|in:active,inactive',
        ]);

        if (isset($data['name'])) {
            $duplicate = DB::table('inventory_product_units')
                ->where('product_id', $productId)
                ->where('name', $data['name'])
                ->where('id', '!=', $unitId)
                ->exists();
            if ($duplicate) {
                return response()->json(['message' => 'That unit already exists for this product'], 422);
            }
        }

        if ($unit->is_base) {
            // The base unit is the measure everything else converts to.
            unset($data['factor']);
        }

        DB::table('inventory_product_units')->where('id', $unitId)
            ->update(array_merge($data, ['updated_at' => now()]));

        return response()->json(['message' => 'Unit updated']);
    }

    #[OA\Delete(

        path: '/inventory/products/{productId}/units/{unitId}',

        summary: 'Delete a resource',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Product Unit'],

        parameters: [

            new OA\Parameter(name: 'productId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

            new OA\Parameter(name: 'unitId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function destroy(int $productId, int $unitId)
    {
        $unit = DB::table('inventory_product_units')
            ->where('id', $unitId)->where('product_id', $productId)->first();
        if (! $unit) {
            return response()->json(['message' => 'Not found'], 404);
        }
        if ($unit->is_base) {
            return response()->json(['message' => 'The base unit cannot be removed'], 422);
        }

        DB::table('inventory_product_units')->where('id', $unitId)->delete();

        return response()->json(['message' => 'Unit deleted']);
    }

    /** Set one tier's price for one unit. Logs the change. */
    #[OA\Post(
        path: '/inventory/products/{productId}/units/{unitId}/price',
        summary: 'Set price',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Product Unit'],
        parameters: [
            new OA\Parameter(name: 'productId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'unitId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['tier', 'price'],
                properties: [
                new OA\Property(property: 'tier', type: 'string', enum: ['retail', 'wholesale', 'special']),
                new OA\Property(property: 'customer_id', type: 'integer', nullable: true),
                new OA\Property(property: 'price', type: 'number'),
                new OA\Property(property: 'effective_from', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'reason', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function setPrice(Request $request, int $productId, int $unitId)
    {
        $exists = DB::table('inventory_product_units')
            ->where('id', $unitId)->where('product_id', $productId)->exists();
        if (! $exists) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'tier' => 'required|in:retail,wholesale,special',
            'customer_id' => 'nullable|integer|exists:inventory_customers,id',
            'price' => 'required|numeric|min:0',
            'effective_from' => 'nullable|date',
            'reason' => 'nullable|string|max:255',
        ]);

        if ($data['tier'] === 'special' && empty($data['customer_id'])) {
            return response()->json(['message' => 'A special price needs a customer'], 422);
        }
        if ($data['tier'] !== 'special') {
            $data['customer_id'] = null;
        }

        DB::transaction(function () use ($unitId, $data, $request) {
            $this->units->writePrice(
                $unitId,
                $data['tier'],
                $data['customer_id'] ?? null,
                (float) $data['price'],
                $data['reason'] ?? null,
                optional($request->user())->id,
                $data['effective_from'] ?? null,
            );
        });

        return response()->json(['message' => 'Price saved']);
    }

    /** Price change history for one unit, newest first. */
    #[OA\Get(
        path: '/inventory/products/{productId}/units/{unitId}/price-history',
        summary: 'Price history',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Product Unit'],
        parameters: [
            new OA\Parameter(name: 'limit', in: 'query', schema: new OA\Schema(type: 'string', default: '50')),
            new OA\Parameter(name: 'productId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'unitId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function priceHistory(Request $request, int $productId, int $unitId)
    {
        $exists = DB::table('inventory_product_units')
            ->where('id', $unitId)->where('product_id', $productId)->exists();
        if (! $exists) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $rows = DB::table('inventory_price_changes as pc')
            ->leftJoin('users as u', 'u.id', '=', 'pc.changed_by')
            ->where('pc.product_unit_id', $unitId)
            ->select('pc.*', 'u.name as changed_by_name')
            ->orderByDesc('pc.created_at')
            ->limit((int) $request->query('limit', 50))
            ->get();

        return response()->json(['data' => $rows]);
    }
}
