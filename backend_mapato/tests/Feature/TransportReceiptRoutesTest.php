<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * /api/admin/receipts/{receiptId} takes a number. "stats" and "search" are routes of their own, but they were
 * declared AFTER the `{receiptId}` route, which took them for a receipt id: the controller asks for an int and the
 * answer was a 500 (a TypeError) on both.
 */
class TransportReceiptRoutesTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->admin = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'transport');
    }

    private function asAdmin(string $uri)
    {
        $token = $this->admin->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->getJson($uri);
    }

    public function test_receipt_stats_is_answered(): void
    {
        $this->asAdmin('/api/admin/receipts/stats')->assertOk();
    }

    public function test_receipt_search_is_answered(): void
    {
        $this->asAdmin('/api/admin/receipts/search?q=RCP')->assertOk();
    }

    public function test_search_without_a_query_is_a_validation_error_not_a_crash(): void
    {
        $this->asAdmin('/api/admin/receipts/search')->assertStatus(422);
    }

    public function test_an_id_that_is_not_a_number_is_not_found_not_a_crash(): void
    {
        $this->asAdmin('/api/admin/receipts/not-a-number')->assertNotFound();
        $this->asAdmin('/api/admin/receipts/not-a-number/preview')->assertNotFound();
    }

    public function test_the_other_receipt_routes_still_work(): void
    {
        $this->asAdmin('/api/admin/receipts/pending')->assertOk();
        $this->asAdmin('/api/admin/receipts')->assertOk();
    }

    public function test_a_numeric_id_still_reaches_the_preview(): void
    {
        $status = $this->asAdmin('/api/admin/receipts/999999')->getStatusCode();
        $this->assertContains($status, [200, 404], 'a receipt that does not exist is "not found", never a server error');
        $this->assertNotSame(500, $this->asAdmin('/api/admin/receipts/999999/preview')->getStatusCode());
    }
}
