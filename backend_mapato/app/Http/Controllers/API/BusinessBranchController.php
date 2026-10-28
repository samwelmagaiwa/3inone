<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Support\Tenancy\ServiceBranch;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * The branches of a business in Transport (yards, garages) or Rental (offices, areas). The shop and the salon keep theirs in
 * SalonBranchController. The service comes from the route, never from the request, so a branch can only be reached through the
 * service it belongs to; the business is always the signed-in person's own.
 */
class BusinessBranchController extends Controller
{
    /** The table that says where each service's records belong, and what to call them in a message. */
    private const RECORDS = [
        'transport' => [['drivers', 'branch_id'], ['devices', 'branch_id']],
        'rental' => [['rental_properties', 'branch_id']],
    ];

    private function service(Request $request): string
    {
        $service = (string) ($request->route()->defaults['service'] ?? '');
        abort_unless(isset(self::RECORDS[$service]), 404);

        return $service;
    }

    /** How many records of each kind sit in a branch (a branch with records is switched off, not deleted). */
    private function used(string $service, int $id): int
    {
        $n = 0;
        foreach (self::RECORDS[$service] as [$table, $column]) {
            $n += DB::table($table)->where($column, $id)->count();
        }

        return $n;
    }

    private function present(object $row, string $service): array
    {
        return [
            'id' => (int) $row->id,
            'name' => $row->name,
            'address' => $row->address,
            'phone' => $row->phone,
            'active' => (bool) $row->active,
            'records' => $this->used($service, (int) $row->id),
        ];
    }

    private function find(Request $request, string $service, int $id): object
    {
        $row = DB::table('business_branches')->where('id', $id)->where('owner_id', $request->user()->accountHeadId())->where('service', $service)->first();
        abort_if($row === null, 404, 'Not found');

        return $row;
    }

    public function index(Request $request): JsonResponse
    {
        $service = $this->service($request);
        $rows = DB::table('business_branches')
            ->where('owner_id', $request->user()->accountHeadId())->where('service', $service)
            ->orderBy('name')->get()
            ->map(fn ($r) => $this->present($r, $service))->values();

        return response()->json(['data' => $rows]);
    }

    public function store(Request $request): JsonResponse
    {
        $service = $this->service($request);
        $owner = $request->user()->accountHeadId();
        $data = $request->validate([
            'name' => ['required', 'string', 'max:80', Rule::unique('business_branches', 'name')->where('owner_id', $owner)->where('service', $service)],
            'address' => 'nullable|string|max:160',
            'phone' => 'nullable|string|max:30',
        ], ['name.unique' => 'Tawi lenye jina hili lipo tayari. / A branch with this name already exists.']);

        $id = DB::table('business_branches')->insertGetId($data + [
            'owner_id' => $owner, 'service' => $service, 'active' => true, 'created_by' => $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
        ServiceBranch::forget();

        return response()->json(['data' => $this->present(DB::table('business_branches')->find($id), $service)], 201);
    }

    public function update(Request $request, int $id): JsonResponse
    {
        $service = $this->service($request);
        $row = $this->find($request, $service, $id);
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:80', Rule::unique('business_branches', 'name')->where('owner_id', $row->owner_id)->where('service', $service)->ignore($id)],
            'address' => 'sometimes|nullable|string|max:160',
            'phone' => 'sometimes|nullable|string|max:30',
            'active' => 'sometimes|boolean',
        ], ['name.unique' => 'Tawi lenye jina hili lipo tayari. / A branch with this name already exists.']);

        if ($data !== []) {
            DB::table('business_branches')->where('id', $id)->update($data + ['updated_at' => now()]);
            ServiceBranch::forget();
        }

        return response()->json(['data' => $this->present(DB::table('business_branches')->find($id), $service)]);
    }

    public function destroy(Request $request, int $id): JsonResponse
    {
        $service = $this->service($request);
        $this->find($request, $service, $id);
        if ($this->used($service, $id) > 0) {
            return response()->json(['message' => 'Tawi lina rekodi: lizime badala ya kulifuta. / This branch has records: switch it off instead of deleting it.'], 422);
        }
        DB::table('business_branches')->where('id', $id)->delete();
        ServiceBranch::forget();

        return response()->json(['message' => 'Deleted']);
    }
}
