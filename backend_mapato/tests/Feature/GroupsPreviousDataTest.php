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
 * Groups (Vikundi): previous data. A leader enters what a member held and owed before the app (savings, shares, each kind of contribution,
 * a running loan). It counts at once in the member's balances, never as cash; refundable contributions show as the member's; a leader
 * never enters their own; a mistake is removed, never reversed.
 */
class GroupsPreviousDataTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    /** @var array<string, User> */
    private array $people = [];

    /** @var array<string, int> */
    private array $ids = [];

    /** @var array<string, int> */
    private array $types = [];

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Carbon::setTestNow(Carbon::parse('2026-11-28 08:00:00'));
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'UWM Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'UWM']);
        foreach ([['chair', 'Juma Mwenyekiti', '0712000001', 'mwenyekiti'], ['treasurer', 'Mweka Hazina', '0712000002', 'mweka_hazina'],
            ['assistant', 'Msaidizi', '0712000003', 'mweka_hazina_msaidizi'], ['michael', 'Michael Prosper Shirima', '0713000001', null]] as [$key, $name, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => $name, 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            if ($office !== null) {
                $this->api($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
        foreach ([['JAMII', 15000, false], ['MRADI', 200000, true], ['UGONJWA', 10000, false], ['SHEREHE', 10000, false]] as [$name, $amount, $refundable]) {
            $this->types[$name] = $this->api($this->owner, 'POST', '/contribution-types', ['name' => $name, 'amount' => $amount, 'frequency' => 'event', 'refundable' => $refundable])
                ->assertCreated()->assertJsonPath('data.type.refundable', $refundable)->json('data.type.id');
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function api(User $as, string $method, string $uri, array $body = [], bool $me = false)
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();
        GroupAccess::viewAsMember(false);

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeaders($me ? ['X-Group-View' => 'member'] : [])->json($method, '/api/groups' . $uri, $body);
    }

    /** Michael's book before the app, as the Mwenyekiti sent it. */
    private function michael(): array
    {
        return ['as_of' => '2026-06-30', 'savings' => 1300000, 'note' => 'Daftari la zamani', 'contributions' => [
            ['type_id' => $this->types['JAMII'], 'amount' => 180000], ['type_id' => $this->types['MRADI'], 'amount' => 200000],
            ['type_id' => $this->types['UGONJWA'], 'amount' => 10000], ['type_id' => $this->types['SHEREHE'], 'amount' => 10000],
        ]];
    }

    public function test_previous_totals_fill_the_members_balances_at_once_but_are_never_cash(): void
    {
        $this->api($this->people['chair'], 'POST', "/members/{$this->ids['michael']}/previous", $this->michael())->assertCreated()->assertJsonPath('data.created', 5);

        $s = $this->api($this->people['treasurer'], 'GET', "/members/{$this->ids['michael']}/statement")->assertOk()->json('data');
        $this->assertEquals(1300000, $s['balances']['savings']);
        $this->assertEquals(400000, $s['balances']['contribution']);
        $this->assertEquals(200000, $s['refundable'], 'MRADI is refundable; JAMII, UGONJWA and SHEREHE are not');
        $this->assertTrue(collect($s['lines'])->every(fn ($l) => $l['brought_forward'] === true && $l['status'] === 'verified'));
        $this->assertContains('MRADI', array_column($s['lines'], 'obligation_label'));

        // Records, not cash: the books' cash and this month's money in do not move.
        $this->api($this->people['treasurer'], 'GET', '/transactions/summary')->assertOk()->assertJsonPath('data.cash_on_record', 0);
        $d = $this->api($this->owner, 'GET', '/dashboard?month=2026-06')->assertOk()->json('data.money');
        $this->assertEquals(0, $d['cash_on_record']);
        $this->assertEquals(0, $d['month_in']);
        $this->assertEquals(1300000, $d['savings'], 'the group still holds his savings for him');

        // Michael sees it on his own account.
        $me = $this->api($this->people['michael'], 'GET', '/me')->assertOk()->json('data');
        $this->assertEquals(1300000, $me['balances']['savings']);
        $this->assertEquals(200000, $me['refundable']);

        // The leaders' list shows what was entered.
        $this->api($this->people['treasurer'], 'GET', "/members/{$this->ids['michael']}/previous")->assertOk()->assertJsonCount(5, 'data.entries');
    }

    public function test_only_a_leader_enters_previous_data_and_never_their_own(): void
    {
        $michael = "/members/{$this->ids['michael']}/previous";
        $this->api($this->people['michael'], 'POST', "/members/{$this->ids['chair']}/previous", ['as_of' => '2026-06-30', 'savings' => 5000])->assertForbidden()->assertJsonPath('code', 'leaders_only');
        $this->api($this->people['chair'], 'POST', "/members/{$this->ids['chair']}/previous", ['as_of' => '2026-06-30', 'savings' => 5000])->assertForbidden()->assertJsonPath('code', 'own_record');
        $this->api($this->people['chair'], 'POST', $michael, ['as_of' => '2026-06-30', 'savings' => 5000], true)->assertForbidden()->assertJsonPath('code', 'leaders_only');
        $this->api($this->people['chair'], 'POST', $michael, ['as_of' => '2026-06-30'])->assertStatus(422)->assertJsonPath('code', 'nothing_entered');
        $this->api($this->people['chair'], 'POST', $michael, ['as_of' => '2027-01-01', 'savings' => 5000])->assertStatus(422);
        $this->assertSame(0, DB::table('group_transactions')->count());
    }

    public function test_a_mistake_is_removed_never_reversed(): void
    {
        $this->api($this->people['chair'], 'POST', "/members/{$this->ids['michael']}/previous", ['as_of' => '2026-06-30', 'shares' => 99000])->assertCreated();
        $tx = (int) DB::table('group_transactions')->value('id');
        $this->api($this->owner, 'POST', "/transactions/{$tx}/reverse", ['reason' => 'mistake'])->assertStatus(409);
        $this->assertSame(1, DB::table('group_transactions')->count(), 'nothing was reversed');

        $this->api($this->people['michael'], 'DELETE', "/previous/entries/{$tx}")->assertForbidden();
        $this->api($this->people['treasurer'], 'DELETE', "/previous/entries/{$tx}")->assertOk();
        $this->assertSame(0, DB::table('group_transactions')->count());
        $this->assertTrue(DB::table('group_audit_log')->where('action', 'previous_removed')->exists());
    }

    public function test_a_running_loan_starts_from_what_is_left_and_is_repaid_like_any_loan(): void
    {
        $loan = $this->api($this->people['chair'], 'POST', "/members/{$this->ids['michael']}/previous/loan", [
            'amount' => 500000, 'remaining' => 250000, 'instalment' => 100000, 'next_due' => '2026-12-05', 'issued_on' => '2026-05-01', 'purpose' => 'Mtaji',
        ])->assertCreated()->json('data.loan');
        $this->assertSame('active', $loan['status']);
        $this->assertEquals(250000, $loan['outstanding']);
        $schedule = DB::table('group_loan_schedule')->where('loan_id', $loan['id'])->orderBy('number')->get();
        $this->assertSame(['2026-12-05', '2027-01-05', '2027-02-05'], $schedule->pluck('due_date')->map(fn ($d) => (string) $d)->all());
        $this->assertEquals([100000, 100000, 50000], $schedule->pluck('principal_due')->map(fn ($v) => (float) $v)->all());
        $this->assertSame(0, DB::table('group_transactions')->count(), 'no cash went out for it here');

        // Repaid under Payments like any loan; then it can no longer be removed.
        $tx = $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids['michael'], 'category' => 'loan_repayment', 'loan_id' => $loan['id'], 'amount' => 100000, 'method' => 'cash'])
            ->assertCreated()->json('data.transaction.id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$tx}/verify")->assertOk();
        $this->api($this->people['treasurer'], 'GET', "/members/{$this->ids['michael']}/previous")->assertOk()->assertJsonPath('data.loans.0.outstanding', 150000);
        $this->api($this->people['treasurer'], 'DELETE', "/previous/loans/{$loan['id']}")->assertStatus(409)->assertJsonPath('code', 'loan_has_repayments');
    }

    public function test_a_previous_loan_entered_by_mistake_is_removed_and_refundable_survives_an_older_app(): void
    {
        $loan = $this->api($this->people['chair'], 'POST', "/members/{$this->ids['michael']}/previous/loan", ['amount' => 80000, 'remaining' => 80000, 'instalment' => 20000, 'next_due' => '2026-12-01'])
            ->assertCreated()->json('data.loan.id');
        $this->api($this->people['chair'], 'DELETE', "/previous/loans/{$loan}")->assertOk();
        $this->assertSame(0, DB::table('group_loans')->count());
        $this->assertSame(0, DB::table('group_loan_schedule')->count());

        // An older app edits MRADI without knowing "refundable": it stays refundable.
        $this->api($this->owner, 'PUT', "/contribution-types/{$this->types['MRADI']}", ['name' => 'MRADI', 'amount' => 250000, 'frequency' => 'event'])
            ->assertCreated()->assertJsonPath('data.type.refundable', true);
    }
}
