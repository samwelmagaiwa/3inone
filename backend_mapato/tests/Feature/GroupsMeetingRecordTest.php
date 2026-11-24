<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupOffices;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Groups (Vikundi): the record of a meeting. The secretary writes minutes, resolutions and actions; the chair approves the minutes (never
 * ones they wrote); until then only leaders see them; actions are ticked off by their owner; approved minutes are not edited unless reopened.
 */
class GroupsMeetingRecordTest extends TestCase
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
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['treasurer', '0712000002', 'mweka_hazina'], ['secretary', '0712000004', 'katibu'],
            ['asha', '0713000001', null], ['juma', '0713000002', null]] as [$key, $phone, $office]) {
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

    /** A meeting that has happened, recorded by [who] with minutes. */
    private function heldMeeting(string $who = 'secretary'): int
    {
        $id = (int) $this->api($this->people['chair'], 'POST', '/meetings', ['title' => 'Kikao cha mwezi', 'starts_at' => '2026-05-10 14:00:00'])->assertCreated()->json('data.meeting.id');
        Carbon::setTestNow(Carbon::parse('2026-05-10 17:00:00'));
        $this->api($this->people[$who], 'POST', "/meetings/{$id}/record", ['present_ids' => [$this->ids['asha'], $this->ids['chair']], 'minutes' => 'Tumekubaliana kujenga banda.'])->assertOk();

        return $id;
    }

    public function test_the_minutes_right_belongs_to_the_chair_and_the_deputy_only(): void
    {
        $this->assertContains('approve_minutes', GroupOffices::rightsOf('mwenyekiti'));
        $this->assertContains('approve_minutes', GroupOffices::rightsOf('makamu_mwenyekiti'));
        $this->assertNotContains('approve_minutes', GroupOffices::rightsOf('katibu'));
        $this->assertNotContains('approve_minutes', GroupOffices::rightsOf('mweka_hazina'));
    }

    public function test_minutes_are_a_draft_for_leaders_until_the_chair_approves_and_then_the_members_see_them(): void
    {
        $id = $this->heldMeeting();
        $this->api($this->people['secretary'], 'POST', "/meetings/{$id}/items", ['kind' => 'resolution', 'text' => 'Banda la kuku lijengwe kabla ya Julai'])->assertOk();
        $this->api($this->people['secretary'], 'POST', "/meetings/{$id}/items", ['kind' => 'action', 'text' => 'Kupata bei ya mabati', 'assignee_id' => $this->ids['asha'], 'due_date' => '2026-05-09'])
            ->assertOk()->assertJsonCount(2, 'data.meeting.items');
        $this->api($this->people['asha'], 'POST', "/meetings/{$id}/items", ['kind' => 'resolution', 'text' => 'Mimi pia nasema'])->assertForbidden();

        // A draft: leaders see it, ordinary members do not.
        $this->api($this->people['treasurer'], 'GET', '/meetings')->assertJsonPath('data.meetings.0.minutes_status', 'draft')->assertJsonCount(2, 'data.meetings.0.items');
        $this->api($this->people['asha'], 'GET', '/meetings')->assertJsonPath('data.meetings.0.minutes', null)->assertJsonPath('data.meetings.0.items', [])->assertJsonPath('data.meetings.0.minutes_status', 'draft');

        $this->api($this->people['chair'], 'GET', '/me')->assertJsonPath('data.waiting.minutes_to_approve', 1);
        $this->api($this->people['secretary'], 'POST', "/meetings/{$id}/approve-minutes")->assertForbidden();
        $this->api($this->people['chair'], 'POST', "/meetings/{$id}/approve-minutes")->assertOk()->assertJsonPath('data.meeting.minutes_status', 'approved')
            ->assertJsonPath('data.meeting.minutes_approved_by_name', 'Chair Member');
        $this->api($this->people['asha'], 'GET', '/meetings')->assertJsonPath('data.meetings.0.minutes', 'Tumekubaliana kujenga banda.')->assertJsonCount(2, 'data.meetings.0.items');
        $this->api($this->people['chair'], 'GET', '/me')->assertJsonPath('data.waiting.minutes_to_approve', 0);

        // Approved minutes are not edited.
        $this->api($this->people['secretary'], 'POST', "/meetings/{$id}/items", ['kind' => 'resolution', 'text' => 'Late addition'])->assertStatus(409)->assertJsonPath('code', 'minutes_approved');
        $this->api($this->people['secretary'], 'POST', "/meetings/{$id}/record", ['present_ids' => [], 'minutes' => 'Changed'])->assertStatus(409)->assertJsonPath('code', 'minutes_approved');
    }

    public function test_nobody_approves_minutes_they_wrote_and_empty_minutes_are_not_approved(): void
    {
        $id = $this->heldMeeting('chair');
        $this->api($this->people['chair'], 'POST', "/meetings/{$id}/approve-minutes")->assertStatus(403)->assertJsonPath('code', 'own_minutes');
        $this->api($this->owner, 'POST', "/meetings/{$id}/approve-minutes")->assertOk();

        Carbon::setTestNow(Carbon::parse('2026-05-01 08:00:00'));
        $empty = (int) $this->api($this->people['chair'], 'POST', '/meetings', ['title' => 'Kikao kingine', 'starts_at' => '2026-05-20 14:00:00'])->json('data.meeting.id');
        Carbon::setTestNow(Carbon::parse('2026-05-20 17:00:00'));
        $this->api($this->people['secretary'], 'POST', "/meetings/{$empty}/record", ['present_ids' => []])->assertOk();
        $this->api($this->owner, 'POST', "/meetings/{$empty}/approve-minutes")->assertStatus(422)->assertJsonPath('code', 'minutes_empty');
    }

    public function test_actions_are_ticked_off_by_their_owner_and_followed_up_by_the_secretary(): void
    {
        $id = $this->heldMeeting();
        $mine = (int) collect($this->api($this->people['secretary'], 'POST', "/meetings/{$id}/items", ['kind' => 'action', 'text' => 'Kupata bei ya mabati', 'assignee_id' => $this->ids['asha'], 'due_date' => '2026-05-09'])
            ->json('data.meeting.items'))->firstWhere('kind', 'action')['id'];
        $this->api($this->people['secretary'], 'POST', "/meetings/{$id}/items", ['kind' => 'action', 'text' => 'Kualika mgeni', 'assignee_id' => $this->ids['juma']])->assertOk();

        // Nothing is asked of anyone before the minutes are approved.
        $this->api($this->people['asha'], 'POST', "/meetings/{$id}/items/{$mine}/done")->assertStatus(409)->assertJsonPath('code', 'minutes_not_approved');
        $this->assertCount(0, $this->api($this->people['asha'], 'GET', '/meeting-actions')->json('data.actions'));
        $this->api($this->people['chair'], 'POST', "/meetings/{$id}/approve-minutes")->assertOk();

        $this->api($this->people['asha'], 'GET', '/me')->assertJsonPath('data.waiting.my_actions', 1);
        $this->assertSame('Kupata bei ya mabati', $this->api($this->people['asha'], 'GET', '/meeting-actions')->json('data.actions.0.text'));
        $this->api($this->people['asha'], 'GET', '/meeting-actions?scope=all')->assertForbidden();
        $this->assertCount(2, $this->api($this->people['secretary'], 'GET', '/meeting-actions?scope=all')->json('data.actions'));
        $this->api($this->people['secretary'], 'GET', '/me')->assertJsonPath('data.waiting.actions_overdue', 1);

        $this->api($this->people['juma'], 'POST', "/meetings/{$id}/items/{$mine}/done")->assertForbidden();
        $this->api($this->people['asha'], 'POST', "/meetings/{$id}/items/{$mine}/done")->assertOk();
        $this->api($this->people['asha'], 'POST', "/meetings/{$id}/items/{$mine}/done")->assertStatus(409);
        $this->assertCount(1, $this->api($this->people['secretary'], 'GET', '/meeting-actions?scope=all')->json('data.actions'));
        $this->api($this->people['secretary'], 'GET', '/me')->assertJsonMissingPath('data.waiting.actions_overdue');
    }

    public function test_the_chair_can_reopen_approved_minutes_with_a_reason_and_members_stop_seeing_them(): void
    {
        $id = $this->heldMeeting();
        $this->api($this->people['chair'], 'POST', "/meetings/{$id}/approve-minutes")->assertOk();
        $this->api($this->people['secretary'], 'POST', "/meetings/{$id}/reopen-minutes", ['reason' => 'Wrong figure'])->assertForbidden();
        $this->api($this->people['chair'], 'POST', "/meetings/{$id}/reopen-minutes", [])->assertStatus(422);
        $this->api($this->people['chair'], 'POST', "/meetings/{$id}/reopen-minutes", ['reason' => 'Wrong figure'])->assertOk()->assertJsonPath('data.meeting.minutes_status', 'draft');
        $this->api($this->people['asha'], 'GET', '/meetings')->assertJsonPath('data.meetings.0.minutes', null);
        $this->api($this->people['secretary'], 'POST', "/meetings/{$id}/record", ['present_ids' => [$this->ids['asha']], 'minutes' => 'Corrected.'])->assertOk();
        $this->assertGreaterThanOrEqual(2, DB::table('group_audit_log')->whereIn('action', ['minutes_approved', 'minutes_reopened'])->count());
    }
}
