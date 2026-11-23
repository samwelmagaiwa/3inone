<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupOffices;
use App\Support\Groups\GroupVotings;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Groups (Vikundi): voting. Many independent processes at once: each with its own target, voters, rules, dates, ballots and result. One vote
 * per member per process, never two in the same one and never one counted in another; a secret ballot never records who chose what; a
 * closed, paused or cancelled process takes no vote; a candidate never runs the process they stand in.
 */
class GroupsVotingTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    /** @var array<string, User> */
    private array $people = [];

    /** @var array<string, int> */
    private array $ids = [];

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Carbon::setTestNow(Carbon::parse('2026-05-01 08:00:00'));
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'MEG Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG']);
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['deputy', '0712000002', 'makamu_mwenyekiti'], ['secretary', '0712000003', 'katibu'], ['treasurer', '0712000004', 'mweka_hazina'],
            ['asha', '0713000001', null], ['juma', '0713000002', null], ['rehema', '0713000003', null], ['neema', '0713000004', null], ['baraka', '0713000005', null]] as [$key, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            if ($office !== null) {
                $this->api($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, '/api/groups' . $uri, $body);
    }

    /** @param array<string, mixed> $extra */
    private function election(string $position, array $candidates, array $extra = []): int
    {
        return (int) $this->api($this->people['secretary'], 'POST', '/votings', $extra + [
            'title' => 'Uchaguzi wa ' . $position, 'category' => 'leadership', 'kind' => 'election', 'series' => 'Uchaguzi 2026', 'position' => $position, 'eligibility' => 'active',
            'opens_at' => '2026-05-02 08:00:00', 'closes_at' => '2026-05-09 18:00:00',
            'options' => array_map(fn ($k) => ['label' => ucfirst($k) . ' Member', 'member_id' => $this->ids[$k]], $candidates),
        ])->assertCreated()->json('data.voting.id');
    }

    private function agenda(string $title, array $extra = []): int
    {
        return (int) $this->api($this->people['secretary'], 'POST', '/votings', $extra + [
            'title' => $title, 'category' => 'project', 'kind' => 'decision', 'eligibility' => 'active', 'opens_at' => '2026-05-02 08:00:00', 'closes_at' => '2026-05-09 18:00:00',
        ])->assertCreated()->json('data.voting.id');
    }

    private function publish(int $id): void
    {
        $this->api($this->people['secretary'], 'POST', "/votings/{$id}/publish")->assertOk();
    }

    private function open(int $id): void
    {
        $this->publish($id);
        Carbon::setTestNow(Carbon::parse('2026-05-03 09:00:00'));
    }

    private function optionOf(int $voting, string $label): int
    {
        return (int) DB::table('group_voting_options')->where('voting_id', $voting)->where(fn ($q) => $q->where('label', 'like', $label . '%')->orWhere('role', strtolower($label)))->value('id');
    }

    public function test_the_voting_rights_belong_to_the_officers_who_run_votings(): void
    {
        foreach (['mwenyekiti', 'makamu_mwenyekiti', 'katibu', 'katibu_msaidizi'] as $office) {
            $this->assertContains('manage_votings', GroupOffices::rightsOf($office));
        }
        $this->assertContains('publish_voting_results', GroupOffices::rightsOf('mwenyekiti'));
        $this->assertNotContains('publish_voting_results', GroupOffices::rightsOf('katibu'), 'the secretary prepares, the chair announces');
        $this->assertSame([], array_intersect(GroupOffices::rightsOf('mweka_hazina'), ['manage_votings', 'publish_voting_results']));
        $this->api($this->people['asha'], 'POST', '/votings', [])->assertForbidden();
    }

    public function test_every_member_votes_whatever_their_office(): void
    {
        // The four offices not made in setUp, so all eight offices and an ordinary member are covered.
        foreach ([['assistant', '0712000011', 'mweka_hazina_msaidizi'], ['deputysec', '0712000012', 'katibu_msaidizi'], ['projects', '0712000013', 'mwenyekiti_miradi'], ['committee', '0712000014', 'kamati_miradi']] as [$key, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            $this->api($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
        $id = $this->agenda('Jambo la wote');
        $this->open($id);
        $yes = ['option_id' => $this->optionOf($id, 'Approve')];

        foreach (array_keys($this->people) as $who) {
            $this->api($this->people[$who], 'GET', '/votings')->assertOk();
            $this->assertSame('pending', $this->api($this->people[$who], 'GET', "/votings/{$id}")->json('data.voting.my.state'), "{$who} may vote");
            $this->api($this->people[$who], 'POST', "/votings/{$id}/vote", $yes)->assertCreated();
        }
        $this->assertSame(count($this->people), DB::table('group_voting_turnout')->where('voting_id', $id)->count(), 'every member of every office voted once');
    }

    public function test_an_election_has_its_own_candidates_and_a_decision_has_approve_reject_abstain(): void
    {
        $e = $this->election('Mwenyekiti', ['asha', 'juma', 'rehema']);
        $this->assertSame(3, DB::table('group_voting_options')->where('voting_id', $e)->count());
        $a = $this->agenda('Kuidhinisha bajeti ya mwaka');
        $this->assertSame(['approve', 'reject', 'abstain'], DB::table('group_voting_options')->where('voting_id', $a)->orderBy('sort')->pluck('role')->all());
        $this->assertSame(0, DB::table('group_voting_options')->where('voting_id', $a)->whereIn('member_id', array_values($this->ids))->count());

        $this->api($this->people['secretary'], 'POST', '/votings', ['title' => 'Mmoja tu', 'category' => 'leadership', 'kind' => 'election', 'position' => 'Katibu', 'eligibility' => 'active',
            'opens_at' => '2026-05-02 08:00:00', 'closes_at' => '2026-05-09 08:00:00', 'options' => [['label' => 'Peke yake', 'member_id' => $this->ids['asha']]]])
            ->assertStatus(422)->assertJsonPath('code', 'candidates_needed');
        $this->api($this->people['secretary'], 'POST', '/votings', ['title' => 'Siri na kubadili', 'category' => 'general', 'kind' => 'decision', 'eligibility' => 'active', 'secret' => true,
            'allow_change' => true, 'opens_at' => '2026-05-02 08:00:00', 'closes_at' => '2026-05-09 08:00:00'])->assertStatus(422)->assertJsonPath('code', 'secret_no_change');
    }

    public function test_each_process_counts_only_its_own_ballots_and_a_member_votes_once_in_each(): void
    {
        $chair = $this->election('Mwenyekiti', ['asha', 'juma']);
        $treasurer = $this->election('Mweka hazina', ['rehema', 'neema']);
        $budget = $this->agenda('Bajeti ya mwaka');
        foreach ([$chair, $treasurer, $budget] as $id) {
            $this->publish($id);
        }
        Carbon::setTestNow(Carbon::parse('2026-05-03 09:00:00'));

        $voter = $this->people['baraka'];
        $this->api($voter, 'POST', "/votings/{$chair}/vote", ['option_id' => $this->optionOf($chair, 'Asha')])->assertCreated();
        // The same member may vote in the other processes, and not twice in the same one.
        $this->api($voter, 'POST', "/votings/{$treasurer}/vote", ['option_id' => $this->optionOf($treasurer, 'Neema')])->assertCreated();
        $this->api($voter, 'POST', "/votings/{$budget}/vote", ['option_id' => $this->optionOf($budget, 'Approve')])->assertCreated();
        $this->api($voter, 'POST', "/votings/{$chair}/vote", ['option_id' => $this->optionOf($chair, 'Juma')])->assertStatus(409)->assertJsonPath('code', 'already_voted');

        // An option of another process is refused.
        $this->api($this->people['deputy'], 'POST', "/votings/{$chair}/vote", ['option_id' => $this->optionOf($treasurer, 'Rehema')])->assertStatus(422)->assertJsonPath('code', 'bad_option');

        $this->assertSame(1, DB::table('group_ballots')->where('voting_id', $chair)->count());
        $this->assertSame(1, DB::table('group_ballots')->where('voting_id', $treasurer)->count());
        $this->assertSame(1, DB::table('group_voting_turnout')->where('voting_id', $budget)->count());
        $mine = collect($this->api($voter, 'GET', '/votings')->assertOk()->json('data.votings'));
        $this->assertSame(['voted'], $mine->pluck('my.state')->unique()->values()->all());
        $this->assertSame('pending', $this->api($this->people['juma'], 'GET', "/votings/{$chair}")->json('data.voting.my.state'));
    }

    public function test_a_secret_ballot_never_records_who_chose_what(): void
    {
        $id = $this->election('Katibu', ['asha', 'juma'], ['secret' => true, 'results_visibility' => 'live']);
        $this->open($id);
        $this->api($this->people['baraka'], 'POST', "/votings/{$id}/vote", ['option_id' => $this->optionOf($id, 'Asha')])->assertCreated();
        $this->api($this->people['neema'], 'POST', "/votings/{$id}/vote", ['option_id' => $this->optionOf($id, 'Asha')])->assertCreated();

        $this->assertSame(0, DB::table('group_ballots')->where('voting_id', $id)->whereNotNull('member_id')->count(), 'no member on any ballot');
        $this->assertSame(2, DB::table('group_voting_turnout')->where('voting_id', $id)->count(), 'who took part is known');
        $this->assertSame(['Baraka Member', 'Neema Member'], collect($this->api($this->people['chair'], 'GET', "/votings/{$id}/report")->json('data.turnout'))->pluck('name')->sort()->values()->all());
        $report = $this->api($this->people['chair'], 'GET', "/votings/{$id}/report")->assertOk();
        $this->assertNull($report->json('data.individual'), 'no list of who chose what');
        $this->assertNull($this->api($this->people['baraka'], 'GET', "/votings/{$id}")->json('data.voting.my.choice'));
        $this->assertStringNotContainsString('Asha', DB::table('group_audit_log')->where('action', 'vote_cast')->pluck('summary')->implode(' '), 'the audit never says for whom');

        $results = $this->api($this->people['rehema'], 'GET', "/votings/{$id}")->json('data.voting.results');
        $this->assertSame(2, collect($results['options'])->firstWhere('label', 'Asha Member')['votes']);
    }

    public function test_an_open_ballot_can_be_changed_and_its_individual_votes_are_reported_after_it_closes(): void
    {
        $id = $this->agenda('Sera ya msaada', ['secret' => false, 'allow_change' => true]);
        $this->open($id);
        $v = $this->people['asha'];
        $this->api($v, 'POST', "/votings/{$id}/vote", ['option_id' => $this->optionOf($id, 'Reject')])->assertCreated();
        $this->assertSame($this->optionOf($id, 'Reject'), $this->api($v, 'GET', "/votings/{$id}")->json('data.voting.my.choice'));
        $this->api($v, 'POST', "/votings/{$id}/vote", ['option_id' => $this->optionOf($id, 'Approve')])->assertCreated();
        $this->assertSame(1, DB::table('group_ballots')->where('voting_id', $id)->count(), 'a change replaces, never adds');
        $this->assertSame($this->optionOf($id, 'Approve'), $this->api($v, 'GET', "/votings/{$id}")->json('data.voting.my.choice'));

        $this->api($this->people['chair'], 'POST', "/votings/{$id}/close")->assertOk();
        $rows = $this->api($this->people['chair'], 'GET', "/votings/{$id}/report")->json('data.individual');
        $this->assertSame([['member_number' => DB::table('group_members')->where('id', $this->ids['asha'])->value('member_number'), 'name' => 'Asha Member', 'option' => 'Ndiyo / Approve', 'date' => '2026-05-03']], $rows);
        $this->api($this->people['treasurer'], 'GET', "/votings/{$id}/report")->assertForbidden();
    }

    public function test_only_eligible_members_vote(): void
    {
        $this->api($this->people['secretary'], 'POST', '/votings', ['title' => 'Viongozi pekee', 'category' => 'general', 'kind' => 'decision', 'eligibility' => 'officers',
            'opens_at' => '2026-05-02 08:00:00', 'closes_at' => '2026-05-09 08:00:00'])->assertStatus(422);
        $everyone = $this->agenda('Jambo la wote');
        $selected = $this->agenda('Jambo la wachache', ['eligibility' => 'selected', 'member_ids' => [$this->ids['asha'], $this->ids['juma']]]);
        $this->publish($everyone);
        $this->publish($selected);
        Carbon::setTestNow(Carbon::parse('2026-05-03 09:00:00'));

        $yes = fn (int $v) => ['option_id' => $this->optionOf($v, 'Approve')];
        $this->api($this->people['asha'], 'POST', "/votings/{$everyone}/vote", $yes($everyone))->assertCreated();
        $this->api($this->people['treasurer'], 'POST', "/votings/{$everyone}/vote", $yes($everyone))->assertCreated();
        $this->api($this->people['asha'], 'POST', "/votings/{$selected}/vote", $yes($selected))->assertCreated();
        $this->api($this->people['rehema'], 'POST', "/votings/{$selected}/vote", $yes($selected))->assertForbidden()->assertJsonPath('code', 'not_eligible');
        $this->assertSame('not_eligible', $this->api($this->people['rehema'], 'GET', "/votings/{$selected}")->json('data.voting.my.state'));
    }

    public function test_a_voting_opens_and_closes_by_its_dates_and_takes_no_vote_outside_them(): void
    {
        $id = $this->agenda('Jambo la muda');
        $this->publish($id);
        $yes = ['option_id' => $this->optionOf($id, 'Approve')];
        $this->assertSame('scheduled', DB::table('group_votings')->where('id', $id)->value('status'));
        $this->api($this->people['asha'], 'POST', "/votings/{$id}/vote", $yes)->assertStatus(409)->assertJsonPath('code', 'not_open');
        $this->assertContains('upcoming', $this->api($this->people['asha'], 'GET', "/votings/{$id}")->json('data.voting.buckets'));

        Carbon::setTestNow(Carbon::parse('2026-05-02 12:00:00'));
        $this->api($this->people['asha'], 'POST', "/votings/{$id}/vote", $yes)->assertCreated();
        $this->assertContains('active', $this->api($this->people['juma'], 'GET', "/votings/{$id}")->json('data.voting.buckets'));
        $this->assertContains('pending', $this->api($this->people['juma'], 'GET', "/votings/{$id}")->json('data.voting.buckets'));

        $this->api($this->people['secretary'], 'POST', "/votings/{$id}/pause")->assertOk();
        $this->api($this->people['juma'], 'POST', "/votings/{$id}/vote", $yes)->assertStatus(409)->assertJsonPath('code', 'not_open');
        $this->api($this->people['secretary'], 'POST', "/votings/{$id}/resume")->assertOk();
        $this->api($this->people['juma'], 'POST', "/votings/{$id}/vote", $yes)->assertCreated();

        Carbon::setTestNow(Carbon::parse('2026-05-09 19:00:00'));
        $this->api($this->people['rehema'], 'POST', "/votings/{$id}/vote", $yes)->assertStatus(409);
        $this->assertSame('closed', DB::table('group_votings')->where('id', $id)->value('status'));
        $this->assertSame(2, DB::table('group_ballots')->where('voting_id', $id)->count());
    }

    public function test_a_cancelled_voting_takes_no_vote_and_says_why(): void
    {
        $id = $this->agenda('Jambo la kughairi');
        $this->open($id);
        $this->api($this->people['secretary'], 'POST', "/votings/{$id}/cancel", [])->assertStatus(422);
        $this->api($this->people['secretary'], 'POST', "/votings/{$id}/cancel", ['reason' => 'Imeunganishwa na kikao'])->assertOk()->assertJsonPath('data.voting.status', 'cancelled');
        $this->api($this->people['asha'], 'POST', "/votings/{$id}/vote", ['option_id' => $this->optionOf($id, 'Approve')])->assertStatus(409);
        $this->assertContains('closed', $this->api($this->people['asha'], 'GET', "/votings/{$id}")->json('data.voting.buckets'));
    }

    public function test_a_decision_passes_on_its_threshold_and_needs_its_quorum(): void
    {
        $id = $this->agenda('Bajeti', ['quorum_percent' => 50, 'threshold_percent' => 66.7, 'results_visibility' => 'live']);
        $this->open($id);
        $vote = fn (string $who, string $label) => $this->api($this->people[$who], 'POST', "/votings/{$id}/vote", ['option_id' => $this->optionOf($id, $label)])->assertCreated();
        // 9 members are eligible: 5 votes is a quorum of 50%+.
        foreach (['asha', 'juma', 'rehema', 'neema'] as $who) {
            $vote($who, 'Approve');
        }
        $vote('baraka', 'Reject');
        $vote('treasurer', 'Abstain');
        $r = GroupVotings::results(GroupVotings::find($id));
        $this->assertTrue($r['quorum_met']);
        $this->assertSame('passed', $r['decision'], '4 of 5 valid votes: 80% is over 66.7%, abstentions are not counted against it');

        $other = $this->agenda('Michango mipya', ['quorum_percent' => 80]);
        $this->open($other);
        $this->api($this->people['asha'], 'POST', "/votings/{$other}/vote", ['option_id' => $this->optionOf($other, 'Approve')])->assertCreated();
        $this->assertSame('no_quorum', GroupVotings::results(GroupVotings::find($other))['decision']);
    }

    public function test_an_election_names_a_winner_or_a_tie_and_the_chair_announces_it(): void
    {
        $id = $this->election('Mweka hazina', ['asha', 'juma'], ['results_visibility' => 'after_publish']);
        $this->open($id);
        $this->api($this->people['rehema'], 'POST', "/votings/{$id}/vote", ['option_id' => $this->optionOf($id, 'Asha')])->assertCreated();
        $this->api($this->people['neema'], 'POST', "/votings/{$id}/vote", ['option_id' => $this->optionOf($id, 'Juma')])->assertCreated();
        $this->api($this->people['baraka'], 'POST', "/votings/{$id}/vote", ['option_id' => $this->optionOf($id, 'Asha')])->assertCreated();

        $this->assertNull($this->api($this->people['rehema'], 'GET', "/votings/{$id}")->json('data.voting.results'), 'hidden while it runs');
        $this->api($this->people['chair'], 'POST', "/votings/{$id}/publish-results")->assertStatus(409)->assertJsonPath('code', 'not_closed');
        $this->api($this->people['secretary'], 'POST', "/votings/{$id}/close")->assertOk()->assertJsonPath('data.voting.status', 'closed');
        $this->assertNull($this->api($this->people['rehema'], 'GET', "/votings/{$id}")->json('data.voting.results'), 'a member waits for the announcement');
        $this->assertNotNull($this->api($this->people['secretary'], 'GET', "/votings/{$id}")->json('data.voting.results'), 'officers who report see it once closed');

        $this->api($this->people['secretary'], 'POST', "/votings/{$id}/publish-results")->assertForbidden();
        $this->api($this->people['chair'], 'POST', "/votings/{$id}/publish-results")->assertOk();
        $seen = $this->api($this->people['rehema'], 'GET', "/votings/{$id}")->json('data.voting');
        $this->assertSame('winner', $seen['decision']);
        $this->assertSame($this->optionOf($id, 'Asha'), $seen['winner_option_id']);
        $this->assertContains('completed', $seen['buckets']);
        $this->assertSame(66.7, collect($seen['results']['options'])->firstWhere('label', 'Asha Member')['percent']);

        $tie = $this->election('Katibu', ['asha', 'juma'], ['results_visibility' => 'live']);
        $this->open($tie);
        $this->api($this->people['rehema'], 'POST', "/votings/{$tie}/vote", ['option_id' => $this->optionOf($tie, 'Asha')])->assertCreated();
        $this->api($this->people['neema'], 'POST', "/votings/{$tie}/vote", ['option_id' => $this->optionOf($tie, 'Juma')])->assertCreated();
        $this->assertSame('tie', GroupVotings::results(GroupVotings::find($tie))['decision']);
    }

    public function test_a_candidate_never_runs_the_process_they_stand_in(): void
    {
        $id = $this->election('Katibu', ['secretary', 'juma']);
        $this->api($this->people['secretary'], 'POST', "/votings/{$id}/publish")->assertForbidden()->assertJsonPath('code', 'candidate_conflict');
        $this->api($this->people['chair'], 'POST', "/votings/{$id}/publish")->assertOk();
        $this->api($this->people['secretary'], 'POST', "/votings/{$id}/cancel", ['reason' => 'Napenda kughairi'])->assertForbidden()->assertJsonPath('code', 'candidate_conflict');
        $this->api($this->people['secretary'], 'POST', "/votings/{$id}/extend", ['closes_at' => '2026-05-20 18:00:00'])->assertForbidden();
        $this->api($this->people['chair'], 'POST', "/votings/{$id}/extend", ['closes_at' => '2026-05-20 18:00:00'])->assertOk();
        Carbon::setTestNow(Carbon::parse('2026-05-03 09:00:00'));
        $this->api($this->people['secretary'], 'POST', "/votings/{$id}/close")->assertForbidden();
        $this->api($this->people['deputy'], 'POST', "/votings/{$id}/close")->assertOk();
    }

    public function test_a_published_voting_is_not_edited_and_the_dates_are_checked(): void
    {
        $id = $this->agenda('Jambo');
        $this->api($this->people['secretary'], 'PUT', "/votings/{$id}", ['title' => 'Jambo jipya', 'category' => 'general', 'kind' => 'decision', 'eligibility' => 'active',
            'opens_at' => '2026-05-02 08:00:00', 'closes_at' => '2026-05-10 08:00:00'])->assertOk()->assertJsonPath('data.voting.title', 'Jambo jipya');
        $this->api($this->people['secretary'], 'POST', '/votings', ['title' => 'Tarehe mbaya', 'category' => 'general', 'kind' => 'decision', 'eligibility' => 'active',
            'opens_at' => '2026-05-05 08:00:00', 'closes_at' => '2026-05-04 08:00:00'])->assertStatus(422);
        $this->publish($id);
        $this->api($this->people['secretary'], 'PUT', "/votings/{$id}", ['title' => 'Siri', 'category' => 'general', 'kind' => 'decision', 'eligibility' => 'active',
            'opens_at' => '2026-05-02 08:00:00', 'closes_at' => '2026-05-10 08:00:00'])->assertStatus(409)->assertJsonPath('code', 'not_draft');
        $this->api($this->people['secretary'], 'DELETE', "/votings/{$id}")->assertStatus(409);
        $this->api($this->people['asha'], 'GET', '/votings')->assertOk();
        $draft = $this->agenda('Rasimu');
        $this->assertCount(0, collect($this->api($this->people['asha'], 'GET', '/votings')->json('data.votings'))->where('id', $draft), 'a member never sees a draft');
        $this->api($this->people['secretary'], 'DELETE', "/votings/{$draft}")->assertOk();
    }

    public function test_every_voting_notifies_its_own_members_with_a_link_to_that_item_and_the_waiting_count_follows(): void
    {
        $a = $this->agenda('Jambo A');
        $b = $this->election('Mwenyekiti', ['asha', 'juma']);
        $this->publish($a);
        $this->publish($b);
        Carbon::setTestNow(Carbon::parse('2026-05-03 09:00:00'));
        $this->api($this->people['asha'], 'GET', '/votings')->assertOk();

        $n = $this->api($this->people['rehema'], 'GET', '/me/notifications')->assertOk()->json('data');
        // Each voting told them twice (a new voting, then that it is open), and every notice points at its own voting.
        $this->assertSame(4, $n['unread']);
        $this->assertEqualsCanonicalizing([$a, $a, $b, $b], collect($n['notifications'])->pluck('link_id')->all());
        $this->assertEqualsCanonicalizing(['voting_new', 'voting_new', 'voting_open', 'voting_open'], collect($n['notifications'])->pluck('kind')->all());
        $this->assertSame('voting', $n['notifications'][0]['link_type']);
        $this->api($this->people['rehema'], 'GET', '/me')->assertJsonPath('data.waiting.votes_to_cast', 2);

        $this->api($this->people['rehema'], 'POST', "/votings/{$a}/vote", ['option_id' => $this->optionOf($a, 'Approve')])->assertCreated();
        $this->api($this->people['rehema'], 'GET', '/me')->assertJsonPath('data.waiting.votes_to_cast', 1);
        $after = $this->api($this->people['rehema'], 'GET', '/me/notifications')->json('data.notifications');
        $this->assertSame('voting_voted', $after[0]['kind']);
        $this->assertSame($a, $after[0]['link_id']);
        $this->api($this->people['rehema'], 'POST', '/me/notifications/read', ['all' => true])->assertJsonPath('data.unread', 0);
        $this->api($this->people['juma'], 'GET', '/me/notifications')->assertJsonPath('data.unread', 4);
    }

    public function test_the_audit_records_each_step_and_the_export_never_carries_a_formula(): void
    {
        $id = $this->agenda('=HYPERLINK("x")', ['secret' => false]);
        $this->open($id);
        $this->api($this->people['asha'], 'POST', "/votings/{$id}/vote", ['option_id' => $this->optionOf($id, 'Approve')])->assertCreated();
        $this->api($this->people['chair'], 'POST', "/votings/{$id}/close")->assertOk();
        $this->api($this->people['chair'], 'POST', "/votings/{$id}/publish-results")->assertOk();

        $actions = DB::table('group_audit_log')->where('subject_type', 'voting')->where('subject_id', $id)->orderBy('id')->pluck('action')->all();
        foreach (['voting_created', 'voting_published', 'vote_cast', 'voting_closed', 'voting_results_published'] as $a) {
            $this->assertContains($a, $actions);
        }
        $csv = $this->api($this->people['chair'], 'GET', "/votings/{$id}/report.csv")->assertOk()->streamedContent();
        $this->assertStringContainsString("'=HYPERLINK", $csv);
        $this->assertStringNotContainsString(',=HYPERLINK', $csv);
        $this->assertStringContainsString('Asha Member', $csv, 'an open ballot lists who chose what');
    }

    public function test_processes_of_one_business_never_show_in_another(): void
    {
        $id = $this->agenda('Jambo la siri');
        $this->publish($id);
        $other = $this->givenServices(User::factory()->create(['name' => 'Other Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000888']), 'groups');
        $this->api($other, 'GET', '/votings')->assertOk()->assertJsonCount(0, 'data.votings');
        $this->api($other, 'GET', "/votings/{$id}")->assertStatus(404);
    }
}
