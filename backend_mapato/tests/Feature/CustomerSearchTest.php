<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The customer search the till uses: every word typed must be found (in any order), a phone is found however it is written, and a list
 * for picking comes by name and long enough to scroll.
 */
class CustomerSearchTest extends TestCase
{
    use RefreshDatabase;

    private function owner(): User
    {
        $owner = $this->givenServices(User::factory()->create(['name' => 'Neema Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0723000001']), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => 'Glow']);

        return $owner;
    }

    private function fetch(User $as, string $uri)
    {
        $token = $as->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json('GET', $uri);
    }

    private function names(User $as, string $query): array
    {
        return array_column($this->fetch($as, '/api/inventory/customers?' . $query)->assertOk()->json('data'), 'name');
    }

    private function scene(): User
    {
        $owner = $this->owner();
        foreach ([['Ali Juma', '0712 345 678'], ['Juma Hamisi', '0755111222'], ['Neema Joseph', '+255713999888'], ['Zawadi Mussa', '0788000999']] as [$name, $phone]) {
            $token = $owner->createToken('t')->plainTextToken;
            $this->app['auth']->forgetGuards();
            $this->flushHeaders();
            $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json('POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone ?? ''])->assertSuccessful();
        }

        return $owner;
    }

    public function test_every_word_is_found_in_any_order(): void
    {
        $owner = $this->scene();

        $this->assertEqualsCanonicalizing(['Ali Juma'], $this->names($owner, 'q=juma+ali'));
        $this->assertEqualsCanonicalizing(['Ali Juma', 'Juma Hamisi'], $this->names($owner, 'q=juma'));
        $this->assertSame([], $this->names($owner, 'q=juma+zawadi'));
    }

    public function test_a_phone_is_found_however_it_is_written(): void
    {
        $owner = $this->scene();

        $this->assertSame(['Ali Juma'], $this->names($owner, 'q=0712345678'));
        $this->assertSame(['Ali Juma'], $this->names($owner, 'q=%2B255712345678'));
        $this->assertSame(['Ali Juma'], $this->names($owner, 'q=712345678'));
        $this->assertSame(['Neema Joseph'], $this->names($owner, 'q=0713999888'));
        $this->assertSame(['Juma Hamisi'], $this->names($owner, 'q=755111'));
    }

    public function test_the_list_for_picking_comes_by_name_and_the_old_order_is_kept_otherwise(): void
    {
        $owner = $this->scene();

        $this->assertSame(['Ali Juma', 'Juma Hamisi', 'Neema Joseph', 'Zawadi Mussa'], $this->names($owner, 'sort=name&per_page=60'));
        $this->assertSame('Zawadi Mussa', $this->names($owner, '')[0], 'newest first, as before');
        $this->assertCount(2, $this->fetch($owner, '/api/inventory/customers?per_page=2')->json('data'));
        $this->assertSame(100, $this->fetch($owner, '/api/inventory/customers?per_page=9999')->json('meta.per_page'));
    }
}
