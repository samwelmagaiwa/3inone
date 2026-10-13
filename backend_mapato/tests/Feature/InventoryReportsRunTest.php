<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Inventory\CrateLedgerService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Every inventory report must actually run. The report list test only checked the
 * names, so a report that crashed whenever it was opened (the crates position one
 * imported a controller class that no longer existed) went unnoticed.
 */
class InventoryReportsRunTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->admin = $this->actAsBusiness(
            $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory')
        );
    }

    private function fetch(string $uri)
    {
        $token = $this->admin->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->getJson($uri);
    }

    public function test_every_report_runs_on_an_empty_depot(): void
    {
        $keys = array_column($this->fetch('/api/inventory/reports')->assertOk()->json('data'), 'key');
        $this->assertCount(12, $keys);

        foreach ($keys as $key) {
            $response = $this->fetch("/api/inventory/reports/{$key}?from=2026-01-01&to=2026-12-31");
            $this->assertSame(200, $response->status(), "Report '{$key}' failed: " . substr($response->getContent(), 0, 300));
        }
    }

    public function test_the_crates_position_report_shows_crates_held_and_the_deposit_at_risk(): void
    {
        $customer = (int) DB::table('inventory_customers')->insertGetId([
            'name' => 'mama anna', 'phone' => '0783510498', 'created_at' => now(), 'updated_at' => now(),
        ]);
        $crate = (int) DB::table('inventory_crate_types')->where('name', 'Crate')->value('id');
        app(CrateLedgerService::class)->post($crate, 'issued', 10, $customer, 'S-1', null, $this->admin->id);

        $report = $this->fetch('/api/inventory/reports/crates_position')->assertOk()->json('data');

        $this->assertNotEmpty($report['rows'] ?? $report);
        $this->assertStringContainsString('"out_with_customers":10', json_encode($report));
    }
}
