<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Support\Inventory\ShopTexts;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/** The shop's texts: the customer's receipt, the thank-you for a debt paid, and the owner's night summary; each under its own business. */
class ShopTextsTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function setUp(): void
    {
        parent::setUp();
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);
        Carbon::setTestNow(Carbon::parse('2026-11-18 10:00:00', 'Africa/Dar_es_Salaam')->utc());
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function shop(string $name = 'DUKA LA MAMA ASHA', array $business = []): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => $name] + $business);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, fn () => TenantContext::runInService('inventory', $fn));
    }

    private function product(User $as, string $name, int $cost, int $price): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'sku' => strtoupper(substr($name, 0, 3)) . ++$this->seq, 'quantity' => 1000, 'min_stock' => 0, 'status' => 'active', 'cost_price' => $cost, 'selling_price' => $price])->assertCreated()->json('data.id');
    }

    private function customer(User $as, string $name, string $phone): int
    {
        return $this->api($as, 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertCreated()->json('data.id');
    }

    private function sell(User $as, int $product, int $qty, int $price, int $cost, ?int $customer = null, int $paid = -1)
    {
        $total = $qty * $price;
        $paid = $paid < 0 ? $total : $paid;

        return $this->api($as, 'POST', '/api/inventory/sales', array_filter([
            'customer_id' => $customer, 'payment_status' => $paid >= $total ? 'paid' : ($paid > 0 ? 'partial' : 'debt'), 'subtotal' => $total, 'discount' => 0, 'tax' => 0, 'total' => $total,
            'paid_total' => $paid, 'due_date' => $paid >= $total ? null : now()->addDays(7)->toDateString(),
            'items' => [['product_id' => $product, 'quantity' => $qty, 'unit_price' => $price, 'unit_cost_snapshot' => $cost]],
        ], fn ($v) => $v !== null))->assertCreated();
    }

    // ------------------------------------------------------------------ the receipt

    public function test_a_customer_gets_a_receipt_naming_what_they_bought_and_the_business_as_registered(): void
    {
        $owner = $this->shop('DUKA LA MAMA ASHA');
        $sugar = $this->product($owner, 'Sukari', 1500, 3000);
        $juma = $this->customer($owner, 'juma bakari', '0711000001');

        $this->sell($owner, $sugar, 15, 3000, 1500, $juma, 30000);

        $texts = $this->sms->to('0711000001');
        $this->assertCount(1, $texts);
        $this->assertSame(
            'Habari Juma, umenunua Sukari kwa TSh 45,000 kwa DUKA LA MAMA ASHA. Umelipa TSh 30,000, bado TSh 15,000. Asante, karibu tena!',
            $texts[0]['message']
        );
    }

    public function test_a_sale_paid_in_full_says_so_and_a_walk_in_or_an_opted_out_customer_gets_nothing(): void
    {
        $owner = $this->shop();
        $rice = $this->product($owner, 'Mchele', 1000, 2000);
        $ann = $this->customer($owner, 'Ann', '0711000002');
        $bob = $this->customer($owner, 'Bob', '0711000003');
        $this->rows($owner, fn () => DB::table('inventory_customers')->where('id', $bob)->update(['sms_opt_out' => true]));

        $this->sell($owner, $rice, 2, 2000, 1000, $ann);
        $this->sell($owner, $rice, 2, 2000, 1000, $bob);
        $this->sell($owner, $rice, 2, 2000, 1000, null);

        $this->assertCount(1, $this->sms->sent, 'only the customer who can be texted');
        $this->assertStringContainsString('Umelipa kikamilifu', $this->sms->sent[0]['message']);
        $this->assertStringNotContainsString('Paid in full', $this->sms->sent[0]['message'], 'Swahili only');
    }

    public function test_the_owner_can_switch_the_customer_texts_off(): void
    {
        $owner = $this->shop();
        $rice = $this->product($owner, 'Mchele', 1000, 2000);
        $ann = $this->customer($owner, 'Ann', '0711000002');
        $this->rows($owner, fn () => ShopTexts::saveCustomersOn(false));

        $this->sell($owner, $rice, 2, 2000, 1000, $ann);

        $this->assertCount(0, $this->sms->sent);
    }

    public function test_each_business_texts_its_own_customers_under_its_own_sender_and_name(): void
    {
        $a = $this->shop('DUKA A', ['sms_sender_id' => 'DUKAA', 'sms_sender_status' => 'approved']);
        $b = $this->shop('DUKA B', ['sms_sender_id' => 'DUKAB', 'sms_sender_status' => 'approved']);
        $pa = $this->product($a, 'Sukari', 1000, 2000);
        $pb = $this->product($b, 'Mafuta', 1000, 2000);
        $ca = $this->customer($a, 'Ann', '0711000011');
        $cb = $this->customer($b, 'Bob', '0711000022');

        $this->sell($a, $pa, 1, 2000, 1000, $ca);
        $this->sell($b, $pb, 1, 2000, 1000, $cb);

        $this->assertCount(2, $this->sms->sent);
        $toAnn = $this->sms->to('0711000011')[0];
        $toBob = $this->sms->to('0711000022')[0];
        $this->assertSame('DUKAA', $toAnn['sender']);
        $this->assertSame('DUKAB', $toBob['sender']);
        $this->assertStringContainsString('DUKA A', $toAnn['message']);
        $this->assertStringNotContainsString('DUKA B', $toAnn['message']);
        $this->assertStringContainsString('DUKA B', $toBob['message']);
        $this->assertStringContainsString('Mafuta', $toBob['message']);
        $this->assertStringNotContainsString('Sukari', $toBob['message']);
    }

    // ------------------------------------------------------------------ a debt paid

    public function test_paying_on_a_debt_thanks_the_customer_and_says_what_is_left(): void
    {
        $owner = $this->shop('DUKA LA MAMA ASHA');
        $sugar = $this->product($owner, 'Sukari', 1500, 3000);
        $juma = $this->customer($owner, 'Juma', '0711000001');
        $sale = $this->sell($owner, $sugar, 5, 3000, 1500, $juma, 0)->json('data.id');
        $this->sms->sent = [];

        $this->api($owner, 'POST', "/api/inventory/sales/{$sale}/payments", ['amount' => 10000, 'method' => 'cash'])->assertOk();

        $texts = $this->sms->to('0711000001');
        $this->assertCount(1, $texts);
        $this->assertSame(
            'Asante Juma, tumepokea TSh 10,000. Deni lililobaki: TSh 5,000. Karibu DUKA LA MAMA ASHA!',
            $texts[0]['message']
        );

        $this->api($owner, 'POST', "/api/inventory/sales/{$sale}/payments", ['amount' => 5000, 'method' => 'cash'])->assertOk();
        $this->assertStringContainsString('Deni lako limelipwa lote', $this->sms->to('0711000001')[1]['message']);
    }

    public function test_receiving_a_payment_from_a_customer_texts_them_too(): void
    {
        $owner = $this->shop('DUKA LA MAMA ASHA');
        $sugar = $this->product($owner, 'Sukari', 1500, 3000);
        $juma = $this->customer($owner, 'Juma', '0711000001');
        $this->sell($owner, $sugar, 5, 3000, 1500, $juma, 0);
        $this->sms->sent = [];

        $this->api($owner, 'POST', '/api/inventory/payments', ['customer_id' => $juma, 'amount' => 10000, 'method' => 'cash'])->assertCreated();

        $texts = $this->sms->to('0711000001');
        $this->assertCount(1, $texts);
        $this->assertStringContainsString('tumepokea TSh 10,000. Deni lililobaki: TSh 5,000', $texts[0]['message']);
    }

    // ------------------------------------------------------------------ the night summary

    private function atNight(string $day = '2026-11-18'): void
    {
        Carbon::setTestNow(Carbon::parse("{$day} 23:59:00", 'Africa/Dar_es_Salaam')->utc());
    }

    public function test_the_owner_is_texted_the_day_with_the_difference_from_yesterday_once_a_night(): void
    {
        $owner = $this->shop('DUKA LA MAMA ASHA');
        $sugar = $this->product($owner, 'Sukari', 1000, 2000);
        $juma = $this->customer($owner, 'Juma', '0711000001');

        // yesterday: 100,000 sold at a cost of 50,000 (profit 50,000)
        Carbon::setTestNow(Carbon::parse('2026-11-17 12:00:00', 'Africa/Dar_es_Salaam')->utc());
        $this->sell($owner, $sugar, 50, 2000, 1000);
        // today: 320,000 sold (cost 160,000), 25,000 of it left owing, 18,000 spent
        Carbon::setTestNow(Carbon::parse('2026-11-18 12:00:00', 'Africa/Dar_es_Salaam')->utc());
        $this->sell($owner, $sugar, 160, 2000, 1000, $juma, 295000);
        $this->api($owner, 'POST', '/api/inventory/expenses', ['category' => 'rent', 'description' => 'Rent', 'amount' => 18000, 'expense_date' => '2026-11-18'])->assertCreated();
        // 9,000 spent on themselves: named apart, never taken off the profit
        $this->api($owner, 'POST', '/api/inventory/expenses', ['category' => 'family', 'description' => 'School fees', 'amount' => 9000, 'expense_date' => '2026-11-18', 'is_personal' => true])->assertCreated();
        $this->sms->sent = [];

        $this->atNight();
        $this->artisan('inventory:daily-summary', ['--dry-run' => true])->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent, 'a dry run sends nothing');
        $this->artisan('inventory:daily-summary')->assertExitCode(0);

        $this->assertCount(1, $this->sms->sent);
        $this->assertSame($owner->phone_number, $this->sms->sent[0]['to']);
        $this->assertSame(
            'Leo DUKA LA MAMA ASHA: mauzo TSh 320,000, faida TSh 142,000, matumizi TSh 18,000, madeni mapya TSh 25,000. Tofauti ya faida na jana: +TSh 92,000. Matumizi binafsi TSh 9,000 hayahesabiwi kwenye faida.',
            $this->sms->sent[0]['message']
        );

        $this->artisan('inventory:daily-summary')->assertExitCode(0);
        $this->assertCount(1, $this->sms->sent, 'the same night again: not texted twice');
    }

    public function test_a_worse_day_says_minus_and_a_day_at_a_loss_says_loss(): void
    {
        $text = ShopTexts::summaryMessage('DUKA', ['sales' => 10000, 'cost' => 9000, 'expenses' => 5000, 'profit' => -4000, 'new_debts' => 0, 'personal' => 0.0], ['sales' => 30000, 'cost' => 0, 'expenses' => 0, 'profit' => 6000, 'new_debts' => 0, 'personal' => 0.0]);

        $this->assertStringContainsString('hasara TSh 4,000', $text);
        $this->assertStringContainsString('Tofauti ya faida na jana: -TSh 10,000.', $text);
        $this->assertStringNotContainsString('binafsi', $text, 'no personal spending, no line about it');
        $this->assertStringNotContainsString('Today', $text, 'Swahili only');
    }

    public function test_each_shop_is_told_only_its_own_day_under_its_own_sender_and_the_owner_can_switch_it_off(): void
    {
        $a = $this->shop('DUKA A', ['sms_sender_id' => 'DUKAA', 'sms_sender_status' => 'approved']);
        $b = $this->shop('DUKA B', ['sms_sender_id' => 'DUKAB', 'sms_sender_status' => 'approved']);
        $c = $this->shop('DUKA C');
        $pa = $this->product($a, 'Sukari', 1000, 2000);
        $pb = $this->product($b, 'Mafuta', 1000, 2000);
        $this->sell($a, $pa, 10, 2000, 1000);
        $this->sell($b, $pb, 1, 2000, 1000);
        $this->rows($c, fn () => ShopTexts::saveSummaryOn(false));
        $this->sms->sent = [];

        $this->atNight();
        $this->artisan('inventory:daily-summary')->assertExitCode(0);

        $this->assertCount(2, $this->sms->sent, 'DUKA C switched it off');
        $toA = $this->sms->to($a->phone_number)[0];
        $toB = $this->sms->to($b->phone_number)[0];
        $this->assertSame('DUKAA', $toA['sender']);
        $this->assertSame('DUKAB', $toB['sender']);
        $this->assertStringContainsString('Leo DUKA A: mauzo TSh 20,000', $toA['message']);
        $this->assertStringContainsString('Leo DUKA B: mauzo TSh 2,000', $toB['message']);
        $this->assertCount(0, $this->sms->to($c->phone_number));
    }

    public function test_the_night_summary_is_scheduled_for_23_59_in_tanzania(): void
    {
        // 23:59 in Tanzania (UTC+3) is 20:59 UTC, the clock the server runs on
        $this->artisan('schedule:list')->expectsOutputToContain('inventory:daily-summary')->assertExitCode(0);
        $this->assertStringContainsString("dailyAt('20:59')", (string) file_get_contents(base_path('routes/console.php')));
    }

    // ------------------------------------------------------------------ low stock, month end, a debt reminder

    public function test_the_owner_is_told_each_morning_which_goods_are_low_once_and_never_when_none_are(): void
    {
        $owner = $this->shop('DUKA LA MAMA ASHA', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'approved']);
        $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Sukari', 'sku' => 'SUK1', 'quantity' => 3, 'min_stock' => 10, 'status' => 'active', 'cost_price' => 1000, 'selling_price' => 2000])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Mchele', 'sku' => 'MCH1', 'quantity' => 50, 'min_stock' => 10, 'status' => 'active', 'cost_price' => 1000, 'selling_price' => 2000])->assertCreated();
        $this->sms->sent = [];
        Carbon::setTestNow(Carbon::parse('2026-11-19 08:00:00', 'Africa/Dar_es_Salaam')->utc());

        $this->artisan('inventory:low-stock')->assertExitCode(0);
        $this->artisan('inventory:low-stock')->assertExitCode(0);

        $this->assertCount(1, $this->sms->sent, 'once a morning');
        $this->assertSame('MAMAASHA', $this->sms->sent[0]['sender']);
        $this->assertSame('DUKA LA MAMA ASHA: bidhaa 1 zimebaki chache: Sukari (3). Ongeza stoo.', $this->sms->sent[0]['message']);
    }

    public function test_nothing_is_texted_when_no_goods_are_low_or_when_it_is_switched_off(): void
    {
        $quiet = $this->shop('DUKA Q');
        $this->api($quiet, 'POST', '/api/inventory/products', ['name' => 'Mchele', 'sku' => 'MCH2', 'quantity' => 50, 'min_stock' => 10, 'status' => 'active', 'cost_price' => 1000, 'selling_price' => 2000])->assertCreated();
        $off = $this->shop('DUKA OFF');
        $this->api($off, 'POST', '/api/inventory/products', ['name' => 'Sukari', 'sku' => 'SUK2', 'quantity' => 1, 'min_stock' => 10, 'status' => 'active', 'cost_price' => 1000, 'selling_price' => 2000])->assertCreated();
        $this->api($off, 'PUT', '/api/inventory/settings', ['inv_low_stock_sms' => '0'])->assertOk();
        $this->sms->sent = [];

        $this->artisan('inventory:low-stock')->assertExitCode(0);

        $this->assertCount(0, $this->sms->sent);
    }

    public function test_the_month_end_text_says_the_profit_the_trend_and_the_target(): void
    {
        $report = [
            'figures' => ['net_profit' => 2140000],
            'compare' => ['net_profit' => ['direction' => 'up', 'percent' => 12.5]],
            'target' => ['status' => 'reached', 'profit_target' => 2000000, 'left' => 0],
        ];
        $this->assertSame(
            'DUKA LA MAMA ASHA: Oktoba 2026 umeisha. Faida TSh 2,140,000 (imepanda 12.5%). Lengo la TSh 2,000,000 limefikiwa. Fungua app uone ripoti kamili.',
            ShopTexts::monthMessage('DUKA LA MAMA ASHA', '2026-10', $report)
        );
        $report['target'] = ['status' => 'missed', 'profit_target' => 3000000, 'left' => 860000];
        $this->assertStringContainsString('Lengo la TSh 3,000,000 halikufikiwa, upungufu TSh 860,000.', ShopTexts::monthMessage('DUKA', '2026-10', $report));
    }

    public function test_the_owner_can_remind_a_customer_of_their_debt_and_is_told_why_when_it_cannot_be_done(): void
    {
        $owner = $this->shop('DUKA LA MAMA ASHA', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'approved']);
        $sugar = $this->product($owner, 'Sukari', 1500, 3000);
        $juma = $this->customer($owner, 'Juma', '0711000001');
        $none = $this->customer($owner, 'Hana Deni', '0711000009');
        $this->sell($owner, $sugar, 5, 3000, 1500, $juma, 0);
        $this->sms->sent = [];

        $this->api($owner, 'POST', "/api/inventory/credit/customers/{$juma}/remind")->assertOk()->assertJsonPath('data.owed', 15000);

        $this->assertCount(1, $this->sms->sent);
        $this->assertSame('MAMAASHA', $this->sms->sent[0]['sender']);
        $this->assertSame('Habari Juma, unadaiwa TSh 15,000 na DUKA LA MAMA ASHA. Tafadhali lipa ukipata nafasi. Asante!', $this->sms->sent[0]['message']);
        $this->api($owner, 'POST', "/api/inventory/credit/customers/{$none}/remind")->assertStatus(422)->assertJsonPath('data.reason', 'owes_nothing');
        $this->assertCount(1, $this->sms->sent, 'nothing sent for a customer who owes nothing');
    }

    public function test_the_text_switches_are_on_from_the_start_in_the_settings(): void
    {
        $owner = $this->shop();
        $s = $this->api($owner, 'GET', '/api/inventory/settings')->assertOk()->json('data');

        foreach (['inv_customer_sms', 'inv_daily_summary', 'inv_low_stock_sms', 'inv_month_sms', 'inv_debt_reminder_sms'] as $key) {
            $this->assertSame('1', $s[$key], $key);
        }
    }

    // ------------------------------------------------------------------ the weekly debt reminder

    private function morning(string $day): void
    {
        Carbon::setTestNow(Carbon::parse("{$day} 10:00:00", 'Africa/Dar_es_Salaam')->utc());
    }

    public function test_a_customer_who_has_owed_for_a_week_is_reminded_once_a_week_and_never_a_new_debt_or_a_paid_one(): void
    {
        $this->morning('2026-11-01');
        $owner = $this->shop('DUKA LA MAMA ASHA', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'approved']);
        $sugar = $this->product($owner, 'Sukari', 1500, 3000);
        $old = $this->customer($owner, 'Juma', '0711000001');
        $new = $this->customer($owner, 'Neo', '0711000002');
        $paid = $this->customer($owner, 'Paid', '0711000003');
        $quiet = $this->customer($owner, 'Quiet', '0711000004');
        $this->rows($owner, fn () => DB::table('inventory_customers')->where('id', $quiet)->update(['sms_opt_out' => true]));
        $this->sell($owner, $sugar, 5, 3000, 1500, $old, 0);
        $this->sell($owner, $sugar, 1, 3000, 1500, $quiet, 0);
        $this->sell($owner, $sugar, 1, 3000, 1500, $paid, 3000);
        $this->morning('2026-11-06');
        $this->sell($owner, $sugar, 1, 3000, 1500, $new, 0);
        $this->sms->sent = [];

        // 8 days after the first debts: Juma is due; Neo's debt is two days old; Paid owes nothing; Quiet asked for no texts
        $this->morning('2026-11-09');
        $this->artisan('inventory:debt-reminders', ['--dry-run' => true])->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent, 'a dry run sends nothing');
        $this->artisan('inventory:debt-reminders')->assertExitCode(0);

        $this->assertCount(1, $this->sms->sent);
        $this->assertSame('0711000001', $this->sms->sent[0]['to']);
        $this->assertSame('MAMAASHA', $this->sms->sent[0]['sender']);
        $this->assertSame('Habari Juma, unadaiwa TSh 15,000 na DUKA LA MAMA ASHA. Tafadhali lipa ukipata nafasi. Asante!', $this->sms->sent[0]['message']);

        $this->artisan('inventory:debt-reminders')->assertExitCode(0);
        $this->morning('2026-11-12');
        $this->artisan('inventory:debt-reminders')->assertExitCode(0);
        $this->assertCount(1, $this->sms->sent, 'not again within the week');

        // a week later Juma is reminded again, and Neo (now over a week) for the first time
        $this->morning('2026-11-16');
        $this->artisan('inventory:debt-reminders')->assertExitCode(0);
        $this->assertCount(3, $this->sms->sent);
        $this->assertSame(['0711000001', '0711000001', '0711000002'], array_column($this->sms->sent, 'to'));
    }

    public function test_debt_reminders_can_be_switched_off_and_a_failed_text_is_tried_again(): void
    {
        $this->morning('2026-11-01');
        $owner = $this->shop();
        $sugar = $this->product($owner, 'Sukari', 1500, 3000);
        $juma = $this->customer($owner, 'Juma', '0711000001');
        $this->sell($owner, $sugar, 5, 3000, 1500, $juma, 0);
        $this->morning('2026-11-09');
        $this->sms->sent = [];

        $this->api($owner, 'PUT', '/api/inventory/settings', ['inv_debt_reminder_sms' => '0'])->assertOk();
        $this->artisan('inventory:debt-reminders')->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent, 'switched off');

        $this->api($owner, 'PUT', '/api/inventory/settings', ['inv_debt_reminder_sms' => '1'])->assertOk();
        $this->sms->refuseAll();
        $this->artisan('inventory:debt-reminders')->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent);

        $this->sms = new \Tests\Support\FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);
        $this->artisan('inventory:debt-reminders')->assertExitCode(0);
        $this->assertCount(1, $this->sms->sent, 'the failed one was tried again');
    }

    public function test_the_debt_reminder_is_scheduled_for_10_in_the_morning_in_tanzania(): void
    {
        $this->artisan('schedule:list')->expectsOutputToContain('inventory:debt-reminders')->assertExitCode(0);
        $this->assertStringContainsString("->dailyAt('07:00')", (string) file_get_contents(base_path('routes/console.php')));
    }
}
