<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupOffices;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Groups (Vikundi): projects (miradi). A member proposes, the projects committee recommends, the chair approves, the Projects Chairperson
 * runs and closes; never one's own proposal; members see only what runs or finished (and their own proposals).
 */
class GroupsProjectsTest extends TestCase
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
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'MEG Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG']);
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['treasurer', '0712000002', 'mweka_hazina'], ['projects', '0712000006', 'mwenyekiti_miradi'],
            ['committee', '0712000007', 'kamati_miradi'], ['asha', '0713000001', null], ['juma', '0713000002', null]] as [$key, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            if ($office !== null) {
                $this->api($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, '/api/groups' . $uri, $body);
    }

    private function propose(string $who, string $title = 'Poultry house'): int
    {
        return (int) $this->api($this->people[$who], 'POST', '/projects', ['title' => $title, 'budget' => 5000000, 'description' => 'Layers for eggs'])
            ->assertCreated()->json('data.project.id');
    }

    public function test_the_project_rights_follow_the_offices(): void
    {
        $this->assertContains('manage_projects', GroupOffices::rightsOf('mwenyekiti_miradi'));
        $this->assertContains('recommend_projects', GroupOffices::rightsOf('kamati_miradi'));
        $this->assertNotContains('manage_projects', GroupOffices::rightsOf('kamati_miradi'));
        $this->assertContains('approve_projects', GroupOffices::rightsOf('mwenyekiti'));
        $this->assertNotContains('approve_projects', GroupOffices::rightsOf('mwenyekiti_miradi'));
        $this->assertContains('view_projects', GroupOffices::rightsOf('mweka_hazina'));
        $this->assertSame([], array_intersect(['view_projects', 'manage_projects'], GroupOffices::rightsOf(null)));
    }

    public function test_a_project_goes_from_proposal_to_committee_to_chair_to_progress_to_completed(): void
    {
        $id = $this->propose('asha');

        // The committee recommends; the chair cannot approve before that, and an ordinary member cannot do either.
        $this->api($this->people['juma'], 'POST', "/projects/{$id}/review", ['supports' => true])->assertForbidden();
        $this->api($this->people['chair'], 'POST', "/projects/{$id}/decide", ['approve' => true])->assertStatus(422)->assertJsonPath('code', 'committee_first');
        $this->api($this->people['committee'], 'POST', "/projects/{$id}/review", ['supports' => false])->assertStatus(422);
        $this->api($this->people['committee'], 'POST', "/projects/{$id}/review", ['supports' => true, 'note' => 'Good market'])->assertOk()->assertJsonPath('data.project.supports', 1);
        $this->api($this->people['juma'], 'POST', "/projects/{$id}/decide", ['approve' => true])->assertForbidden();
        $this->api($this->people['projects'], 'POST', "/projects/{$id}/decide", ['approve' => true])->assertForbidden();
        $this->api($this->people['chair'], 'POST', "/projects/{$id}/decide", ['approve' => true])->assertOk()->assertJsonPath('data.project.status', 'active');

        // The Projects Chairperson names a manager and logs progress; the manager may log it too; others may not.
        $this->api($this->people['projects'], 'PUT', "/projects/{$id}", ['manager_id' => $this->ids['juma'], 'budget' => 6000000])->assertOk()->assertJsonPath('data.project.manager_name', 'Juma Member');
        $this->api($this->people['asha'], 'POST', "/projects/{$id}/progress", ['progress' => 10, 'note' => 'Trying'])->assertForbidden();
        $this->api($this->people['juma'], 'POST', "/projects/{$id}/progress", ['progress' => 40, 'note' => 'Roof done'])->assertOk()->assertJsonPath('data.project.progress', 40);
        $this->api($this->people['projects'], 'POST', "/projects/{$id}/progress", ['progress' => 70, 'note' => 'Birds bought'])->assertOk()->assertJsonPath('data.project.updates.0.note', 'Birds bought');
        $this->api($this->people['juma'], 'POST', "/projects/{$id}/close", ['outcome' => 'completed', 'note' => 'Done'])->assertForbidden();
        $this->api($this->people['projects'], 'POST', "/projects/{$id}/close", ['outcome' => 'completed', 'note' => 'Done'])->assertOk()->assertJsonPath('data.project.status', 'completed')->assertJsonPath('data.project.progress', 100);
        $this->api($this->people['projects'], 'POST', "/projects/{$id}/progress", ['progress' => 50, 'note' => 'again'])->assertStatus(409);
        $this->assertGreaterThanOrEqual(5, DB::table('group_audit_log')->where('subject_type', 'project')->count());
    }

    public function test_nobody_reviews_or_decides_their_own_proposal_and_a_turn_down_needs_a_reason(): void
    {
        $id = $this->propose('committee', 'Water pump');
        $this->api($this->people['committee'], 'POST', "/projects/{$id}/review", ['supports' => true])->assertForbidden();

        $chairs = $this->propose('chair', 'Own idea');
        $this->api($this->people['committee'], 'POST', "/projects/{$chairs}/review", ['supports' => true])->assertOk();
        $this->api($this->people['chair'], 'POST', "/projects/{$chairs}/decide", ['approve' => true])->assertForbidden();

        $this->api($this->people['chair'], 'POST', "/projects/{$id}/decide", ['approve' => false])->assertStatus(422);
        $this->api($this->people['chair'], 'POST', "/projects/{$id}/decide", ['approve' => false, 'note' => 'Too costly'])->assertOk()->assertJsonPath('data.project.status', 'rejected');
        $this->api($this->people['chair'], 'POST', "/projects/{$id}/decide", ['approve' => true])->assertStatus(409);
    }

    public function test_members_see_running_projects_and_their_own_proposals_but_not_other_proposals(): void
    {
        $mine = $this->propose('asha', 'Mine');
        $theirs = $this->propose('juma', 'Theirs');
        $this->api($this->people['committee'], 'POST', "/projects/{$theirs}/review", ['supports' => true])->assertOk();
        $this->api($this->people['chair'], 'POST', "/projects/{$theirs}/decide", ['approve' => true])->assertOk();
        $other = $this->propose('juma', 'Still open');

        $titles = collect($this->api($this->people['asha'], 'GET', '/projects')->assertOk()->json('data.projects'))->pluck('title')->all();
        $this->assertEqualsCanonicalizing(['Mine', 'Theirs'], $titles);
        $this->api($this->people['asha'], 'GET', "/projects/{$other}")->assertNotFound();
        $this->api($this->people['asha'], 'GET', "/projects/{$mine}")->assertOk()->assertJsonPath('data.project.reviews', []);
        $this->assertCount(3, $this->api($this->people['treasurer'], 'GET', '/projects')->json('data.projects'));
        $this->api($this->people['treasurer'], 'GET', "/projects/{$other}")->assertOk();

        // The proposer withdraws an open proposal, and only their own.
        $this->api($this->people['asha'], 'POST', "/projects/{$other}/withdraw")->assertForbidden();
        $this->api($this->people['juma'], 'POST', "/projects/{$other}/withdraw")->assertOk();
        $this->api($this->people['juma'], 'POST', "/projects/{$theirs}/withdraw")->assertStatus(409);
    }

    public function test_the_waiting_counts_reach_the_committee_and_the_chair_and_the_owner_may_propose(): void
    {
        $this->propose('asha');
        $this->api($this->people['committee'], 'GET', '/me')->assertJsonPath('data.waiting.projects_to_review', 1);
        $this->api($this->people['chair'], 'GET', '/me')->assertJsonPath('data.waiting.projects_to_approve', 1);
        $this->api($this->people['asha'], 'GET', '/me')->assertJsonMissingPath('data.waiting.projects_to_review');
        $this->api($this->owner, 'POST', '/projects', ['title' => 'Owner plan', 'budget' => 1000])->assertCreated();
    }
}
