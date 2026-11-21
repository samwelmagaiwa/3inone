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
 * Groups (Vikundi), phase 4: the asset register and hiring things out (chairs at 300 a chair a day): availability, the keeper's decision,
 * payment before hand-over, return with late, damaged and missing counts, the damage charge decided by the chair, and closing.
 */
class GroupsHireTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    /** @var array<string, User> */
    private array $people = [];

    /** @var array<string, int> */
    private array $ids = [];

    private int $chairs;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Carbon::setTestNow(Carbon::parse('2026-11-10 08:00:00'));
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'MEG Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG']);
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['treasurer', '0712000002', 'mweka_hazina'], ['keeper', '0713000009', null],
            ['asha', '0713000001', null], ['juma', '0713000002', null]] as [$key, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            if ($office !== null) {
                $this->api($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
        $this->chairs = $this->api($this->people['chair'], 'POST', '/assets', [
            'code' => 'VT-01', 'name' => 'Viti vya plastiki', 'category' => 'Viti', 'quantity' => 100, 'cost' => 1500000, 'location' => 'Stoo ya Mwenyekiti',
            'custodian_id' => $this->ids['keeper'], 'hire_rate' => 300,
        ])->assertOk()->json('data.asset.id');
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

    private function verifyLast(): void
    {
        $tx = (int) DB::table('group_transactions')->where('status', 'pending')->orderByDesc('id')->value('id');
        $this->api($this->people['treasurer'], 'POST', "/transactions/{$tx}/verify")->assertOk();
    }

    public function test_members_see_what_can_be_hired_but_not_its_value_or_where_it_is_kept(): void
    {
        $asset = $this->api($this->people['asha'], 'GET', '/assets')->assertOk()->json('data.assets.0');
        $this->assertSame(100, $asset['free_today']);
        $this->assertEquals(300, $asset['hire_rate']);
        $this->assertArrayNotHasKey('cost', $asset);
        $this->assertArrayNotHasKey('location', $asset);
        $this->api($this->people['keeper'], 'GET', "/assets/{$this->chairs}")->assertJsonPath('data.asset.location', 'Stoo ya Mwenyekiti')->assertJsonPath('data.can_handle', true);
        $this->api($this->people['asha'], 'POST', '/assets', ['code' => 'X', 'name' => 'XX', 'quantity' => 1])->assertForbidden();
    }

    public function test_a_hire_is_confirmed_by_the_keeper_paid_before_hand_over_and_closed_once_settled(): void
    {
        $hire = $this->api($this->people['asha'], 'POST', '/me/hires', ['asset_id' => $this->chairs, 'quantity' => 60, 'start_date' => '2026-11-20', 'end_date' => '2026-11-22', 'purpose' => 'Harusi'])
            ->assertCreated()->assertJsonPath('data.hire.days', 3)->assertJsonPath('data.hire.amount', 54000)->json('data.hire.id');
        $other = $this->api($this->people['juma'], 'POST', '/me/hires', ['asset_id' => $this->chairs, 'quantity' => 50, 'start_date' => '2026-11-21', 'end_date' => '2026-11-21'])
            ->assertCreated()->json('data.hire.id');
        $this->api($this->people['juma'], 'POST', '/me/hires', ['asset_id' => $this->chairs, 'quantity' => 101, 'start_date' => '2026-11-21', 'end_date' => '2026-11-21'])
            ->assertStatus(422)->assertJsonPath('code', 'not_enough');

        // Only the keeper (or whoever manages assets) confirms, never for their own hire.
        $this->api($this->people['juma'], 'POST', "/hires/{$hire}/decide", ['approve' => true])->assertForbidden();
        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/decide", ['approve' => true])->assertOk()->assertJsonPath('data.hire.state', 'waiting_payment');
        $this->api($this->people['keeper'], 'POST', "/hires/{$other}/decide", ['approve' => true])->assertStatus(422)->assertJsonPath('code', 'not_enough');
        $this->api($this->people['keeper'], 'GET', "/assets/{$this->chairs}/availability?from=2026-11-21&to=2026-11-21")->assertJsonPath('data.free', 40);

        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/issue", ['quantity' => 60])->assertStatus(409)->assertJsonPath('code', 'not_paid');
        $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'hire', 'hire_id' => $hire, 'amount' => 60000, 'method' => 'cash'])->assertStatus(422)->assertJsonPath('code', 'more_than_hire');
        $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'hire', 'hire_id' => $hire, 'amount' => 54000, 'method' => 'mpesa', 'external_ref' => 'VITI1'])->assertCreated();
        $this->verifyLast();
        $this->api($this->people['asha'], 'GET', '/me/hires')->assertJsonPath('data.hires.0.state', 'confirmed');

        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/issue", ['quantity' => 60, 'condition' => 'Nzuri'])->assertOk()->assertJsonPath('data.hire.state', 'out');

        // Back two days late: no late rate set, so no late charge. 55 back (2 of them broken), 5 missing.
        Carbon::setTestNow(Carbon::parse('2026-11-24 10:00:00'));
        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/return", ['returned' => 50, 'missing' => 5])->assertStatus(422)->assertJsonPath('code', 'counts_do_not_add_up');
        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/return", ['returned' => 55, 'damaged' => 2, 'missing' => 5, 'note' => '2 zimevunjika'])
            ->assertOk()->assertJsonPath('data.hire.late_charge', 0)->assertJsonPath('data.hire.state', 'damage_pending');
        $this->assertSame(93, (int) DB::table('group_assets')->where('id', $this->chairs)->value('quantity'));
        $this->assertSame(2, DB::table('group_asset_events')->where('asset_id', $this->chairs)->whereIn('kind', ['damage', 'loss'])->count());

        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/close")->assertStatus(409);
        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/charge", ['amount' => 1, 'note' => 'x x x'])->assertForbidden();
        $this->api($this->people['chair'], 'POST', "/hires/{$hire}/charge", ['amount' => 21000, 'note' => '7 chairs x 3,000 replacement'])->assertOk()
            ->assertJsonPath('data.hire.total', 75000)->assertJsonPath('data.hire.balance', 21000)->assertJsonPath('data.hire.state', 'balance_due');
        $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'hire', 'hire_id' => $hire, 'amount' => 21000, 'method' => 'cash'])->assertCreated();
        $this->verifyLast();
        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/close")->assertOk()->assertJsonPath('data.hire.status', 'closed');
    }

    public function test_a_late_rate_charges_overdue_days_and_the_group_can_count_only_the_nights_between(): void
    {
        $this->api($this->people['chair'], 'PUT', "/assets/{$this->chairs}", ['code' => 'VT-01', 'name' => 'Viti vya plastiki', 'custodian_id' => $this->ids['keeper'], 'hire_rate' => 300, 'late_rate' => 300])->assertOk();
        $this->api($this->owner, 'PUT', '/settings', ['values' => ['hire_days_rule' => 'between'], 'reason' => 'Meeting'])->assertOk();

        $hire = $this->api($this->people['asha'], 'POST', '/me/hires', ['asset_id' => $this->chairs, 'quantity' => 10, 'start_date' => '2026-11-20', 'end_date' => '2026-11-22'])
            ->assertJsonPath('data.hire.days', 2)->assertJsonPath('data.hire.amount', 6000)->json('data.hire.id');
        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/decide", ['approve' => true])->assertOk();
        $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'hire', 'hire_id' => $hire, 'amount' => 6000, 'method' => 'cash'])->assertCreated();
        $this->verifyLast();
        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/issue", ['quantity' => 10])->assertOk();

        Carbon::setTestNow(Carbon::parse('2026-11-25 09:00:00'));
        $this->api($this->people['chair'], 'GET', '/me')->assertJsonPath('data.waiting.hires_overdue', 1);
        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/return", ['returned' => 10])->assertOk()
            ->assertJsonPath('data.hire.late_charge', 9000)->assertJsonPath('data.hire.state', 'balance_due');
    }

    public function test_someone_outside_the_group_hires_through_the_keeper_who_records_their_payment(): void
    {
        $hire = $this->api($this->people['keeper'], 'POST', '/hires', [
            'asset_id' => $this->chairs, 'quantity' => 20, 'start_date' => '2026-11-15', 'end_date' => '2026-11-15', 'customer_name' => 'Mzee Kassim', 'customer_phone' => '0754000111',
        ])->assertCreated()->assertJsonPath('data.hire.who', 'Mzee Kassim')->json('data.hire.id');
        $this->api($this->people['asha'], 'POST', '/hires', ['asset_id' => $this->chairs, 'quantity' => 1, 'start_date' => '2026-11-15', 'end_date' => '2026-11-15', 'customer_name' => 'X Y', 'customer_phone' => '0754000112'])
            ->assertForbidden();

        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/decide", ['approve' => true])->assertOk();
        $this->api($this->people['keeper'], 'POST', "/hires/{$hire}/pay", ['amount' => 6000, 'method' => 'cash'])->assertOk();
        $tx = DB::table('group_transactions')->where('hire_id', $hire)->first();
        $this->assertNull($tx->member_id);
        $this->api($this->people['treasurer'], 'POST', "/transactions/{$tx->id}/verify")->assertOk();
        $this->api($this->people['keeper'], 'GET', '/hires?status=open')->assertJsonPath('data.hires.0.state', 'confirmed');
        // A keeper sees only the hires of what they keep; a plain member none.
        $this->api($this->people['juma'], 'GET', '/hires')->assertForbidden();
    }

    public function test_every_change_of_count_is_an_event_with_its_reason(): void
    {
        $this->api($this->people['chair'], 'POST', "/assets/{$this->chairs}/events", ['kind' => 'loss', 'quantity' => 3, 'note' => 'Stolen at the meeting'])->assertOk()->assertJsonPath('data.asset.quantity', 97);
        $this->api($this->people['chair'], 'POST', "/assets/{$this->chairs}/events", ['kind' => 'adjust', 'direction' => 'down', 'quantity' => 200, 'note' => 'Recount'])->assertStatus(422);
        $this->api($this->people['chair'], 'POST', "/assets/{$this->chairs}/events", ['kind' => 'repair', 'quantity' => 2, 'note' => 'Two fixed'])->assertOk()->assertJsonPath('data.asset.quantity', 99);
        $this->api($this->people['chair'], 'POST', "/assets/{$this->chairs}/events", ['kind' => 'maintenance', 'cost' => 15000, 'note' => 'Washed'])->assertOk();
        $this->assertSame(4, DB::table('group_asset_events')->where('asset_id', $this->chairs)->count(), 'registered, loss, repair, maintenance (the refused recount wrote nothing)');
        $this->api($this->people['chair'], 'PUT', "/assets/{$this->chairs}", ['code' => 'VT-01', 'name' => 'Viti', 'quantity' => 500])->assertStatus(422, 'the count changes only through events');
    }
}
