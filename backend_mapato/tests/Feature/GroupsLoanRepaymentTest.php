<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupLoans;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Groups (Vikundi): how often a loan is repaid. The group chooses a rhythm (every day from tomorrow, every week, two weeks, month, two
 * months, three months, six months, or every N days); each loan keeps the rhythm of the day it was applied under; the interest of a loan is
 * its rate for its months whatever the rhythm; the last instalment falls on the day the loan ends.
 */
class GroupsLoanRepaymentTest extends TestCase
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
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['treasurer', '0712000002', 'mweka_hazina'], ['assistant', '0712000003', 'mweka_hazina_msaidizi'],
            ['projects', '0712000006', 'mwenyekiti_miradi'], ['asha', '0713000001', null], ['juma', '0713000002', null]] as [$key, $phone, $office]) {
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

    private function settings(array $values): void
    {
        $this->api($this->owner, 'PUT', '/settings', ['values' => $values, 'reason' => 'Loan policy'])->assertOk();
    }

    private function paidIn(string $who, string $category, float $amount): void
    {
        $tx = $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids[$who], 'category' => $category, 'amount' => $amount, 'method' => 'cash'])->assertCreated()->json('data.transaction.id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$tx}/verify")->assertOk();
    }

    /** A borrower with enough savings and shares, and the group's terms set with [every] as the rhythm. */
    private function ready(string $every, int $maxMonths = 12, ?int $days = null): void
    {
        $this->settings(['share_amount' => 200000, 'loan_multiplier' => 3, 'loan_interest_rate' => 2, 'loan_interest_method' => 'flat', 'loan_max_months' => $maxMonths,
            'loan_guarantors' => 0, 'loan_repayment' => $every] + ($days === null ? [] : ['loan_repayment_days' => $days]));
        $this->paidIn('asha', 'savings', 400000);
        $this->paidIn('asha', 'shares', 200000);
    }

    /** @return array<int, string> the due dates of a schedule */
    private function dates(array $rows): array
    {
        return array_column($rows, 'due_date');
    }

    public function test_a_daily_loan_is_first_paid_tomorrow_and_a_weekly_one_a_week_after(): void
    {
        $daily = GroupLoans::schedule(300000, 2, 'flat', 1, '2026-11-10', 'daily');
        $this->assertSame('2026-11-11', $daily[0]['due_date'], 'borrowed today, first paid tomorrow');
        $this->assertCount(30, $daily, 'a month of daily instalments (10 Nov to 10 Dec)');
        $this->assertSame('2026-12-10', end($daily)['due_date'], 'the last is on the day the loan ends');

        $weekly = GroupLoans::schedule(240000, 2, 'flat', 3, '2026-11-10', 'weekly');
        $this->assertSame(['2026-11-17', '2026-11-24', '2026-12-01'], array_slice($this->dates($weekly), 0, 3));
        $this->assertCount(13, $weekly, '3 months is 92 days: 13 whole weeks');
        $this->assertSame('2027-02-10', end($weekly)['due_date'], 'the last absorbs the days over');

        $fortnight = GroupLoans::schedule(240000, 2, 'flat', 2, '2026-11-10', 'every_2_weeks');
        $this->assertSame('2026-11-24', $fortnight[0]['due_date']);
        $this->assertCount(4, $fortnight);
    }

    public function test_the_month_based_rhythms_and_every_n_days(): void
    {
        $this->assertSame(['2026-12-10', '2027-01-10', '2027-02-10', '2027-03-10', '2027-04-10', '2027-05-10'], $this->dates(GroupLoans::schedule(240000, 2, 'flat', 6, '2026-11-10')), 'monthly is as it always was');
        $this->assertSame(['2027-01-10', '2027-03-10', '2027-05-10'], $this->dates(GroupLoans::schedule(240000, 2, 'flat', 6, '2026-11-10', 'every_2_months')));
        $this->assertSame(['2027-02-10', '2027-05-10'], $this->dates(GroupLoans::schedule(240000, 2, 'flat', 6, '2026-11-10', 'quarterly')), 'every three months');
        $this->assertSame(['2027-05-10', '2027-11-10'], $this->dates(GroupLoans::schedule(240000, 2, 'flat', 12, '2026-11-10', 'every_6_months')));
        $this->assertSame(['2026-11-20', '2026-11-30', '2026-12-10'], $this->dates(GroupLoans::schedule(100000, 2, 'flat', 1, '2026-11-10', 'custom', 10)), 'every 10 days');
        // A loan shorter than one period is one instalment, on its last day.
        $this->assertSame(['2027-02-10'], $this->dates(GroupLoans::schedule(100000, 2, 'flat', 3, '2026-11-10', 'every_6_months')));
    }

    public function test_whatever_the_rhythm_the_loan_costs_its_rate_for_its_months_and_adds_up_to_the_cent(): void
    {
        foreach (['daily', 'weekly', 'every_2_weeks', 'monthly', 'every_2_months', 'quarterly', 'every_6_months', 'custom'] as $every) {
            $rows = GroupLoans::schedule(240000, 2, 'flat', 6, '2026-11-10', $every, 9);
            $this->assertEquals(240000, round(array_sum(array_column($rows, 'principal_due')), 2), "{$every}: the principal is repaid in full");
            $this->assertEquals(28800, round(array_sum(array_column($rows, 'interest_due')), 2), "{$every}: 2% a month flat for 6 months is 28,800 at any rhythm");
        }
        // A reducing loan also repays its principal exactly, with less interest than a flat one.
        foreach (['daily', 'weekly', 'monthly', 'quarterly'] as $every) {
            $rows = GroupLoans::schedule(240000, 2, 'reducing', 6, '2026-11-10', $every);
            $this->assertEquals(240000, round(array_sum(array_column($rows, 'principal_due')), 2), "{$every}: reducing repays the principal in full");
            $this->assertLessThan(28800, array_sum(array_column($rows, 'interest_due')), "{$every}: interest on what is still owed is less than flat");
        }
    }

    public function test_the_group_chooses_its_rhythm_and_a_wrong_one_is_refused(): void
    {
        $this->settings(['loan_repayment' => 'weekly']);
        $this->api($this->people['asha'], 'GET', '/settings')->assertOk()->assertJsonPath('data.settings.loan_repayment', 'weekly');
        $this->settings(['loan_repayment' => 'custom', 'loan_repayment_days' => 45]);
        $this->api($this->people['asha'], 'GET', '/settings')->assertJsonPath('data.settings.loan_repayment_days', '45');
        $this->api($this->owner, 'PUT', '/settings', ['values' => ['loan_repayment' => 'sometimes'], 'reason' => 'x x x'])->assertStatus(422);
        $this->api($this->owner, 'PUT', '/settings', ['values' => ['loan_repayment_days' => 0], 'reason' => 'x x x'])->assertStatus(422);
        $this->api($this->owner, 'PUT', '/settings', ['values' => ['loan_repayment_days' => 400], 'reason' => 'x x x'])->assertStatus(422);
    }

    public function test_a_loan_keeps_the_rhythm_it_was_applied_under_and_its_instalments_follow_it(): void
    {
        $this->ready('weekly');
        $this->api($this->people['asha'], 'GET', '/me/loan-eligibility')->assertOk()->assertJsonPath('data.terms.repayment', 'weekly');
        $loan = $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 240000, 'purpose' => 'Mtaji wa duka', 'term_months' => 3])->assertCreated()
            ->assertJsonPath('data.loan.repayment_every', 'weekly')->json('data.loan');
        $id = $loan['id'];
        $this->assertCount(13, $loan['preview']['instalments']);
        $this->assertSame('2026-11-17', $loan['preview']['instalments'][0]['due_date']);

        // The group changes its rhythm afterwards: this loan stays weekly.
        $this->settings(['loan_repayment' => 'quarterly']);
        $this->api($this->people['asha'], 'GET', "/loans/{$id}")->assertJsonPath('data.loan.repayment_every', 'weekly');

        $this->api($this->people['projects'], 'POST', "/loans/{$id}/recommend", ['amount' => 240000, 'note' => 'Good record'])->assertOk();
        $this->api($this->people['chair'], 'POST', "/loans/{$id}/approve")->assertOk();
        $this->api($this->people['treasurer'], 'POST', "/loans/{$id}/disburse", ['method' => 'cash'])->assertOk();
        $payout = (int) DB::table('group_transactions')->where('loan_id', $id)->where('category', 'loan_disbursement')->value('id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$payout}/verify")->assertOk();

        $running = $this->api($this->people['asha'], 'GET', "/loans/{$id}")->assertJsonPath('data.loan.state', 'active')->json('data.loan');
        $this->assertCount(13, $running['position']['instalments']);
        $this->assertSame('2026-11-17', $running['position']['instalments'][0]['due_date'], 'a week after the payout');
        $this->assertEquals(254400, $running['position']['outstanding'], '240,000 plus 2% a month for 3 months (14,400), at any rhythm');

        // A second loan, applied after the change, is quarterly.
        $this->paidIn('juma', 'savings', 400000);
        $this->paidIn('juma', 'shares', 200000);
        $this->api($this->people['juma'], 'POST', '/me/loans', ['amount' => 120000, 'purpose' => 'Ada', 'term_months' => 6])->assertCreated()->assertJsonPath('data.loan.repayment_every', 'quarterly');
    }

    public function test_a_rhythm_that_would_make_too_many_instalments_is_refused_with_the_limit(): void
    {
        $this->ready('daily', 36);
        $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 100000, 'purpose' => 'Mtaji', 'term_months' => 24])->assertStatus(422)->assertJsonPath('code', 'too_many_instalments')->assertJsonPath('max', 400);
        $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 100000, 'purpose' => 'Mtaji', 'term_months' => 12])->assertCreated()->assertJsonPath('data.loan.repayment_every', 'daily');
    }

    public function test_every_n_days_is_remembered_with_the_loan(): void
    {
        $this->ready('custom', 12, 15);
        $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 150000, 'purpose' => 'Mtaji', 'term_months' => 3])->assertCreated()
            ->assertJsonPath('data.loan.repayment_every', 'custom')->assertJsonPath('data.loan.repayment_days', 15)->assertJsonPath('data.loan.preview.instalments.0.due_date', '2026-11-25');
    }
}
