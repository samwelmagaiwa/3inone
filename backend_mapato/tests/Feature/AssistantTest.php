<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/** The AI assistant answers only from what the signed-in person may see, only about this business, and never gives a phone number to the AI. */
class AssistantTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function shop(string $name = 'Mama Shop'): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function officer(User $owner): User
    {
        return $this->givenServices(User::factory()->create(['name' => 'Officer Ali', 'role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id]), 'inventory');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    private function customer(User $as, string $name, string $phone): int
    {
        return $this->api($as, 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertCreated()->json('data.id');
    }

    private function sell(User $as, int $product, ?int $customer, int $total, string $status = 'paid'): void
    {
        $this->api($as, 'POST', '/api/inventory/sales', array_filter([
            'customer_id' => $customer, 'payment_status' => $status, 'subtotal' => $total, 'discount' => 0, 'tax' => 0, 'total' => $total,
            'paid_total' => $status === 'paid' ? $total : 0, 'due_date' => $status === 'paid' ? null : now()->addDays(7)->toDateString(),
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => $total, 'unit_cost_snapshot' => 100]],
        ], fn ($v) => $v !== null))->assertCreated();
    }

    private function product(User $as, string $name): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'sku' => strtoupper(substr($name, 0, 3)) . ++$this->seq, 'quantity' => 50, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 100, 'selling_price' => 500])->assertCreated()->json('data.id');
    }

    /** A fake Gemini that first asks for one tool, then answers in words. */
    private function geminiCalls(string $tool, array $args, string $final = 'Done.'): void
    {
        config(['services.gemini.key' => 'g-test', 'services.gemini.model' => 'gemini-test']);
        Http::fake(['generativelanguage.googleapis.com/*' => Http::sequence()
            ->push(['candidates' => [['content' => ['role' => 'model', 'parts' => [['functionCall' => ['name' => $tool, 'args' => $args]]]]]]], 200)
            ->push(['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => $final]]]]]], 200)]);
    }

    /** @return array<int, array<string, mixed>> the JSON bodies sent to Gemini, in order */
    private function sent(): array
    {
        return Http::recorded()->map(fn ($pair) => $pair[0]->data())->values()->all();
    }

    public function test_when_the_server_has_no_key_the_assistant_says_it_is_off(): void
    {
        config(['services.gemini.key' => '']);
        Http::fake();
        $owner = $this->shop();

        $this->api($owner, 'GET', '/api/inventory/assistant')->assertOk()->assertJsonPath('data.available', false);
        $this->api($owner, 'POST', '/api/inventory/assistant', ['question' => 'Who owes me?'])->assertStatus(503)->assertJsonPath('code', 'assistant_off');
        Http::assertNothingSent();
    }

    public function test_the_owner_asks_about_a_customer_the_name_is_shown_and_the_phone_never_reaches_the_ai(): void
    {
        $owner = $this->shop();
        $neema = $this->customer($owner, 'Mama Neema Joseph', '0711000001');
        $this->sell($owner, $this->product($owner, 'Soda'), $neema, 90000, 'debt');
        $this->geminiCalls('find_customer', ['name' => 'Neema'], 'Mama Neema Joseph owes TSh 90,000.');

        $r = $this->api($owner, 'POST', '/api/inventory/assistant', ['question' => 'Tell me about Neema', 'lang' => 'en'])->assertOk();

        $this->assertSame('Mama Neema Joseph owes TSh 90,000.', $r->json('data.answer'));
        $card = $r->json('data.cards.0.rows.0');
        $this->assertSame(['Mama Neema Joseph', '0711000001'], [$card['title'], $card['value']], 'the app card shows the full name and phone from the record');
        $this->assertStringContainsString('owes TSh 90,000', $card['note']);

        Http::assertSentCount(2);
        $bodies = $this->sent();
        $this->assertStringContainsString('find_customer', json_encode($bodies[0]['tools']));
        $this->assertStringContainsString('business_report', json_encode($bodies[0]['tools']), 'the owner holds every right, so every tool is offered');
        $second = json_encode($bodies[1]['contents']);
        $this->assertStringContainsString('Mama Neema Joseph', $second);
        $this->assertStringNotContainsString('0711000001', $second);
        $this->assertStringContainsString('ONLY about this business', $bodies[0]['systemInstruction']['parts'][0]['text']);
        Http::assertSent(fn ($req) => $req->hasHeader('x-goog-api-key', 'g-test') && !str_contains($req->url(), 'g-test'));
    }

    public function test_a_sales_officer_is_offered_only_the_tools_their_rights_open_and_cannot_read_the_rest(): void
    {
        $owner = $this->shop();
        $officer = $this->officer($owner);
        $p = $this->product($owner, 'Soda');
        $this->sell($owner, $p, $this->customer($owner, 'Mama Neema', '0711000001'), 90000, 'debt');
        $this->geminiCalls('business_report', ['month' => now()->format('Y-m')]);

        $topics = $this->api($officer, 'GET', '/api/inventory/assistant')->assertOk()->json('data.topics');
        $this->assertNotContains('business_report', $topics);
        $this->assertNotContains('expenses_summary', $topics);
        $this->assertContains('customers_who_owe', $topics, 'the officer role holds inv_view_credit, the right that opens the debtors screen');
        $this->assertContains('recent_sales', $topics);

        // Even if the model asks for a tool it was never offered, the person's rights decide: nothing is read.
        $this->api($officer, 'POST', '/api/inventory/assistant', ['question' => 'Show the profit'])->assertOk();
        $bodies = $this->sent();
        $this->assertStringNotContainsString('business_report', json_encode($bodies[0]['tools']));
        $second = json_encode($bodies[1]['contents']);
        $this->assertStringContainsString('Not allowed', $second);
        $this->assertStringNotContainsString('net_profit', $second);
        $this->assertStringNotContainsString('Mama Neema', $second);
    }

    public function test_a_sales_officer_sees_only_their_own_sales_but_the_owner_sees_everyones(): void
    {
        $owner = $this->shop();
        $officer = $this->officer($owner);
        $p = $this->product($owner, 'Soda');
        $this->sell($owner, $p, $this->customer($owner, 'Owner Customer', '0711000001'), 1000);
        $this->sell($officer, $p, $this->customer($owner, 'Officer Customer', '0711000002'), 2000);

        $this->geminiCalls('recent_sales', ['days' => 7]);
        $this->api($officer, 'POST', '/api/inventory/assistant', ['question' => 'My sales'])->assertOk();
        $second = json_encode($this->sent()[1]['contents']);
        $this->assertStringContainsString('Officer Customer', $second);
        $this->assertStringNotContainsString('Owner Customer', $second);
    }

    public function test_the_owner_sees_everyones_sales(): void
    {
        $owner = $this->shop();
        $officer = $this->officer($owner);
        $p = $this->product($owner, 'Soda');
        $this->sell($owner, $p, $this->customer($owner, 'Owner Customer', '0711000001'), 1000);
        $this->sell($officer, $p, $this->customer($owner, 'Officer Customer', '0711000002'), 2000);

        $this->geminiCalls('recent_sales', ['days' => 7]);
        $this->api($owner, 'POST', '/api/inventory/assistant', ['question' => 'All sales'])->assertOk();
        $second = json_encode($this->sent()[1]['contents']);
        $this->assertStringContainsString('Officer Customer', $second);
        $this->assertStringContainsString('Owner Customer', $second);
    }

    public function test_one_business_cannot_reach_another_businesss_customers_through_the_assistant(): void
    {
        $a = $this->shop('Shop A');
        $b = $this->shop('Shop B');
        $this->customer($b, 'Secret Customer', '0755000009');
        $this->geminiCalls('find_customer', ['name' => 'Secret']);

        $r = $this->api($a, 'POST', '/api/inventory/assistant', ['question' => 'Find Secret'])->assertOk();

        $this->assertSame([], $r->json('data.cards'));
        $this->assertStringNotContainsString('Secret Customer', json_encode($this->sent()[1]['contents']));
    }

    public function test_the_question_is_checked_and_the_daily_limit_holds(): void
    {
        config(['services.gemini.key' => 'g-test']);
        Http::fake();
        $owner = $this->shop();

        $this->api($owner, 'POST', '/api/inventory/assistant', ['question' => ''])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/assistant', ['question' => str_repeat('x', 601)])->assertStatus(422);

        Cache::put('assistant_questions:' . $owner->id . ':' . now()->toDateString(), 60, now()->endOfDay());
        $this->api($owner, 'POST', '/api/inventory/assistant', ['question' => 'One more?'])->assertStatus(429)->assertJsonPath('code', 'assistant_daily_limit');
        Http::assertNothingSent();
    }

    public function test_when_the_ai_fails_the_person_gets_a_plain_message_with_no_technical_detail(): void
    {
        config(['services.gemini.key' => 'g-test']);
        Http::fake(['generativelanguage.googleapis.com/*' => Http::response(['error' => ['message' => 'quota for key g-test']], 429)]);
        $owner = $this->shop();

        $r = $this->api($owner, 'POST', '/api/inventory/assistant', ['question' => 'Who owes me?'])->assertStatus(503);

        $this->assertSame('assistant_failed', $r->json('code'));
        $this->assertStringNotContainsString('quota', $r->getContent());
        $this->assertStringNotContainsString('g-test', $r->getContent());
    }
}
