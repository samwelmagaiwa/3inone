<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Groups (Vikundi): a new member's request goes to the management (chairperson, vice chairperson, secretary, assistant secretary). Whoever of
 * them decides first decides for all: one approval is enough, and the others' notices change to "already approved by ...".
 */
class GroupsApprovalsTest extends TestCase
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
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG Group']);
        foreach ([
            ['chair', '0712000001', 'mwenyekiti'], ['vice', '0712000002', 'makamu_mwenyekiti'], ['secretary', '0712000003', 'katibu'],
            ['assistant', '0712000004', 'katibu_msaidizi'], ['treasurer', '0712000005', 'mweka_hazina'], ['asha', '0713000001', null],
        ] as [$key, $phone, $office]) {
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

    /** Asha, an ordinary member, registers Neema. Returns Neema's member id. */
    private function register(string $phone = '0715000111', string $name = 'Neema New'): int
    {
        return (int) $this->api($this->people['asha'], 'POST', '/members/register', ['full_name' => $name, 'phone' => $phone])->assertCreated()->json('data.member.id');
    }

    private function notices(string $who): array
    {
        return $this->api($this->people[$who], 'GET', '/me/notifications')->assertOk()->json('data.notifications');
    }

    public function test_every_one_of_the_management_may_approve_a_request(): void
    {
        foreach (['chair', 'vice', 'secretary', 'assistant'] as $who) {
            $this->assertContains('approve_members', $this->api($this->people[$who], 'GET', '/me')->json('data.rights'), $who);
        }
        foreach (['treasurer', 'asha'] as $who) {
            $this->assertNotContains('approve_members', $this->api($this->people[$who], 'GET', '/me')->json('data.rights'), $who);
        }
    }

    public function test_a_request_registered_by_a_normal_member_is_sent_to_all_four_of_the_management_and_to_nobody_else(): void
    {
        $id = $this->register();

        foreach (['chair', 'vice', 'secretary', 'assistant'] as $who) {
            $notices = $this->notices($who);
            $this->assertCount(1, $notices, $who);
            $this->assertSame('member_request', $notices[0]['kind']);
            $this->assertSame('member', $notices[0]['link_type']);
            $this->assertSame($id, $notices[0]['link_id']);
            $this->assertStringContainsString('Neema New', $notices[0]['title_en']);
            $this->assertStringContainsString('Asha Member', $notices[0]['body_en'], 'who registered them');
            // It also waits in their list of what needs them.
            $this->assertSame(1, $this->api($this->people[$who], 'GET', '/me')->json('data.waiting.applications'), $who);
        }
        $this->assertCount(0, $this->notices('treasurer'));
        $this->assertCount(0, $this->notices('asha'));
    }

    public function test_when_one_of_the_management_approves_the_others_are_told_it_is_already_approved_and_by_whom(): void
    {
        $id = $this->register();

        $this->api($this->people['secretary'], 'POST', "/members/{$id}/status", ['action' => 'approve'])->assertOk()->assertJsonPath('data.member.status', 'active');

        foreach (['chair', 'vice', 'assistant', 'secretary'] as $who) {
            $n = $this->notices($who)[0];
            $this->assertSame('member_approved', $n['kind'], $who);
            $this->assertSame('Neema New: already approved by Secretary Member', $n['title_en'], $who);
            $this->assertStringContainsString('Neema New: tayari imeidhinishwa na Secretary Member', $n['title']);
        }
        $this->assertSame(0, $this->api($this->people['chair'], 'GET', '/me')->json('data.waiting.applications'), 'nothing is left to approve');
        $this->assertSame('Secretary Member', $this->api($this->people['chair'], 'GET', "/members/{$id}")->json('data.member.approved_by_name'));
    }

    public function test_a_second_approval_is_refused_and_names_the_one_who_approved_so_it_counts_once(): void
    {
        $id = $this->register();
        $this->api($this->people['vice'], 'POST', "/members/{$id}/status", ['action' => 'approve'])->assertOk();
        $before = DB::table('group_member_events')->where('member_id', $id)->where('kind', 'status')->count();

        $this->api($this->people['chair'], 'POST', "/members/{$id}/status", ['action' => 'approve'])
            ->assertStatus(409)->assertJsonPath('code', 'already_approved')->assertJsonPath('approved_by', 'Vice Member');
        $this->assertStringContainsString('Tayari imeidhinishwa na Vice Member', $this->api($this->people['assistant'], 'POST', "/members/{$id}/status", ['action' => 'approve'])->json('message'));
        $this->assertSame($before, DB::table('group_member_events')->where('member_id', $id)->where('kind', 'status')->count(), 'no second approval was recorded');
        $this->assertSame('active', DB::table('group_members')->where('id', $id)->value('status'));
    }

    public function test_the_next_steps_go_on_as_usual_after_the_one_approval(): void
    {
        $id = $this->register();
        $this->api($this->people['assistant'], 'POST', "/members/{$id}/status", ['action' => 'approve'])->assertOk();

        // Active now: a member number was given, and they appear in the branch of the member who brought them in.
        $this->assertNotNull(DB::table('group_members')->where('id', $id)->value('member_number'));
        $this->assertStringContainsString('Neema New', json_encode($this->api($this->people['asha'], 'GET', '/me/referrals')->json()));
        // The one who decides a request is not the one who registered it; nobody approves their own membership.
        $this->api($this->people['assistant'], 'POST', "/members/{$this->ids['assistant']}/status", ['action' => 'suspend', 'reason' => 'x'])->assertForbidden();
    }

    public function test_a_request_that_is_turned_down_tells_the_others_who_turned_it_down(): void
    {
        $id = $this->register();
        $this->api($this->people['chair'], 'POST', "/members/{$id}/status", ['action' => 'reject', 'reason' => 'Not known to the group'])->assertOk();
        $n = $this->notices('vice')[0];
        $this->assertSame('member_declined', $n['kind']);
        $this->assertSame('Neema New: request turned down by Chair Member', $n['title_en']);
    }

    public function test_someone_without_the_right_cannot_approve(): void
    {
        $id = $this->register();
        $this->api($this->people['treasurer'], 'POST', "/members/{$id}/status", ['action' => 'approve'])->assertForbidden();
        $this->api($this->people['asha'], 'POST', "/members/{$id}/status", ['action' => 'approve'])->assertForbidden();
        $this->assertSame('submitted', DB::table('group_members')->where('id', $id)->value('status'));
    }

    public function test_a_request_recorded_by_one_of_the_management_goes_to_the_others_but_not_to_themselves(): void
    {
        $id = (int) $this->api($this->people['secretary'], 'POST', '/members', ['full_name' => 'Recorded By Katibu', 'phone' => '0716000333'])->assertCreated()->json('data.member.id');
        $this->assertCount(1, $this->notices('chair'));
        $this->assertCount(1, $this->notices('vice'));
        $this->assertCount(1, $this->notices('assistant'));
        $this->assertCount(0, $this->notices('secretary'), 'they recorded it themselves');
        $this->assertSame($id, $this->notices('chair')[0]['link_id']);
    }

    public function test_someone_who_applies_with_a_code_is_sent_to_the_management_too(): void
    {
        $code = $this->api($this->people['asha'], 'GET', '/invitations')->assertOk()->json('data.mine.code');
        $this->assertNotEmpty($code);
        $this->flushHeaders();
        $this->postJson('/api/public/groups/' . $code . '/apply', ['full_name' => 'Applied Alone', 'phone' => '0717000444', 'consent' => true])->assertCreated();
        $n = $this->notices('chair');
        $this->assertCount(1, $n);
        $this->assertStringContainsString('Applied Alone', $n[0]['title_en']);
        $this->assertStringContainsString('Asha Member', $n[0]['body_en'], 'the member whose code they used');
    }
}
