<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The owner's list of payment reference numbers (mobile money and bank codes), oldest first, with the time paid, the amount
 * and the sale each belongs to. Cash and payments with no code are not in it; another business's are never in it.
 */
class PaymentReferencesTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function shop(string $name = 'Mama Shop'): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0727' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function officer(User $owner): User
    {
        return $this->givenServices(User::factory()->create(['name' => 'Officer', 'role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id, 'phone_number' => '0728' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    private function product(User $as): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => 'Soda ' . ++$this->seq, 'sku' => 'SO' . $this->seq, 'quantity' => 500, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 600, 'selling_price' => 1000])->assertCreated()->json('data.id');
    }

    /** One paid sale of $total, the whole of it paid by $method with $reference, at $paidAt. */
    private function sale(User $as, int $product, string $method, ?string $reference, string $paidAt, int $total = 1000, ?string $customerName = null): int
    {
        $body = [
            'payment_status' => 'paid', 'subtotal' => $total, 'discount' => 0, 'tax' => 0, 'total' => $total, 'paid_total' => $total,
            'items' => [['product_id' => $product, 'quantity' => (int) ($total / 1000), 'unit_price' => 1000, 'unit_cost_snapshot' => 600]],
            'payments' => [['amount' => $total, 'method' => $method, 'reference' => $reference, 'paid_at' => $paidAt]],
        ];
        if ($customerName !== null) {
            $body['customer_name_override'] = $customerName;
        }

        return $this->api($as, 'POST', '/api/inventory/sales', $body)->assertCreated()->json('data.id');
    }

    public function test_lists_the_references_oldest_first_without_cash_or_codeless_payments(): void
    {
        $owner = $this->shop();
        $p = $this->product($owner);
        $late = $this->sale($owner, $p, 'mpesa', 'LATE9', '2026-10-05 15:00:00', 2000);
        $early = $this->sale($owner, $p, 'airtel_money', 'EARLY1', '2026-10-02 09:30:00', 1000, 'Neema');
        $this->sale($owner, $p, 'cash', null, '2026-10-03 10:00:00');
        $this->sale($owner, $p, 'mpesa', '', '2026-10-04 10:00:00');
        $this->sale($owner, $p, 'bank_transfer', 'BANK7', '2026-10-04 12:00:00', 3000);

        $r = $this->api($owner, 'GET', '/api/inventory/payment-references')->assertOk();

        $this->assertSame(['EARLY1', 'BANK7', 'LATE9'], array_column($r->json('data'), 'reference'));
        $first = $r->json('data.0');
        $this->assertSame($early, $first['sale_id']);
        $this->assertSame('airtel_money', $first['channel']);
        $this->assertSame(1000.0, (float) $first['amount']);
        $this->assertSame('Neema', $first['customer_name']);
        $this->assertStringStartsWith('2026-10-02 09:30', $first['paid_at']);
        $this->assertSame($late, $r->json('data.2.sale_id'));
        $this->assertEquals(['count' => 3, 'amount' => 6000], $r->json('summary'));
    }

    public function test_can_be_narrowed_by_dates_channel_and_a_search(): void
    {
        $owner = $this->shop();
        $p = $this->product($owner);
        $this->sale($owner, $p, 'mpesa', 'AAA111', '2026-10-01 10:00:00');
        $this->sale($owner, $p, 'mpesa', 'BBB222', '2026-10-10 10:00:00');
        $this->sale($owner, $p, 'halopesa', 'CCC333', '2026-10-10 11:00:00', 1000, 'Rehema');

        $refs = fn (array $q) => array_column($this->api($owner, 'GET', '/api/inventory/payment-references?' . http_build_query($q))->assertOk()->json('data'), 'reference');

        $this->assertSame(['BBB222', 'CCC333'], $refs(['from' => '2026-10-05', 'to' => '2026-10-10']));
        $this->assertSame(['AAA111', 'BBB222'], $refs(['channel' => 'mpesa']));
        $this->assertSame(['CCC333'], $refs(['q' => 'rehema']));
        $this->assertSame(['BBB222'], $refs(['q' => 'bbb']));
        $this->assertSame([], $refs(['q' => 'nothing-like-this']));
    }

    public function test_marks_a_payment_whose_sale_was_cancelled(): void
    {
        $owner = $this->shop();
        $p = $this->product($owner);
        $id = $this->sale($owner, $p, 'mpesa', 'GONE1', '2026-10-02 10:00:00');
        $this->api($owner, 'POST', "/api/inventory/sales/{$id}/cancel", ['reason' => 'Wrong goods'])->assertOk();

        $row = $this->api($owner, 'GET', '/api/inventory/payment-references')->assertOk()->json('data.0');
        $this->assertTrue($row['cancelled']);
    }

    public function test_the_sale_behind_a_reference_can_be_opened_in_full(): void
    {
        $owner = $this->shop();
        $p = $this->product($owner);
        $id = $this->sale($owner, $p, 'mpesa', 'FULL42', '2026-10-02 10:00:00', 2000);

        $row = $this->api($owner, 'GET', '/api/inventory/payment-references')->assertOk()->json('data.0');
        $sale = $this->api($owner, 'GET', "/api/inventory/sales/{$row['sale_id']}")->assertOk()->json('data');

        $this->assertSame($id, (int) $sale['id']);
        $this->assertCount(1, $sale['items']);
        $this->assertSame('FULL42', $sale['payments'][0]['reference']);
    }

    public function test_only_people_who_may_see_reports_get_the_list(): void
    {
        $owner = $this->shop();
        $officer = $this->officer($owner);

        $this->api($officer, 'GET', '/api/inventory/payment-references')->assertForbidden();
    }

    public function test_another_business_never_sees_these_references(): void
    {
        $mine = $this->shop('Mine');
        $theirs = $this->shop('Theirs');
        $this->sale($theirs, $this->product($theirs), 'mpesa', 'THEIRS1', '2026-10-02 10:00:00');
        $this->sale($mine, $this->product($mine), 'mpesa', 'MINE1', '2026-10-02 11:00:00');

        $this->assertSame(['MINE1'], array_column($this->api($mine, 'GET', '/api/inventory/payment-references')->assertOk()->json('data'), 'reference'));
        // the totals only count my own
        $this->assertSame(1, $this->api($theirs, 'GET', '/api/inventory/payment-references')->json('summary.count'));
        $this->assertSame(['THEIRS1'], array_column($this->api($theirs, 'GET', '/api/inventory/payment-references')->json('data'), 'reference'));
    }

    public function test_pages_of_the_list_keep_the_order(): void
    {
        $owner = $this->shop();
        $p = $this->product($owner);
        foreach ([1, 2, 3] as $i) {
            $this->sale($owner, $p, 'mpesa', "REF{$i}", "2026-10-0{$i} 10:00:00");
        }

        $second = $this->api($owner, 'GET', '/api/inventory/payment-references?per_page=2&page=2')->assertOk();

        $this->assertSame(['REF3'], array_column($second->json('data'), 'reference'));
        $this->assertSame(2, $second->json('meta.last_page'));
        $this->assertSame(3, $second->json('summary.count'));
    }
}
