<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The super admin's lists read a page at a time and filter on the server, so they keep working with thousands of accounts: Users &
 * access (role group, status, the numbers at the top) and the Users SMS counter.
 */
class AdminListsPagingTest extends TestCase
{
    use RefreshDatabase;

    private function api(User $as, string $uri)
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->getJson($uri);
    }

    private function people(): User
    {
        $super = User::factory()->create(['name' => 'Platform', 'role' => 'super_admin', 'is_active' => true]);
        foreach (['Asha', 'Baraka', 'Chausiku'] as $i => $n) {
            $owner = $this->givenServices(User::factory()->create(['name' => "{$n} Owner", 'role' => 'admin', 'is_active' => true]), 'inventory');
            Business::forOwnerId($owner->id)->update(['name' => "{$n} Shop"]);
            User::factory()->create(['name' => "{$n} Cashier", 'role' => 'sales_officer', 'is_active' => $i !== 2, 'created_by' => $owner->id]);
        }

        return $super;
    }

    public function test_users_are_read_a_page_at_a_time_with_the_numbers_for_the_top_of_the_screen(): void
    {
        $super = $this->people();

        $res = $this->api($super, '/api/admin/users?page=1&limit=2&with_counts=1')->assertOk();
        $this->assertCount(2, $res->json('data.users'));
        $this->assertSame(7, $res->json('data.pagination.total'));
        $this->assertTrue($res->json('data.pagination.has_more_pages'));
        $this->assertSame(['total' => 7, 'active' => 6, 'owners' => 3, 'super' => 1], $res->json('data.counts'));

        $last = $this->api($super, '/api/admin/users?page=4&limit=2')->assertOk();
        $this->assertCount(1, $last->json('data.users'));
        $this->assertFalse($last->json('data.pagination.has_more_pages'));
        $this->assertNull($last->json('data.counts'), 'counted only when asked');
    }

    public function test_users_are_filtered_by_role_group_status_and_search_on_the_server(): void
    {
        $super = $this->people();
        $names = fn (string $q) => collect($this->api($super, "/api/admin/users?limit=50&{$q}")->assertOk()->json('data.users'))->pluck('name')->sort()->values()->all();

        $this->assertSame(['Asha Owner', 'Baraka Owner', 'Chausiku Owner'], $names('role_group=owners'));
        $this->assertSame(['Platform'], $names('role_group=super'));
        $this->assertSame(['Asha Cashier', 'Baraka Cashier', 'Chausiku Cashier'], $names('role_group=staff'));
        $this->assertSame(['Chausiku Cashier'], $names('role_group=staff&status=off'));
        $this->assertSame(['Baraka Cashier', 'Baraka Owner'], $names('q=baraka'));
        // The numbers stay those of everyone, whatever the filter.
        $this->assertSame(7, $this->api($super, '/api/admin/users?q=baraka&with_counts=1')->json('data.counts.total'));
    }

    public function test_a_page_never_holds_more_than_500_people(): void
    {
        $super = $this->people();

        $this->assertSame(500, $this->api($super, '/api/admin/users?limit=100000')->assertOk()->json('data.pagination.limit'));
    }

    public function test_the_sms_counter_list_is_read_a_page_at_a_time(): void
    {
        $super = $this->people();

        $first = $this->api($super, '/api/admin/sms-usage?per_page=2')->assertOk();
        $this->assertSame(['Asha Shop', 'Baraka Shop'], collect($first->json('data'))->pluck('name')->all());
        $this->assertTrue($first->json('meta.pagination.has_more_pages'));
        $this->assertSame(3, $first->json('meta.pagination.total'));

        $second = $this->api($super, '/api/admin/sms-usage?per_page=2&page=2')->assertOk();
        $this->assertSame(['Chausiku Shop'], collect($second->json('data'))->pluck('name')->all());
        $this->assertFalse($second->json('meta.pagination.has_more_pages'));

        $this->assertSame(100, $this->api($super, '/api/admin/sms-usage?per_page=5000')->json('meta.pagination.per_page'));
    }
}
