<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * The web app sends the due date of a sale paid later as ISO text with a time zone ("2026-11-05T08:32:34.916Z"). MariaDB (the production
 * database) refuses that for a DATE column (error 1292, a 500 for the cashier), so it is stored as the day only.
 */
class SaleDueDateTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function shop(): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => 'Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0729000001']), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => 'Due Shop']);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    private function sellOnCredit(User $owner, ?string $due): int
    {
        $product = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Soda', 'sku' => 'SODA' . ++$this->seq, 'quantity' => 50, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 600, 'selling_price' => 1000])->assertCreated()->json('data.id');
        $customer = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Neema', 'phone' => '07120001' . str_pad((string) $this->seq, 2, '0', STR_PAD_LEFT)])->assertCreated()->json('data.id');

        return $this->api($owner, 'POST', '/api/inventory/sales', array_filter([
            'customer_id' => $customer, 'payment_status' => 'debt', 'subtotal' => 2000, 'discount' => 0, 'tax' => 0, 'total' => 2000, 'paid_total' => 0,
            'due_date' => $due,
            'items' => [['product_id' => $product, 'quantity' => 2, 'unit_price' => 1000, 'unit_cost_snapshot' => 600]],
        ], fn ($v) => $v !== null))->assertCreated()->json('data.id');
    }

    private function stored(User $owner, int $saleId): array
    {
        return TenantContext::runAs($owner, fn () => TenantContext::runInService('inventory', fn () => [
            'due_date' => (string) DB::table('inventory_sales')->where('id', $saleId)->value('due_date'),
            'reminder' => (string) DB::table('inventory_reminders')->where('related_id', $saleId)->where('type', 'payment_due')->value('due_at'),
        ]));
    }

    public function test_an_iso_due_date_with_a_time_zone_is_stored_as_the_day(): void
    {
        $owner = $this->shop();

        $id = $this->sellOnCredit($owner, '2026-11-05T08:32:34.916Z');

        $stored = $this->stored($owner, $id);
        $this->assertSame('2026-11-05', substr($stored['due_date'], 0, 10));
        $this->assertStringNotContainsString('T', $stored['due_date']);
        $this->assertStringNotContainsString('Z', $stored['due_date']);
        $this->assertStringNotContainsString('Z', $stored['reminder']);
        $this->assertSame('2026-11-05', substr($stored['reminder'], 0, 10));
    }

    public function test_a_plain_day_and_no_date_at_all_still_work(): void
    {
        $owner = $this->shop();

        $plain = $this->stored($owner, $this->sellOnCredit($owner, '2026-12-01'));
        $this->assertSame('2026-12-01', substr($plain['due_date'], 0, 10));

        $none = $this->stored($owner, $this->sellOnCredit($owner, null));
        $this->assertSame(now()->addDays(7)->toDateString(), substr($none['due_date'], 0, 10), 'a week from today when none is given');
    }
}
