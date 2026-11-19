<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Services\SmsService;
use App\Support\SmsQuota;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * SMS counted per business against the limit the super admin sets: the counter, the 3-day list, the warning and the stop at the limit
 * (owner and super admin texted), and that other businesses never notice.
 */
class SmsQuotaTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function setUp(): void
    {
        parent::setUp();
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);
        Carbon::setTestNow(Carbon::parse('2026-11-19 10:00:00', 'Africa/Dar_es_Salaam')->utc());
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function owner(string $name): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function business(User $owner): Business
    {
        return Business::withoutAccountScope()->with('owner')->where('owner_id', $owner->id)->firstOrFail();
    }

    private function superAdmin(): User
    {
        return User::factory()->create(['name' => 'Platform Admin', 'role' => 'super_admin', 'is_active' => true, 'phone_number' => '0617919104']);
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function text(User $owner, string $to = '0711000001', string $message = 'Habari, asante kwa kununua.'): bool
    {
        return SmsService::sendFor($this->business($owner), $to, $message);
    }

    public function test_a_text_costs_parts_as_the_provider_bills_them(): void
    {
        $this->assertSame(1, SmsQuota::parts(str_repeat('a', 160)));
        $this->assertSame(2, SmsQuota::parts(str_repeat('a', 161)));
        $this->assertSame(1, SmsQuota::parts(str_repeat('é', 70)));
        $this->assertSame(2, SmsQuota::parts(str_repeat('é', 71)));
        config(['sms.count_by' => 'messages']);
        $this->assertSame(1, SmsQuota::parts(str_repeat('a', 500)));
    }

    public function test_every_business_text_is_counted_and_listed_while_platform_texts_are_not(): void
    {
        $masai = $this->owner('masai mitumba bora');
        $other = $this->owner('DUKA LA MAMA ASHA');

        $this->text($masai);
        $this->text($masai, '0711000002', str_repeat('a', 200)); // 2 parts
        $this->text($other);
        SmsService::send('0711000003', 'Your code is 1234', true); // the platform's

        $this->assertSame(3, SmsQuota::usage($this->business($masai)->fresh())['used']);
        $this->assertSame(1, SmsQuota::usage($this->business($other)->fresh())['used']);
        $usage = SmsQuota::usage($this->business($masai)->fresh());
        $this->assertSame(2, $usage['week_messages']);
        $this->assertSame(3, $usage['week_parts']);
        $this->assertNull($usage['limit'], 'no limit until the super admin sets one: nothing is blocked');
        $this->assertCount(2, SmsQuota::recent($this->business($masai)));
        $this->assertSame('0711000002', SmsQuota::recent($this->business($masai))[0]['to']);
    }

    public function test_at_the_warning_line_and_at_the_limit_the_owner_and_the_super_admin_are_texted_once_and_texts_stop(): void
    {
        $this->superAdmin();
        $masai = $this->owner('masai mitumba bora');
        $other = $this->owner('DUKA LA MAMA ASHA');
        $ownerPhone = (string) $masai->phone_number;
        SmsQuota::setLimit($this->business($masai), 10, false);
        $this->sms->sent = [];

        for ($i = 0; $i < 8; $i++) {
            $this->assertTrue($this->text($masai));
        }
        $this->assertCount(0, $this->sms->to($ownerPhone));

        $this->assertTrue($this->text($masai)); // 9 of 10 = 90 %
        $this->assertCount(1, $this->sms->to($ownerPhone), 'the owner is warned');
        $this->assertStringContainsString('umetumia SMS 9 kati ya 10, zimebaki 1', $this->sms->to($ownerPhone)[0]['message']);
        $this->assertCount(1, $this->sms->to('0617919104'), 'the super admin is warned');
        $this->assertStringContainsString('masai mitumba bora', $this->sms->to('0617919104')[0]['message']);

        $this->assertTrue($this->text($masai)); // 10 of 10: the limit
        $this->assertCount(2, $this->sms->to($ownerPhone));
        $this->assertStringContainsString('kifurushi chako cha SMS (10) kimeisha', $this->sms->to($ownerPhone)[1]['message']);
        $this->assertNull($this->sms->to($ownerPhone)[1]['sender'], 'told under the platform name');
        $this->assertCount(2, $this->sms->to('0617919104'));
        $this->assertStringContainsString('imefikia kikomo cha SMS 10/10', $this->sms->to('0617919104')[1]['message']);

        $this->assertFalse($this->text($masai, '0711000099'), 'blocked at the limit');
        $this->assertCount(0, $this->sms->to('0711000099'));
        $this->assertCount(2, $this->sms->to($ownerPhone), 'told once, not on every refused text');
        $this->assertTrue(SmsQuota::usage($this->business($masai)->fresh())['blocked']);

        $this->assertTrue($this->text($other, '0711000098'), 'another business keeps sending');
    }

    public function test_the_super_admin_sets_the_limit_on_the_sender_screen_and_a_new_bundle_starts_the_counter_again(): void
    {
        $admin = $this->superAdmin();
        $masai = $this->owner('masai mitumba bora');
        $id = $this->business($masai)->id;
        SmsQuota::setLimit($this->business($masai), 2, false);
        $this->text($masai);
        $this->text($masai);
        $this->assertFalse($this->text($masai));
        $this->sms->sent = [];

        $this->api($admin, 'PUT', "/api/admin/sms-usage/{$id}/limit", ['sms_limit' => 1000, 'reset_used' => true])
            ->assertOk()->assertJsonPath('data.usage.used', 0)->assertJsonPath('data.usage.limit', 1000)->assertJsonPath('data.usage.blocked', false);
        $this->assertStringContainsString('kifurushi chako cha SMS kimewekwa: SMS 1000. Umetumia 0, zimebaki 1000', $this->sms->to((string) $masai->phone_number)[0]['message']);
        $this->assertTrue($this->text($masai), 'sending again');

        // The sender screen shows the counter too.
        $this->api($admin, 'GET', '/api/admin/sms-senders?q=masai')->assertOk()->assertJsonPath('data.0.sms_sender.usage.used', 1)->assertJsonPath('data.0.sms_sender.usage.limit', 1000);

        // No limit again.
        $this->api($admin, 'PUT', "/api/admin/sms-usage/{$id}/limit", ['sms_limit' => null])->assertOk()->assertJsonPath('data.usage.limit', null);
        $this->api($masai, 'PUT', "/api/admin/sms-usage/{$id}/limit", ['sms_limit' => 5])->assertForbidden();
    }

    public function test_the_list_keeps_three_days_and_the_counters_stay(): void
    {
        $masai = $this->owner('masai mitumba bora');
        $this->text($masai);
        Carbon::setTestNow(now()->addDays(4));
        $this->text($masai, '0711000002');

        Artisan::call('sms:prune-log');

        $recent = SmsQuota::recent($this->business($masai));
        $this->assertCount(1, $recent, 'the text from 4 days ago is gone from the list');
        $this->assertSame('0711000002', $recent[0]['to']);
        $this->assertSame(2, SmsQuota::usage($this->business($masai)->fresh())['used'], 'the counter keeps both');
        $this->assertSame(2, (int) DB::table('sms_daily_counts')->sum('messages'));
    }

    public function test_the_owner_sees_their_counter_and_the_super_admin_sees_every_business_and_its_texts(): void
    {
        $admin = $this->superAdmin();
        $masai = $this->owner('masai mitumba bora');
        $staff = $this->givenServices(User::factory()->create(['role' => 'sales_officer', 'is_active' => true, 'created_by' => $masai->id]), 'inventory');
        SmsQuota::setLimit($this->business($masai), 5000, false);
        $this->text($masai);

        $this->api($masai, 'GET', '/api/business/sms-usage')->assertOk()
            ->assertJsonPath('data.used', 1)->assertJsonPath('data.limit', 5000)->assertJsonPath('data.remaining', 4999)->assertJsonPath('data.business_name', 'masai mitumba bora');
        $this->api($staff, 'GET', '/api/business/sms-usage')->assertForbidden();

        $this->api($admin, 'GET', '/api/admin/sms-usage?q=masai')->assertOk()->assertJsonPath('data.0.usage.used', 1)->assertJsonPath('data.0.owner.name', 'masai mitumba bora Owner');
        $id = $this->business($masai)->id;
        $this->api($admin, 'GET', "/api/admin/sms-usage/{$id}")->assertOk()
            ->assertJsonPath('data.recent.0.to', '0711000001')->assertJsonPath('data.recent.0.message', 'Habari, asante kwa kununua.')->assertJsonPath('data.log_days', 3);
        $this->api($masai, 'GET', '/api/admin/sms-usage')->assertForbidden();
    }

    public function test_the_counter_list_holds_business_admins_only(): void
    {
        $admin = $this->superAdmin();
        $this->owner('masai mitumba bora');
        $this->owner('MaremaTech Labs');

        // An applicant who was never approved: switched off, no services.
        $applicant = User::factory()->create(['name' => 'sammi', 'role' => 'admin', 'is_active' => false, 'is_applicant' => true]);
        Business::ensureFor($applicant)?->update(['name' => 'sammi']);
        // A switched-off owner who still has a service.
        $off = $this->owner('closed shop');
        $off->update(['is_active' => false]);
        // A business record whose owner account is gone.
        $ghost = $this->owner('ivan samwel');
        Business::forOwnerId($ghost->id)->update(['owner_id' => (string) \Illuminate\Support\Str::uuid()]);

        $names = collect($this->api($admin, 'GET', '/api/admin/sms-usage')->assertOk()->json('data'))->pluck('name')->sort()->values()->all();

        $this->assertSame(['MaremaTech Labs', 'masai mitumba bora'], $names);
    }

    public function test_a_reminder_tapped_by_hand_says_the_sms_are_used_up(): void
    {
        $masai = $this->owner('masai mitumba bora');
        SmsQuota::setLimit($this->business($masai), 0, false);
        $customer = $this->api($masai, 'POST', '/api/inventory/customers', ['name' => 'Happy', 'phone' => '0711000005'])->assertCreated()->json('data.id');
        DB::table('inventory_opening_debts')->insert(['owner_id' => $masai->id, 'customer_id' => $customer, 'party_name' => 'Happy', 'kind' => 'receivable', 'amount' => 100000, 'paid_amount' => 0, 'started_on' => now()->subDays(10)->toDateString(), 'created_at' => now(), 'updated_at' => now()]);

        $this->withHeader('X-Service', 'inventory');
        $this->api($masai, 'POST', "/api/inventory/credit/customers/{$customer}/remind")->assertStatus(422)->assertJsonPath('data.reason', 'sms_limit');
        $this->assertCount(0, $this->sms->to('0711000005'));
    }
}
