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
 * Groups (Vikundi): the payment methods the group authorises. The Mwenyekiti (and the Makamu) choose them and set where each is paid; everyone
 * reads them; once chosen, money is recorded only by those methods, in or out. Before that, every method is accepted as it always was.
 */
class GroupsPaymentMethodsTest extends TestCase
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
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['deputy', '0712000002', 'makamu_mwenyekiti'], ['treasurer', '0712000003', 'mweka_hazina'], ['assistant', '0712000004', 'mweka_hazina_msaidizi'],
            ['secretary', '0712000005', 'katibu'], ['asha', '0713000001', null]] as [$key, $phone, $office]) {
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

    /** @return array<int, array<string, mixed>> */
    private function chosen(): array
    {
        return [
            ['method' => 'mpesa', 'number' => '0754 100 200', 'account_name' => 'Umoja wa Wajasiriamali Mikocheni'],
            ['method' => 'bank_transfer', 'number' => '2051234567', 'account_name' => 'UWM Savings Group', 'bank_name' => 'NMB'],
            ['method' => 'airtel_money', 'number' => '0784 300 400', 'account_name' => 'UWM Savings Group'],
        ];
    }

    private function choose(array $methods = null): void
    {
        $this->api($this->people['chair'], 'PUT', '/payment-methods', ['methods' => $methods ?? $this->chosen(), 'reason' => 'Uamuzi wa kikao cha Novemba'])->assertOk();
    }

    public function test_the_mwenyekiti_and_the_makamu_choose_the_methods_nobody_else(): void
    {
        $this->assertContains('manage_payment_methods', GroupOffices::rightsOf('mwenyekiti'));
        $this->assertContains('manage_payment_methods', GroupOffices::rightsOf('makamu_mwenyekiti'));
        foreach (['mweka_hazina', 'mweka_hazina_msaidizi', 'katibu', 'katibu_msaidizi', 'mwenyekiti_miradi', 'kamati_miradi'] as $office) {
            $this->assertNotContains('manage_payment_methods', GroupOffices::rightsOf($office));
        }
        foreach (['treasurer', 'secretary', 'asha'] as $who) {
            $this->api($this->people[$who], 'PUT', '/payment-methods', ['methods' => $this->chosen(), 'reason' => 'Jaribu'])->assertForbidden();
        }
        $this->api($this->people['deputy'], 'PUT', '/payment-methods', ['methods' => $this->chosen(), 'reason' => 'Chair yuko safarini'])->assertOk();
    }

    public function test_until_the_group_chooses_every_method_is_accepted_as_before(): void
    {
        $this->api($this->people['asha'], 'GET', '/payment-methods')->assertOk()->assertJsonPath('data.configured', false)->assertJsonCount(0, 'data.methods');
        $this->api($this->people['asha'], 'GET', '/me')->assertJsonCount(0, 'data.payment_methods');
        foreach (['cash', 'mpesa', 'halopesa', 'other'] as $i => $method) {
            $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids['asha'], 'category' => 'savings', 'amount' => 1000, 'method' => $method, 'external_ref' => $method === 'cash' ? null : "REF{$i}"])->assertCreated();
        }
    }

    public function test_each_chosen_method_needs_where_to_pay_and_a_bank_its_name(): void
    {
        $chair = $this->people['chair'];
        $put = fn (array $methods) => $this->api($chair, 'PUT', '/payment-methods', ['methods' => $methods, 'reason' => 'Uamuzi wa kikao']);

        $put([])->assertStatus(422);
        $put([['method' => 'mpesa', 'account_name' => 'UWM']])->assertStatus(422)->assertJsonPath('code', 'number_needed');
        $put([['method' => 'mpesa', 'number' => '0754100200']])->assertStatus(422)->assertJsonPath('code', 'name_needed');
        $put([['method' => 'bank_transfer', 'number' => '2051234567', 'account_name' => 'UWM']])->assertStatus(422)->assertJsonPath('code', 'bank_needed');
        $put([['method' => 'bitcoin', 'number' => '1', 'account_name' => 'UWM']])->assertStatus(422);
        $put([['method' => 'mpesa', 'number' => 'drop table; --', 'account_name' => 'UWM']])->assertStatus(422);
        $put([['method' => 'mpesa', 'number' => '0754100200', 'account_name' => 'UWM'], ['method' => 'mpesa', 'number' => '0754100201', 'account_name' => 'UWM']])->assertStatus(422);
        $this->api($chair, 'PUT', '/payment-methods', ['methods' => $this->chosen()])->assertStatus(422);
        $this->assertSame(0, DB::table('group_payment_methods')->count(), 'nothing was saved by a refused request');

        $put([['method' => 'cash'], ['method' => 'mixx', 'number' => '0652 111 222', 'account_name' => 'UWM'], ['method' => 'halopesa', 'number' => '0621 333 444', 'account_name' => 'UWM']])->assertOk();
        $this->assertSame(['cash', 'mixx', 'halopesa'], DB::table('group_payment_methods')->orderBy('sort')->pluck('method')->all());
    }

    public function test_everyone_in_the_group_reads_where_to_pay_for_each_method(): void
    {
        $this->choose();
        foreach (['asha', 'treasurer', 'secretary'] as $who) {
            $r = $this->api($this->people[$who], 'GET', '/payment-methods')->assertOk()->assertJsonPath('data.configured', true)->assertJsonCount(3, 'data.methods');
            $this->assertSame(['mpesa', 'bank_transfer', 'airtel_money'], collect($r->json('data.methods'))->pluck('method')->all(), 'in the order the chair chose');
            $this->assertSame('0754 100 200', $r->json('data.methods.0.number'));
            $this->assertSame('NMB', $r->json('data.methods.1.bank_name'));
        }
        $me = $this->api($this->people['asha'], 'GET', '/me')->assertOk();
        $this->assertSame('2051234567', collect($me->json('data.payment_methods'))->firstWhere('method', 'bank_transfer')['number']);
        $this->assertFalse($this->api($this->people['asha'], 'GET', '/payment-methods')->json('data.can_manage'));
        $this->assertTrue($this->api($this->people['chair'], 'GET', '/payment-methods')->json('data.can_manage'));
    }

    public function test_once_chosen_money_is_recorded_only_by_those_methods_in_or_out(): void
    {
        $this->choose();
        $pay = fn (string $method) => $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'savings', 'amount' => 5000, 'method' => $method, 'external_ref' => "R-{$method}"]);
        $pay('cash')->assertStatus(422)->assertJsonPath('code', 'method_not_authorized');
        $pay('halopesa')->assertStatus(422)->assertJsonPath('code', 'method_not_authorized');
        $pay('mixx')->assertStatus(422);
        $pay('mpesa')->assertCreated();
        $pay('bank_transfer')->assertCreated();

        // The treasurer recording a member's payment is held to the same list.
        $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids['asha'], 'category' => 'savings', 'amount' => 1000, 'method' => 'cash'])
            ->assertStatus(422)->assertJsonPath('code', 'method_not_authorized');
        // So is money paid out: a savings withdrawal by cash is refused, by an authorised method it is recorded.
        $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids['asha'], 'category' => 'savings', 'direction' => 'out', 'amount' => 1000, 'method' => 'cash'])
            ->assertStatus(422)->assertJsonPath('code', 'method_not_authorized');
        $this->assertSame(2, DB::table('group_transactions')->count(), 'only the two authorised payments exist');
    }

    public function test_changing_the_list_replaces_it_and_the_change_is_in_the_activity_log(): void
    {
        $this->choose();
        $this->choose([['method' => 'cash'], ['method' => 'mpesa', 'number' => '0754 999 888', 'account_name' => 'UWM Mpya']]);
        $this->assertSame(['cash', 'mpesa'], DB::table('group_payment_methods')->orderBy('sort')->pluck('method')->all(), 'the others are no longer authorised');
        $this->assertSame('0754 999 888', DB::table('group_payment_methods')->where('method', 'mpesa')->value('number'));
        $this->assertSame(2, DB::table('group_audit_log')->where('action', 'payment_methods_changed')->count());
        $this->assertStringContainsString('Uamuzi wa kikao cha Novemba', (string) DB::table('group_audit_log')->where('action', 'payment_methods_changed')->orderByDesc('id')->value('summary'));
        // Cash is now authorised and needs no number; the airtel number is gone with its method.
        $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids['asha'], 'category' => 'savings', 'amount' => 1000, 'method' => 'cash'])->assertCreated();
        $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'savings', 'amount' => 5000, 'method' => 'airtel_money', 'external_ref' => 'AIR1'])->assertStatus(422);
    }

    public function test_the_treasurer_sees_the_months_verified_money_for_each_method_and_a_member_does_not(): void
    {
        $this->choose();
        $tx = $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'savings', 'amount' => 50000, 'method' => 'mpesa', 'external_ref' => 'MP1'])->assertCreated()->json('data.transaction.id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$tx}/verify")->assertOk();
        $pending = $this->api($this->people['asha'], 'POST', '/me/payments', ['category' => 'savings', 'amount' => 7000, 'method' => 'bank_transfer', 'external_ref' => 'BK1'])->assertCreated();

        $r = $this->api($this->people['treasurer'], 'GET', '/payment-methods')->assertOk();
        $mpesa = collect($r->json('data.methods'))->firstWhere('method', 'mpesa');
        $this->assertEquals(50000, $mpesa['month']['in']);
        $this->assertSame(1, $mpesa['month']['count']);
        $this->assertSame(0, collect($r->json('data.methods'))->firstWhere('method', 'bank_transfer')['month']['count'], 'waiting money is not counted yet');
        $this->assertArrayNotHasKey('month', $this->api($this->people['asha'], 'GET', '/payment-methods')->json('data.methods.0'));
        $this->assertNotNull($pending->json('data.transaction.id'));
    }
}
