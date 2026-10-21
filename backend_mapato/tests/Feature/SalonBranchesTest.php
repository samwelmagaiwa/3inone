<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** Branches: records carry their branch, figures can be of one branch, and a single-branch salon sees no change. */
class SalonBranchesTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    private function salon(string $name = 'Glow'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0724' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function api(User $as, string $method, string $uri, array $body = [], array $headers = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->withHeaders($headers)->json($method, $uri, $body);
    }

    private function sell(User $as, int $product, int $price, array $headers = [])
    {
        return $this->api($as, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => $price, 'discount' => 0, 'tax' => 0, 'total' => $price, 'paid_total' => $price,
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => $price]],
            'payments' => [['amount' => $price, 'method' => 'cash']],
        ], $headers)->assertCreated();
    }

    private function product(User $as): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => 'Braids', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 10000, 'duration_minutes' => 60])->assertCreated()->json('data.id');
    }

    public function test_figures_follow_the_chosen_branch(): void
    {
        $owner = $this->salon();
        $a = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Kariakoo'])->assertCreated()->json('data.id');
        $b = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Mikocheni'])->assertCreated()->json('data.id');
        $p = $this->product($owner);
        $this->sell($owner, $p, 10000, ['X-Branch' => (string) $a]);
        $this->sell($owner, $p, 10000, ['X-Branch' => (string) $a]);
        $this->sell($owner, $p, 5000, ['X-Branch' => (string) $b]);

        $this->api($owner, 'POST', '/api/inventory/expenses', ['description' => 'Rent', 'category' => 'rent', 'amount' => 3000, 'expense_date' => now()->toDateString()], ['X-Branch' => (string) $b])->assertSuccessful();

        $all = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?period=today')->assertOk()->json('data');
        $this->assertEquals(25000, $all['revenue']['total'] ?? $all['revenue'] ?? null);

        $ka = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?period=today', [], ['X-Branch' => (string) $a])->assertOk()->json('data');
        $this->assertEquals(20000, $ka['revenue']['total'] ?? $ka['revenue']);

        $mi = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?period=today', [], ['X-Branch' => (string) $b])->assertOk()->json('data');
        $this->assertEquals(5000, $mi['revenue']['total'] ?? $mi['revenue']);
    }

    public function test_no_branches_means_nothing_changes_and_bad_header_is_ignored(): void
    {
        $owner = $this->salon();
        $p = $this->product($owner);
        $this->sell($owner, $p, 10000, ['X-Branch' => '999']);
        $this->assertNull(\DB::table('inventory_sales')->value('branch_id'));
        $d = $this->api($owner, 'GET', '/api/inventory/salon/profit-loss?period=today', [], ['X-Branch' => '999'])->assertOk()->json('data');
        $this->assertEquals(10000, $d['revenue']['total'] ?? $d['revenue']);
    }

    public function test_only_managers_change_branches_and_used_ones_cannot_be_deleted(): void
    {
        $owner = $this->salon();
        $stylist = $this->givenServices(User::factory()->create(['name' => 'S', 'role' => 'hair_stylist', 'is_active' => true, 'created_by' => $owner->id]), 'salon');
        $this->api($stylist, 'POST', '/api/inventory/salon/branches', ['name' => 'X'])->assertForbidden();
        $id = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertCreated()->json('data.id');
        $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertStatus(422);
        $this->api($stylist, 'GET', '/api/inventory/salon/branches')->assertOk()->assertJsonCount(1, 'data');
        $this->sell($owner, $this->product($owner), 1000, ['X-Branch' => (string) $id]);
        $this->api($owner, 'DELETE', "/api/inventory/salon/branches/{$id}")->assertStatus(422);
        $this->api($owner, 'PUT', "/api/inventory/salon/branches/{$id}", ['active' => false])->assertOk();
        $this->api($stylist, 'GET', '/api/inventory/salon/branches')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_another_salon_never_sees_these_branches(): void
    {
        $one = $this->salon('One');
        $two = $this->salon('Two');
        $this->api($one, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertCreated();
        $this->api($two, 'GET', '/api/inventory/salon/branches')->assertOk()->assertJsonCount(0, 'data');
        $this->api($two, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertCreated();
    }

    private function goods(User $as, int $stock): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => 'Shampoo', 'quantity' => $stock, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 3000, 'selling_price' => 8000])->assertCreated()->json('data.id');
    }

    private function branchShelf(User $as, int $product, int $branch): int
    {
        $rows = $this->api($as, 'GET', '/api/inventory/salon/branch-stock')->assertOk()->json('data.products');
        $row = collect($rows)->firstWhere('id', $product);

        return (int) collect($row['branches'])->firstWhere('branch_id', $branch)['quantity'];
    }

    private function stockOf(int $product): int
    {
        return (int) \Illuminate\Support\Facades\DB::table('inventory_products')->where('id', $product)->value('quantity');
    }

    public function test_goods_are_moved_between_the_main_store_and_branches_and_never_more_than_is_there(): void
    {
        $owner = $this->salon();
        $a = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Kariakoo'])->assertCreated()->json('data.id');
        $b = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Mikocheni'])->assertCreated()->json('data.id');
        $p = $this->goods($owner, 10);

        $first = $this->api($owner, 'GET', '/api/inventory/salon/branch-stock')->json('data.products.0');
        $this->assertSame([10, 10], [$first['total'], $first['unallocated']], 'all in the main store at first');

        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'to_branch_id' => $a, 'quantity' => 6])->assertOk();
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'from_branch_id' => $a, 'to_branch_id' => $b, 'quantity' => 2])->assertOk();
        $row = $this->api($owner, 'GET', '/api/inventory/salon/branch-stock')->json('data.products.0');
        $this->assertSame([10, 4], [$row['total'], $row['unallocated']]);
        $this->assertSame([4, 2], [$this->branchShelf($owner, $p, $a), $this->branchShelf($owner, $p, $b)]);

        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'from_branch_id' => $b, 'to_branch_id' => $a, 'quantity' => 3])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'to_branch_id' => $a, 'quantity' => 5])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'from_branch_id' => $a, 'to_branch_id' => $a, 'quantity' => 1])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'from_branch_id' => $b, 'quantity' => 2])->assertOk();
        $this->assertSame(6, $this->api($owner, 'GET', '/api/inventory/salon/branch-stock')->json('data.products.0.unallocated'), 'back in the main store');
    }

    public function test_a_sale_in_a_branch_takes_from_its_shelf_and_a_cancel_puts_it_back(): void
    {
        $owner = $this->salon();
        $a = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Kariakoo'])->assertCreated()->json('data.id');
        $b = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Mikocheni'])->assertCreated()->json('data.id');
        $p = $this->goods($owner, 10);
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'to_branch_id' => $a, 'quantity' => 6])->assertOk();

        $sale = $this->api($owner, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 16000, 'discount' => 0, 'tax' => 0, 'total' => 16000, 'paid_total' => 16000,
            'items' => [['product_id' => $p, 'quantity' => 2, 'unit_price' => 8000]], 'payments' => [['amount' => 16000, 'method' => 'cash']],
        ], ['X-Branch' => (string) $a])->assertCreated()->json('data.id');
        $this->assertSame(4, $this->branchShelf($owner, $p, $a));
        $this->assertSame(8, $this->stockOf($p));

        // A branch with nothing allocated still sells (from the main store): never stopped for this.
        $this->api($owner, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 8000, 'discount' => 0, 'tax' => 0, 'total' => 8000, 'paid_total' => 8000,
            'items' => [['product_id' => $p, 'quantity' => 1, 'unit_price' => 8000]], 'payments' => [['amount' => 8000, 'method' => 'cash']],
        ], ['X-Branch' => (string) $b])->assertCreated();
        $this->assertSame(0, $this->branchShelf($owner, $p, $b));
        $this->assertSame(7, $this->stockOf($p));

        $this->api($owner, 'POST', "/api/inventory/sales/{$sale}/cancel", ['reason' => 'Mistake'])->assertOk();
        $this->assertSame(6, $this->branchShelf($owner, $p, $a));
        $this->assertSame(9, $this->stockOf($p));
    }

    public function test_only_keepers_move_stock_but_everyone_may_look_and_a_salon_never_sees_anothers_stock(): void
    {
        $owner = $this->salon('One');
        $other = $this->salon('Two');
        $stylist = $this->givenServices(User::factory()->create(['name' => 'S', 'role' => 'hair_stylist', 'is_active' => true, 'created_by' => $owner->id]), 'salon');
        $br = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertCreated()->json('data.id');
        $p = $this->goods($owner, 5);
        $this->api($stylist, 'GET', '/api/inventory/salon/branch-stock')->assertOk();
        $this->api($stylist, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'to_branch_id' => $br, 'quantity' => 1])->assertForbidden();

        $this->assertSame([], $this->api($other, 'GET', '/api/inventory/salon/branch-stock')->json('data.products'));
        $this->api($other, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'to_branch_id' => $br, 'quantity' => 1])->assertStatus(422);
    }

    private function sellGoods(User $as, int $product, int $qty, int $branch): int
    {
        return $this->api($as, 'POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 8000 * $qty, 'discount' => 0, 'tax' => 0, 'total' => 8000 * $qty, 'paid_total' => 8000 * $qty,
            'items' => [['product_id' => $product, 'quantity' => $qty, 'unit_price' => 8000]], 'payments' => [['amount' => 8000 * $qty, 'method' => 'cash']],
        ], ['X-Branch' => (string) $branch])->assertCreated()->json('data.id');
    }

    private function lowAlerts(): int
    {
        return \Illuminate\Support\Facades\DB::table('inventory_notifications')->where('type', 'salon_branch_low_stock')->count();
    }

    public function test_every_move_is_kept_in_a_history_newest_first_with_names(): void
    {
        $owner = $this->salon();
        $a = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Kariakoo'])->assertCreated()->json('data.id');
        $b = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Mikocheni'])->assertCreated()->json('data.id');
        $p = $this->goods($owner, 10);
        $q = $this->goods($owner, 5);
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'to_branch_id' => $a, 'quantity' => 6])->assertOk();
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'from_branch_id' => $a, 'to_branch_id' => $b, 'quantity' => 2])->assertOk();
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $q, 'to_branch_id' => $b, 'quantity' => 1])->assertOk();
        // a refused move leaves nothing in the history
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'from_branch_id' => $b, 'to_branch_id' => $a, 'quantity' => 50])->assertStatus(422);

        $all = $this->api($owner, 'GET', '/api/inventory/salon/branch-stock/transfers')->assertOk()->json('data');
        $this->assertCount(3, $all);
        $this->assertSame([1, 2, 6], array_column($all, 'quantity'), 'newest first');
        $this->assertSame([null, 'Kariakoo', null], array_column($all, 'from'));
        $this->assertSame(['Mikocheni', 'Mikocheni', 'Kariakoo'], array_column($all, 'to'));
        $this->assertSame('Glow Owner', $all[0]['by']);

        $this->assertCount(2, $this->api($owner, 'GET', "/api/inventory/salon/branch-stock/transfers?product_id={$p}")->json('data'));
        $this->assertCount(2, $this->api($owner, 'GET', "/api/inventory/salon/branch-stock/transfers?branch_id={$b}")->json('data'));
        $this->assertCount(2, $this->api($owner, 'GET', "/api/inventory/salon/branch-stock/transfers?branch_id={$a}")->json('data'));
        $this->assertCount(1, $this->api($owner, 'GET', '/api/inventory/salon/branch-stock/transfers?limit=1')->json('data'));
    }

    public function test_the_history_is_one_salons_only(): void
    {
        $one = $this->salon('One');
        $two = $this->salon('Two');
        $br = $this->api($one, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertCreated()->json('data.id');
        $p = $this->goods($one, 5);
        $this->api($one, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'to_branch_id' => $br, 'quantity' => 1])->assertOk();
        $this->assertSame([], $this->api($two, 'GET', '/api/inventory/salon/branch-stock/transfers')->json('data'));
    }

    public function test_a_branch_is_told_once_when_a_product_drops_to_its_level(): void
    {
        $owner = $this->salon();
        $a = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Kariakoo'])->assertCreated()->json('data.id');
        $p = $this->goods($owner, 10);
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'to_branch_id' => $a, 'quantity' => 6])->assertOk();
        $this->api($owner, 'PUT', '/api/inventory/salon/branch-stock/level', ['product_id' => $p, 'branch_id' => $a, 'min_quantity' => 3])->assertOk();

        $this->sellGoods($owner, $p, 2, $a);   // 6 -> 4: still above 3
        $this->assertSame(0, $this->lowAlerts());
        $this->sellGoods($owner, $p, 1, $a);   // 4 -> 3: at its level
        $this->assertSame(1, $this->lowAlerts());
        $this->sellGoods($owner, $p, 1, $a);   // 3 -> 2: already low, not told again
        $this->assertSame(1, $this->lowAlerts());

        $row = collect($this->api($owner, 'GET', '/api/inventory/salon/branch-stock')->json('data.products.0.branches'))->firstWhere('branch_id', $a);
        $this->assertSame([2, 3, true], [$row['quantity'], $row['min_quantity'], $row['low']]);
        $this->assertSame(1, $this->api($owner, 'GET', '/api/inventory/salon/branch-stock')->json('data.low'));

        // restocked above the level, then it drops again: told again
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'to_branch_id' => $a, 'quantity' => 3])->assertOk();
        $this->sellGoods($owner, $p, 2, $a);   // 5 -> 3
        $this->assertSame(2, $this->lowAlerts());
        $note = \Illuminate\Support\Facades\DB::table('inventory_notifications')->where('type', 'salon_branch_low_stock')->first();
        $this->assertStringContainsString('Kariakoo: Shampoo', (string) $note->body);
    }

    public function test_moving_goods_out_of_a_branch_below_its_level_also_tells(): void
    {
        $owner = $this->salon();
        $a = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Kariakoo'])->assertCreated()->json('data.id');
        $b = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Mikocheni'])->assertCreated()->json('data.id');
        $p = $this->goods($owner, 10);
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'to_branch_id' => $a, 'quantity' => 6])->assertOk();
        $this->api($owner, 'PUT', '/api/inventory/salon/branch-stock/level', ['product_id' => $p, 'branch_id' => $a, 'min_quantity' => 4])->assertOk();
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'from_branch_id' => $a, 'to_branch_id' => $b, 'quantity' => 3])->assertOk();
        $this->assertSame(1, $this->lowAlerts());
    }

    public function test_without_a_level_there_is_no_alert_and_a_level_can_be_cleared_or_refused(): void
    {
        $owner = $this->salon();
        $a = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Kariakoo'])->assertCreated()->json('data.id');
        $p = $this->goods($owner, 10);
        $this->api($owner, 'POST', '/api/inventory/salon/branch-stock/transfer', ['product_id' => $p, 'to_branch_id' => $a, 'quantity' => 4])->assertOk();
        $this->sellGoods($owner, $p, 4, $a);
        $this->assertSame(0, $this->lowAlerts(), 'no level, no alert');

        $this->api($owner, 'PUT', '/api/inventory/salon/branch-stock/level', ['product_id' => $p, 'branch_id' => $a, 'min_quantity' => 2])->assertOk();
        $this->api($owner, 'PUT', '/api/inventory/salon/branch-stock/level', ['product_id' => $p, 'branch_id' => $a, 'min_quantity' => null])->assertOk();
        $row = collect($this->api($owner, 'GET', '/api/inventory/salon/branch-stock')->json('data.products.0.branches'))->firstWhere('branch_id', $a);
        $this->assertNull($row['min_quantity']);
        $this->assertFalse($row['low']);

        $this->api($owner, 'PUT', '/api/inventory/salon/branch-stock/level', ['product_id' => $p, 'branch_id' => $a, 'min_quantity' => -1])->assertStatus(422);
        $this->api($owner, 'PUT', '/api/inventory/salon/branch-stock/level', ['product_id' => $p, 'branch_id' => 99999, 'min_quantity' => 1])->assertStatus(422);
        $svc = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Braids', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 1000, 'duration_minutes' => 30])->assertCreated()->json('data.id');
        $this->api($owner, 'PUT', '/api/inventory/salon/branch-stock/level', ['product_id' => $svc, 'branch_id' => $a, 'min_quantity' => 1])->assertStatus(422);
    }

    public function test_only_keepers_set_levels_and_a_level_is_not_shared_between_salons(): void
    {
        $owner = $this->salon('One');
        $other = $this->salon('Two');
        $stylist = $this->givenServices(User::factory()->create(['name' => 'S', 'role' => 'hair_stylist', 'is_active' => true, 'created_by' => $owner->id]), 'salon');
        $br = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Main'])->assertCreated()->json('data.id');
        $p = $this->goods($owner, 5);
        $this->api($stylist, 'PUT', '/api/inventory/salon/branch-stock/level', ['product_id' => $p, 'branch_id' => $br, 'min_quantity' => 1])->assertForbidden();
        $this->api($other, 'PUT', '/api/inventory/salon/branch-stock/level', ['product_id' => $p, 'branch_id' => $br, 'min_quantity' => 1])->assertStatus(422);
    }

    public function test_the_sales_lists_and_summaries_follow_the_chosen_branch(): void
    {
        $owner = $this->salon();
        $a = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Kariakoo'])->assertCreated()->json('data.id');
        $b = $this->api($owner, 'POST', '/api/inventory/salon/branches', ['name' => 'Mikocheni'])->assertCreated()->json('data.id');
        $p = $this->product($owner);
        $this->sell($owner, $p, 10000, ['X-Branch' => (string) $a]);
        $this->sell($owner, $p, 10000, ['X-Branch' => (string) $a]);
        $this->sell($owner, $p, 10000, ['X-Branch' => (string) $b]);

        $this->assertCount(3, $this->api($owner, 'GET', '/api/inventory/sales')->assertOk()->json('data'));
        $this->assertCount(2, $this->api($owner, 'GET', '/api/inventory/sales', [], ['X-Branch' => (string) $a])->assertOk()->json('data'));
        $this->assertCount(1, $this->api($owner, 'GET', '/api/inventory/sales', [], ['X-Branch' => (string) $b])->assertOk()->json('data'));

        $summary = fn (array $h) => $this->api($owner, 'GET', '/api/inventory/sales/summary', [], $h)->assertOk()->json('data');
        $this->assertSame([3, 30000], [$summary([])['count'], $summary([])['total']]);
        $this->assertSame([2, 20000], [$summary(['X-Branch' => (string) $a])['count'], $summary(['X-Branch' => (string) $a])['total']]);
        $this->assertSame([1, 10000], [$summary(['X-Branch' => (string) $b])['count'], $summary(['X-Branch' => (string) $b])['total']]);
    }
}
