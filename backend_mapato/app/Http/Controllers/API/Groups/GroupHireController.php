<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupHires;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupMembers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use InvalidArgumentException;

/**
 * Hiring out, step by step: a member asks (or a leader or the keeper writes down someone outside the group) -> the keeper confirms they
 * are there (or declines) -> it is paid and verified by someone else -> handed over -> back, counted (late charge from the group's late
 * rate; damage and loss counted) -> the damage charge, if any, decided by whoever decides hire charges -> closed when every unit is back or
 * settled and every shilling paid. Nobody approves, hands over or charges their own hire.
 */
class GroupHireController extends Controller
{
    private const PAGE = 50;

    private function fail(string $code, string $message, int $status = 422): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => $message], $status);
    }

    private function myId(Request $request): ?int
    {
        $me = GroupAccess::member($request->user());

        return $me === null ? null : (int) $me['id'];
    }

    private function show(int $id, int $status = 200): JsonResponse
    {
        return response()->json(['success' => true, 'data' => ['hire' => GroupHires::payload(GroupHires::query()->where('h.id', $id)->first())]], $status);
    }

    /** The hire and its asset, if [request]'s user may handle it; else a refusal. @return array{0: ?object, 1: ?object, 2: ?JsonResponse} */
    private function handled(Request $request, int $id): array
    {
        $hire = DB::table('group_hires')->where('id', $id)->first();
        if ($hire === null) {
            return [null, null, $this->fail('not_found', 'Ukodishaji haupo. / Hire not found.', 404)];
        }
        $asset = DB::table('group_assets')->where('id', $hire->asset_id)->first();
        if (!GroupHires::canHandle($request->user(), $asset)) {
            return [null, null, $this->fail('group_right_missing', 'Ni mtunzaji wa mali hii au msimamizi wa mali tu. / Only the keeper of this asset or whoever manages assets.', 403)];
        }
        if ($hire->member_id !== null && (int) $hire->member_id === $this->myId($request)) {
            return [null, null, $this->fail('own_hire', 'Huwezi kushughulikia ukodishaji wako mwenyewe. / You cannot handle your own hire.', 403)];
        }

        return [$hire, $asset, null];
    }

    // ---------------------------------------------------------------- asking

    /** @return array<string, mixed> */
    private static function askRules(): array
    {
        return [
            'asset_id' => 'required|integer',
            'quantity' => 'required|integer|min:1|max:100000',
            'start_date' => 'required|date|after_or_equal:today',
            'end_date' => 'required|date|after_or_equal:start_date',
            'purpose' => 'nullable|string|max:255',
        ];
    }

    private function ask(Request $request, array $data, ?int $memberId, ?string $name, ?string $phone): JsonResponse
    {
        $asset = DB::table('group_assets')->where('id', (int) $data['asset_id'])->where('status', 'active')->first();
        if ($asset === null || $asset->hire_rate === null) {
            return $this->fail('not_for_hire', 'Mali hii haikodishwi. / This asset is not for hire.');
        }
        $free = GroupHires::available($asset, $data['start_date'], $data['end_date']);
        if ((int) $data['quantity'] > $free) {
            return response()->json(['success' => false, 'code' => 'not_enough', 'message' => "Zipo {$free} tu kwa siku hizo. / Only {$free} are free on those days.", 'free' => $free], 422);
        }
        $days = GroupHires::days($data['start_date'], $data['end_date']);
        $id = (int) DB::table('group_hires')->insertGetId([
            'reference' => GroupHires::newReference(),
            'asset_id' => (int) $asset->id,
            'member_id' => $memberId,
            'customer_name' => $name,
            'customer_phone' => $phone,
            'purpose' => $data['purpose'] ?? null,
            'quantity' => (int) $data['quantity'],
            'start_date' => $data['start_date'],
            'end_date' => $data['end_date'],
            'days' => $days,
            'rate' => (float) $asset->hire_rate,
            'amount' => round((int) $data['quantity'] * (float) $asset->hire_rate * $days, 2),
            'status' => 'requested',
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'hire_requested', $data['quantity'] . ' x ' . $asset->name . ' ' . $data['start_date'] . '..' . $data['end_date'], 'hire', $id);

        return $this->show($id, 201);
    }

    public function askMine(Request $request): JsonResponse
    {
        $me = GroupAccess::member($request->user());
        if ($me === null || $me['status'] !== GroupMembers::ACTIVE) {
            return $this->fail('member_not_open', 'Ni mwanachama hai tu. / Active members only.');
        }

        return $this->ask($request, $request->validate(self::askRules()), (int) $me['id'], null, null);
    }

    /** A leader (or the keeper) writes down a hire for a member or for someone outside the group. */
    public function askFor(Request $request): JsonResponse
    {
        $data = $request->validate(self::askRules() + [
            'member_id' => 'nullable|integer',
            'customer_name' => 'nullable|string|min:2|max:150|required_without:member_id',
            'customer_phone' => ['nullable', 'string', 'regex:/^(0\d{9}|\+\d{9,15})$/', 'required_without:member_id'],
        ]);
        $asset = DB::table('group_assets')->where('id', (int) $data['asset_id'])->first();
        if ($asset === null || !GroupHires::canHandle($request->user(), $asset)) {
            return $this->fail('group_right_missing', 'Ni mtunzaji wa mali hii au msimamizi wa mali tu. / Only the keeper of this asset or whoever manages assets.', 403);
        }
        if (!empty($data['member_id']) && !DB::table('group_members')->where('id', (int) $data['member_id'])->where('status', GroupMembers::ACTIVE)->exists()) {
            return $this->fail('member_not_open', 'Mwanachama si hai. / The member is not active.');
        }

        return $this->ask($request, $data, empty($data['member_id']) ? null : (int) $data['member_id'], $data['customer_name'] ?? null, $data['customer_phone'] ?? null);
    }

    public function mine(Request $request): JsonResponse
    {
        $id = $this->myId($request);
        $rows = $id === null ? collect() : GroupHires::query()->where('h.member_id', $id)->orderByDesc('h.id')->limit(100)->get();

        return response()->json(['success' => true, 'data' => ['hires' => $rows->map(fn ($h) => GroupHires::payload($h))->values()]]);
    }

    public function cancelMine(Request $request, int $id): JsonResponse
    {
        $hire = DB::table('group_hires')->where('id', $id)->first();
        if ($hire === null || (int) $hire->member_id !== $this->myId($request)) {
            return $this->fail('not_yours', 'Huu si wako. / This is not yours.', 403);
        }
        if (!in_array($hire->status, ['requested', 'approved'], true) || GroupHires::paid($id) > 0) {
            return $this->fail('wrong_status', 'Haiwezi kuondolewa sasa. / It cannot be withdrawn now.', 409);
        }
        DB::table('group_hires')->where('id', $id)->update(['status' => 'cancelled', 'updated_at' => now()]);

        return $this->show($id);
    }

    // ---------------------------------------------------------------- the keeper and the leaders

    /** Hires the person may handle: everything for whoever manages assets, the hires of their assets for a keeper. */
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'status' => ['nullable', Rule::in(['requested', 'approved', 'issued', 'returned', 'closed', 'declined', 'cancelled', 'open'])],
            'page' => 'nullable|integer|min:1',
        ]);
        $user = $request->user();
        $manager = GroupAccess::can($user, 'manage_assets') || GroupAccess::can($user, 'view_finance');
        $me = $this->myId($request);
        if (!$manager && ($me === null || !DB::table('group_assets')->where('custodian_id', $me)->exists())) {
            return $this->fail('group_right_missing', 'Huna ruhusa. / Not allowed.', 403);
        }
        $q = GroupHires::query()
            ->when(!$manager, fn ($w) => $w->where('a.custodian_id', $me))
            ->when(($data['status'] ?? null) === 'open', fn ($w) => $w->whereIn('h.status', ['requested', 'approved', 'issued', 'returned']))
            ->when(($data['status'] ?? null) !== null && ($data['status'] ?? null) !== 'open', fn ($w) => $w->where('h.status', $data['status']));
        $total = (clone $q)->count();
        $page = (int) ($data['page'] ?? 1);

        return response()->json([
            'success' => true,
            'data' => ['hires' => $q->orderBy('h.start_date')->orderBy('h.id')->forPage($page, self::PAGE)->get()->map(fn ($h) => GroupHires::payload($h))->values()],
            'meta' => ['pagination' => ['page' => $page, 'per_page' => self::PAGE, 'total' => $total, 'has_more' => $page * self::PAGE < $total]],
        ]);
    }

    /** The keeper confirms they are there (checked again: another hire may have taken them since), or declines with a note. */
    public function decide(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['approve' => 'required|boolean', 'note' => 'nullable|string|max:255|required_if:approve,false']);
        [$hire, $asset, $refused] = $this->handled($request, $id);
        if ($refused) {
            return $refused;
        }
        if ($hire->status !== 'requested') {
            return $this->fail('wrong_status', 'Hatua hii haiwezekani sasa. / Not possible at this stage.', 409);
        }
        if ($data['approve'] && GroupHires::available($asset, (string) $hire->start_date, (string) $hire->end_date, $id) < (int) $hire->quantity) {
            return $this->fail('not_enough', 'Hazitoshi tena kwa siku hizo. / Not enough are free on those days any more.');
        }
        DB::table('group_hires')->where('id', $id)->update([
            'status' => $data['approve'] ? 'approved' : 'declined', 'decision_note' => $data['note'] ?? null,
            'decided_by' => (string) $request->user()->id, 'decided_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, $data['approve'] ? 'hire_approved' : 'hire_declined', $hire->reference . (($data['note'] ?? '') !== '' ? ': ' . $data['note'] : ''), 'hire', $id);

        return $this->show($id);
    }

    /** Hand them over: only once the charge is paid and verified. */
    public function issue(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['quantity' => 'required|integer|min:1', 'condition' => 'nullable|string|max:255']);
        [$hire, , $refused] = $this->handled($request, $id);
        if ($refused) {
            return $refused;
        }
        if ($hire->status !== 'approved') {
            return $this->fail('wrong_status', 'Hatua hii haiwezekani sasa. / Not possible at this stage.', 409);
        }
        if (GroupHires::paid($id) + 0.001 < (float) $hire->amount) {
            return $this->fail('not_paid', 'Malipo bado hayajathibitishwa. / The payment is not verified yet.', 409);
        }
        if ((int) $data['quantity'] > (int) $hire->quantity) {
            return $this->fail('too_many', 'Ni zaidi ya zilizokodishwa. / More than were hired.');
        }
        DB::table('group_hires')->where('id', $id)->update([
            'status' => 'issued', 'issued_quantity' => (int) $data['quantity'], 'issued_condition' => $data['condition'] ?? null, 'issued_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'hire_issued', $hire->reference . ': ' . $data['quantity'] . ' handed over', 'hire', $id);

        return $this->show($id);
    }

    /** Back: how many came back, damaged and missing. A late charge follows the asset's late rate; damaged and missing leave the usable count. */
    public function return(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'returned' => 'required|integer|min:0',
            'damaged' => 'nullable|integer|min:0',
            'missing' => 'nullable|integer|min:0',
            'note' => 'nullable|string|max:255',
            'returned_on' => 'nullable|date|before_or_equal:today',
        ]);
        [$hire, $asset, $refused] = $this->handled($request, $id);
        if ($refused) {
            return $refused;
        }
        if ($hire->status !== 'issued') {
            return $this->fail('wrong_status', 'Hatua hii haiwezekani sasa. / Not possible at this stage.', 409);
        }
        $damaged = (int) ($data['damaged'] ?? 0);
        $missing = (int) ($data['missing'] ?? 0);
        if ((int) $data['returned'] + $missing !== (int) $hire->issued_quantity || $damaged > (int) $data['returned']) {
            return $this->fail('counts_do_not_add_up', 'Zilizorudi na zilizopotea lazima zilingane na zilizotolewa. / Returned plus missing must equal what was handed over.');
        }
        $on = $data['returned_on'] ?? now()->toDateString();
        $late = GroupHires::lateCharge($hire, $asset, $on);
        $by = (string) $request->user()->id;
        DB::transaction(function () use ($hire, $asset, $data, $damaged, $missing, $on, $late, $by, $id) {
            DB::table('group_hires')->where('id', $id)->update([
                'status' => 'returned', 'returned_quantity' => (int) $data['returned'], 'damaged_quantity' => $damaged, 'missing_quantity' => $missing,
                'return_note' => $data['note'] ?? null, 'returned_on' => $on, 'late_charge' => $late,
                'damage_status' => $damaged + $missing > 0 ? 'pending' : null, 'updated_at' => now(),
            ]);
            if ($damaged + $missing > 0) {
                DB::table('group_assets')->where('id', $asset->id)->update(['quantity' => max(0, (int) $asset->quantity - $damaged - $missing), 'updated_at' => now()]);
                if ($damaged > 0) {
                    GroupHires::event((int) $asset->id, 'damage', -$damaged, 'came back damaged: ' . $hire->reference, $by, null, $id);
                }
                if ($missing > 0) {
                    GroupHires::event((int) $asset->id, 'loss', -$missing, 'did not come back: ' . $hire->reference, $by, null, $id);
                }
            }
        });
        GroupAudit::record($by, 'hire_returned', $hire->reference . ": {$data['returned']} back, {$damaged} damaged, {$missing} missing" . ($late > 0 ? ', late charge ' . number_format($late) : ''), 'hire', $id);

        return $this->show($id);
    }

    /** The damage or loss charge, decided case by case (0 is a decision too), with the reason. */
    public function charge(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['amount' => 'required|numeric|min:0|max:100000000', 'note' => 'required|string|min:3|max:255']);
        $hire = DB::table('group_hires')->where('id', $id)->first();
        if ($hire === null) {
            return $this->fail('not_found', 'Ukodishaji haupo. / Hire not found.', 404);
        }
        if ($hire->member_id !== null && (int) $hire->member_id === $this->myId($request)) {
            return $this->fail('own_hire', 'Huwezi kuamua ukodishaji wako mwenyewe. / You cannot decide your own hire.', 403);
        }
        if ($hire->status !== 'returned' || $hire->damage_status !== 'pending') {
            return $this->fail('wrong_status', 'Hakuna gharama ya kuamua. / There is no charge to decide.', 409);
        }
        DB::table('group_hires')->where('id', $id)->update([
            'damage_charge' => round((float) $data['amount'], 2), 'damage_note' => trim($data['note']), 'damage_status' => 'decided', 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'hire_charged', $hire->reference . ': ' . number_format((float) $data['amount']) . ' (' . trim($data['note']) . ')', 'hire', $id);

        return $this->show($id);
    }

    /** A payment for a hire, recorded by the keeper or a leader (the hirer may be outside the group). It waits for verification. */
    public function pay(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'amount' => 'required|numeric|min:1|max:1000000000',
            'method' => ['required', Rule::in(GroupLedger::METHODS)],
            'external_ref' => 'nullable|string|max:80',
        ]);
        $hire = DB::table('group_hires')->where('id', $id)->first();
        $asset = $hire === null ? null : DB::table('group_assets')->where('id', $hire->asset_id)->first();
        if ($hire === null || (!GroupHires::canHandle($request->user(), $asset) && !GroupAccess::can($request->user(), 'record_payments'))) {
            return $this->fail('group_right_missing', 'Huna ruhusa. / Not allowed.', 403);
        }
        try {
            GroupLedger::submit([
                'member_id' => $hire->member_id === null ? null : (int) $hire->member_id, 'hire_id' => $id, 'category' => 'hire',
                'amount' => (float) $data['amount'], 'method' => $data['method'], 'external_ref' => $data['external_ref'] ?? null, 'note' => $hire->reference,
            ], (string) $request->user()->id);
        } catch (InvalidArgumentException $e) {
            return $this->fail($e->getMessage(), GroupTransactionController::word($e->getMessage()));
        }

        return $this->show($id);
    }

    /** Closed: back (or settled) and paid in full. */
    public function close(Request $request, int $id): JsonResponse
    {
        [$hire, , $refused] = $this->handled($request, $id);
        if ($refused) {
            return $refused;
        }
        if ($hire->status !== 'returned' || $hire->damage_status === 'pending' || GroupHires::paid($id) + 0.001 < GroupHires::total($hire)) {
            return $this->fail('not_settled', 'Bado kuna kinachodaiwa au gharama ya uharibifu haijaamuliwa. / Money is still owed, or a damage charge is not decided.', 409);
        }
        DB::table('group_hires')->where('id', $id)->update(['status' => 'closed', 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'hire_closed', $hire->reference, 'hire', $id);

        return $this->show($id);
    }
}
