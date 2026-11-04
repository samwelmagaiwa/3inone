<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\User;
use App\Services\Inventory\AuditTrail;
use App\Support\Salon\SalonAccess;
use App\Support\Salon\StylistPerformance;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * What the owner expects each stylist to bring in for a month. Whoever sees everyone's results may read them; only whoever sets the salon up
 * (the settings right: the owner by default) may change them. A person given a target sees how close they are on their own results line.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Monthly targets per stylist')]
class StylistTargetController extends Controller
{
    public function __construct(private readonly AuditTrail $audit) {}

    private function month(Request $request): string
    {
        $month = (string) $request->query('month', $request->input('month', now()->format('Y-m')));
        abort_unless(preg_match('/^\d{4}-(0[1-9]|1[0-2])$/', $month) === 1, 422, 'Month must look like 2026-11.');

        return $month;
    }

    /** Everyone who can serve, with the target (if any) for the month and how they stand against it. */
    #[OA\Get(path: '/inventory/salon/stylist-targets', summary: 'Monthly targets and progress per person', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function show(Request $request): JsonResponse
    {
        abort_unless(SalonAccess::isManager($request->user()), 403, 'Ni mmiliki, meneja au mhasibu tu. / Only the owner, a manager or an accountant.');
        $month = $this->month($request);
        $progress = StylistPerformance::targets($month, now()->toDateString());

        $people = User::query()->whereIn('id', $request->user()->accountMemberIds())->where('is_active', true)->orderBy('name')->get(['id', 'name', 'role'])
            ->map(fn ($u) => ['staff_id' => (string) $u->id, 'name' => $u->name, 'role' => $u->role, 'target' => $progress[(string) $u->id] ?? null])
            ->values();

        return response()->json(['data' => ['month' => $month, 'can_set' => SalonAccess::canConfigure($request->user()), 'people' => $people]]);
    }

    /** Sets (or, with 0 or nothing, removes) the targets of the people named; the rest are left as they are. */
    #[OA\Put(path: '/inventory/salon/stylist-targets', summary: 'Set the monthly targets', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function save(Request $request): JsonResponse
    {
        abort_unless(SalonAccess::canConfigure($request->user()), 403, 'Ni mmiliki tu anayeweka malengo. / Only the owner sets targets.');
        $month = $this->month($request);
        $data = $request->validate([
            'month' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'],
            'targets' => 'required|array|min:1|max:200',
            'targets.*.staff_id' => 'required|string',
            'targets.*.revenue_target' => 'nullable|numeric|min:0|max:100000000000',
        ]);

        $members = array_map('strval', $request->user()->accountMemberIds());
        $before = DB::table('inventory_staff_targets')->where('month', $month)->pluck('revenue_target', 'staff_id')->all();
        foreach ($data['targets'] as $t) {
            abort_unless(in_array((string) $t['staff_id'], $members, true), 422, 'That person is not in this business.');
            $amount = round((float) ($t['revenue_target'] ?? 0), 2);
            $where = ['staff_id' => (string) $t['staff_id'], 'month' => $month];
            if ($amount <= 0) {
                DB::table('inventory_staff_targets')->where($where)->delete();

                continue;
            }
            DB::table('inventory_staff_targets')->updateOrInsert($where, ['revenue_target' => $amount, 'service' => 'salon', 'created_by' => (string) $request->user()->id, 'updated_at' => now()] + (DB::table('inventory_staff_targets')->where($where)->exists() ? [] : ['created_at' => now()]));
        }
        $after = DB::table('inventory_staff_targets')->where('month', $month)->pluck('revenue_target', 'staff_id')->all();
        $this->audit->record($request, 'staff_target', null, 'updated', $before, $after, "Targets for {$month}");

        return $this->show($request->duplicate(['month' => $month]));
    }
}
