<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * "Snooze a day" on a payment reminder: it is put away for a day (the list says it is snoozed and until when), it comes back as open when
 * the day is over, and marking it done still works.
 */
class ReminderSnoozeTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;
    private int $reminder;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow(Carbon::parse('2026-11-03 10:00:00', 'UTC'));
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726000001']), 'inventory');
        Business::forOwnerId($this->owner->id)->update(['name' => 'Mama Shop']);
        $rice = $this->api('POST', '/api/inventory/products', ['name' => 'Rice', 'sku' => 'RICE1', 'quantity' => 100, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 600, 'selling_price' => 1000])->assertCreated()->json('data.id');
        $customer = $this->api('POST', '/api/inventory/customers', ['name' => 'Mama Mary', 'phone' => '0711000777'])->assertCreated()->json('data.id');
        $this->api('POST', '/api/inventory/sales', [
            'customer_id' => $customer, 'payment_status' => 'debt', 'subtotal' => 5000, 'discount' => 0, 'tax' => 0, 'total' => 5000, 'paid_total' => 0,
            'due_date' => now()->addDays(7)->toDateString(),
            'items' => [['product_id' => $rice, 'quantity' => 5, 'unit_price' => 1000, 'unit_cost_snapshot' => 600]],
        ])->assertCreated();
        $this->reminder = (int) $this->rows(fn () => DB::table('inventory_reminders')->where('type', 'payment_due')->value('id'));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function api(string $method, string $uri, array $body = [])
    {
        $token = $this->owner->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    private function rows(callable $fn)
    {
        return TenantContext::runAs($this->owner, fn () => TenantContext::runInService('inventory', $fn));
    }

    private function listed(): array
    {
        return collect($this->api('GET', '/api/inventory/reminders')->assertOk()->json('data'))->keyBy('id')->all();
    }

    public function test_a_credit_sale_makes_an_open_payment_reminder(): void
    {
        $this->assertGreaterThan(0, $this->reminder);
        $this->assertSame('open', $this->listed()[$this->reminder]['status']);
    }

    public function test_snoozing_for_a_day_puts_it_away_until_tomorrow(): void
    {
        $this->api('PUT', "/api/inventory/reminders/{$this->reminder}/snooze", ['minutes' => 1440])->assertOk();

        $row = $this->listed()[$this->reminder];
        $this->assertSame('snoozed', $row['status']);
        $this->assertSame('2026-11-04 10:00:00', Carbon::parse($row['snooze_until'])->format('Y-m-d H:i:s'));
    }

    public function test_when_the_day_is_over_it_comes_back_as_open(): void
    {
        $this->api('PUT', "/api/inventory/reminders/{$this->reminder}/snooze", ['minutes' => 1440])->assertOk();
        $this->assertSame('snoozed', $this->listed()[$this->reminder]['status']);

        Carbon::setTestNow(Carbon::parse('2026-11-04 10:01:00', 'UTC'));

        $row = $this->listed()[$this->reminder];
        $this->assertSame('open', $row['status'], 'the snooze is over, so it asks again');
        $this->assertNull($row['snooze_until']);
    }

    public function test_it_stays_snoozed_until_the_time_is_reached(): void
    {
        $this->api('PUT', "/api/inventory/reminders/{$this->reminder}/snooze", ['minutes' => 1440])->assertOk();

        Carbon::setTestNow(Carbon::parse('2026-11-04 09:59:00', 'UTC'));

        $this->assertSame('snoozed', $this->listed()[$this->reminder]['status']);
    }

    public function test_a_snoozed_reminder_can_be_marked_done_and_a_done_one_never_comes_back(): void
    {
        $this->api('PUT', "/api/inventory/reminders/{$this->reminder}/snooze", ['minutes' => 1440])->assertOk();
        $this->api('PUT', "/api/inventory/reminders/{$this->reminder}/done")->assertOk();
        $this->assertSame('done', $this->listed()[$this->reminder]['status']);

        Carbon::setTestNow(Carbon::parse('2026-11-10 10:00:00', 'UTC'));

        $this->assertSame('done', $this->listed()[$this->reminder]['status']);
    }

    public function test_a_bad_snooze_is_refused_and_an_unknown_reminder_is_not_found(): void
    {
        $this->api('PUT', "/api/inventory/reminders/{$this->reminder}/snooze", ['minutes' => 0])->assertStatus(422);
        $this->api('PUT', '/api/inventory/reminders/999999/snooze', ['minutes' => 60])->assertStatus(404);
    }
}
