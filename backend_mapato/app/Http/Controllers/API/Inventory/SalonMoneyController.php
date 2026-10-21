<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\User;
use App\Support\PaymentChannels;
use App\Support\Salon\AppointmentPlanner;
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
 * The salon's money pages: profit and loss, the dashboard's figures, what each person earns and what has been paid
 * out to them. Only the owner and managers see salaries and payroll: an ordinary stylist sees their own commission on
 * the stylists page, never anyone else's pay.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Salon money: profit and loss, overview, payroll')]
class SalonMoneyController extends Controller
{
    private function today(): Carbon
    {
        return Carbon::now(AppointmentPlanner::TIMEZONE)->startOfDay();
    }

    private function isManager(Request $request): bool
    {
        $u = $request->user();

        return \App\Support\Salon\SalonAccess::isManager($u);
    }

    private function requireManager(Request $request): void
    {
        abort_unless($this->isManager($request), 403, 'Ni mmiliki au mhasibu tu anayeweza kuona hii. / Only the owner or the accountant can see this.');
    }

    // ------------------------------------------------------------------ profit and loss, the dashboard

    #[OA\Get(path: '/inventory/salon/profit-loss', summary: 'Revenue, costs, commissions, expenses and profit for a period (default: this month)', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function profitLoss(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate(['from' => 'nullable|date', 'to' => 'nullable|date|after_or_equal:from']);
        $today = $this->today();
        $from = isset($data['from']) ? Carbon::parse($data['from']) : $today->copy()->startOfMonth();
        $to = isset($data['to']) ? Carbon::parse($data['to']) : $today;

        return response()->json(['data' => SalonFinance::summary($from, $to, \App\Support\Salon\SalonBranch::selected($request))]);
    }

    #[OA\Get(path: '/inventory/salon/overview', summary: 'The dashboard: today, week, month, year, top services and staff, bookings', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function overview(Request $request): JsonResponse
    {
        $this->requireManager($request);

        return response()->json(['data' => SalonFinance::overview($this->today(), \App\Support\Salon\SalonBranch::selected($request))]);
    }

    // ------------------------------------------------------------------ who earns what

    #[OA\Get(path: '/inventory/salon/staff-profiles', summary: 'Each person with their specialization, monthly salary and own commission rate', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function profiles(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $profiles = DB::table('inventory_staff_profiles')->get()->keyBy('staff_id');

        $rows = User::query()
            ->whereIn('id', $request->user()->accountMemberIds())
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'name', 'role'])
            ->map(function ($u) use ($profiles) {
                $p = $profiles[(string) $u->id] ?? null;

                return [
                    'staff_id' => (string) $u->id,
                    'name' => $u->name,
                    'role' => $u->role,
                    'specialization' => $p->specialization ?? null,
                    'monthly_salary' => SalonFinance::money($p->monthly_salary ?? 0),
                    'commission_percent' => $p && $p->commission_percent !== null ? (float) $p->commission_percent : null,
                    'branch_id' => isset($p->branch_id) ? (int) $p->branch_id : null,
                    'work_days' => array_values(array_filter(array_map('intval', explode(',', (string) ($p->work_days ?? ''))))),
                    'shift_start' => $p->shift_start ?? null,
                    'shift_end' => $p->shift_end ?? null,
                ];
            })
            ->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Put(path: '/inventory/salon/staff-profiles/{staffId}', summary: 'Set a person\'s specialization, salary and own commission rate', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'staffId', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function saveProfile(Request $request, string $staffId): JsonResponse
    {
        $this->requireManager($request);
        $this->memberOrFail($request, $staffId);
        $data = $request->validate([
            'specialization' => 'nullable|string|max:60',
            'monthly_salary' => 'nullable|numeric|min:0|max:100000000',
            'commission_percent' => 'nullable|numeric|min:0|max:100',
            // The weekdays they work (Monday = 1) and their hours; none = not said (anyone, any time).
            'work_days' => 'nullable|array|max:7',
            'work_days.*' => 'integer|between:1,7',
            'shift_start' => ['nullable', 'regex:/^([01]\d|2[0-3]):[0-5]\d$/'],
            'shift_end' => ['nullable', 'regex:/^([01]\d|2[0-3]):[0-5]\d$/'],
            // Their home branch (none = not tied to one).
            'branch_id' => 'sometimes|nullable|integer',
        ]);
        if (!empty($data['branch_id']) && DB::table('inventory_branches')->where('id', $data['branch_id'])->doesntExist()) {
            throw ValidationException::withMessages(['branch_id' => ['Tawi hilo halipo. / That branch does not exist.']]);
        }
        if (!empty($data['shift_start']) && !empty($data['shift_end']) && $data['shift_start'] >= $data['shift_end']) {
            throw ValidationException::withMessages(['shift_end' => ['Saa ya kuondoka iwe baada ya saa ya kuanza. / The finishing time must be after the starting time.']]);
        }

        $existing = DB::table('inventory_staff_profiles')->where('staff_id', $staffId)->first();
        // Only what is sent changes; what is not sent stays.
        $row = [
            'specialization' => array_key_exists('specialization', $data) ? (trim((string) $data['specialization']) ?: null) : ($existing->specialization ?? null),
            'monthly_salary' => array_key_exists('monthly_salary', $data) ? (float) ($data['monthly_salary'] ?? 0) : (float) ($existing->monthly_salary ?? 0),
            'commission_percent' => array_key_exists('commission_percent', $data) ? $data['commission_percent'] : ($existing->commission_percent ?? null),
        ];
        if (array_key_exists('branch_id', $data) && \Illuminate\Support\Facades\Schema::hasColumn('inventory_staff_profiles', 'branch_id')) {
            $row['branch_id'] = $data['branch_id'] ?: null;
        }
        if (\Illuminate\Support\Facades\Schema::hasColumn('inventory_staff_profiles', 'work_days')) {
            if (array_key_exists('work_days', $data)) {
                $row['work_days'] = $data['work_days'] ? implode(',', collect($data['work_days'])->unique()->sort()->values()->all()) : null;
            }
            foreach (['shift_start', 'shift_end'] as $k) {
                if (array_key_exists($k, $data)) {
                    $row[$k] = $data[$k] ?: null;
                }
            }
        }

        if ($existing) {
            DB::table('inventory_staff_profiles')->where('id', $existing->id)->update($row + ['updated_at' => now()]);
        } else {
            DB::table('inventory_staff_profiles')->insert($row + ['staff_id' => $staffId, 'created_at' => now(), 'updated_at' => now()]);
        }

        return response()->json(['message' => 'Saved']);
    }

    // ------------------------------------------------------------------ payroll

    #[OA\Get(path: '/inventory/salon/payroll', summary: 'For a month: each person\'s salary, commission earned, what was paid and advanced, and what is still owed', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function payroll(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate(['month' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/']]);
        $month = $data['month'] ?? $this->today()->format('Y-m');
        $from = Carbon::createFromFormat('Y-m-d', $month . '-01')->startOfMonth();
        $to = $from->copy()->endOfMonth();

        $earned = \Illuminate\Support\Facades\Schema::hasColumn('inventory_sale_items', 'commission_amount')
            ? DB::table('inventory_sale_items as si')
                ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
                ->whereNull('s.cancelled_at')
                ->whereNotNull('si.staff_id')
                ->whereDate('s.created_at', '>=', $from->toDateString())
                ->whereDate('s.created_at', '<=', $to->toDateString())
                ->when(\App\Support\Salon\SalonBranch::selected($request) !== null, fn ($q) => $q->where('s.branch_id', \App\Support\Salon\SalonBranch::selected($request)))
                ->groupBy('si.staff_id')
                ->selectRaw('si.staff_id as staff_id, COALESCE(SUM(si.commission_amount), 0) as earned')
                ->pluck('earned', 'staff_id')
            : collect();

        $paid = DB::table('inventory_staff_payouts')
            ->where('period_month', $month)
            ->groupBy('staff_id', 'kind')
            ->selectRaw('staff_id, kind, SUM(amount) as total')
            ->get()
            ->groupBy('staff_id');

        $profiles = DB::table('inventory_staff_profiles')->get()->keyBy('staff_id');

        $rows = User::query()
            ->whereIn('id', $request->user()->accountMemberIds())
            ->orderBy('name')
            ->get(['id', 'name', 'role', 'is_active'])
            ->map(function ($u) use ($earned, $paid, $profiles) {
                $id = (string) $u->id;
                $by = collect($paid[$id] ?? [])->pluck('total', 'kind');
                $salary = (float) ($profiles[$id]->monthly_salary ?? 0);
                $commission = (float) ($earned[$id] ?? 0);
                $salaryPaid = (float) ($by['salary'] ?? 0);
                $commissionPaid = (float) ($by['commission'] ?? 0);
                $advances = (float) ($by['advance'] ?? 0);

                return [
                    'staff_id' => $id,
                    'name' => $u->name,
                    'active' => (bool) $u->is_active,
                    'salary' => SalonFinance::money($salary),
                    'commission_earned' => SalonFinance::money($commission),
                    'salary_paid' => SalonFinance::money($salaryPaid),
                    'commission_paid' => SalonFinance::money($commissionPaid),
                    'advances' => SalonFinance::money($advances),
                    // What the salon still owes them for the month: what they earned less everything already given.
                    'owed' => SalonFinance::money($salary + $commission - $salaryPaid - $commissionPaid - $advances),
                ];
            })
            // Someone who left and has nothing to do with this month is not listed.
            ->filter(fn ($r) => $r['active'] || $r['salary'] > 0 || $r['commission_earned'] > 0 || $r['salary_paid'] > 0 || $r['commission_paid'] > 0 || $r['advances'] > 0)
            ->values();

        $sum = fn (string $k) => SalonFinance::money($rows->sum($k));

        return response()->json(['data' => [
            'month' => $month,
            'staff' => $rows,
            'totals' => [
                'salary' => $sum('salary'), 'commission_earned' => $sum('commission_earned'), 'salary_paid' => $sum('salary_paid'),
                'commission_paid' => $sum('commission_paid'), 'advances' => $sum('advances'), 'owed' => $sum('owed'),
            ],
        ]]);
    }

    #[OA\Get(path: '/inventory/salon/payouts', summary: 'What has been paid out to staff (salary, commission, advances)', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function payouts(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate(['month' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'], 'staff_id' => 'nullable|string|max:64']);

        $rows = DB::table('inventory_staff_payouts')
            ->when(!empty($data['month']), fn ($q) => $q->where('period_month', $data['month']))
            ->when(!empty($data['staff_id']), fn ($q) => $q->where('staff_id', $data['staff_id']))
            ->orderByDesc('paid_on')
            ->orderByDesc('id')
            ->get()
            ->map(fn ($r) => [
                'id' => (int) $r->id,
                'staff_id' => $r->staff_id,
                'staff_name' => $r->staff_name,
                'kind' => $r->kind,
                'amount' => SalonFinance::money($r->amount),
                'paid_on' => Carbon::parse($r->paid_on)->toDateString(),
                'period_month' => $r->period_month,
                'method' => $r->method,
                'note' => $r->note,
            ])
            ->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Post(path: '/inventory/salon/payouts', summary: 'Record a salary, commission or advance paid to someone', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function storePayout(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate([
            'staff_id' => 'required|string|max:64',
            'kind' => 'required|in:salary,commission,advance',
            'amount' => 'required|numeric|min:0.01|max:100000000',
            'paid_on' => 'nullable|date_format:Y-m-d',
            'period_month' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'],
            'method' => ['nullable', Rule::in(PaymentChannels::all())],
            'note' => 'nullable|string|max:160',
        ]);
        $member = $this->memberOrFail($request, $data['staff_id']);
        $paidOn = $data['paid_on'] ?? $this->today()->toDateString();

        $payoutRow = [
            'staff_id' => (string) $member->id,
            'staff_name' => $member->name,
            'kind' => $data['kind'],
            'amount' => $data['amount'],
            'paid_on' => $paidOn,
            // An advance counts against the month it was given in; the others against the month named (default: when paid).
            'period_month' => $data['kind'] === 'advance' ? substr($paidOn, 0, 7) : ($data['period_month'] ?? substr($paidOn, 0, 7)),
            'method' => $data['method'] ?? 'cash',
            'note' => !empty($data['note']) ? trim($data['note']) : null,
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ];
        $id = DB::table('inventory_staff_payouts')->insertGetId($payoutRow);

        // They are told what was paid to them (and for what), so pay is never a surprise or a secret.
        if ((string) $member->id !== (string) $request->user()->id) {
            $kinds = ['salary' => 'Mshahara / Salary', 'commission' => 'Kamisheni / Commission', 'advance' => 'Advance'];
            app(\App\Services\Inventory\InventoryNotifier::class)->notifyUser(
                (string) $member->id,
                'salon_payout',
                'Malipo yamerekodiwa / A payment was recorded',
                ($kinds[$data['kind']] ?? $data['kind']) . ': ' . number_format((float) $data['amount']) . ' TSh',
                ['payout_id' => (int) $id],
            );
        }

        return response()->json(['message' => 'Recorded', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Delete(path: '/inventory/salon/payouts/{id}', summary: 'Take back a payout recorded by mistake', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function destroyPayout(Request $request, int $id): JsonResponse
    {
        $this->requireManager($request);
        abort_if(DB::table('inventory_staff_payouts')->where('id', $id)->doesntExist(), 404, 'Not found');
        DB::table('inventory_staff_payouts')->where('id', $id)->delete();

        return response()->json(['message' => 'Deleted']);
    }

    /** Someone in this business (never a stranger's id). */
    private function memberOrFail(Request $request, string $staffId): User
    {
        $member = User::query()->whereIn('id', $request->user()->accountMemberIds())->where('id', $staffId)->first(['id', 'name']);
        if ($member === null) {
            throw ValidationException::withMessages(['staff_id' => ['That person is not in this business.']]);
        }

        return $member;
    }
}
