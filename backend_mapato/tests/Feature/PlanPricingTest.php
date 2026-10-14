<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\BusinessRegistration;
use App\Models\PlanPrice;
use App\Models\User;
use App\Support\PlanCatalog;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Plans are numbers of services: basic is one, standard is two, premium is all three. The super admin sets what each
 * costs for 1, 3, 6 and 12 months; the registration form shows it as soon as it is saved, tells the applicant what
 * their plan covers, and a business can never be put on a plan that covers fewer services than it has.
 */
class PlanPricingTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function setUp(): void
    {
        parent::setUp();
        $this->travelTo(now()->setDate(2026, 10, 15)->setTime(12, 0));
    }

    private function superAdmin(): User
    {
        return User::factory()->create(['role' => 'super_admin', 'is_active' => true, 'phone_number' => '0617919104']);
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function ownerWith(array $services, string $plan = 'trial'): User
    {
        $owner = User::factory()->create([
            'role' => 'admin', 'is_active' => true,
            'phone_number' => '07240000' . str_pad((string) ++$this->seq, 2, '0', STR_PAD_LEFT),
        ]);
        $this->givenServices($owner, ...$services);
        Business::forOwnerId($owner->id)->update(['name' => 'Biz ' . $this->seq, 'plan' => $plan, 'valid_until' => now()->addDays(10)]);

        return $owner;
    }

    private function business(User $owner): Business
    {
        return Business::forOwnerId($owner->id)->fresh();
    }

    private function setPrices(array $prices = null)
    {
        return $this->as($this->superAdmin(), 'PUT', '/api/admin/plan-prices', ['prices' => $prices ?? [
            'basic' => ['1' => 30000, '3' => 85000, '6' => 160000, '12' => 300000],
            'standard' => ['1' => 50000, '3' => 140000, '6' => 270000, '12' => 520000],
            'premium' => ['1' => 70000, '3' => 200000, '6' => 390000, '12' => 750000],
        ]]);
    }

    private function registration(array $overrides = []): array
    {
        return array_merge([
            'name' => 'Asha Owner', 'business_name' => 'Asha Rentals', 'email' => 'asha@example.test',
            'phone_number' => '0743519100', 'password' => 'secret-pass-1', 'password_confirmation' => 'secret-pass-1',
            'requested_services' => ['rental'],
        ], $overrides);
    }

    // ------------------------------------------------------------------ the rules

    public function test_a_plan_is_a_number_of_services(): void
    {
        $this->assertSame(['basic' => 1, 'standard' => 2, 'premium' => 3], PlanCatalog::limits());
        $this->assertSame(['basic', 'standard', 'premium'], PlanCatalog::sellable());

        $this->assertSame('basic', PlanCatalog::planFor(1));
        $this->assertSame('standard', PlanCatalog::planFor(2));
        $this->assertSame('premium', PlanCatalog::planFor(3));
        $this->assertSame('premium', PlanCatalog::planFor(9), 'more than any covers: the biggest');
        $this->assertSame('basic', PlanCatalog::planFor(0));

        $this->assertTrue(PlanCatalog::covers('basic', 1));
        $this->assertFalse(PlanCatalog::covers('basic', 2));
        $this->assertTrue(PlanCatalog::covers('standard', 2));
        $this->assertFalse(PlanCatalog::covers('standard', 3));
        $this->assertTrue(PlanCatalog::covers('premium', 3));
        $this->assertTrue(PlanCatalog::covers('trial', 3), 'a trial has no limit');
        $this->assertTrue(PlanCatalog::covers('free', 3), 'nor has free');
        $this->assertNull(PlanCatalog::servicesIncluded('trial'));
    }

    public function test_the_message_says_what_the_plan_covers_in_both_languages(): void
    {
        $basic = PlanCatalog::tooSmallMessage('basic', 2);
        $this->assertStringContainsString('Mpango wa Basic ni huduma MOJA tu, na umechagua 2', $basic);
        $this->assertStringContainsString('The Basic plan covers ONE service only, and you chose 2', $basic);
        $this->assertStringContainsString('Standard', $basic, 'it says which plan fits');

        $standard = PlanCatalog::tooSmallMessage('standard', 3);
        $this->assertStringContainsString('unahusu huduma 2 tu', $standard);
        $this->assertStringContainsString('covers 2 services only', $standard);
        $this->assertStringContainsString('Premium', $standard);
    }

    // ------------------------------------------------------------------ the list anybody can read

    public function test_the_plans_are_public_and_say_when_no_price_is_set_yet(): void
    {
        $this->flushHeaders();
        $response = $this->getJson('/api/plans')->assertOk();

        $this->assertFalse($response->json('data.configured'));
        $this->assertSame('TZS', $response->json('data.currency'));
        $this->assertSame([1, 3, 6, 12], $response->json('data.periods'));
        $this->assertSame(30, $response->json('data.trial_days'));
        $this->assertSame(3, $response->json('data.total_services'));
        $this->assertSame(['basic', 'standard', 'premium'], array_column($response->json('data.plans'), 'plan'));
        $this->assertSame([1, 2, 3], array_column($response->json('data.plans'), 'services_included'));
        foreach ($response->json('data.plans') as $plan) {
            $this->assertSame([null, null, null, null], array_column($plan['prices'], 'amount'), 'no price yet');
            $this->assertSame([1, 3, 6, 12], array_column($plan['prices'], 'months'));
        }
    }

    public function test_a_price_saved_by_the_super_admin_is_what_the_public_list_shows_at_once(): void
    {
        $this->setPrices()->assertOk()->assertJsonPath('data.configured', true);

        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $public = $this->getJson('/api/plans')->assertOk();
        $this->assertTrue($public->json('data.configured'));

        $byPlan = collect($public->json('data.plans'))->keyBy('plan');
        $this->assertEquals([30000, 85000, 160000, 300000], array_column($byPlan['basic']['prices'], 'amount'));
        $this->assertEquals([50000, 140000, 270000, 520000], array_column($byPlan['standard']['prices'], 'amount'));
        $this->assertEquals([70000, 200000, 390000, 750000], array_column($byPlan['premium']['prices'], 'amount'));
        $this->assertSame(30000.0, PlanCatalog::priceFor('basic', 1));
        $this->assertNull(PlanCatalog::priceFor('basic', 2), 'a period that is not offered has no price');
    }

    public function test_prices_can_be_changed_cleared_and_partly_set(): void
    {
        $this->setPrices()->assertOk();

        $this->setPrices(['basic' => ['1' => 35000, '3' => null, '6' => '']])->assertOk();

        $this->assertSame(35000.0, PlanCatalog::priceFor('basic', 1));
        $this->assertNull(PlanCatalog::priceFor('basic', 3), 'null clears a price');
        $this->assertNull(PlanCatalog::priceFor('basic', 6), 'so does an empty one');
        $this->assertSame(300000.0, PlanCatalog::priceFor('basic', 12), 'what was not mentioned is untouched');
        $this->assertSame(50000.0, PlanCatalog::priceFor('standard', 1));
        $this->assertSame(10, PlanPrice::count(), 'twelve prices, two of them cleared');

        $this->setPrices(['premium' => ['12' => '799999.50']])->assertOk();
        $this->assertSame(799999.5, PlanCatalog::priceFor('premium', 12));
    }

    public function test_a_wrong_price_is_refused_and_nothing_changes(): void
    {
        $this->setPrices()->assertOk();

        foreach ([
            ['basic' => ['1' => -5]],
            ['basic' => ['1' => 0]],
            ['basic' => ['1' => 'cheap']],
            ['basic' => ['2' => 1000]],
            ['gold' => ['1' => 1000]],
            ['trial' => ['1' => 1000]],
            ['basic' => ['1' => 1000, '3' => -1]],
        ] as $bad) {
            $this->setPrices($bad)->assertStatus(422)->assertJsonPath('errors.code', 'price_invalid');
        }

        $this->assertSame(30000.0, PlanCatalog::priceFor('basic', 1), 'even the valid part of a refused request is not kept');
        $this->as($this->superAdmin(), 'PUT', '/api/admin/plan-prices', [])->assertStatus(422);
    }

    public function test_only_a_super_admin_sets_prices_and_changes_are_logged_without_noise(): void
    {
        $owner = $this->ownerWith(['rental']);
        $this->as($owner, 'GET', '/api/admin/plan-prices')->assertForbidden();
        $this->as($owner, 'PUT', '/api/admin/plan-prices', ['prices' => ['basic' => ['1' => 1]]])->assertForbidden();
        $this->flushHeaders();
        $this->app['auth']->forgetGuards();
        $this->putJson('/api/admin/plan-prices', ['prices' => ['basic' => ['1' => 1]]])->assertUnauthorized();
        $this->assertSame(0, PlanPrice::count());

        $this->setPrices(['basic' => ['1' => 30000]])->assertOk();
        $this->setPrices(['basic' => ['1' => 30000]])->assertOk(); // the same again
        $this->setPrices(['basic' => ['1' => 35000]])->assertOk();

        $log = TenantContext::withoutScope(fn () => DB::table('inventory_audit_log')->where('action', 'plan_prices_changed')->orderBy('id')->pluck('summary'));
        $this->assertCount(2, $log, 'saving the same prices again is not a change');
        $this->assertStringContainsString('Basic 1m 30,000', $log[0]);
        $this->assertStringContainsString('Basic 1m 35,000', $log[1]);
    }

    public function test_saving_every_price_at_once_is_logged_without_overflowing_the_log_line(): void
    {
        // Twelve changes make a long summary: the log column holds 255 characters (MariaDB enforces it, SQLite does not).
        $this->setPrices()->assertOk();

        $line = (string) TenantContext::withoutScope(fn () => DB::table('inventory_audit_log')->where('action', 'plan_prices_changed')->value('summary'));
        $this->assertNotSame('', $line);
        $this->assertLessThanOrEqual(255, mb_strlen($line));
        $this->assertStringContainsString('changed plan prices', $line);
    }

    public function test_an_audit_line_is_cut_to_the_column_for_everybody(): void
    {
        $user = $this->superAdmin();
        $request = \Illuminate\Http\Request::create('/x');
        $request->setUserResolver(fn () => $user);

        app(\App\Services\Inventory\AuditTrail::class)->record($request, 'business', null, 'long_line', null, null, str_repeat('Long business name ', 40));

        $line = (string) TenantContext::withoutScope(fn () => DB::table('inventory_audit_log')->where('action', 'long_line')->value('summary'));
        $this->assertLessThanOrEqual(255, mb_strlen($line));
        $this->assertStringEndsWith('...', $line);
    }

    public function test_the_admin_page_reads_the_same_list_with_the_time_of_the_last_change(): void
    {
        $super = $this->superAdmin();
        $this->setPrices()->assertOk();

        $page = $this->as($super, 'GET', '/api/admin/plan-prices')->assertOk();
        $this->assertTrue($page->json('data.configured'));
        $this->assertNotNull($page->json('data.updated_at'));
        $this->assertSame(3, count($page->json('data.plans')));
    }

    // ------------------------------------------------------------------ registration

    public function test_a_registration_remembers_the_package_and_the_months_and_shows_the_price_to_the_super_admin(): void
    {
        $this->setPrices();

        $this->postJson('/api/auth/register', $this->registration([
            'requested_services' => ['rental', 'transport'], 'requested_plan' => 'standard', 'requested_months' => 3,
        ]))->assertCreated();

        $registration = BusinessRegistration::firstOrFail();
        $this->assertSame('standard', $registration->requested_plan);
        $this->assertSame(3, $registration->requested_months);

        $row = $this->as($this->superAdmin(), 'GET', '/api/admin/registrations')->assertOk()->json('data.0');
        $this->assertSame('standard', $row['requested_plan']);
        $this->assertSame(3, $row['requested_months']);
        $this->assertEquals(140000, $row['requested_price']);
        $this->assertSame(2, $row['plan_services_included']);
    }

    public function test_without_a_choice_the_smallest_plan_that_covers_the_services_is_meant_for_one_month(): void
    {
        foreach ([[['rental'], 'basic'], [['rental', 'transport'], 'standard'], [['rental', 'transport', 'inventory'], 'premium']] as $i => [$services, $plan]) {
            $this->postJson('/api/auth/register', $this->registration([
                'email' => "u{$i}@example.test", 'requested_services' => $services,
                'inventory_type' => in_array('inventory', $services, true) ? 'depot' : null,
            ]))->assertCreated();
            $registration = BusinessRegistration::whereHas('user', fn ($q) => $q->where('email', "u{$i}@example.test"))->firstOrFail();
            $this->assertSame($plan, $registration->requested_plan, implode('+', $services));
            $this->assertSame(1, $registration->requested_months);
        }
    }

    public function test_a_plan_that_covers_fewer_services_than_chosen_is_refused_with_a_plain_message(): void
    {
        $response = $this->postJson('/api/auth/register', $this->registration([
            'requested_services' => ['rental', 'transport'], 'requested_plan' => 'basic',
        ]))->assertStatus(422);

        $response->assertJsonPath('errors.code', 'plan_too_small')
            ->assertJsonPath('errors.recommended', 'standard')
            ->assertJsonPath('errors.services', 2);
        $this->assertStringContainsString('ONE service only', $response->json('message'));
        $this->assertStringContainsString('MOJA', $response->json('message'));
        $this->assertSame(0, BusinessRegistration::count());
        $this->assertSame(0, User::where('email', 'asha@example.test')->count(), 'no account is left behind');

        $this->postJson('/api/auth/register', $this->registration([
            'requested_services' => ['rental', 'transport', 'inventory'], 'inventory_type' => 'depot', 'requested_plan' => 'standard',
        ]))->assertStatus(422)->assertJsonPath('errors.recommended', 'premium');
    }

    public function test_a_bigger_plan_than_needed_is_the_applicants_choice_and_allowed(): void
    {
        $this->postJson('/api/auth/register', $this->registration(['requested_services' => ['rental'], 'requested_plan' => 'premium']))->assertCreated();

        $this->assertSame('premium', BusinessRegistration::firstOrFail()->requested_plan);
    }

    public function test_only_plans_that_are_sold_and_periods_that_are_offered_are_accepted(): void
    {
        foreach ([['requested_plan' => 'trial'], ['requested_plan' => 'gold'], ['requested_months' => 2], ['requested_months' => 0], ['requested_months' => 'forever']] as $bad) {
            $this->postJson('/api/auth/register', $this->registration($bad))->assertStatus(422);
        }
        $this->assertSame(0, BusinessRegistration::count());
    }

    public function test_applying_again_after_a_rejection_takes_the_new_package(): void
    {
        $this->postJson('/api/auth/register', $this->registration(['requested_plan' => 'basic']))->assertCreated();
        $registration = BusinessRegistration::firstOrFail();
        $this->as($this->superAdmin(), 'POST', "/api/admin/registrations/{$registration->id}/reject", ['reason' => 'Incomplete'])->assertOk();

        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $this->postJson('/api/auth/register', $this->registration(['requested_services' => ['rental', 'transport'], 'requested_plan' => 'standard', 'requested_months' => 6]))->assertSuccessful();

        $registration->refresh();
        $this->assertSame('standard', $registration->requested_plan);
        $this->assertSame(6, $registration->requested_months);
    }

    // ------------------------------------------------------------------ approval

    public function test_approving_on_a_plan_that_covers_fewer_services_than_given_is_refused(): void
    {
        $this->postJson('/api/auth/register', $this->registration(['requested_services' => ['rental', 'transport']]))->assertCreated();
        $registration = BusinessRegistration::firstOrFail();
        $super = $this->superAdmin();

        $this->as($super, 'POST', "/api/admin/registrations/{$registration->id}/approve", [
            'service_types' => ['rental', 'transport'], 'plan' => 'basic', 'allow_unverified' => true,
        ])->assertStatus(422)->assertJsonPath('errors.code', 'plan_too_small');
        $this->assertSame(BusinessRegistration::PENDING, $registration->fresh()->status);

        // a trial (the default) has no limit, and a plan that covers them is fine
        $this->as($super, 'POST', "/api/admin/registrations/{$registration->id}/approve", [
            'service_types' => ['rental', 'transport'], 'plan' => 'standard', 'allow_unverified' => true,
        ])->assertOk();
        $this->assertSame('standard', Business::forOwnerId($registration->user_id)->plan);
    }

    public function test_the_default_trial_approval_has_no_service_limit(): void
    {
        $this->postJson('/api/auth/register', $this->registration(['requested_services' => ['rental', 'transport', 'inventory'], 'inventory_type' => 'depot']))->assertCreated();
        $registration = BusinessRegistration::firstOrFail();

        $this->as($this->superAdmin(), 'POST', "/api/admin/registrations/{$registration->id}/approve", [
            'service_types' => ['rental', 'transport', 'inventory'], 'allow_unverified' => true,
        ])->assertOk();

        $this->assertSame('trial', Business::forOwnerId($registration->user_id)->plan);
    }

    // ------------------------------------------------------------------ payments and plan changes

    public function test_a_payment_may_not_put_a_business_on_a_plan_smaller_than_its_services(): void
    {
        $owner = $this->ownerWith(['rental', 'transport']);
        $id = $this->business($owner)->id;
        $super = $this->superAdmin();

        $this->as($super, 'POST', "/api/admin/businesses/{$id}/payments", ['amount' => 30000, 'plan' => 'basic'])
            ->assertStatus(422)->assertJsonPath('errors.code', 'plan_too_small')->assertJsonPath('errors.recommended', 'standard');
        $this->assertSame('trial', $this->business($owner)->plan, 'nothing was recorded');
        $this->assertSame(0, DB::table('business_payments')->count());

        $this->as($super, 'POST', "/api/admin/businesses/{$id}/payments", ['amount' => 50000, 'plan' => 'standard'])
            ->assertCreated()->assertJsonPath('data.business.billing.plan', 'standard');
        $this->as($super, 'POST', "/api/admin/businesses/{$id}/payments", ['amount' => 70000, 'plan' => 'premium'])->assertCreated();
    }

    public function test_a_payment_without_a_plan_picks_the_smallest_one_that_covers_the_services(): void
    {
        $super = $this->superAdmin();
        foreach ([[['rental'], 'basic'], [['rental', 'transport'], 'standard'], [['rental', 'transport', 'inventory'], 'premium']] as [$services, $expected]) {
            $owner = $this->ownerWith($services);
            $this->as($super, 'POST', '/api/admin/businesses/' . $this->business($owner)->id . '/payments', ['amount' => 1000])
                ->assertCreated()->assertJsonPath('data.business.billing.plan', $expected);
        }
    }

    public function test_a_paid_plan_that_is_too_small_is_not_kept_quietly_either(): void
    {
        // A business that is on basic but was given a second service: paying without saying which plan must not
        // carry on as if basic covered it.
        $owner = $this->ownerWith(['rental', 'transport'], 'basic');

        $this->as($this->superAdmin(), 'POST', '/api/admin/businesses/' . $this->business($owner)->id . '/payments', ['amount' => 30000])
            ->assertStatus(422)->assertJsonPath('errors.code', 'plan_too_small');
    }

    public function test_changing_a_plan_by_hand_follows_the_same_rule_and_an_unchanged_one_is_left_alone(): void
    {
        $owner = $this->ownerWith(['rental', 'transport', 'inventory'], 'premium');
        $id = $this->business($owner)->id;
        $super = $this->superAdmin();

        $this->as($super, 'PUT', "/api/admin/businesses/{$id}", ['plan' => 'basic'])->assertStatus(422)->assertJsonPath('errors.code', 'plan_too_small');
        $this->as($super, 'PUT', "/api/admin/businesses/{$id}", ['plan' => 'standard'])->assertStatus(422);
        $this->assertSame('premium', $this->business($owner)->plan);

        $this->as($super, 'PUT', "/api/admin/businesses/{$id}", ['plan' => 'trial'])->assertOk();
        $this->as($super, 'PUT', "/api/admin/businesses/{$id}", ['plan' => 'free'])->assertOk();
        $this->as($super, 'PUT', "/api/admin/businesses/{$id}", ['plan' => 'premium'])->assertOk();

        // saving a business whose plan is already too small (it was set before this rule) is not blocked
        Business::forOwnerId($owner->id)->update(['plan' => 'basic']);
        $this->as($super, 'PUT', "/api/admin/businesses/{$id}", ['plan' => 'basic', 'valid_until' => '2027-01-01'])->assertOk();
    }

    public function test_free_and_trial_businesses_are_never_limited(): void
    {
        $owner = $this->ownerWith(['rental', 'transport', 'inventory'], 'free');

        $this->assertTrue($this->business($owner)->planCoversServices('free'));
        $this->assertTrue($this->business($owner)->planCoversServices('trial'));
        $this->assertFalse($this->business($owner)->planCoversServices('basic'));
        $this->assertFalse($this->business($owner)->planCoversServices('standard'));
        $this->assertTrue($this->business($owner)->planCoversServices('premium'));
        $this->assertSame(['inventory', 'rental', 'transport'], collect($this->business($owner)->serviceTypes())->sort()->values()->all());
    }
}
