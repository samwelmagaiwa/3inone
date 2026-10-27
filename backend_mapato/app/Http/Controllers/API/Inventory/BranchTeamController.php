<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\User;
use App\Support\Inventory\MonthlyFigures;
use App\Support\Salon\SalonAccess;
use App\Support\Salon\SalonBranch;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * Who works in which branch, and what each branch and each person sold. The owner places a person in a branch (their home
 * branch: new sales they make are recorded in it when no other branch is chosen); the sales report compares branches and
 * people over any period. Profit is shown only to those who may see profit.
 */
#[OA\Tag(name: 'Inventory / Branches', description: 'Staff by branch and sales by branch and by person')]
class BranchTeamController extends Controller
{
    private function requireOwner(Request $request): void
    {
        abort_unless(SalonAccess::canConfigure($request->user()), 403, 'Ni mmiliki tu anayeweza kufanya hivi. / Only the owner can do this.');
        abort_unless(SalonBranch::available(), 404, 'Matawi hayapatikani. / Branches are not available.');
    }

    #[OA\Get(path: '/inventory/branch-team', summary: 'Each person with the branch they work in', security: [['bearerAuth' => []]], tags: ['Inventory / Branches'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function index(Request $request): JsonResponse
    {
        $this->requireOwner($request);
        $homes = Schema::hasColumn('inventory_staff_profiles', 'branch_id')
            ? DB::table('inventory_staff_profiles')->pluck('branch_id', 'staff_id')
            : collect();
        $names = DB::table('inventory_branches')->pluck('name', 'id');

        $rows = User::query()->whereIn('id', $request->user()->accountMemberIds())->where('is_active', true)
            ->orderBy('name')->get(['id', 'name', 'role'])
            ->map(function ($u) use ($homes, $names) {
                $b = $homes[(string) $u->id] ?? null;

                return ['staff_id' => (string) $u->id, 'name' => $u->name, 'role' => $u->role,
                    'branch_id' => $b === null ? null : (int) $b, 'branch' => $b === null ? null : ($names[$b] ?? null)];
            })->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Put(path: '/inventory/branch-team/{staffId}', summary: 'Place a person in a branch (null = not tied to one)', security: [['bearerAuth' => []]], tags: ['Inventory / Branches'], parameters: [new OA\Parameter(name: 'staffId', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function assign(Request $request, string $staffId): JsonResponse
    {
        $this->requireOwner($request);
        $data = $request->validate(['branch_id' => 'present|nullable|integer']);
        if (!User::query()->whereIn('id', $request->user()->accountMemberIds())->where('id', $staffId)->exists()) {
            throw ValidationException::withMessages(['staff_id' => ['Mtu huyo hayumo kwenye biashara hii. / That person is not in this business.']]);
        }
        if ($data['branch_id'] !== null && DB::table('inventory_branches')->where('id', $data['branch_id'])->where('active', true)->doesntExist()) {
            throw ValidationException::withMessages(['branch_id' => ['Tawi hilo halipo au limezimwa. / That branch does not exist or is switched off.']]);
        }

        $existing = DB::table('inventory_staff_profiles')->where('staff_id', $staffId)->first();
        if ($existing) {
            DB::table('inventory_staff_profiles')->where('id', $existing->id)->update(['branch_id' => $data['branch_id'], 'updated_at' => now()]);
        } else {
            DB::table('inventory_staff_profiles')->insert(['staff_id' => $staffId, 'branch_id' => $data['branch_id'], 'created_at' => now(), 'updated_at' => now()]);
        }

        return response()->json(['message' => 'Saved']);
    }

    #[OA\Get(path: '/inventory/branch-sales', summary: 'Sales, paid and profit by branch and by person for a period', security: [['bearerAuth' => []]], tags: ['Inventory / Branches'], parameters: [new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string')), new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function sales(Request $request): JsonResponse
    {
        $user = $request->user();
        abort_unless($user->hasInventoryPermission('inv_view_reports'), 403, 'Huna ruhusa ya kuona ripoti. / You may not see reports.');
        $data = $request->validate(['from' => 'nullable|date', 'to' => 'nullable|date|after_or_equal:from']);
        $tz = MonthlyFigures::TIMEZONE;
        $to = Carbon::parse($data['to'] ?? now($tz)->toDateString(), $tz);
        $from = Carbon::parse($data['from'] ?? $to->copy()->startOfMonth()->toDateString(), $tz);
        $fromUtc = $from->copy()->startOfDay()->utc()->format('Y-m-d H:i:s');
        $toUtc = $to->copy()->endOfDay()->utc()->format('Y-m-d H:i:s');
        $branchCol = SalonBranch::available() ? 's.branch_id' : 'NULL';

        $base = fn () => DB::table('inventory_sales as s')
            ->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')
            ->whereBetween('s.created_at', [$fromUtc, $toUtc]);

        $groups = $base()->groupBy(DB::raw($branchCol), 's.created_by')
            ->get([DB::raw($branchCol . ' as branch_id'), 's.created_by as staff_id',
                DB::raw('COUNT(*) as n'), DB::raw('SUM(s.total) as sales'), DB::raw('SUM(s.paid_total) as paid')]);
        $costs = [];
        foreach ($base()->join('inventory_sale_items as si', 'si.sale_id', '=', 's.id')->groupBy(DB::raw($branchCol), 's.created_by')
            ->get([DB::raw($branchCol . ' as branch_id'), 's.created_by as staff_id', DB::raw('SUM(si.unit_cost_snapshot * si.quantity) as cost')]) as $c) {
            $costs[($c->branch_id ?? '') . '|' . $c->staff_id] = (float) $c->cost;
        }

        $branchNames = Schema::hasTable('inventory_branches') ? DB::table('inventory_branches')->pluck('name', 'id') : collect();
        $staffNames = User::query()->whereIn('id', $groups->pluck('staff_id')->filter()->unique()->all())->pluck('name', 'id');

        $blank = fn (array $who) => $who + ['sales_count' => 0, 'sales' => 0.0, 'paid' => 0.0, 'profit' => 0.0];
        $add = function (array $row, array $cell): array {
            $row['sales_count'] += $cell['sales_count'];
            $row['sales'] = round($row['sales'] + $cell['sales'], 2);
            $row['paid'] = round($row['paid'] + $cell['paid'], 2);
            $row['profit'] = round($row['profit'] + $cell['profit'], 2);

            return $row;
        };

        $byBranch = [];
        $byStaff = [];
        foreach ($groups as $g) {
            $bid = $g->branch_id === null ? null : (int) $g->branch_id;
            $sid = (string) $g->staff_id;
            $bname = $bid === null ? null : ($branchNames[$bid] ?? '#' . $bid);
            $sname = $staffNames[$sid] ?? '?';
            $cell = [
                'sales_count' => (int) $g->n, 'sales' => round((float) $g->sales, 2), 'paid' => round((float) $g->paid, 2),
                'profit' => round((float) $g->sales - ($costs[($g->branch_id ?? '') . '|' . $g->staff_id] ?? 0.0), 2),
            ];

            $byBranch[(string) $bid] ??= $blank(['branch_id' => $bid, 'name' => $bname]) + ['staff' => []];
            $byBranch[(string) $bid] = $add($byBranch[(string) $bid], $cell);
            $byBranch[(string) $bid]['staff'][] = ['staff_id' => $sid, 'name' => $sname] + $cell;

            $byStaff[$sid] ??= $blank(['staff_id' => $sid, 'name' => $sname]) + ['branches' => []];
            $byStaff[$sid] = $add($byStaff[$sid], $cell);
            $byStaff[$sid]['branches'][] = ['branch_id' => $bid, 'name' => $bname] + $cell;
        }

        // Profit only for those who may see it.
        $seesProfit = $user->hasInventoryPermission('inv_view_reports');
        $finish = function (array $rows, string $inner) use ($seesProfit): array {
            return collect($rows)->map(function ($r) use ($seesProfit, $inner) {
                if (!$seesProfit) {
                    $r['profit'] = null;
                    $r[$inner] = array_map(fn ($x) => ['profit' => null] + $x, $r[$inner]);
                }
                usort($r[$inner], fn ($a, $b) => $b['sales'] <=> $a['sales']);

                return $r;
            })->sortByDesc('sales')->values()->all();
        };

        return response()->json(['data' => [
            'from' => $from->toDateString(), 'to' => $to->toDateString(),
            'by_branch' => $finish($byBranch, 'staff'),
            'by_staff' => $finish($byStaff, 'branches'),
            'total' => ['sales_count' => (int) $groups->sum('n'), 'sales' => round((float) $groups->sum('sales'), 2), 'paid' => round((float) $groups->sum('paid'), 2)],
        ]]);
    }
}
