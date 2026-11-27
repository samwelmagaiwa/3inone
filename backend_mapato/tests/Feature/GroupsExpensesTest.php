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
 * Groups (Vikundi): expenses. An official asks, the treasurer or chair approves (never their own), the treasurer pays through the ledger and
 * someone else verifies; approved is not paid; a project's budget is never passed.
 */
class GroupsExpensesTest extends TestCase
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
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['treasurer', '0712000002', 'mweka_hazina'], ['assistant', '0712000003', 'mweka_hazina_msaidizi'],
            ['secretary', '0712000004', 'katibu'], ['projects', '0712000006', 'mwenyekiti_miradi'], ['asha', '0713000001', null]] as [$key, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            if ($office !== null) {
                $this->api($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
        // The cash the group held before it kept its books here, so payouts have money on record to come from.
        DB::table('group_transactions')->insert([
            'owner_id' => $this->owner->id, 'reference' => 'TX-OPENING', 'member_id' => null, 'category' => 'opening_balance', 'direction' => 'in',
            'amount' => 10000000, 'method' => 'cash', 'paid_on' => now()->toDateString(), 'status' => 'verified', 'verified_at' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, '/api/groups' . $uri, $body);
    }

    private function ask(string $who, float $amount = 100000, ?int $project = null, string $payee = 'Hardware Ltd'): int
    {
        return (int) $this->api($this->people[$who], 'POST', '/expenses', ['purpose' => 'Cement for the hall', 'category' => $project ? 'project' : 'office', 'payee' => $payee, 'amount' => $amount, 'project_id' => $project])
            ->assertCreated()->json('data.request.id');
    }

    private function runningProject(float $budget): int
    {
        $id = (int) $this->api($this->people['asha'], 'POST', '/projects', ['title' => 'Hall', 'budget' => $budget])->assertCreated()->json('data.project.id');
        $this->api($this->people['projects'], 'POST', "/projects/{$id}/review", ['supports' => true])->assertOk();
        $this->api($this->people['chair'], 'POST', "/projects/{$id}/decide", ['approve' => true])->assertOk();

        return $id;
    }

    public function test_the_expense_rights_follow_the_offices(): void
    {
        $this->assertContains('approve_expenses', GroupOffices::rightsOf('mweka_hazina'));
        $this->assertContains('approve_expenses', GroupOffices::rightsOf('mwenyekiti'));
        $this->assertNotContains('approve_expenses', GroupOffices::rightsOf('mwenyekiti_miradi'));
        $this->assertNotContains('approve_expenses', GroupOffices::rightsOf('katibu'));
        $this->assertContains('request_expenses', GroupOffices::rightsOf('katibu'));
        $this->assertContains('request_expenses', GroupOffices::rightsOf('mwenyekiti_miradi'));
        $this->assertSame([], array_intersect(['request_expenses', 'view_expenses', 'approve_expenses'], GroupOffices::rightsOf(null)));
    }

    public function test_a_request_is_approved_by_the_treasurer_paid_by_the_treasurer_and_paid_only_once_someone_else_verifies(): void
    {
        $id = $this->ask('projects');

        $this->api($this->people['projects'], 'POST', "/expenses/{$id}/decide", ['approve' => true])->assertForbidden();
        $this->api($this->people['secretary'], 'POST', "/expenses/{$id}/decide", ['approve' => true])->assertForbidden();
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$id}/pay", ['method' => 'cash'])->assertStatus(422)->assertJsonPath('code', 'expense_not_ready');
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$id}/decide", ['approve' => true, 'amount' => 150000])->assertStatus(422)->assertJsonPath('code', 'more_than_asked');
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$id}/decide", ['approve' => true, 'amount' => 90000])->assertOk()
            ->assertJsonPath('data.request.state', 'approved')->assertJsonPath('data.request.amount_approved', 90000);

        // The requester may not pay their own; the treasurer pays the approved amount, and it is only "paying" until verified.
        $this->api($this->people['projects'], 'POST', "/expenses/{$id}/pay", ['method' => 'cash'])->assertForbidden();
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$id}/pay", ['method' => 'cash'])->assertOk()->assertJsonPath('data.request.state', 'paying');
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$id}/pay", ['method' => 'cash'])->assertStatus(422)->assertJsonPath('code', 'expense_not_ready');
        $tx = (int) DB::table('group_transactions')->where('expense_id', $id)->value('id');
        $this->assertEquals(90000, DB::table('group_transactions')->where('id', $tx)->value('amount'));
        $this->assertSame('Hardware Ltd', DB::table('group_transactions')->where('id', $tx)->value('payee'));
        $this->api($this->people['treasurer'], 'POST', "/transactions/{$tx}/verify")->assertForbidden();
        $this->api($this->people['assistant'], 'POST', "/transactions/{$tx}/verify")->assertOk();
        $this->api($this->people['projects'], 'GET', '/expenses')->assertJsonPath('data.requests.0.state', 'paid');

        // A verified payout put right with a reversal makes the request payable again.
        $this->api($this->people['treasurer'], 'POST', "/transactions/{$tx}/reverse", ['reason' => 'Paid the wrong shop'])->assertOk();
        $this->api($this->people['projects'], 'GET', '/expenses')->assertJsonPath('data.requests.0.state', 'approved');
    }

    public function test_nobody_decides_or_pays_their_own_request_and_a_turn_down_needs_a_reason(): void
    {
        $own = $this->ask('treasurer');
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$own}/decide", ['approve' => true])->assertForbidden();
        $this->api($this->people['chair'], 'POST', "/expenses/{$own}/decide", ['approve' => true])->assertOk();
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$own}/pay", ['method' => 'cash'])->assertForbidden();
        $this->api($this->owner, 'POST', "/expenses/{$own}/pay", ['method' => 'cash'])->assertOk()->assertJsonPath('data.request.state', 'paying');

        $other = $this->ask('secretary');
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$other}/decide", ['approve' => false])->assertStatus(422);
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$other}/decide", ['approve' => false, 'note' => 'No quotation'])->assertOk()->assertJsonPath('data.request.state', 'rejected');
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$other}/decide", ['approve' => true])->assertStatus(409);

        $cancel = $this->ask('secretary');
        $this->api($this->people['projects'], 'POST', "/expenses/{$cancel}/cancel")->assertForbidden();
        $this->api($this->people['secretary'], 'POST', "/expenses/{$cancel}/cancel")->assertOk()->assertJsonPath('data.request.state', 'cancelled');
    }

    public function test_a_project_budget_is_never_passed_and_the_project_shows_what_was_spent(): void
    {
        $project = $this->runningProject(1000000);
        $first = $this->ask('projects', 800000, $project);
        $second = $this->ask('projects', 300000, $project);

        $this->api($this->people['treasurer'], 'POST', "/expenses/{$first}/decide", ['approve' => true])->assertOk();
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$second}/decide", ['approve' => true])->assertStatus(422)->assertJsonPath('code', 'over_budget');
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$second}/decide", ['approve' => true, 'amount' => 200000])->assertOk();

        $this->api($this->people['chair'], 'GET', "/projects/{$project}")->assertJsonPath('data.project.committed', 1000000)->assertJsonPath('data.project.spent', 0);
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$first}/pay", ['method' => 'cash'])->assertOk();
        $this->api($this->people['assistant'], 'POST', '/transactions/' . DB::table('group_transactions')->where('expense_id', $first)->value('id') . '/verify')->assertOk();
        $this->api($this->people['chair'], 'GET', "/projects/{$project}")->assertJsonPath('data.project.spent', 800000);

        // A project that is not running takes no requests.
        $this->api($this->people['projects'], 'POST', "/projects/{$project}/close", ['outcome' => 'completed', 'note' => 'Done'])->assertOk();
        $this->api($this->people['projects'], 'POST', '/expenses', ['purpose' => 'More cement', 'category' => 'project', 'payee' => 'X Shop', 'amount' => 1000, 'project_id' => $project])
            ->assertStatus(422)->assertJsonPath('code', 'project_not_running');
    }

    public function test_who_may_ask_and_who_sees_what(): void
    {
        $this->api($this->people['asha'], 'POST', '/expenses', ['purpose' => 'Sodas', 'category' => 'meeting', 'payee' => 'Duka', 'amount' => 5000])->assertForbidden();
        $this->api($this->people['asha'], 'GET', '/expenses')->assertForbidden();

        $mine = $this->ask('secretary');
        $this->ask('projects');
        $this->assertCount(1, $this->api($this->people['secretary'], 'GET', '/expenses')->assertOk()->json('data.requests'));
        $this->assertCount(2, $this->api($this->people['treasurer'], 'GET', '/expenses')->json('data.requests'));
        $this->assertCount(2, $this->api($this->people['chair'], 'GET', '/expenses')->json('data.requests'));
        $this->api($this->people['secretary'], 'GET', '/expenses')->assertJsonPath('data.requests.0.id', $mine)->assertJsonPath('data.requests.0.mine', true);

        $this->api($this->people['treasurer'], 'GET', '/me')->assertJsonPath('data.waiting.expenses_to_approve', 2)->assertJsonPath('data.waiting.expenses_to_pay', 0);
        $this->api($this->people['treasurer'], 'POST', "/expenses/{$mine}/decide", ['approve' => true])->assertOk();
        $this->api($this->people['treasurer'], 'GET', '/me')->assertJsonPath('data.waiting.expenses_to_approve', 1)->assertJsonPath('data.waiting.expenses_to_pay', 1);
        $this->api($this->people['secretary'], 'GET', '/me')->assertJsonMissingPath('data.waiting.expenses_to_approve');
    }
}
