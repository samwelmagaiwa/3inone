<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * What one business sets in its Settings never reaches another business: the shop's settings, the salon's settings (reminders,
 * booking page, loyalty), the receipt, the business profile. Two shops, two salons, and one owner who has both a shop and a salon.
 * A member of staff reads their own business's settings and may change them only with the right to.
 */
class SettingsIndependenceTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private User $alpha;
    private User $bravo;
    private User $glow;
    private User $shine;
    private User $duo;

    protected function setUp(): void
    {
        parent::setUp();
        $this->alpha = $this->owner('Alpha Shop', ['inventory']);
        $this->bravo = $this->owner('Bravo Shop', ['inventory']);
        $this->glow = $this->owner('Glow Salon', ['salon']);
        $this->shine = $this->owner('Shine Salon', ['salon']);
        $this->duo = $this->owner('Duo Business', ['inventory', 'salon']);
    }

    private function owner(string $name, array $services): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0724' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), ...$services);
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function staff(User $owner, string $service, array $permissions = []): User
    {
        $user = User::factory()->create([
            'name' => 'Staff', 'role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id,
            'phone_number' => '0725' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]);
        $this->givenServices($user, $service);
        if ($permissions !== []) {
            $user->forceFill(['permissions' => $permissions])->save();
        }

        return $user;
    }

    private function api(User $as, string $method, string $uri, array $body = [], string $service = 'inventory')
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', $service)->json($method, $uri, $body);
    }

    private function settings(User $as, string $service = 'inventory'): array
    {
        return $this->api($as, 'GET', '/api/inventory/settings', [], $service)->assertOk()->json('data');
    }

    private function salonSettings(User $as): array
    {
        return $this->api($as, 'GET', '/api/inventory/salon/settings', [], 'salon')->assertOk()->json('data');
    }

    // ------------------------------------------------------------------ the shop's settings

    public function test_every_shop_setting_one_business_saves_stays_in_that_business(): void
    {
        $values = [
            'depot_name' => 'Alpha Wholesale', 'depot_phone' => '0711000111', 'depot_address' => 'Kariakoo', 'tax_percent' => '18',
            'max_discount_percent' => '25', 'low_stock_threshold' => '9', 'receipt_footer_note' => 'Alpha thanks you', 'receipt_tin' => '111-111-111',
            'receipt_tagline' => 'Best prices', 'receipt_email' => 'alpha@shop.test', 'receipt_website' => 'alpha.test', 'invoice_prefix' => 'ALP',
            'sale_tier' => 'wholesale', 'prices_include_vat' => '0', 'use_crates' => '0', 'hidden_reports' => 'stock_valuation',
        ];
        $before = $this->settings($this->bravo);

        $this->api($this->alpha, 'PUT', '/api/inventory/settings', $values)->assertOk();

        $alpha = $this->settings($this->alpha);
        foreach ($values as $key => $value) {
            $this->assertSame($value, (string) $alpha[$key], "{$key} is saved for Alpha");
        }
        $bravo = $this->settings($this->bravo);
        foreach (array_keys($values) as $key) {
            $this->assertSame((string) ($before[$key] ?? ''), (string) ($bravo[$key] ?? ''), "{$key} did not move for Bravo");
        }
    }

    public function test_the_same_setting_can_hold_a_different_value_in_each_business_and_each_keeps_its_own(): void
    {
        $this->api($this->alpha, 'PUT', '/api/inventory/settings', ['tax_percent' => '18', 'receipt_footer_note' => 'Alpha'])->assertOk();
        $this->api($this->bravo, 'PUT', '/api/inventory/settings', ['tax_percent' => '5', 'receipt_footer_note' => 'Bravo'])->assertOk();
        $this->api($this->alpha, 'PUT', '/api/inventory/settings', ['tax_percent' => '20'])->assertOk();

        $this->assertSame('20', (string) $this->settings($this->alpha)['tax_percent']);
        $this->assertSame('5', (string) $this->settings($this->bravo)['tax_percent']);
        $this->assertSame('Alpha', $this->settings($this->alpha)['receipt_footer_note']);
        $this->assertSame('Bravo', $this->settings($this->bravo)['receipt_footer_note']);
    }

    public function test_a_business_that_never_saved_a_setting_reads_its_own_default_never_anothers_value(): void
    {
        $this->api($this->alpha, 'PUT', '/api/inventory/settings', ['depot_name' => 'Alpha Only', 'sale_tier' => 'wholesale'])->assertOk();

        $bravo = $this->settings($this->bravo);
        $this->assertNotSame('Alpha Only', $bravo['depot_name']);
        $this->assertStringContainsString('Bravo', $bravo['depot_name'], 'a new business starts from its own name');
        $this->assertNotSame('wholesale', $bravo['sale_tier']);
    }

    public function test_an_unknown_setting_is_ignored_and_never_appears_in_anothers_settings(): void
    {
        $this->api($this->alpha, 'PUT', '/api/inventory/settings', ['not_a_real_setting' => 'evil', 'tax_percent' => '7']);

        $this->assertArrayNotHasKey('not_a_real_setting', $this->settings($this->bravo));
        $this->assertSame('7', (string) $this->settings($this->alpha)['tax_percent']);
    }

    // ------------------------------------------------------------------ the salon's settings

    public function test_the_salon_reminders_and_options_of_one_salon_never_reach_another(): void
    {
        $before = $this->salonSettings($this->shine);

        $this->api($this->glow, 'PUT', '/api/inventory/salon/settings', [
            'rebook_enabled' => true, 'rebook_weeks' => 9, 'appointment_reminders' => true, 'daily_summary' => true, 'cancel_hours' => 36,
            'feedback_sms' => true, 'birthday_offer' => true, 'birthday_text' => 'Happy birthday from Glow',
        ], 'salon')->assertOk();

        $glow = $this->salonSettings($this->glow);
        $this->assertSame([true, 9, 36, true, 'Happy birthday from Glow'], [$glow['rebook_enabled'], $glow['rebook_weeks'], $glow['cancel_hours'], $glow['feedback_sms'], $glow['birthday_text']]);
        $this->assertSame($before, $this->salonSettings($this->shine), 'Shine saw nothing change');

        $this->api($this->shine, 'PUT', '/api/inventory/salon/settings', ['rebook_weeks' => 3, 'cancel_hours' => 2], 'salon')->assertOk();
        $this->assertSame(9, $this->salonSettings($this->glow)['rebook_weeks']);
        $this->assertSame(36, $this->salonSettings($this->glow)['cancel_hours']);
        $this->assertSame(3, $this->salonSettings($this->shine)['rebook_weeks']);
    }

    public function test_the_salons_loyalty_scheme_is_its_own(): void
    {
        $this->api($this->glow, 'PUT', '/api/inventory/salon/loyalty/settings', ['on' => true, 'per' => 2500, 'value' => 75, 'referral' => 5], 'salon')->assertOk();

        $shine = $this->api($this->shine, 'GET', '/api/inventory/salon/loyalty/settings', [], 'salon')->assertOk()->json('data');
        $glow = $this->api($this->glow, 'GET', '/api/inventory/salon/loyalty/settings', [], 'salon')->assertOk()->json('data');
        $this->assertTrue($glow['on']);
        $this->assertSame(2500, $glow['per']);
        $this->assertFalse($shine['on']);
        $this->assertNotSame(2500, $shine['per']);
        $this->assertNotSame(75, $shine['value']);
    }

    public function test_the_online_booking_address_is_one_salons_only_and_cannot_be_taken_twice(): void
    {
        $this->api($this->glow, 'PUT', '/api/inventory/salon/settings', ['booking_slug' => 'glow-salon', 'online_booking' => true], 'salon')->assertOk();

        $this->api($this->shine, 'PUT', '/api/inventory/salon/settings', ['booking_slug' => 'glow-salon'], 'salon')->assertStatus(422);
        $this->assertNull($this->salonSettings($this->shine)['booking_slug']);
        $this->assertSame('glow-salon', $this->salonSettings($this->glow)['booking_slug']);

        $this->api($this->shine, 'PUT', '/api/inventory/salon/settings', ['booking_slug' => 'shine-salon'], 'salon')->assertOk();
        $this->assertSame('glow-salon', $this->salonSettings($this->glow)['booking_slug'], 'Glow keeps its own address');
        $this->assertSame('shine-salon', $this->salonSettings($this->shine)['booking_slug']);
    }

    public function test_a_salons_receipt_and_tax_settings_are_its_own_not_the_shops_or_another_salons(): void
    {
        $this->api($this->glow, 'PUT', '/api/inventory/settings', ['tax_percent' => '18', 'receipt_footer_note' => 'Glow says hi', 'depot_name' => 'Glow Hair'], 'salon')->assertOk();

        $shine = $this->settings($this->shine, 'salon');
        $this->assertSame('0', (string) $shine['tax_percent']);
        $this->assertNotSame('Glow says hi', $shine['receipt_footer_note']);
        $this->assertStringContainsString('Shine', $shine['depot_name']);
        $this->assertStringNotContainsString('Glow', $shine['depot_name']);
    }

    // ------------------------------------------------------------------ one owner with a shop and a salon

    public function test_an_owner_with_a_shop_and_a_salon_keeps_their_settings_apart(): void
    {
        $this->api($this->duo, 'PUT', '/api/inventory/settings', ['tax_percent' => '18', 'receipt_footer_note' => 'Shop note', 'depot_phone' => '0711111111'], 'inventory')->assertOk();
        $this->api($this->duo, 'PUT', '/api/inventory/settings', ['tax_percent' => '5', 'receipt_footer_note' => 'Salon note'], 'salon')->assertOk();
        $this->api($this->duo, 'PUT', '/api/inventory/salon/settings', ['rebook_weeks' => 7], 'salon')->assertOk();

        $shop = $this->settings($this->duo, 'inventory');
        $salon = $this->settings($this->duo, 'salon');
        $this->assertSame(['18', 'Shop note'], [(string) $shop['tax_percent'], $shop['receipt_footer_note']]);
        $this->assertSame(['5', 'Salon note'], [(string) $salon['tax_percent'], $salon['receipt_footer_note']]);
        $this->assertSame(7, $this->salonSettings($this->duo)['rebook_weeks']);
    }

    // ------------------------------------------------------------------ the business profile

    public function test_the_business_profile_of_one_owner_never_changes_another(): void
    {
        $this->api($this->alpha, 'PUT', '/api/business', ['name' => 'Alpha Trading', 'phone' => '0712345678', 'address' => 'Dodoma', 'tin' => '123-456-789'])->assertOk();

        $bravo = $this->api($this->bravo, 'GET', '/api/business')->assertOk()->json('data');
        $this->assertSame('Bravo Shop', $bravo['name']);
        $this->assertNotSame('0712345678', $bravo['phone'] ?? null);
        $this->assertNotSame('123-456-789', $bravo['tin'] ?? null);
        $this->assertSame('Alpha Trading', $this->api($this->alpha, 'GET', '/api/business')->json('data.name'));
        $this->assertSame('Glow Salon', $this->api($this->glow, 'GET', '/api/business', [], 'salon')->json('data.name'));
    }

    // ------------------------------------------------------------------ staff

    public function test_staff_read_their_own_business_settings_and_nobody_elses(): void
    {
        $this->api($this->alpha, 'PUT', '/api/inventory/settings', ['depot_name' => 'Alpha Wholesale', 'tax_percent' => '18'])->assertOk();
        $this->api($this->bravo, 'PUT', '/api/inventory/settings', ['depot_name' => 'Bravo Wholesale', 'tax_percent' => '5'])->assertOk();
        $staff = $this->staff($this->alpha, 'inventory');

        $seen = $this->settings($staff);

        $this->assertSame('Alpha Wholesale', $seen['depot_name']);
        $this->assertSame('18', (string) $seen['tax_percent']);
    }

    public function test_staff_without_the_right_cannot_change_settings_and_with_it_change_only_their_own_business(): void
    {
        $this->api($this->bravo, 'PUT', '/api/inventory/settings', ['tax_percent' => '5'])->assertOk();
        $plain = $this->staff($this->alpha, 'inventory', ['inv_create_sales']);
        $manager = $this->staff($this->alpha, 'inventory', ['inv_manage_settings']);

        $this->api($plain, 'PUT', '/api/inventory/settings', ['tax_percent' => '99'])->assertForbidden();
        $this->assertNotSame('99', (string) $this->settings($this->alpha)['tax_percent']);

        $this->api($manager, 'PUT', '/api/inventory/settings', ['tax_percent' => '12'])->assertOk();
        $this->assertSame('12', (string) $this->settings($this->alpha)['tax_percent']);
        $this->assertSame('5', (string) $this->settings($this->bravo)['tax_percent'], 'Bravo is untouched');
    }
}
