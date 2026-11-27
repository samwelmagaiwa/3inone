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
 * Groups (Vikundi), phase 3: loans (eligibility, guarantors, the committee's recommendation, the chair's approval, the payout and its
 * verification, instalments and repayments) and welfare (request, the chair's decision, the treasurer's payment, verification).
 */
class GroupsLoansWelfareTest extends TestCase
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
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['deputy', '0712000005', 'makamu_mwenyekiti'], ['treasurer', '0712000002', 'mweka_hazina'],
            ['assistant', '0712000003', 'mweka_hazina_msaidizi'], ['secretary', '0712000004', 'katibu'], ['projects', '0712000006', 'mwenyekiti_miradi'],
            ['asha', '0713000001', null], ['juma', '0713000002', null]] as [$key, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            if ($office !== null) {
                $this->api($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
        $this->api($this->owner, 'PUT', '/settings', ['values' => ['share_amount' => 200000, 'loan_multiplier' => 3], 'reason' => 'Rules'])->assertOk();
        // The cash the group held before it kept its books here, so payouts have money on record to come from.
        DB::table('group_transactions')->insert([
            'owner_id' => $this->owner->id, 'reference' => 'TX-OPENING', 'member_id' => null, 'category' => 'opening_balance', 'direction' => 'in',
            'amount' => 10000000, 'method' => 'cash', 'paid_on' => now()->toDateString(), 'status' => 'verified', 'verified_at' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);
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

    /** A verified payment in for [who] (recorded by the treasurer, verified by the assistant). */
    private function paidIn(string $who, string $category, float $amount): void
    {
        $tx = $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids[$who], 'category' => $category, 'amount' => $amount, 'method' => 'cash'])
            ->assertCreated()->json('data.transaction.id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$tx}/verify")->assertOk();
    }

    private function terms(): void
    {
        $this->api($this->people['chair'], 'PUT', '/settings', [
            'values' => ['loan_interest_rate' => 2, 'loan_interest_method' => 'flat', 'loan_max_months' => 12, 'loan_guarantors' => 1],
            'reason' => 'Loan policy',
        ])->assertOk();
    }

    public function test_nobody_borrows_before_the_group_sets_its_terms_and_the_ceiling_is_savings_times_three(): void
    {
        $this->paidIn('asha', 'savings', 100000);
        $this->api($this->people['asha'], 'GET', '/me/loan-eligibility')->assertOk()
            ->assertJsonPath('data.eligible', false)->assertJsonPath('data.reasons', ['terms_not_set', 'shares_unpaid']);
        $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 100000, 'purpose' => 'Biashara', 'term_months' => 6, 'guarantor_ids' => [$this->ids['juma']]])
            ->assertStatus(422)->assertJsonPath('code', 'not_eligible');

        $this->terms();
        $this->paidIn('asha', 'shares', 200000);
        $e = $this->api($this->people['asha'], 'GET', '/me/loan-eligibility')->assertJsonPath('data.eligible', true);
        $this->assertEquals(300000, $e->json('data.ceiling'));
        $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 350000, 'purpose' => 'Biashara', 'term_months' => 6, 'guarantor_ids' => [$this->ids['juma']]])
            ->assertStatus(422)->assertJsonPath('code', 'over_ceiling');
        $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 100000, 'purpose' => 'Biashara', 'term_months' => 13, 'guarantor_ids' => [$this->ids['juma']]])
            ->assertStatus(422)->assertJsonPath('code', 'term_too_long');
        $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 100000, 'purpose' => 'Biashara', 'term_months' => 6])
            ->assertStatus(422)->assertJsonPath('code', 'guarantors_needed');
        $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 100000, 'purpose' => 'Biashara', 'term_months' => 6, 'guarantor_ids' => [$this->ids['asha']]])
            ->assertStatus(422)->assertJsonPath('code', 'bad_guarantor');
    }

    public function test_a_loan_goes_through_every_step_by_the_right_person_and_repayments_go_to_interest_first(): void
    {
        $this->terms();
        $this->paidIn('asha', 'savings', 100000);
        $this->paidIn('asha', 'shares', 200000);

        $loan = $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 240000, 'purpose' => 'Mtaji wa duka', 'term_months' => 6, 'guarantor_ids' => [$this->ids['juma']]])
            ->assertCreated()->assertJsonPath('data.loan.status', 'awaiting_guarantors')->assertJsonPath('data.loan.interest_rate', 2)->json('data.loan');
        $id = $loan['id'];
        $this->assertEquals(28800, $loan['preview']['total_interest'], '2% a month flat on 240,000 for 6 months');
        $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 1000, 'purpose' => 'x x', 'term_months' => 1, 'guarantor_ids' => [$this->ids['juma']]])
            ->assertStatus(409)->assertJsonPath('code', 'open_application');

        // The committee cannot recommend before the guarantor has answered.
        $this->api($this->people['projects'], 'POST', "/loans/{$id}/recommend", ['amount' => 200000, 'note' => 'Good record'])->assertStatus(409);
        $this->api($this->people['juma'], 'GET', '/me')->assertJsonPath('data.waiting.guarantees', 1);
        $g = $this->api($this->people['juma'], 'GET', '/me/loans')->json('data.guarantees.0.id');
        $this->api($this->people['secretary'], 'POST', "/guarantees/{$g}/respond", ['accept' => true])->assertForbidden();
        $this->api($this->people['juma'], 'POST', "/guarantees/{$g}/respond", ['accept' => true])->assertOk()->assertJsonPath('data.loan.status', 'under_review');

        $this->api($this->people['chair'], 'POST', "/loans/{$id}/approve")->assertStatus(409, 'the chair approves only what the committee recommended');
        $this->api($this->people['projects'], 'POST', "/loans/{$id}/recommend", ['amount' => 250000, 'note' => 'More'])->assertStatus(422);
        $this->api($this->people['projects'], 'POST', "/loans/{$id}/recommend", ['amount' => 200000, 'note' => 'Good record'])->assertOk()->assertJsonPath('data.loan.status', 'recommended');
        $this->api($this->people['treasurer'], 'POST', "/loans/{$id}/approve")->assertForbidden();
        $this->api($this->people['chair'], 'POST', "/loans/{$id}/approve")->assertOk()->assertJsonPath('data.loan.status', 'approved')->assertJsonPath('data.loan.amount_approved', 200000);

        $this->api($this->people['chair'], 'POST', "/loans/{$id}/disburse", ['method' => 'cash'])->assertForbidden();
        $this->api($this->people['treasurer'], 'POST', "/loans/{$id}/disburse", ['method' => 'mpesa', 'external_ref' => 'LNPAY1'])->assertOk();
        $this->api($this->people['treasurer'], 'POST', "/loans/{$id}/disburse", ['method' => 'cash'])->assertStatus(422)->assertJsonPath('code', 'loan_not_ready');
        $payout = (int) DB::table('group_transactions')->where('loan_id', $id)->where('category', 'loan_disbursement')->value('id');
        $this->api($this->people['treasurer'], 'POST', "/transactions/{$payout}/verify")->assertStatus(403)->assertJsonPath('code', 'own_submission');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$payout}/verify")->assertOk();

        $running = $this->api($this->people['asha'], 'GET', "/loans/{$id}")->assertOk()->assertJsonPath('data.loan.state', 'active')->json('data.loan');
        $this->assertCount(6, $running['position']['instalments']);
        $this->assertEquals(224000, $running['position']['outstanding']);
        $this->assertSame('2026-12-10', $running['position']['instalments'][0]['due_date']);

        $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'loan_repayment', 'loan_id' => $id, 'amount' => 300000, 'method' => 'cash'])
            ->assertStatus(422)->assertJsonPath('code', 'more_than_loan');
        $tx = $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'loan_repayment', 'loan_id' => $id, 'amount' => 40000, 'method' => 'cash'])->assertCreated()->json('data.transaction.id');
        $this->api($this->people['treasurer'], 'POST', "/transactions/{$tx}/verify")->assertOk();
        $p = $this->api($this->people['chair'], 'GET', "/loans/{$id}")->json('data.loan.position');
        $this->assertEquals(33333.33, $p['principal_paid']);
        $this->assertEquals(6666.67, $p['interest_paid']);
        $this->assertSame('paid', $p['instalments'][0]['state']);
        $this->assertEquals(184000, $p['outstanding']);

        $portfolio = $this->api($this->people['chair'], 'GET', '/loans')->assertOk()->json('data.portfolio');
        $this->assertEquals(200000, $portfolio['disbursed']);
        $this->assertEquals(6666.67, $portfolio['interest_paid']);

        // Paid out and repaid: the payout can no longer be undone.
        $this->api($this->people['treasurer'], 'POST', "/transactions/{$payout}/reverse", ['reason' => 'mistake'])->assertStatus(409);
        // Leaders see all of it; another member does not.
        $this->api($this->people['secretary'], 'GET', "/loans/{$id}")->assertForbidden();
        $this->api($this->people['juma'], 'GET', "/loans/{$id}")->assertOk();
    }

    public function test_nobody_decides_their_own_loan(): void
    {
        $this->terms();
        $this->paidIn('chair', 'savings', 100000);
        $this->paidIn('chair', 'shares', 200000);
        $id = $this->api($this->people['chair'], 'POST', '/me/loans', ['amount' => 100000, 'purpose' => 'Ada ya shule', 'term_months' => 3, 'guarantor_ids' => [$this->ids['juma']]])->json('data.loan.id');
        $g = $this->api($this->people['juma'], 'GET', '/me/loans')->json('data.guarantees.0.id');
        $this->api($this->people['juma'], 'POST', "/guarantees/{$g}/respond", ['accept' => true])->assertOk();
        $this->api($this->people['projects'], 'POST', "/loans/{$id}/recommend", ['amount' => 100000, 'note' => 'Fine'])->assertOk();

        $this->api($this->people['chair'], 'POST', "/loans/{$id}/approve")->assertForbidden()->assertJsonPath('code', 'own_loan');
        $this->api($this->people['chair'], 'POST', "/loans/{$id}/reject", ['reason' => 'mine'])->assertForbidden();
        $this->api($this->people['deputy'], 'POST', "/loans/{$id}/approve", ['amount' => 80000])->assertOk()->assertJsonPath('data.loan.amount_approved', 80000);
    }

    public function test_a_disbursement_reversed_before_any_repayment_puts_the_loan_back_to_approved(): void
    {
        $this->terms();
        $this->api($this->owner, 'PUT', '/settings', ['values' => ['loan_guarantors' => 0], 'reason' => 'No guarantors'])->assertOk();
        $this->paidIn('asha', 'savings', 50000);
        $this->paidIn('asha', 'shares', 200000);
        $id = $this->api($this->people['asha'], 'POST', '/me/loans', ['amount' => 60000, 'purpose' => 'Kilimo', 'term_months' => 2])
            ->assertCreated()->assertJsonPath('data.loan.status', 'under_review')->json('data.loan.id');
        $this->api($this->people['projects'], 'POST', "/loans/{$id}/recommend", ['amount' => 60000, 'note' => 'ok ok'])->assertOk();
        $this->api($this->people['chair'], 'POST', "/loans/{$id}/approve")->assertOk();
        $this->api($this->people['treasurer'], 'POST', "/loans/{$id}/disburse", ['method' => 'cash'])->assertOk();
        $payout = (int) DB::table('group_transactions')->where('loan_id', $id)->value('id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$payout}/verify")->assertOk();
        $this->assertSame(2, DB::table('group_loan_schedule')->where('loan_id', $id)->count());

        $this->api($this->people['treasurer'], 'POST', "/transactions/{$payout}/reverse", ['reason' => 'Paid the wrong member'])->assertOk();
        $this->assertSame('approved', DB::table('group_loans')->where('id', $id)->value('status'));
        $this->assertSame(0, DB::table('group_loan_schedule')->where('loan_id', $id)->count());
    }

    public function test_reducing_balance_instalments_are_equal_and_repay_exactly_the_principal(): void
    {
        $rows = GroupLoans::schedule(100000, 2, 'reducing', 12, '2026-01-15');
        $this->assertCount(12, $rows);
        $this->assertEqualsWithDelta(100000, array_sum(array_column($rows, 'principal_due')), 0.01);
        $first = $rows[0]['principal_due'] + $rows[0]['interest_due'];
        $this->assertEqualsWithDelta(9455.96, $first, 0.02);
        $this->assertEquals(2000, $rows[0]['interest_due'], 'interest on the whole amount the first month');
        $this->assertLessThan(200, $rows[11]['interest_due'], 'and almost nothing the last');
        $this->assertSame('2026-02-15', $rows[0]['due_date']);
    }

    public function test_welfare_is_approved_by_the_chair_paid_by_the_treasurer_and_paid_only_once_verified(): void
    {
        $type = $this->api($this->owner, 'POST', '/benefit-types', ['name' => 'Msiba', 'amount' => 100000])->assertOk()->json('data.types.0.id');
        $r = $this->api($this->people['asha'], 'POST', '/me/benefits', [
            'type_id' => $type, 'beneficiary' => 'Mama Asha', 'relationship' => 'parent', 'event_date' => '2026-11-08', 'description' => 'Private details',
        ])->assertCreated()->json('data.request.id');

        $this->api($this->people['secretary'], 'GET', '/benefits')->assertOk()->assertJsonPath('data.requests.0.description', null);
        $this->api($this->people['chair'], 'GET', '/benefits')->assertJsonPath('data.requests.0.description', 'Private details');
        $this->api($this->people['treasurer'], 'POST', "/benefits/{$r}/decide", ['approve' => true, 'amount' => 100000])->assertForbidden();
        $this->api($this->people['treasurer'], 'POST', "/benefits/{$r}/pay", ['method' => 'cash'])->assertStatus(422)->assertJsonPath('code', 'benefit_not_ready');
        $this->api($this->people['chair'], 'POST', "/benefits/{$r}/decide", ['approve' => true, 'amount' => 100000])->assertOk()->assertJsonPath('data.request.state', 'approved');

        $this->api($this->people['treasurer'], 'POST', "/benefits/{$r}/pay", ['method' => 'mpesa', 'external_ref' => 'MSB1'])->assertOk()->assertJsonPath('data.request.state', 'paying');
        $this->api($this->people['treasurer'], 'POST', "/benefits/{$r}/pay", ['method' => 'cash'])->assertStatus(422);
        $tx = (int) DB::table('group_transactions')->where('benefit_id', $r)->value('id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$tx}/verify")->assertOk();
        $this->api($this->people['asha'], 'GET', '/me/benefits')->assertJsonPath('data.requests.0.state', 'paid');

        // Nobody decides their own request.
        $own = $this->api($this->people['chair'], 'POST', '/me/benefits', ['type_id' => $type, 'beneficiary' => 'Self', 'relationship' => 'self', 'event_date' => '2026-11-09'])->json('data.request.id');
        $this->api($this->people['chair'], 'POST', "/benefits/{$own}/decide", ['approve' => true, 'amount' => 1000])->assertForbidden();
        $this->api($this->people['deputy'], 'POST', "/benefits/{$own}/decide", ['approve' => false, 'note' => 'Not covered'])->assertOk()->assertJsonPath('data.request.state', 'rejected');
    }
}
