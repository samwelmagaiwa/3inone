<?php

namespace App\Http\Controllers\API\Inventory;

use App\Services\Inventory\AuditTrail;
use App\Support\GroupColumns;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Area 2 — product categories.
 */
class CategoryController extends Controller
{
    public function __construct(private readonly AuditTrail $audit)
    {
    }

    #[OA\Get(

        path: '/categories',

        summary: 'List resources',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Category'],
        parameters: [
            new OA\Parameter(name: 'q', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]
    #[OA\Get(
        path: '/inventory/categories',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Category'],
        parameters: [
            new OA\Parameter(name: 'q', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function index(Request $request)
    {
        $query = DB::table('inventory_categories as c')
            ->leftJoin('inventory_products as p', 'p.category_id', '=', 'c.id')
            ->select('c.*', DB::raw('COUNT(p.id) as products_count'))
            ->groupBy(GroupColumns::of('inventory_categories', 'c'));

        if ($q = $request->query('q')) {
            $query->where('c.name', 'like', "%{$q}%");
        }
        if ($status = $request->query('status')) {
            $query->where('c.status', $status);
        }

        return response()->json(['data' => $query->orderBy('c.name')->get()]);
    }

    #[OA\Get(

        path: '/inventory/categories/{id}',

        summary: 'Get a single resource',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Category'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function show(int $id)
    {
        $row = DB::table('inventory_categories as c')
            ->leftJoin('inventory_products as p', 'p.category_id', '=', 'c.id')
            ->select('c.*', DB::raw('COUNT(p.id) as products_count'))
            ->groupBy(GroupColumns::of('inventory_categories', 'c'))
            ->where('c.id', $id)
            ->first();

        if (! $row) {
            return response()->json(['message' => 'Not found'], 404);
        }

        return response()->json(['data' => $row]);
    }

    #[OA\Post(

        path: '/inventory/categories',

        summary: 'Create a resource',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Category'],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['name'],
                properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'description', type: 'string', nullable: true),
                new OA\Property(property: 'status', type: 'string', enum: ['active', 'inactive'], nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function store(Request $request)
    {
        $data = $request->validate([
            'name'        => 'required|string|max:255|unique:inventory_categories,name',
            'description' => 'nullable|string|max:500',
            'status'      => 'nullable|in:active,inactive',
        ]);

        $id = DB::table('inventory_categories')->insertGetId([
            'name'        => $data['name'],
            'description' => $data['description'] ?? null,
            'status'      => $data['status'] ?? 'active',
            'created_by'  => optional($request->user())->id,
            'created_at'  => now(),
            'updated_at'  => now(),
        ]);

        $this->audit->record($request, 'category', (int) $id, 'created', null, $data, $data['name']);

        return response()->json(['message' => 'Category created', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Put(

        path: '/inventory/categories/{id}',

        summary: 'Update a resource',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Category'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['status'],
                properties: [
                new OA\Property(property: 'description', type: 'string', nullable: true),
                new OA\Property(property: 'status', type: 'string', enum: ['active', 'inactive']),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function update(Request $request, int $id)
    {
        $existing = DB::table('inventory_categories')->where('id', $id)->first();
        if (! $existing) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'name'        => 'sometimes|required|string|max:255|unique:inventory_categories,name,' . $id,
            'description' => 'nullable|string|max:500',
            'status'      => 'sometimes|required|in:active,inactive',
        ]);

        $before = (array) $existing;

        DB::transaction(function () use ($id, $data) {
            DB::table('inventory_categories')->where('id', $id)
                ->update(array_merge($data, ['updated_at' => now()]));

            // Keep the legacy denormalised string on products in step.
            if (isset($data['name'])) {
                DB::table('inventory_products')->where('category_id', $id)
                    ->update(['category' => $data['name'], 'updated_at' => now()]);
            }
        });

        $this->audit->record($request, 'category', $id, 'updated', $before, $data, $existing->name);

        return response()->json(['message' => 'Category updated']);
    }

    /**
     * DELETE /inventory/categories/{id}
     *
     * By default, refuses if the category has products.
     * Pass ?force=1 (admin-only) to null out product references instead.
     */
    #[OA\Delete(
        path: '/inventory/categories/{id}',
        summary: 'Delete a resource',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Category'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function destroy(Request $request, int $id)
    {
        $existing = DB::table('inventory_categories')->where('id', $id)->first();
        if (! $existing) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $force    = filter_var($request->query('force', false), FILTER_VALIDATE_BOOLEAN);
        $inUse    = DB::table('inventory_products')->where('category_id', $id)->exists();

        if ($inUse && ! $force) {
            return response()->json([
                'message'       => 'Category is in use by products. Pass ?force=1 to remove anyway.',
                'products_count' => DB::table('inventory_products')->where('category_id', $id)->count(),
            ], 422);
        }

        if ($force && $inUse) {
            // Only admins/super_admin may force-delete a category with products
            $user = $request->user();
            if (! $user || ! ($user->isSuperAdmin() || in_array($user->role, ['admin', 'manager']) || $user->full_access)) {
                return response()->json(['message' => 'Only admins may force-delete a category with products.'], 403);
            }
            // Null out the FK on products — they remain, just uncategorised
            DB::table('inventory_products')->where('category_id', $id)->update([
                'category_id' => null,
                'category'    => null,
                'updated_at'  => now(),
            ]);
        }

        DB::table('inventory_categories')->where('id', $id)->delete();

        $this->audit->record($request, 'category', $id, 'deleted', (array) $existing, null, $existing->name);

        return response()->json(['message' => 'Category deleted']);
    }
}
