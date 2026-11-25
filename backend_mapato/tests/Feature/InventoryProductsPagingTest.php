<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The product list is paged, newest first. A shop's older products (the slow sellers, saved long ago) sit on the later pages: the app must be
 * able to read all of them. The server gives 100 to a page (an older app that reads only the first page then still sees a hundred, not
 * twenty), or fewer when asked.
 */
class InventoryProductsPagingTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');
    }

    private function api(string $method, string $uri, array $body = [])
    {
        $token = $this->owner->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function save(int $count): void
    {
        for ($i = 1; $i <= $count; $i++) {
            $this->api('POST', '/api/inventory/products', ['name' => "Item {$i}", 'cost_price' => 500, 'selling_price' => 800, 'quantity' => 4, 'min_stock' => 1, 'status' => 'active'])->assertCreated();
        }
    }

    public function test_every_product_is_there_nothing_is_lost_only_the_first_page_is_short(): void
    {
        $this->save(45);

        $first = $this->api('GET', '/api/inventory/products?per_page=20')->assertOk();
        $this->assertCount(20, $first->json('data'));
        $this->assertSame(45, $first->json('meta.total'));
        $this->assertSame(3, $first->json('meta.last_page'));
        $this->assertSame('Item 45', $first->json('data.0.name'));

        // The oldest product is on the last page: saved long ago, not gone.
        $last = $this->api('GET', '/api/inventory/products?per_page=20&page=3')->assertOk();
        $this->assertSame('Item 1', $last->json('data.4.name'));
        $this->assertCount(5, $last->json('data'));
    }

    public function test_the_app_can_ask_for_a_longer_page_and_gets_them_all_in_one_go_up_to_the_ceiling(): void
    {
        $this->save(45);

        $all = $this->api('GET', '/api/inventory/products?per_page=100')->assertOk();
        $this->assertCount(45, $all->json('data'));
        $this->assertSame(1, $all->json('meta.last_page'));
        $names = collect($all->json('data'))->pluck('name')->all();
        $this->assertContains('Item 1', $names);
        $this->assertContains('Item 45', $names);

        // Nobody can ask for the whole table at once: the ceiling is 100, and nonsense falls back to the default of 100.
        $this->assertSame(100, $this->api('GET', '/api/inventory/products?per_page=5000')->json('meta.per_page'));
        $this->assertSame(100, $this->api('GET', '/api/inventory/products?per_page=abc')->json('meta.per_page'));
        $this->assertSame(10, $this->api('GET', '/api/inventory/products?per_page=10')->json('meta.per_page'));
    }

    public function test_an_older_app_that_asks_for_nothing_and_reads_only_the_first_page_still_sees_up_to_a_hundred_products(): void
    {
        $this->save(45);
        $res = $this->api('GET', '/api/inventory/products?page=1&with_units=1')->assertOk();
        $this->assertCount(45, $res->json('data'), 'the shop of the customer who lost products has fewer than a hundred: all of them show');
        $this->assertContains('Item 1', collect($res->json('data'))->pluck('name')->all());
    }

    public function test_the_list_can_be_asked_for_from_a_to_z_capitals_and_spaces_ignored_and_the_pages_follow_that_order(): void
    {
        foreach (['kucha', 'Bangili', '  Cheni', 'bangili', 'Zeze', 'afro wig', 'Rasta', 'Mafuta'] as $name) {
            $this->api('POST', '/api/inventory/products', ['name' => $name, 'cost_price' => 500, 'selling_price' => 800, 'quantity' => 4, 'min_stock' => 1, 'status' => 'active'])->assertCreated();
        }
        $names = fn (string $q) => collect($this->api('GET', '/api/inventory/products?sort=name&' . $q)->assertOk()->json('data'))->pluck('name')->map(fn ($n) => trim($n))->all();

        $this->assertSame(['afro wig', 'Bangili', 'bangili', 'Cheni', 'kucha', 'Mafuta', 'Rasta', 'Zeze'], $names('per_page=100'));
        // Page by page it is the same one order, not each page sorted on its own.
        $this->assertSame(['afro wig', 'Bangili', 'bangili'], $names('per_page=3&page=1'));
        $this->assertSame(['Cheni', 'kucha', 'Mafuta'], $names('per_page=3&page=2'));
        $this->assertSame(['Rasta', 'Zeze'], $names('per_page=3&page=3'));
        // Without it the newest comes first, as before.
        $this->assertSame('Mafuta', trim($this->api('GET', '/api/inventory/products?per_page=100')->json('data.0.name')));
    }

    public function test_a_search_finds_an_old_product_whatever_page_it_is_on(): void
    {
        $this->save(45);
        $found = $this->api('GET', '/api/inventory/products?q=Item 1&per_page=100')->assertOk();
        $this->assertContains('Item 1', collect($found->json('data'))->pluck('name')->all());
    }
}
