<?php

namespace Tests\Unit;

use App\Support\Inventory\BusinessAdvisor;
use PHPUnit\Framework\TestCase;

/**
 * The AI's advice is checked against the month's facts before the owner reads it: an amount that is not in the facts (nor the sum or
 * difference of two of them) is never shown, the page holds at most five pieces, and rule-based pieces fill what the check removed.
 */
class AdviceCheckTest extends TestCase
{
    private function facts(): array
    {
        return [
            'this_month' => ['sales' => 3460000, 'net_profit' => 235000, 'expenses' => 0],
            'position' => ['receivable' => 14190000, 'stock_value' => 20000000],
            'customers_who_owe' => [['name' => 'Baba D', 'owed' => 5610000, 'days' => 0], ['name' => 'BABA D', 'owed' => 1370000, 'days' => 1]],
            'worked_out' => ['net_profit_per_day' => 11750, 'owed_percent_of_sales' => 410.1],
        ];
    }

    private function item(string $detail, string $level = 'tip'): array
    {
        // the title carries no digits, so only the detail is under test
        static $n = 0;

        return ['level' => $level, 'title' => 'Title ' . str_repeat(chr(65 + ($n++ % 26)), 2), 'detail' => $detail];
    }

    private function rules(): array
    {
        return [
            ['level' => 'warning', 'title' => 'Rule one', 'detail' => 'r1'],
            ['level' => 'tip', 'title' => 'Rule two', 'detail' => 'r2'],
            ['level' => 'tip', 'title' => 'Rule three', 'detail' => 'r3'],
        ];
    }

    public function test_an_amount_that_is_in_the_facts_is_kept(): void
    {
        $items = [
            $this->item('Baba D owes TSh 5,610,000: call him.'),
            $this->item('Profit is TSh 235,000 so far.'),
            $this->item('You are owed 14,190,000 in all.'),
        ];

        $kept = BusinessAdvisor::checked($items, $this->facts(), $this->rules());

        $this->assertCount(3, $kept);
        $this->assertSame($items, $kept);
    }

    public function test_an_invented_amount_is_dropped(): void
    {
        $items = [
            $this->item('Baba D owes TSh 5,610,000.'),
            $this->item('Baba D owes TSh 9,999,999.'),
            $this->item('Profit is TSh 235,000.'),
            $this->item('Sales are TSh 3,460,000.'),
        ];

        $kept = BusinessAdvisor::checked($items, $this->facts(), $this->rules());

        $this->assertCount(3, $kept);
        $this->assertNotContains('Baba D owes TSh 9,999,999.', array_column($kept, 'detail'));
    }

    public function test_a_sum_or_difference_of_two_known_amounts_is_accepted(): void
    {
        // 5,610,000 + 1,370,000 = 6,980,000 (the two Baba D records together); 3,460,000 - 235,000 = 3,225,000 (the cost of goods)
        $items = [
            $this->item('Together Baba D owes TSh 6,980,000.'),
            $this->item('The goods cost TSh 3,225,000.'),
            $this->item('Profit is TSh 235,000.'),
        ];

        $this->assertCount(3, BusinessAdvisor::checked($items, $this->facts(), $this->rules()));
    }

    public function test_small_numbers_percentages_and_years_are_not_amounts(): void
    {
        $items = [
            $this->item('Only 6.8% margin, 27 days left in 2026, 3 customers owe more than 60 days.'),
            $this->item('Profit is TSh 235,000.'),
            $this->item('Sales are TSh 3,460,000.'),
        ];

        $this->assertCount(3, BusinessAdvisor::checked($items, $this->facts(), $this->rules()));
    }

    public function test_when_too_little_is_left_the_rules_fill_the_page_without_repeating(): void
    {
        $items = [$this->item('Profit is TSh 235,000.'), $this->item('Made up TSh 8,888,888.')];

        $kept = BusinessAdvisor::checked($items, $this->facts(), $this->rules());

        $this->assertSame(['Profit is TSh 235,000.', 'r1', 'r2', 'r3'], array_column($kept, 'detail'));
    }

    public function test_nothing_usable_is_nothing(): void
    {
        $this->assertSame([], BusinessAdvisor::checked([], $this->facts(), $this->rules()));
        $this->assertSame([], BusinessAdvisor::checked([$this->item('Made up TSh 8,888,888.')], $this->facts(), $this->rules()), 'all invented: the AI did not give a usable answer');
    }

    public function test_the_page_never_holds_more_than_five(): void
    {
        $items = [];
        for ($i = 1; $i <= 9; $i++) {
            $items[] = $this->item("Point {$i}: profit TSh 235,000.");
        }

        $this->assertCount(BusinessAdvisor::ITEMS, BusinessAdvisor::checked($items, $this->facts(), []));
        $this->assertSame(5, BusinessAdvisor::ITEMS);
    }

    public function test_the_ai_reply_is_read_into_at_most_five_clean_items(): void
    {
        $reply = 'Sure: ' . json_encode(array_map(fn ($i) => ['level' => 'tip', 'title' => "Title {$i}", 'detail' => "Detail {$i}"], range(1, 8)));

        $this->assertCount(5, BusinessAdvisor::parse($reply));
    }
}
