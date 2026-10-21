<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** A super admin opens the salon from the service picker: every page answers (a business-less account must not get "not found"). */
class SalonSuperAdminViewTest extends TestCase
{
    use RefreshDatabase;

    public function test_every_salon_page_answers_for_a_super_admin(): void
    {
        $owner = $this->givenServices(User::factory()->create(['name' => 'Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0728000001']), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => 'Glow']);
        $super = User::factory()->create(['name' => 'Super', 'role' => 'super_admin', 'is_active' => true, 'full_access' => true, 'phone_number' => '0728000002']);
        $token = $super->createToken('test')->plainTextToken;

        $failures = [];
        foreach ([
            'settings', 'loyalty/settings', 'branches', 'branch-stock', 'branch-stock/transfers', 'cashbook', 'analytics', 'queue', 'equipment', 'feedback',
            'vouchers', 'campaigns', 'overview', 'profit-loss', 'payroll', 'stylists', 'appointments', 'reports', 'staff', 'rebook/due', 'shifts', 'attendance/today',
        ] as $path) {
            $this->app['auth']->forgetGuards();
            $this->flushHeaders();
            $res = $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json('GET', "/api/inventory/salon/{$path}");
            if (!in_array($res->status(), [200, 403], true)) {
                $failures[] = "{$path}: {$res->status()} " . substr((string) $res->getContent(), 0, 120);
            }
        }

        $this->assertSame([], $failures, implode("\n", $failures));
    }
}
