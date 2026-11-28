<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupContributions;
use App\Support\Groups\GroupMembers;
use App\Support\Groups\GroupPromises;
use App\Support\Groups\GroupStatement;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use InvalidArgumentException;

/**
 * Contributions: what the group asks of its members in turn, raising a month's or an event's call, who owes what, excusing a member
 * (udhuru) and promises to pay. The rights are on the routes; who-is-acting rules (nobody excuses themself) are here.
 */
class GroupContributionController extends Controller
{
    private const PAGE = 50;

    private function fail(string $code, string $message, int $status = 422): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => $message], $status);
    }

    public function types(): JsonResponse
    {
        $types = DB::table('group_contribution_types')->orderByDesc('active')->orderBy('name')->get()->map(fn ($t) => GroupContributions::typePayload($t))->values();

        return response()->json(['success' => true, 'data' => ['types' => $types]]);
    }

    /** Add a contribution, or change one ([id]). A new amount applies to calls raised from now on; what is already owed stays as it was. */
    public function saveType(Request $request, ?int $id = null): JsonResponse
    {
        $data = $request->validate([
            'name' => 'required|string|min:2|max:100',
            'description' => 'nullable|string|max:255',
            'amount' => 'required|numeric|min:1|max:1000000000',
            'frequency' => ['required', Rule::in(GroupContributions::FREQUENCIES)],
            'due_day' => 'nullable|integer|min:1|max:31|required_if:frequency,monthly',
            'mandatory' => 'nullable|boolean',
            'refundable' => 'nullable|boolean',
            'starts_on' => 'nullable|date',
            'ends_on' => 'nullable|date|after_or_equal:starts_on',
            'active' => 'nullable|boolean',
        ]);
        $row = [
            'name' => trim($data['name']),
            'description' => $data['description'] ?? null,
            'amount' => round((float) $data['amount'], 2),
            'frequency' => $data['frequency'],
            'due_day' => $data['frequency'] === 'monthly' ? (int) $data['due_day'] : null,
            'mandatory' => (bool) ($data['mandatory'] ?? true),
            'starts_on' => $data['starts_on'] ?? now()->toDateString(),
            'ends_on' => $data['ends_on'] ?? null,
            'active' => (bool) ($data['active'] ?? true),
            'updated_at' => now(),
        ];
        // refundable: the member gets it back on leaving. An older app that does not send it leaves it as it was.
        if (array_key_exists('refundable', $data) || $id === null) {
            $row['refundable'] = (bool) ($data['refundable'] ?? false);
        }
        if ($id === null) {
            $id = (int) DB::table('group_contribution_types')->insertGetId($row + ['created_by' => (string) $request->user()->id, 'created_at' => now()]);
        } elseif (DB::table('group_contribution_types')->where('id', $id)->update($row) === 0 && !DB::table('group_contribution_types')->where('id', $id)->exists()) {
            return $this->fail('not_found', 'Mchango haupo. / Contribution not found.', 404);
        }
        GroupAudit::record((string) $request->user()->id, 'contribution_saved', $row['name'] . ': ' . number_format($row['amount']) . ' ' . $row['frequency'], 'contribution_type', $id);
        $type = DB::table('group_contribution_types')->where('id', $id)->first();

        return response()->json(['success' => true, 'data' => ['type' => GroupContributions::typePayload($type)]], 201);
    }

    /**
     * Raise a call: every active member then owes it. Monthly: for a month (this one unless given). Once: on a due date. An event (a
     * celebration, a funeral): a due date and what it is for.
     */
    public function raise(Request $request, int $id): JsonResponse
    {
        $type = DB::table('group_contribution_types')->where('id', $id)->first();
        if ($type === null) {
            return $this->fail('not_found', 'Mchango haupo. / Contribution not found.', 404);
        }
        if (!$type->active) {
            return $this->fail('inactive', 'Mchango huu umesimamishwa. / This contribution is switched off.', 409);
        }
        $data = $request->validate([
            'month' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/'],
            'due_date' => 'nullable|date',
            'label' => 'nullable|string|max:120',
        ]);

        if ($type->frequency === 'monthly') {
            $month = $data['month'] ?? now()->format('Y-m');
            $created = GroupContributions::raise($type, $month, GroupContributions::dueDateIn((int) $type->due_day, $month));
            $what = $month;
        } else {
            if (empty($data['due_date'])) {
                return $this->fail('due_date_required', 'Weka tarehe ya mwisho ya kulipa. / Give the date it is due.');
            }
            if ($type->frequency === 'event' && trim((string) ($data['label'] ?? '')) === '') {
                return $this->fail('label_required', 'Andika ni kwa ajili ya nini (mfano: harusi ya Juma). / Write what it is for (e.g. Juma\'s wedding).');
            }
            $period = $type->frequency === 'one_time' ? 'once' : GroupContributions::eventPeriod($type, $data['due_date']);
            $created = GroupContributions::raise($type, $period, $data['due_date'], $data['label'] ?? null);
            $what = $data['label'] ?? $period;
        }
        GroupAudit::record((string) $request->user()->id, 'contribution_raised', $type->name . ' (' . $what . '): ' . $created . ' member(s)', 'contribution_type', $id);

        return response()->json(['success' => true, 'data' => ['created' => $created]]);
    }

    /** Who owes what: a page at a time, by state (owing, overdue, paid, exempt, all), contribution, period or member. */
    public function obligations(Request $request): JsonResponse
    {
        $data = $request->validate([
            'state' => ['nullable', Rule::in(['owing', 'overdue', 'paid', 'exempt', 'all'])],
            'type_id' => 'nullable|integer',
            'period' => 'nullable|string|max:30',
            'member_id' => 'nullable|integer',
            'q' => 'nullable|string|max:100',
            'page' => 'nullable|integer|min:1',
        ]);
        $today = now()->toDateString();
        $q = GroupContributions::query()
            ->when($data['type_id'] ?? null, fn ($w, $v) => $w->where('o.contribution_type_id', (int) $v))
            ->when($data['period'] ?? null, fn ($w, $v) => $w->where('o.period', $v))
            ->when($data['member_id'] ?? null, fn ($w, $v) => $w->where('o.member_id', (int) $v))
            ->when(trim((string) ($data['q'] ?? '')) !== '', fn ($w) => $w->where(fn ($x) => $x->where('m.full_name', 'like', '%' . trim((string) $data['q']) . '%')
                ->orWhere('m.member_number', 'like', '%' . trim((string) $data['q']) . '%')));
        $state = $data['state'] ?? 'owing';
        match ($state) {
            'owing' => GroupContributions::owing($q),
            'overdue' => GroupContributions::owing($q)->where('o.due_date', '<', $today),
            'paid' => $q->where('o.status', GroupContributions::OPEN)->whereRaw('COALESCE(p.paid, 0) >= o.amount_due'),
            'exempt' => $q->where('o.status', GroupContributions::EXEMPT),
            default => $q,
        };
        $total = (clone $q)->count();
        $page = (int) ($data['page'] ?? 1);
        $rows = $q->orderBy('o.due_date')->orderBy('m.full_name')->forPage($page, self::PAGE)->get();

        return response()->json([
            'success' => true,
            'data' => ['obligations' => $rows->map(fn ($o) => GroupContributions::payload($o, $today))->values()],
            'meta' => ['pagination' => ['page' => $page, 'per_page' => self::PAGE, 'total' => $total, 'has_more' => $page * self::PAGE < $total]],
        ]);
    }

    /** Excuse a member from what they owe (udhuru), with the reason. Nobody excuses themself. */
    public function exempt(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['reason' => 'required|string|min:3|max:255']);
        $o = DB::table('group_obligations')->where('id', $id)->first();
        if ($o === null) {
            return $this->fail('not_found', 'Deni la mchango halipo. / Not found.', 404);
        }
        $me = GroupAccess::member($request->user());
        if ($me !== null && (int) $me['id'] === (int) $o->member_id) {
            return $this->fail('own_obligation', 'Huwezi kujipa udhuru mwenyewe. / You cannot excuse yourself.', 403);
        }
        try {
            GroupContributions::exempt($id, (string) $request->user()->id, trim($data['reason']));
        } catch (InvalidArgumentException) {
            return $this->fail('not_owing', 'Hakuna kinachodaiwa hapa. / Nothing is owed here.', 409);
        }
        GroupAudit::record((string) $request->user()->id, 'obligation_exempted', 'Udhuru for obligation #' . $id . ': ' . trim($data['reason']), 'obligation', $id);

        return response()->json(['success' => true]);
    }

    // ---------------------------------------------------------------- promises

    public function promises(Request $request): JsonResponse
    {
        $request->validate(['member_id' => 'nullable|integer']);
        $today = now()->toDateString();
        $rows = GroupPromises::query()->where('p.status', 'open')
            ->when($request->query('member_id'), fn ($q, $m) => $q->where('p.member_id', (int) $m))
            ->orderBy('p.promised_on')->limit(200)->get();

        return response()->json(['success' => true, 'data' => ['promises' => $rows->map(fn ($p) => GroupPromises::payload($p, $today))->values()]]);
    }

    /** @return array<string, mixed> */
    private static function promiseRules(): array
    {
        return [
            'obligation_id' => 'nullable|integer',
            'amount' => 'required|numeric|min:1|max:1000000000',
            'promised_on' => 'required|date|after_or_equal:today',
            'note' => 'nullable|string|max:255',
        ];
    }

    /** Record a promise for [member] (a leader for a member, or a member for themself). */
    public static function promiseFor(Request $request, object|array $member, array $data): JsonResponse
    {
        $member = (object) $member;
        if (!empty($data['obligation_id'])) {
            $ok = DB::table('group_obligations')->where('id', (int) $data['obligation_id'])->where('member_id', $member->id)->exists();
            if (!$ok) {
                return response()->json(['success' => false, 'code' => 'obligation_required', 'message' => 'Chagua mchango wa mwanachama huyu. / Choose one of this member\'s contributions.'], 422);
            }
        }
        $id = (int) DB::table('group_promises')->insertGetId([
            'member_id' => (int) $member->id,
            'obligation_id' => empty($data['obligation_id']) ? null : (int) $data['obligation_id'],
            'amount' => round((float) $data['amount'], 2),
            'promised_on' => $data['promised_on'],
            'note' => $data['note'] ?? null,
            'status' => 'open',
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'promise_made', $member->full_name . ' promised ' . number_format((float) $data['amount']) . ' by ' . $data['promised_on'], 'promise', $id);

        return response()->json(['success' => true, 'data' => ['promise' => GroupPromises::payload(GroupPromises::query()->where('p.id', $id)->first())]], 201);
    }

    public function storePromise(Request $request): JsonResponse
    {
        $data = $request->validate(self::promiseRules() + ['member_id' => 'required|integer']);
        $member = DB::table('group_members')->where('id', (int) $data['member_id'])->whereIn('status', [GroupMembers::ACTIVE, GroupMembers::SUSPENDED])->first();
        if ($member === null) {
            return $this->fail('member_not_open', 'Mwanachama hayupo au si hai. / Member not found or not active.');
        }

        return self::promiseFor($request, $member, $data);
    }

    public function myPromise(Request $request): JsonResponse
    {
        $member = GroupAccess::member($request->user());
        if ($member === null || !in_array($member['status'], [GroupMembers::ACTIVE, GroupMembers::SUSPENDED], true)) {
            return $this->fail('member_not_open', 'Huna uanachama hai. / You have no active membership.');
        }

        return self::promiseFor($request, $member, $request->validate(self::promiseRules()));
    }

    /** Withdraw a promise: the member who made it, or a leader who records payments. */
    public function cancelPromise(Request $request, int $id): JsonResponse
    {
        $p = DB::table('group_promises')->where('id', $id)->first();
        if ($p === null || $p->status !== 'open') {
            return $this->fail('not_found', 'Ahadi haipo. / Promise not found.', 404);
        }
        $user = $request->user();
        $me = GroupAccess::member($user);
        $own = $me !== null && (int) $me['id'] === (int) $p->member_id;
        if (!$own && !GroupAccess::can($user, 'record_payments')) {
            return $this->fail('group_right_missing', 'Huna ruhusa. / Not allowed.', 403);
        }
        DB::table('group_promises')->where('id', $id)->update(['status' => 'cancelled', 'updated_at' => now()]);
        GroupAudit::record((string) $user->id, 'promise_cancelled', 'Promise #' . $id . ' withdrawn', 'promise', $id);

        return response()->json(['success' => true]);
    }

    // ---------------------------------------------------------------- statements

    /** The period asked for (?from=2026-01-01&to=2026-03-31); a bad or reversed pair is ignored (the whole history). @return array{0: ?string, 1: ?string} */
    private function period(Request $request): array
    {
        $ok = fn ($v) => is_string($v) && preg_match('/^\d{4}-\d{2}-\d{2}$/', $v) === 1 && strtotime($v) !== false;
        $from = $ok($request->query('from')) ? (string) $request->query('from') : null;
        $to = $ok($request->query('to')) ? (string) $request->query('to') : null;
        if ($from !== null && $to !== null && $from > $to) {
            return [null, null];
        }

        return [$from, $to];
    }

    public function statement(Request $request, int $id): JsonResponse
    {
        if (!DB::table('group_members')->where('id', $id)->exists()) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }
        [$from, $to] = $this->period($request);

        return response()->json(['success' => true, 'data' => GroupStatement::for($id, $from, $to)]);
    }

    public function myStatement(Request $request): JsonResponse
    {
        $member = GroupAccess::member($request->user());
        [$from, $to] = $this->period($request);

        return response()->json(['success' => true, 'data' => $member === null ? null : GroupStatement::for((int) $member['id'], $from, $to)]);
    }
}
