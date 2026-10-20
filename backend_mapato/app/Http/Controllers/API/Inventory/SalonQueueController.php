<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\User;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * The walk-in queue: clients who arrive without an appointment wait their turn. Each is waiting, being served, done or
 * left; the page shows the order and a rough wait (the time of the services ahead of them). Today's queue only.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Walk-in queue')]
class SalonQueueController extends Controller
{
    private const DEFAULT_MINUTES = 45;

    private function today(): Carbon
    {
        return Carbon::now(AppointmentPlanner::TIMEZONE)->startOfDay();
    }

    /** Midnight (the salon's clock) in the database's time. */
    private function dayStart(): Carbon
    {
        return $this->today()->copy()->utc();
    }

    #[OA\Get(path: '/inventory/salon/queue', summary: 'Today\'s walk-in queue with the rough wait', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function index(): JsonResponse
    {
        $rows = DB::table('inventory_walkins')->where('arrived_at', '>=', $this->dayStart())->orderBy('arrived_at')->orderBy('id')->get();
        $minutes = DB::table('inventory_products')->whereIn('id', $rows->pluck('product_id')->filter()->unique())->pluck('duration_minutes', 'id');
        $mins = fn ($r) => (int) ($r->product_id !== null ? ($minutes[$r->product_id] ?? self::DEFAULT_MINUTES) : self::DEFAULT_MINUTES) ?: self::DEFAULT_MINUTES;

        $ahead = $rows->where('status', 'serving')->sum(fn ($r) => $mins($r));
        $queue = [];
        $position = 0;
        foreach ($rows as $r) {
            $row = [
                'id' => (int) $r->id,
                'name' => $r->name,
                'phone' => $r->phone,
                'customer_id' => $r->customer_id === null ? null : (int) $r->customer_id,
                'service' => $r->product_name,
                'product_id' => $r->product_id === null ? null : (int) $r->product_id,
                'staff_id' => $r->staff_id,
                'staff_name' => $r->staff_name,
                'status' => $r->status,
                'note' => $r->note,
                'arrived_at' => Carbon::parse($r->arrived_at, 'UTC')->setTimezone(AppointmentPlanner::TIMEZONE)->format('H:i'),
            ];
            if ($r->status === 'waiting') {
                $position++;
                $row['position'] = $position;
                $row['wait_minutes'] = $ahead;
                $ahead += $mins($r);
            }
            $queue[] = $row;
        }

        return response()->json(['data' => [
            'queue' => $queue,
            'waiting' => $rows->where('status', 'waiting')->count(),
            'serving' => $rows->where('status', 'serving')->count(),
            'done' => $rows->where('status', 'done')->count(),
            'left' => $rows->where('status', 'left')->count(),
        ]]);
    }

    #[OA\Post(path: '/inventory/salon/queue', summary: 'Put a walk-in client in the queue', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => 'required|string|min:2|max:120',
            'phone' => 'nullable|string|max:30',
            'customer_id' => 'nullable|integer',
            'product_id' => 'nullable|integer',
            'staff_id' => 'nullable|string|max:64',
            'note' => 'nullable|string|max:160',
        ]);

        $product = null;
        if (!empty($data['product_id'])) {
            $product = DB::table('inventory_products')->where('id', $data['product_id'])->where('is_service', true)->first();
            if ($product === null) {
                throw ValidationException::withMessages(['product_id' => ['Chagua huduma halisi. / Choose a real service.']]);
            }
        }
        if (!empty($data['customer_id']) && DB::table('inventory_customers')->where('id', $data['customer_id'])->doesntExist()) {
            throw ValidationException::withMessages(['customer_id' => ['Mteja huyo hayupo. / That client does not exist.']]);
        }
        $staffName = null;
        if (!empty($data['staff_id'])) {
            $staff = User::query()->whereKey($data['staff_id'])->whereIn('id', TenantContext::viewer()?->accountMemberIds() ?? [])->first();
            if ($staff === null) {
                throw ValidationException::withMessages(['staff_id' => ['Mhudumu huyo hayupo. / That person does not exist.']]);
            }
            $staffName = $staff->name;
        }

        $id = DB::table('inventory_walkins')->insertGetId([
            'customer_id' => $data['customer_id'] ?? null,
            'name' => trim($data['name']),
            'phone' => !empty($data['phone']) ? trim($data['phone']) : null,
            'product_id' => $product?->id,
            'product_name' => $product?->name,
            'staff_id' => $data['staff_id'] ?? null,
            'staff_name' => $staffName,
            'status' => 'waiting',
            'note' => !empty($data['note']) ? trim($data['note']) : null,
            'arrived_at' => now(),
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Saved', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Post(path: '/inventory/salon/queue/{id}/status', summary: 'Start serving, finish, or mark that a client left', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function status(Request $request, int $id): JsonResponse
    {
        $row = DB::table('inventory_walkins')->where('id', $id)->first();
        abort_if($row === null, 404, 'Not found');
        $data = $request->validate(['status' => ['required', Rule::in(['waiting', 'serving', 'done', 'left'])]]);

        // done and left are the end of the line: nobody is brought back by mistake.
        if (in_array($row->status, ['done', 'left'], true)) {
            throw ValidationException::withMessages(['status' => ['Mteja huyu amemaliza tayari. / This client is already finished.']]);
        }

        $update = ['status' => $data['status'], 'updated_at' => now()];
        if ($data['status'] === 'serving') {
            $update['started_at'] = now();
        }
        if (in_array($data['status'], ['done', 'left'], true)) {
            $update['finished_at'] = now();
        }
        DB::table('inventory_walkins')->where('id', $id)->update($update);

        return response()->json(['message' => 'Saved']);
    }
}
