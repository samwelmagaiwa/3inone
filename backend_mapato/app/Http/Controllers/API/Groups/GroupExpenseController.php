<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupLedger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use InvalidArgumentException;

/**
 * Expenses (matumizi): an official asks for money to be spent; the treasurer (or the chair) approves it, or turns it down; the treasurer pays it
 * out through the ledger and someone else verifies the payment. An APPROVED request is not a PAID one: it is paid only when its payout is
 * verified. Nobody approves their own request or pays out their own; a request for a project is held to that project's budget.
 */
class GroupExpenseController extends Controller
{
    private const PAGE = 50;

    public const CATEGORIES = ['project', 'office', 'meeting', 'transport', 'event', 'other'];

    private function fail(string $code, string $message, int $status = 422): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => $message], $status);
    }

    private function myId(Request $request): ?int
    {
        $me = GroupAccess::member($request->user());

        return $me === null ? null : (int) $me['id'];
    }

    /** Is [r] this person's own request (so they may neither approve nor pay it)? */
    private function isMine(Request $request, object $r): bool
    {
        $me = $this->myId($request);

        return ($r->requested_by !== null && (string) $r->requested_by === (string) $request->user()->id)
            || ($me !== null && $r->requested_by_member_id !== null && (int) $r->requested_by_member_id === $me);
    }

    /** requested | approved | paying (payout waiting for verification) | paid | rejected | cancelled */
    private static function state(object $r): string
    {
        if ($r->status !== 'approved') {
            return $r->status;
        }
        $payout = DB::table('group_transactions')->where('expense_id', $r->id)->where('direction', 'out')->whereIn('status', [GroupLedger::PENDING, GroupLedger::VERIFIED])
            ->whereNull('reversed_by_id')->whereNull('reverses_id')->orderByDesc('id')->value('status');

        return match ($payout) {
            GroupLedger::VERIFIED => 'paid',
            GroupLedger::PENDING => 'paying',
            default => 'approved',
        };
    }

    /** @return array<string, mixed> */
    private function payload(Request $request, object $r): array
    {
        return [
            'id' => (int) $r->id,
            'reference' => $r->reference,
            'purpose' => $r->purpose,
            'category' => $r->category,
            'payee' => $r->payee,
            'amount' => (float) $r->amount,
            'amount_approved' => $r->amount_approved === null ? null : (float) $r->amount_approved,
            'project_id' => $r->project_id === null ? null : (int) $r->project_id,
            'project_title' => $r->project_title ?? null,
            'requested_by_name' => $r->requester_name ?? $r->requester_user_name ?? null,
            'state' => self::state($r),
            'decision_note' => $r->decision_note,
            'mine' => $this->isMine($request, $r),
            'created_at' => (string) $r->created_at,
        ];
    }

    private static function query(): \Illuminate\Database\Query\Builder
    {
        return DB::table('group_expense_requests as e')
            ->leftJoin('group_members as rm', 'rm.id', '=', 'e.requested_by_member_id')
            ->leftJoin('users as ru', 'ru.id', '=', 'e.requested_by')
            ->leftJoin('group_projects as p', 'p.id', '=', 'e.project_id')
            ->select('e.*', 'rm.full_name as requester_name', 'ru.name as requester_user_name', 'p.title as project_title');
    }

    // ---------------------------------------------------------------- reading

    /** Whoever sees every request (view right) gets all of them; a requester gets their own. */
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate(['status' => ['nullable', Rule::in(['requested', 'approved', 'rejected', 'cancelled'])], 'project_id' => 'nullable|integer', 'page' => 'nullable|integer|min:1']);
        $all = GroupAccess::can($request->user(), 'view_expenses');
        if (!$all && !GroupAccess::can($request->user(), 'request_expenses')) {
            return $this->fail('not_allowed', 'Huna ruhusa ya kuona matumizi. / You may not see expenses.', 403);
        }
        $me = $this->myId($request);
        $q = self::query()->when(!$all, fn ($w) => $w->where(fn ($x) => $x->where('e.requested_by', (string) $request->user()->id)->when($me !== null, fn ($y) => $y->orWhere('e.requested_by_member_id', $me))))
            ->when($data['status'] ?? null, fn ($w, $s) => $w->where('e.status', $s))
            ->when($data['project_id'] ?? null, fn ($w, $s) => $w->where('e.project_id', (int) $s));
        $total = (clone $q)->count();
        $page = (int) ($data['page'] ?? 1);

        return response()->json([
            'success' => true,
            'data' => ['requests' => $q->orderByRaw("case e.status when 'requested' then 0 when 'approved' then 1 else 2 end")->orderByDesc('e.id')->forPage($page, self::PAGE)->get()
                ->map(fn ($r) => $this->payload($request, $r))->values()],
            'meta' => ['pagination' => ['page' => $page, 'per_page' => self::PAGE, 'total' => $total, 'has_more' => $page * self::PAGE < $total]],
        ]);
    }

    private function one(Request $request, int $id, int $status = 200): JsonResponse
    {
        return response()->json(['success' => true, 'data' => ['request' => $this->payload($request, self::query()->where('e.id', $id)->first())]], $status);
    }

    // ---------------------------------------------------------------- asking

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'purpose' => 'required|string|min:3|max:255',
            'category' => ['required', Rule::in(self::CATEGORIES)],
            'payee' => 'required|string|min:2|max:150',
            'amount' => 'required|numeric|min:1|max:100000000000',
            'project_id' => 'nullable|integer',
        ]);
        if (!empty($data['project_id']) && !DB::table('group_projects')->where('id', (int) $data['project_id'])->where('status', 'active')->exists()) {
            return $this->fail('project_not_running', 'Mradi huu hauendelei. / This project is not running.');
        }
        do {
            $ref = 'MT-' . strtoupper(Str::random(6));
        } while (DB::table('group_expense_requests')->where('reference', $ref)->exists());
        $id = (int) DB::table('group_expense_requests')->insertGetId([
            'reference' => $ref, 'purpose' => trim($data['purpose']), 'category' => $data['category'], 'payee' => trim($data['payee']),
            'amount' => round((float) $data['amount'], 2), 'project_id' => $data['project_id'] ?? null,
            'requested_by_member_id' => $this->myId($request), 'requested_by' => (string) $request->user()->id,
            'status' => 'requested', 'created_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'expense_requested', $ref . ': ' . number_format((float) $data['amount']) . ' to ' . trim($data['payee']) . ' (' . trim($data['purpose']) . ')', 'expense', $id);

        return $this->one($request, $id, 201);
    }

    /** The requester takes back a request nobody has decided yet. */
    public function cancel(Request $request, int $id): JsonResponse
    {
        $r = DB::table('group_expense_requests')->where('id', $id)->first();
        if ($r === null || !$this->isMine($request, $r)) {
            return $this->fail('not_yours', 'Hili si ombi lako. / This is not your request.', 403);
        }
        if ($r->status !== 'requested') {
            return $this->fail('wrong_status', 'Ombi hili limeshaamuliwa. / This request was already decided.', 409);
        }
        DB::table('group_expense_requests')->where('id', $id)->update(['status' => 'cancelled', 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'expense_cancelled', $r->reference, 'expense', $id);

        return $this->one($request, $id);
    }

    // ---------------------------------------------------------------- deciding and paying

    /** Approve (the amount asked or less) or turn down with the reason. Never one's own; a project's budget is never passed. */
    public function decide(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'approve' => 'required|boolean',
            'amount' => 'nullable|numeric|min:1|max:100000000000',
            'note' => 'nullable|string|max:255|required_if:approve,false',
        ]);
        $r = DB::table('group_expense_requests')->where('id', $id)->first();
        if ($r === null) {
            return $this->fail('not_found', 'Ombi halipo. / Request not found.', 404);
        }
        if ($this->isMine($request, $r)) {
            return $this->fail('own_request', 'Huwezi kuamua ombi lako mwenyewe. / You cannot decide your own request.', 403);
        }
        if ($r->status !== 'requested') {
            return $this->fail('wrong_status', 'Ombi hili limeshaamuliwa. / This request was already decided.', 409);
        }
        $amount = round((float) ($data['amount'] ?? $r->amount), 2);
        if ($data['approve']) {
            if ($amount > (float) $r->amount + 0.001) {
                return $this->fail('more_than_asked', 'Kiasi hakiwezi kuzidi kilichoombwa. / The amount cannot be more than was asked.');
            }
            if ($r->project_id !== null) {
                $project = DB::table('group_projects')->where('id', $r->project_id)->first();
                if ($project === null || $project->status !== 'active') {
                    return $this->fail('project_not_running', 'Mradi huu hauendelei. / This project is not running.');
                }
                if (GroupProjectController::committed((int) $r->project_id) + $amount > (float) $project->budget + 0.001) {
                    return $this->fail('over_budget', 'Hii inazidi bajeti ya mradi. Ongeza bajeti ya mradi kwanza. / This goes past the project\'s budget: raise the project budget first.');
                }
            }
        }
        DB::table('group_expense_requests')->where('id', $id)->update([
            'status' => $data['approve'] ? 'approved' : 'rejected', 'amount_approved' => $data['approve'] ? $amount : null,
            'decision_note' => isset($data['note']) ? trim($data['note']) : null, 'decided_by' => (string) $request->user()->id, 'decided_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, $data['approve'] ? 'expense_approved' : 'expense_rejected', $r->reference . ($data['approve'] ? ': ' . number_format($amount) : ': ' . trim((string) $data['note'])), 'expense', $id);

        return $this->one($request, $id);
    }

    /** The treasurer pays an approved request out. It is PAID once someone else verifies the payment. Never one's own request. */
    public function pay(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['method' => ['required', Rule::in(GroupLedger::METHODS)], 'external_ref' => 'nullable|string|max:80']);
        $r = DB::table('group_expense_requests')->where('id', $id)->first();
        if ($r === null) {
            return $this->fail('not_found', 'Ombi halipo. / Request not found.', 404);
        }
        if ($this->isMine($request, $r)) {
            return $this->fail('own_request', 'Huwezi kulipa ombi lako mwenyewe. / You cannot pay your own request.', 403);
        }
        try {
            GroupLedger::submit([
                'member_id' => null, 'expense_id' => $id, 'category' => 'expense', 'direction' => 'out', 'amount' => (float) $r->amount_approved, 'payee' => $r->payee,
                'method' => $data['method'], 'external_ref' => $data['external_ref'] ?? null, 'note' => mb_substr($r->reference . ': ' . $r->purpose, 0, 255),
            ], (string) $request->user()->id);
        } catch (InvalidArgumentException $e) {
            return $this->fail($e->getMessage(), GroupTransactionController::word($e->getMessage()));
        }
        GroupAudit::record((string) $request->user()->id, 'expense_paid', $r->reference . ': ' . number_format((float) $r->amount_approved) . ' paid, waiting for verification', 'expense', $id);

        return $this->one($request, $id);
    }
}
