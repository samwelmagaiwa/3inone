<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupMembers;
use App\Support\Groups\GroupVotings;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Voting: many independent processes at once. Each one is an election for ONE position (its candidates) or a decision on ONE agenda
 * (approve / reject / abstain), with its own eligible voters, rules, dates, ballots, participation and result. A member votes once in each
 * process they may vote in and never twice in the same one; a secret ballot never records who chose what.
 *
 * Leaders with `manage_votings` prepare and run the processes; `publish_voting_results` announces a result; `view_voting_reports` reads the
 * reports. A candidate never runs, closes, cancels or announces the process they stand in. Members only vote, see the processes and read what
 * the process's own rules allow them to read.
 */
class GroupVotingController extends Controller
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

    private function find(int $id): ?object
    {
        $v = GroupVotings::find($id);

        return $v === null ? null : GroupVotings::sync($v);
    }

    private function missing(): JsonResponse
    {
        return $this->fail('not_found', 'Kura haipo. / Voting not found.', 404);
    }

    /** A candidate may not run, close, cancel or announce the process they stand in. */
    private function conflict(Request $request, object $v): ?JsonResponse
    {
        if (GroupVotings::isCandidate($v, $this->myId($request))) {
            return $this->fail('candidate_conflict', 'Huwezi kusimamia kura unayogombea. / You cannot run a voting you stand in.', 403);
        }

        return null;
    }

    // ---------------------------------------------------------------- reading

    /** @return array<string, mixed> */
    private function payload(object $v, Request $request, bool $detail): array
    {
        $user = $request->user();
        $mid = $this->myId($request);
        $manage = GroupAccess::can($user, 'manage_votings');
        $reports = GroupAccess::can($user, 'view_voting_reports');
        $options = DB::table('group_voting_options')->where('voting_id', $v->id)->orderBy('sort')->orderBy('id')->get();

        $eligible = $v->status === 'draft' ? $this->draftEligible($v) : GroupVotings::isEligible($v, $mid);
        $voted = GroupVotings::hasVoted($v, $mid);
        $open = $v->status === 'open';
        $myChoice = null;
        if ($voted && !$v->secret && $mid !== null) {
            $myChoice = DB::table('group_ballots')->where('voting_id', $v->id)->where('member_id', $mid)->value('option_id');
        }
        $myState = match (true) {
            $v->status === 'draft' => 'draft',
            $mid === null => 'not_a_member',
            !$eligible && $v->status !== 'draft' => 'not_eligible',
            $voted => 'voted',
            $open => 'pending',
            default => $v->status === 'scheduled' ? 'not_open' : 'over',
        };

        $out = [
            'id' => (int) $v->id, 'reference' => $v->reference, 'series' => $v->series, 'category' => $v->category, 'kind' => $v->kind,
            'title' => $v->title, 'description' => $v->description, 'position' => $v->position, 'target' => GroupVotings::target($v),
            'eligibility' => $v->eligibility, 'quorum_percent' => (float) $v->quorum_percent, 'threshold_percent' => (float) $v->threshold_percent,
            'secret' => (bool) $v->secret, 'allow_change' => (bool) $v->allow_change, 'show_progress' => (bool) $v->show_progress, 'results_visibility' => $v->results_visibility,
            'opens_at' => $v->opens_at === null ? null : (string) $v->opens_at, 'closes_at' => $v->closes_at === null ? null : (string) $v->closes_at,
            'status' => $v->status, 'cancel_reason' => $v->cancel_reason, 'closed_at' => $v->closed_at === null ? null : (string) $v->closed_at,
            'eligible_count' => $v->status === 'draft' ? count($this->draftEligibleIds($v)) : (int) $v->eligible_count,
            'results_published' => $v->results_published_at !== null, 'results_published_at' => $v->results_published_at === null ? null : (string) $v->results_published_at,
            'my' => ['eligible' => $eligible, 'voted' => $voted, 'state' => $myState, 'can_vote' => $open && $eligible && (!$voted || ($v->allow_change && !$v->secret)), 'choice' => $myChoice],
            'buckets' => $this->buckets($v, $myState),
            'options' => $options->map(fn ($o) => ['id' => (int) $o->id, 'label' => $o->label, 'description' => $o->description, 'member_id' => $o->member_id === null ? null : (int) $o->member_id, 'role' => $o->role])->all(),
            'can_manage' => $manage, 'can_report' => $reports,
        ];

        if ($manage || $v->show_progress) {
            $turnout = (int) DB::table('group_voting_turnout')->where('voting_id', $v->id)->count();
            $out['progress'] = ['turnout' => $turnout, 'eligible' => $out['eligible_count'], 'percent' => $out['eligible_count'] === 0 ? 0.0 : round($turnout * 100 / $out['eligible_count'], 1)];
        } else {
            $out['progress'] = null;
        }
        $out['results'] = GroupVotings::resultsVisible($v, $reports) ? GroupVotings::results($v) : null;
        if ($out['results'] !== null && $v->status === 'closed') {
            $out['decision'] = $v->decision;
            $out['winner_option_id'] = $v->winner_option_id === null ? null : (int) $v->winner_option_id;
        }

        return $out;
    }

    /** @return array<int, string> */
    private function buckets(object $v, string $myState): array
    {
        $b = [];
        if (in_array($v->status, ['open', 'paused'], true)) {
            $b[] = 'active';
        }
        if ($v->status === 'scheduled') {
            $b[] = 'upcoming';
        }
        if ($v->status === 'open' && $myState === 'pending') {
            $b[] = 'pending';
        }
        if ($v->status === 'closed' && $v->results_published_at !== null) {
            $b[] = 'completed';
        }
        if (($v->status === 'closed' && $v->results_published_at === null) || $v->status === 'cancelled') {
            $b[] = 'closed';
        }
        if ($v->status === 'draft') {
            $b[] = 'draft';
        }

        return $b;
    }

    /** @return array<int, int> */
    private function draftEligibleIds(object $v): array
    {
        $selected = $v->eligibility === 'selected' ? DB::table('group_voting_eligible')->where('voting_id', $v->id)->pluck('member_id')->all() : [];

        return GroupVotings::eligibleIds($v->eligibility, $selected);
    }

    private function draftEligible(object $v): bool
    {
        return false;
    }

    public function index(Request $request): JsonResponse
    {
        $manage = GroupAccess::can($request->user(), 'manage_votings');
        $rows = DB::table('group_votings')->when(!$manage, fn ($q) => $q->where('status', '!=', 'draft'))->orderByDesc('id')->limit(300)->get();
        $list = $rows->map(fn ($v) => $this->payload($this->sync($v), $request, false))->values();

        return response()->json(['success' => true, 'data' => ['votings' => $list, 'can_manage' => $manage, 'can_report' => GroupAccess::can($request->user(), 'view_voting_reports')]]);
    }

    private function sync(object $v): object
    {
        return GroupVotings::sync($v);
    }

    public function show(Request $request, int $id): JsonResponse
    {
        $v = $this->find($id);
        if ($v === null || ($v->status === 'draft' && !GroupAccess::can($request->user(), 'manage_votings'))) {
            return $this->missing();
        }

        return response()->json(['success' => true, 'data' => ['voting' => $this->payload($v, $request, true)]]);
    }

    // ---------------------------------------------------------------- preparing

    /** @return array<string, mixed> */
    private function rules(): array
    {
        return [
            'title' => 'required|string|min:3|max:150',
            'category' => ['required', Rule::in(GroupVotings::CATEGORIES)],
            'kind' => ['required', Rule::in(GroupVotings::KINDS)],
            'series' => 'nullable|string|max:120',
            'description' => 'nullable|string|max:5000',
            'position' => 'nullable|string|min:2|max:100|required_if:kind,election',
            'eligibility' => ['required', Rule::in(GroupVotings::ELIGIBILITY)],
            'member_ids' => 'nullable|array|max:2000|required_if:eligibility,selected',
            'member_ids.*' => 'integer',
            'quorum_percent' => 'nullable|numeric|min:0|max:100',
            'threshold_percent' => 'nullable|numeric|min:1|max:100',
            'secret' => 'nullable|boolean',
            'allow_change' => 'nullable|boolean',
            'show_progress' => 'nullable|boolean',
            'results_visibility' => ['nullable', Rule::in(GroupVotings::VISIBILITY)],
            'opens_at' => 'required|date',
            'closes_at' => 'required|date|after:opens_at',
            'options' => 'nullable|array|max:30',
            'options.*.label' => 'required|string|min:2|max:150',
            'options.*.description' => 'nullable|string|max:1000',
            'options.*.member_id' => 'nullable|integer',
        ];
    }

    /** Writes a draft (new, or the one being changed) and its options. */
    private function save(Request $request, ?object $existing): JsonResponse
    {
        $data = $request->validate($this->rules());
        $secret = (bool) ($data['secret'] ?? true);
        $change = (bool) ($data['allow_change'] ?? false);
        if ($secret && $change) {
            return $this->fail('secret_no_change', 'Kura ya siri haiwezi kubadilishwa baada ya kupigwa. / A secret ballot cannot be changed once cast.');
        }
        $options = $data['kind'] === 'election' ? array_values($data['options'] ?? []) : [];
        if ($data['kind'] === 'election') {
            if (count($options) < 2) {
                return $this->fail('candidates_needed', 'Weka angalau wagombea wawili. / Give at least two candidates.');
            }
            $ids = array_filter(array_map(fn ($o) => $o['member_id'] ?? null, $options));
            if (count($ids) !== count(array_unique($ids))) {
                return $this->fail('candidate_twice', 'Mgombea mmoja amewekwa mara mbili. / A candidate is listed twice.');
            }
            if ($ids !== [] && DB::table('group_members')->whereIn('id', $ids)->where('status', GroupMembers::ACTIVE)->count() !== count($ids)) {
                return $this->fail('candidate_not_member', 'Mgombea lazima awe mwanachama hai. / A candidate must be an active member.');
            }
        }

        $row = [
            'series' => isset($data['series']) && trim($data['series']) !== '' ? trim($data['series']) : null, 'category' => $data['category'], 'kind' => $data['kind'],
            'title' => trim($data['title']), 'description' => $data['description'] ?? null, 'position' => $data['kind'] === 'election' ? trim((string) $data['position']) : null,
            'eligibility' => $data['eligibility'], 'quorum_percent' => round((float) ($data['quorum_percent'] ?? 0), 2), 'threshold_percent' => round((float) ($data['threshold_percent'] ?? 50), 2),
            'secret' => $secret, 'allow_change' => $change, 'show_progress' => (bool) ($data['show_progress'] ?? true), 'results_visibility' => $data['results_visibility'] ?? 'after_close',
            'opens_at' => $data['opens_at'], 'closes_at' => $data['closes_at'], 'updated_at' => now(),
        ];

        $id = DB::transaction(function () use ($existing, $row, $data, $options, $request) {
            if ($existing === null) {
                do {
                    $ref = 'VT-' . strtoupper(Str::random(6));
                } while (DB::table('group_votings')->where('reference', $ref)->exists());
                $id = (int) DB::table('group_votings')->insertGetId($row + ['reference' => $ref, 'status' => 'draft', 'created_by' => (string) $request->user()->id, 'created_at' => now()]);
            } else {
                $id = (int) $existing->id;
                DB::table('group_votings')->where('id', $id)->update($row);
                DB::table('group_voting_options')->where('voting_id', $id)->delete();
            }
            if ($data['kind'] === 'election') {
                foreach ($options as $i => $o) {
                    DB::table('group_voting_options')->insert(['voting_id' => $id, 'label' => trim($o['label']), 'description' => $o['description'] ?? null, 'member_id' => $o['member_id'] ?? null, 'role' => null, 'sort' => $i, 'created_at' => now(), 'updated_at' => now()]);
                }
            } else {
                $i = 0;
                foreach (GroupVotings::DECISION_ROLES as $role => [$label]) {
                    DB::table('group_voting_options')->insert(['voting_id' => $id, 'label' => $label, 'description' => null, 'member_id' => null, 'role' => $role, 'sort' => $i++, 'created_at' => now(), 'updated_at' => now()]);
                }
            }
            // The chosen voters of a 'selected' process are kept (as a draft list) until it is published.
            DB::table('group_voting_eligible')->where('voting_id', $id)->delete();
            if ($data['eligibility'] === 'selected') {
                foreach (array_unique(array_map('intval', $data['member_ids'] ?? [])) as $m) {
                    DB::table('group_voting_eligible')->insert(['voting_id' => $id, 'member_id' => $m]);
                }
            }

            return $id;
        });

        $v = GroupVotings::find($id);
        GroupAudit::record((string) $request->user()->id, $existing === null ? 'voting_created' : 'voting_updated', $v->reference . ': ' . GroupVotings::target($v), 'voting', $id);

        return response()->json(['success' => true, 'data' => ['voting' => $this->payload($v, $request, true)]], $existing === null ? 201 : 200);
    }

    public function store(Request $request): JsonResponse
    {
        return $this->save($request, null);
    }

    public function update(Request $request, int $id): JsonResponse
    {
        $v = $this->find($id);
        if ($v === null) {
            return $this->missing();
        }
        if ($v->status !== 'draft') {
            return $this->fail('not_draft', 'Kura iliyochapishwa haibadilishwi; ahirisha au ghairi. / A published voting is not edited; extend or cancel it.', 409);
        }

        return $this->conflict($request, $v) ?? $this->save($request, $v);
    }

    public function destroy(Request $request, int $id): JsonResponse
    {
        $v = $this->find($id);
        if ($v === null) {
            return $this->missing();
        }
        if ($v->status !== 'draft') {
            return $this->fail('not_draft', 'Rasimu tu ndiyo inafutwa. / Only a draft is deleted.', 409);
        }
        DB::transaction(function () use ($id) {
            foreach (['group_voting_options', 'group_voting_eligible'] as $t) {
                DB::table($t)->where('voting_id', $id)->delete();
            }
            DB::table('group_votings')->where('id', $id)->delete();
        });
        GroupAudit::record((string) $request->user()->id, 'voting_deleted', 'Draft ' . $v->reference . ' deleted', 'voting', $id);

        return response()->json(['success' => true, 'data' => ['deleted' => true]]);
    }

    // ---------------------------------------------------------------- running

    public function publish(Request $request, int $id): JsonResponse
    {
        $v = $this->find($id);
        if ($v === null) {
            return $this->missing();
        }
        if ($c = $this->conflict($request, $v)) {
            return $c;
        }
        if ($v->status !== 'draft') {
            return $this->fail('not_draft', 'Kura hii tayari imechapishwa. / This voting is already published.', 409);
        }
        if (Carbon::parse($v->closes_at)->lte(now())) {
            return $this->fail('deadline_passed', 'Tarehe ya kufunga imepita; ibadilishe kwanza. / The closing time has passed; change it first.');
        }
        if (DB::table('group_voting_options')->where('voting_id', $id)->count() < 2) {
            return $this->fail('candidates_needed', 'Weka chaguo angalau mbili. / Give at least two options.');
        }
        $selected = $v->eligibility === 'selected' ? DB::table('group_voting_eligible')->where('voting_id', $id)->pluck('member_id')->all() : [];
        if (GroupVotings::snapshotEligible($v, $selected) === 0) {
            return $this->fail('no_voters', 'Hakuna mwanachama anayeruhusiwa kupiga kura hii. / No member may vote in this one.');
        }
        $opensNow = Carbon::parse($v->opens_at)->lte(now());
        DB::table('group_votings')->where('id', $id)->update(['status' => $opensNow ? 'open' : 'scheduled', 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'voting_published', $v->reference . ': ' . GroupVotings::target($v) . ($opensNow ? ' (open)' : ' (opens ' . $v->opens_at . ')'), 'voting', $id);
        $v = GroupVotings::find($id);
        if ($opensNow) {
            GroupVotings::notifyEligible($v, 'voting_open', 'Kura ya ' . GroupVotings::target($v) . ' imefunguliwa', 'Voting on ' . GroupVotings::target($v) . ' is now open',
                'Piga kura yako kabla ya ' . Carbon::parse($v->closes_at)->format('d/m/Y H:i') . '.', 'Cast your vote before ' . Carbon::parse($v->closes_at)->format('d/m/Y H:i') . '.');
        } else {
            GroupVotings::notifyEligible($v, 'voting_new', 'Kura mpya: ' . GroupVotings::target($v), 'New voting: ' . GroupVotings::target($v),
                'Itafunguliwa ' . Carbon::parse($v->opens_at)->format('d/m/Y H:i') . '.', 'It opens ' . Carbon::parse($v->opens_at)->format('d/m/Y H:i') . '.');
        }

        return response()->json(['success' => true, 'data' => ['voting' => $this->payload(GroupVotings::sync($v), $request, true)]]);
    }

    /** Pause, resume, close or cancel: one entry point, each with its own rule. */
    private function move(Request $request, int $id, string $action): JsonResponse
    {
        $v = $this->find($id);
        if ($v === null) {
            return $this->missing();
        }
        if ($c = $this->conflict($request, $v)) {
            return $c;
        }
        $by = (string) $request->user()->id;
        switch ($action) {
            case 'pause':
                if ($v->status !== 'open') {
                    return $this->fail('wrong_status', 'Ni kura iliyo wazi tu inasimamishwa. / Only an open voting is paused.', 409);
                }
                DB::table('group_votings')->where('id', $id)->update(['status' => 'paused', 'updated_at' => now()]);
                GroupAudit::record($by, 'voting_paused', $v->reference . ' paused', 'voting', $id);
                break;
            case 'resume':
                if ($v->status !== 'paused') {
                    return $this->fail('wrong_status', 'Ni kura iliyosimamishwa tu inaendelezwa. / Only a paused voting is resumed.', 409);
                }
                if (Carbon::parse($v->closes_at)->lte(now())) {
                    return $this->fail('deadline_passed', 'Muda wa kufunga umepita; uongeze kwanza. / The closing time has passed; extend it first.');
                }
                DB::table('group_votings')->where('id', $id)->update(['status' => 'open', 'updated_at' => now()]);
                GroupAudit::record($by, 'voting_resumed', $v->reference . ' resumed', 'voting', $id);
                break;
            case 'close':
                if (!in_array($v->status, ['open', 'paused'], true)) {
                    return $this->fail('wrong_status', 'Ni kura iliyo wazi tu inafungwa. / Only an open voting is closed.', 409);
                }
                GroupVotings::close($v, $by);
                break;
            case 'cancel':
                $data = $request->validate(['reason' => 'required|string|min:3|max:255']);
                if (!in_array($v->status, ['draft', 'scheduled', 'open', 'paused'], true)) {
                    return $this->fail('wrong_status', 'Kura hii haiwezi kughairiwa tena. / This voting can no longer be cancelled.', 409);
                }
                DB::table('group_votings')->where('id', $id)->update(['status' => 'cancelled', 'cancel_reason' => trim($data['reason']), 'updated_at' => now()]);
                GroupAudit::record($by, 'voting_cancelled', $v->reference . ' cancelled: ' . trim($data['reason']), 'voting', $id);
                GroupVotings::notifyEligible($v, 'voting_closed', 'Kura ya ' . GroupVotings::target($v) . ' imeghairiwa', 'Voting on ' . GroupVotings::target($v) . ' was cancelled',
                    trim($data['reason']), trim($data['reason']));
                break;
        }

        return response()->json(['success' => true, 'data' => ['voting' => $this->payload(GroupVotings::find($id), $request, true)]]);
    }

    public function pause(Request $request, int $id): JsonResponse
    {
        return $this->move($request, $id, 'pause');
    }

    public function resume(Request $request, int $id): JsonResponse
    {
        return $this->move($request, $id, 'resume');
    }

    public function close(Request $request, int $id): JsonResponse
    {
        return $this->move($request, $id, 'close');
    }

    public function cancel(Request $request, int $id): JsonResponse
    {
        return $this->move($request, $id, 'cancel');
    }

    /** Moves the closing time later (never earlier than now); for a voting that has not closed. */
    public function extend(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['closes_at' => 'required|date|after:now']);
        $v = $this->find($id);
        if ($v === null) {
            return $this->missing();
        }
        if ($c = $this->conflict($request, $v)) {
            return $c;
        }
        if (!in_array($v->status, ['scheduled', 'open', 'paused'], true)) {
            return $this->fail('wrong_status', 'Kura iliyofungwa haiongezwi muda. / A closed voting cannot be extended.', 409);
        }
        if (Carbon::parse($data['closes_at'])->lte(Carbon::parse($v->opens_at))) {
            return $this->fail('bad_dates', 'Kufunga lazima kuwe baada ya kufungua. / It must close after it opens.');
        }
        DB::table('group_votings')->where('id', $id)->update(['closes_at' => $data['closes_at'], 'closing_notified_at' => null, 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'voting_extended', $v->reference . ' now closes ' . $data['closes_at'], 'voting', $id);

        return response()->json(['success' => true, 'data' => ['voting' => $this->payload(GroupVotings::find($id), $request, true)]]);
    }

    /** The chair announces the final result of a closed voting. */
    public function publishResults(Request $request, int $id): JsonResponse
    {
        $v = $this->find($id);
        if ($v === null) {
            return $this->missing();
        }
        if ($c = $this->conflict($request, $v)) {
            return $c;
        }
        if ($v->status !== 'closed') {
            return $this->fail('not_closed', 'Matokeo yanatangazwa kura ikishafungwa. / Results are announced once the voting has closed.', 409);
        }
        if ($v->results_published_at !== null) {
            return $this->fail('already_published', 'Matokeo yametangazwa tayari. / The results are already announced.', 409);
        }
        DB::table('group_votings')->where('id', $id)->update(['results_published_at' => now(), 'results_published_by' => (string) $request->user()->id, 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'voting_results_published', $v->reference . ': ' . $v->decision, 'voting', $id);
        GroupVotings::notifyEligible($v, 'voting_results', 'Matokeo ya ' . GroupVotings::target($v), 'Results: ' . GroupVotings::target($v), 'Matokeo yametangazwa.', 'The results have been announced.');

        return response()->json(['success' => true, 'data' => ['voting' => $this->payload(GroupVotings::find($id), $request, true)]]);
    }

    // ---------------------------------------------------------------- voting

    public function vote(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['option_id' => 'required|integer']);
        $v = $this->find($id);
        if ($v === null || $v->status === 'draft') {
            return $this->missing();
        }
        $mid = $this->myId($request);
        if ($mid === null) {
            return $this->fail('not_a_member', 'Ni wanachama tu wanaopiga kura. / Only members vote.', 403);
        }
        if ($v->status !== 'open') {
            $why = ['scheduled' => 'Kura haijafunguliwa. / This voting has not opened yet.', 'paused' => 'Kura imesimamishwa. / This voting is paused.', 'closed' => 'Kura imefungwa. / This voting is closed.', 'cancelled' => 'Kura imeghairiwa. / This voting was cancelled.'];

            return $this->fail('not_open', $why[$v->status] ?? 'Kura haiko wazi. / This voting is not open.', 409);
        }
        if (!GroupVotings::isEligible($v, $mid)) {
            return $this->fail('not_eligible', 'Huruhusiwi kupiga kura hii. / You may not vote in this one.', 403);
        }
        $option = DB::table('group_voting_options')->where('id', (int) $data['option_id'])->where('voting_id', $id)->first();
        if ($option === null) {
            return $this->fail('bad_option', 'Chaguo hili si la kura hii. / That option does not belong to this voting.');
        }

        if (GroupVotings::hasVoted($v, $mid)) {
            if (!$v->allow_change || $v->secret) {
                return $this->fail('already_voted', 'Umeshapiga kura hii. / You have already voted in this one.', 409);
            }
            DB::table('group_ballots')->where('voting_id', $id)->where('member_id', $mid)->update(['option_id' => (int) $option->id, 'cast_on' => now()->toDateString()]);
            GroupAudit::record((string) $request->user()->id, 'vote_changed', 'Vote changed in ' . $v->reference, 'voting', $id);
        } else {
            try {
                DB::transaction(function () use ($v, $mid, $option) {
                    DB::table('group_voting_turnout')->insert(['voting_id' => $v->id, 'member_id' => $mid, 'voted_on' => now()->toDateString()]);
                    DB::table('group_ballots')->insert(['id' => (string) Str::uuid(), 'voting_id' => $v->id, 'option_id' => (int) $option->id, 'member_id' => $v->secret ? null : $mid, 'cast_on' => now()->toDateString()]);
                });
            } catch (\Illuminate\Database\QueryException $e) {
                if (str_starts_with((string) $e->getCode(), '23')) {
                    return $this->fail('already_voted', 'Umeshapiga kura hii. / You have already voted in this one.', 409);
                }
                throw $e;
            }
            // The audit says that a vote was cast, never for whom.
            GroupAudit::record((string) $request->user()->id, 'vote_cast', 'Vote cast in ' . $v->reference, 'voting', $id);
            GroupVotings::notify([$mid], 'voting_voted', 'Umepiga kura: ' . GroupVotings::target($v), 'You voted: ' . GroupVotings::target($v), 'Asante kwa kushiriki.', 'Thank you for taking part.', (int) $v->id);
        }

        return response()->json(['success' => true, 'data' => ['voting' => $this->payload(GroupVotings::find($id), $request, true), 'chosen' => ['option_id' => (int) $option->id, 'label' => $option->label]]], 201);
    }

    // ---------------------------------------------------------------- reports

    /** @return array<string, mixed> */
    private function report(object $v, Request $request): array
    {
        $results = GroupVotings::results($v);
        $turnout = DB::table('group_voting_turnout as t')->join('group_members as m', 'm.id', '=', 't.member_id')->where('t.voting_id', $v->id)->orderBy('m.full_name')->get(['m.id', 'm.full_name', 'm.member_number', 't.voted_on']);
        $eligible = DB::table('group_voting_eligible as e')->join('group_members as m', 'm.id', '=', 'e.member_id')->where('e.voting_id', $v->id)->get(['m.id', 'm.full_name', 'm.member_number']);
        $votedIds = $turnout->pluck('id')->all();
        $individual = null;
        if (!$v->secret && $v->status === 'closed') {
            $labels = DB::table('group_voting_options')->where('voting_id', $v->id)->pluck('label', 'id');
            $individual = DB::table('group_ballots as b')->join('group_members as m', 'm.id', '=', 'b.member_id')->where('b.voting_id', $v->id)->orderBy('m.full_name')
                ->get(['m.full_name', 'm.member_number', 'b.option_id', 'b.cast_on'])
                ->map(fn ($b) => ['member_number' => $b->member_number, 'name' => $b->full_name, 'option' => $labels[$b->option_id] ?? '', 'date' => (string) $b->cast_on])->values()->all();
        }

        return [
            'voting' => $this->payload($v, $request, true),
            'results' => $results,
            'decision' => $v->status === 'closed' ? $v->decision : $results['decision'],
            'turnout' => $turnout->map(fn ($t) => ['member_number' => $t->member_number, 'name' => $t->full_name, 'date' => (string) $t->voted_on])->values()->all(),
            'not_voted' => $eligible->filter(fn ($m) => !in_array($m->id, $votedIds, true))->map(fn ($m) => ['member_number' => $m->member_number, 'name' => $m->full_name])->values()->all(),
            'individual' => $individual,
            'secret' => (bool) $v->secret,
            'final' => $v->status === 'closed',
        ];
    }

    public function reportShow(Request $request, int $id): JsonResponse
    {
        $v = $this->find($id);
        if ($v === null || $v->status === 'draft') {
            return $this->missing();
        }

        return response()->json(['success' => true, 'data' => $this->report($v, $request)]);
    }

    /** The report as a CSV: individual votes when the ballot is open and closed, otherwise the counts only. */
    public function reportCsv(Request $request, int $id): StreamedResponse|JsonResponse
    {
        $v = $this->find($id);
        if ($v === null || $v->status === 'draft') {
            return $this->missing();
        }
        $r = $this->report($v, $request);
        GroupAudit::record((string) $request->user()->id, 'voting_report_exported', $v->reference . ' report exported', 'voting', $id);
        $rows = [['Reference', $v->reference], ['Target', GroupVotings::target($v)], ['Status', $v->status], ['Decision', (string) $r['decision']],
            ['Eligible', $r['results']['eligible']], ['Voted', $r['results']['turnout']], ['Participation %', $r['results']['participation_percent']], [], ['Option', 'Votes', 'Percent']];
        foreach ($r['results']['options'] as $o) {
            $rows[] = [$o['label'], $o['votes'], $o['percent']];
        }
        if ($r['individual'] !== null) {
            $rows[] = [];
            $rows[] = ['Member number', 'Name', 'Chose', 'Date'];
            foreach ($r['individual'] as $i) {
                $rows[] = [$i['member_number'], $i['name'], $i['option'], $i['date']];
            }
        }

        return response()->streamDownload(function () use ($rows) {
            $out = fopen('php://output', 'w');
            foreach ($rows as $row) {
                // A cell that starts like a formula is written as text: an export must never run anything in a spreadsheet.
                fputcsv($out, array_map(fn ($c) => is_string($c) && $c !== '' && in_array($c[0], ['=', '+', '-', '@', "\t", "\r"], true) ? "'" . $c : $c, $row));
            }
            fclose($out);
        }, 'voting-' . Str::slug($v->reference) . '.csv', ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    // ---------------------------------------------------------------- notifications

    public function notifications(Request $request): JsonResponse
    {
        $mid = $this->myId($request);
        $rows = $mid === null ? collect() : DB::table('group_notifications')->where('member_id', $mid)->orderByDesc('id')->limit(100)->get();
        // In ME the leaders' notices (a membership request waiting for the management) are not shown: they belong to the office, not the member.
        if (\App\Support\Groups\GroupAccess::asMember($request->user())) {
            $rows = $rows->reject(fn ($n) => str_starts_with((string) $n->kind, 'member_'))->values();
        }

        return response()->json(['success' => true, 'data' => [
            'notifications' => $rows->map(fn ($n) => ['id' => (int) $n->id, 'kind' => $n->kind, 'title' => $n->title, 'title_en' => $n->title_en, 'body' => $n->body, 'body_en' => $n->body_en,
                'link_type' => $n->link_type, 'link_id' => $n->link_id === null ? null : (int) $n->link_id, 'read' => $n->read_at !== null, 'created_at' => (string) $n->created_at])->values(),
            'unread' => $rows->whereNull('read_at')->count(),
        ]]);
    }

    public function readNotifications(Request $request): JsonResponse
    {
        $data = $request->validate(['ids' => 'nullable|array|max:200', 'ids.*' => 'integer', 'all' => 'nullable|boolean']);
        $mid = $this->myId($request);
        if ($mid !== null) {
            DB::table('group_notifications')->where('member_id', $mid)->whereNull('read_at')
                ->when(!($data['all'] ?? false), fn ($q) => $q->whereIn('id', array_map('intval', $data['ids'] ?? [])))->update(['read_at' => now()]);
        }

        return $this->notifications($request);
    }
}
