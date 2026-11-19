<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Services\SmsService;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * "Remove this business": the super admin removes ONE whole business (its record, owner, staff, drivers/tenants and its data in every
 * service) after typing REMOVE, their password and a reason, with a full backup written first. Every other business is untouched.
 */
class BusinessRemovalTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('local');
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);
    }

    private function api(User $as, string $method, string $uri, array $body = [], ?string $service = null)
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $req = $this->withHeader('Authorization', "Bearer {$token}");
        if ($service !== null) {
            $req = $req->withHeader('X-Service', $service);
        }

        return $req->json($method, $uri, $body);
    }

    /** A shop with a staff member, a product (and one in the Trash), a customer, a sale, a rental property and an SMS sent. */
    private function shop(string $name): array
    {
        $owner = $this->givenServices(User::factory()->create(['name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true, 'phone_number' => '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)]), 'inventory', 'rental');
        Business::forOwnerId($owner->id)->update(['name' => $name]);
        $staff = $this->givenServices(User::factory()->create(['name' => "{$name} Cashier", 'role' => 'sales_officer', 'is_active' => true, 'created_by' => $owner->id]), 'inventory');

        $product = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Mchele', 'sku' => 'MCH' . ++$this->seq, 'quantity' => 100, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 1000, 'selling_price' => 2000], 'inventory')->assertCreated()->json('data.id');
        $old = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Sukari', 'sku' => 'SUK' . ++$this->seq, 'quantity' => 1, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 1000, 'selling_price' => 2000], 'inventory')->assertCreated()->json('data.id');
        $this->api($owner, 'DELETE', "/api/inventory/products/{$old}", [], 'inventory');
        $customer = $this->api($owner, 'POST', '/api/inventory/customers', ['name' => 'Happy', 'phone' => '0711' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT)], 'inventory')->assertCreated()->json('data.id');
        $this->api($owner, 'POST', '/api/inventory/sales', [
            'customer_id' => $customer, 'payment_status' => 'paid', 'subtotal' => 2000, 'discount' => 0, 'tax' => 0, 'total' => 2000, 'paid_total' => 2000,
            'items' => [['product_id' => $product, 'quantity' => 1, 'unit_price' => 2000, 'unit_cost_snapshot' => 1000]],
        ], 'inventory')->assertCreated();
        DB::table('rental_properties')->insert(['id' => (string) \Illuminate\Support\Str::uuid(), 'owner_id' => $owner->id, 'name' => "{$name} Flats", 'created_at' => now(), 'updated_at' => now()]);
        SmsService::sendFor(Business::forOwnerId($owner->id), '0711999999', 'Habari');

        return ['owner' => $owner, 'staff' => $staff, 'business' => Business::forOwnerId($owner->id)];
    }

    /** Rows of a business in the main tables, read without any scope (Trash included). */
    private function footprint(User $owner): array
    {
        return TenantContext::withoutScope(fn () => TenantContext::withTrashed(fn () => [
            'products' => DB::table('inventory_products')->where('owner_id', $owner->id)->count(),
            'customers' => DB::table('inventory_customers')->where('owner_id', $owner->id)->count(),
            'sales' => DB::table('inventory_sales')->where('owner_id', $owner->id)->count(),
            'properties' => DB::table('rental_properties')->where('owner_id', $owner->id)->count(),
            'users' => DB::table('users')->where('id', $owner->id)->orWhere('created_by', $owner->id)->count(),
            'business' => DB::table('businesses')->where('owner_id', $owner->id)->count(),
        ]));
    }

    private function superAdmin(): User
    {
        return User::factory()->create(['name' => 'Platform Admin', 'role' => 'super_admin', 'is_active' => true]);
    }

    public function test_the_super_admin_sees_what_would_go_then_removes_the_whole_business_and_nothing_of_another(): void
    {
        $admin = $this->superAdmin();
        $masai = $this->shop('masai mitumba bora');
        $other = $this->shop('DUKA LA MAMA ASHA');
        $otherBefore = $this->footprint($other['owner']);
        $this->assertSame(2, $this->footprint($masai['owner'])['products'], 'one live, one in the Trash');

        $plan = $this->api($admin, 'GET', "/api/admin/users/{$masai['owner']->id}/business-removal")->assertOk()
            ->assertJsonPath('data.business.name', 'masai mitumba bora')->json('data');
        $this->assertMatchesRegularExpression('/^[A-HJ-NP-Z2-9]{6}$/', $plan['confirm_word'], 'a code made up for this removal');
        $this->assertEqualsCanonicalizing(['masai mitumba bora Owner', 'masai mitumba bora Cashier'], array_column($plan['users'], 'name'));
        $this->assertSame(2, $plan['tables']['inventory_products']);
        $this->assertSame(2, $plan['tables']['sms_logs'], 'the sale receipt to Happy and the text sent by hand');
        $this->assertSame(2, $this->footprint($masai['owner'])['products'], 'looking changes nothing');

        $res = $this->api($admin, 'POST', "/api/admin/users/{$masai['owner']->id}/business-removal", [
            'confirm' => $plan['confirm_word'], 'password' => 'password', 'reason' => 'Mteja ameacha huduma',
        ])->assertOk()->assertJsonPath('data.users_removed', 2)->assertJsonPath('data.reason', 'Mteja ameacha huduma');

        $this->assertSame(['products' => 0, 'customers' => 0, 'sales' => 0, 'properties' => 0, 'users' => 0, 'business' => 0], $this->footprint($masai['owner']));
        $this->assertDatabaseMissing('users', ['id' => $masai['staff']->id]);
        $this->assertSame(0, DB::table('sms_logs')->where('business_id', $masai['business']->id)->count());
        $this->assertSame(0, TenantContext::withoutScope(fn () => DB::table('inventory_sale_items')->where('owner_id', $masai['owner']->id)->count()));

        $this->assertSame($otherBefore, $this->footprint($other['owner']), 'the other business is untouched');
        $this->assertSame(2, DB::table('sms_logs')->where('business_id', $other['business']->id)->count());

        // A full backup was written first, listed with the other backups.
        $file = $res->json('data.safety_backup');
        $this->assertStringStartsWith('backups/before_removing_business_', $file);
        Storage::disk('local')->assertExists($file);
        $this->assertStringContainsString('masai mitumba bora', Storage::disk('local')->get($file));

        // Recorded with the reason.
        $this->assertTrue(DB::table('inventory_audit_log')->where('action', 'business_removed')->where('summary', 'like', '%Mteja ameacha huduma%')->exists());
    }

    public function test_it_needs_the_generated_code_the_super_admin_password_and_a_reason(): void
    {
        $admin = $this->superAdmin();
        $masai = $this->shop('masai mitumba bora');
        $url = "/api/admin/users/{$masai['owner']->id}/business-removal";
        $before = $this->footprint($masai['owner']);
        // Many tries in a row here; the route allows 5 a minute (that limit is the route's, not what this test is about).
        $this->withoutMiddleware(\Illuminate\Routing\Middleware\ThrottleRequests::class);

        // No warning opened yet: there is no code to type.
        $this->api($admin, 'POST', $url, ['confirm' => 'REMOVE', 'password' => 'password', 'reason' => 'Mteja ameacha'])->assertStatus(422)->assertJsonValidationErrors('confirm');

        $first = $this->api($admin, 'GET', $url)->assertOk()->json('data.confirm_word');
        $code = $this->api($admin, 'GET', $url)->assertOk()->json('data.confirm_word');
        if ($first !== $code) {
            $this->api($admin, 'POST', $url, ['confirm' => $first, 'password' => 'password', 'reason' => 'Mteja ameacha'])->assertStatus(422)->assertJsonValidationErrors('confirm');
        }
        $this->api($admin, 'POST', $url, ['confirm' => strtolower($code), 'password' => 'password', 'reason' => 'Mteja ameacha'])->assertStatus(422)->assertJsonValidationErrors('confirm');
        $this->api($admin, 'POST', $url, ['confirm' => 'REMOVE', 'password' => 'password', 'reason' => 'Mteja ameacha'])->assertStatus(422)->assertJsonValidationErrors('confirm');
        $this->api($admin, 'POST', $url, ['confirm' => $code, 'password' => 'wrong', 'reason' => 'Mteja ameacha'])->assertStatus(422)->assertJsonValidationErrors('password');
        $this->api($admin, 'POST', $url, ['confirm' => $code, 'password' => 'password'])->assertStatus(422)->assertJsonValidationErrors('reason');
        $this->api($admin, 'POST', $url, ['confirm' => $code, 'password' => 'password', 'reason' => 'no'])->assertStatus(422)->assertJsonValidationErrors('reason');

        // Another super admin's code does not work for this one.
        $other = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
        $this->api($other, 'POST', $url, ['confirm' => $code, 'password' => 'password', 'reason' => 'Mteja ameacha'])->assertStatus(422)->assertJsonValidationErrors('confirm');

        $this->assertSame($before, $this->footprint($masai['owner']), 'nothing removed');
        $this->assertSame([], Storage::disk('local')->allFiles('backups'));
    }

    public function test_only_the_super_admin_and_only_for_a_business_owner(): void
    {
        $admin = $this->superAdmin();
        $masai = $this->shop('masai mitumba bora');

        $this->api($masai['owner'], 'GET', "/api/admin/users/{$masai['owner']->id}/business-removal")->assertForbidden();
        $this->api($masai['owner'], 'POST', "/api/admin/users/{$masai['owner']->id}/business-removal", ['confirm' => 'REMOVE', 'password' => 'password', 'reason' => 'Mteja ameacha'])->assertForbidden();
        $this->api($admin, 'GET', "/api/admin/users/{$masai['staff']->id}/business-removal")->assertNotFound()->assertJsonPath('code', 'no_business');
        $this->api($admin, 'GET', "/api/admin/users/{$admin->id}/business-removal")->assertNotFound();
    }

    public function test_a_business_owner_cannot_be_deleted_alone_but_staff_still_can(): void
    {
        $admin = $this->superAdmin();
        $masai = $this->shop('masai mitumba bora');

        $this->api($admin, 'DELETE', "/api/admin/users/{$masai['owner']->id}")->assertStatus(422)->assertJsonPath('code', 'use_remove_business');
        $this->assertDatabaseHas('users', ['id' => $masai['owner']->id]);

        $this->api($admin, 'DELETE', "/api/admin/users/{$masai['staff']->id}")->assertOk();
        $this->assertDatabaseMissing('users', ['id' => $masai['staff']->id]);
    }

    public function test_the_super_admin_reads_every_sms_control_of_a_business_admin_in_one_place(): void
    {
        $admin = $this->superAdmin();
        $masai = $this->shop('masai mitumba bora');
        \App\Support\SmsQuota::setLimit($masai['business']->fresh(), 1000, false);

        $this->api($admin, 'GET', "/api/admin/users/{$masai['owner']->id}/sms-controls")->assertOk()
            ->assertJsonPath('data.id', $masai['business']->id)
            ->assertJsonPath('data.name', 'masai mitumba bora')
            ->assertJsonPath('data.switch.enabled', true)
            ->assertJsonPath('data.switch.confirm_word', 'ZIMA')
            ->assertJsonPath('data.usage.limit', 1000)
            ->assertJsonPath('data.usage.used', 2)
            ->assertJsonPath('data.sender.status', 'none')
            ->assertJsonPath('data.log_days', 3)
            ->assertJsonCount(2, 'data.recent');
        $this->api($admin, 'GET', "/api/admin/users/{$masai['staff']->id}/sms-controls")->assertNotFound();
        $this->api($masai['owner'], 'GET', "/api/admin/users/{$masai['owner']->id}/sms-controls")->assertForbidden();
    }

    public function test_an_applicant_never_approved_is_removed_with_its_empty_business(): void
    {
        $admin = $this->superAdmin();
        $applicant = User::factory()->create(['name' => 'samm54', 'role' => 'admin', 'is_active' => false, 'is_applicant' => true]);
        Business::ensureFor($applicant);

        $code = $this->api($admin, 'GET', "/api/admin/users/{$applicant->id}/business-removal")->assertOk()->json('data.confirm_word');
        $this->api($admin, 'POST', "/api/admin/users/{$applicant->id}/business-removal", ['confirm' => $code, 'password' => 'password', 'reason' => 'Ombi la majaribio'])->assertOk();
        // The code is used once.
        $this->api($admin, 'GET', "/api/admin/users/{$applicant->id}/business-removal")->assertNotFound();

        $this->assertDatabaseMissing('users', ['id' => $applicant->id]);
        $this->assertDatabaseMissing('businesses', ['owner_id' => $applicant->id]);
    }
}
