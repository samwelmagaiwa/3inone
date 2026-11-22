<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupMembers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * Projects (miradi): a member or an officer proposes a project; the projects committee recommends it (yes or no, with the reason); the chair
 * approves or turns it down, never their own, and only once the committee has said yes; the Projects Chairperson runs it (names a manager,
 * logs progress, closes it). Members see the projects that run or finished; proposals are seen by the proposer and by the officers.
 * The budget is what the group PLANS: money still moves only through the verified ledger.
 */
class GroupProjectController extends Controller
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

    private static function query(): \Illuminate\Database\Query\Builder
    {
        return DB::table('group_projects as p')
            ->leftJoin('group_members as pm', 'pm.id', '=', 'p.proposed_by_member_id')
            ->leftJoin('group_members as mm', 'mm.id', '=', 'p.manager_member_id')
            ->select('p.*', 'pm.full_name as proposer_name', 'mm.full_name as manager_name');
    }

    /** @return array<string, mixed> */
    private static function payload(object $p): array
    {
        $reviews = DB::table('group_project_reviews')->where('project_id', $p->id);

        return [
            'id' => (int) $p->id,
            'reference' => $p->reference,
            'title' => $p->title,
            'description' => $p->description,
            'budget' => (float) $p->budget,
            'start_date' => $p->start_date === null ? null : (string) $p->start_date,
            'end_date' => $p->end_date === null ? null : (string) $p->end_date,
            'proposed_by_id' => $p->proposed_by_member_id === null ? null : (int) $p->proposed_by_member_id,
            'proposer_name' => $p->proposer_name ?? null,
            'manager_id' => $p->manager_member_id === null ? null : (int) $p->manager_member_id,
            'manager_name' => $p->manager_name ?? null,
            'status' => $p->status,
            'progress' => (int) $p->progress,
            'spent' => self::spent((int) $p->id),
            'committed' => self::committed((int) $p->id),
            'supports' => (clone $reviews)->where('supports', true)->count(),
            'opposes' => (clone $reviews)->where('supports', false)->count(),
            'decision_note' => $p->decision_note,
            'closing_note' => $p->closing_note,
            'created_at' => (string) $p->created_at,
        ];
    }

    /** Money actually paid out for the project: verified payouts of its expense requests, not reversed. */
    public static function spent(int $id): float
    {
        return round((float) DB::table('group_transactions as t')->join('group_expense_requests as e', 'e.id', '=', 't.expense_id')->where('e.project_id', $id)
            ->where('t.direction', 'out')->where('t.status', 'verified')->whereNull('t.reversed_by_id')->whereNull('t.reverses_id')->sum('t.amount'), 2);
    }

    /** Money asked for and approved for the project (paid or not yet), the figure the budget is held against. */
    public static function committed(int $id): float
    {
        return round((float) DB::table('group_expense_requests')->where('project_id', $id)->where('status', 'approved')->sum('amount_approved'), 2);
    }

    private function mayRun(Request $request, object $p): bool
    {
        return GroupAccess::can($request->user(), 'manage_projects')
            || ($p->manager_member_id !== null && (int) $p->manager_member_id === $this->myId($request));
    }

    // ---------------------------------------------------------------- reading

    /** Officers see every project; everyone else sees the running and finished ones, and their own proposals. */
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate(['status' => ['nullable', Rule::in(['proposed', 'active', 'completed', 'rejected', 'cancelled'])], 'page' => 'nullable|integer|min:1']);
        $all = GroupAccess::can($request->user(), 'view_projects');
        $me = $this->myId($request);
        if (!$all && $me === null) {
            return $this->fail('not_a_member', 'Ni wanachama tu wanaoona miradi. / Only members see the projects.', 403);
        }
        $q = self::query()->when(!$all, fn ($w) => $w->where(fn ($x) => $x->whereIn('p.status', ['active', 'completed'])->orWhere('p.proposed_by_member_id', $me)))
            ->when($data['status'] ?? null, fn ($w, $s) => $w->where('p.status', $s));
        $total = (clone $q)->count();
        $page = (int) ($data['page'] ?? 1);

        return response()->json([
            'success' => true,
            'data' => ['projects' => $q->orderByRaw("case p.status when 'proposed' then 0 when 'active' then 1 else 2 end")->orderByDesc('p.id')->forPage($page, self::PAGE)->get()
                ->map(fn ($p) => self::payload($p))->values()],
            'meta' => ['pagination' => ['page' => $page, 'per_page' => self::PAGE, 'total' => $total, 'has_more' => $page * self::PAGE < $total]],
        ]);
    }

    public function show(Request $request, int $id): JsonResponse
    {
        $p = self::query()->where('p.id', $id)->first();
        $all = GroupAccess::can($request->user(), 'view_projects');
        $me = $this->myId($request);
        if ($p === null || (!$all && !in_array($p->status, ['active', 'completed'], true) && (int) $p->proposed_by_member_id !== $me)) {
            return $this->fail('not_found', 'Mradi haupo. / Project not found.', 404);
        }
        $out = self::payload($p);
        $out['updates'] = DB::table('group_project_updates as u')->leftJoin('users as x', 'x.id', '=', 'u.created_by')->where('u.project_id', $id)->orderByDesc('u.id')->limit(100)
            ->get(['u.id', 'u.progress', 'u.note', 'u.created_at', 'x.name as by_name'])->map(fn ($u) => (array) $u)->all();
        $out['reviews'] = $all || GroupAccess::can($request->user(), 'recommend_projects')
            ? DB::table('group_project_reviews as r')->join('group_members as m', 'm.id', '=', 'r.member_id')->where('r.project_id', $id)->orderBy('r.id')
                ->get(['r.supports', 'r.note', 'm.full_name as member_name', 'r.member_id'])->map(fn ($r) => ['supports' => (bool) $r->supports, 'note' => $r->note, 'member_name' => $r->member_name, 'mine' => (int) $r->member_id === $me])->all()
            : [];

        return response()->json(['success' => true, 'data' => ['project' => $out]]);
    }

    // ---------------------------------------------------------------- proposing

    /** A member (or an officer with the right to run projects) proposes a project. */
    public function propose(Request $request): JsonResponse
    {
        $data = $request->validate([
            'title' => 'required|string|min:3|max:150',
            'description' => 'nullable|string|max:3000',
            'budget' => 'required|numeric|min:0|max:100000000000',
            'start_date' => 'nullable|date',
            'end_date' => 'nullable|date|after_or_equal:start_date',
        ]);
        $member = GroupAccess::member($request->user());
        if ($member !== null && $member['status'] !== GroupMembers::ACTIVE) {
            return $this->fail('member_not_open', 'Ni mwanachama hai tu anayependekeza mradi. / Only an active member can propose a project.');
        }
        if ($member === null && !GroupAccess::can($request->user(), 'manage_projects')) {
            return $this->fail('not_a_member', 'Ni wanachama tu wanaopendekeza miradi. / Only members propose projects.', 403);
        }
        do {
            $ref = 'MR-' . strtoupper(Str::random(6));
        } while (DB::table('group_projects')->where('reference', $ref)->exists());
        $id = (int) DB::table('group_projects')->insertGetId([
            'reference' => $ref, 'title' => trim($data['title']), 'description' => $data['description'] ?? null, 'budget' => round((float) $data['budget'], 2),
            'start_date' => $data['start_date'] ?? null, 'end_date' => $data['end_date'] ?? null,
            'proposed_by_member_id' => $member === null ? null : (int) $member['id'], 'status' => 'proposed',
            'created_by' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'project_proposed', $ref . ': ' . trim($data['title']) . ' (' . number_format((float) $data['budget']) . ')', 'project', $id);

        return response()->json(['success' => true, 'data' => ['project' => self::payload(self::query()->where('p.id', $id)->first())]], 201);
    }

    /** The proposer withdraws a proposal nobody has decided yet. */
    public function withdraw(Request $request, int $id): JsonResponse
    {
        $p = DB::table('group_projects')->where('id', $id)->first();
        if ($p === null || $p->proposed_by_member_id === null || (int) $p->proposed_by_member_id !== $this->myId($request)) {
            return $this->fail('not_yours', 'Huu si pendekezo lako. / This is not your proposal.', 403);
        }
        if ($p->status !== 'proposed') {
            return $this->fail('wrong_status', 'Pendekezo hili limeshaamuliwa. / This proposal was already decided.', 409);
        }
        DB::table('group_projects')->where('id', $id)->update(['status' => 'cancelled', 'closing_note' => 'Withdrawn by the proposer', 'closed_at' => now(), 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'project_withdrawn', $p->reference, 'project', $id);

        return response()->json(['success' => true]);
    }

    // ---------------------------------------------------------------- the committee and the chair

    /** The committee's yes or no, once each; they may change it while the proposal is open. Never on their own proposal. */
    public function review(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['supports' => 'required|boolean', 'note' => 'nullable|string|max:255|required_if:supports,false']);
        $p = DB::table('group_projects')->where('id', $id)->first();
        $me = $this->myId($request);
        if ($p === null) {
            return $this->fail('not_found', 'Mradi haupo. / Project not found.', 404);
        }
        if ($me === null) {
            return $this->fail('not_a_member', 'Kamati inatoa maoni kama mwanachama. / A committee view is given as a member.', 403);
        }
        if ($p->proposed_by_member_id !== null && (int) $p->proposed_by_member_id === $me) {
            return $this->fail('own_project', 'Huwezi kutoa maoni juu ya pendekezo lako mwenyewe. / You cannot review your own proposal.', 403);
        }
        if ($p->status !== 'proposed') {
            return $this->fail('wrong_status', 'Pendekezo hili limeshaamuliwa. / This proposal was already decided.', 409);
        }
        $row = ['supports' => (bool) $data['supports'], 'note' => isset($data['note']) ? trim($data['note']) : null, 'updated_at' => now()];
        if (DB::table('group_project_reviews')->where('project_id', $id)->where('member_id', $me)->exists()) {
            DB::table('group_project_reviews')->where('project_id', $id)->where('member_id', $me)->update($row);
        } else {
            DB::table('group_project_reviews')->insert($row + ['project_id' => $id, 'member_id' => $me, 'created_at' => now()]);
        }
        GroupAudit::record((string) $request->user()->id, 'project_reviewed', $p->reference . ': ' . ($data['supports'] ? 'supports' : 'does not support') . ($row['note'] ? ' (' . $row['note'] . ')' : ''), 'project', $id);

        return $this->show($request, $id);
    }

    /** The chair approves (only when the committee supports it and nobody on it opposes without an answer) or turns it down with the reason. */
    public function decide(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['approve' => 'required|boolean', 'note' => 'nullable|string|max:255|required_if:approve,false']);
        $p = DB::table('group_projects')->where('id', $id)->first();
        if ($p === null) {
            return $this->fail('not_found', 'Mradi haupo. / Project not found.', 404);
        }
        if ($p->proposed_by_member_id !== null && (int) $p->proposed_by_member_id === $this->myId($request)) {
            return $this->fail('own_project', 'Huwezi kuamua pendekezo lako mwenyewe. / You cannot decide your own proposal.', 403);
        }
        if ($p->status !== 'proposed') {
            return $this->fail('wrong_status', 'Pendekezo hili limeshaamuliwa. / This proposal was already decided.', 409);
        }
        if ($data['approve']) {
            $yes = DB::table('group_project_reviews')->where('project_id', $id)->where('supports', true)->count();
            if ($yes === 0) {
                return $this->fail('committee_first', 'Kamati ya miradi haijapendekeza mradi huu. / The projects committee has not recommended this project yet.');
            }
        }
        DB::table('group_projects')->where('id', $id)->update([
            'status' => $data['approve'] ? 'active' : 'rejected', 'decision_note' => isset($data['note']) ? trim($data['note']) : null,
            'decided_by' => (string) $request->user()->id, 'decided_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, $data['approve'] ? 'project_approved' : 'project_rejected', $p->reference . ($data['approve'] ? '' : ': ' . trim((string) $data['note'])), 'project', $id);

        return $this->show($request, $id);
    }

    // ---------------------------------------------------------------- running it

    /** Edit a project that is not closed, and name its manager. */
    public function update(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'title' => 'sometimes|string|min:3|max:150',
            'description' => 'nullable|string|max:3000',
            'budget' => 'sometimes|numeric|min:0|max:100000000000',
            'start_date' => 'nullable|date',
            'end_date' => 'nullable|date|after_or_equal:start_date',
            'manager_id' => 'nullable|integer',
        ]);
        $p = DB::table('group_projects')->where('id', $id)->first();
        if ($p === null) {
            return $this->fail('not_found', 'Mradi haupo. / Project not found.', 404);
        }
        if (!in_array($p->status, ['proposed', 'active'], true)) {
            return $this->fail('closed', 'Mradi huu umefungwa. / This project is closed.', 409);
        }
        $row = ['updated_at' => now()];
        foreach (['title', 'description', 'start_date', 'end_date'] as $k) {
            if (array_key_exists($k, $data)) {
                $row[$k] = is_string($data[$k]) ? trim($data[$k]) : $data[$k];
            }
        }
        if (array_key_exists('budget', $data)) {
            $row['budget'] = round((float) $data['budget'], 2);
        }
        if (array_key_exists('manager_id', $data)) {
            if ($data['manager_id'] !== null && !DB::table('group_members')->where('id', (int) $data['manager_id'])->where('status', GroupMembers::ACTIVE)->exists()) {
                return $this->fail('manager_not_found', 'Chagua mwanachama hai kuwa msimamizi. / Choose an active member as manager.');
            }
            $row['manager_member_id'] = $data['manager_id'] === null ? null : (int) $data['manager_id'];
        }
        DB::table('group_projects')->where('id', $id)->update($row);
        GroupAudit::record((string) $request->user()->id, 'project_edited', $p->reference . ': ' . implode(', ', array_keys(array_diff_key($row, ['updated_at' => 1]))), 'project', $id);

        return $this->show($request, $id);
    }

    /** Progress: how far it is and what was done. The manager (or whoever runs projects) logs it; the log is never edited. */
    public function progress(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['progress' => 'required|integer|min:0|max:100', 'note' => 'required|string|min:2|max:500']);
        $p = DB::table('group_projects')->where('id', $id)->first();
        if ($p === null) {
            return $this->fail('not_found', 'Mradi haupo. / Project not found.', 404);
        }
        if (!$this->mayRun($request, $p)) {
            return $this->fail('not_yours', 'Ni msimamizi wa mradi au Mwenyekiti wa Miradi tu. / Only the project manager or the Projects Chairperson.', 403);
        }
        if ($p->status !== 'active') {
            return $this->fail('wrong_status', 'Mradi haujaanza au umefungwa. / The project is not running.', 409);
        }
        DB::table('group_project_updates')->insert(['project_id' => $id, 'progress' => (int) $data['progress'], 'note' => trim($data['note']), 'created_by' => (string) $request->user()->id, 'created_at' => now()]);
        DB::table('group_projects')->where('id', $id)->update(['progress' => (int) $data['progress'], 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'project_progress', $p->reference . ': ' . (int) $data['progress'] . '%', 'project', $id);

        return $this->show($request, $id);
    }

    /** Close a running project as completed, or cancel it, with a note. */
    public function close(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['outcome' => ['required', Rule::in(['completed', 'cancelled'])], 'note' => 'required|string|min:2|max:255']);
        $p = DB::table('group_projects')->where('id', $id)->first();
        if ($p === null) {
            return $this->fail('not_found', 'Mradi haupo. / Project not found.', 404);
        }
        if (!in_array($p->status, ['proposed', 'active'], true)) {
            return $this->fail('closed', 'Mradi huu umefungwa. / This project is closed.', 409);
        }
        if ($data['outcome'] === 'completed' && $p->status !== 'active') {
            return $this->fail('wrong_status', 'Mradi lazima uwe unaendelea kabla ya kukamilika. / A project must be running before it is completed.', 409);
        }
        DB::table('group_projects')->where('id', $id)->update([
            'status' => $data['outcome'], 'closing_note' => trim($data['note']), 'closed_at' => now(),
            'progress' => $data['outcome'] === 'completed' ? 100 : $p->progress, 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'project_' . $data['outcome'], $p->reference . ': ' . trim($data['note']), 'project', $id);

        return $this->show($request, $id);
    }
}
