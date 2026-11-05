<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * The salon's money pages are each a right the owner gives or takes back: the Salon tab of Reports, the profit (and what staff are paid), payroll, the
 * cashbook, export, and who plans the schedule and days off. An accountant starts with the books, not with these.
 */
class SalonMoneyRightsTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function salon(): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => 'Neema Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0723' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => 'Glow']);

        return $owner;
    }

    private function person(User $owner, string $role, string $name): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    /** An owner, an accountant and a stylist, with a month of sales so there is a profit to hide. */
    private function scene(): array
    {
        $owner = $this->salon();
        $acc = $this->person($owner, 'accountant', 'Ivan Accountant');
        $asha = $this->person($owner, 'hair_stylist', 'Asha');
        $svc = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Braids', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 50000, 'duration_minutes' => 60])->assertCreated()->json('data.id');
        $this->api($owner, 'PUT', '/api/inventory/salon/staff-profiles/' . $asha->id, ['monthly_salary' => 200000, 'commission_percent' => 10])->assertOk();
        Carbon::setTestNow(Carbon::parse('2026-11-10 11:00:00', 'Africa/Dar_es_Salaam'));
        $this->api($owner, 'POST', '/api/inventory/sales', ['payment_status' => 'paid', 'subtotal' => 50000, 'discount' => 0, 'tax' => 0, 'total' => 50000, 'paid_total' => 50000, 'items' => [['product_id' => $svc, 'quantity' => 1, 'unit_price' => 50000, 'staff_id' => (string) $asha->id]]])->assertCreated();
        $this->api($owner, 'POST', '/api/inventory/expenses', ['category' => 'rent', 'description' => 'Rent', 'amount' => 10000, 'expense_date' => '2026-11-10'])->assertCreated();

        return [$owner, $acc, $asha];
    }

    private function give(User $owner, User $who, array $extra = [], array $minus = []): void
    {
        $on = collect($this->api($owner, 'GET', "/api/admin/users/{$who->id}/access")->assertOk()->json('data.modules'))->filter(fn ($m) => $m['on'])->pluck('key')->all();
        $this->api($owner, 'PUT', "/api/admin/users/{$who->id}/access", ['on' => array_values(array_diff(array_unique(array_merge($on, $extra)), $minus))])->assertOk();
    }

    public function test_the_accountant_starts_with_the_books_but_not_payroll_the_cashbook_the_profit_the_salon_report_or_the_schedule(): void
    {
        [, $acc] = $this->scene();
        $have = $this->api($acc, 'GET', '/api/auth/user')->json('data.user.effective_permissions');

        foreach (['inv_salon_money', 'inv_view_expenses'] as $key) {
            $this->assertContains($key, $have, $key);
        }
        foreach (['inv_salon_reports', 'inv_salon_profit', 'inv_salon_payroll', 'inv_salon_cashbook', 'inv_salon_export', 'inv_salon_schedule'] as $key) {
            $this->assertNotContains($key, $have, $key);
        }
        $this->api($acc, 'GET', '/api/inventory/salon/reports')->assertForbidden()->assertJsonPath('code', 'module_not_allowed');
        $this->api($acc, 'GET', '/api/inventory/salon/payroll?month=2026-11')->assertForbidden();
        $this->api($acc, 'GET', '/api/inventory/salon/payouts')->assertForbidden();
        $this->api($acc, 'GET', '/api/inventory/salon/cashbook')->assertForbidden();
        $this->api($acc, 'GET', '/api/inventory/salon/staff-profiles')->assertForbidden();
    }

    public function test_the_owner_has_every_one_of_them(): void
    {
        [$owner] = $this->scene();

        foreach (['reports', 'payroll?month=2026-11', 'payouts', 'cashbook', 'staff-profiles', 'profit-loss', 'days-off'] as $page) {
            $this->api($owner, 'GET', "/api/inventory/salon/{$page}")->assertOk();
        }
    }

    public function test_the_profit_and_salaries_are_hidden_without_the_profit_right_and_what_came_in_is_not(): void
    {
        [$owner, $acc] = $this->scene();
        $from = '?from=2026-11-01&to=2026-11-30';

        $mine = $this->api($acc, 'GET', "/api/inventory/salon/profit-loss{$from}")->assertOk()->json('data');
        $this->assertTrue($mine['profit_hidden']);
        foreach (['net_profit', 'gross_profit', 'commissions', 'salaries', 'goods_profit', 'services_profit', 'operating_costs', 'cost_of_goods'] as $key) {
            $this->assertArrayNotHasKey($key, $mine, "{$key} is not sent at all (a zero would read as no profit)");
        }
        $this->assertEquals(50000, $mine['revenue']);
        $this->assertEquals(10000, $mine['expenses']);
        $this->assertArrayHasKey('collected', $mine);

        $full = $this->api($owner, 'GET', "/api/inventory/salon/profit-loss{$from}")->assertOk()->json('data');
        $this->assertArrayNotHasKey('profit_hidden', $full);
        $this->assertArrayHasKey('net_profit', $full);
        $this->assertArrayHasKey('salaries', $full);
    }

    public function test_switching_the_profit_on_shows_it_and_taking_it_back_hides_it_again(): void
    {
        [$owner, $acc] = $this->scene();
        $from = '?from=2026-11-01&to=2026-11-30';

        $this->give($owner, $acc, ['inv_salon_profit']);
        $this->assertArrayHasKey('net_profit', $this->api($acc, 'GET', "/api/inventory/salon/profit-loss{$from}")->json('data'));

        $this->give($owner, $acc, [], ['inv_salon_profit']);
        $this->assertArrayNotHasKey('net_profit', $this->api($acc, 'GET', "/api/inventory/salon/profit-loss{$from}")->json('data'));
    }

    public function test_the_salon_report_tab_is_the_owners_to_give_and_without_profit_it_has_none(): void
    {
        [$owner, $acc] = $this->scene();
        $from = '?from=2026-11-01&to=2026-11-30';

        $this->give($owner, $acc, ['inv_salon_reports']);
        $d = $this->api($acc, 'GET', "/api/inventory/salon/reports{$from}")->assertOk()->json('data');

        $this->assertTrue($d['profit_hidden']);
        $this->assertArrayNotHasKey('net_profit', $d['summary']);
        $this->assertArrayNotHasKey('commissions', $d['summary']);
        $this->assertEquals(50000, $d['summary']['revenue']);
        foreach ($d['by_service'] as $row) {
            $this->assertArrayNotHasKey('profit', $row);
            $this->assertArrayNotHasKey('commission', $row);
            $this->assertArrayHasKey('revenue', $row);
        }

        $this->give($owner, $acc, ['inv_salon_profit']);
        $full = $this->api($acc, 'GET', "/api/inventory/salon/reports{$from}")->assertOk()->json('data');
        $this->assertArrayHasKey('net_profit', $full['summary']);
        $this->assertArrayHasKey('profit', $full['by_service'][0]);
    }

    public function test_payroll_and_the_cashbook_open_only_when_given_and_close_when_taken_back(): void
    {
        [$owner, $acc] = $this->scene();

        $this->give($owner, $acc, ['inv_salon_payroll', 'inv_salon_cashbook']);
        $this->api($acc, 'GET', '/api/inventory/salon/payroll?month=2026-11')->assertOk();
        $this->api($acc, 'GET', '/api/inventory/salon/cashbook')->assertOk();

        $this->give($owner, $acc, [], ['inv_salon_payroll']);
        $this->api($acc, 'GET', '/api/inventory/salon/payroll?month=2026-11')->assertForbidden();
        $this->api($acc, 'GET', '/api/inventory/salon/cashbook')->assertOk();
    }

    public function test_the_pay_is_seen_and_changed_with_the_payroll_right_and_the_days_with_the_schedule_right(): void
    {
        [$owner, $acc, $asha] = $this->scene();

        // Schedule only: sees the days and hours, but not the pay, and cannot change the pay.
        $this->give($owner, $acc, ['inv_salon_schedule']);
        $row = collect($this->api($acc, 'GET', '/api/inventory/salon/staff-profiles')->assertOk()->json('data'))->firstWhere('name', 'Asha');
        $this->assertNull($row['monthly_salary']);
        $this->assertNull($row['commission_percent']);
        $this->api($acc, 'PUT', '/api/inventory/salon/staff-profiles/' . $asha->id, ['work_days' => [1, 2, 3], 'shift_start' => '09:00', 'shift_end' => '17:00'])->assertStatus(403, 'the server also needs the settings right to change a profile');
    }

    public function test_only_whoever_holds_the_schedule_right_gives_or_takes_back_a_day_off(): void
    {
        [$owner, $acc, $asha] = $this->scene();
        $body = ['staff_id' => (string) $asha->id, 'off_on' => '2026-11-20', 'reason' => 'Family'];

        $this->api($acc, 'POST', '/api/inventory/salon/days-off', $body)->assertForbidden();
        $id = $this->api($owner, 'POST', '/api/inventory/salon/days-off', $body)->assertCreated()->json('data.id');
        $this->api($acc, 'DELETE', "/api/inventory/salon/days-off/{$id}")->assertForbidden();

        $this->give($owner, $acc, ['inv_salon_schedule']);
        $this->api($acc, 'DELETE', "/api/inventory/salon/days-off/{$id}")->assertSuccessful();
        $this->api($acc, 'POST', '/api/inventory/salon/days-off', $body)->assertCreated();
    }

    public function test_export_gives_each_person_only_the_reports_their_rights_allow(): void
    {
        [$owner, $acc] = $this->scene();
        $from = '?from=2026-11-01&to=2026-11-30&format=csv';

        // Off by default; once the owner switches export on, each report still needs its own right.
        $this->api($acc, 'GET', "/api/inventory/salon/export/sales{$from}")->assertForbidden()->assertJsonPath('code', 'module_not_allowed');
        $this->give($owner, $acc, ['inv_salon_export']);

        foreach (['sales', 'expenses', 'tax', 'stylists'] as $type) {
            $this->api($acc, 'GET', "/api/inventory/salon/export/{$type}{$from}")->assertOk();
        }
        foreach (['payroll', 'profit-loss', 'cashbook'] as $type) {
            $this->api($acc, 'GET', "/api/inventory/salon/export/{$type}{$from}")->assertForbidden();
        }

        $this->give($owner, $acc, ['inv_salon_profit']);
        $this->api($acc, 'GET', "/api/inventory/salon/export/profit-loss{$from}")->assertOk();
        $this->api($acc, 'GET', "/api/inventory/salon/export/payroll{$from}")->assertForbidden();

        $this->give($owner, $acc, [], ['inv_salon_export']);
        $this->api($acc, 'GET', "/api/inventory/salon/export/sales{$from}")->assertForbidden()->assertJsonPath('code', 'module_not_allowed');

        foreach (['sales', 'expenses', 'payroll', 'stylists', 'profit-loss', 'tax', 'cashbook'] as $type) {
            $this->api($owner, 'GET', "/api/inventory/salon/export/{$type}{$from}")->assertOk();
        }
    }

    public function test_someone_given_reports_by_hand_before_keeps_what_it_opened(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'hair_stylist', 'Asha');
        $asha->forceFill(['permissions' => ['inv_view_reports']])->save();
        $plain = $this->person($owner, 'hair_stylist', 'Plain');

        (require base_path('database/migrations/2026_11_23_000100_give_report_grants_the_new_salon_rights.php'))->up();

        foreach (['inv_salon_reports', 'inv_salon_profit', 'inv_salon_payroll', 'inv_salon_cashbook', 'inv_salon_export', 'inv_salon_schedule'] as $key) {
            $this->assertContains($key, $asha->refresh()->permissions, $key);
        }
        $this->assertEmpty($plain->refresh()->permissions ?? []);
    }

    public function test_every_new_right_is_a_named_switch_the_owner_can_see(): void
    {
        [$owner, $acc] = $this->scene();
        $state = collect($this->api($owner, 'GET', "/api/admin/users/{$acc->id}/access")->assertOk()->json('data.modules'))->keyBy('key');

        foreach (['inv_salon_reports', 'inv_salon_profit', 'inv_salon_payroll', 'inv_salon_cashbook', 'inv_salon_export', 'inv_salon_schedule'] as $key) {
            $this->assertTrue($state->has($key), $key);
            $this->assertNotSame('', $state[$key]['en']);
            $this->assertNotSame('', $state[$key]['sw']);
        }
        foreach (['inv_salon_reports', 'inv_salon_profit', 'inv_salon_payroll', 'inv_salon_cashbook', 'inv_salon_export', 'inv_salon_schedule'] as $key) {
            $this->assertFalse($state[$key]['on'], "{$key} starts off");
        }
    }
}
