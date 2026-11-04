<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Support\Salon\DemoSalon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The demo salon: a believable business with months of work made through the app's own endpoints, kept apart from every real business, with
 * no SMS and a way to take away exactly what it made.
 */
class SalonDemoTest extends TestCase
{
    use RefreshDatabase;

    private const PASSWORD = 'Demo-pass-2026';

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function build(int $days = 40): array
    {
        $demo = new DemoSalon($days, 2026, Carbon::parse('2026-11-04', 'Africa/Dar_es_Salaam'));
        $demo->password = self::PASSWORD;

        return $demo->build();
    }

    private function owner(): User
    {
        return User::where('email', DemoSalon::OWNER_EMAIL)->firstOrFail();
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    public function test_it_makes_a_whole_salon_with_the_people_clients_visits_spending_and_pay(): void
    {
        $s = $this->build();

        $this->assertSame('Glow Beauty Lounge', $s['business']);
        $this->assertGreaterThan(150, $s['made']['sales'], 'about ten visits a day over 40 days');
        $this->assertGreaterThan(40, $s['made']['clients']);
        $this->assertGreaterThan(10, $s['made']['expenses']);
        $this->assertGreaterThan(0, $s['made']['payouts']);
        $this->assertSame(6, $s['made']['equipment']);
        $this->assertGreaterThan(20, $s['made']['shifts'], 'the Team page has attendance');
        $this->assertGreaterThan(0, $s['made']['reviews']);
        $this->assertGreaterThan(0, $s['made']['bookings']);
        $this->assertGreaterThan(2000000, $s['revenue']);

        $owner = $this->owner();
        $this->assertSame('Glow Beauty Lounge', Business::forOwnerId($owner->id)->name);
        $roles = User::where('created_by', $owner->id)->pluck('role')->sort()->values()->all();
        $this->assertSame(['accountant', 'hair_stylist', 'hair_stylist', 'hair_stylist', 'hair_stylist', 'lash_makeup_artist', 'nail_technician'], $roles);
        foreach (User::where('created_by', $owner->id)->get() as $u) {
            $this->assertTrue($u->canUseService('salon'), $u->name);
        }
    }

    public function test_the_stylists_report_reads_like_a_real_business_best_first_with_changes_and_returning_clients(): void
    {
        $this->build(60);
        $owner = $this->owner();

        $d = $this->api($owner, 'GET', '/api/inventory/salon/stylists?from=2026-10-05&to=2026-11-04')->assertOk()->json('data');

        $this->assertCount(6, $d['stylists'], 'everyone worked');
        $this->assertSame(range(1, 6), array_column($d['stylists'], 'rank'));
        $revenues = array_column($d['stylists'], 'revenue');
        $sorted = $revenues;
        rsort($sorted);
        $this->assertSame($sorted, $revenues, 'best first');
        $this->assertGreaterThan(count($revenues) > 1 ? $revenues[array_key_last($revenues)] * 1.2 : 0, $revenues[0], 'a real spread between the best and the last');
        foreach ($d['stylists'] as $r) {
            $this->assertGreaterThan(0, $r['avg_ticket'], $r['name']);
            $this->assertNotNull($r['change']['revenue'], $r['name'] . ' has a month before to be compared with');
            $this->assertNotNull($r['return_rate'], $r['name']);
            $this->assertNotNull($r['target'], $r['name'] . ' has a target');
        }
        $rate = array_column($d['stylists'], 'return_rate');
        $this->assertGreaterThan(20, max($rate), 'some clients come back');
        $this->assertGreaterThan(1, max($rate) - min($rate), 'and the rates differ');
        $changes = array_map(fn ($r) => $r['change']['revenue'], $d['stylists']);
        $this->assertTrue(max($changes) > 0 && min($changes) < 15, 'someone is up and someone is not');
        $this->assertContains(true, array_map(fn ($r) => in_array($r['target']['pace'], ['ahead', 'reached', 'on_track', 'behind'], true), $d['stylists']));
    }

    public function test_the_books_tie_up_money_in_matches_the_sales_and_nothing_is_negative(): void
    {
        $s = $this->build(30);
        $owner = $this->owner();

        $sales = (float) DB::table('inventory_sales')->where('owner_id', (string) $owner->id)->whereNull('cancelled_at')->sum('total');
        $this->assertEqualsWithDelta($s['revenue'], $sales, 1.0, 'what was told is what was recorded');
        $this->assertSame(0, DB::table('inventory_products')->where('owner_id', (string) $owner->id)->where('quantity', '<', 0)->count(), 'stock never goes below nothing');
        $this->assertGreaterThan(0, DB::table('inventory_sale_payments')->where('owner_id', (string) $owner->id)->where('method', 'mobile_money')->count(), 'mobile money is used');
        $this->assertGreaterThan(0, DB::table('inventory_sale_payments')->where('owner_id', (string) $owner->id)->where('method', 'cash')->count());
        $this->assertGreaterThan(0, DB::table('inventory_sales')->where('owner_id', (string) $owner->id)->where('payment_status', '!=', 'paid')->count(), 'a little credit');
        $overview = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?from=2026-10-05&to=2026-11-04')->assertOk()->json('data');
        $this->assertGreaterThan(0, $overview['service_revenue'] ?? 0);
    }

    public function test_the_accountant_the_stylists_and_the_owner_can_sign_in_with_the_password_given(): void
    {
        $this->build(14);

        foreach (['demo.owner', 'demo.accountant', 'demo.asha'] as $who) {
            $res = $this->postJson('/api/auth/login', ['email' => $who . '@glowbeauty.example', 'phone_number' => $who === 'demo.owner' ? '0700000101' : ($who === 'demo.accountant' ? '0700000102' : '0700000103'), 'password' => self::PASSWORD]);
            $res->assertOk();
        }
        $this->postJson('/api/auth/login', ['email' => 'demo.owner@glowbeauty.example', 'phone_number' => '0700000101', 'password' => 'wrong'])->assertStatus(401);
    }

    public function test_no_sms_can_leave_while_it_is_made(): void
    {
        $this->build(10);

        $this->assertFalse(app(SmsGateway::class)->delivers(), 'the gateway only logs');
    }

    public function test_the_same_seed_makes_the_same_salon_and_a_second_run_without_fresh_is_refused(): void
    {
        $a = $this->build(14);
        DemoSalon::remove();
        Carbon::setTestNow();
        $b = $this->build(14);

        $this->assertSame($a['made'], $b['made']);
        $this->assertSame($a['revenue'], $b['revenue']);

        $this->expectException(\RuntimeException::class);
        $this->build(14);
    }

    public function test_removing_it_takes_away_the_demo_and_leaves_every_other_business_as_it_was(): void
    {
        // A real business, with its own client and sale.
        $real = $this->givenServices(User::factory()->create(['name' => 'Real Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711999888']), 'salon');
        $token = $real->createToken('t')->plainTextToken;
        $this->flushHeaders();
        $svc = $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json('POST', '/api/inventory/products', ['name' => 'Real braids', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 40000, 'duration_minutes' => 60])->assertCreated()->json('data.id');
        $this->app['auth']->forgetGuards();
        $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json('POST', '/api/inventory/sales', ['payment_status' => 'paid', 'subtotal' => 40000, 'discount' => 0, 'tax' => 0, 'total' => 40000, 'paid_total' => 40000, 'items' => [['product_id' => $svc, 'quantity' => 1, 'unit_price' => 40000]]])->assertCreated();
        // (Counted with no business in scope, as the demo's own removal does.)
        $count = fn (string $table) => \App\Support\Tenancy\TenantContext::withoutScope(fn () => DB::table($table)->count());
        $realSales = $count('inventory_sales');
        $this->assertSame(1, $realSales, 'the real business has its one sale');
        $realUsers = User::count();

        $this->build(14);
        $this->assertGreaterThan($realUsers, User::count());
        $gone = DemoSalon::remove();

        $this->assertGreaterThan(100, $gone);
        $this->assertSame(0, User::where('email', 'like', '%@glowbeauty.example')->count());
        $this->assertSame($realUsers, User::count(), 'only the demo people went');
        $this->assertSame($realSales, $count('inventory_sales'), 'the real sale is still there and nothing of the demo is left');
        $this->assertSame(1, $count('inventory_products'), 'the real business keeps its one service');
        $this->assertSame(0, $count('inventory_customers'));
        $this->assertSame(0, DemoSalon::remove(), 'removing it again finds nothing');
    }

    public function test_the_command_refuses_to_run_twice_and_needs_force_on_a_live_server(): void
    {
        $this->artisan('salon:demo', ['--days' => 7, '--password' => self::PASSWORD])->assertExitCode(0);
        $this->artisan('salon:demo', ['--days' => 7])->assertExitCode(1);
        $this->artisan('salon:demo', ['--days' => 7, '--fresh' => true, '--password' => self::PASSWORD])->assertExitCode(0);
        $this->artisan('salon:demo', ['--remove' => true])->assertExitCode(0);
        $this->assertSame(0, User::where('email', DemoSalon::OWNER_EMAIL)->count());

        $this->app->detectEnvironment(fn () => 'production');
        $this->artisan('salon:demo', ['--days' => 7])->assertExitCode(1);
        $this->assertSame(0, User::where('email', DemoSalon::OWNER_EMAIL)->count(), 'nothing was made without --force');
    }
}
