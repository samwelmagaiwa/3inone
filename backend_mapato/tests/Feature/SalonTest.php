<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Support\PlanCatalog;
use App\Support\Salon\RebookPlanner;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * The Salon service: a fourth service that runs on the sales engine shared with Inventory.
 *
 * A salon sells SERVICES (no stock) and some goods (shampoo), says which stylist served each line, can look up a
 * client's history, sees how each stylist did, and can have clients texted "it has been 4 weeks since your
 * braiding" when it is time to come back. Several salons share one database, so every check that matters is made
 * with two salons side by side.
 */
class SalonTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    // ------------------------------------------------------------------ fixtures

    private function salon(string $name = 'Glow Salon', array $services = ['salon']): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0723' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), ...$services);
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function stylist(User $owner, string $name, string $role = 'sales_officer', bool $withService = true): User
    {
        $user = User::factory()->create(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]);

        return $withService ? $this->givenServices($user, 'salon') : $user;
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, $fn);
    }

    private function service(User $as, string $name, int $price, array $extra = []): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', array_merge([
            'name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active',
            'cost_price' => 0, 'selling_price' => $price,
        ], $extra))->assertCreated()->json('data.id');
    }

    private function goods(User $as, string $name, int $qty, int $price): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', [
            'name' => $name, 'quantity' => $qty, 'min_stock' => 2, 'status' => 'active',
            'cost_price' => (int) ($price / 2), 'selling_price' => $price,
        ])->assertCreated()->json('data.id');
    }

    private function client(User $as, string $name, string $phone): int
    {
        return $this->api($as, 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertCreated()->json('data.id');
    }

    /** Ring up a cash sale. Each item: [product_id, quantity, unit_price, (staff_id)]. */
    private function sell(User $as, array $items, ?int $clientId = null)
    {
        $lines = array_map(fn (array $i) => array_filter([
            'product_id' => $i[0], 'quantity' => $i[1], 'unit_price' => $i[2], 'staff_id' => $i[3] ?? null,
        ], fn ($v) => $v !== null), $items);
        $total = array_sum(array_map(fn (array $i) => $i[1] * $i[2], $items));

        return $this->api($as, 'POST', '/api/inventory/sales', array_filter([
            'customer_id' => $clientId, 'payment_status' => 'paid', 'subtotal' => $total, 'discount' => 0, 'tax' => 0,
            'total' => $total, 'paid_total' => $total, 'items' => $lines,
        ], fn ($v) => $v !== null));
    }

    private function at(string $when): void
    {
        Carbon::setTestNow(Carbon::parse($when, 'UTC'));
    }

    private function stock(User $as, int $productId): int
    {
        return (int) $this->rows($as, fn () => DB::table('inventory_products')->where('id', $productId)->value('quantity'));
    }

    private function enableRebooking(User $owner, int $weeks = 4): void
    {
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['rebook_enabled' => true, 'rebook_weeks' => $weeks])->assertOk();
    }

    /** Swap in a fresh fake SMS provider (the way a test starts over). */
    private function freshSms(): FakeSmsGateway
    {
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);

        return $this->sms;
    }

    // ------------------------------------------------------------------ the service itself

    public function test_a_salon_runs_on_the_sales_engine_and_gets_none_of_the_other_services(): void
    {
        $owner = $this->salon();

        $this->api($owner, 'GET', '/api/inventory/products')->assertOk();
        $this->api($owner, 'GET', '/api/rental/properties')->assertForbidden()->assertJsonPath('code', 'service_not_assigned');
    }

    public function test_a_salon_starts_as_a_retail_business_without_crates(): void
    {
        $owner = $this->salon();

        $this->assertSame('retail', Business::forOwnerId($owner->id)->inventory_type);
        $useCrates = $this->rows($owner, fn () => DB::table('inventory_settings')->where('key', 'use_crates')->value('value'));
        $this->assertSame('0', $useCrates, 'a salon has no returnable crates');
    }

    public function test_a_business_that_chose_its_inventory_kind_keeps_it_when_salon_is_added(): void
    {
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');
        Business::forOwnerId($owner->id)->update(['inventory_type' => 'wholesale']);

        $this->givenServices($owner, 'salon');

        $this->assertSame('wholesale', Business::forOwnerId($owner->id)->inventory_type);
    }

    public function test_staff_get_the_salon_only_when_it_was_given_to_them_and_to_the_business(): void
    {
        $owner = $this->salon();
        $withService = $this->stylist($owner, 'Asha');
        $withoutService = $this->stylist($owner, 'Zuri', withService: false);

        $this->api($withService, 'GET', '/api/inventory/products')->assertOk();
        // a sales officer with no service bound falls back to the role's default (inventory), which this business does not have
        $this->api($withoutService, 'GET', '/api/inventory/products')->assertForbidden();
    }

    public function test_an_owner_can_create_staff_for_the_salon_service(): void
    {
        $owner = $this->salon();

        $this->api($owner, 'POST', '/api/admin/users', [
            'name' => 'Mwajuma Stylist', 'email' => 'mwajuma@example.test', 'phone_number' => '0755123456',
            'password' => 'Secret123!', 'password_confirmation' => 'Secret123!',
            'role' => 'sales_officer', 'service_types' => ['salon'], 'permissions' => ['inv_create_sales'],
        ])->assertCreated();

        $staff = User::query()->where('email', 'mwajuma@example.test')->first();
        $this->assertSame(['salon'], $staff->serviceTypes());
    }

    public function test_a_super_admin_has_the_salon_like_every_other_service_even_if_their_saved_services_predate_it(): void
    {
        $super = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
        // what an account made before the salon existed has saved: the three old services
        foreach (['inventory', 'rental', 'transport'] as $service) {
            $super->services()->create(['service_type' => $service]);
        }
        $super->unsetRelation('services');

        $this->assertContains('salon', $super->allowedServiceTypes());
        $this->assertTrue($super->canUseService('salon'));
        $this->assertContains('salon', $super->effectiveServiceTypes());

        // signing in brings the saved list up to date, and the salon's screens answer
        $services = $this->api($super, 'GET', '/api/auth/user')->assertOk()->json('data.user.services');
        $this->assertContains('salon', array_column($services, 'service_type'));
        $this->api($super, 'GET', '/api/inventory/products')->assertOk();
        $this->api($super, 'GET', '/api/inventory/salon/settings')->assertOk();
    }

    public function test_four_services_are_sold_but_a_plan_covers_at_most_three(): void
    {
        $this->assertSame(['transport', 'rental', 'inventory', 'salon'], config('billing.services'));
        $this->assertTrue(PlanCatalog::covers('premium', 3));
        $this->assertFalse(PlanCatalog::covers('premium', 4));
        $this->assertSame('premium', PlanCatalog::planFor(3));

        $message = PlanCatalog::tooSmallMessage('premium', 4);
        $this->assertStringContainsString('huduma 3 au pungufu', $message);
        $this->assertStringContainsString('3 services at most', $message);
        $this->assertStringNotContainsString('Choose the Premium plan', $message, 'there is no bigger plan to point to');
    }

    // ------------------------------------------------------------------ services are not stock

    public function test_a_service_has_no_stock_a_duration_and_a_rebook_wait(): void
    {
        $owner = $this->salon();
        $id = $this->service($owner, 'Braids', 40000, ['quantity' => 5, 'min_stock' => 3, 'duration_minutes' => 180, 'rebook_after_weeks' => 6]);

        $row = $this->rows($owner, fn () => DB::table('inventory_products')->find($id));
        $this->assertTrue((bool) $row->is_service);
        $this->assertSame(0, (int) $row->quantity, 'whatever was typed, a service has nothing on a shelf');
        $this->assertSame(0, (int) $row->min_stock);
        $this->assertSame(180, (int) $row->duration_minutes);
        $this->assertSame(6, (int) $row->rebook_after_weeks);
    }

    public function test_services_and_goods_can_be_listed_apart(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);
        $shampoo = $this->goods($owner, 'Shampoo', 10, 8000);

        $services = array_column($this->api($owner, 'GET', '/api/inventory/products?is_service=1')->assertOk()->json('data'), 'id');
        $goods = array_column($this->api($owner, 'GET', '/api/inventory/products?is_service=0')->assertOk()->json('data'), 'id');

        $this->assertSame([$braids], $services);
        $this->assertSame([$shampoo], $goods);
    }

    public function test_a_service_sells_with_no_stock_and_never_moves_any(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);

        $this->sell($owner, [[$braids, 3, 40000]])->assertCreated();

        $this->assertSame(0, $this->stock($owner, $braids));
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_stock_movements')->where('product_id', $braids)->count()));
        $line = $this->rows($owner, fn () => DB::table('inventory_sale_items')->where('product_id', $braids)->first());
        $this->assertTrue((bool) $line->is_service);
        $this->assertSame(0.0, (float) $line->unit_cost_snapshot, 'a service carries no cost of goods');
        $this->assertSame(120000.0, (float) $line->total);
    }

    public function test_goods_on_the_same_receipt_are_still_guarded_and_still_leave_the_shelf(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);
        $shampoo = $this->goods($owner, 'Shampoo', 10, 8000);

        $this->sell($owner, [[$braids, 1, 40000], [$shampoo, 4, 8000]])->assertCreated();
        $this->assertSame(6, $this->stock($owner, $shampoo));

        $this->sell($owner, [[$braids, 1, 40000], [$shampoo, 7, 8000]])->assertStatus(422)->assertJsonPath('code', 'insufficient_stock');
        $this->assertSame(6, $this->stock($owner, $shampoo), 'a refused receipt takes nothing');
        $this->assertSame(1, $this->rows($owner, fn () => DB::table('inventory_sales')->count()), 'and writes nothing');
    }

    public function test_services_never_raise_a_low_stock_alert(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);
        // even if a service somehow carried a minimum, it can never be "low"
        $this->rows($owner, fn () => DB::table('inventory_products')->where('id', $braids)->update(['min_stock' => 5]));

        $this->assertSame([], $this->api($owner, 'GET', '/api/inventory/products?low_stock=1')->assertOk()->json('data'));
    }

    public function test_cancelling_a_sale_puts_goods_back_and_never_invents_stock_for_a_service(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000);
        $shampoo = $this->goods($owner, 'Shampoo', 10, 8000);
        $saleId = $this->sell($owner, [[$braids, 1, 40000], [$shampoo, 4, 8000]])->assertCreated()->json('data.id');

        $this->api($owner, 'POST', "/api/inventory/sales/{$saleId}/cancel", ['reason' => 'Client left'])->assertOk();

        $this->assertSame(10, $this->stock($owner, $shampoo), 'the shampoo is back');
        $this->assertSame(0, $this->stock($owner, $braids), 'a service never had stock to put back');
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_batches')->where('product_id', $braids)->count()));
    }

    public function test_returning_a_service_does_not_put_stock_on_a_shelf(): void
    {
        $owner = $this->salon();
        $manager = $this->stylist($owner, 'Manager', 'manager');
        $braids = $this->service($owner, 'Braids', 40000);
        $shampoo = $this->goods($owner, 'Shampoo', 10, 8000);
        $saleId = $this->sell($owner, [[$braids, 1, 40000], [$shampoo, 2, 8000]])->assertCreated()->json('data.id');

        $returnId = $this->api($owner, 'POST', '/api/inventory/returns', [
            'sale_id' => $saleId, 'type' => 'return', 'reason' => 'Unhappy',
            'lines' => [
                ['product_id' => $braids, 'quantity' => 1, 'unit_price' => 40000],
                ['product_id' => $shampoo, 'quantity' => 2, 'unit_price' => 8000],
            ],
        ])->assertCreated()->json('data.id');
        $this->api($manager, 'POST', "/api/inventory/returns/{$returnId}/decide", ['decision' => 'approved'])->assertOk();

        $this->assertSame(10, $this->stock($owner, $shampoo), 'the goods are back on the shelf');
        $this->assertSame(0, $this->stock($owner, $braids), 'the refunded service is not');
    }

    public function test_something_already_sold_cannot_change_between_a_product_and_a_service(): void
    {
        $owner = $this->salon();
        $shampoo = $this->goods($owner, 'Shampoo', 10, 8000);
        $fresh = $this->goods($owner, 'Oil', 3, 5000);
        $this->sell($owner, [[$shampoo, 1, 8000]])->assertCreated();

        $this->api($owner, 'PUT', "/api/inventory/products/{$shampoo}", ['is_service' => true])->assertStatus(422);
        $this->assertFalse((bool) $this->rows($owner, fn () => DB::table('inventory_products')->where('id', $shampoo)->value('is_service')));

        // one that was never sold may change, and loses its (meaningless) stock
        $this->api($owner, 'PUT', "/api/inventory/products/{$fresh}", ['is_service' => true])->assertOk();
        $row = $this->rows($owner, fn () => DB::table('inventory_products')->find($fresh));
        $this->assertTrue((bool) $row->is_service);
        $this->assertSame(0, (int) $row->quantity);
    }

    public function test_sizes_of_a_service_are_services_too(): void
    {
        $owner = $this->salon();
        $id = $this->service($owner, 'Braids', 40000);

        $ids = $this->api($owner, 'POST', "/api/inventory/products/{$id}/variants", [
            'variants' => [['label' => 'Short', 'selling_price' => 30000], ['label' => 'Long', 'selling_price' => 60000]],
        ])->assertCreated()->json('data.ids');

        foreach ($ids as $variant) {
            $this->assertTrue((bool) $this->rows($owner, fn () => DB::table('inventory_products')->where('id', $variant)->value('is_service')));
        }
    }

    // ------------------------------------------------------------------ who served the client

    public function test_each_line_says_who_served_it_and_keeps_that_name(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $braids = $this->service($owner, 'Braids', 40000);

        $saleId = $this->sell($owner, [[$braids, 1, 40000, (string) $asha->id]])->assertCreated()->json('data.id');
        $asha->update(['name' => 'Asha Renamed']);

        $line = $this->api($owner, 'GET', "/api/inventory/sales/{$saleId}")->assertOk()->json('data.items.0');
        $this->assertSame((string) $asha->id, $line['staff_id']);
        $this->assertSame('Asha', $line['staff_name'], 'an old receipt is not rewritten by a later rename');
        $this->assertTrue($line['is_service']);
    }

    public function test_a_stylist_from_another_salon_is_refused(): void
    {
        $alpha = $this->salon('Alpha Salon');
        $bravo = $this->salon('Bravo Salon');
        $stranger = $this->stylist($bravo, 'Bravo Stylist');
        $braids = $this->service($alpha, 'Braids', 40000);

        // the sales endpoint answers a refused request as {"message": "<the first problem>"}
        $response = $this->sell($alpha, [[$braids, 1, 40000, (string) $stranger->id]])->assertStatus(422);
        $this->assertStringContainsString('staff_id', $response->json('message'));
        $this->assertSame(0, $this->rows($alpha, fn () => DB::table('inventory_sales')->count()));
    }

    public function test_the_staff_list_is_this_salons_active_people_only(): void
    {
        $alpha = $this->salon('Alpha Salon');
        $bravo = $this->salon('Bravo Salon');
        $asha = $this->stylist($alpha, 'Asha');
        $gone = $this->stylist($alpha, 'Gone');
        $gone->update(['is_active' => false]);
        $this->stylist($bravo, 'Bravo Stylist');

        $names = array_column($this->api($alpha, 'GET', '/api/inventory/salon/staff')->assertOk()->json('data'), 'name');

        $this->assertEqualsCanonicalizing(['Alpha Salon Owner', 'Asha'], $names);
        $this->assertContains('Asha', array_column($this->api($asha, 'GET', '/api/inventory/salon/staff')->json('data'), 'name'), 'staff see their colleagues too');
    }

    // ------------------------------------------------------------------ how each stylist did

    /** A month of work: two stylists, two clients, a walk-in, a cancelled sale, goods, and last month. */
    private function monthOfWork(User $owner, User $asha, User $bahati): array
    {
        $braids = $this->service($owner, 'Braids', 40000);
        $wash = $this->service($owner, 'Wash', 5000);
        $shampoo = $this->goods($owner, 'Shampoo', 50, 8000);
        $neema = $this->client($owner, 'Neema', '0711000001');
        $rehema = $this->client($owner, 'Rehema', '0711000002');
        $a = (string) $asha->id;
        $b = (string) $bahati->id;

        $this->at('2026-09-20 10:00:00');
        $this->sell($owner, [[$braids, 1, 40000, $a]], $neema)->assertCreated();                        // last month
        $this->at('2026-10-05 10:00:00');
        $this->sell($owner, [[$braids, 1, 40000, $a], [$wash, 1, 5000, $a]], $neema)->assertCreated();  // Asha: 2 services
        $this->sell($owner, [[$braids, 1, 40000, $b], [$shampoo, 1, 8000]], $rehema)->assertCreated();  // Bahati + goods
        $this->at('2026-10-06 10:00:00');
        $this->sell($owner, [[$wash, 1, 5000, $a]], $neema)->assertCreated();                            // Asha again, same client
        $cancelled = $this->sell($owner, [[$braids, 1, 40000, $b]], $rehema)->assertCreated()->json('data.id');
        $this->api($owner, 'POST', "/api/inventory/sales/{$cancelled}/cancel", ['reason' => 'No show'])->assertOk();
        $this->sell($owner, [[$wash, 1, 5000]])->assertCreated();                                        // walk-in, nobody named
        $this->at('2026-10-07 09:00:00');

        return compact('braids', 'wash', 'shampoo', 'neema', 'rehema');
    }

    public function test_the_stylist_report_adds_up_each_stylists_month(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $bahati = $this->stylist($owner, 'Bahati');
        $this->monthOfWork($owner, $asha, $bahati);

        $data = $this->api($owner, 'GET', '/api/inventory/salon/stylists')->assertOk()->json('data');

        $this->assertSame('2026-10-01', $data['from'], 'this month by default');
        $this->assertSame('2026-10-07', $data['to']);
        $byName = collect($data['stylists'])->keyBy(fn ($r) => $r['name'] ?? '(nobody)');

        $this->assertSame(['services' => 3, 'revenue' => 50000, 'visits' => 2, 'clients' => 1], collect($byName['Asha'])->only(['services', 'revenue', 'visits', 'clients'])->all());
        $this->assertSame(['services' => 1, 'revenue' => 40000, 'visits' => 1, 'clients' => 1], collect($byName['Bahati'])->only(['services', 'revenue', 'visits', 'clients'])->all(), 'the cancelled sale and the shampoo do not count');
        $this->assertSame(['services' => 1, 'revenue' => 5000, 'visits' => 1, 'clients' => 0], collect($byName['(nobody)'])->only(['services', 'revenue', 'visits', 'clients'])->all(), 'a walk-in with no stylist named is still shown');
        $this->assertSame('Asha', $data['stylists'][0]['name'], 'best first');
        $this->assertSame(['services' => 5, 'revenue' => 95000, 'visits' => 4], $data['totals']);
    }

    public function test_the_stylist_report_follows_the_period_asked_for(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $bahati = $this->stylist($owner, 'Bahati');
        $this->monthOfWork($owner, $asha, $bahati);

        $september = $this->api($owner, 'GET', '/api/inventory/salon/stylists?from=2026-09-01&to=2026-09-30')->assertOk()->json('data');

        $this->assertCount(1, $september['stylists']);
        $this->assertSame(['name' => 'Asha', 'services' => 1, 'revenue' => 40000], collect($september['stylists'][0])->only(['name', 'services', 'revenue'])->all());
        $this->api($owner, 'GET', '/api/inventory/salon/stylists?from=2026-10-05&to=2026-10-01')->assertStatus(422);
    }

    public function test_a_stylist_sees_only_their_own_results_and_another_salon_sees_nothing(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $bahati = $this->stylist($owner, 'Bahati');
        $this->monthOfWork($owner, $asha, $bahati);
        $other = $this->salon('Other Salon');

        $mine = $this->api($bahati, 'GET', '/api/inventory/salon/stylists')->assertOk()->json('data');
        $this->assertSame(['Bahati'], array_column($mine['stylists'], 'name'), 'Bahati never sees Asha\'s money');
        $this->assertSame(40000, $mine['totals']['revenue']);

        $this->assertSame([], $this->api($other, 'GET', '/api/inventory/salon/stylists')->assertOk()->json('data.stylists'));
    }

    // ------------------------------------------------------------------ a client's page

    public function test_a_clients_page_tells_how_they_come_and_what_they_like(): void
    {
        $owner = $this->salon();
        $braids = $this->service($owner, 'Braids', 40000, ['rebook_after_weeks' => 6]);
        $wash = $this->service($owner, 'Wash', 5000, ['rebook_after_weeks' => 2]);
        $shampoo = $this->goods($owner, 'Shampoo', 10, 8000);
        $neema = $this->client($owner, 'Neema', '0711000001');

        $this->at('2026-09-01 10:00:00');
        $this->sell($owner, [[$braids, 1, 40000]], $neema)->assertCreated();
        $this->at('2026-09-20 10:00:00');
        $this->sell($owner, [[$braids, 1, 40000], [$wash, 1, 5000]], $neema)->assertCreated();
        $this->at('2026-10-02 10:00:00');
        $this->sell($owner, [[$shampoo, 1, 8000]], $neema)->assertCreated();   // goods: not a visit
        $this->at('2026-10-03 10:00:00');

        $data = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/history")->assertOk()->json('data');

        $this->assertSame('Neema', $data['client']['name']);
        $this->assertSame(2, $data['stats']['visits'], 'the shampoo is not a visit');
        $this->assertSame(93000.0, (float) $data['stats']['total_spent'], 'braids 40,000 + braids and wash 45,000 + shampoo 8,000');
        $this->assertSame('2026-09-20', $data['stats']['last_visit_on']);
        $this->assertSame('Braids', $data['stats']['favourite_service']);
        $this->assertSame(
            ['visit_on' => '2026-09-20', 'due_on' => '2026-11-01', 'rule_weeks' => 6, 'service' => 'Braids'],
            $data['stats']['next_visit'],
            'the longest wait of that visit (braids, 6 weeks) sets the pace, not the wash'
        );
        $this->assertCount(3, $data['visits']);
        $this->assertSame('Shampoo', $data['visits'][0]['items'][0]['name'], 'newest first');
    }

    public function test_a_client_who_never_had_a_service_has_no_next_visit(): void
    {
        $owner = $this->salon();
        $shampoo = $this->goods($owner, 'Shampoo', 10, 8000);
        $client = $this->client($owner, 'Neema', '0711000001');
        $this->sell($owner, [[$shampoo, 1, 8000]], $client)->assertCreated();

        $stats = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$client}/history")->assertOk()->json('data.stats');

        $this->assertSame(0, $stats['visits']);
        $this->assertNull($stats['next_visit']);
        $this->assertNull($stats['favourite_service']);
    }

    public function test_notes_and_the_sms_choice_can_be_saved_by_whoever_serves_clients(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');
        $client = $this->client($owner, 'Neema', '0711000001');

        $this->api($asha, 'PATCH', "/api/inventory/salon/clients/{$client}", ['notes' => "  Allergic to ammonia dye \n", 'sms_opt_out' => true])->assertOk();

        $data = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$client}/history")->json('data.client');
        $this->assertSame('Allergic to ammonia dye', $data['notes']);
        $this->assertTrue($data['sms_opt_out']);

        $this->api($asha, 'PATCH', "/api/inventory/salon/clients/{$client}", ['notes' => '   '])->assertOk();
        $this->assertNull($this->api($owner, 'GET', "/api/inventory/salon/clients/{$client}/history")->json('data.client.notes'), 'empty notes are cleared');
    }

    public function test_another_salon_cannot_see_or_change_a_client(): void
    {
        $alpha = $this->salon('Alpha Salon');
        $bravo = $this->salon('Bravo Salon');
        $client = $this->client($alpha, 'Neema', '0711000001');

        $this->api($bravo, 'GET', "/api/inventory/salon/clients/{$client}/history")->assertNotFound();
        $this->api($bravo, 'PATCH', "/api/inventory/salon/clients/{$client}", ['notes' => 'hello'])->assertNotFound();
        $this->assertNull($this->rows($alpha, fn () => DB::table('inventory_customers')->where('id', $client)->value('notes')));
    }

    // ------------------------------------------------------------------ the reminder settings

    public function test_reminders_start_switched_off_and_the_owner_can_switch_them_on(): void
    {
        $owner = $this->salon();
        $asha = $this->stylist($owner, 'Asha');

        $this->assertSame(['rebook_enabled' => false, 'rebook_weeks' => 4], collect($this->api($owner, 'GET', '/api/inventory/salon/settings')->json('data'))->only(['rebook_enabled', 'rebook_weeks'])->all());

        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['rebook_enabled' => true, 'rebook_weeks' => 6])->assertOk();
        $this->assertSame(['rebook_enabled' => true, 'rebook_weeks' => 6], collect($this->api($asha, 'GET', '/api/inventory/salon/settings')->json('data'))->only(['rebook_enabled', 'rebook_weeks'])->all(), 'a stylist can read them');

        $this->api($asha, 'PUT', '/api/inventory/salon/settings', ['rebook_enabled' => false])->assertForbidden();
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['rebook_weeks' => 0])->assertStatus(422);
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['rebook_weeks' => 53])->assertStatus(422);
    }

    public function test_each_salon_has_its_own_reminder_settings(): void
    {
        $alpha = $this->salon('Alpha Salon');
        $bravo = $this->salon('Bravo Salon');

        $this->enableRebooking($alpha, 8);

        $this->assertSame(['rebook_enabled' => false, 'rebook_weeks' => 4], collect($this->api($bravo, 'GET', '/api/inventory/salon/settings')->json('data'))->only(['rebook_enabled', 'rebook_weeks'])->all());
    }

    // ------------------------------------------------------------------ who is due, and when

    /** Anna, Beth, Cora, Dina, Eve and friends: one salon with a client for every rule. */
    private function clientsForEveryRule(User $owner): array
    {
        $haircut = $this->service($owner, 'Haircut', 15000);                              // no wait of its own: the salon's 4 weeks
        $braids = $this->service($owner, 'Braids', 40000, ['rebook_after_weeks' => 6]);
        $wash = $this->service($owner, 'Wash', 5000, ['rebook_after_weeks' => 2]);
        $shampoo = $this->goods($owner, 'Shampoo', 50, 8000);
        $this->enableRebooking($owner, 4);

        $anna = $this->client($owner, 'Anna Mushi', '0711000001');
        $beth = $this->client($owner, 'Beth', '0711000002');
        $cora = $this->client($owner, 'Cora', '0711000003');
        $dina = $this->client($owner, 'Dina', '0711000004');
        $eve = $this->client($owner, 'Eve', '0711000005');
        $fey = $this->client($owner, 'Fey', '0711000006');
        $gina = $this->client($owner, 'Gina', '0711000007');
        $this->rows($owner, fn () => DB::table('inventory_customers')->where('id', $fey)->update(['phone' => '']));
        $this->rows($owner, fn () => DB::table('inventory_customers')->where('id', $gina)->update(['sms_opt_out' => true]));

        $this->at('2026-08-01 10:00:00');
        $this->sell($owner, [[$haircut, 1, 15000]], $cora)->assertCreated();                               // an older visit, replaced below
        $this->at('2026-09-01 10:00:00');
        $this->sell($owner, [[$haircut, 1, 15000]], $anna)->assertCreated();                               // due 2026-09-29
        $this->sell($owner, [[$braids, 1, 40000], [$wash, 1, 5000]], $beth)->assertCreated();              // 6 weeks wins: due 2026-10-13
        $cancelled = $this->sell($owner, [[$haircut, 1, 15000]], $dina)->assertCreated()->json('data.id');
        $this->api($owner, 'POST', "/api/inventory/sales/{$cancelled}/cancel", ['reason' => 'Changed mind'])->assertOk();
        $this->sell($owner, [[$shampoo, 1, 8000]], $eve)->assertCreated();                                 // goods: not a visit
        $this->sell($owner, [[$haircut, 1, 15000]])->assertCreated();                                      // walk-in: nobody to text
        $this->sell($owner, [[$haircut, 1, 15000]], $fey)->assertCreated();                                // no phone
        $this->sell($owner, [[$haircut, 1, 15000]], $gina)->assertCreated();                               // asked not to be texted
        $this->at('2026-09-20 10:00:00');
        $this->sell($owner, [[$braids, 1, 40000]], $cora)->assertCreated();                                // her LAST visit: due 2026-11-01

        return compact('anna', 'beth', 'cora', 'dina', 'eve', 'fey', 'gina');
    }

    private function due(User $owner, string $day, bool $includeSent = false): array
    {
        return $this->rows($owner, fn () => RebookPlanner::due(Carbon::parse($day, 'UTC'), $includeSent));
    }

    private function names(array $rows): array
    {
        $names = array_column($rows, 'name');
        sort($names);

        return $names;
    }

    public function test_nobody_is_due_before_their_wait_is_over(): void
    {
        $owner = $this->salon();
        $this->clientsForEveryRule($owner);

        $this->assertSame([], $this->due($owner, '2026-09-28'), 'Anna is due on the 29th, not the 28th');
    }

    public function test_a_client_is_due_on_the_day_the_wait_ends_with_the_weeks_that_have_passed(): void
    {
        $owner = $this->salon();
        $ids = $this->clientsForEveryRule($owner);

        $rows = $this->due($owner, '2026-09-29', includeSent: true);
        $anna = collect($rows)->firstWhere('customer_id', $ids['anna']);

        $this->assertSame(['visit_on' => '2026-09-01', 'due_on' => '2026-09-29', 'weeks_waited' => 4, 'rule_weeks' => 4, 'service' => 'Haircut'],
            collect($anna)->only(['visit_on', 'due_on', 'weeks_waited', 'rule_weeks', 'service'])->all());
        // the same day the other 4-week clients are listed too, with the reason they cannot be texted
        $this->assertSame(['no_phone', 'opted_out'], [
            collect($rows)->firstWhere('customer_id', $ids['fey'])['skip_reason'],
            collect($rows)->firstWhere('customer_id', $ids['gina'])['skip_reason'],
        ]);
        $this->assertTrue($anna['can_text']);
    }

    public function test_the_longest_wait_of_a_visit_sets_the_day_and_its_main_service_is_named(): void
    {
        $owner = $this->salon();
        $ids = $this->clientsForEveryRule($owner);

        $this->assertNotContains($ids['beth'], array_column($this->due($owner, '2026-09-29'), 'customer_id'), 'her wash would say 2 weeks, her braids 6');
        $beth = collect($this->due($owner, '2026-10-13'))->firstWhere('customer_id', $ids['beth']);

        $this->assertSame(6, $beth['rule_weeks']);
        $this->assertSame('Braids', $beth['service'], 'the service that was paid the most for');
        $this->assertSame(6, $beth['weeks_waited']);
    }

    public function test_a_missed_day_is_caught_for_two_more_weeks_and_then_left_alone(): void
    {
        $owner = $this->salon();
        $ids = $this->clientsForEveryRule($owner);

        $this->assertContains($ids['anna'], array_column($this->due($owner, '2026-10-13'), 'customer_id'), 'the last day of the grace');
        $this->assertNotContains($ids['anna'], array_column($this->due($owner, '2026-10-14'), 'customer_id'), 'no "it has been 4 weeks" six weeks late');
        $this->assertContains($ids['beth'], array_column($this->due($owner, '2026-10-27'), 'customer_id'));
        $this->assertNotContains($ids['beth'], array_column($this->due($owner, '2026-10-28'), 'customer_id'));
    }

    public function test_only_the_last_visit_counts_and_cancelled_sales_goods_and_walk_ins_never_do(): void
    {
        $owner = $this->salon();
        $ids = $this->clientsForEveryRule($owner);

        // Cora's August haircut is long past; her September braids (6 weeks) make her due on 1 November
        $everyone = array_column($this->due($owner, '2026-11-01'), 'name');
        $this->assertSame(['Cora'], $everyone);
        $this->assertNotContains('Dina', array_column($this->due($owner, '2026-09-29', true), 'name'), 'her only visit was cancelled');
        $this->assertNotContains('Eve', array_column($this->due($owner, '2026-09-29', true), 'name'), 'shampoo is not a visit');
        $this->assertSame(['Anna Mushi', 'Fey', 'Gina'], $this->names($this->due($owner, '2026-09-29', true)), 'the walk-in has no record to remind');
    }

    // ------------------------------------------------------------------ the daily job

    private function remind(array $options = [])
    {
        return $this->artisan('salon:remind-rebooking', $options);
    }

    private function remindersSent(User $owner): int
    {
        return (int) $this->rows($owner, fn () => DB::table('inventory_rebook_reminders')->count());
    }

    public function test_the_daily_job_texts_the_client_once_with_a_correct_message(): void
    {
        $owner = $this->salon('Glow Salon');
        $ids = $this->clientsForEveryRule($owner);
        $this->freshSms();
        $this->at('2026-09-29 07:00:00');

        $this->remind()->assertExitCode(0);

        $this->assertCount(1, $this->sms->sent, 'Anna only: the others have no phone, asked not to be texted, or are not due');
        $this->assertSame(
            'Habari Anna, Zimepita wiki 4 tangu ulipohudumiwa kwa Haircut katika Glow Salon. Karibu tena! / '
            . 'Hello Anna, it has been 4 weeks since your Haircut at Glow Salon. We would love to see you again!',
            $this->sms->sent[0]['message']
        );
        $this->assertSame('0711000001', $this->sms->sent[0]['to']);
        $this->assertSame(1, $this->remindersSent($owner));

        // the same morning again, and the days after: that visit is never texted twice
        $this->remind()->assertExitCode(0);
        $this->at('2026-09-30 07:00:00');
        $this->remind()->assertExitCode(0);
        $this->assertCount(1, $this->sms->sent);
        $this->assertSame(1, $this->remindersSent($owner));
    }

    public function test_two_runs_at_the_same_moment_text_a_visit_once(): void
    {
        $owner = $this->salon();
        $ids = $this->clientsForEveryRule($owner);
        $this->freshSms();
        $this->at('2026-09-29 07:00:00');

        // Another run claims Anna's visit in the instant between "who is due" being read and this run sending.
        $raced = false;
        DB::listen(function ($query) use (&$raced, $ids) {
            if (!$raced && str_starts_with(strtolower($query->sql), 'select') && str_contains($query->sql, 'inventory_rebook_reminders')) {
                $raced = true;
                DB::table('inventory_rebook_reminders')->insert([
                    'customer_id' => $ids['anna'], 'visit_on' => '2026-09-01', 'weeks' => 4,
                    'sent_at' => now(), 'created_at' => now(), 'updated_at' => now(),
                ]);
            }
        });

        $this->remind()->assertExitCode(0);

        $this->assertTrue($raced, 'the race was staged');
        $this->assertSame([], $this->sms->to('0711000001'), 'the other run owns that text: this one must not send it again');
        $this->assertSame(1, $this->remindersSent($owner));
    }

    public function test_the_owner_sees_who_was_reminded(): void
    {
        $owner = $this->salon();
        $ids = $this->clientsForEveryRule($owner);
        $this->freshSms();
        $this->at('2026-09-29 07:00:00');
        $this->remind();

        $rows = $this->api($owner, 'GET', '/api/inventory/salon/rebook/due')->assertOk()->json('data');

        $anna = collect($rows['clients'])->firstWhere('customer_id', $ids['anna']);
        $this->assertTrue($anna['sent']);
        $this->assertTrue($rows['settings']['rebook_enabled']);
        $this->assertFalse(collect($rows['clients'])->firstWhere('customer_id', $ids['fey'])['sent']);
    }

    public function test_a_late_run_still_texts_inside_the_grace_days_and_says_how_long_it_really_has_been(): void
    {
        $owner = $this->salon();
        $this->clientsForEveryRule($owner);
        $this->freshSms();

        $this->at('2026-10-10 07:00:00');   // the job did not run for 11 days: Anna was due on the 29th
        $this->remind();

        $this->assertCount(1, $this->sms->to('0711000001'));
        $this->assertStringContainsString('Zimepita wiki 5', $this->sms->to('0711000001')[0]['message'], '39 days is 5 whole weeks');
    }

    public function test_a_client_past_the_grace_days_is_left_alone_and_the_next_one_is_still_texted(): void
    {
        $owner = $this->salon();
        $this->clientsForEveryRule($owner);
        $this->freshSms();

        $this->at('2026-10-14 07:00:00');   // Anna's grace ended on the 13th; Beth's wait ended on the 13th
        $this->remind();

        $this->assertSame([], $this->sms->to('0711000001'), 'Anna is too late to be told "4 weeks"');
        $this->assertCount(1, $this->sms->to('0711000002'), 'Beth is texted');
        $this->assertCount(1, $this->sms->sent);
    }

    public function test_a_salon_that_has_not_switched_reminders_on_is_never_texted(): void
    {
        $owner = $this->salon();
        $this->clientsForEveryRule($owner);
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['rebook_enabled' => false])->assertOk();
        $this->freshSms();
        $this->at('2026-09-29 07:00:00');

        $this->remind()->assertExitCode(0);

        $this->assertSame([], $this->sms->sent);
        $this->assertSame(0, $this->remindersSent($owner));
    }

    public function test_a_dry_run_lists_what_it_would_do_and_does_nothing(): void
    {
        $owner = $this->salon('Glow Salon');
        $this->clientsForEveryRule($owner);
        $this->freshSms();
        $this->at('2026-09-29 07:00:00');

        $this->remind(['--dry-run' => true])
            ->expectsOutputToContain('would text: Glow Salon -> Anna Mushi')
            ->expectsOutputToContain('dry run: 1 reminder(s)')
            ->assertExitCode(0);

        $this->assertSame([], $this->sms->sent);
        $this->assertSame(0, $this->remindersSent($owner), 'nothing is claimed by a dry run');
    }

    public function test_a_text_that_could_not_be_sent_is_tried_again_the_next_day(): void
    {
        $owner = $this->salon();
        $this->clientsForEveryRule($owner);
        $this->freshSms()->refuseAll();
        $this->at('2026-09-29 07:00:00');

        $this->remind()->assertExitCode(0);
        $this->assertSame(0, $this->remindersSent($owner), 'a failed text gives its claim back');

        $this->freshSms();
        $this->at('2026-09-30 07:00:00');
        $this->remind();

        $this->assertCount(1, $this->sms->sent, 'the provider is back: Anna is texted, one day late');
        $this->assertSame(1, $this->remindersSent($owner));
    }

    public function test_the_text_goes_out_under_the_salons_own_sender_name(): void
    {
        $owner = $this->salon('Glow Salon');
        Business::forOwnerId($owner->id)->update(['sms_sender_id' => 'GLOWSALON', 'sms_sender_status' => 'approved']);
        $this->clientsForEveryRule($owner);
        $this->freshSms();
        $this->at('2026-09-29 07:00:00');

        $this->remind();

        $this->assertSame('GLOWSALON', $this->sms->sent[0]['sender']);
    }

    public function test_a_salon_whose_plan_has_ended_is_not_texted(): void
    {
        $owner = $this->salon();
        $this->clientsForEveryRule($owner);
        config(['billing.enforce' => true]);
        Business::forOwnerId($owner->id)->update(['plan' => 'basic', 'valid_until' => Carbon::parse('2026-07-01', 'UTC')]);
        $this->freshSms();
        $this->at('2026-09-29 07:00:00');

        $this->remind();

        $this->assertSame([], $this->sms->sent, 'the service is held back until it pays, and so is the SMS bill');
    }

    public function test_a_business_without_the_salon_service_is_never_texted(): void
    {
        $shop = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');
        $haircut = $this->service($shop, 'Haircut', 15000);
        $this->enableRebooking($shop, 4);
        $client = $this->client($shop, 'Anna', '0711000001');
        $this->at('2026-09-01 10:00:00');
        $this->sell($shop, [[$haircut, 1, 15000]], $client)->assertCreated();
        $this->freshSms();
        $this->at('2026-09-29 07:00:00');

        $this->remind();

        $this->assertSame([], $this->sms->sent);
    }

    public function test_two_salons_are_texted_separately_and_never_see_each_others_clients(): void
    {
        $alpha = $this->salon('Alpha Salon');
        $bravo = $this->salon('Bravo Salon');
        foreach ([[$alpha, 'Amina', '0711111111'], [$bravo, 'Bahati', '0722222222']] as [$owner, $name, $phone]) {
            $service = $this->service($owner, 'Braids', 40000);
            $this->enableRebooking($owner, 4);
            $client = $this->client($owner, $name, $phone);
            $this->at('2026-09-01 10:00:00');
            $this->sell($owner, [[$service, 1, 40000]], $client)->assertCreated();
        }
        $this->freshSms();
        $this->at('2026-09-29 07:00:00');

        $this->remind()->assertExitCode(0);

        $this->assertCount(2, $this->sms->sent);
        $toAmina = $this->sms->to('0711111111')[0]['message'];
        $toBahati = $this->sms->to('0722222222')[0]['message'];
        $this->assertStringContainsString('Alpha Salon', $toAmina);
        $this->assertStringNotContainsString('Bravo', $toAmina);
        $this->assertStringContainsString('Bravo Salon', $toBahati);
        $this->assertStringNotContainsString('Alpha', $toBahati);
        $this->assertSame(1, $this->remindersSent($alpha));
        $this->assertSame(1, $this->remindersSent($bravo));
        $this->assertSame(['Amina'], array_column($this->due($alpha, '2026-09-29', true), 'name'));
        $this->assertSame(['Bahati'], array_column($this->due($bravo, '2026-09-29', true), 'name'));
    }

    public function test_the_job_is_on_the_daily_schedule(): void
    {
        $this->artisan('schedule:list')->expectsOutputToContain('salon:remind-rebooking')->assertExitCode(0);
    }

    // ------------------------------------------------------------------ the words

    public function test_the_message_agrees_with_the_number_of_weeks_in_both_languages(): void
    {
        $one = RebookPlanner::message('neema', 'Braids', 1, 'Glow Salon');
        $many = RebookPlanner::message('NEEMA JUMA', 'Braids', 6, 'Glow Salon');

        $this->assertStringContainsString('Imepita wiki moja tangu ulipohudumiwa', $one);
        $this->assertStringContainsString('it has been one week since your Braids', $one);
        $this->assertStringContainsString('Zimepita wiki 6 tangu ulipohudumiwa', $many);
        $this->assertStringContainsString('it has been 6 weeks since your Braids', $many);
        $this->assertStringStartsWith('Habari Neema,', $many, 'the first name, properly capitalised');
        $this->assertStringContainsString('Hello Neema, ', $many);
        $this->assertStringContainsString(' / ', $many);
    }

    public function test_the_message_copes_with_no_name_and_very_long_names_and_stays_in_the_sms_alphabet(): void
    {
        $text = RebookPlanner::message('', str_repeat('Long service name ', 6), 4, str_repeat('Beautiful Salon ', 6));

        $this->assertStringStartsWith('Habari, Zimepita wiki 4', $text);
        $this->assertStringContainsString('Hello, it has been 4 weeks', $text);
        $this->assertStringContainsString('...', $text, 'a long name is cut, not left to run on');
        $this->assertSame($text, mb_convert_encoding($text, 'ASCII', 'UTF-8'), 'plain characters only: one 160-character segment, not 70');
        $this->assertLessThan(320, mb_strlen($text), 'at most two text messages');
    }
}
