<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** What is wrong is said in plain words, in both languages, by the name of the field, and says what to do. */
class FriendlyValidationTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0728000009']), 'inventory');
    }

    private function api(string $method, string $uri, array $body = [])
    {
        $token = $this->owner->createToken('t')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'inventory')->json($method, $uri, $body);
    }

    public function test_a_missing_field_is_named_as_a_person_says_it(): void
    {
        $r = $this->api('POST', '/api/inventory/products', ['name' => 'Rice'])->assertStatus(422);

        $msg = $r->json('message');
        $this->assertStringNotContainsString('selling_price', $msg);
        $this->assertStringNotContainsString('field is required', $msg);
        $this->assertStringContainsString(' / ', $msg, 'both languages');
        $this->assertNotEmpty($r->json('errors'));
    }

    public function test_the_message_is_the_first_problem_not_and_n_more_errors(): void
    {
        $r = $this->api('POST', '/api/inventory/products', [])->assertStatus(422);

        $this->assertStringNotContainsString('more error', $r->json('message'));
    }

    public function test_a_controllers_own_english_error_becomes_a_clear_two_language_sentence(): void
    {
        $r = $this->api('GET', '/api/inventory/products/999999');

        $this->assertStringContainsString(' / ', (string) $r->json('message'));
    }

    public function test_rules_read_well(): void
    {
        $m = fn (string $a, string $rule, array $p, string $t, $v = null) => \App\Support\FriendlyMessages::rule($a, $rule, $p, $t, $v);

        $this->assertSame('Andika bei ya kuuza. / Enter the selling price.', $m('selling_price', 'required', [], 'string'));
        $this->assertSame('Chagua mteja. / Choose the customer.', $m('customer_id', 'required', [], 'string'));
        $this->assertSame('Mstari 2: Idadi haiwezi kuwa chini ya 1. / Line 2: The quantity cannot be less than 1.', $m('items.1.quantity', 'min', ['1'], 'numeric'));
        $this->assertStringContainsString("SKU 'A1' tayari inatumika", $m('sku', 'unique', [], 'string', 'A1'));
    }
}
