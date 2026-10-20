<?php

namespace App\Http\Controllers\API\Inventory;

use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\SalonAccess;
use App\Support\Salon\SalonFinance;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * The salon's equipment: dryers, steamers, chairs, basins. What it cost, whether it works, when it is next due for
 * service, and every service and repair it has had. A repair or service that cost money is also put in the expenses
 * (once), so the profit knows. Kept by the owner, managers and the stock manager.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Salon equipment and its upkeep')]
class SalonEquipmentController extends Controller
{
    /** Service or repair due within this many days is flagged. */
    private const SOON_DAYS = 7;

    private function requireKeeper(Request $request): void
    {
        $u = $request->user();
        abort_unless(SalonAccess::isManager($u) || strtolower((string) $u->role) === 'stock_manager', 403, 'Mmiliki, meneja au msimamizi wa stoo tu. / Only the owner, a manager or the stock manager.');
    }

    private function today(): Carbon
    {
        return Carbon::now(AppointmentPlanner::TIMEZONE)->startOfDay();
    }

    #[OA\Get(path: '/inventory/salon/equipment', summary: 'The equipment with what is due and what it all cost', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function index(Request $request): JsonResponse
    {
        $this->requireKeeper($request);
        $today = $this->today();
        $soon = $today->copy()->addDays(self::SOON_DAYS)->toDateString();

        $repairs = DB::table('inventory_equipment_logs')->groupBy('equipment_id')->selectRaw('equipment_id, COUNT(*) as n, SUM(cost) as spent')->get()->keyBy('equipment_id');

        $rows = DB::table('inventory_equipment')->orderByRaw("CASE status WHEN 'repair' THEN 0 WHEN 'working' THEN 1 ELSE 2 END")->orderBy('name')->get()->map(function ($e) use ($repairs, $today, $soon) {
            $due = $e->next_service_on ? Carbon::parse($e->next_service_on)->toDateString() : null;

            return [
                'id' => (int) $e->id,
                'name' => $e->name,
                'kind' => $e->kind,
                'serial' => $e->serial,
                'bought_on' => $e->bought_on ? Carbon::parse($e->bought_on)->toDateString() : null,
                'cost' => SalonFinance::money($e->cost),
                'status' => $e->status,
                'next_service_on' => $due,
                // Overdue or coming up soon (retired things are never due).
                'overdue' => $e->status !== 'retired' && $due !== null && $due < $today->toDateString(),
                'due_soon' => $e->status !== 'retired' && $due !== null && $due >= $today->toDateString() && $due <= $soon,
                'notes' => $e->notes,
                'jobs' => (int) ($repairs[$e->id]->n ?? 0),
                'spent_on_upkeep' => SalonFinance::money($repairs[$e->id]->spent ?? 0),
            ];
        })->values();

        return response()->json(['data' => [
            'equipment' => $rows,
            'totals' => [
                'count' => $rows->where('status', '!=', 'retired')->count(),
                'value' => SalonFinance::money($rows->where('status', '!=', 'retired')->sum('cost')),
                'in_repair' => $rows->where('status', 'repair')->count(),
                'needs_attention' => $rows->filter(fn ($r) => $r['overdue'] || $r['due_soon'])->count(),
            ],
        ]]);
    }

    private function rules(bool $creating): array
    {
        $req = $creating ? 'required' : 'sometimes';

        return [
            'name' => "{$req}|string|min:2|max:120",
            'kind' => 'sometimes|nullable|string|max:40',
            'serial' => 'sometimes|nullable|string|max:80',
            'bought_on' => 'sometimes|nullable|date_format:Y-m-d|before_or_equal:today',
            'cost' => 'sometimes|nullable|numeric|min:0|max:1000000000',
            'status' => ['sometimes', Rule::in(['working', 'repair', 'retired'])],
            'next_service_on' => 'sometimes|nullable|date_format:Y-m-d',
            'notes' => 'sometimes|nullable|string|max:255',
        ];
    }

    #[OA\Post(path: '/inventory/salon/equipment', summary: 'Add a piece of equipment', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function store(Request $request): JsonResponse
    {
        $this->requireKeeper($request);
        $data = $request->validate($this->rules(true));

        $id = DB::table('inventory_equipment')->insertGetId($this->row($data) + ['status' => $data['status'] ?? 'working', 'created_by' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now()]);

        return response()->json(['message' => 'Saved', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Put(path: '/inventory/salon/equipment/{id}', summary: 'Change a piece of equipment (or say it is in repair or retired)', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function update(Request $request, int $id): JsonResponse
    {
        $this->requireKeeper($request);
        abort_if(DB::table('inventory_equipment')->where('id', $id)->doesntExist(), 404, 'Equipment not found');
        $data = $request->validate($this->rules(false));

        DB::table('inventory_equipment')->where('id', $id)->update($this->row($data) + (isset($data['status']) ? ['status' => $data['status']] : []) + ['updated_at' => now()]);

        return response()->json(['message' => 'Saved']);
    }

    /** Only what was sent changes. */
    private function row(array $data): array
    {
        $out = [];
        foreach (['name', 'kind', 'serial', 'bought_on', 'next_service_on', 'notes'] as $k) {
            if (array_key_exists($k, $data)) {
                $v = is_string($data[$k]) ? trim($data[$k]) : $data[$k];
                $out[$k] = $v === '' ? null : $v;
            }
        }
        if (array_key_exists('cost', $data)) {
            $out['cost'] = (float) ($data['cost'] ?? 0);
        }

        return $out;
    }

    #[OA\Delete(path: '/inventory/salon/equipment/{id}', summary: 'Delete equipment that has no history (retire it otherwise)', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function destroy(Request $request, int $id): JsonResponse
    {
        $this->requireKeeper($request);
        abort_if(DB::table('inventory_equipment')->where('id', $id)->doesntExist(), 404, 'Equipment not found');
        if (DB::table('inventory_equipment_logs')->where('equipment_id', $id)->exists()) {
            throw ValidationException::withMessages(['equipment' => ['Kifaa chenye historia hakifutwi: kistaafishe badala yake. / Equipment with a history cannot be deleted: retire it instead.']]);
        }
        DB::table('inventory_equipment')->where('id', $id)->delete();

        return response()->json(['message' => 'Deleted']);
    }

    #[OA\Get(path: '/inventory/salon/equipment/{id}/logs', summary: 'Every service and repair', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function logs(Request $request, int $id): JsonResponse
    {
        $this->requireKeeper($request);
        abort_if(DB::table('inventory_equipment')->where('id', $id)->doesntExist(), 404, 'Equipment not found');

        $rows = DB::table('inventory_equipment_logs')->where('equipment_id', $id)->orderByDesc('done_on')->orderByDesc('id')->get()->map(fn ($l) => [
            'id' => (int) $l->id,
            'kind' => $l->kind,
            'done_on' => Carbon::parse($l->done_on)->toDateString(),
            'cost' => SalonFinance::money($l->cost),
            'description' => $l->description,
            'in_expenses' => $l->expense_id !== null,
        ])->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Post(path: '/inventory/salon/equipment/{id}/logs', summary: 'Record a service or repair (and what it cost)', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function addLog(Request $request, int $id): JsonResponse
    {
        $this->requireKeeper($request);
        $equipment = DB::table('inventory_equipment')->find($id);
        abort_if($equipment === null, 404, 'Equipment not found');
        $data = $request->validate([
            'kind' => ['required', Rule::in(['maintenance', 'repair'])],
            'done_on' => 'nullable|date_format:Y-m-d|before_or_equal:today',
            'cost' => 'nullable|numeric|min:0|max:1000000000',
            'description' => 'required|string|min:3|max:255',
            'next_service_on' => 'nullable|date_format:Y-m-d',
            'record_expense' => 'sometimes|boolean',
            // Working again after a repair (default), or still in repair.
            'status' => ['sometimes', Rule::in(['working', 'repair', 'retired'])],
        ]);
        $on = $data['done_on'] ?? $this->today()->toDateString();
        $cost = (float) ($data['cost'] ?? 0);

        $expenseId = null;
        // What it cost goes in the books once, as an expense (approved: the keeper is a manager or the stock manager).
        if ($cost > 0 && ($data['record_expense'] ?? true)) {
            $hasStatus = \Illuminate\Support\Facades\Schema::hasColumn('inventory_expenses', 'status');
            $expenseId = DB::table('inventory_expenses')->insertGetId([
                'category' => 'maintenance',
                'description' => mb_substr("{$equipment->name}: {$data['description']}", 0, 255),
                'amount' => $cost,
                'expense_date' => $on,
                'created_by' => (string) $request->user()->id,
                'created_at' => now(),
                'updated_at' => now(),
            ] + ($hasStatus ? ['status' => 'approved', 'approved_by' => (string) $request->user()->id, 'approved_at' => now()] : []));
        }

        $logId = DB::table('inventory_equipment_logs')->insertGetId([
            'equipment_id' => $id,
            'kind' => $data['kind'],
            'done_on' => $on,
            'cost' => $cost,
            'description' => trim($data['description']),
            'expense_id' => $expenseId,
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // A job that is done puts the equipment back to work and moves its next service on, unless told otherwise.
        $update = ['status' => $data['status'] ?? ($equipment->status === 'retired' ? 'retired' : 'working'), 'updated_at' => now()];
        if (array_key_exists('next_service_on', $data)) {
            $update['next_service_on'] = $data['next_service_on'];
        }
        DB::table('inventory_equipment')->where('id', $id)->update($update);

        return response()->json(['message' => 'Saved', 'data' => ['id' => (int) $logId, 'expense_id' => $expenseId]], 201);
    }
}
