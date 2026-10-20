<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\User;
use App\Services\Inventory\InventoryNotifier;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\SalonAccess;
use App\Support\Salon\SalonFinance;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * The salon's people at work: days off, who came in and for how long, and each shift's cash (what the till should
 * hold against what was handed over, with an alert to the owner when they differ). A person sees only their own
 * attendance and shifts; the owner and managers see everyone's.
 *
 * Staff revenue, commission and the cash handed over are three different figures. This is the third.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Salon attendance, days off and shift cash')]
class SalonStaffController extends Controller
{
    private function manager(Request $request): bool
    {
        return SalonAccess::isManager($request->user());
    }

    private function requireManager(Request $request): void
    {
        abort_unless($this->manager($request), 403, 'Ni mmiliki au meneja tu anayeweza kufanya hivi. / Only the owner or a manager can do this.');
    }

    /** Someone in this business (never a stranger's id). */
    private function member(Request $request, string $staffId): User
    {
        $member = User::query()->whereIn('id', $request->user()->accountMemberIds())->where('id', $staffId)->first(['id', 'name', 'role']);
        if ($member === null) {
            throw ValidationException::withMessages(['staff_id' => ['That person is not in this business.']]);
        }

        return $member;
    }

    /** Whose record this is: themselves, or (for the owner and managers) someone they name. */
    private function subject(Request $request): User
    {
        $asked = $request->input('staff_id');
        if ($asked !== null && $asked !== '' && (string) $asked !== (string) $request->user()->id) {
            $this->requireManager($request);

            return $this->member($request, (string) $asked);
        }

        return $request->user();
    }

    private function salonNow(): Carbon
    {
        return Carbon::now(AppointmentPlanner::TIMEZONE);
    }

    // ------------------------------------------------------------------ days off

    #[OA\Get(path: '/inventory/salon/days-off', summary: 'Days off for a month', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function daysOff(Request $request): JsonResponse
    {
        $data = $request->validate(['month' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/']]);
        $month = $data['month'] ?? $this->salonNow()->format('Y-m');
        $from = Carbon::createFromFormat('Y-m-d', $month . '-01')->startOfMonth();

        $rows = DB::table('inventory_staff_days_off as d')
            ->leftJoin('users as u', 'u.id', '=', 'd.staff_id')
            ->whereBetween('d.off_on', [$from->toDateString(), $from->copy()->endOfMonth()->toDateString()])
            ->when(!$this->manager($request), fn ($q) => $q->where('d.staff_id', (string) $request->user()->id))
            ->orderBy('d.off_on')
            ->get(['d.id', 'd.staff_id', 'u.name as staff_name', 'd.off_on', 'd.reason'])
            ->map(fn ($r) => ['id' => (int) $r->id, 'staff_id' => $r->staff_id, 'staff_name' => $r->staff_name, 'off_on' => Carbon::parse($r->off_on)->toDateString(), 'reason' => $r->reason])
            ->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Post(path: '/inventory/salon/days-off', summary: 'Give someone a day off', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function storeDayOff(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate(['staff_id' => 'required|string|max:64', 'off_on' => 'required|date_format:Y-m-d', 'reason' => 'nullable|string|max:120']);
        $member = $this->member($request, $data['staff_id']);

        if (DB::table('inventory_staff_days_off')->where('staff_id', (string) $member->id)->where('off_on', $data['off_on'])->exists()) {
            throw ValidationException::withMessages(['off_on' => ["{$member->name} ana mapumziko siku hiyo tayari. / {$member->name} already has that day off."]]);
        }
        $id = DB::table('inventory_staff_days_off')->insertGetId([
            'staff_id' => (string) $member->id,
            'off_on' => $data['off_on'],
            'reason' => !empty($data['reason']) ? trim($data['reason']) : null,
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Saved', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Delete(path: '/inventory/salon/days-off/{id}', summary: 'Take a day off back', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function destroyDayOff(Request $request, int $id): JsonResponse
    {
        $this->requireManager($request);
        abort_if(DB::table('inventory_staff_days_off')->where('id', $id)->doesntExist(), 404, 'Not found');
        DB::table('inventory_staff_days_off')->where('id', $id)->delete();

        return response()->json(['message' => 'Deleted']);
    }

    // ------------------------------------------------------------------ attendance

    #[OA\Post(path: '/inventory/salon/attendance/clock-in', summary: 'Start work', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function clockIn(Request $request): JsonResponse
    {
        $request->validate(['staff_id' => 'nullable|string|max:64', 'note' => 'nullable|string|max:160']);
        $who = $this->subject($request);

        $open = DB::table('inventory_attendance')->where('staff_id', (string) $who->id)->whereNull('clock_out')->first();
        if ($open !== null) {
            $since = Carbon::parse($open->clock_in)->format('H:i');
            throw ValidationException::withMessages(['staff_id' => ["Tayari umeanza kazi saa {$since}. / Already at work since {$since}."]]);
        }

        $now = $this->salonNow();
        $id = DB::table('inventory_attendance')->insertGetId((\Illuminate\Support\Facades\Schema::hasColumn('inventory_attendance', 'branch_id') ? ['branch_id' => \App\Support\Salon\SalonBranch::forNew($request)] : []) + [
            'staff_id' => (string) $who->id,
            'staff_name' => $who->name,
            'work_date' => $now->toDateString(),
            'clock_in' => $now->format('Y-m-d H:i:s'),
            'note' => $request->input('note') ? trim((string) $request->input('note')) : null,
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Clocked in', 'data' => $this->presentAttendance(DB::table('inventory_attendance')->find($id))], 201);
    }

    #[OA\Post(path: '/inventory/salon/attendance/clock-out', summary: 'Finish work', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function clockOut(Request $request): JsonResponse
    {
        $request->validate(['staff_id' => 'nullable|string|max:64']);
        $who = $this->subject($request);

        $open = DB::table('inventory_attendance')->where('staff_id', (string) $who->id)->whereNull('clock_out')->orderByDesc('id')->first();
        if ($open === null) {
            throw ValidationException::withMessages(['staff_id' => ['Hujaanza kazi bado. / Not clocked in.']]);
        }
        DB::table('inventory_attendance')->where('id', $open->id)->update(['clock_out' => $this->salonNow()->format('Y-m-d H:i:s'), 'updated_at' => now()]);

        return response()->json(['message' => 'Clocked out', 'data' => $this->presentAttendance(DB::table('inventory_attendance')->find($open->id))]);
    }

    #[OA\Get(path: '/inventory/salon/attendance', summary: 'Who worked when, with hours, for a month', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function attendance(Request $request): JsonResponse
    {
        $data = $request->validate(['month' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'], 'staff_id' => 'nullable|string|max:64']);
        $month = $data['month'] ?? $this->salonNow()->format('Y-m');
        $from = Carbon::createFromFormat('Y-m-d', $month . '-01')->startOfMonth();
        $manager = $this->manager($request);

        $rows = DB::table('inventory_attendance')
            ->whereBetween('work_date', [$from->toDateString(), $from->copy()->endOfMonth()->toDateString()])
            ->when(!$manager, fn ($q) => $q->where('staff_id', (string) $request->user()->id))
            ->when($manager && !empty($data['staff_id']), fn ($q) => $q->where('staff_id', $data['staff_id']))
            ->when(\App\Support\Salon\SalonBranch::selected($request) !== null, fn ($q) => $q->where('branch_id', \App\Support\Salon\SalonBranch::selected($request)))
            ->orderBy('clock_in')
            ->get();

        $people = $rows->groupBy('staff_id')->map(function ($list, $staffId) {
            $minutes = $list->sum(fn ($r) => $r->clock_out ? Carbon::parse($r->clock_in)->diffInMinutes(Carbon::parse($r->clock_out)) : 0);

            return [
                'staff_id' => (string) $staffId,
                'name' => $list->first()->staff_name,
                'days' => $list->pluck('work_date')->map(fn ($d) => Carbon::parse($d)->toDateString())->unique()->count(),
                'hours' => round($minutes / 60, 2),
                'at_work' => $list->contains(fn ($r) => $r->clock_out === null),
                'records' => $list->map(fn ($r) => $this->presentAttendance($r))->values(),
            ];
        })->sortBy('name')->values();

        return response()->json(['data' => ['month' => $month, 'staff' => $people]]);
    }

    #[OA\Get(path: '/inventory/salon/attendance/today', summary: 'Am I at work now?', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function attendanceToday(Request $request): JsonResponse
    {
        $open = DB::table('inventory_attendance')->where('staff_id', (string) $request->user()->id)->whereNull('clock_out')->orderByDesc('id')->first();

        return response()->json(['data' => ['at_work' => $open !== null, 'since' => $open ? Carbon::parse($open->clock_in)->format('Y-m-d H:i') : null]]);
    }

    /** @return array<string, mixed> */
    private function presentAttendance(object $r): array
    {
        return [
            'id' => (int) $r->id,
            'staff_id' => $r->staff_id,
            'name' => $r->staff_name,
            'date' => Carbon::parse($r->work_date)->toDateString(),
            'clock_in' => Carbon::parse($r->clock_in)->format('Y-m-d H:i'),
            'clock_out' => $r->clock_out ? Carbon::parse($r->clock_out)->format('Y-m-d H:i') : null,
            'hours' => $r->clock_out ? round(Carbon::parse($r->clock_in)->diffInMinutes(Carbon::parse($r->clock_out)) / 60, 2) : null,
        ];
    }

    // ------------------------------------------------------------------ shifts and cash

    #[OA\Get(path: '/inventory/salon/shifts/current', summary: 'My open shift, with what I have taken so far', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function currentShift(Request $request): JsonResponse
    {
        $shift = DB::table('inventory_salon_shifts')->where('staff_id', (string) $request->user()->id)->where('status', 'open')->orderByDesc('id')->first();

        return response()->json(['data' => $shift ? $this->presentShift($shift, true) : null]);
    }

    #[OA\Post(path: '/inventory/salon/shifts/open', summary: 'Open a shift with the cash in the till', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function openShift(Request $request): JsonResponse
    {
        $data = $request->validate(['opening_float' => 'nullable|numeric|min:0|max:100000000']);
        $who = $request->user();

        if (DB::table('inventory_salon_shifts')->where('staff_id', (string) $who->id)->where('status', 'open')->exists()) {
            throw ValidationException::withMessages(['shift' => ['Una zamu iliyo wazi tayari: ifunge kwanza. / You already have an open shift: close it first.']]);
        }
        $id = DB::table('inventory_salon_shifts')->insertGetId((\Illuminate\Support\Facades\Schema::hasColumn('inventory_salon_shifts', 'branch_id') ? ['branch_id' => \App\Support\Salon\SalonBranch::forNew($request)] : []) + [
            'staff_id' => (string) $who->id,
            'staff_name' => $who->name,
            'opened_at' => now(),
            'opening_float' => (float) ($data['opening_float'] ?? 0),
            'status' => 'open',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Shift opened', 'data' => $this->presentShift(DB::table('inventory_salon_shifts')->find($id), true)], 201);
    }

    #[OA\Post(path: '/inventory/salon/shifts/{id}/close', summary: 'Close a shift: count the cash and hand it over', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function closeShift(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'counted_cash' => 'required|numeric|min:0|max:1000000000',
            'handed_to_id' => 'nullable|string|max:64',
            'note' => 'nullable|string|max:160',
        ]);
        $shift = DB::table('inventory_salon_shifts')->find($id);
        abort_if($shift === null, 404, 'Shift not found');
        abort_if(!$this->manager($request) && (string) $shift->staff_id !== (string) $request->user()->id, 403, 'Hii si zamu yako. / This is not your shift.');
        if ($shift->status !== 'open') {
            throw ValidationException::withMessages(['shift' => ['Zamu hii imefungwa tayari. / This shift is already closed.']]);
        }

        $receiver = !empty($data['handed_to_id']) ? $this->member($request, $data['handed_to_id']) : null;
        $collected = $this->collectedSince($shift);
        $expected = (float) $shift->opening_float + (float) ($collected['cash'] ?? 0);
        $counted = (float) $data['counted_cash'];
        $difference = round($counted - $expected, 2);

        DB::table('inventory_salon_shifts')->where('id', $id)->update([
            'closed_at' => now(),
            'counted_cash' => $counted,
            'expected_cash' => $expected,
            'difference' => $difference,
            'collected' => json_encode($collected),
            'handed_to_id' => $receiver ? (string) $receiver->id : null,
            'handed_to_name' => $receiver?->name,
            'note' => !empty($data['note']) ? trim($data['note']) : null,
            'status' => 'closed',
            'updated_at' => now(),
        ]);

        if (abs($difference) >= 0.01) {
            $short = $difference < 0;
            $amount = number_format(abs($difference));
            app(InventoryNotifier::class)->notifyByPermission(
                ['inv_view_reports'],
                'salon_cash_discrepancy',
                $short ? 'Pesa pungufu kwenye zamu / Cash short on a shift' : 'Pesa zaidi kwenye zamu / Cash over on a shift',
                "{$shift->staff_name}: " . ($short ? "pungufu / short {$amount}" : "zaidi / over {$amount}") . ' (TSh)',
                ['shift_id' => $id, 'staff_id' => $shift->staff_id, 'difference' => $difference],
                excludeUserId: (string) $request->user()->id,
            );
        }

        return response()->json(['message' => 'Shift closed', 'data' => $this->presentShift(DB::table('inventory_salon_shifts')->find($id))]);
    }

    #[OA\Get(path: '/inventory/salon/shifts', summary: 'Shifts for a month, with what was handed over and any difference', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function shifts(Request $request): JsonResponse
    {
        $data = $request->validate(['month' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'], 'staff_id' => 'nullable|string|max:64']);
        $month = $data['month'] ?? $this->salonNow()->format('Y-m');
        $from = Carbon::createFromFormat('Y-m-d', $month . '-01')->startOfMonth();
        $manager = $this->manager($request);

        $rows = DB::table('inventory_salon_shifts')
            ->whereBetween('opened_at', [$from->format('Y-m-d H:i:s'), $from->copy()->endOfMonth()->format('Y-m-d H:i:s')])
            ->when(!$manager, fn ($q) => $q->where('staff_id', (string) $request->user()->id))
            ->when($manager && !empty($data['staff_id']), fn ($q) => $q->where('staff_id', $data['staff_id']))
            ->when(\App\Support\Salon\SalonBranch::selected($request) !== null, fn ($q) => $q->where('branch_id', \App\Support\Salon\SalonBranch::selected($request)))
            ->orderByDesc('opened_at')
            ->get()
            ->map(fn ($s) => $this->presentShift($s, $s->status === 'open'))
            ->values();

        return response()->json(['data' => [
            'month' => $month,
            'shifts' => $rows,
            'totals' => [
                'shifts' => $rows->count(),
                'with_difference' => $rows->filter(fn ($s) => abs((float) ($s['difference'] ?? 0)) >= 0.01)->count(),
                'difference' => SalonFinance::money($rows->sum(fn ($s) => (float) ($s['difference'] ?? 0))),
            ],
        ]]);
    }

    /**
     * What this person took since the shift opened, by how it was paid: money from sales they rang up. (Cash is what
     * the till should hold; mobile money and bank went elsewhere and are shown so the owner can match them.)
     *
     * @return array{cash: int|float, mobile_money: int|float, bank_transfer: int|float}
     */
    private function collectedSince(object $shift): array
    {
        $to = $shift->closed_at ?? now();
        $rows = DB::table('inventory_sale_payments as p')
            ->join('inventory_sales as s', 's.id', '=', 'p.sale_id')
            ->whereNull('s.cancelled_at')
            ->where('s.created_by', $shift->staff_id)
            ->where('p.paid_at', '>=', $shift->opened_at)
            ->where('p.paid_at', '<=', $to)
            ->groupBy('p.method')
            ->selectRaw('p.method as method, COALESCE(SUM(p.amount), 0) as amount')
            ->pluck('amount', 'method');

        return [
            'cash' => SalonFinance::money($rows['cash'] ?? 0),
            'mobile_money' => SalonFinance::money($rows['mobile_money'] ?? 0),
            'bank_transfer' => SalonFinance::money($rows['bank_transfer'] ?? 0),
        ];
    }

    /** @return array<string, mixed> */
    private function presentShift(object $s, bool $live = false): array
    {
        $collected = $live && $s->status === 'open' ? $this->collectedSince($s) : (json_decode((string) ($s->collected ?? ''), true) ?: null);

        return [
            'id' => (int) $s->id,
            'staff_id' => $s->staff_id,
            'staff_name' => $s->staff_name,
            'status' => $s->status,
            'opened_at' => Carbon::parse($s->opened_at)->format('Y-m-d H:i'),
            'closed_at' => $s->closed_at ? Carbon::parse($s->closed_at)->format('Y-m-d H:i') : null,
            'opening_float' => SalonFinance::money($s->opening_float),
            'collected' => $collected,
            'expected_cash' => $s->status === 'open' ? SalonFinance::money((float) $s->opening_float + (float) ($collected['cash'] ?? 0)) : SalonFinance::money($s->expected_cash),
            'counted_cash' => $s->counted_cash === null ? null : SalonFinance::money($s->counted_cash),
            'difference' => $s->difference === null ? null : SalonFinance::money($s->difference),
            'handed_to_name' => $s->handed_to_name,
            'note' => $s->note,
        ];
    }
}
