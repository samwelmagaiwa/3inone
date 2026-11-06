<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * A stylist's day: the diary, the queue, their own results, attendance and asking for a day off are theirs from the start. Selling at the
 * counter and seeing what clients said about themselves start switched OFF: the owner gives them on the access-rights screen.
 */
class StylistHomeRightsTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function salon(): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => 'Neema Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0725' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => 'Glow']);

        return $owner;
    }

    private function person(User $owner, string $role, string $name): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    private function switchOn(User $owner, User $who, array $extra): void
    {
        $on = collect($this->api($owner, 'GET', "/api/admin/users/{$who->id}/access")->assertOk()->json('data.modules'))->filter(fn ($m) => $m['on'])->pluck('key')->all();
        $this->api($owner, 'PUT', "/api/admin/users/{$who->id}/access", ['on' => array_values(array_unique(array_merge($on, $extra)))])->assertOk();
    }

    private function service(User $owner): int
    {
        return (int) $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Braids', 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => 50000, 'duration_minutes' => 60])->assertCreated()->json('data.id');
    }

    public function test_a_stylist_starts_with_her_day_but_not_the_till_or_the_feedback(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'hair_stylist', 'Asha');
        $have = $this->api($asha, 'GET', '/api/auth/user')->json('data.user.effective_permissions');

        foreach (['inv_salon_appointments', 'inv_salon_walkins', 'inv_salon_stylists', 'inv_salon_team'] as $key) {
            $this->assertContains($key, $have, $key);
        }
        foreach (['inv_create_sales', 'inv_salon_feedback', 'inv_salon_money', 'inv_view_reports'] as $key) {
            $this->assertNotContains($key, $have, $key);
        }
        $svc = $this->service($owner);
        $this->api($asha, 'POST', '/api/inventory/sales', ['payment_status' => 'paid', 'subtotal' => 50000, 'discount' => 0, 'tax' => 0, 'total' => 50000, 'paid_total' => 50000, 'items' => [['product_id' => $svc, 'quantity' => 1, 'unit_price' => 50000, 'staff_id' => (string) $asha->id]]])->assertForbidden();
        $this->api($asha, 'GET', '/api/inventory/salon/feedback')->assertForbidden();
    }

    public function test_her_day_still_works_without_the_till(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'hair_stylist', 'Asha');

        $this->api($asha, 'GET', '/api/inventory/salon/appointments?date=' . now()->toDateString())->assertOk();
        $this->api($asha, 'GET', '/api/inventory/salon/queue')->assertOk();
        $this->api($asha, 'GET', '/api/inventory/salon/stylists?from=' . now()->startOfMonth()->toDateString() . '&to=' . now()->toDateString())->assertOk();
        $this->api($asha, 'GET', '/api/inventory/salon/attendance/today')->assertOk();
        $this->api($asha, 'POST', '/api/inventory/salon/attendance/clock-in')->assertSuccessful();
        // Finding a client to book works for whoever uses the diary, selling or not.
        $this->api($asha, 'GET', '/api/inventory/customers')->assertOk();
        $this->api($asha, 'GET', '/api/inventory/salon/staff')->assertOk();
    }

    public function test_the_owner_can_switch_the_till_and_the_feedback_on_for_her(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'hair_stylist', 'Asha');
        $svc = $this->service($owner);

        $this->switchOn($owner, $asha, ['inv_create_sales', 'inv_salon_feedback']);

        $this->api($asha, 'POST', '/api/inventory/sales', ['payment_status' => 'paid', 'subtotal' => 50000, 'discount' => 0, 'tax' => 0, 'total' => 50000, 'paid_total' => 50000, 'items' => [['product_id' => $svc, 'quantity' => 1, 'unit_price' => 50000, 'staff_id' => (string) $asha->id]], 'payments' => [['amount' => 50000, 'method' => 'cash']]])->assertCreated();
        $this->api($asha, 'GET', '/api/inventory/salon/feedback')->assertOk();
    }

    public function test_the_switches_are_named_and_start_off_in_the_access_screen(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'hair_stylist', 'Asha');
        $state = collect($this->api($owner, 'GET', "/api/admin/users/{$asha->id}/access")->assertOk()->json('data.modules'))->keyBy('key');

        foreach (['inv_create_sales', 'inv_salon_feedback'] as $key) {
            $this->assertTrue($state->has($key), $key);
            $this->assertFalse($state[$key]['on'], "{$key} starts off");
            $this->assertNotSame('', $state[$key]['sw']);
        }
    }

    public function test_someone_already_working_keeps_the_till_when_this_is_installed(): void
    {
        $owner = $this->salon();
        $old = $this->person($owner, 'hair_stylist', 'Old hand');
        $this->assertFalse($old->refresh()->hasInventoryPermission('inv_create_sales'));

        (require base_path('database/migrations/2026_11_24_000200_keep_selling_for_existing_stylists.php'))->up();

        $this->assertTrue($old->refresh()->hasInventoryPermission('inv_create_sales'), 'written down once, so the till is not taken away');
        $this->assertFalse($old->hasInventoryPermission('inv_salon_feedback'), 'only the till is kept');
    }

    public function test_a_stylist_asks_for_a_day_off_and_the_owner_decides(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'hair_stylist', 'Asha');
        $day = now()->addDays(3)->toDateString();

        $id = $this->api($asha, 'POST', '/api/inventory/salon/days-off/requests', ['off_on' => $day, 'reason' => 'Family'])->assertCreated()->json('data.id');

        // asking again for the same day, or for a day that has passed, is refused
        $this->api($asha, 'POST', '/api/inventory/salon/days-off/requests', ['off_on' => $day])->assertStatus(422);
        $this->api($asha, 'POST', '/api/inventory/salon/days-off/requests', ['off_on' => now()->subDay()->toDateString()])->assertStatus(422);
        // she sees her own, as waiting, and cannot decide
        $mine = $this->api($asha, 'GET', '/api/inventory/salon/days-off/requests')->assertOk()->json('data');
        $this->assertFalse($mine['can_decide']);
        $this->assertSame(['pending'], array_column($mine['requests'], 'status'));
        $this->api($asha, 'POST', "/api/inventory/salon/days-off/requests/{$id}/decision", ['decision' => 'approve'])->assertForbidden();
        // the owner is told, sees it, and approves: it becomes a day off
        $told = collect($this->api($owner, 'GET', '/api/inventory/notifications')->json('data'))->firstWhere('type', 'salon_dayoff_request');
        $this->assertNotNull($told);
        $all = $this->api($owner, 'GET', '/api/inventory/salon/days-off/requests')->assertOk()->json('data');
        $this->assertTrue($all['can_decide']);
        $this->assertSame(['Asha'], array_column($all['requests'], 'staff_name'));
        $this->api($owner, 'POST', "/api/inventory/salon/days-off/requests/{$id}/decision", ['decision' => 'approve'])->assertOk();
        $off = $this->api($owner, 'GET', '/api/inventory/salon/days-off?month=' . substr($day, 0, 7))->assertOk()->json('data');
        $this->assertContains($day, array_map(fn ($d) => substr($d['off_on'], 0, 10), $off));
        $this->assertSame(['approved'], array_column($this->api($asha, 'GET', '/api/inventory/salon/days-off/requests')->json('data.requests'), 'status'));
        // decided once
        $this->api($owner, 'POST', "/api/inventory/salon/days-off/requests/{$id}/decision", ['decision' => 'reject'])->assertStatus(422);
    }

    public function test_turning_a_request_down_makes_no_day_off(): void
    {
        $owner = $this->salon();
        $asha = $this->person($owner, 'hair_stylist', 'Asha');
        $day = now()->addDays(5)->toDateString();
        $id = $this->api($asha, 'POST', '/api/inventory/salon/days-off/requests', ['off_on' => $day])->assertCreated()->json('data.id');

        $this->api($owner, 'POST', "/api/inventory/salon/days-off/requests/{$id}/decision", ['decision' => 'reject'])->assertOk();

        $off = $this->api($owner, 'GET', '/api/inventory/salon/days-off?month=' . substr($day, 0, 7))->json('data');
        $this->assertNotContains($day, array_map(fn ($d) => substr($d['off_on'], 0, 10), $off));
        // and she may ask for that day again
        $this->api($asha, 'POST', '/api/inventory/salon/days-off/requests', ['off_on' => $day])->assertCreated();
    }

    public function test_one_salons_requests_are_not_another_salons(): void
    {
        $one = $this->salon();
        $two = $this->salon();
        $asha = $this->person($one, 'hair_stylist', 'Asha');
        $this->api($asha, 'POST', '/api/inventory/salon/days-off/requests', ['off_on' => now()->addDays(2)->toDateString()])->assertCreated();

        $this->assertSame([], $this->api($two, 'GET', '/api/inventory/salon/days-off/requests')->assertOk()->json('data.requests'));
    }
}
