<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Salon\StylistPerformance;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * How each stylist did, as the owner reads it: what they brought in, what a visit is worth, how many of their clients come back, how they
 * rank, how they did against the period before, and how close they are to the target set for the month.
 */
class StylistPerformanceTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function salon(): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => 'Neema Owner', 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0723' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => 'Glow']);

        return $owner;
    }

    private function person(User $owner, string $name, string $role = 'hair_stylist'): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    private function service(User $owner, string $name, int $price): int
    {
        return $this->api($owner, 'POST', '/api/inventory/products', ['name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price, 'duration_minutes' => 60])->assertCreated()->json('data.id');
    }

    private function client(User $owner, string $name, string $phone): int
    {
        return $this->api($owner, 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertCreated()->json('data.id');
    }

    /** A sale on a given day, done by one stylist. */
    private function sell(User $owner, string $day, int $service, int $price, User $stylist, ?int $client = null, int $discount = 0): void
    {
        $why = $discount > 0 ? ['discount_reason' => 'Regular client'] : [];
        Carbon::setTestNow(Carbon::parse($day . ' 11:00:00', 'Africa/Dar_es_Salaam'));
        $this->api($owner, 'POST', '/api/inventory/sales', array_filter([
            ...$why, 'customer_id' => $client, 'payment_status' => 'paid', 'subtotal' => $price, 'discount' => $discount, 'tax' => 0, 'total' => $price - $discount, 'paid_total' => $price - $discount,
            'items' => [['product_id' => $service, 'quantity' => 1, 'unit_price' => $price, 'staff_id' => (string) $stylist->id]],
        ], fn ($v) => $v !== null))->assertCreated();
    }

    /** @return array{0: User, 1: User, 2: User, 3: User} owner, Asha, Bahati, Chao */
    private function scene(): array
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $bahati = $this->person($owner, 'Bahati');
        $chao = $this->person($owner, 'Chao');
        $braids = $this->service($owner, 'Braids', 40000);
        $c1 = $this->client($owner, 'Mama Neema', '0711000001');
        $c2 = $this->client($owner, 'Bi Rehema', '0711000002');
        $c3 = $this->client($owner, 'Dada Zawadi', '0711000003');
        $c4 = $this->client($owner, 'Mama Tumaini', '0711000004');
        $c5 = $this->client($owner, 'Dada Mwanaidi', '0711000005');

        // The month so far (1-20 November) and the 20 days before it (12-31 October).
        $this->sell($owner, '2026-11-03', $braids, 40000, $asha, $c1);
        $this->sell($owner, '2026-11-08', $braids, 40000, $asha, $c5);
        $this->sell($owner, '2026-11-14', $braids, 60000, $asha, $c1);
        $this->sell($owner, '2026-11-05', $braids, 30000, $bahati, $c4);
        $this->sell($owner, '2026-10-15', $braids, 50000, $asha, $c1);
        $this->sell($owner, '2026-10-20', $braids, 50000, $asha, $c3);
        $this->sell($owner, '2026-10-13', $braids, 30000, $bahati, $c3);
        $this->sell($owner, '2026-10-22', $braids, 30000, $bahati, $c3);
        $this->sell($owner, '2026-10-28', $braids, 30000, $bahati, $c3);
        $this->sell($owner, '2026-10-25', $braids, 50000, $chao, $c2);
        Carbon::setTestNow(Carbon::parse('2026-11-20 12:00:00', 'Africa/Dar_es_Salaam'));

        return [$owner, $asha, $bahati, $chao];
    }

    private function results(User $as, string $query = '?from=2026-11-01&to=2026-11-20'): array
    {
        return $this->api($as, 'GET', '/api/inventory/salon/stylists' . $query)->assertOk()->json('data');
    }

    public function test_each_line_says_what_a_visit_is_worth_how_many_clients_come_back_and_each_ones_share_and_rank(): void
    {
        [$owner, $asha, $bahati] = $this->scene();

        $d = $this->results($owner);
        $rows = collect($d['stylists'])->keyBy('name');

        $this->assertSame(['Asha', 'Bahati', 'Chao'], collect($d['stylists'])->pluck('name')->all(), 'best first; Chao brought nothing this period but is still listed');
        $this->assertEquals(140000, $rows['Asha']['revenue']);
        $this->assertSame(3, $rows['Asha']['visits']);
        $this->assertSame(2, $rows['Asha']['clients']);
        $this->assertEqualsWithDelta(46666.67, $rows['Asha']['avg_ticket'], 0.01);
        $this->assertEquals(50.0, $rows['Asha']['return_rate'], 'Mama Neema had been before, Dada Mwanaidi had not');
        $this->assertSame(1, $rows['Asha']['rank']);
        $this->assertSame(2, $rows['Bahati']['rank']);
        $this->assertNull($rows['Chao']['rank'], 'no rank without any work in the period');
        $this->assertEquals(82.4, $rows['Asha']['share']);
        $this->assertEquals(17.6, $rows['Bahati']['share']);
        $this->assertEquals(0.0, $rows['Bahati']['return_rate'], 'Mama Tumaini is new');
        $this->assertNull($rows['Chao']['return_rate']);
        $this->assertEquals(170000, $d['totals']['revenue']);
        $this->assertEqualsWithDelta(42500.0, $d['totals']['avg_ticket'], 0.01);
    }

    public function test_every_line_is_set_against_the_period_just_before(): void
    {
        [$owner] = $this->scene();

        $d = $this->results($owner);
        $rows = collect($d['stylists'])->keyBy('name');

        $this->assertSame(['2026-10-12', '2026-10-31'], [$d['previous_from'], $d['previous_to']], 'the 20 days before the 20 asked for');
        $this->assertEquals(100000, $rows['Asha']['previous']['revenue']);
        $this->assertEquals(40.0, $rows['Asha']['change']['revenue']);
        $this->assertEquals(-66.7, $rows['Bahati']['change']['revenue']);
        $this->assertEquals(-100.0, $rows['Chao']['change']['revenue'], 'gone to nothing is shown, not hidden');
        $this->assertSame(0, $rows['Chao']['visits']);
        $this->assertEquals(240000, $d['totals']['previous']['revenue']);
        $this->assertEquals(-29.2, $d['totals']['change']['revenue']);
    }

    public function test_a_period_with_nothing_before_it_has_no_percent_not_a_made_up_one(): void
    {
        [$owner] = $this->scene();

        $d = $this->results($owner, '?from=2026-07-01&to=2026-07-31');
        $this->assertSame([], $d['stylists'] === [] ? [] : array_filter($d['stylists'], fn ($r) => $r['revenue'] > 0));

        $d = $this->results($owner, '?from=2026-10-01&to=2026-10-31');
        $asha = collect($d['stylists'])->firstWhere('name', 'Asha');
        $this->assertNull($asha['change']['revenue'], 'September had nothing to compare October with');
    }

    public function test_a_target_says_how_far_along_a_person_is_and_whether_that_is_ahead_of_the_month(): void
    {
        [$owner, $asha, $bahati] = $this->scene();
        $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', ['month' => '2026-11', 'targets' => [
            ['staff_id' => (string) $asha->id, 'revenue_target' => 200000],
            ['staff_id' => (string) $bahati->id, 'revenue_target' => 100000],
        ]])->assertOk();

        $rows = collect($this->results($owner)['stylists'])->keyBy('name');

        $this->assertEquals(200000, $rows['Asha']['target']['amount']);
        $this->assertEquals(140000, $rows['Asha']['target']['achieved']);
        $this->assertEquals(70.0, $rows['Asha']['target']['percent']);
        $this->assertEquals(66.7, $rows['Asha']['target']['expected_percent'], '20 of the 30 days have gone');
        $this->assertSame('ahead', $rows['Asha']['target']['pace']);
        $this->assertEquals(30.0, $rows['Bahati']['target']['percent']);
        $this->assertSame('behind', $rows['Bahati']['target']['pace']);
        $this->assertNull($rows['Chao']['target']);
    }

    public function test_in_the_first_days_of_a_month_nobody_is_called_behind(): void
    {
        [$owner, $asha, $bahati] = $this->scene();
        $this->sell($owner, '2026-11-02', $this->service($owner, 'Wash', 10000), 10000, $bahati);
        $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', ['month' => '2026-11', 'targets' => [['staff_id' => (string) $bahati->id, 'revenue_target' => 900000]]])->assertOk();

        $t = StylistPerformance::targets('2026-11', '2026-11-03');
        $this->assertSame('on_track', $t[(string) $bahati->id]['pace'], 'three days in, 1% of the target: too early to say behind');
        $later = StylistPerformance::targets('2026-11', '2026-11-20');
        $this->assertSame('behind', $later[(string) $bahati->id]['pace'], 'twenty days in it is');
    }

    public function test_reaching_the_target_is_said_so_and_an_old_month_is_judged_by_the_whole_month(): void
    {
        [$owner, $asha] = $this->scene();
        $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', ['month' => '2026-11', 'targets' => [['staff_id' => (string) $asha->id, 'revenue_target' => 100000]]])->assertOk();
        $this->assertSame('reached', collect($this->results($owner)['stylists'])->firstWhere('name', 'Asha')['target']['pace']);

        $t = StylistPerformance::targets('2026-10', '2026-11-20');
        $this->assertSame([], $t, 'no target was set for October');
    }

    public function test_one_who_only_sees_their_own_line_has_no_ranking_and_cannot_see_the_others(): void
    {
        [$owner, $asha, $bahati] = $this->scene();
        $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', ['month' => '2026-11', 'targets' => [['staff_id' => (string) $asha->id, 'revenue_target' => 200000]]])->assertOk();

        $d = $this->results($asha);

        $this->assertCount(1, $d['stylists']);
        $this->assertSame('Asha', $d['stylists'][0]['name']);
        $this->assertNull($d['stylists'][0]['rank']);
        $this->assertEquals(70.0, $d['stylists'][0]['target']['percent'], 'their own target is theirs to see');
        $this->assertEquals(140000, $d['totals']['revenue'], 'the totals are of what they can see');
        $this->assertFalse($d['sees_everyone']);
        $this->assertFalse($d['can_set_targets']);
        $this->assertTrue($this->results($owner)['can_set_targets']);
        $this->assertTrue($this->results($owner)['sees_everyone']);
    }

    public function test_only_the_owner_sets_targets_while_the_accountant_and_a_stylist_may_not(): void
    {
        [$owner, $asha] = $this->scene();
        $accountant = $this->person($owner, 'Ivy', 'accountant');
        $body = ['month' => '2026-11', 'targets' => [['staff_id' => (string) $asha->id, 'revenue_target' => 150000]]];

        $this->api($accountant, 'PUT', '/api/inventory/salon/stylist-targets', $body)->assertForbidden();
        $this->api($asha, 'PUT', '/api/inventory/salon/stylist-targets', $body)->assertForbidden();
        $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', $body)->assertOk()->assertJsonPath('data.can_set', true);

        $this->api($accountant, 'GET', '/api/inventory/salon/stylist-targets?month=2026-11')->assertForbidden();
        $accountant->forceFill(['permissions' => ['inv_salon_stylists']])->save();
        $read = $this->api($accountant, 'GET', '/api/inventory/salon/stylist-targets?month=2026-11')->assertOk();
        $read->assertJsonPath('data.can_set', false);
        $this->assertEquals(150000, collect($read->json('data.people'))->firstWhere('name', 'Asha')['target']['amount']);
        $this->api($asha, 'GET', '/api/inventory/salon/stylist-targets?month=2026-11')->assertForbidden();
    }

    public function test_a_target_can_be_changed_and_removed_and_is_checked(): void
    {
        [$owner, $asha, $bahati] = $this->scene();
        $set = fn (array $t) => $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', ['month' => '2026-11', 'targets' => $t]);

        $set([['staff_id' => (string) $asha->id, 'revenue_target' => 150000], ['staff_id' => (string) $bahati->id, 'revenue_target' => 90000]])->assertOk();
        $set([['staff_id' => (string) $asha->id, 'revenue_target' => 180000]])->assertOk();
        $rows = collect($this->api($owner, 'GET', '/api/inventory/salon/stylist-targets?month=2026-11')->json('data.people'))->keyBy('name');
        $this->assertEquals(180000, $rows['Asha']['target']['amount']);
        $this->assertEquals(90000, $rows['Bahati']['target']['amount'], 'the person not named is left as it was');

        $set([['staff_id' => (string) $bahati->id, 'revenue_target' => 0]])->assertOk();
        $this->assertNull(collect($this->api($owner, 'GET', '/api/inventory/salon/stylist-targets?month=2026-11')->json('data.people'))->firstWhere('name', 'Bahati')['target']);

        $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', ['month' => 'soon', 'targets' => [['staff_id' => (string) $asha->id, 'revenue_target' => 1]]])->assertStatus(422);
        $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', ['month' => '2026-11', 'targets' => [['staff_id' => (string) $asha->id, 'revenue_target' => -5]]])->assertStatus(422);
        $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', ['month' => '2026-11', 'targets' => []])->assertStatus(422);
    }

    public function test_nobody_can_set_a_target_for_a_person_of_another_business(): void
    {
        [$owner] = $this->scene();
        $rival = $this->salon();
        $stranger = $this->person($rival, 'Stranger');

        $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', ['month' => '2026-11', 'targets' => [['staff_id' => (string) $stranger->id, 'revenue_target' => 99999]]])->assertStatus(422);

        $people = collect($this->api($owner, 'GET', '/api/inventory/salon/stylist-targets?month=2026-11')->json('data.people'))->pluck('name')->all();
        $this->assertNotContains('Stranger', $people);
        $this->assertSame(0, \Illuminate\Support\Facades\DB::table('inventory_staff_targets')->count());
    }

    public function test_one_business_never_sees_the_targets_or_results_of_another(): void
    {
        [$owner, $asha] = $this->scene();
        $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', ['month' => '2026-11', 'targets' => [['staff_id' => (string) $asha->id, 'revenue_target' => 150000]]])->assertOk();
        $rival = $this->salon();

        $this->assertSame([], $this->results($rival)['stylists']);
        $people = $this->api($rival, 'GET', '/api/inventory/salon/stylist-targets?month=2026-11')->json('data.people');
        $this->assertSame([], array_values(array_filter($people, fn ($p) => $p['target'] !== null)));
    }

    public function test_a_discount_is_taken_off_the_stylists_revenue_in_proportion(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $braids = $this->service($owner, 'Braids', 40000);
        $this->sell($owner, '2026-11-03', $braids, 40000, $asha, null, 4000);

        $rows = $this->results($owner, '?from=2026-11-01&to=2026-11-30')['stylists'];

        $this->assertEquals(36000, $rows[0]['revenue']);
        $this->assertEquals(4000, $rows[0]['discount']);
        $this->assertEquals(36000, $rows[0]['avg_ticket']);
    }

    public function test_the_export_carries_the_new_columns_in_both_languages(): void
    {
        [$owner, $asha] = $this->scene();
        $this->api($owner, 'PUT', '/api/inventory/salon/stylist-targets', ['month' => '2026-11', 'targets' => [['staff_id' => (string) $asha->id, 'revenue_target' => 200000]]])->assertOk();

        $en = $this->api($owner, 'GET', '/api/inventory/salon/export/stylists?from=2026-11-01&to=2026-11-20&format=csv')->assertOk()->getContent();
        $sw = $this->api($owner, 'GET', '/api/inventory/salon/export/stylists?from=2026-11-01&to=2026-11-20&format=csv&lang=sw')->assertOk()->getContent();

        foreach (['Rank', 'Avg per visit', 'Came back', 'Target', 'Asha', '+40%', '50%', '200000'] as $needle) {
            $this->assertStringContainsString($needle, $en, $needle);
        }
        foreach (['Nafasi', 'Wastani wa ziara', 'Waliorudi', 'Lengo'] as $needle) {
            $this->assertStringContainsString($needle, $sw, $needle);
        }
    }
}
