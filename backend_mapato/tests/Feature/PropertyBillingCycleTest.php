<?php

namespace Tests\Feature;

use App\Http\Requests\StorePropertyRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

/**
 * Creating a property must not fail with "Kipindi cha kodi kinahitajika" just because a screen did not
 * send billing_cycle, or sent it under the name the properties list used to use.
 */
class PropertyBillingCycleTest extends TestCase
{
    use RefreshDatabase;

    private function validated(array $input): array
    {
        $request = StorePropertyRequest::create('/api/rental/properties', 'POST', $input + [
            'name' => 'Mabibo House',
            'property_type' => 'rental_compound',
            'region' => 'Dar es Salaam',
            'district' => 'Ubungo',
            'address' => 'mabibo road',
        ]);
        $user = User::factory()->create();
        $request->setContainer(app())->setRedirector(app('redirect'));
        $request->setUserResolver(fn () => $user);
        $request->validateResolved();

        return $request->validated();
    }

    public function test_billing_cycle_defaults_to_monthly_when_the_app_does_not_send_it(): void
    {
        $this->assertSame('monthly', $this->validated([])['billing_cycle']);
    }

    public function test_older_field_names_are_accepted(): void
    {
        $data = $this->validated([
            'default_billing_cycle' => 'quarterly',
            'total_blocks' => 3,
            'default_currency' => 'USD',
        ]);

        $this->assertSame('quarterly', $data['billing_cycle']);
        $this->assertEquals(3, $data['number_of_blocks']);
        $this->assertSame('USD', $data['currency']);
    }

    public function test_a_sent_billing_cycle_wins_and_is_still_checked(): void
    {
        $this->assertSame('yearly', $this->validated(['billing_cycle' => 'yearly', 'default_billing_cycle' => 'monthly'])['billing_cycle']);

        $this->expectException(ValidationException::class);
        $this->validated(['billing_cycle' => 'weekly']);
    }

    public function test_place_is_kept(): void
    {
        $this->assertSame('Mabibo Hostel', $this->validated(['place' => 'Mabibo Hostel'])['place']);
    }
}
