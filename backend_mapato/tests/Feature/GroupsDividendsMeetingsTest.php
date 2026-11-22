<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Groups (Vikundi), phase 5a: dividends by the group's own formula (prepared by one officer, approved and posted by another, never twice for
 * a period, never past the approved profit), meetings with attendance and minutes, announcements, and texts to many members.
 */
class GroupsDividendsMeetingsTest extends TestCase
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
        Carbon::setTestNow(Carbon::parse('2026-01-01 08:00:00'));
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'MEG Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG']);
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['treasurer', '0712000002', 'mweka_hazina'], ['assistant', '0712000003', 'mweka_hazina_msaidizi'],
            ['secretary', '0712000004', 'katibu'], ['asha', '0713000001', null], ['juma', '0713000002', null]] as [$key, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true, 'joined_on' => '2025-06-01'])->assertCreated()->json('data.member.id');
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

    /** Savings for [who], verified on [day]. */
    private function save(string $who, float $amount, string $day): void
    {
        Carbon::setTestNow(Carbon::parse($day . ' 09:00:00'));
        $tx = $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids[$who], 'category' => 'savings', 'amount' => $amount, 'method' => 'cash'])->json('data.transaction.id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$tx}/verify")->assertOk();
    }

    public function test_two_percent_of_closing_savings_is_prepared_by_the_treasurer_and_posted_by_the_chair_once(): void
    {
        $this->save('asha', 100000, '2026-02-01');
        $this->save('juma', 50000, '2026-03-01');
        Carbon::setTestNow(Carbon::parse('2026-12-31 10:00:00'));
        $plan = ['period_from' => '2026-01-01', 'period_to' => '2026-12-31', 'profit_pool' => 10000, 'base' => 'closing', 'method' => 'rate', 'rate' => 2, 'note' => 'AGM 2026 decision'];

        $this->api($this->people['treasurer'], 'POST', '/dividends', ['profit_pool' => 2000] + $plan)->assertStatus(422)->assertJsonPath('code', 'over_pool')->assertJsonPath('total', 3000);
        $this->api($this->people['chair'], 'POST', '/dividends', $plan)->assertForbidden();
        $run = $this->api($this->people['treasurer'], 'POST', '/dividends', $plan)->assertCreated()->assertJsonPath('data.run.total', 3000)->assertJsonPath('data.run.status', 'draft')->json('data.run');
        $this->assertEquals(2000, collect($run['lines'])->firstWhere('member_id', $this->ids['asha'])['amount']);
        $this->assertEquals(1000, collect($run['lines'])->firstWhere('member_id', $this->ids['juma'])['amount']);
        $this->assertNull(collect($run['lines'])->firstWhere('member_id', $this->ids['chair']), 'no savings, no line');

        $this->api($this->owner, 'GET', '/me')->assertJsonPath('data.waiting.dividends_to_approve', 1);
        $this->api($this->owner, 'POST', "/dividends/{$run['id']}/post")->assertOk()->assertJsonPath('data.run.status', 'posted');
        $this->api($this->owner, 'POST', "/dividends/{$run['id']}/post")->assertStatus(409);

        // Credited to savings, kept apart from deposits.
        $this->api($this->people['asha'], 'GET', '/me')->assertJsonPath('data.balances.savings', 102000);
        $this->api($this->people['asha'], 'GET', '/me/dividends')->assertJsonPath('data.dividends.0.amount', 2000);
        $this->assertSame(2, DB::table('group_transactions')->where('category', 'dividend')->count());
        $this->api($this->people['treasurer'], 'POST', '/dividends', ['period_from' => '2026-06-01'] + $plan)->assertStatus(422)->assertJsonPath('code', 'period_paid');
    }

    public function test_nobody_posts_a_run_they_prepared(): void
    {
        $this->save('asha', 100000, '2026-02-01');
        Carbon::setTestNow(Carbon::parse('2026-12-31 10:00:00'));
        $this->api($this->owner, 'POST', '/dividends', ['period_from' => '2026-01-01', 'period_to' => '2026-12-31', 'profit_pool' => 5000, 'base' => 'closing', 'method' => 'share', 'note' => 'AGM'])->assertCreated();
        $id = (int) DB::table('group_dividend_runs')->value('id');
        $this->api($this->owner, 'POST', "/dividends/{$id}/post")->assertForbidden()->assertJsonPath('code', 'own_run');
        $this->api($this->people['chair'], 'POST', "/dividends/{$id}/post")->assertOk();
        $this->api($this->people['asha'], 'GET', '/me/dividends')->assertJsonPath('data.dividends.0.amount', 5000);
    }

    public function test_average_savings_count_a_late_deposit_for_less_when_the_profit_is_shared(): void
    {
        $this->save('asha', 100000, '2026-04-01');
        $this->save('juma', 100000, '2026-04-06');
        Carbon::setTestNow(Carbon::parse('2026-04-30 10:00:00'));
        $run = $this->api($this->people['treasurer'], 'POST', '/dividends', [
            'period_from' => '2026-04-01', 'period_to' => '2026-04-10', 'profit_pool' => 3000, 'base' => 'average', 'method' => 'share', 'note' => 'April test',
        ])->assertCreated()->json('data.run');
        $lines = collect($run['lines']);
        $this->assertEquals(100000, $lines->firstWhere('member_id', $this->ids['asha'])['base']);
        $this->assertEquals(50000, $lines->firstWhere('member_id', $this->ids['juma'])['base'], 'saved on day 6 of 10');
        $this->assertEquals(2000, $lines->firstWhere('member_id', $this->ids['asha'])['amount']);
        $this->assertEquals(1000, $lines->firstWhere('member_id', $this->ids['juma'])['amount']);
    }

    public function test_the_chair_calls_a_meeting_members_are_texted_and_the_secretary_records_it_after(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-05-01 08:00:00'));
        $id = $this->api($this->people['chair'], 'POST', '/meetings', ['title' => 'Kikao cha mwezi', 'starts_at' => '2026-05-10 14:00:00', 'venue' => 'Ukumbi', 'notify' => true])
            ->assertCreated()->json('data.meeting.id');
        $this->assertCount(6, $this->sms->sent, 'every active member with a phone');
        $this->assertStringContainsString('Kikao cha mwezi', $this->sms->sent[0]['message']);
        $this->api($this->people['secretary'], 'POST', '/meetings', ['title' => 'x x x', 'starts_at' => '2026-05-11 14:00:00'])->assertForbidden();
        $this->api($this->people['asha'], 'GET', '/me')->assertJsonPath('data.next_meeting.id', $id);

        $this->api($this->people['secretary'], 'POST', "/meetings/{$id}/record", ['present_ids' => [$this->ids['asha']]])->assertStatus(409)->assertJsonPath('code', 'not_yet');
        Carbon::setTestNow(Carbon::parse('2026-05-10 17:00:00'));
        $this->api($this->people['secretary'], 'POST', "/meetings/{$id}/record", ['present_ids' => [$this->ids['asha'], $this->ids['chair']], 'minutes' => 'Tumekubaliana ...'])
            ->assertOk()->assertJsonPath('data.meeting.status', 'held')->assertJsonPath('data.meeting.present_count', 2);
        $this->api($this->people['asha'], 'GET', '/meetings')->assertJsonPath('data.meetings.0.i_was_there', true);
        $this->api($this->people['juma'], 'GET', '/meetings')->assertJsonPath('data.meetings.0.i_was_there', false);
    }

    public function test_announcements_for_officers_stay_with_officers_and_texts_show_their_cost_first(): void
    {
        $this->api($this->people['secretary'], 'POST', '/announcements', ['title' => 'Kwa wote', 'body' => 'Karibuni kikaoni'])->assertCreated();
        $this->api($this->people['secretary'], 'POST', '/announcements', ['title' => 'Viongozi tu', 'body' => 'Tukutane saa nane', 'audience' => 'officers'])->assertCreated();
        $this->api($this->people['asha'], 'GET', '/announcements')->assertJsonCount(1, 'data.announcements');
        $this->api($this->people['treasurer'], 'GET', '/announcements')->assertJsonCount(2, 'data.announcements');
        $this->api($this->people['asha'], 'POST', '/announcements', ['title' => 'xxx', 'body' => 'yyy'])->assertForbidden();

        $this->api($this->people['secretary'], 'POST', '/messages/estimate', ['audience' => 'officers', 'body' => str_repeat('a', 200)])
            ->assertOk()->assertJsonPath('data.recipients', 4)->assertJsonPath('data.parts_each', 2)->assertJsonPath('data.parts_total', 8);
        $this->api($this->people['asha'], 'POST', '/messages', ['audience' => 'all', 'body' => 'Hello'])->assertForbidden();
        $this->api($this->people['secretary'], 'POST', '/messages', ['audience' => 'selected', 'member_ids' => [$this->ids['juma']], 'body' => 'Tafadhali njoo ofisini.'])
            ->assertCreated()->assertJsonPath('data.messages.0.recipients', 1)->assertJsonPath('data.messages.0.sent', 1);
        $this->assertSame('0713000002', $this->sms->sent[0]['to']);
    }
}
