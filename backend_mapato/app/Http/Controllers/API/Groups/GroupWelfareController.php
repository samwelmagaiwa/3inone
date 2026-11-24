<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupMembers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use InvalidArgumentException;

/**
 * Welfare (msaada): a member asks for help (a bereavement, an illness, a celebration); the chair approves the entitlement and its amount
 * or turns it down; the treasurer pays it; someone else verifies the payment, and only then is it PAID. The chair approves, the treasurer
 * pays: never the same step by one person, never one's own request. The description (it may be medical or private) is shown only to the
 * member and to whoever decides or pays.
 */
class GroupWelfareController extends Controller
{
    private const PAGE = 50;

    public const RELATIONSHIPS = ['self', 'parent', 'spouse', 'child', 'parent_in_law', 'other'];

    private function fail(string $code, string $message, int $status = 422): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => $message], $status);
    }

    private function myId(Request $request): ?int
    {
        $me = GroupAccess::member($request->user());

        return $me === null ? null : (int) $me['id'];
    }

    /** submitted | approved | paying (payout waiting) | paid | rejected | cancelled */
    private static function state(object $r): string
    {
        if ($r->status !== 'approved') {
            return $r->status;
        }
        $payout = DB::table('group_transactions')->where('benefit_id', $r->id)->where('category', 'welfare')->whereIn('status', [GroupLedger::PENDING, GroupLedger::VERIFIED])
            ->whereNull('reversed_by_id')->orderByDesc('id')->value('status');

        return match ($payout) {
            GroupLedger::VERIFIED => 'paid',
            GroupLedger::PENDING => 'paying',
            default => 'approved',
        };
    }

    /** @return array<string, mixed> */
    private static function payload(object $r, bool $private): array
    {
        return [
            'id' => (int) $r->id,
            'reference' => $r->reference,
            'member_id' => (int) $r->member_id,
            'member_name' => $r->member_name ?? null,
            'type_id' => (int) $r->benefit_type_id,
            'type_name' => $r->type_name ?? null,
            'beneficiary' => $r->beneficiary,
            'relationship' => $r->relationship,
            'event_date' => (string) $r->event_date,
            'description' => $private ? $r->description : null,
            'amount_requested' => $r->amount_requested === null ? null : (float) $r->amount_requested,
            'amount_approved' => $r->amount_approved === null ? null : (float) $r->amount_approved,
            'state' => self::state($r),
            'decision_note' => $r->decision_note,
            'created_at' => (string) $r->created_at,
        ];
    }

    private static function query(): \Illuminate\Database\Query\Builder
    {
        return DB::table('group_benefit_requests as r')->join('group_members as m', 'm.id', '=', 'r.member_id')
            ->join('group_benefit_types as t', 't.id', '=', 'r.benefit_type_id')
            ->select('r.*', 'm.full_name as member_name', 't.name as type_name');
    }

    // ---------------------------------------------------------------- kinds of help

    public function types(): JsonResponse
    {
        return response()->json(['success' => true, 'data' => ['types' => DB::table('group_benefit_types')->orderByDesc('active')->orderBy('name')->get()
            ->map(fn ($t) => ['id' => (int) $t->id, 'name' => $t->name, 'description' => $t->description, 'amount' => $t->amount === null ? null : (float) $t->amount, 'active' => (bool) $t->active])
            ->values()]]);
    }

    public function saveType(Request $request, ?int $id = null): JsonResponse
    {
        $data = $request->validate([
            'name' => 'required|string|min:2|max:100',
            'description' => 'nullable|string|max:255',
            'amount' => 'nullable|numeric|min:0|max:1000000000',
            'active' => 'nullable|boolean',
        ]);
        $row = ['name' => trim($data['name']), 'description' => $data['description'] ?? null, 'amount' => $data['amount'] ?? null, 'active' => (bool) ($data['active'] ?? true), 'updated_at' => now()];
        if ($id === null) {
            $id = (int) DB::table('group_benefit_types')->insertGetId($row + ['created_at' => now()]);
        } elseif (!DB::table('group_benefit_types')->where('id', $id)->exists()) {
            return $this->fail('not_found', 'Aina ya msaada haipo. / Not found.', 404);
        } else {
            DB::table('group_benefit_types')->where('id', $id)->update($row);
        }
        GroupAudit::record((string) $request->user()->id, 'benefit_type_saved', $row['name'], 'benefit_type', $id);

        return $this->types();
    }

    // ---------------------------------------------------------------- the member

    public function mine(Request $request): JsonResponse
    {
        $id = $this->myId($request);
        $rows = $id === null ? collect() : self::query()->where('r.member_id', $id)->orderByDesc('r.id')->limit(100)->get();

        return response()->json(['success' => true, 'data' => ['requests' => $rows->map(fn ($r) => self::payload($r, true))->values()]]);
    }

    public function apply(Request $request): JsonResponse
    {
        $data = $request->validate([
            'type_id' => 'required|integer',
            'beneficiary' => 'required|string|min:2|max:150',
            'relationship' => ['required', Rule::in(self::RELATIONSHIPS)],
            'event_date' => 'required|date|before_or_equal:' . now()->addDays(60)->toDateString(),
            'description' => 'nullable|string|max:2000',
            'amount' => 'nullable|numeric|min:0|max:1000000000',
        ]);
        $member = GroupAccess::member($request->user());
        if ($member === null || $member['status'] !== GroupMembers::ACTIVE) {
            return $this->fail('member_not_open', 'Ni mwanachama hai tu anayeomba msaada. / Only an active member can ask for help.');
        }
        if (!DB::table('group_benefit_types')->where('id', (int) $data['type_id'])->where('active', true)->exists()) {
            return $this->fail('type_required', 'Chagua aina ya msaada. / Choose the kind of help.');
        }
        do {
            $ref = 'MS-' . strtoupper(Str::random(6));
        } while (DB::table('group_benefit_requests')->where('reference', $ref)->exists());
        $id = (int) DB::table('group_benefit_requests')->insertGetId([
            'reference' => $ref,
            'member_id' => (int) $member['id'],
            'benefit_type_id' => (int) $data['type_id'],
            'beneficiary' => trim($data['beneficiary']),
            'relationship' => $data['relationship'],
            'event_date' => $data['event_date'],
            'description' => $data['description'] ?? null,
            'amount_requested' => $data['amount'] ?? null,
            'status' => 'submitted',
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'benefit_requested', 'Welfare request ' . $ref, 'benefit', $id);

        return response()->json(['success' => true, 'data' => ['request' => self::payload(self::query()->where('r.id', $id)->first(), true)]], 201);
    }

    public function cancel(Request $request, int $id): JsonResponse
    {
        $r = DB::table('group_benefit_requests')->where('id', $id)->first();
        if ($r === null || (int) $r->member_id !== $this->myId($request)) {
            return $this->fail('not_yours', 'Huu si ombi lako. / This is not yours.', 403);
        }
        if ($r->status !== 'submitted') {
            return $this->fail('wrong_status', 'Ombi hili limeshaamuliwa. / This request was already decided.', 409);
        }
        DB::table('group_benefit_requests')->where('id', $id)->update(['status' => 'cancelled', 'updated_at' => now()]);

        return response()->json(['success' => true]);
    }

    // ---------------------------------------------------------------- the leaders

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate(['status' => ['nullable', Rule::in(['submitted', 'approved', 'rejected', 'cancelled'])], 'page' => 'nullable|integer|min:1']);
        $q = self::query()->when($data['status'] ?? null, fn ($w, $s) => $w->where('r.status', $s));
        $total = (clone $q)->count();
        $page = (int) ($data['page'] ?? 1);
        $private = GroupAccess::can($request->user(), 'approve_benefits') || GroupAccess::can($request->user(), 'record_payouts');

        return response()->json([
            'success' => true,
            'data' => ['requests' => $q->orderByDesc('r.id')->forPage($page, self::PAGE)->get()->map(fn ($r) => self::payload($r, $private))->values()],
            'meta' => ['pagination' => ['page' => $page, 'per_page' => self::PAGE, 'total' => $total, 'has_more' => $page * self::PAGE < $total]],
        ]);
    }

    /** The chair approves the help and its amount, or turns it down with the reason. Never their own request. */
    public function decide(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'approve' => 'required|boolean',
            'amount' => 'nullable|numeric|min:1|max:1000000000|required_if:approve,true',
            'note' => 'nullable|string|max:255|required_if:approve,false',
        ]);
        $r = DB::table('group_benefit_requests')->where('id', $id)->first();
        if ($r === null) {
            return $this->fail('not_found', 'Ombi halipo. / Request not found.', 404);
        }
        if ((int) $r->member_id === $this->myId($request)) {
            return $this->fail('own_request', 'Huwezi kuamua ombi lako mwenyewe. / You cannot decide your own request.', 403);
        }
        if ($r->status !== 'submitted') {
            return $this->fail('wrong_status', 'Ombi hili limeshaamuliwa. / This request was already decided.', 409);
        }
        DB::table('group_benefit_requests')->where('id', $id)->update([
            'status' => $data['approve'] ? 'approved' : 'rejected',
            'amount_approved' => $data['approve'] ? round((float) $data['amount'], 2) : null,
            'decision_note' => $data['note'] ?? null,
            'decided_by' => (string) $request->user()->id,
            'decided_at' => now(),
            'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, $data['approve'] ? 'benefit_approved' : 'benefit_rejected', $r->reference . ($data['approve'] ? ': ' . number_format((float) $data['amount']) : ': ' . $data['note']), 'benefit', $id);

        return response()->json(['success' => true, 'data' => ['request' => self::payload(self::query()->where('r.id', $id)->first(), true)]]);
    }

    /** The treasurer pays an approved request. It is PAID once someone else verifies the payment. */
    public function pay(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['method' => ['required', Rule::in(GroupLedger::METHODS)], 'external_ref' => 'nullable|string|max:80']);
        $r = DB::table('group_benefit_requests')->where('id', $id)->first();
        if ($r === null) {
            return $this->fail('not_found', 'Ombi halipo. / Request not found.', 404);
        }
        if ((int) $r->member_id === $this->myId($request)) {
            return $this->fail('own_request', 'Huwezi kulipa ombi lako mwenyewe. / You cannot pay your own request.', 403);
        }
        try {
            GroupLedger::submit([
                'member_id' => (int) $r->member_id, 'benefit_id' => $id, 'category' => 'welfare', 'amount' => (float) $r->amount_approved,
                'method' => $data['method'], 'external_ref' => $data['external_ref'] ?? null, 'note' => $r->reference,
            ], (string) $request->user()->id);
        } catch (InvalidArgumentException $e) {
            return $this->fail($e->getMessage(), GroupTransactionController::word($e->getMessage()));
        }
        GroupAudit::record((string) $request->user()->id, 'benefit_paid', $r->reference . ': ' . number_format((float) $r->amount_approved) . ' paid, waiting for verification', 'benefit', $id);

        return response()->json(['success' => true, 'data' => ['request' => self::payload(self::query()->where('r.id', $id)->first(), true)]]);
    }
}
