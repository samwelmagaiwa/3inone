<?php

namespace App\Http\Controllers\API\Inventory;

use App\Support\Inventory\RecordTrash;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Validation\Rule;
use OpenApi\Attributes as OA;

/**
 * The Trash: what the owner or an admin has deleted (expenses, customers, debts from before the app, products and services), with the
 * way to restore it or remove it for good, and the sales that were cancelled (kept for the record). Only the owner and the admins of a
 * business may use it, and it only ever shows that business's own records.
 */
#[OA\Tag(name: 'Inventory / Trash', description: 'Deleted records: look, restore, remove for good')]
class TrashController extends Controller
{
    #[OA\Get(path: '/inventory/trash', summary: 'What is in the Trash: counts of each kind, and one kind listed (newest first)', security: [['bearerAuth' => []]], tags: ['Inventory / Trash'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function index(Request $request): JsonResponse
    {
        RecordTrash::requireManager($request);
        $data = $request->validate([
            'type' => ['nullable', Rule::in(array_merge(array_keys(RecordTrash::TYPES), ['sales']))],
            'page' => 'nullable|integer|min:1',
            'per_page' => 'nullable|integer|min:1|max:100',
        ]);

        $page = (int) ($data['page'] ?? 1);
        $perPage = (int) ($data['per_page'] ?? 30);
        $list = isset($data['type']) ? RecordTrash::list($data['type'], $page, $perPage) : ['rows' => [], 'total' => 0];

        return response()->json([
            'data' => $list['rows'],
            'counts' => RecordTrash::counts(),
            'meta' => ['current_page' => $page, 'per_page' => $perPage, 'total' => $list['total'], 'last_page' => max(1, (int) ceil($list['total'] / $perPage))],
        ]);
    }

    #[OA\Post(path: '/inventory/trash/{type}/{id}/restore', summary: 'Bring a record back from the Trash', security: [['bearerAuth' => []]], tags: ['Inventory / Trash'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function restore(Request $request, string $type, int $id): JsonResponse
    {
        RecordTrash::requireManager($request);
        $this->guardType($type, true);
        if ($type === 'sales') {
            return response()->json(['message' => 'Mauzo yaliyofutwa hayarudishwi: bidhaa na malipo yalirudishwa. Fanya mauzo mapya. / A cancelled sale cannot be restored: its stock and payments were reversed. Make a new sale.'], 422);
        }
        $data = $request->validate(['sku' => 'nullable|string|max:120']);

        return response()->json(['message' => 'Restored', 'data' => RecordTrash::restore($request, $type, $id, $data['sku'] ?? null)]);
    }

    #[OA\Delete(path: '/inventory/trash/{type}/{id}', summary: 'Remove a trashed record for good (asks for confirm=DELETE; refused when it has history)', security: [['bearerAuth' => []]], tags: ['Inventory / Trash'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function remove(Request $request, string $type, int $id): JsonResponse
    {
        RecordTrash::requireManager($request);
        $this->guardType($type, true);
        if ($type === 'sales') {
            return response()->json(['message' => 'Mauzo yaliyofutwa hubaki kwa kumbukumbu. / Cancelled sales are kept for the record.'], 422);
        }
        $request->validate(['confirm' => ['required', Rule::in(['DELETE'])]]);
        RecordTrash::remove($request, $type, $id);

        return response()->json(['message' => 'Removed for good']);
    }

    private function guardType(string $type, bool $allowSales): void
    {
        abort_unless(array_key_exists($type, RecordTrash::TYPES) || ($allowSales && $type === 'sales'), 404, 'Unknown kind');
    }
}
