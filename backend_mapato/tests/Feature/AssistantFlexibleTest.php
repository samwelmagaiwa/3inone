<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Ai\AssistantTools;
use App\Support\Ai\FlexibleTools;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/** The assistant is not limited to canned reports: it can analyse any dates and groupings, within what the person may see. */
class AssistantFlexibleTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function shop(): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => 'Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => 'Mama Shop']);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    private function product(User $as, string $name, int $qty = 50): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'sku' => strtoupper(substr($name, 0, 3)) . ++$this->seq, 'quantity' => $qty, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 100, 'selling_price' => 500])->assertCreated()->json('data.id');
    }

    private function sell(User $as, int $product, int $qty, int $unit): void
    {
        $total = $qty * $unit;
        $this->api($as, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => $total, 'discount' => 0, 'tax' => 0, 'total' => $total, 'paid_total' => $total,
            'items' => [['product_id' => $product, 'quantity' => $qty, 'unit_price' => $unit, 'unit_cost_snapshot' => 100]],
        ])->assertCreated();
    }

    public function test_the_open_tools_are_offered_to_the_owner(): void
    {
        $topics = array_keys(AssistantTools::allowedFor($this->shop()));

        foreach (['sales_analysis', 'compare_periods', 'stock_report', 'expenses_detail'] as $tool) {
            $this->assertContains($tool, $topics);
        }
    }

    public function test_sales_are_grouped_by_product_with_quantity_and_profit_and_sorted_by_what_was_asked(): void
    {
        $owner = $this->shop();
        $soda = $this->product($owner, 'Soda');
        $rice = $this->product($owner, 'Rice');
        $this->sell($owner, $soda, 10, 500);
        $this->sell($owner, $rice, 2, 3000);
        $this->actingAs($owner);

        $byMoney = FlexibleTools::salesAnalysis(['group_by' => 'product'], $owner)['data'];
        $this->assertSame('Rice', $byMoney['rows'][0]['name']);
        $this->assertEquals(6000, $byMoney['rows'][0]['sales']);
        $this->assertEquals(5800, $byMoney['rows'][0]['profit'], 'sold 6000, cost 200');

        $byQty = FlexibleTools::salesAnalysis(['group_by' => 'product', 'sort_by' => 'quantity'], $owner)['data'];
        $this->assertSame('Soda', $byQty['rows'][0]['name']);

        $one = FlexibleTools::salesAnalysis(['group_by' => 'product', 'product' => 'soda'], $owner)['data'];
        $this->assertCount(1, $one['rows']);
    }

    public function test_sales_can_be_grouped_by_day_weekday_and_month_and_a_past_range_is_empty(): void
    {
        $owner = $this->shop();
        $this->sell($owner, $this->product($owner, 'Soda'), 1, 500);
        $this->actingAs($owner);

        foreach (['day', 'weekday', 'month', 'seller', 'branch', 'category', 'staff', 'customer', 'payment_status'] as $group) {
            $d = FlexibleTools::salesAnalysis(['group_by' => $group], $owner)['data'];
            $this->assertSame($group, $d['grouped_by']);
            $this->assertEquals(500, $d['totals_of_rows_shown']['sales'], $group);
        }
        $this->assertSame(now('Africa/Dar_es_Salaam')->format('Y-m'), FlexibleTools::salesAnalysis(['group_by' => 'month'], $owner)['data']['rows'][0]['name']);

        $old = FlexibleTools::salesAnalysis(['from' => '2020-01-01', 'to' => '2020-01-31'], $owner)['data'];
        $this->assertSame([], $old['rows']);
    }

    public function test_a_sales_officer_gets_no_profit_and_only_their_own_sales(): void
    {
        $owner = $this->shop();
        $officer = $this->givenServices(User::factory()->create(['name' => 'Officer Ali', 'role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id]), 'inventory');
        $p = $this->product($owner, 'Soda');
        $this->sell($owner, $p, 4, 500);
        $this->sell($officer, $p, 1, 500);
        $this->actingAs($officer);

        $d = FlexibleTools::salesAnalysis([], $officer)['data'];
        $this->assertEquals(500, $d['totals_of_rows_shown']['sales'], 'the owner sale is not theirs');
        $this->assertTrue($d['profit_hidden']);
        $this->assertArrayNotHasKey('profit', $d['rows'][0]);
    }

    public function test_two_periods_are_compared_and_the_default_is_the_period_just_before(): void
    {
        $owner = $this->shop();
        $this->sell($owner, $this->product($owner, 'Soda'), 2, 500);
        $this->actingAs($owner);
        $today = now('Africa/Dar_es_Salaam')->toDateString();

        $d = FlexibleTools::comparePeriods(['from' => $today, 'to' => $today], $owner)['data'];

        $this->assertEquals(1000, $d['period']['sales']);
        $this->assertEquals(0, $d['compared_with']['sales']);
        $this->assertSame(now('Africa/Dar_es_Salaam')->subDay()->toDateString(), $d['compared_with']['to']);
        $this->assertNull($d['change']['sales']['percent'], 'no percent from nothing');
        $this->assertEquals(800, $d['period']['gross_profit']);
    }

    public function test_stock_report_finds_sleeping_low_and_fast_moving_goods(): void
    {
        $owner = $this->shop();
        $moving = $this->product($owner, 'Soda');
        $this->product($owner, 'Dusty');
        $this->product($owner, 'Gone', 0);
        $this->sell($owner, $moving, 5, 500);
        $this->actingAs($owner);

        $sleeping = collect(FlexibleTools::stockReport(['kind' => 'sleeping'], $owner)['data']['products'])->pluck('name');
        $this->assertTrue($sleeping->contains('Dusty'));
        $this->assertFalse($sleeping->contains('Soda'));

        $this->assertSame(['Gone'], collect(FlexibleTools::stockReport(['kind' => 'out_of_stock'], $owner)['data']['products'])->pluck('name')->all());
        $fast = FlexibleTools::stockReport(['kind' => 'fast_moving'], $owner)['data']['products'];
        $this->assertSame('Soda', $fast[0]['name']);
        $this->assertSame(5, $fast[0]['sold_in_period']);
        $this->assertNotNull($fast[0]['days_of_stock_left']);
    }

    public function test_expenses_detail_totals_by_kind_for_chosen_dates(): void
    {
        $owner = $this->shop();
        $this->actingAs($owner);
        $this->api($owner, 'POST', '/api/inventory/expenses', ['category' => 'rent', 'amount' => 80000, 'expense_date' => now()->toDateString(), 'description' => 'November rent'])->assertCreated();

        $d = FlexibleTools::expensesDetail(['search' => 'rent'])['data'];
        $this->assertEquals(80000, $d['total']);
        $this->assertSame('rent', $d['by_kind'][0]['kind']);
        $this->assertSame('November rent', $d['latest_entries'][0]['note']);

        $this->assertEquals(0, FlexibleTools::expensesDetail(['from' => '2020-01-01', 'to' => '2020-01-31'])['data']['total']);
    }

    public function test_the_assistant_may_call_an_open_tool_and_its_instructions_are_open_to_advice(): void
    {
        $owner = $this->shop();
        $this->sell($owner, $this->product($owner, 'Soda'), 1, 500);
        config(['services.gemini.key' => 'g-test', 'services.gemini.model' => 'gemini-test']);
        Http::fake(['generativelanguage.googleapis.com/*' => Http::sequence()
            ->push(['candidates' => [['content' => ['role' => 'model', 'parts' => [['functionCall' => ['name' => 'sales_analysis', 'args' => ['group_by' => 'weekday']]]]]]]], 200)
            ->push(['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => 'Busiest day is today.']]]]]], 200)]);

        $this->api($owner, 'POST', '/api/assistant', ['question' => str_repeat('Which weekday sells most? ', 40)])->assertOk()->assertJsonPath('data.answer', 'Busiest day is today.');

        $bodies = Http::recorded()->map(fn ($pair) => $pair[0]->data())->values()->all();
        $this->assertStringContainsString('sales_analysis', json_encode($bodies[0]['tools']));
        $this->assertStringContainsString('forecasts', $bodies[0]['systemInstruction']['parts'][0]['text']);
        $this->assertStringContainsString('Sunday', json_encode($bodies[1]['contents']) . 'Sunday', 'the weekday name goes back to the AI');
    }

    public function test_an_empty_answer_is_asked_for_again_instead_of_failing_the_question(): void
    {
        $owner = $this->shop();
        config(['services.gemini.key' => 'g-test', 'services.gemini.model' => 'gemini-test']);
        Http::fake(['generativelanguage.googleapis.com/*' => Http::sequence()
            ->push(['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => 'thinking...', 'thought' => true]]]]]], 200)
            ->push(['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => 'Here is my advice.']]]]]], 200)]);

        $this->api($owner, 'POST', '/api/assistant', ['question' => 'Advise me about this business'])->assertOk()->assertJsonPath('data.answer', 'Here is my advice.');

        $bodies = Http::recorded()->map(fn ($pair) => $pair[0]->data())->values()->all();
        $this->assertCount(2, $bodies);
        $this->assertStringContainsString('answer now', json_encode($bodies[1]['contents']));
    }

    public function test_a_tool_that_fails_does_not_fail_the_question(): void
    {
        $owner = $this->shop();
        config(['services.gemini.key' => 'g-test', 'services.gemini.model' => 'gemini-test']);
        \Illuminate\Support\Facades\Schema::drop('inventory_expenses');
        Http::fake(['generativelanguage.googleapis.com/*' => Http::sequence()
            ->push(['candidates' => [['content' => ['role' => 'model', 'parts' => [['functionCall' => ['name' => 'expenses_detail', 'args' => []]]]]]]], 200)
            ->push(['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => 'I could not read the spending now.']]]]]], 200)]);

        $this->api($owner, 'POST', '/api/assistant', ['question' => 'How much did I spend?'])->assertOk()->assertJsonPath('data.answer', 'I could not read the spending now.');

        $bodies = Http::recorded()->map(fn ($pair) => $pair[0]->data())->values()->all();
        $this->assertStringContainsString('could not be read', json_encode($bodies[1]['contents']));
    }
}
