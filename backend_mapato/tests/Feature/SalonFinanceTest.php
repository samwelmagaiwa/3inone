<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Where the salon's money goes: what a stylist earns on each service (fixed, percent or her own rate, fixed when it was
 * sold), expenses that wait for the owner's approval and carry a receipt, payroll (salary + commission - paid -
 * advances), and one profit and loss that all the pages agree with. Staff revenue, commission and cash stay separate
 * figures, and only the owner and managers see anyone's pay.
 */
class SalonFinanceTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function salon(string $name = 'Glow Salon'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0723' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function person(User $owner, string $name, string $role = 'sales_officer', array $extra = []): User
    {
        return $this->givenServices(User::factory()->create(array_merge(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id], $extra)), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [], bool $salon = true)
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $request = $this->withHeader('Authorization', "Bearer {$token}");

        return ($salon ? $request->withHeader('X-Service', 'salon') : $request)->json($method, $uri, $body);
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, fn () => TenantContext::runInService('salon', $fn));
    }

    private function service(User $as, string $name, int $price, array $extra = []): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', array_merge([
            'name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price,
        ], $extra))->assertCreated()->json('data.id');
    }

    private function goods(User $as, string $name, int $qty, int $price, int $cost): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', [
            'name' => $name, 'quantity' => $qty, 'min_stock' => 1, 'status' => 'active', 'cost_price' => $cost, 'selling_price' => $price,
        ])->assertCreated()->json('data.id');
    }

    private function sell(User $as, array $lines, array $extra = [])
    {
        $subtotal = array_sum(array_map(fn (array $i) => $i[1] * $i[2], $lines));
        $total = $subtotal - ($extra['discount'] ?? 0);

        return $this->api($as, 'POST', '/api/inventory/sales', array_merge([
            'payment_status' => 'paid', 'subtotal' => $subtotal, 'discount' => 0, 'tax' => 0, 'total' => $total, 'paid_total' => $total,
            'items' => array_map(fn (array $i) => array_filter(['product_id' => $i[0], 'quantity' => $i[1], 'unit_price' => $i[2], 'staff_id' => $i[3] ?? null], fn ($v) => $v !== null), $lines),
        ], $extra));
    }

    private function at(string $when): void
    {
        Carbon::setTestNow(Carbon::parse($when, 'UTC'));
    }

    private function commissionOf(User $owner, int $saleId): ?float
    {
        $v = $this->rows($owner, fn () => DB::table('inventory_sale_items')->where('sale_id', $saleId)->value('commission_amount'));

        return $v === null ? null : (float) $v;
    }

    // ------------------------------------------------------------------ what a stylist earns on a service

    public function test_a_fixed_amount_wins_over_a_percent_and_multiplies_by_how_many(): void
    {
        $owner = $this->salon();
        $asha = (string) $this->person($owner, 'Asha')->id;
        $both = $this->service($owner, 'Both', 20000, ['commission_percent' => 50, 'commission_fixed' => 2000]);

        $id = $this->sell($owner, [[$both, 3, 20000, $asha]])->assertCreated()->json('data.id');

        $this->assertSame(6000.0, $this->commissionOf($owner, $id), '2,000 each, three times; not 50% of 60,000');
    }

    public function test_a_service_with_no_rate_uses_the_persons_own_rate_and_otherwise_none(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $bahati = $this->person($owner, 'Bahati');
        $makeup = $this->service($owner, 'Makeup', 50000);
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha->id}", ['commission_percent' => 5, 'specialization' => 'Makeup artist'])->assertOk();

        $a = $this->sell($owner, [[$makeup, 1, 50000, (string) $asha->id]])->assertCreated()->json('data.id');
        $b = $this->sell($owner, [[$makeup, 1, 50000, (string) $bahati->id]])->assertCreated()->json('data.id');
        $c = $this->sell($owner, [[$makeup, 1, 50000]])->assertCreated()->json('data.id');

        $this->assertSame(2500.0, $this->commissionOf($owner, $a), 'her own 5%');
        $this->assertNull($this->commissionOf($owner, $b), 'Bahati has no rate, the service has none');
        $this->assertNull($this->commissionOf($owner, $c), 'nobody named');
    }

    public function test_the_services_own_rate_beats_the_persons_and_changing_either_later_changes_nothing_already_earned(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $braids = $this->service($owner, 'Braids', 80000, ['commission_percent' => 10]);
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha->id}", ['commission_percent' => 30])->assertOk();
        $id = $this->sell($owner, [[$braids, 1, 80000, (string) $asha->id]])->assertCreated()->json('data.id');

        $this->api($owner, 'PUT', "/api/inventory/products/{$braids}", ['commission_percent' => 50, 'commission_fixed' => 9999])->assertOk();
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha->id}", ['commission_percent' => 40])->assertOk();

        $this->assertSame(8000.0, $this->commissionOf($owner, $id), 'the service said 10% when it was sold');
        $this->assertEquals(9999, $this->rows($owner, fn () => DB::table('inventory_products')->where('id', $braids)->value('commission_fixed')));
    }

    public function test_goods_never_earn_commission(): void
    {
        $owner = $this->salon();
        $asha = (string) $this->person($owner, 'Asha')->id;
        $oil = $this->goods($owner, 'Oil', 10, 6000, 2000);
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha}", ['commission_percent' => 20])->assertOk();

        $id = $this->sell($owner, [[$oil, 1, 6000, $asha]])->assertCreated()->json('data.id');

        $this->assertNull($this->commissionOf($owner, $id));
    }

    // ------------------------------------------------------------------ expenses

    private function expense(User $as, array $extra = [])
    {
        return $this->api($as, 'POST', '/api/inventory/expenses', array_merge([
            'category' => 'rent', 'description' => 'Frame rent', 'amount' => 300000, 'expense_date' => '2026-10-01',
        ], $extra));
    }

    public function test_the_owners_spending_is_approved_at_once_and_carries_who_supplied_and_how_it_was_paid(): void
    {
        $owner = $this->salon();

        $res = $this->expense($owner, ['supplier' => 'Mama Landlord', 'payment_method' => 'mpesa'])->assertCreated();

        $res->assertJsonPath('data.status', 'approved')->assertJsonPath('data.supplier', 'Mama Landlord')->assertJsonPath('data.payment_method', 'mpesa');
        $this->expense($owner, ['payment_method' => 'bitcoin'])->assertStatus(422);
        $this->expense($owner, ['category' => 'licences', 'description' => 'Business licence', 'amount' => 50000])->assertCreated();
    }

    public function test_spending_by_someone_else_waits_for_approval_and_is_not_a_cost_until_then(): void
    {
        $owner = $this->salon();
        $helper = $this->person($owner, 'Helper', 'sales_officer', ['permissions' => ['inv_view_expenses', 'inv_manage_expenses']]);
        $this->expense($owner)->assertCreated();                                                   // 300,000 approved
        $id = $this->expense($helper, ['category' => 'transport', 'description' => 'Taxi for supplies', 'amount' => 20000])->assertCreated()->assertJsonPath('data.status', 'pending')->json('data.id');

        $summary = fn () => $this->api($owner, 'GET', '/api/inventory/expenses/summary?from=2026-10-01&to=2026-10-31')->json('data.total_expenses');
        $this->assertEquals(300000, $summary(), 'the waiting expense is not counted');
        $this->api($helper, 'POST', "/api/inventory/expenses/{$id}/approval", ['decision' => 'approve'])->assertStatus(403);

        $this->api($owner, 'POST', "/api/inventory/expenses/{$id}/approval", ['decision' => 'approve'])->assertOk()->assertJsonPath('data.status', 'approved');
        $this->assertEquals(320000, $summary());
        $this->api($owner, 'POST', "/api/inventory/expenses/{$id}/approval", ['decision' => 'reject'])->assertStatus(422);
    }

    public function test_a_rejected_expense_never_counts_and_an_edit_by_the_helper_needs_approving_again(): void
    {
        $owner = $this->salon();
        $helper = $this->person($owner, 'Helper', 'sales_officer', ['permissions' => ['inv_view_expenses', 'inv_manage_expenses']]);
        $a = $this->expense($helper, ['amount' => 1000])->json('data.id');
        $this->api($owner, 'POST', "/api/inventory/expenses/{$a}/approval", ['decision' => 'reject'])->assertOk()->assertJsonPath('data.status', 'rejected');
        $b = $this->expense($helper, ['amount' => 2000])->json('data.id');
        $this->api($owner, 'POST', "/api/inventory/expenses/{$b}/approval", ['decision' => 'approve'])->assertOk();

        $this->api($helper, 'PUT', "/api/inventory/expenses/{$b}", ['amount' => 9000])->assertOk()->assertJsonPath('data.status', 'pending');

        $this->assertEquals(0, $this->api($owner, 'GET', '/api/inventory/expenses/summary?from=2026-10-01&to=2026-10-31')->json('data.total_expenses'));
    }

    public function test_a_receipt_photo_is_kept_privately_and_given_back_as_a_signed_link(): void
    {
        Storage::fake('local');
        $owner = $this->salon();
        $id = $this->expense($owner)->json('data.id');

        $res = $this->api($owner, 'POST', "/api/inventory/expenses/{$id}/receipt", ['photo' => $this->tinyPng()]);

        $res->assertOk();
        $url = $res->json('data.receipt_url');
        $this->assertStringContainsString('/api/files/private/salon_receipts/', (string) $url);
        $this->assertStringContainsString('signature=', (string) $url);
        $this->assertArrayNotHasKey('receipt_path', $res->json('data'), 'the stored path is never shown');
        $list = $this->api($owner, 'GET', '/api/inventory/expenses?from=2026-10-01&to=2026-10-31')->json('data');
        $this->assertNotNull($list[0]['receipt_url']);
        $this->api($owner, 'POST', "/api/inventory/expenses/{$id}/receipt", ['photo' => UploadedFile::fake()->create('virus.php', 10, 'application/x-php')])->assertStatus(422);
    }

    /** A real one-pixel PNG on disk (the test image has no GD to draw one). */
    private function tinyPng(): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'png');
        file_put_contents($path, base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

        return new UploadedFile($path, 'receipt.png', 'image/png', null, true);
    }

    public function test_the_shop_is_untouched_its_expenses_are_approved_and_counted(): void
    {
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'phone_number' => '0724000009']), 'inventory');

        $this->api($owner, 'POST', '/api/inventory/expenses', ['category' => 'rent', 'description' => 'Rent', 'amount' => 5000, 'expense_date' => '2026-10-01'], false)
            ->assertCreated()->assertJsonPath('data.status', 'approved');
        $this->assertEquals(5000, $this->api($owner, 'GET', '/api/inventory/expenses/summary?from=2026-10-01&to=2026-10-31', [], false)->json('data.total_expenses'));
    }

    // ------------------------------------------------------------------ payroll

    public function test_payroll_for_a_month_is_salary_plus_commission_less_what_was_given(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $braids = $this->service($owner, 'Braids', 80000, ['commission_percent' => 10]);
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha->id}", ['monthly_salary' => 100000])->assertOk();
        $this->at('2026-10-05 10:00:00');
        $this->sell($owner, [[$braids, 2, 80000, (string) $asha->id]])->assertCreated();                       // 16,000 commission
        $this->at('2026-09-20 10:00:00');
        $this->sell($owner, [[$braids, 1, 80000, (string) $asha->id]])->assertCreated();                       // last month's
        $this->at('2026-10-07 09:00:00');
        $this->api($owner, 'POST', '/api/inventory/salon/payouts', ['staff_id' => (string) $asha->id, 'kind' => 'advance', 'amount' => 30000, 'paid_on' => '2026-10-03'])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/salon/payouts', ['staff_id' => (string) $asha->id, 'kind' => 'commission', 'amount' => 10000, 'paid_on' => '2026-10-06', 'method' => 'mpesa'])->assertCreated();

        $row = collect($this->api($owner, 'GET', '/api/inventory/salon/payroll?month=2026-10')->assertOk()->json('data.staff'))->firstWhere('name', 'Asha');

        $this->assertSame(
            ['salary' => 100000, 'commission_earned' => 16000, 'salary_paid' => 0, 'commission_paid' => 10000, 'advances' => 30000, 'owed' => 76000],
            collect($row)->only(['salary', 'commission_earned', 'salary_paid', 'commission_paid', 'advances', 'owed'])->all(),
            '100,000 + 16,000 - 10,000 - 30,000'
        );

        $this->api($owner, 'POST', '/api/inventory/salon/payouts', ['staff_id' => (string) $asha->id, 'kind' => 'salary', 'amount' => 70000, 'paid_on' => '2026-10-31'])->assertCreated();
        $data = $this->api($owner, 'GET', '/api/inventory/salon/payroll?month=2026-10')->json('data');
        $this->assertSame(6000, collect($data['staff'])->firstWhere('name', 'Asha')['owed']);
        $this->assertSame(6000, $data['totals']['owed']);

        $sept = collect($this->api($owner, 'GET', '/api/inventory/salon/payroll?month=2026-09')->json('data.staff'))->firstWhere('name', 'Asha');
        $this->assertSame([8000, 100000], [$sept['commission_earned'], $sept['salary']], 'September has its own commission; nothing paid yet');
    }

    public function test_a_payout_is_listed_can_be_taken_back_and_names_a_real_person(): void
    {
        $owner = $this->salon();
        $asha = (string) $this->person($owner, 'Asha')->id;
        $stranger = (string) $this->person($this->salon('Other'), 'Stranger')->id;

        $id = $this->api($owner, 'POST', '/api/inventory/salon/payouts', ['staff_id' => $asha, 'kind' => 'advance', 'amount' => 5000, 'paid_on' => '2026-10-03', 'note' => 'School fees'])->assertCreated()->json('data.id');
        $this->api($owner, 'POST', '/api/inventory/salon/payouts', ['staff_id' => $stranger, 'kind' => 'advance', 'amount' => 5000])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/payouts', ['staff_id' => $asha, 'kind' => 'bonus', 'amount' => 5000])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/payouts', ['staff_id' => $asha, 'kind' => 'advance', 'amount' => 0])->assertStatus(422);

        $list = $this->api($owner, 'GET', '/api/inventory/salon/payouts?month=2026-10')->json('data');
        $this->assertCount(1, $list);
        $this->assertSame(['Asha', 'advance', 5000, '2026-10', 'School fees'], [$list[0]['staff_name'], $list[0]['kind'], $list[0]['amount'], $list[0]['period_month'], $list[0]['note']]);

        $this->api($owner, 'DELETE', "/api/inventory/salon/payouts/{$id}")->assertOk();
        $this->assertCount(0, $this->api($owner, 'GET', '/api/inventory/salon/payouts')->json('data'));
        $this->api($owner, 'DELETE', "/api/inventory/salon/payouts/{$id}")->assertStatus(404);
    }

    public function test_only_the_owner_and_managers_see_pay_and_a_salon_never_sees_anothers(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $manager = $this->person($owner, 'Mary', 'manager');
        $other = $this->salon('Other');
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha->id}", ['monthly_salary' => 100000])->assertOk();

        foreach (['/api/inventory/salon/payroll', '/api/inventory/salon/payouts', '/api/inventory/salon/staff-profiles', '/api/inventory/salon/profit-loss', '/api/inventory/salon/overview'] as $uri) {
            $this->api($asha, 'GET', $uri)->assertStatus(403);
            $this->api($manager, 'GET', $uri)->assertOk();
        }
        $this->api($asha, 'PUT', "/api/inventory/salon/staff-profiles/{$asha->id}", ['monthly_salary' => 900000])->assertStatus(403);
        $this->api($asha, 'POST', '/api/inventory/salon/payouts', ['staff_id' => (string) $asha->id, 'kind' => 'advance', 'amount' => 1000])->assertStatus(403);

        $theirs = collect($this->api($other, 'GET', '/api/inventory/salon/payroll')->json('data.staff'))->pluck('name')->all();
        $this->assertNotContains('Asha', $theirs);
        $this->assertEquals(100000, collect($this->api($owner, 'GET', '/api/inventory/salon/staff-profiles')->json('data'))->firstWhere('name', 'Asha')['monthly_salary']);
    }

    // ------------------------------------------------------------------ profit and loss

    /** A small month: discount, goods with a cost, a debt, a cancelled sale, an approved and a waiting expense, pay. */
    private function month(User $owner): array
    {
        $asha = $this->person($owner, 'Asha');
        $helper = $this->person($owner, 'Helper', 'sales_officer', ['permissions' => ['inv_view_expenses', 'inv_manage_expenses']]);
        $braids = $this->service($owner, 'Braids', 80000, ['commission_percent' => 10]);
        $wash = $this->service($owner, 'Wash', 20000, ['commission_fixed' => 2000]);
        $shampoo = $this->goods($owner, 'Shampoo', 20, 8000, 4000);
        $neema = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Neema', 'phone' => '0711000001'])->json('data.id');
        $a = (string) $asha->id;

        $this->at('2026-10-05 10:00:00');
        $this->sell($owner, [[$braids, 1, 80000, $a], [$wash, 1, 20000, $a]], ['customer_id' => $neema, 'discount' => 10000, 'discount_reason' => 'Loyal', 'payments' => [['amount' => 90000, 'method' => 'mpesa']]])->assertCreated();
        $this->at('2026-10-06 11:00:00');
        $this->sell($owner, [[$shampoo, 2, 8000]], ['payments' => [['amount' => 16000, 'method' => 'cash']]])->assertCreated();
        $this->at('2026-10-07 09:00:00');
        $this->sell($owner, [[$wash, 1, 20000, $a]], ['customer_id' => $neema, 'payment_status' => 'debt', 'paid_total' => 0])->assertCreated();
        $cancelled = $this->sell($owner, [[$braids, 1, 80000, $a]], ['payments' => [['amount' => 80000, 'method' => 'cash']]])->assertCreated()->json('data.id');
        $this->api($owner, 'POST', "/api/inventory/sales/{$cancelled}/cancel", ['reason' => 'No show'])->assertOk();
        $this->expense($owner, ['amount' => 30000, 'category' => 'rent', 'expense_date' => '2026-10-01'])->assertCreated();
        $this->expense($helper, ['amount' => 5000, 'category' => 'transport', 'expense_date' => '2026-10-02'])->assertCreated();   // waiting
        $this->api($owner, 'POST', '/api/inventory/salon/payouts', ['staff_id' => $a, 'kind' => 'salary', 'amount' => 25000, 'paid_on' => '2026-10-04'])->assertCreated();
        $this->at('2026-10-08 09:00:00');

        return compact('asha', 'neema');
    }

    public function test_profit_and_loss_adds_up(): void
    {
        $owner = $this->salon();
        $this->month($owner);

        $d = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?from=2026-10-01&to=2026-10-31')->assertOk()->json('data');

        // services: braids 72,000 + wash 18,000 (after the 10,000 discount) + the owing wash 20,000 = 110,000; goods 16,000
        $this->assertSame([110000, 16000, 126000, 10000], [$d['service_revenue'], $d['goods_revenue'], $d['revenue'], $d['discounts']]);
        $this->assertSame(8000, $d['cost_of_goods'], 'two bottles at 4,000');
        $this->assertSame(118000, $d['gross_profit']);
        $this->assertSame(30000, $d['expenses'], 'the 5,000 still waiting is not a cost');
        $this->assertSame([['category' => 'rent', 'total' => 30000, 'count' => 1]], $d['expenses_by_category']);
        $this->assertSame(12000, $d['commissions'], '8,000 on the braids, 2,000 on each of the two washes');
        $this->assertSame(25000, $d['salaries']);
        $this->assertSame(67000, $d['operating_costs']);
        $this->assertSame(51000, $d['net_profit']);
        $this->assertSame(20000, $d['outstanding'], 'the owing wash');
        $this->assertSame(['count' => 1, 'total' => 80000], $d['cancelled']);
        $this->assertSame([2, 1], [$d['sales'] - 1, $d['clients']], 'three sales counted (cancelled is not), one client (the walk-in sale sold goods only)');
    }

    public function test_collections_are_money_in_by_how_it_was_paid(): void
    {
        $owner = $this->salon();
        $this->month($owner);

        $d = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?from=2026-10-01&to=2026-10-31')->json('data');
        $byMethod = collect($d['collections'])->pluck('amount', 'method')->all();

        $this->assertSame(['mpesa' => 90000, 'cash' => 16000], $byMethod, 'the cancelled sale\'s cash is not money in');
        $this->assertSame(106000, $d['collected']);
    }

    public function test_the_period_is_respected_and_a_bad_one_refused(): void
    {
        $owner = $this->salon();
        $this->month($owner);

        $d = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?from=2026-11-01&to=2026-11-30')->json('data');
        $this->assertSame([0, 0, 0, 0], [$d['revenue'], $d['expenses'], $d['commissions'], $d['net_profit']]);
        $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?from=2026-10-09&to=2026-10-01')->assertStatus(422);
        $default = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss')->json('data');
        $this->assertSame('2026-10-01', $default['from'], 'this month by default');
    }

    public function test_the_overview_for_the_dashboard(): void
    {
        $owner = $this->salon();
        $parts = $this->month($owner);
        $wash = $this->rows($owner, fn () => DB::table('inventory_products')->where('name', 'Wash')->value('id'));
        $this->api($owner, 'POST', '/api/inventory/salon/appointments', ['client_name' => 'Today', 'starts_at' => '2026-10-08 15:00', 'services' => [['product_id' => $wash]]])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/salon/appointments', ['client_name' => 'Later', 'starts_at' => '2026-10-12 10:00', 'services' => [['product_id' => $wash]]])->assertCreated();

        $d = $this->api($owner, 'GET', '/api/inventory/salon/overview')->assertOk()->json('data');

        $this->assertSame(0, $d['periods']['today']['revenue'], 'nothing was sold on the 8th');
        $this->assertSame(126000, $d['periods']['week']['revenue']);
        $this->assertSame(126000, $d['periods']['month']['revenue']);
        $this->assertSame(126000, $d['periods']['year']['revenue']);
        $this->assertSame([30000, 51000], [$d['periods']['month']['expenses'], $d['periods']['month']['net_profit']]);
        $this->assertSame('Braids', $d['top_services'][0]['name']);
        $this->assertSame(72000, $d['top_services'][0]['revenue']);
        $this->assertSame('Asha', $d['top_staff'][0]['name']);
        $this->assertSame(110000, $d['top_staff'][0]['revenue']);
        $this->assertSame(['today' => 1, 'upcoming' => 1], $d['bookings']);
        $this->assertSame(20000, $d['month']['outstanding']);
        $this->assertSame('mpesa', $d['month']['collections'][0]['method']);
        $this->assertNotNull($parts['asha']);
    }

    public function test_one_salon_never_sees_anothers_money(): void
    {
        $glow = $this->salon('Glow');
        $this->month($glow);
        $other = $this->salon('Other');

        $d = $this->api($other, 'GET', '/api/inventory/salon/profit-loss?from=2026-10-01&to=2026-10-31')->json('data');

        $this->assertSame([0, 0, 0, 0, 0], [$d['revenue'], $d['expenses'], $d['commissions'], $d['salaries'], $d['collected']]);
        $this->assertSame([], $this->api($other, 'GET', '/api/inventory/salon/payouts')->json('data'));
    }
}
