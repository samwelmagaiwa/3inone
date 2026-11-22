<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupMembers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * The record of a meeting: the secretary writes the minutes, the resolutions and the actions (who must do what by when); the chair approves
 * the minutes (never the ones they wrote themselves); from then on members see them and whoever owns an action ticks it off. Approved minutes
 * are not edited unless the chair reopens them, with a reason, and the log keeps who did what.
 */
class GroupMeetingRecordController extends Controller
{
    private function fail(string $code, string $message, int $status = 422): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => $message], $status);
    }

    private function myId(Request $request): ?int
    {
        $me = GroupAccess::member($request->user());

        return $me === null ? null : (int) $me['id'];
    }

    /** @return array<string, mixed> */
    public static function itemPayload(object $i): array
    {
        return [
            'id' => (int) $i->id,
            'meeting_id' => (int) $i->meeting_id,
            'meeting_title' => $i->meeting_title ?? null,
            'kind' => $i->kind,
            'text' => $i->text,
            'assignee_id' => $i->assignee_member_id === null ? null : (int) $i->assignee_member_id,
            'assignee_name' => $i->assignee_name ?? null,
            'due_date' => $i->due_date === null ? null : (string) $i->due_date,
            'status' => $i->status,
            'overdue' => $i->kind === 'action' && $i->status === 'open' && $i->due_date !== null && (string) $i->due_date < now()->toDateString(),
        ];
    }

    private static function itemsQuery(): \Illuminate\Database\Query\Builder
    {
        return DB::table('group_meeting_items as i')->join('group_meetings as g', 'g.id', '=', 'i.meeting_id')->leftJoin('group_members as a', 'a.id', '=', 'i.assignee_member_id')
            ->select('i.*', 'g.title as meeting_title', 'a.full_name as assignee_name');
    }

    /** @return array<int, array<string, mixed>> */
    public static function itemsOf(int $meetingId): array
    {
        return self::itemsQuery()->where('i.meeting_id', $meetingId)->orderBy('i.kind', 'desc')->orderBy('i.id')->get()->map(fn ($i) => self::itemPayload($i))->all();
    }

    /** The meeting when its minutes may be edited, otherwise the response that says why not. */
    private function openForEditing(int $id): mixed
    {
        $m = DB::table('group_meetings')->where('id', $id)->first();
        if ($m === null) {
            return $this->fail('not_found', 'Kikao hakipo. / Meeting not found.', 404);
        }
        if ($m->status !== 'held') {
            return $this->fail('not_held', 'Kikao hakijarekodiwa. / The meeting has not been recorded yet.', 409);
        }
        if ($m->minutes_approved_at !== null) {
            return $this->fail('minutes_approved', 'Muhtasari umeidhinishwa; Mwenyekiti afungue upya kwanza. / The minutes are approved: the chair must reopen them first.', 409);
        }

        return $m;
    }

    private function meetingJson(Request $request, int $id): JsonResponse
    {
        $row = DB::table('group_meetings as g')->leftJoin('users as u', 'u.id', '=', 'g.called_by')->leftJoin('users as v', 'v.id', '=', 'g.minutes_approved_by')
            ->where('g.id', $id)->first(['g.*', 'u.name as called_by_name', 'v.name as approved_by_name']);
        $me = $this->myId($request);

        return response()->json(['success' => true, 'data' => ['meeting' => GroupCommunicationController::meetingFor($row, $me, GroupCommunicationController::officer($request))]]);
    }

    // ---------------------------------------------------------------- resolutions and actions

    public function addItem(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'kind' => ['required', Rule::in(['resolution', 'action'])],
            'text' => 'required|string|min:3|max:500',
            'assignee_id' => 'nullable|integer',
            'due_date' => 'nullable|date',
        ]);
        $m = $this->openForEditing($id);
        if ($m instanceof JsonResponse) {
            return $m;
        }
        $assignee = null;
        if ($data['kind'] === 'action' && !empty($data['assignee_id'])) {
            $assignee = DB::table('group_members')->where('id', (int) $data['assignee_id'])->where('status', GroupMembers::ACTIVE)->value('id');
            if ($assignee === null) {
                return $this->fail('assignee_not_found', 'Chagua mwanachama hai. / Choose an active member.');
            }
        }
        $itemId = (int) DB::table('group_meeting_items')->insertGetId([
            'meeting_id' => $id, 'kind' => $data['kind'], 'text' => trim($data['text']),
            'assignee_member_id' => $assignee === null ? null : (int) $assignee, 'due_date' => $data['kind'] === 'action' ? ($data['due_date'] ?? null) : null,
            'status' => 'open', 'created_by' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'meeting_item_added', 'Meeting #' . $id . ' ' . $data['kind'] . ': ' . trim($data['text']), 'meeting', $id);

        return $this->meetingJson($request, $id);
    }

    public function removeItem(Request $request, int $id, int $itemId): JsonResponse
    {
        $m = $this->openForEditing($id);
        if ($m instanceof JsonResponse) {
            return $m;
        }
        $gone = DB::table('group_meeting_items')->where('id', $itemId)->where('meeting_id', $id)->delete();
        if ($gone === 0) {
            return $this->fail('not_found', 'Kipengele hakipo. / Item not found.', 404);
        }
        GroupAudit::record((string) $request->user()->id, 'meeting_item_removed', 'Meeting #' . $id . ' item #' . $itemId, 'meeting', $id);

        return $this->meetingJson($request, $id);
    }

    /** Tick an action as done: whoever it was given to, or whoever records the meetings. Only once the minutes are approved. */
    public function completeItem(Request $request, int $id, int $itemId): JsonResponse
    {
        $item = DB::table('group_meeting_items')->where('id', $itemId)->where('meeting_id', $id)->first();
        $m = DB::table('group_meetings')->where('id', $id)->first();
        if ($item === null || $m === null || $item->kind !== 'action') {
            return $this->fail('not_found', 'Kipengele hakipo. / Item not found.', 404);
        }
        $mine = $item->assignee_member_id !== null && (int) $item->assignee_member_id === $this->myId($request);
        if (!$mine && !GroupAccess::can($request->user(), 'record_meetings')) {
            return $this->fail('not_yours', 'Si kazi yako. / This action is not yours.', 403);
        }
        if ($m->minutes_approved_at === null) {
            return $this->fail('minutes_not_approved', 'Muhtasari haujaidhinishwa bado. / The minutes are not approved yet.', 409);
        }
        if ($item->status === 'done') {
            return $this->fail('wrong_status', 'Kazi hii imeshakamilika. / Already done.', 409);
        }
        DB::table('group_meeting_items')->where('id', $itemId)->update(['status' => 'done', 'done_at' => now(), 'done_by' => (string) $request->user()->id, 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'meeting_action_done', 'Meeting #' . $id . ': ' . $item->text, 'meeting', $id);

        return $this->meetingJson($request, $id);
    }

    /** Open actions: one's own, or (for whoever records meetings) everyone's. Only from approved minutes. */
    public function actions(Request $request): JsonResponse
    {
        $data = $request->validate(['scope' => ['nullable', Rule::in(['mine', 'all'])]]);
        $all = ($data['scope'] ?? 'mine') === 'all';
        if ($all && !GroupAccess::can($request->user(), 'record_meetings')) {
            return $this->fail('not_allowed', 'Huna ruhusa. / Not allowed.', 403);
        }
        $me = $this->myId($request);
        $q = self::itemsQuery()->where('i.kind', 'action')->where('i.status', 'open')->whereNotNull('g.minutes_approved_at')
            ->when(!$all, fn ($w) => $w->where('i.assignee_member_id', $me ?? 0));

        return response()->json(['success' => true, 'data' => ['actions' => $q->orderByRaw('case when i.due_date is null then 1 else 0 end')->orderBy('i.due_date')->orderBy('i.id')->limit(200)->get()
            ->map(fn ($i) => self::itemPayload($i))->values()]]);
    }

    // ---------------------------------------------------------------- the chair and the minutes

    /** The chair approves the minutes (not ones they wrote themselves): members then see them. */
    public function approveMinutes(Request $request, int $id): JsonResponse
    {
        $m = $this->openForEditing($id);
        if ($m instanceof JsonResponse) {
            return $m;
        }
        if (trim((string) $m->minutes) === '' && !DB::table('group_meeting_items')->where('meeting_id', $id)->exists()) {
            return $this->fail('minutes_empty', 'Hakuna muhtasari wa kuidhinisha. / There are no minutes to approve.');
        }
        if ($m->minutes_by !== null && (string) $m->minutes_by === (string) $request->user()->id) {
            return $this->fail('own_minutes', 'Huwezi kuidhinisha muhtasari uliouandika mwenyewe. / You cannot approve minutes you wrote yourself.', 403);
        }
        DB::table('group_meetings')->where('id', $id)->update(['minutes_approved_by' => (string) $request->user()->id, 'minutes_approved_at' => now(), 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'minutes_approved', 'Meeting #' . $id . ': ' . $m->title, 'meeting', $id);

        return $this->meetingJson($request, $id);
    }

    /** The chair opens approved minutes again so they can be corrected; the reason is kept in the log. */
    public function reopenMinutes(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['reason' => 'required|string|min:3|max:255']);
        $m = DB::table('group_meetings')->where('id', $id)->first();
        if ($m === null || $m->minutes_approved_at === null) {
            return $this->fail('wrong_status', 'Muhtasari haujaidhinishwa. / The minutes are not approved.', 409);
        }
        DB::table('group_meetings')->where('id', $id)->update(['minutes_approved_by' => null, 'minutes_approved_at' => null, 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'minutes_reopened', 'Meeting #' . $id . ': ' . trim($data['reason']), 'meeting', $id);

        return $this->meetingJson($request, $id);
    }
}
