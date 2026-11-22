<?php

namespace App\Http\Controllers\API\Groups;

use App\Jobs\SendGroupMessageJob;
use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupContributions;
use App\Support\Groups\GroupMembers;
use App\Support\SmsQuota;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Meetings (the chair calls them, the secretary keeps attendance and minutes), announcements, and texts to many members at once. Every member
 * reads the meetings and the announcements meant for them; a text shows how many people and SMS it will take before anything goes out.
 */
class GroupCommunicationController extends Controller
{
    private function fail(string $code, string $message, int $status = 422): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => $message], $status);
    }

    private static function isOfficer(Request $request): bool
    {
        if (GroupAccess::isOwner($request->user())) {
            return true;
        }
        $me = GroupAccess::member($request->user());

        return $me !== null && !empty($me['office']) && $me['status'] === GroupMembers::ACTIVE;
    }

    // ---------------------------------------------------------------- meetings

    /** @return array<string, mixed> */
    private static function meeting(object $m, ?int $myId): array
    {
        $present = DB::table('group_meeting_attendance')->where('meeting_id', $m->id)->where('present', true)->pluck('member_id')->map(fn ($id) => (int) $id)->all();

        return [
            'id' => (int) $m->id,
            'title' => $m->title,
            'agenda' => $m->agenda,
            'starts_at' => (string) $m->starts_at,
            'venue' => $m->venue,
            'status' => $m->status,
            'minutes' => $m->minutes,
            'cancel_reason' => $m->cancel_reason,
            'called_by_name' => $m->called_by_name ?? null,
            'present_count' => count($present),
            'present_ids' => $present,
            'i_was_there' => $myId === null ? null : in_array($myId, $present, true),
        ];
    }

    public function meetings(Request $request): JsonResponse
    {
        $me = GroupAccess::member($request->user());
        $rows = DB::table('group_meetings as g')->leftJoin('users as u', 'u.id', '=', 'g.called_by')->orderByDesc('g.starts_at')->limit(100)->get(['g.*', 'u.name as called_by_name']);

        return response()->json(['success' => true, 'data' => ['meetings' => $rows->map(fn ($m) => self::meeting($m, $me === null ? null : (int) $me['id']))->values()]]);
    }

    /** The chair calls a meeting; members can be told by text (it uses the group's SMS). */
    public function callMeeting(Request $request): JsonResponse
    {
        $data = $request->validate([
            'title' => 'required|string|min:3|max:150',
            'agenda' => 'nullable|string|max:5000',
            'starts_at' => 'required|date|after:now',
            'venue' => 'nullable|string|max:150',
            'notify' => 'nullable|boolean',
        ]);
        $id = (int) DB::table('group_meetings')->insertGetId([
            'title' => trim($data['title']), 'agenda' => $data['agenda'] ?? null, 'starts_at' => $data['starts_at'], 'venue' => $data['venue'] ?? null,
            'status' => 'scheduled', 'called_by' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'meeting_called', trim($data['title']) . ' ' . $data['starts_at'], 'meeting', $id);
        if ($data['notify'] ?? false) {
            $when = \Illuminate\Support\Carbon::parse($data['starts_at'])->format('d/m/Y H:i');
            $this->queueText($request, 'all', [], "Kikao: {$data['title']}, {$when}" . (empty($data['venue']) ? '' : ", {$data['venue']}") . '. Karibu.');
        }

        return response()->json(['success' => true, 'data' => ['meeting' => self::meeting(DB::table('group_meetings')->where('id', $id)->first(), null)]], 201);
    }

    public function cancelMeeting(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['reason' => 'required|string|min:3|max:255']);
        $done = DB::table('group_meetings')->where('id', $id)->where('status', 'scheduled')->update(['status' => 'cancelled', 'cancel_reason' => trim($data['reason']), 'updated_at' => now()]);
        if ($done === 0) {
            return $this->fail('wrong_status', 'Kikao hiki hakiwezi kusitishwa. / This meeting cannot be cancelled.', 409);
        }
        GroupAudit::record((string) $request->user()->id, 'meeting_cancelled', 'Meeting #' . $id . ': ' . trim($data['reason']), 'meeting', $id);

        return response()->json(['success' => true]);
    }

    /** The secretary records who was there and the minutes; the meeting is then held. Can be corrected later (the log keeps who did it). */
    public function recordMeeting(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'present_ids' => 'present|array|max:5000',
            'present_ids.*' => 'integer',
            'minutes' => 'nullable|string|max:20000',
        ]);
        $meeting = DB::table('group_meetings')->where('id', $id)->first();
        if ($meeting === null || $meeting->status === 'cancelled') {
            return $this->fail('wrong_status', 'Kikao hiki hakipo au kimesitishwa. / This meeting does not exist or was cancelled.', 409);
        }
        if (\Illuminate\Support\Carbon::parse((string) $meeting->starts_at)->isFuture()) {
            return $this->fail('not_yet', 'Kikao bado hakijafanyika. / The meeting has not happened yet.', 409);
        }
        $valid = DB::table('group_members')->whereIn('id', $data['present_ids'])->pluck('id')->map(fn ($v) => (int) $v)->all();
        DB::transaction(function () use ($id, $valid, $data, $request) {
            DB::table('group_meeting_attendance')->where('meeting_id', $id)->delete();
            foreach (array_chunk($valid, 200) as $chunk) {
                DB::table('group_meeting_attendance')->insert(array_map(fn ($m) => ['meeting_id' => $id, 'member_id' => $m, 'present' => true], $chunk));
            }
            DB::table('group_meetings')->where('id', $id)->update([
                'status' => 'held', 'minutes' => $data['minutes'] ?? null, 'minutes_by' => (string) $request->user()->id, 'updated_at' => now(),
            ]);
        });
        GroupAudit::record((string) $request->user()->id, 'meeting_recorded', 'Meeting #' . $id . ': ' . count($valid) . ' present', 'meeting', $id);

        return response()->json(['success' => true, 'data' => ['meeting' => self::meeting(DB::table('group_meetings')->where('id', $id)->first(), null)]]);
    }

    // ---------------------------------------------------------------- announcements

    public function announcements(Request $request): JsonResponse
    {
        $officer = self::isOfficer($request);
        $rows = DB::table('group_announcements as a')->leftJoin('users as u', 'u.id', '=', 'a.author_id')
            ->when(!$officer, fn ($q) => $q->where('a.audience', 'all'))
            ->where(fn ($q) => $q->whereNull('a.expires_on')->orWhere('a.expires_on', '>=', now()->toDateString()))
            ->orderByDesc('a.id')->limit(100)->get(['a.*', 'u.name as author_name']);

        return response()->json(['success' => true, 'data' => ['announcements' => $rows->map(fn ($a) => [
            'id' => (int) $a->id, 'title' => $a->title, 'body' => $a->body, 'category' => $a->category, 'audience' => $a->audience,
            'expires_on' => $a->expires_on === null ? null : (string) $a->expires_on, 'author_name' => $a->author_name, 'created_at' => (string) $a->created_at,
        ])->values()]]);
    }

    public function postAnnouncement(Request $request): JsonResponse
    {
        $data = $request->validate([
            'title' => 'required|string|min:3|max:150',
            'body' => 'required|string|min:3|max:5000',
            'category' => ['nullable', Rule::in(['general', 'meeting', 'event', 'bereavement', 'contribution', 'loan', 'asset', 'emergency'])],
            'audience' => ['nullable', Rule::in(['all', 'officers'])],
            'expires_on' => 'nullable|date|after_or_equal:today',
        ]);
        $id = (int) DB::table('group_announcements')->insertGetId([
            'title' => trim($data['title']), 'body' => trim($data['body']), 'category' => $data['category'] ?? 'general', 'audience' => $data['audience'] ?? 'all',
            'expires_on' => $data['expires_on'] ?? null, 'author_id' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'announcement_posted', trim($data['title']), 'announcement', $id);

        return $this->announcements($request)->setStatusCode(201);
    }

    public function removeAnnouncement(Request $request, int $id): JsonResponse
    {
        $a = DB::table('group_announcements')->where('id', $id)->first();
        if ($a === null) {
            return $this->fail('not_found', 'Tangazo halipo. / Not found.', 404);
        }
        // It stops showing today; the log keeps that it was there.
        DB::table('group_announcements')->where('id', $id)->update(['expires_on' => now()->subDay()->toDateString(), 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'announcement_removed', $a->title, 'announcement', $id);

        return $this->announcements($request);
    }

    // ---------------------------------------------------------------- texts to many members

    /** @return array<int, array{id: int, phone: string}> the members a text for [audience] goes to */
    private static function recipients(string $audience, array $ids): array
    {
        $q = DB::table('group_members')->where('status', GroupMembers::ACTIVE)->whereNotNull('phone');
        match ($audience) {
            'officers' => $q->whereNotNull('office'),
            'overdue' => $q->whereIn('id', GroupContributions::owing(GroupContributions::query())->where('o.due_date', '<', now()->toDateString())->pluck('o.member_id')),
            'selected' => $q->whereIn('id', array_map('intval', $ids)),
            default => $q,
        };

        return $q->get(['id', 'phone'])->map(fn ($m) => ['id' => (int) $m->id, 'phone' => (string) $m->phone])->all();
    }

    /** How many people and SMS parts a text would take, before sending. */
    public function estimate(Request $request): JsonResponse
    {
        $data = $request->validate([
            'audience' => ['required', Rule::in(['all', 'officers', 'overdue', 'selected'])],
            'member_ids' => 'nullable|array|max:5000',
            'member_ids.*' => 'integer',
            'body' => 'required|string|min:2|max:640',
        ]);
        $people = count(self::recipients($data['audience'], $data['member_ids'] ?? []));
        $parts = SmsQuota::parts($data['body']);

        return response()->json(['success' => true, 'data' => ['recipients' => $people, 'parts_each' => $parts, 'parts_total' => $people * $parts]]);
    }

    private function queueText(Request $request, string $audience, array $ids, string $body): ?int
    {
        $people = self::recipients($audience, $ids);
        if ($people === []) {
            return null;
        }
        $id = (int) DB::table('group_messages')->insertGetId([
            'body' => $body, 'audience' => $audience, 'recipients' => count($people), 'parts' => SmsQuota::parts($body),
            'status' => 'queued', 'sent_by' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);
        foreach (array_chunk($people, 200) as $chunk) {
            DB::table('group_message_recipients')->insert(array_map(fn ($p) => ['message_id' => $id, 'member_id' => $p['id'], 'phone' => $p['phone'], 'status' => 'waiting'], $chunk));
        }
        SendGroupMessageJob::dispatch((string) $request->user()->id, $id);

        return $id;
    }

    public function send(Request $request): JsonResponse
    {
        $data = $request->validate([
            'audience' => ['required', Rule::in(['all', 'officers', 'overdue', 'selected'])],
            'member_ids' => 'nullable|array|max:5000|required_if:audience,selected',
            'member_ids.*' => 'integer',
            'body' => 'required|string|min:2|max:640',
        ]);
        $id = $this->queueText($request, $data['audience'], $data['member_ids'] ?? [], trim($data['body']));
        if ($id === null) {
            return $this->fail('no_recipients', 'Hakuna wa kutumiwa ujumbe. / Nobody to send it to.');
        }
        GroupAudit::record((string) $request->user()->id, 'texts_sent', 'Text to ' . $data['audience'] . ': ' . mb_substr(trim($data['body']), 0, 120), 'message', $id);

        return $this->messages()->setStatusCode(201);
    }

    public function messages(): JsonResponse
    {
        $rows = DB::table('group_messages as m')->leftJoin('users as u', 'u.id', '=', 'm.sent_by')->orderByDesc('m.id')->limit(50)->get(['m.*', 'u.name as sent_by_name']);

        return response()->json(['success' => true, 'data' => ['messages' => $rows->map(fn ($m) => [
            'id' => (int) $m->id, 'body' => $m->body, 'audience' => $m->audience, 'recipients' => (int) $m->recipients, 'sent' => (int) $m->sent,
            'parts' => (int) $m->parts, 'status' => $m->status, 'sent_by_name' => $m->sent_by_name, 'created_at' => (string) $m->created_at,
        ])->values()]]);
    }
}
