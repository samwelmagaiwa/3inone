<?php

namespace Tests\Feature;

use App\Jobs\SendBusinessTextJob;
use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * The till's texts (the receipt, the thank-you for a debt paid) go through the queue: the sale answers without waiting for the SMS
 * provider, and the queue worker sends the very same text afterwards, as the same business.
 */
class QueuedBusinessTextsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    public function test_a_sale_queues_the_receipt_instead_of_waiting_for_the_sms_provider_and_the_worker_sends_it(): void
    {
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'phone_number' => '0726000001']), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => 'masai mitumba bora']);
        $cashier = $this->givenServices(User::factory()->create(['role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id]), 'inventory');
        $product = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Mchele', 'sku' => 'MCH1', 'quantity' => 10, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 1000, 'selling_price' => 2000])->assertCreated()->json('data.id');
        $customer = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Happy Juma', 'phone' => '0711000001'])->assertCreated()->json('data.id');

        Queue::fake();
        $this->api($cashier, 'POST', '/api/inventory/sales', [
            'customer_id' => $customer, 'payment_status' => 'paid', 'subtotal' => 2000, 'discount' => 0, 'tax' => 0, 'total' => 2000, 'paid_total' => 2000,
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => 2000, 'unit_cost_snapshot' => 1000]],
        ])->assertCreated();

        $this->assertCount(0, $this->sms->sent, 'the sale did not wait for the SMS provider');
        $jobs = Queue::pushed(SendBusinessTextJob::class)->filter(fn ($j) => $j->kind === SendBusinessTextJob::RECEIPT);
        $this->assertCount(1, $jobs);
        $job = $jobs->first();
        $this->assertSame((string) $cashier->id, $job->actorId, 'sent later as the same person');
        $this->assertSame('inventory', $job->service);
        $this->assertSame(1, $job->tries, 'never retried: a customer must not get the text twice');

        // The worker: no signed-in user, as in the real queue.
        $this->app['auth']->forgetGuards();
        $job->handle();

        $texts = $this->sms->to('0711000001');
        $this->assertCount(1, $texts);
        $this->assertStringContainsString('Habari Happy, umenunua Mchele kwa TSh 2,000 kwa masai mitumba bora', $texts[0]['message']);
    }

    public function test_a_debt_payment_queues_the_thank_you(): void
    {
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');
        $product = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Mchele', 'sku' => 'MCH2', 'quantity' => 10, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 1000, 'selling_price' => 2000])->assertCreated()->json('data.id');
        $customer = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Neema', 'phone' => '0711000002'])->assertCreated()->json('data.id');
        $sale = $this->api($owner, 'POST', '/api/inventory/sales', [
            'customer_id' => $customer, 'payment_status' => 'debt', 'subtotal' => 2000, 'discount' => 0, 'tax' => 0, 'total' => 2000, 'paid_total' => 0,
            'due_date' => now()->addDays(7)->toDateString(),
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => 2000, 'unit_cost_snapshot' => 1000]],
        ])->assertCreated()->json('data.id');

        $before = count($this->sms->to('0711000002')); // the sale's own receipt, sent before the queue was faked
        Queue::fake();
        $this->api($owner, 'POST', "/api/inventory/sales/{$sale}/payments", ['amount' => 1000, 'method' => 'cash'])->assertOk();
        $this->assertCount($before, $this->sms->to('0711000002'), 'the payment did not wait for the SMS provider');

        $this->assertTrue(Queue::pushed(SendBusinessTextJob::class)->contains(fn ($j) => $j->kind === SendBusinessTextJob::DEBT_THANKS && (int) $j->args[0] === (int) $customer));
    }
}
