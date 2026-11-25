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
 * Groups (Vikundi) "ME": a leader who is also a member sends X-Group-View: member and is answered as an ordinary member -- no office rights,
 * no leaders' lists, no leaders' notices -- until they stop sending it. It can only take rights away, never give any.
 */
class GroupsViewAsMemberTest extends TestCase
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
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['treasurer', '0712000005', 'mweka_hazina'], ['asha', '0713000001', null]] as [$key, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            if ($office !== null) {
                $this->api($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
    }

    private function api(User $as, string $method, string $uri, array $body = [], bool $me = false)
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();
        $request = $this->withHeader('Authorization', "Bearer {$token}");
        if ($me) {
            $request = $request->withHeader('X-Group-View', 'member');
        }

        return $request->json($method, '/api/groups' . $uri, $body);
    }

    public function test_without_the_header_a_leader_is_a_leader_and_the_switch_is_offered(): void
    {
        $d = $this->api($this->people['chair'], 'GET', '/me')->assertOk()->json('data');
        $this->assertContains('view_members', $d['rights']);
        $this->assertTrue($d['can_switch_view']);
        $this->assertFalse($d['viewing_as_member']);
        $this->assertSame('mwenyekiti', $d['member']['office']);
        $this->api($this->people['chair'], 'GET', '/members')->assertOk();
    }

    public function test_with_the_header_the_same_leader_is_answered_as_an_ordinary_member(): void
    {
        $d = $this->api($this->people['chair'], 'GET', '/me', [], true)->assertOk()->json('data');
        $this->assertSame([], $d['rights']);
        $this->assertFalse($d['is_owner']);
        $this->assertTrue($d['viewing_as_member']);
        $this->assertTrue($d['can_switch_view'], 'the switch stays so they can go back');
        $this->assertNull($d['member']['office']);
        $this->assertSame($this->ids['chair'], $d['member']['id'], 'it is still THEIR account');
        $this->assertArrayNotHasKey('payments_to_verify', $d['waiting']);
        $this->assertArrayNotHasKey('applications', $d['waiting']);

        // What needs an office is closed to them in this view, then open again without the header.
        $this->api($this->people['chair'], 'GET', '/members', [], true)->assertForbidden();
        $this->api($this->people['treasurer'], 'GET', '/transactions', [], true)->assertForbidden();
        $this->api($this->people['chair'], 'GET', '/members')->assertOk();
    }

    public function test_their_own_things_still_work_in_this_view(): void
    {
        $this->api($this->people['chair'], 'GET', '/me/transactions', [], true)->assertOk();
        $this->api($this->people['chair'], 'GET', '/me/notifications', [], true)->assertOk();
        $this->api($this->people['chair'], 'GET', '/announcements', [], true)->assertOk();
    }

    public function test_leaders_only_announcements_and_notices_are_not_shown_in_this_view(): void
    {
        $this->api($this->people['chair'], 'POST', '/announcements', ['title' => 'For all of us', 'body' => 'Everyone reads this', 'audience' => 'all'])->assertCreated();
        $this->api($this->people['chair'], 'POST', '/announcements', ['title' => 'Leaders only', 'body' => 'Management matters', 'audience' => 'leaders'])->assertCreated();

        $titles = fn (array $r) => collect($r)->pluck('title')->all();
        $this->assertEqualsCanonicalizing(['For all of us', 'Leaders only'], $titles($this->api($this->people['chair'], 'GET', '/announcements')->json('data.announcements')));
        $this->assertSame(['For all of us'], $titles($this->api($this->people['chair'], 'GET', '/announcements', [], true)->json('data.announcements')));
        $this->assertSame(['For all of us'], $titles($this->api($this->people['asha'], 'GET', '/announcements')->json('data.announcements')));
        $this->assertSame(2, $this->api($this->people['chair'], 'GET', '/me')->json('data.notices'));
        $this->assertSame(1, $this->api($this->people['chair'], 'GET', '/me', [], true)->json('data.notices'));

        // A membership request waits for the management: shown to the chair as a leader, not in ME.
        $this->api($this->people['asha'], 'POST', '/members/register', ['full_name' => 'Neema New', 'phone' => '0715000111'])->assertCreated();
        $kinds = fn (bool $me) => collect($this->api($this->people['chair'], 'GET', '/me/notifications', [], $me)->json('data.notifications'))->pluck('kind')->all();
        $this->assertContains('member_request', $kinds(false));
        $this->assertNotContains('member_request', $kinds(true));
    }

    public function test_the_header_never_adds_anything_and_means_nothing_to_the_owner_or_a_stranger(): void
    {
        // An ordinary member gains nothing from it.
        $d = $this->api($this->people['asha'], 'GET', '/me', [], true)->assertOk()->json('data');
        $this->assertSame([], $d['rights']);
        $this->assertFalse($d['can_switch_view']);
        $this->api($this->people['asha'], 'GET', '/members', [], true)->assertForbidden();
        // The owner has no member record to look from, so the header changes nothing for them.
        $this->api($this->owner, 'GET', '/members', [], true)->assertOk();
        $this->assertFalse($this->api($this->owner, 'GET', '/me', [], true)->json('data.viewing_as_member'));
    }
}
