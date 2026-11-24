<?php

namespace App\Support\Groups;

use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * The rules of voting, in one place. Every voting process is independent: its own target, eligible voters, options, rules, dates, ballots and
 * result. Nothing here ever adds up ballots, turnout or results across processes.
 *
 *   draft -> scheduled (published, not yet open) -> open -> closed;  open <-> paused;  draft/scheduled/open/paused -> cancelled
 *
 * A scheduled process opens and an open one closes by itself when its date passes ({@see self::sync()}); nothing counts after it is closed or
 * cancelled. Eligible voters are fixed when the process is published. In a secret ballot the ballot never carries the voter.
 */
final class GroupVotings
{
    public const CATEGORIES = ['leadership', 'project', 'financial', 'policy', 'proposal', 'general'];

    public const KINDS = ['election', 'decision'];

    /** Every active member votes whatever their office; a voting may be limited to chosen members (a committee's own matter). */
    public const ELIGIBILITY = ['active', 'selected'];

    public const VISIBILITY = ['live', 'after_close', 'after_publish'];

    /** The answers of a decision (an agenda): the fixed options every decision has. */
    public const DECISION_ROLES = ['approve' => ['Ndiyo / Approve', 'approve'], 'reject' => ['Hapana / Reject', 'reject'], 'abstain' => ['Sipigi / Abstain', 'abstain']];

    public static function find(int $id): ?object
    {
        return DB::table('group_votings')->where('id', $id)->first();
    }

    /** @return array<int, int> the members who may vote in a process with this eligibility ([selected] is the chosen list for 'selected') */
    public static function eligibleIds(string $eligibility, array $selected = []): array
    {
        $q = DB::table('group_members')->where('status', GroupMembers::ACTIVE);
        if ($eligibility === 'selected') {
            $q->whereIn('id', array_map('intval', $selected));
        }

        return $q->pluck('id')->map(fn ($v) => (int) $v)->all();
    }

    /** Fixes who may vote in this process (what a member's status was when it was published). */
    public static function snapshotEligible(object $v, array $selected = []): int
    {
        DB::table('group_voting_eligible')->where('voting_id', $v->id)->delete();
        $ids = self::eligibleIds($v->eligibility, $selected);
        foreach (array_chunk($ids, 200) as $chunk) {
            DB::table('group_voting_eligible')->insert(array_map(fn ($m) => ['voting_id' => $v->id, 'member_id' => $m], $chunk));
        }
        DB::table('group_votings')->where('id', $v->id)->update(['eligible_count' => count($ids), 'updated_at' => now()]);

        return count($ids);
    }

    public static function isEligible(object $v, ?int $memberId): bool
    {
        return $memberId !== null && DB::table('group_voting_eligible')->where('voting_id', $v->id)->where('member_id', $memberId)->exists();
    }

    public static function hasVoted(object $v, ?int $memberId): bool
    {
        return $memberId !== null && DB::table('group_voting_turnout')->where('voting_id', $v->id)->where('member_id', $memberId)->exists();
    }

    /** Is [memberId] one of the candidates of this process? (A candidate never runs the process they stand in.) */
    public static function isCandidate(object $v, ?int $memberId): bool
    {
        return $memberId !== null && DB::table('group_voting_options')->where('voting_id', $v->id)->where('member_id', $memberId)->exists();
    }

    // ------------------------------------------------------------------------------------------------ time

    /** Opens a scheduled process whose time has come, closes an open one past its deadline. Returns the fresh row. */
    public static function sync(object $v): object
    {
        $now = now();
        if ($v->status === 'scheduled' && $v->opens_at !== null && Carbon::parse($v->opens_at)->lte($now)) {
            DB::table('group_votings')->where('id', $v->id)->where('status', 'scheduled')->update(['status' => 'open', 'updated_at' => $now]);
            GroupAudit::record(null, 'voting_opened', $v->reference . ' opened', 'voting', (int) $v->id);
            self::notifyEligible($v, 'voting_open', 'Kura ya ' . self::target($v) . ' imefunguliwa', 'Voting on ' . self::target($v) . ' is now open',
                'Piga kura yako kabla ya ' . self::when($v->closes_at) . '.', 'Cast your vote before ' . self::when($v->closes_at) . '.');
            $v = self::find((int) $v->id);
        }
        if ($v->status === 'open' && $v->closes_at !== null && Carbon::parse($v->closes_at)->lte($now)) {
            self::close($v, null);
            $v = self::find((int) $v->id);
        }

        return $v;
    }

    /** Syncs every process that can still change with time (the daily job). */
    public static function syncAll(): int
    {
        $n = 0;
        foreach (DB::table('group_votings')->whereIn('status', ['scheduled', 'open'])->get() as $v) {
            $after = self::sync($v);
            $n += $after->status !== $v->status ? 1 : 0;
        }

        return $n;
    }

    /** Tells the eligible members who have not voted yet that a process closes within a day (once). */
    public static function remindClosing(): int
    {
        $n = 0;
        foreach (DB::table('group_votings')->where('status', 'open')->whereNull('closing_notified_at')->whereBetween('closes_at', [now(), now()->addDay()])->get() as $v) {
            DB::table('group_votings')->where('id', $v->id)->update(['closing_notified_at' => now()]);
            $voted = DB::table('group_voting_turnout')->where('voting_id', $v->id)->pluck('member_id')->all();
            $to = array_values(array_diff(DB::table('group_voting_eligible')->where('voting_id', $v->id)->pluck('member_id')->map(fn ($i) => (int) $i)->all(), array_map('intval', $voted)));
            self::notify($to, 'voting_closing', 'Kura ya ' . self::target($v) . ' inafungwa kesho', 'Voting on ' . self::target($v) . ' closes tomorrow',
                'Bado hujapiga kura. Inafungwa ' . self::when($v->closes_at) . '.', 'You have not voted yet. It closes ' . self::when($v->closes_at) . '.', (int) $v->id);
            $n++;
        }

        return $n;
    }

    /** Closes a process (its time is up, or an administrator closed it) and works out its decision. */
    public static function close(object $v, ?string $userId): void
    {
        $res = self::results($v);
        DB::table('group_votings')->where('id', $v->id)->whereIn('status', ['open', 'paused'])->update([
            'status' => 'closed', 'closed_at' => now(), 'decision' => $res['decision'], 'winner_option_id' => $res['winner_option_id'], 'updated_at' => now(),
        ]);
        GroupAudit::record($userId, 'voting_closed', $v->reference . ' closed: ' . $res['decision'] . ' (' . $res['turnout'] . ' of ' . $res['eligible'] . ' voted)', 'voting', (int) $v->id);
        self::notifyEligible($v, 'voting_closed', 'Kura ya ' . self::target($v) . ' imefungwa', 'Voting on ' . self::target($v) . ' has closed',
            'Kura zimefungwa. Matokeo yatatangazwa na viongozi.', 'Voting is over. The results will be announced by the leaders of the group.');
    }

    // ------------------------------------------------------------------------------------------------ results

    /**
     * The result of ONE process, from its own ballots only.
     *
     * @return array<string, mixed>
     */
    public static function results(object $v): array
    {
        $options = DB::table('group_voting_options')->where('voting_id', $v->id)->orderBy('sort')->orderBy('id')->get();
        $counts = DB::table('group_ballots')->where('voting_id', $v->id)->selectRaw('option_id, COUNT(*) as n')->groupBy('option_id')->pluck('n', 'option_id');
        $turnout = (int) DB::table('group_voting_turnout')->where('voting_id', $v->id)->count();
        $eligible = (int) $v->eligible_count;
        $total = (int) array_sum($counts->all());
        $rows = [];
        foreach ($options as $o) {
            $n = (int) ($counts[$o->id] ?? 0);
            $rows[] = ['option_id' => (int) $o->id, 'label' => $o->label, 'member_id' => $o->member_id === null ? null : (int) $o->member_id, 'role' => $o->role,
                'votes' => $n, 'percent' => $total === 0 ? 0.0 : round($n * 100 / $total, 1)];
        }
        $quorumMet = $eligible > 0 && ($turnout * 100 / $eligible) >= (float) $v->quorum_percent;
        [$decision, $winner] = self::decide($v, $rows, $quorumMet, $total);

        return [
            'options' => $rows, 'ballots' => $total, 'turnout' => $turnout, 'eligible' => $eligible,
            'participation_percent' => $eligible === 0 ? 0.0 : round($turnout * 100 / $eligible, 1),
            'quorum_percent' => (float) $v->quorum_percent, 'quorum_met' => $quorumMet, 'threshold_percent' => (float) $v->threshold_percent,
            'decision' => $decision, 'winner_option_id' => $winner,
        ];
    }

    /** @return array{0: string, 1: int|null} the decision and the winning option */
    private static function decide(object $v, array $rows, bool $quorumMet, int $total): array
    {
        if (!$quorumMet) {
            return ['no_quorum', null];
        }
        if ($total === 0) {
            return ['none', null];
        }
        if ($v->kind === 'election') {
            $max = max(array_column($rows, 'votes'));
            $top = array_values(array_filter($rows, fn ($r) => $r['votes'] === $max));

            return count($top) > 1 ? ['tie', null] : ['winner', $top[0]['option_id']];
        }
        $by = fn (string $role) => (int) (collect($rows)->firstWhere('role', $role)['votes'] ?? 0);
        $valid = $by('approve') + $by('reject');
        if ($valid === 0) {
            return ['none', null];
        }

        return [$by('approve') * 100 / $valid >= (float) $v->threshold_percent ? 'passed' : 'failed', null];
    }

    /** May this person see the counts of this process now? Leaders with the reports right see them once it is closed. */
    public static function resultsVisible(object $v, bool $reportsRight): bool
    {
        if (!in_array($v->status, ['open', 'paused', 'closed'], true)) {
            return false;
        }
        if ($v->status === 'closed' && $reportsRight) {
            return true;
        }

        return match ($v->results_visibility) {
            'live' => true,
            'after_close' => $v->status === 'closed',
            default => $v->results_published_at !== null,
        };
    }

    // ------------------------------------------------------------------------------------------------ naming and notices

    /** The exact thing voted on: "Chairperson (Leadership election 2026)" or the agenda's title. */
    public static function target(object $v): string
    {
        $what = $v->kind === 'election' && $v->position !== null && $v->position !== '' ? $v->position : $v->title;

        return $v->series !== null && $v->series !== '' && $v->kind === 'election' ? $what . ' (' . $v->series . ')' : $what;
    }

    private static function when(?string $at): string
    {
        return $at === null ? '' : Carbon::parse($at)->format('d/m/Y H:i');
    }

    public static function notifyEligible(object $v, string $kind, string $titleSw, string $titleEn, ?string $bodySw, ?string $bodyEn): void
    {
        self::notify(DB::table('group_voting_eligible')->where('voting_id', $v->id)->pluck('member_id')->map(fn ($i) => (int) $i)->all(), $kind, $titleSw, $titleEn, $bodySw, $bodyEn, (int) $v->id);
    }

    /** One notice for each member, linking to the exact voting item. */
    public static function notify(array $memberIds, string $kind, string $titleSw, string $titleEn, ?string $bodySw, ?string $bodyEn, int $votingId): void
    {
        $rows = [];
        foreach (array_unique($memberIds) as $m) {
            $rows[] = ['member_id' => (int) $m, 'kind' => $kind, 'title' => mb_substr($titleSw, 0, 150), 'title_en' => mb_substr($titleEn, 0, 150),
                'body' => $bodySw === null ? null : mb_substr($bodySw, 0, 255), 'body_en' => $bodyEn === null ? null : mb_substr($bodyEn, 0, 255),
                'link_type' => 'voting', 'link_id' => $votingId, 'created_at' => now()];
        }
        foreach (array_chunk($rows, 200) as $chunk) {
            DB::table('group_notifications')->insert($chunk);
        }
    }
}
