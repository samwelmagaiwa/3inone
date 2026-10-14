<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\BusinessPayment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Paying for a plan: a super admin records the payment, the business's paid-until date moves on and everything
 * opens again at once, the owner is told by text, and the owner can always see what was paid and when the plan
 * started and ends. Every morning the owners (and the super admin) are texted about plans that are ending.
 */
class SubscriptionTest extends TestCase
{
    use RefreshDatabase;

    private int $phoneSeq = 0;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(now()->setDate(2026, 10, 15)->setTime(12, 0));
        config(['billing.grace_days' => 7, 'billing.enforce' => false, 'billing.contact_phone' => '']);
    }

    private function owner(string $name, ?string $validUntil, string $plan = 'basic', ?string $phone = null): User
    {
        $phone ??= '07220000' . str_pad((string) ++$this->phoneSeq, 2, '0', STR_PAD_LEFT);
        $owner = $this->givenServices(User::factory()->create([
            'name' => $name, 'role' => 'admin', 'is_active' => true,
            'phone_number' => $phone, 'password' => 'owner-pass-1',
        ]), 'transport', 'rental', 'inventory');

        Business::forOwnerId($owner->id)->update(['name' => $name . ' Ltd', 'plan' => $plan, 'valid_until' => $validUntil]);

        return $owner;
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function superAdmin(?string $phone = null): User
    {
        return User::factory()->create(['role' => 'super_admin', 'is_active' => true, 'phone_number' => $phone]);
    }

    private function business(User $owner): Business
    {
        return Business::forOwnerId($owner->id);
    }

    private function pay(User $super, User $owner, array $body = [])
    {
        return $this->as($super, 'POST', '/api/admin/businesses/' . $this->business($owner)->id . '/payments', array_merge(['amount' => 50000], $body));
    }

    // ------------------------------------------------------------- recording a payment

    public function test_paying_after_the_plan_ran_out_starts_from_today(): void
    {
        $owner = $this->owner('Alpha', '2026-10-01 23:59:59');

        $payment = $this->business($owner)->recordPayment(['amount' => 30000, 'months' => 1]);

        $this->assertSame('2026-10-15', $payment->period_start->toDateString());
        $this->assertSame('2026-11-15', $payment->period_end->toDateString());
        $this->assertSame('2026-11-15', $this->business($owner)->fresh()->valid_until->toDateString());
        $this->assertSame('23:59:59', $this->business($owner)->fresh()->valid_until->format('H:i:s'), 'works through the end of the last day');
    }

    public function test_paying_early_adds_time_after_the_current_end_so_nothing_paid_for_is_lost(): void
    {
        $owner = $this->owner('Alpha', '2026-10-20 23:59:59');

        $payment = $this->business($owner)->recordPayment(['amount' => 30000, 'months' => 3]);

        $this->assertSame('2026-10-21', $payment->period_start->toDateString(), 'the day after the current end');
        $this->assertSame('2027-01-20', $payment->period_end->toDateString());
        $this->assertSame('2027-01-20', $this->business($owner)->fresh()->valid_until->toDateString());
    }

    public function test_an_exact_end_date_can_be_given_and_a_trial_moves_to_a_paid_plan(): void
    {
        $owner = $this->owner('Alpha', '2026-10-18 23:59:59', 'trial');

        $this->business($owner)->recordPayment(['amount' => 1000, 'valid_until' => '2026-12-31']);
        $fresh = $this->business($owner)->fresh();

        $this->assertSame('2026-12-31', $fresh->valid_until->toDateString());
        $this->assertSame('basic', $fresh->plan, 'a trial that pays is on a paid plan');

        $this->business($owner)->recordPayment(['amount' => 1000, 'months' => 1, 'plan' => 'premium']);
        $this->assertSame('premium', $this->business($owner)->fresh()->plan, 'the super admin may choose the plan');
    }

    // ------------------------------------------------------- the super admin records it

    public function test_a_super_admin_records_a_payment_and_the_owner_is_texted(): void
    {
        $owner = $this->owner('Alpha', '2026-10-10 23:59:59', 'basic', '0722123456');
        $super = $this->superAdmin();

        $this->pay($super, $owner, ['amount' => 45000, 'method' => 'mobile_money', 'reference' => 'TRX123', 'months' => 2, 'note' => 'M-Pesa'])
            ->assertCreated()
            ->assertJsonPath('data.payment.amount', 45000)
            ->assertJsonPath('data.payment.method', 'mobile_money')
            ->assertJsonPath('data.subscription.status', 'active')
            ->assertJsonPath('data.subscription.days_left', 61);

        $payment = BusinessPayment::firstOrFail();
        $this->assertSame('2026-10-15', $payment->period_start->toDateString());
        $this->assertSame('2026-12-15', $payment->period_end->toDateString());
        $this->assertSame($super->id, $payment->recorded_by);

        $texts = $this->sms->to('0722123456');
        $this->assertCount(1, $texts);
        $this->assertStringContainsString('Malipo ya TZS 45,000', $texts[0]['message']);
        $this->assertStringContainsString('Payment of TZS 45,000', $texts[0]['message']);
        $this->assertStringContainsString('15/12/2026', $texts[0]['message'], 'it says until when');
    }

    public function test_a_payment_is_validated_and_only_a_super_admin_can_record_one(): void
    {
        $owner = $this->owner('Alpha', '2026-10-30 23:59:59');
        $super = $this->superAdmin();

        $this->pay($super, $owner, ['amount' => 0])->assertStatus(422);
        $this->pay($super, $owner, ['amount' => 'abc'])->assertStatus(422);
        $this->pay($super, $owner, ['valid_until' => '2026-10-01'])->assertStatus(422);
        $this->pay($super, $owner, ['method' => 'witchcraft'])->assertStatus(422);
        $this->pay($super, $owner, ['plan' => 'platinum'])->assertStatus(422);
        $this->assertSame(0, BusinessPayment::count(), 'nothing was recorded by a bad request');

        // An owner can never pay themselves into more time.
        $this->pay($owner, $owner, ['amount' => 1000])->assertForbidden();
        $this->assertSame('2026-10-30', $this->business($owner)->fresh()->valid_until->toDateString());
    }

    public function test_a_failing_sms_provider_never_blocks_recording_a_payment(): void
    {
        $owner = $this->owner('Alpha', '2026-10-10 23:59:59');
        $this->sms->failWith(new \RuntimeException('provider down'));

        $this->pay($this->superAdmin(), $owner)->assertCreated();

        $this->assertSame(1, BusinessPayment::count());
    }

    // ------------------------------------------------------------ the owner sees it

    public function test_the_owner_sees_the_plan_the_dates_and_what_was_paid(): void
    {
        $owner = $this->owner('Alpha', '2026-10-01 23:59:59');
        $this->business($owner)->recordPayment(['amount' => 30000, 'months' => 1, 'method' => 'cash', 'reference' => 'R-1', 'paid_at' => '2026-10-14']);

        $this->as($owner, 'GET', '/api/business/subscription')->assertOk()
            ->assertJsonPath('data.business_name', 'Alpha Ltd')
            ->assertJsonPath('data.is_owner', true)
            ->assertJsonPath('data.plan', 'basic')
            ->assertJsonPath('data.status', 'active')
            ->assertJsonPath('data.days_left', 31)
            ->assertJsonPath('data.last_payment.amount', 30000)
            ->assertJsonPath('data.last_payment.reference', 'R-1')
            ->assertJsonCount(1, 'data.payments');

        $response = $this->as($owner, 'GET', '/api/business/subscription');
        $this->assertStringStartsWith('2026-10-15', $response->json('data.started_at'), 'the day the paid period began');
        $this->assertStringStartsWith('2026-11-15', $response->json('data.valid_until'), 'the day it ends');
        $this->assertStringStartsWith('2026-10-14', $response->json('data.last_payment.paid_at'), 'the day it was paid');
    }

    public function test_staff_see_the_dates_but_not_the_money(): void
    {
        $owner = $this->owner('Alpha', '2026-10-20 23:59:59');
        $this->business($owner)->recordPayment(['amount' => 30000, 'months' => 1]);
        $manager = User::factory()->create(['role' => 'manager', 'is_active' => true, 'created_by' => $owner->id, 'phone_number' => '0733000111']);
        $this->givenServices($manager, 'transport');

        $this->as($manager, 'GET', '/api/business/subscription')->assertOk()
            ->assertJsonPath('data.is_owner', false)
            ->assertJsonPath('data.payments', [])
            ->assertJsonPath('data.status', 'active');
    }

    public function test_a_business_never_sees_another_business_and_a_super_admin_belongs_to_none(): void
    {
        $alpha = $this->owner('Alpha', '2026-10-20 23:59:59');
        $beta = $this->owner('Beta', '2026-12-31 23:59:59');
        $this->business($beta)->recordPayment(['amount' => 99000, 'months' => 1]);

        $this->as($alpha, 'GET', '/api/business/subscription')->assertOk()
            ->assertJsonPath('data.business_name', 'Alpha Ltd')
            ->assertJsonPath('data.payments', []);

        // Fail-closed, not just filtered by the controller: with Alpha signed in, even a bare query cannot see Beta's payment.
        $this->assertSame(1, \App\Models\BusinessPayment::withoutAccountScope()->count());
        $this->assertSame(0, \App\Models\BusinessPayment::count());

        $this->as($this->superAdmin(), 'GET', '/api/business/subscription')->assertNotFound()->assertJsonPath('errors.code', 'no_business');
    }

    public function test_the_super_admin_reads_every_payment_of_a_business(): void
    {
        $owner = $this->owner('Alpha', '2026-10-01 23:59:59');
        $super = $this->superAdmin();
        $this->pay($super, $owner, ['amount' => 1000])->assertCreated();
        $this->pay($super, $owner, ['amount' => 2000])->assertCreated();

        $this->as($super, 'GET', '/api/admin/businesses/' . $this->business($owner)->id . '/payments')->assertOk()
            ->assertJsonCount(2, 'data.payments')
            ->assertJsonPath('data.payments.0.amount', 2000);
        $this->as($owner, 'GET', '/api/admin/businesses/' . $this->business($owner)->id . '/payments')->assertForbidden();
    }

    // --------------------------------------------- stopping, and starting again on payment

    public function test_when_the_date_is_over_the_service_stops_and_paying_opens_it_again_at_once(): void
    {
        config(['billing.enforce' => true]);
        $owner = $this->owner('Alpha', '2026-10-01 23:59:59'); // two weeks over, seven allowed
        $super = $this->superAdmin();
        $token = $owner->createToken('device')->plainTextToken;
        $get = function (string $uri) use ($token) {
            $this->app['auth']->forgetGuards(); // the previous call may have left another user signed in
            return $this->withHeader('Authorization', "Bearer {$token}")->getJson($uri);
        };

        // Held back: a 402 with the reason, never a sign-out.
        $get('/api/admin/vehicles')->assertStatus(402)->assertJsonPath('errors.code', 'subscription_expired');
        // But the owner can still see what is wrong, and what to do.
        $get('/api/business/subscription')->assertOk()->assertJsonPath('data.status', 'expired')->assertJsonPath('data.blocked', true);

        $this->pay($super, $owner, ['amount' => 50000])->assertCreated();

        // Same device, same token: working again, nothing lost.
        $get('/api/admin/vehicles')->assertOk();
        $get('/api/business/subscription')->assertOk()->assertJsonPath('data.status', 'active')->assertJsonPath('data.blocked', false);
    }

    public function test_the_grace_days_still_work_but_say_so(): void
    {
        config(['billing.enforce' => true]);
        $owner = $this->owner('Alpha', '2026-10-12 23:59:59'); // three days over

        $this->as($owner, 'GET', '/api/admin/vehicles')->assertOk();
        $this->as($owner, 'GET', '/api/business/subscription')->assertOk()
            ->assertJsonPath('data.status', 'grace')
            ->assertJsonPath('data.blocked', false)
            ->assertJsonPath('data.grace_days', 7);
    }

    // ----------------------------------------------------------------------- reminders

    private function remind(): void
    {
        $this->artisan('billing:remind')->assertExitCode(0);
    }

    /** @return array<string, string> a business-name => the text its owner got */
    private function ownerTexts(array $owners): array
    {
        $out = [];
        foreach ($owners as $name => $owner) {
            $texts = array_values(array_filter($this->sms->to($owner->phone_number), fn (array $m) => str_contains($m['message'], $name . ' Ltd')));
            $out[$name] = $texts[0]['message'] ?? '';
        }

        return $out;
    }

    public function test_each_owner_is_told_at_the_right_time_and_the_super_admin_gets_one_summary(): void
    {
        $this->superAdmin('0711000111');
        $o = [
            'Seven' => $this->owner('Seven', '2026-10-22 23:59:59'),
            'Three' => $this->owner('Three', '2026-10-18 23:59:59'),
            'One' => $this->owner('One', '2026-10-16 23:59:59'),
            'Today' => $this->owner('Today', '2026-10-15 23:59:59'),
            'Late' => $this->owner('Late', '2026-10-13 23:59:59'),
            'Stopped' => $this->owner('Stopped', '2026-10-01 23:59:59'),
            'Far' => $this->owner('Far', '2026-12-01 23:59:59'),
        ];
        $forever = $this->owner('Forever', null, 'free');

        $this->remind();
        $texts = $this->ownerTexts($o + ['Forever' => $forever]);

        $this->assertStringContainsString('unaisha baada ya siku 7', $texts['Seven']);
        $this->assertStringContainsString('ends in 7 day(s)', $texts['Seven']);
        $this->assertStringContainsString('baada ya siku 3', $texts['Three']);
        $this->assertStringContainsString('baada ya siku 1', $texts['One']);
        $this->assertStringContainsString('unaisha leo', $texts['Today']);
        $this->assertStringContainsString('umeisha', $texts['Late']);
        $this->assertStringContainsString('Please pay to continue', $texts['Late'], 'not enforced: no threat of stopping yet');
        $this->assertStringContainsString('is unpaid', $texts['Stopped']);
        $this->assertSame('', $texts['Far'], 'more than a week away: nothing yet');
        $this->assertSame('', $texts['Forever'], 'no end date: nothing to remind');

        // ONE text to the super admin lists them all
        $digest = array_values(array_filter($this->sms->to('0711000111'), fn (array $m) => str_contains($m['message'], 'Plans ending')));
        $this->assertCount(1, $digest);
        foreach (['Seven Ltd', 'Three Ltd', 'One Ltd', 'Today Ltd', 'Late Ltd', 'Stopped Ltd'] as $name) {
            $this->assertStringContainsString($name, $digest[0]['message']);
        }
        $this->assertStringNotContainsString('Far Ltd', $digest[0]['message']);
        $this->assertStringNotContainsString('Forever Ltd', $digest[0]['message']);
    }

    public function test_when_enforcement_is_on_the_texts_say_the_service_is_stopped(): void
    {
        config(['billing.enforce' => true, 'billing.contact_phone' => '0617919104']);
        $late = $this->owner('Late', '2026-10-13 23:59:59');
        $stopped = $this->owner('Stopped', '2026-10-01 23:59:59');

        $this->remind();
        $texts = $this->ownerTexts(['Late' => $late, 'Stopped' => $stopped]);

        $this->assertStringContainsString('ili huduma zisisimame', $texts['Late']);
        $this->assertStringContainsString('zimesimamishwa', $texts['Stopped']);
        $this->assertStringContainsString('are stopped', $texts['Stopped']);
        $this->assertStringContainsString('0617919104', $texts['Stopped'], 'tells them who to pay');
    }

    public function test_a_reminder_goes_out_once_however_often_the_job_runs(): void
    {
        $this->superAdmin('0711000111');
        $owner = $this->owner('Three', '2026-10-18 23:59:59');

        $this->remind();
        $count = count($this->sms->sent);
        $this->assertGreaterThan(0, $count);

        $this->remind();
        $this->remind();
        $this->assertCount($count, $this->sms->sent, 'nothing new, nothing sent');

        // The next day it is a different reminder (2 days left is still the "3 days" stage: not repeated)
        $this->travelTo(now()->addDay());
        $this->remind();
        $this->assertCount($count, $this->sms->sent);

        // On the last day it is a new stage, so a new text
        $this->travelTo(now()->setDate(2026, 10, 18)->setTime(9, 0));
        $this->remind();
        $this->assertCount($count + 2, $this->sms->sent, 'one to the owner, one summary to the super admin');
        $ownerTexts = $this->sms->to($owner->phone_number);
        $this->assertCount(2, $ownerTexts);
        $this->assertStringContainsString('unaisha leo', $ownerTexts[1]['message']);
    }

    public function test_a_renewal_starts_a_fresh_set_of_reminders(): void
    {
        $owner = $this->owner('Three', '2026-10-18 23:59:59');
        $this->remind();
        $this->assertCount(1, $this->sms->to($owner->phone_number));

        $this->business($owner)->recordPayment(['amount' => 1000, 'months' => 1]); // new end: 2026-11-18

        $this->remind();
        $this->assertCount(1, $this->sms->to($owner->phone_number), 'paid up: nothing to say');

        $this->travelTo(now()->setDate(2026, 11, 15)->setTime(9, 0)); // three days before the new end
        $this->remind();
        $this->assertCount(2, $this->sms->to($owner->phone_number), 'the new end date has its own reminders');
        $this->assertSame(2, DB::table('billing_reminders')->count());
    }

    public function test_a_text_that_could_not_be_sent_is_tried_again_next_time(): void
    {
        $owner = $this->owner('Three', '2026-10-18 23:59:59');

        $this->sms->refuseAll();
        $this->remind();
        $this->assertSame(0, DB::table('billing_reminders')->count(), 'released, so the next run tries again');
        $this->assertCount(0, $this->sms->to($owner->phone_number));

        $fresh = new \Tests\Support\FakeSmsGateway();
        $this->app->instance(\App\Services\Sms\SmsGateway::class, $fresh);
        $this->remind();
        $this->assertCount(1, $fresh->to($owner->phone_number));
        $this->assertSame(1, DB::table('billing_reminders')->count());
    }

    public function test_a_dry_run_sends_and_records_nothing(): void
    {
        $this->owner('Three', '2026-10-18 23:59:59');

        $this->artisan('billing:remind', ['--dry-run' => true])->expectsOutputToContain('would remind: Three Ltd')->assertExitCode(0);

        $this->assertCount(0, $this->sms->sent);
        $this->assertSame(0, DB::table('billing_reminders')->count());
    }
}
