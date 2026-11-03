<?php

namespace App\Http\Controllers\API\Inventory;

use App\Support\Salon\SalonAccess;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * The salon's branches. Everyone in the salon can see the list (to say which branch they are working in); the owner and
 * managers add, change and switch them off. A branch that anything was recorded against is switched off, never deleted,
 * so old figures keep their branch.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Salon branches')]
class SalonBranchController extends Controller
{
    private function requireManager(Request $request): void
    {
        abort_unless(SalonAccess::canConfigure($request->user()), 403, 'Ni mmiliki tu anayeweza kufanya hivi. / Only the owner can do this.');
    }

    private function used(int $id): bool
    {
        foreach (['inventory_sales', 'inventory_expenses', 'inventory_appointments', 'inventory_salon_shifts', 'inventory_attendance', 'inventory_staff_profiles'] as $table) {
            if (DB::table($table)->where('branch_id', $id)->exists()) {
                return true;
            }
        }

        return false;
    }

    #[OA\Get(path: '/inventory/salon/branches', summary: 'The salon\'s branches', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function index(Request $request): JsonResponse
    {
        $manager = SalonAccess::canConfigure($request->user());
        $rows = DB::table('inventory_branches')->when(!$manager, fn ($q) => $q->where('active', true))->orderByDesc('active')->orderBy('name')->get()->map(fn ($b) => [
            'id' => (int) $b->id, 'name' => $b->name, 'address' => $b->address, 'phone' => $b->phone, 'active' => (bool) $b->active,
            'region' => $b->region ?? null, 'district' => $b->district ?? null, 'ward' => $b->ward ?? null, 'street' => $b->street ?? null,
        ])->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Post(path: '/inventory/salon/branches', summary: 'Add a branch', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function store(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate(['name' => 'required|string|min:2|max:80', 'address' => 'nullable|string|max:160', 'phone' => 'nullable|string|max:30', 'region' => 'nullable|string|max:80', 'district' => 'nullable|string|max:80', 'ward' => 'nullable|string|max:80', 'street' => 'nullable|string|max:80']);
        $name = trim($data['name']);
        if (DB::table('inventory_branches')->where('name', $name)->exists()) {
            throw ValidationException::withMessages(['name' => ['Tawi hili lipo tayari. / That branch already exists.']]);
        }

        $id = DB::table('inventory_branches')->insertGetId([
            'name' => $name, 'address' => trim((string) ($data['address'] ?? '')) ?: null, 'phone' => trim((string) ($data['phone'] ?? '')) ?: null,
            'region' => trim((string) ($data['region'] ?? '')) ?: null, 'district' => trim((string) ($data['district'] ?? '')) ?: null,
            'ward' => trim((string) ($data['ward'] ?? '')) ?: null, 'street' => trim((string) ($data['street'] ?? '')) ?: null,
            'active' => true, 'created_by' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Saved', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Put(path: '/inventory/salon/branches/{id}', summary: 'Change a branch or switch it off', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function update(Request $request, int $id): JsonResponse
    {
        $this->requireManager($request);
        abort_if(DB::table('inventory_branches')->where('id', $id)->doesntExist(), 404, 'Branch not found');
        $data = $request->validate(['name' => 'sometimes|string|min:2|max:80', 'address' => 'sometimes|nullable|string|max:160', 'phone' => 'sometimes|nullable|string|max:30', 'active' => 'sometimes|boolean', 'region' => 'sometimes|nullable|string|max:80', 'district' => 'sometimes|nullable|string|max:80', 'ward' => 'sometimes|nullable|string|max:80', 'street' => 'sometimes|nullable|string|max:80']);
        if (isset($data['name'])) {
            $data['name'] = trim($data['name']);
            if (DB::table('inventory_branches')->where('name', $data['name'])->where('id', '!=', $id)->exists()) {
                throw ValidationException::withMessages(['name' => ['Tawi hili lipo tayari. / That branch already exists.']]);
            }
        }
        foreach (['address', 'phone', 'region', 'district', 'ward', 'street'] as $k) {
            if (array_key_exists($k, $data)) {
                $data[$k] = trim((string) $data[$k]) ?: null;
            }
        }
        DB::table('inventory_branches')->where('id', $id)->update($data + ['updated_at' => now()]);

        return response()->json(['message' => 'Saved']);
    }

    #[OA\Delete(path: '/inventory/salon/branches/{id}', summary: 'Delete a branch nothing was recorded against', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function destroy(Request $request, int $id): JsonResponse
    {
        $this->requireManager($request);
        abort_if(DB::table('inventory_branches')->where('id', $id)->doesntExist(), 404, 'Branch not found');
        if ($this->used($id)) {
            throw ValidationException::withMessages(['branch' => ['Tawi lenye historia halifutwi: lizime badala yake. / A branch with a history cannot be deleted: switch it off instead.']]);
        }
        DB::table('inventory_branches')->where('id', $id)->delete();

        return response()->json(['message' => 'Deleted']);
    }
}
