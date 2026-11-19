<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Services\SmsService;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * The owner's master switch for the business's texts (Settings > Notifications > SMS): off, nothing the business sends goes out until it is
 * switched on again; other businesses are untouched; each text's own setting is kept; only the owner, with the password (and the word ZIMA
 * to switch off), can change it.
 */
class BusinessSmsSwitchTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function setUp(): void
    {
        parent::setUp();
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);
    }

    private function shop(string $name): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    private function sellTo(User $as, string $customerName, string $phone, int $paid = 2000): int
    {
        $product = $this->api($as, 'POST', '/api/inventory/products', ['name' => 'Mchele', 'sku' => 'MCH' . ++$this->seq, 'quantity' => 100, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 1000, 'selling_price' => 2000])->assertCreated()->json('data.id');
        $customer = $this->api($as, 'POST', '/api/inventory/customers', ['name' => $customerName, 'phone' => $phone])->assertCreated()->json('data.id');
        $this->api($as, 'POST', '/api/inventory/sales', array_filter([
            'customer_id' => $customer, 'payment_status' => $paid >= 2000 ? 'paid' : 'debt', 'subtotal' => 2000, 'discount' => 0, 'tax' => 0, 'total' => 2000,
            'paid_total' => $paid, 'due_date' => $paid >= 2000 ? null : now()->addDays(7)->toDateString(),
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => 2000, 'unit_cost_snapshot' => 1000]],
        ], fn ($v) => $v !== null))->assertCreated();

        return (int) $customer;
    }

    private function switchOff(User $owner): void
    {
        $this->api($owner, 'PUT', '/api/business/sms-switch', ['enabled' => false, 'password' => 'password', 'confirm' => 'zima'])
            ->assertOk()->assertJsonPath('data.enabled', false);
    }

    public function test_off_stops_every_text_of_that_business_only_and_on_brings_them_back_with_the_settings_kept(): void
    {
        $masai = $this->shop('masai mitumba bora');
        $other = $this->shop('DUKA LA MAMA ASHA');

        $this->switchOff($masai);
        $this->assertTrue(Business::forOwnerId($masai->id)->smsPaused());

        $this->sellTo($masai, 'Happy', '0711000001');
        $this->sellTo($other, 'Juma', '0711000002');

        $this->assertCount(0, $this->sms->to('0711000001'), 'the paused business sends nothing');
        $this->assertCount(1, $this->sms->to('0711000002'), 'another business is not touched');

        // Nothing was deleted or switched: the shop's own text settings are as they were.
        $this->assertNotSame('0', TenantContext::runAs($masai, fn () => DB::table('inventory_settings')->where('key', 'inv_customer_sms')->value('value')));

        $this->api($masai, 'PUT', '/api/business/sms-switch', ['enabled' => true, 'password' => 'password'])->assertOk()->assertJsonPath('data.enabled', true);
        $this->sellTo($masai, 'Neema', '0711000003');
        $this->assertCount(1, $this->sms->to('0711000003'), 'texts go again once switched on');
    }

    public function test_switching_needs_the_owners_password_and_the_word_zima_to_switch_off(): void
    {
        $owner = $this->shop('masai mitumba bora');

        $this->api($owner, 'PUT', '/api/business/sms-switch', ['enabled' => false, 'password' => 'wrong', 'confirm' => 'ZIMA'])->assertStatus(422)->assertJsonValidationErrors('password');
        $this->api($owner, 'PUT', '/api/business/sms-switch', ['enabled' => false, 'password' => 'password'])->assertStatus(422)->assertJsonValidationErrors('confirm');
        $this->api($owner, 'PUT', '/api/business/sms-switch', ['enabled' => false, 'password' => 'password', 'confirm' => 'yes'])->assertStatus(422);
        $this->assertFalse(Business::forOwnerId($owner->id)->smsPaused(), 'still on after every refused try');

        $this->switchOff($owner);
        $this->assertDatabaseHas('businesses', ['owner_id' => $owner->id, 'sms_paused' => true, 'sms_paused_by' => (string) $owner->id]);
    }

    public function test_only_the_owner_can_change_it_while_staff_only_see_it(): void
    {
        $owner = $this->shop('masai mitumba bora');
        $staff = $this->givenServices(User::factory()->create(['role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id]), 'inventory');

        $this->api($staff, 'GET', '/api/business/sms-switch')->assertOk()->assertJsonPath('data.enabled', true)->assertJsonPath('data.can_change', false);
        $this->api($staff, 'PUT', '/api/business/sms-switch', ['enabled' => false, 'password' => 'password', 'confirm' => 'ZIMA'])->assertForbidden();
        $this->assertFalse(Business::forOwnerId($owner->id)->smsPaused());

        $this->api($owner, 'GET', '/api/business/sms-switch')->assertOk()->assertJsonPath('data.can_change', true)->assertJsonPath('data.confirm_word', 'ZIMA');
        $this->switchOff($owner);
        $this->api($staff, 'GET', '/api/business/sms-switch')->assertOk()->assertJsonPath('data.enabled', false)->assertJsonPath('data.paused_by', $owner->name);
    }

    public function test_a_reminder_tapped_by_hand_says_the_texts_are_off(): void
    {
        $owner = $this->shop('masai mitumba bora');
        $happy = $this->sellTo($owner, 'Happy', '0711000001', 0);
        $this->sms->sent = [];
        $this->switchOff($owner);

        $this->api($owner, 'POST', "/api/inventory/credit/customers/{$happy}/remind")
            ->assertStatus(422)->assertJsonPath('data.reason', 'sms_paused');
        $this->assertCount(0, $this->sms->sent);
    }

    // ------------------------------------------------------------------ the super admin, for one business

    private function superAdmin(): User
    {
        return User::factory()->create(['name' => 'Platform Admin', 'role' => 'super_admin', 'is_active' => true]);
    }

    public function test_the_super_admin_switches_off_one_business_and_only_that_one_and_the_owner_cannot_undo_it(): void
    {
        $admin = $this->superAdmin();
        $masai = $this->shop('masai mitumba bora');
        $other = $this->shop('DUKA LA MAMA ASHA');
        $masaiId = Business::forOwnerId($masai->id)->id;

        $this->api($admin, 'PUT', "/api/admin/businesses/{$masaiId}/sms-switch", ['enabled' => false, 'password' => 'password', 'confirm' => 'ZIMA'])
            ->assertOk()->assertJsonPath('data.enabled', false)->assertJsonPath('data.paused_by_platform', true)->assertJsonPath('data.business_name', 'masai mitumba bora');

        $this->sellTo($masai, 'Happy', '0711000001');
        $this->sellTo($other, 'Juma', '0711000002');
        $this->assertCount(0, $this->sms->to('0711000001'), 'the business the super admin picked sends nothing');
        $this->assertCount(1, $this->sms->to('0711000002'), 'every other business still sends');

        // The owner sees it is off by the platform and cannot switch it back on.
        $this->api($masai, 'GET', '/api/business/sms-switch')->assertOk()
            ->assertJsonPath('data.enabled', false)->assertJsonPath('data.paused_by_platform', true)->assertJsonPath('data.can_change', false);
        $this->api($masai, 'PUT', '/api/business/sms-switch', ['enabled' => true, 'password' => 'password'])
            ->assertForbidden()->assertJsonPath('code', 'paused_by_platform');
        $this->assertTrue(Business::forOwnerId($masai->id)->smsPaused());

        // Only the super admin brings them back.
        $this->api($admin, 'PUT', "/api/admin/businesses/{$masaiId}/sms-switch", ['enabled' => true, 'password' => 'password'])
            ->assertOk()->assertJsonPath('data.enabled', true)->assertJsonPath('data.paused_by_platform', false);
        $this->sellTo($masai, 'Neema', '0711000003');
        $this->assertCount(1, $this->sms->to('0711000003'));
        $this->api($masai, 'GET', '/api/business/sms-switch')->assertOk()->assertJsonPath('data.can_change', true);
    }

    public function test_the_super_admin_needs_their_password_and_the_word_and_nobody_else_reaches_the_admin_switch(): void
    {
        $admin = $this->superAdmin();
        $masai = $this->shop('masai mitumba bora');
        $id = Business::forOwnerId($masai->id)->id;

        $this->api($admin, 'PUT', "/api/admin/businesses/{$id}/sms-switch", ['enabled' => false, 'password' => 'wrong', 'confirm' => 'ZIMA'])->assertStatus(422);
        $this->api($admin, 'PUT', "/api/admin/businesses/{$id}/sms-switch", ['enabled' => false, 'password' => 'password'])->assertStatus(422)->assertJsonValidationErrors('confirm');
        $this->api($masai, 'PUT', "/api/admin/businesses/{$id}/sms-switch", ['enabled' => false, 'password' => 'password', 'confirm' => 'ZIMA'])->assertForbidden();
        $this->assertFalse(Business::forOwnerId($masai->id)->smsPaused());

        $this->api($admin, 'GET', "/api/admin/businesses/{$id}/sms-switch")->assertOk()->assertJsonPath('data.enabled', true);
        $this->api($admin, 'GET', '/api/admin/businesses?q=masai')->assertOk()->assertJsonPath('data.0.sms_sender.paused', false);
    }

    public function test_a_business_the_owner_switched_off_can_be_taken_over_by_the_super_admin(): void
    {
        $admin = $this->superAdmin();
        $masai = $this->shop('masai mitumba bora');
        $id = Business::forOwnerId($masai->id)->id;

        $this->switchOff($masai);
        $this->api($admin, 'GET', "/api/admin/businesses/{$id}/sms-switch")->assertOk()->assertJsonPath('data.paused_by', $masai->name)->assertJsonPath('data.paused_by_platform', false);
        $this->api($admin, 'PUT', "/api/admin/businesses/{$id}/sms-switch", ['enabled' => false, 'password' => 'password', 'confirm' => 'zima'])->assertOk()->assertJsonPath('data.paused_by_platform', true);
        $this->api($masai, 'PUT', '/api/business/sms-switch', ['enabled' => true, 'password' => 'password'])->assertForbidden();
    }

    public function test_the_owner_is_texted_from_the_platform_when_the_super_admin_switches_their_sms_off_and_on(): void
    {
        $admin = $this->superAdmin();
        $masai = $this->shop('masai mitumba bora');
        $masai->update(['name' => 'Julius Labarani']);
        $id = Business::forOwnerId($masai->id)->id;
        $phone = (string) $masai->phone_number;

        $this->api($admin, 'PUT', "/api/admin/businesses/{$id}/sms-switch", ['enabled' => false, 'password' => 'password', 'confirm' => 'ZIMA'])->assertOk();

        $texts = $this->sms->to($phone);
        $this->assertCount(1, $texts, 'the owner is told, even though the business itself can no longer text');
        $this->assertNull($texts[0]['sender'], 'under the platform name, not the paused business');
        $this->assertSame(
            "Ndugu Julius Labarani, mmiliki wa biashara ya masai mitumba bora,\n\n"
            . "Tunakujulisha kuwa huduma ya kutuma SMS kwa wateja wako imezimwa kwa muda. Tafadhali wasiliana na Administrator ili huduma hii iweze kurejeshwa na kuruhusu SMS kuendelea kuwafikia wateja wako.\n\n"
            . "Asante kwa kuwa mteja wetu.\n\n"
            . "Kwa msaada, wasiliana nasi kupitia:\n0617919104 / 0743519104",
            $texts[0]['message']
        );

        // Switching off what is already off says nothing more.
        $this->api($admin, 'PUT', "/api/admin/businesses/{$id}/sms-switch", ['enabled' => false, 'password' => 'password', 'confirm' => 'ZIMA'])->assertOk();
        $this->assertCount(1, $this->sms->to($phone));

        $this->api($admin, 'PUT', "/api/admin/businesses/{$id}/sms-switch", ['enabled' => true, 'password' => 'password'])->assertOk();
        $texts = $this->sms->to($phone);
        $this->assertCount(2, $texts);
        $this->assertStringContainsString('imewashwa tena', $texts[1]['message']);
        $this->assertStringStartsWith('Ndugu Julius Labarani, mmiliki wa biashara ya masai mitumba bora,', $texts[1]['message']);
    }

    public function test_the_owner_moving_their_own_switch_gets_no_text(): void
    {
        $masai = $this->shop('masai mitumba bora');
        $this->switchOff($masai);
        $this->api($masai, 'PUT', '/api/business/sms-switch', ['enabled' => true, 'password' => 'password'])->assertOk();

        $this->assertCount(0, $this->sms->to((string) $masai->phone_number));
    }

    public function test_a_text_given_no_business_still_cannot_slip_out_for_a_paused_one_while_platform_texts_go(): void
    {
        $owner = $this->shop('masai mitumba bora');
        $this->switchOff($owner);

        $this->assertFalse(TenantContext::runAs($owner, fn () => SmsService::sendFor(null, '0711000009', 'hello')));
        $this->assertTrue(SmsService::send('0711000009', 'Your code is 1234', true), 'codes and other platform texts are not the business\'s');
        $this->assertCount(1, $this->sms->sent);
    }
}
