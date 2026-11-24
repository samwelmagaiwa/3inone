<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Groups (Vikundi), phase 2: contributions and what each member owes, exemptions (udhuru), savings in and out, group expenses, promises,
 * statements, and the morning job that raises the month and reminds members.
 */
class GroupsMoneyTest extends TestCase
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
        Carbon::setTestNow(Carbon::parse('2026-11-10 08:00:00'));
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'MEG Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG']);
        foreach ([['chair', 'Mwenyekiti', '0712000001', 'mwenyekiti'], ['treasurer', 'Mweka Hazina', '0712000002', 'mweka_hazina'],
            ['assistant', 'Msaidizi', '0712000003', 'mweka_hazina_msaidizi'], ['secretary', 'Katibu', '0712000004', 'katibu'],
            ['asha', 'Asha Juma', '0713000001', null], ['juma', 'Juma Ali', '0713000002', null]] as [$key, $name, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => $name, 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
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

    private function jamii(): int
    {
        $type = $this->api($this->people['chair'], 'POST', '/contribution-types', ['name' => 'JAMII', 'amount' => 10000, 'frequency' => 'monthly', 'due_day' => 5, 'starts_on' => '2026-01-01'])
            ->assertCreated()->json('data.type.id');
        $this->api($this->people['treasurer'], 'POST', "/contribution-types/{$type}/raise", ['month' => '2026-11'])->assertOk()->assertJsonPath('data.created', 6);

        return $type;
    }

    private function obligationOf(string $who, int $type): int
    {
        return (int) DB::table('group_obligations')->where('member_id', $this->ids[$who])->where('contribution_type_id', $type)->value('id');
    }

    public function test_a_call_is_raised_once_for_every_active_member_and_payments_close_it(): void
    {
        $type = $this->jamii();
        $this->api($this->people['treasurer'], 'POST', "/contribution-types/{$type}/raise", ['month' => '2026-11'])->assertJsonPath('data.created', 0);
        // An application waiting for approval owes nothing yet.
        $this->api($this->owner, 'POST', '/members', ['full_name' => 'New', 'phone' => '0719000000'])->assertCreated();
        $this->assertSame(6, DB::table('group_obligations')->count());

        $asha = $this->obligationOf('asha', $type);
        $this->api($this->people['asha'], 'GET', '/me')->assertJsonPath('data.owing.0.id', $asha)
            ->assertJsonPath('data.owing.0.state', 'overdue')->assertJsonPath('data.owing.0.remaining', 10000);

        $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'contribution', 'obligation_id' => $asha, 'amount' => 12000, 'method' => 'cash'])
            ->assertStatus(422)->assertJsonPath('code', 'more_than_owed');
        $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'contribution', 'obligation_id' => $this->obligationOf('juma', $type), 'amount' => 1000, 'method' => 'cash'])
            ->assertStatus(422)->assertJsonPath('code', 'obligation_required');
        $tx = $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'contribution', 'obligation_id' => $asha, 'amount' => 10000, 'method' => 'cash'])
            ->assertCreated()->json('data.transaction.id');
        // A second payment for what is already waiting to be verified would pay it twice.
        $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'contribution', 'obligation_id' => $asha, 'amount' => 1, 'method' => 'cash'])
            ->assertStatus(422)->assertJsonPath('code', 'more_than_owed');

        $this->api($this->people['assistant'], 'POST', "/transactions/{$tx}/verify")->assertOk()->assertJsonPath('data.transaction.obligation_label', 'JAMII · 2026-11');
        $this->api($this->people['asha'], 'GET', '/me')->assertJsonPath('data.owing', []);
        $this->api($this->people['treasurer'], 'GET', '/obligations?state=paid')->assertJsonCount(1, 'data.obligations');

        $summary = $this->api($this->people['treasurer'], 'GET', '/transactions/summary?month=2026-11')->assertOk();
        $this->assertEquals(60000, $summary->json('data.contributions.expected'));
        $this->assertEquals(10000, $summary->json('data.contributions.collected'));
        $this->assertSame(5, $summary->json('data.contributions.overdue_members'));
    }

    public function test_udhuru_excuses_a_member_with_a_reason_but_nobody_excuses_themself(): void
    {
        $type = $this->jamii();
        $juma = $this->obligationOf('juma', $type);
        $this->api($this->people['treasurer'], 'POST', "/obligations/{$juma}/exempt", ['reason' => 'Sick'])->assertForbidden();
        $this->api($this->people['chair'], 'POST', '/obligations/' . $this->obligationOf('chair', $type) . '/exempt', ['reason' => 'Mine'])
            ->assertForbidden()->assertJsonPath('code', 'own_obligation');
        $this->api($this->people['chair'], 'POST', "/obligations/{$juma}/exempt", ['reason' => 'Hospital, approved by the meeting'])->assertOk();

        $this->api($this->people['juma'], 'GET', '/me')->assertJsonPath('data.owing', []);
        $this->api($this->people['treasurer'], 'GET', '/obligations?state=exempt')->assertJsonPath('data.obligations.0.exempt_reason', 'Hospital, approved by the meeting');
        $this->api($this->people['chair'], 'POST', "/obligations/{$juma}/exempt", ['reason' => 'again'])->assertStatus(409);
    }

    public function test_savings_go_in_freely_but_out_only_through_the_treasurer_and_never_past_the_balance(): void
    {
        $tx = $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'savings', 'amount' => 50000, 'method' => 'mpesa', 'external_ref' => 'SAV1'])->json('data.transaction.id');
        $this->api($this->people['treasurer'], 'POST', "/transactions/{$tx}/verify")->assertOk();

        // A member never sends money out for themself.
        $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'savings', 'amount' => 1000, 'method' => 'cash', 'direction' => 'out'])->assertCreated()
            ->assertJsonPath('data.transaction.direction', 'in');
        $withdraw = ['member_id' => $this->ids['asha'], 'category' => 'savings', 'direction' => 'out', 'amount' => 30000, 'method' => 'cash'];
        $this->api($this->people['secretary'], 'POST', '/transactions', $withdraw)->assertForbidden()->assertJsonPath('code', 'payout_right_needed');
        $this->api($this->people['treasurer'], 'POST', '/transactions', ['amount' => 60000] + $withdraw)->assertStatus(422)->assertJsonPath('code', 'more_than_savings');
        $out = $this->api($this->people['treasurer'], 'POST', '/transactions', $withdraw)->assertCreated()->json('data.transaction.id');
        // While it waits, a second withdrawal cannot take the same money.
        $this->api($this->people['treasurer'], 'POST', '/transactions', ['amount' => 30000] + $withdraw)->assertStatus(422)->assertJsonPath('code', 'more_than_savings');
        $this->api($this->people['treasurer'], 'POST', "/transactions/{$out}/verify")->assertForbidden()->assertJsonPath('code', 'own_submission');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$out}/verify")->assertOk();

        $statement = $this->api($this->people['asha'], 'GET', '/me/statement')->assertOk();
        $this->assertEquals(20000, $statement->json('data.balances.savings'));
        $this->assertEquals(20000, $statement->json('data.lines.0.balance_after'));
        $this->assertEquals(50000, $statement->json('data.lines.1.balance_after'));
        $this->assertCount(1, $statement->json('data.waiting'), 'the 1,000 still waits and changed nothing');
    }

    public function test_a_group_expense_names_who_was_paid_and_shows_in_the_cash_on_record(): void
    {
        $tx = $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'shares', 'amount' => 200000, 'method' => 'cash'])->json('data.transaction.id');
        $this->api($this->people['treasurer'], 'POST', "/transactions/{$tx}/verify")->assertOk();

        $this->api($this->people['treasurer'], 'POST', '/transactions', ['category' => 'expense', 'amount' => 15000, 'method' => 'cash'])
            ->assertStatus(422)->assertJsonPath('code', 'payee_required');
        $spend = $this->api($this->people['treasurer'], 'POST', '/transactions', ['category' => 'expense', 'amount' => 15000, 'method' => 'cash', 'payee' => 'Ukumbi wa mikutano', 'note' => 'Hall hire'])
            ->assertCreated()->assertJsonPath('data.transaction.direction', 'out')->assertJsonPath('data.transaction.member_id', null)->json('data.transaction.id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$spend}/verify")->assertOk();

        $summary = $this->api($this->people['chair'], 'GET', '/transactions/summary?month=2026-11')->assertOk();
        $this->assertEquals(185000, $summary->json('data.cash_on_record'));
        $this->assertEquals(15000, $summary->json('data.expenses_in_month'));
        $this->assertEquals(-15000, $summary->json('data.verified.expense'));
    }

    public function test_a_promise_changes_no_balance_and_is_kept_once_the_money_is_verified(): void
    {
        $type = $this->jamii();
        $asha = $this->obligationOf('asha', $type);
        $promise = $this->api($this->people['asha'], 'POST', '/me/promises', ['obligation_id' => $asha, 'amount' => 10000, 'promised_on' => '2026-11-20', 'note' => 'Mshahara'])
            ->assertCreated()->assertJsonPath('data.promise.state', 'due')->json('data.promise.id');
        $this->api($this->people['asha'], 'GET', '/me')->assertJsonPath('data.owing.0.remaining', 10000)->assertJsonPath('data.promises.0.id', $promise);

        $tx = $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids['asha'], 'category' => 'contribution', 'obligation_id' => $asha, 'amount' => 10000, 'method' => 'cash'])->json('data.transaction.id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$tx}/verify")->assertOk();
        $this->api($this->people['treasurer'], 'GET', '/promises')->assertJsonPath('data.promises.0.state', 'kept');

        // Only the member or a leader who records payments can withdraw a promise.
        $other = $this->api($this->people['asha'], 'POST', '/me/promises', ['amount' => 5000, 'promised_on' => '2026-11-25'])->json('data.promise.id');
        $this->api($this->people['juma'], 'POST', "/promises/{$other}/cancel")->assertForbidden();
        $this->api($this->people['asha'], 'POST', "/promises/{$other}/cancel")->assertOk();
    }

    public function test_the_morning_job_raises_the_month_and_texts_without_amounts_once(): void
    {
        $this->api($this->people['chair'], 'POST', '/contribution-types', ['name' => 'JAMII', 'amount' => 10000, 'frequency' => 'monthly', 'due_day' => 13, 'starts_on' => '2026-01-01'])->assertCreated();

        Artisan::call('groups:daily');
        $this->assertSame(6, DB::table('group_obligations')->where('period', '2026-11')->count(), 'raised although nobody pressed a button');
        $this->assertCount(0, $this->sms->sent, 'reminders are off until the group switches them on');

        $this->api($this->owner, 'PUT', '/settings', ['values' => ['sms_reminders' => 'on'], 'reason' => 'Meeting decided'])->assertOk();
        Artisan::call('groups:daily');
        $texts = collect($this->sms->sent);
        $this->assertCount(6, $texts, 'due in 3 days (the 13th): every active member once');
        $this->assertStringContainsString('MEG', $texts->first()['message']);
        $this->assertStringNotContainsString('10,000', $texts->implode('message', ' '), 'no amounts by default');

        Artisan::call('groups:daily');
        $this->assertCount(6, $this->sms->sent, 'a rerun the same day texts nobody again');

        $this->api($this->owner, 'PUT', '/settings', ['values' => ['sms_show_amounts' => 'on'], 'reason' => 'Members asked'])->assertOk();
        Carbon::setTestNow(Carbon::parse('2026-11-14 08:00:00'));
        Artisan::call('groups:daily');
        $this->assertCount(12, $this->sms->sent, 'the day after it fell due: overdue');
        $this->assertStringContainsString('TSh 10,000', collect($this->sms->sent)->last()['message']);
    }

    public function test_only_leaders_who_handle_money_see_who_owes(): void
    {
        $this->jamii();
        $this->api($this->people['asha'], 'GET', '/obligations')->assertForbidden();
        $this->api($this->people['asha'], 'GET', '/members/' . $this->ids['juma'] . '/statement')->assertForbidden();
        $this->api($this->people['secretary'], 'GET', '/obligations')->assertOk(); // records payments
        $this->api($this->people['chair'], 'GET', '/me')->assertJsonPath('data.waiting.members_overdue', 6);
    }
}
