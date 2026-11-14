<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * A customer typed at the till: saved once with the name and the number that were written, handed back whole (so the till shows them and
 * sends them with the sale), found again by number or by name, and, after a paid visit with a service, texted with the thank-you and
 * the link to say how it went.
 */
class TillCustomerTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;
    protected FakeSmsGateway $sms;

    private function salon(): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => 'Mary Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0725' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => "Mary's Beauty"]);
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    private function service(User $as): int
    {
        return (int) $this->api($as, 'POST', '/api/inventory/products', ['name' => 'Knotless', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 25000])->assertCreated()->json('data.id');
    }

    /** The sale the web till sends: the customer by id, and the phone only when the till knew it. */
    private function sell(User $as, int $service, ?int $customer, ?string $phone = null, array $extra = [])
    {
        return $this->api($as, 'POST', '/api/inventory/sales', array_filter([
            'customer_id' => $customer, 'customer_phone' => $phone, 'payment_status' => 'paid', 'subtotal' => 25000, 'discount' => 0, 'tax' => 0, 'total' => 25000, 'paid_total' => 25000,
            'payments' => [['amount' => 25000, 'method' => 'cash', 'reference' => null, 'paid_at' => now()->toIso8601String()]],
            'items' => [['product_id' => $service, 'quantity' => 1, 'unit_price' => 25000, 'unit_cost_snapshot' => 0, 'staff_id' => (string) $as->id]],
        ] + $extra, fn ($v) => $v !== null));
    }

    public function test_a_new_customer_comes_back_whole_with_the_name_and_number_that_were_typed(): void
    {
        $owner = $this->salon();

        $res = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Amina Bakari', 'phone' => '0712 345 678'])->assertCreated();

        $res->assertJsonPath('data.name', 'Amina Bakari')->assertJsonPath('data.phone', '0712 345 678')->assertJsonPath('data.existing', false);
        $row = TenantContext::runAs($owner, fn () => TenantContext::runInService('salon', fn () => DB::table('inventory_customers')->find($res->json('data.id'))));
        $this->assertSame('Amina Bakari', $row->name);
        $this->assertSame('0712 345 678', $row->phone);
    }

    public function test_the_customer_saved_at_the_till_gets_the_thank_you_text_after_a_paid_visit_even_when_the_till_sent_no_number(): void
    {
        $owner = $this->salon();
        $service = $this->service($owner);
        $id = (int) $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Amina Bakari', 'phone' => '0712345678'])->assertCreated()->json('data.id');

        // the old till sent an empty number (it never saw the saved one): the text goes to the saved number all the same
        $this->sell($owner, $service, $id, null)->assertCreated();

        $this->assertCount(1, $this->sms->sent);
        $this->assertSame('0712345678', $this->sms->sent[0]['to']);
        $this->assertStringContainsString('Asante Amina', $this->sms->sent[0]['message']);
        $this->assertStringContainsString('/f/', $this->sms->sent[0]['message']);
    }

    public function test_a_name_and_number_typed_on_the_sale_make_a_client_who_is_texted(): void
    {
        $owner = $this->salon();
        $service = $this->service($owner);

        $this->sell($owner, $service, null, '0713 111 222', ['customer_name_override' => 'Zawadi Said'])->assertCreated();

        $row = TenantContext::runAs($owner, fn () => TenantContext::runInService('salon', fn () => DB::table('inventory_customers')->where('name', 'Zawadi Said')->first()));
        $this->assertNotNull($row, 'the name typed is saved');
        $this->assertSame('0713 111 222', $row->phone);
        $this->assertCount(1, $this->sms->sent);
        $this->assertSame('0713 111 222', $this->sms->sent[0]['to']);
    }

    public function test_the_same_number_typed_again_is_the_customer_who_is_there_and_the_till_is_told_whose_card_it_is(): void
    {
        $owner = $this->salon();
        $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Amina Bakari', 'phone' => '0712345678'])->assertCreated();

        $again = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Mama Neema', 'phone' => '+255712345678'])->assertOk();

        $again->assertJsonPath('data.existing', true)->assertJsonPath('data.matched_by', 'phone')->assertJsonPath('data.name', 'Amina Bakari')->assertJsonPath('data.phone_differs', false);
    }

    public function test_the_same_name_with_another_number_keeps_the_saved_number_and_says_so(): void
    {
        $owner = $this->salon();
        $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Amina Bakari', 'phone' => '0712345678'])->assertCreated();

        $again = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'AMINA bakari', 'phone' => '0788999000'])->assertOk();

        // the card keeps its own number (a text goes there), and the answer says the number typed is not that one
        $again->assertJsonPath('data.matched_by', 'name')->assertJsonPath('data.phone', '0712345678')->assertJsonPath('data.phone_differs', true);
    }

    public function test_a_number_is_required_and_the_name_too(): void
    {
        $owner = $this->salon();

        $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Amina', 'phone' => ''])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/customers', ['name' => '', 'phone' => '0712345678'])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Amina', 'phone' => '123'])->assertStatus(422);
    }
}
