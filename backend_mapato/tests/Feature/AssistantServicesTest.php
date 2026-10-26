<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\Rental\House;
use App\Models\Rental\MaintenanceRequest;
use App\Models\Rental\Property;
use App\Models\Rental\RentalAgreement;
use App\Models\Rental\RentBill;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * The assistant across all services and businesses: Transport and Rental data, the how-to guide, the one-call fast path, and the walls
 * between businesses, services and roles.
 */
class AssistantServicesTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function make(string $role, array $services, ?User $creator = null, array $extra = []): User
    {
        return $this->givenServices(User::factory()->create(array_merge([
            'role' => $role, 'is_active' => true, 'created_by' => $creator?->id, 'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ], $extra)), ...$services);
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    /** A transport business with one driver who owes money. @return array{0: User, 1: User} the admin and the driver's login */
    private function fleet(string $driverName, float $owes): array
    {
        $admin = $this->make('admin', ['transport']);
        $login = $this->make('driver', ['transport'], $admin, ['name' => $driverName]);
        $driverId = (string) Str::uuid();
        DB::table('drivers')->insert(['id' => $driverId, 'user_id' => $login->id, 'license_number' => 'LIC-' . Str::random(6), 'license_expiry' => now()->addYear()->toDateString(), 'created_at' => now(), 'updated_at' => now()]);
        DB::table('debt_records')->insert(['driver_id' => $driverId, 'earning_date' => now()->toDateString(), 'expected_amount' => $owes, 'paid_amount' => 0, 'is_paid' => false, 'days_overdue' => 12, 'created_at' => now(), 'updated_at' => now()]);
        DB::table('payments')->insert(['reference_number' => 'PAY-' . Str::random(8), 'driver_id' => $driverId, 'amount' => 5000, 'payment_channel' => 'cash', 'status' => 'completed', 'payment_date' => now(), 'recorded_by' => $admin->id, 'created_at' => now(), 'updated_at' => now()]);

        return [$admin, $login];
    }

    /** A rental business with one tenant who owes rent. @return array{0: User, 1: User, 2: User} landlord, tenant, caretaker */
    private function estate(string $tenantName, float $owes): array
    {
        $landlord = $this->make('landlord', ['rental']);
        $tenant = $this->make('tenant', ['rental'], $landlord, ['name' => $tenantName]);
        $caretaker = $this->make('caretaker', ['rental'], $landlord);
        $property = Property::create(['owner_id' => $landlord->id, 'caretaker_id' => $caretaker->id, 'name' => 'Plaza ' . $tenantName]);
        $house = House::create(['property_id' => $property->id, 'house_number' => 'A1', 'rent_amount' => 100000, 'status' => 'occupied']);
        $lease = RentalAgreement::create(['tenant_id' => $tenant->id, 'house_id' => $house->id, 'property_id' => $property->id, 'start_date' => now()->toDateString(), 'rent_cycle' => 'monthly', 'rent_amount' => 100000, 'status' => 'active']);
        RentBill::create(['agreement_id' => $lease->id, 'month_year' => now()->format('m-Y'), 'amount_due' => 100000, 'balance' => $owes, 'due_date' => now()->subDays(3)->toDateString(), 'status' => 'overdue']);
        MaintenanceRequest::create(['property_id' => $property->id, 'house_id' => $house->id, 'tenant_id' => $tenant->id, 'category' => 'plumbing', 'priority' => 'high', 'description' => 'Leak', 'status' => 'open']);

        return [$landlord, $tenant, $caretaker];
    }

    private function gemini(?string $tool = null, array $args = [], string $final = 'Done.'): void
    {
        config(['services.gemini.key' => 'g-test', 'services.gemini.model' => 'gemini-2.5-flash']);
        $final = ['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => $final]]]]]];
        Http::fake(['generativelanguage.googleapis.com/*' => $tool === null ? Http::response($final, 200) : Http::sequence()
            ->push(['candidates' => [['content' => ['role' => 'model', 'parts' => [['functionCall' => ['name' => $tool, 'args' => $args]]]]]]], 200)
            ->push($final, 200)]);
    }

    /** @return array<int, array<string, mixed>> */
    private function sent(): array
    {
        return Http::recorded()->map(fn ($pair) => $pair[0]->data())->values()->all();
    }

    private function topics(User $u): array
    {
        return $this->api($u, 'GET', '/api/assistant')->assertOk()->json('data.topics');
    }

    // ------------------------------------------------------------------ transport

    public function test_a_transport_admin_reads_their_own_drivers_debts_and_never_another_businesss(): void
    {
        [$a] = $this->fleet('Juma Dereva', 40000);
        $this->fleet('Other Business Driver', 99999);
        $this->gemini('transport_debts');

        $r = $this->api($a, 'POST', '/api/assistant', ['question' => 'Which drivers owe me?'])->assertOk();

        $card = $r->json('data.cards.0.rows.0');
        $this->assertSame(['Juma Dereva', 'TSh 40,000', '12 days'], [$card['title'], $card['value'], $card['note']]);
        $second = json_encode($this->sent()[1]['contents']);
        $this->assertStringContainsString('Juma Dereva', $second);
        $this->assertStringNotContainsString('Other Business Driver', $second);
        $this->assertSame(1, count($r->json('data.cards.0.rows')));
    }

    public function test_a_driver_is_offered_only_their_own_debts_and_payments(): void
    {
        [, $driver] = $this->fleet('Juma Dereva', 40000);
        $this->fleet('Other Business Driver', 99999);

        $topics = $this->topics($driver);
        $this->assertEqualsCanonicalizing(['transport_debts', 'transport_payments'], $topics, 'no fleet overview, no driver list, no shop or rental tools');

        $this->gemini('transport_debts');
        $this->api($driver, 'POST', '/api/assistant', ['question' => 'What do I owe?'])->assertOk();
        $second = json_encode($this->sent()[1]['contents']);
        $this->assertStringContainsString('Juma Dereva', $second);
        $this->assertStringNotContainsString('Other Business Driver', $second);
    }

    // ------------------------------------------------------------------ rental

    public function test_a_landlord_reads_their_rent_arrears_by_tenant_name_and_not_another_landlords(): void
    {
        [$landlord] = $this->estate('Mama Rehema', 70000);
        $this->estate('Mzee Hamisi', 88000);
        $this->gemini('rental_arrears');

        $r = $this->api($landlord, 'POST', '/api/assistant', ['question' => 'Who owes rent?'])->assertOk();

        $card = $r->json('data.cards.0.rows.0');
        $this->assertSame(['Mama Rehema', 'TSh 70,000'], [$card['title'], $card['value']]);
        $this->assertStringContainsString('overdue', $card['note']);
        $this->assertStringNotContainsString('Mzee Hamisi', json_encode($this->sent()[1]['contents']));
    }

    public function test_a_tenant_sees_only_their_own_rent_and_a_caretaker_only_maintenance(): void
    {
        [, $tenant, $caretaker] = $this->estate('Mama Rehema', 70000);
        $this->estate('Mzee Hamisi', 88000);

        $this->assertEqualsCanonicalizing(['rental_arrears', 'rental_maintenance'], $this->topics($tenant));
        $this->assertSame(['rental_maintenance'], $this->topics($caretaker));

        $this->gemini('rental_arrears');
        $this->api($tenant, 'POST', '/api/assistant', ['question' => 'What do I owe?'])->assertOk();
        $second = json_encode($this->sent()[1]['contents']);
        $this->assertStringContainsString('Mama Rehema', $second);
        $this->assertStringNotContainsString('Mzee Hamisi', $second);
    }

    // ------------------------------------------------------------------ services and platform

    public function test_each_business_gets_only_the_tools_of_its_own_services(): void
    {
        [$fleetAdmin] = $this->fleet('Juma Dereva', 1000);
        [$landlord] = $this->estate('Mama Rehema', 1000);
        $shop = $this->make('admin', ['inventory']);

        $this->assertSame([], array_filter($this->topics($fleetAdmin), fn ($t) => !str_starts_with($t, 'transport_')), 'a transport business has no shop or rental tools');
        $this->assertSame([], array_filter($this->topics($landlord), fn ($t) => !str_starts_with($t, 'rental_')));
        $this->assertSame([], array_filter($this->topics($shop), fn ($t) => str_starts_with($t, 'transport_') || str_starts_with($t, 'rental_')));
        $this->assertContains('business_report', $this->topics($shop));
    }

    public function test_the_platform_admin_gets_the_guide_but_no_business_data(): void
    {
        $this->gemini();
        $super = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);

        $this->assertSame([], $this->topics($super));
        $this->api($super, 'POST', '/api/assistant', ['question' => 'How do I add a business?'])->assertOk();
        $system = $this->sent()[0]['systemInstruction']['parts'][0]['text'];
        $this->assertStringContainsString('PLATFORM ADMIN', $system);
        $this->assertArrayNotHasKey('tools', $this->sent()[0], 'no tools to offer when nothing may be read');
    }

    // ------------------------------------------------------------------ the guide

    public function test_the_how_to_guide_is_cut_to_the_persons_services_and_rights(): void
    {
        [$landlord, $tenant] = $this->estate('Mama Rehema', 1000);
        $this->gemini();

        $this->api($landlord, 'POST', '/api/assistant', ['question' => 'How do I add a tenant?'])->assertOk();
        $this->api($tenant, 'POST', '/api/assistant', ['question' => 'How do I pay?'])->assertOk();
        [$forLandlord, $forTenant] = array_map(fn ($b) => $b['systemInstruction']['parts'][0]['text'], $this->sent());

        $this->assertStringContainsString('TENANTS AND LEASES', $forLandlord);
        $this->assertStringContainsString('Services this business has: rental', $forLandlord);
        $this->assertStringNotContainsString('SELLING:', $forLandlord);
        $this->assertStringNotContainsString('DRIVERS:', $forLandlord);
        $this->assertStringContainsString('AS A TENANT', $forTenant);
        $this->assertStringNotContainsString('TENANTS AND LEASES', $forTenant, 'a tenant is not told how to onboard tenants');
    }

    public function test_the_suggestions_follow_the_persons_services_and_rights(): void
    {
        [$fleetAdmin] = $this->fleet('Juma', 1000);
        [$landlord] = $this->estate('Rehema', 1000);

        $ids = fn (User $u) => array_column($this->api($u, 'GET', '/api/assistant')->json('data.suggestions'), 'id');

        $this->assertContains('sg_t_debt', $ids($fleetAdmin));
        $this->assertContains('hg_driver', $ids($fleetAdmin));
        $this->assertNotContains('sg_r_owe', $ids($fleetAdmin));
        $this->assertContains('sg_r_owe', $ids($landlord));
        $this->assertContains('hg_tenant', $ids($landlord));
        $this->assertNotContains('hg_driver', $ids($landlord));
        $this->assertContains('hg_start', $ids($landlord));
    }

    // ------------------------------------------------------------------ speed

    public function test_a_one_tap_suggestion_is_answered_with_one_ai_call_and_the_data_already_in_it(): void
    {
        [$landlord] = $this->estate('Mama Rehema', 70000);
        $this->gemini(null, [], 'Mama Rehema owes TSh 70,000.');

        $r = $this->api($landlord, 'POST', '/api/assistant', ['question' => 'Which tenants owe rent?', 'topic' => 'sg_r_owe'])->assertOk();

        Http::assertSentCount(1);
        $body = $this->sent()[0];
        $this->assertArrayNotHasKey('tools', $body, 'nothing to wait for: the data was read first');
        $this->assertStringContainsString('Mama Rehema', json_encode($body['contents']));
        $this->assertSame('Mama Rehema', $r->json('data.cards.0.rows.0.title'));
    }

    public function test_a_suggestion_that_is_not_the_persons_own_is_not_a_shortcut_to_its_data(): void
    {
        [, $tenant] = $this->estate('Mama Rehema', 70000);
        $this->gemini(null, [], 'I cannot show that.');

        // sg_r_over (the landlord's overview) is not one of the tenant's suggestions, so it must not read anything.
        $r = $this->api($tenant, 'POST', '/api/assistant', ['question' => 'Overview', 'topic' => 'sg_r_over'])->assertOk();

        $this->assertSame([], $r->json('data.cards'));
        $this->assertStringNotContainsString('rent_collected_this_month', json_encode($this->sent()[0]['contents']));
    }

    public function test_the_flash_model_is_asked_not_to_think_so_answers_come_back_fast(): void
    {
        $this->gemini();
        $shop = $this->make('admin', ['inventory']);
        Business::forOwnerId($shop->id)->update(['name' => 'Quick Shop']);

        $this->api($shop, 'POST', '/api/assistant', ['question' => 'How do I add a product?', 'topic' => 'hg_product'])->assertOk();

        $this->assertSame(0, $this->sent()[0]['generationConfig']['thinkingConfig']['thinkingBudget']);
        $this->assertLessThanOrEqual(1024, $this->sent()[0]['generationConfig']['maxOutputTokens']);
        $this->assertStringContainsString('PRODUCTS: menu "Products"', $this->sent()[0]['systemInstruction']['parts'][0]['text']);
    }
}
