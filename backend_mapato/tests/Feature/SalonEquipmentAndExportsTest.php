<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Equipment and its upkeep (what it cost, what is due, every repair, and the repair's cost landing in the expenses once),
 * and the books on paper and in a spreadsheet (CSV and PDF) with the VAT collected. Money is for the owner, managers and
 * accountants only.
 */
class SalonEquipmentAndExportsTest extends TestCase
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

    private function person(User $owner, string $name, string $role = 'hair_stylist'): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, fn () => TenantContext::runInService('salon', $fn));
    }

    private function at(string $when): void
    {
        Carbon::setTestNow(Carbon::parse($when, 'UTC'));
    }

    // ------------------------------------------------------------------ equipment

    private function dryer(User $as, array $extra = [])
    {
        return $this->api($as, 'POST', '/api/inventory/salon/equipment', array_merge(['name' => 'Hood dryer', 'kind' => 'dryer', 'cost' => 450000, 'bought_on' => '2026-01-10'], $extra));
    }

    public function test_equipment_is_kept_with_what_it_cost_and_when_it_is_due(): void
    {
        $owner = $this->salon();
        $this->at('2026-10-07 09:00:00');
        $this->dryer($owner, ['next_service_on' => '2026-10-10'])->assertCreated();                                        // due in 3 days
        $this->dryer($owner, ['name' => 'Old steamer', 'cost' => 200000, 'next_service_on' => '2026-10-01'])->assertCreated();   // overdue
        $this->dryer($owner, ['name' => 'Chair', 'cost' => 300000, 'next_service_on' => '2027-01-01'])->assertCreated();
        $retired = $this->dryer($owner, ['name' => 'Broken basin', 'cost' => 50000, 'status' => 'retired', 'next_service_on' => '2026-10-01'])->json('data.id');

        $d = $this->api($owner, 'GET', '/api/inventory/salon/equipment')->assertOk()->json('data');
        $by = collect($d['equipment'])->keyBy('name');

        $this->assertSame([false, true], [$by['Hood dryer']['overdue'], $by['Hood dryer']['due_soon']]);
        $this->assertSame([true, false], [$by['Old steamer']['overdue'], $by['Old steamer']['due_soon']]);
        $this->assertSame([false, false], [$by['Chair']['overdue'], $by['Chair']['due_soon']]);
        $this->assertSame([false, false], [$by['Broken basin']['overdue'], $by['Broken basin']['due_soon']], 'retired things are never due');
        $this->assertSame(['count' => 3, 'value' => 950000, 'in_repair' => 0, 'needs_attention' => 2], $d['totals'], 'what is still in use; the retired basin is not counted');
        $this->assertNotNull($retired);
    }

    public function test_the_checks_on_equipment_and_who_may_keep_it(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'Asha');
        $stock = $this->person($owner, 'Stock', 'stock_manager');
        $cashier = $this->person($owner, 'Cash', 'cashier');

        $this->dryer($owner, ['name' => 'x'])->assertStatus(422);
        $this->dryer($owner, ['cost' => -1])->assertStatus(422);
        $this->dryer($owner, ['bought_on' => '2999-01-01'])->assertStatus(422);
        $this->dryer($owner, ['status' => 'exploded'])->assertStatus(422);
        $this->dryer($owner, ['next_service_on' => 'soon'])->assertStatus(422);
        $this->dryer($asha)->assertStatus(403);
        $this->dryer($cashier)->assertStatus(403);
        $this->api($asha, 'GET', '/api/inventory/salon/equipment')->assertStatus(403);
        $this->dryer($stock)->assertCreated();
        $this->api($stock, 'GET', '/api/inventory/salon/equipment')->assertOk();
    }

    public function test_equipment_is_changed_in_part_and_can_be_put_in_repair_or_retired(): void
    {
        $owner = $this->salon();
        $id = $this->dryer($owner, ['serial' => 'SN-1', 'notes' => 'Back room'])->json('data.id');

        $this->api($owner, 'PUT', "/api/inventory/salon/equipment/{$id}", ['status' => 'repair'])->assertOk();
        $row = $this->rows($owner, fn () => DB::table('inventory_equipment')->find($id));
        $this->assertSame(['repair', 'SN-1', 'Back room', 450000.0], [$row->status, $row->serial, $row->notes, (float) $row->cost], 'only what was sent changed');
        $this->assertSame(1, $this->api($owner, 'GET', '/api/inventory/salon/equipment')->json('data.totals.in_repair'));

        $this->api($owner, 'PUT', "/api/inventory/salon/equipment/{$id}", ['serial' => ''])->assertOk();
        $this->assertNull($this->rows($owner, fn () => DB::table('inventory_equipment')->where('id', $id)->value('serial')), 'emptied');
        $this->api($owner, 'PUT', '/api/inventory/salon/equipment/999', ['status' => 'repair'])->assertStatus(404);
    }

    public function test_a_repair_goes_in_the_history_and_its_cost_in_the_expenses_once(): void
    {
        $owner = $this->salon();
        $this->at('2026-10-07 09:00:00');
        $id = $this->dryer($owner, ['status' => 'repair'])->json('data.id');

        $res = $this->api($owner, 'POST', "/api/inventory/salon/equipment/{$id}/logs", ['kind' => 'repair', 'description' => 'New heating element', 'cost' => 35000, 'next_service_on' => '2027-04-01'])->assertCreated();

        $expense = $this->rows($owner, fn () => DB::table('inventory_expenses')->find($res->json('data.expense_id')));
        $this->assertSame(['maintenance', 'Hood dryer: New heating element', 35000.0, '2026-10-07', 'approved'], [$expense->category, $expense->description, (float) $expense->amount, substr((string) $expense->expense_date, 0, 10), $expense->status]);
        $eq = $this->rows($owner, fn () => DB::table('inventory_equipment')->find($id));
        $this->assertSame(['working', '2027-04-01'], [$eq->status, substr((string) $eq->next_service_on, 0, 10)], 'working again, next service moved on');

        $logs = $this->api($owner, 'GET', "/api/inventory/salon/equipment/{$id}/logs")->json('data');
        $this->assertSame([['repair', '2026-10-07', 35000, true]], array_map(fn ($l) => [$l['kind'], $l['done_on'], $l['cost'], $l['in_expenses']], $logs));
        $list = collect($this->api($owner, 'GET', '/api/inventory/salon/equipment')->json('data.equipment'))->first();
        $this->assertSame([1, 35000], [$list['jobs'], $list['spent_on_upkeep']]);
        $this->assertEquals(35000, $this->api($owner, 'GET', '/api/inventory/expenses/summary?from=2026-10-01&to=2026-10-31')->json('data.total_expenses'));
    }

    public function test_a_free_job_or_one_that_asks_not_to_be_an_expense_adds_none(): void
    {
        $owner = $this->salon();
        $id = $this->dryer($owner)->json('data.id');

        $free = $this->api($owner, 'POST', "/api/inventory/salon/equipment/{$id}/logs", ['kind' => 'maintenance', 'description' => 'Cleaned the filter'])->assertCreated();
        $paid = $this->api($owner, 'POST', "/api/inventory/salon/equipment/{$id}/logs", ['kind' => 'repair', 'description' => 'Paid already', 'cost' => 5000, 'record_expense' => false])->assertCreated();

        $this->assertNull($free->json('data.expense_id'));
        $this->assertNull($paid->json('data.expense_id'));
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_expenses')->count()));
        $this->api($owner, 'POST', "/api/inventory/salon/equipment/{$id}/logs", ['kind' => 'cleaning', 'description' => 'x'])->assertStatus(422);
        $this->api($owner, 'POST', "/api/inventory/salon/equipment/{$id}/logs", ['kind' => 'repair', 'description' => 'ab'])->assertStatus(422);
        $this->api($owner, 'POST', "/api/inventory/salon/equipment/{$id}/logs", ['kind' => 'repair', 'description' => 'Future', 'done_on' => '2999-01-01'])->assertStatus(422);
    }

    public function test_equipment_with_a_history_is_retired_not_deleted_and_each_salon_has_its_own(): void
    {
        $owner = $this->salon();
        $other = $this->salon('Other');
        $used = $this->dryer($owner)->json('data.id');
        $fresh = $this->dryer($owner, ['name' => 'Spare'])->json('data.id');
        $this->api($owner, 'POST', "/api/inventory/salon/equipment/{$used}/logs", ['kind' => 'maintenance', 'description' => 'Serviced'])->assertCreated();

        $this->api($owner, 'DELETE', "/api/inventory/salon/equipment/{$used}")->assertStatus(422);
        $this->api($owner, 'DELETE', "/api/inventory/salon/equipment/{$fresh}")->assertOk();
        $this->api($owner, 'DELETE', "/api/inventory/salon/equipment/{$fresh}")->assertStatus(404);

        $this->assertSame([], $this->api($other, 'GET', '/api/inventory/salon/equipment')->json('data.equipment'));
        $this->api($other, 'GET', "/api/inventory/salon/equipment/{$used}/logs")->assertStatus(404);
        $this->api($other, 'POST', "/api/inventory/salon/equipment/{$used}/logs", ['kind' => 'repair', 'description' => 'Not mine'])->assertStatus(404);
    }

    // ------------------------------------------------------------------ the books on paper

    /** A month: braids and wash with a 10% VAT product, a discount, an expense and a payout. */
    private function month(User $owner): array
    {
        $asha = $this->person($owner, 'Asha');
        $braids = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Braids', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 55000, 'commission_percent' => 10, 'tax_percent' => 10])->json('data.id');
        $neema = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => '=cmd|calc', 'phone' => '0711000001'])->json('data.id');
        $this->at('2026-10-05 10:00:00');
        $this->api($owner, 'POST', '/api/inventory/sales', [
            'customer_id' => $neema, 'payment_status' => 'paid', 'subtotal' => 55000, 'discount' => 5000, 'discount_reason' => 'Loyal', 'tax' => 0, 'total' => 50000, 'paid_total' => 50000,
            'items' => [['product_id' => $braids, 'quantity' => 1, 'unit_price' => 55000, 'staff_id' => (string) $asha->id]], 'payments' => [['amount' => 50000, 'method' => 'mpesa']],
        ])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/expenses', ['category' => 'rent', 'description' => 'Frame rent', 'amount' => 30000, 'expense_date' => '2026-10-01', 'supplier' => 'Mama Landlord'])->assertCreated();
        $this->api($owner, 'PUT', "/api/inventory/salon/staff-profiles/{$asha->id}", ['monthly_salary' => 100000])->assertOk();
        $this->at('2026-10-08 09:00:00');

        return compact('asha');
    }

    public function test_the_sales_report_is_a_csv_excel_opens_with_the_right_columns_and_a_total(): void
    {
        $owner = $this->salon();
        $this->month($owner);

        $res = $this->api($owner, 'GET', '/api/inventory/salon/export/sales?from=2026-10-01&to=2026-10-31&format=csv')->assertOk();

        $this->assertStringContainsString('text/csv', (string) $res->headers->get('Content-Type'));
        $this->assertStringContainsString('attachment; filename="salon-sales-20261001-20261031.csv"', (string) $res->headers->get('Content-Disposition'));
        $body = $res->getContent();
        $this->assertStringStartsWith("\xEF\xBB\xBF", $body, 'so Excel reads the letters right');
        $lines = array_map('str_getcsv', array_values(array_filter(explode("\n", substr($body, 3)))));
        $this->assertSame(['Sales', '01/10/2026 - 31/10/2026'], $lines[0]);
        $this->assertSame('Date', $lines[1][0]);
        $this->assertSame(['2026-10-05 10:00'], [$lines[2][0]]);
        $this->assertSame(['Braids', 'Asha', '55000', '5000', 'Loyal', '50000', '50000', 'paid', 'mpesa'], [$lines[2][3], $lines[2][4], $lines[2][5], $lines[2][6], $lines[2][7], $lines[2][8], $lines[2][9], $lines[2][10], $lines[2][11]]);
        $this->assertSame(['Total', '55000', '5000', '50000'], [$lines[3][0], $lines[3][5], $lines[3][6], $lines[3][8]]);
    }

    public function test_a_name_that_looks_like_a_formula_cannot_run_inside_excel(): void
    {
        $owner = $this->salon();
        $this->month($owner);

        $body = $this->api($owner, 'GET', '/api/inventory/salon/export/sales?from=2026-10-01&to=2026-10-31')->getContent();

        $this->assertStringContainsString("'=cmd|calc", $body);
        $this->assertStringNotContainsString(',=cmd|calc', $body);
    }

    public function test_every_report_comes_in_english_and_swahili_and_as_csv_and_pdf(): void
    {
        $owner = $this->salon();
        $this->month($owner);

        foreach (['sales', 'expenses', 'payroll', 'stylists', 'profit-loss', 'tax'] as $type) {
            $csv = $this->api($owner, 'GET', "/api/inventory/salon/export/{$type}?from=2026-10-01&to=2026-10-31&month=2026-10&format=csv")->assertOk();
            $this->assertStringContainsString('text/csv', (string) $csv->headers->get('Content-Type'), $type);
            $pdf = $this->api($owner, 'GET', "/api/inventory/salon/export/{$type}?from=2026-10-01&to=2026-10-31&month=2026-10&format=pdf&lang=sw")->assertOk();
            $this->assertSame('application/pdf', $pdf->headers->get('Content-Type'), $type);
            $this->assertStringStartsWith('%PDF', $pdf->getContent(), $type);
        }
        $sw = $this->api($owner, 'GET', '/api/inventory/salon/export/expenses?from=2026-10-01&to=2026-10-31&lang=sw')->getContent();
        $this->assertStringContainsString('Matumizi', $sw);
        $this->assertStringContainsString('Muuzaji', $sw);
        $this->assertStringContainsString('Mama Landlord', $sw);
    }

    public function test_payroll_stylists_and_profit_loss_reports_say_what_the_pages_say(): void
    {
        $owner = $this->salon();
        $this->month($owner);
        $csv = fn (string $t) => array_map('str_getcsv', array_values(array_filter(explode("\n", substr($this->api($owner, 'GET', "/api/inventory/salon/export/{$t}?from=2026-10-01&to=2026-10-31&month=2026-10")->getContent(), 3)))));

        $payroll = $csv('payroll');
        $this->assertSame(['Asha', '100000', '5500', '0', '0', '0', '105500'], array_slice($payroll[2], 0, 7), '10% commission on the 55,000 service');
        $stylists = $csv('stylists');
        $this->assertSame(['Asha', '1', '50000', '5000', '5500'], array_slice($stylists[2], 0, 5), 'net of the 5,000 discount');
        $pl = collect($csv('profit-loss'))->mapWithKeys(fn ($r) => [$r[0] => $r[1] ?? null]);
        $this->assertSame('50000', $pl['Service revenue']);
        $this->assertSame('-30000', $pl['rent']);
        $this->assertSame('-5500', $pl['Stylists commission']);
        $this->assertSame('14500', $pl['Net profit'], '50,000 - 30,000 rent - 5,500 commission');
    }

    public function test_the_vat_collected_is_summed_by_rate(): void
    {
        $owner = $this->salon();
        $this->month($owner);

        $d = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?from=2026-10-01&to=2026-10-31')->json('data');

        // 55,000 sold with 10% inside the price: 5,000 of VAT and 50,000 before it
        $this->assertSame(['rate' => 10, 'taxable' => 50000, 'vat' => 5000], $d['vat']['by_rate'][0]);
        $this->assertSame(5000, $d['vat']['total']);
        $csv = array_map('str_getcsv', array_values(array_filter(explode("\n", substr($this->api($owner, 'GET', '/api/inventory/salon/export/tax?from=2026-10-01&to=2026-10-31')->getContent(), 3)))));
        $this->assertSame(['10%', '50000', '5000'], $csv[2]);
        $this->assertSame(['Total', '50000', '5000'], $csv[3]);
    }

    public function test_only_the_owner_managers_and_accountants_may_download_and_a_wrong_request_is_refused(): void
    {
        $owner = $this->salon();
        $this->month($owner);
        $accountant = $this->person($owner, 'Acc', 'accountant');
        $manager = $this->person($owner, 'Mary', 'manager');

        foreach (['hair_stylist', 'cashier', 'receptionist', 'stock_manager'] as $role) {
            $this->api($this->person($owner, ucfirst($role), $role), 'GET', '/api/inventory/salon/export/sales')->assertStatus(403);
        }
        $this->api($accountant, 'GET', '/api/inventory/salon/export/sales')->assertOk();
        $this->api($manager, 'GET', '/api/inventory/salon/export/sales')->assertOk();
        $this->api($owner, 'GET', '/api/inventory/salon/export/secrets')->assertStatus(404);
        $this->api($owner, 'GET', '/api/inventory/salon/export/sales?format=docx')->assertStatus(422);
        $this->api($owner, 'GET', '/api/inventory/salon/export/sales?from=2026-10-09&to=2026-10-01')->assertStatus(422);
        $this->api($owner, 'GET', '/api/inventory/salon/export/payroll?month=2026-13')->assertStatus(422);
    }

    public function test_one_salons_reports_never_hold_another_salons_figures(): void
    {
        $glow = $this->salon('Glow');
        $this->month($glow);
        $other = $this->salon('Other');

        $sales = $this->api($other, 'GET', '/api/inventory/salon/export/sales?from=2026-10-01&to=2026-10-31')->getContent();
        $this->assertStringNotContainsString('Braids', $sales);
        $this->assertStringNotContainsString('Asha', $sales);
        $this->assertStringNotContainsString('Mama Landlord', $this->api($other, 'GET', '/api/inventory/salon/export/expenses?from=2026-10-01&to=2026-10-31')->getContent());
    }
}
