<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\BusinessRegistration;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The business is a real record: its name, address, TIN, logo and contact, plus the plan and
 * paid-until date. Created with its owner, filled from the registration form, edited by the owner
 * (never its billing), and visible to everyone who works for it and to nobody else.
 */
class BusinessRecordTest extends TestCase
{
    use RefreshDatabase;

    /** A 1x1 PNG. */
    private const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

    private function superAdmin(): User
    {
        return User::factory()->create(['role' => 'super_admin', 'is_active' => true, 'name' => 'Platform Admin']);
    }

    private function owner(string $name, string $role = 'admin', array $extra = []): User
    {
        return $this->givenServices(User::factory()->create(array_merge([
            'name' => $name, 'role' => $role, 'is_active' => true,
        ], $extra)), 'transport', 'rental', 'inventory');
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function unscoped(callable $fn)
    {
        return TenantContext::withoutScope($fn);
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'Asha Owner', 'business_name' => 'Asha Rentals', 'email' => 'asha@example.test',
            'phone_number' => '0743519100', 'password' => 'secret-pass-1', 'password_confirmation' => 'secret-pass-1',
            'requested_services' => ['rental', 'inventory'],
            // Asking for inventory means saying what kind of stock business it is.
            'inventory_type' => 'retail',
            'region' => 'Dar es Salaam', 'district' => 'Kinondoni', 'address' => 'Mikocheni B',
        ], $overrides);
    }

    private function register(array $overrides = []): BusinessRegistration
    {
        $payload = $this->payload($overrides);
        $this->postJson('/api/auth/register', $payload)->assertCreated();
        $this->postJson('/api/auth/register/verify-phone', [
            'email' => $payload['email'], 'code' => $this->sms->lastCodeFor($payload['phone_number']) ?? '000000',
        ])->assertOk();

        return BusinessRegistration::whereHas('user', fn ($q) => $q->where('email', $payload['email']))->firstOrFail();
    }

    private function approve(BusinessRegistration $registration, array $extra = [])
    {
        return $this->as($this->superAdmin(), 'POST', "/api/admin/registrations/{$registration->id}/approve",
            array_merge(['service_types' => ['rental', 'inventory']], $extra));
    }

    /** A real file on disk (not Laravel's fake), so validation sniffs its actual content. */
    private function realFile(string $name, string $content): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'logo');
        file_put_contents($path, $content);

        return new UploadedFile($path, $name, null, null, true);
    }

    private function businessOf(User $owner): ?Business
    {
        return Business::forOwnerId($owner->id);
    }

    // ------------------------------------------------------- it exists

    public function test_every_account_head_has_a_business_record_from_the_moment_it_exists(): void
    {
        // ('administrator' is also a head role in the code, but MySQL's users.role enum has no such value, so
        // no such account can exist there.)
        foreach (['admin', 'landlord'] as $role) {
            $head = User::factory()->create(['role' => $role, 'name' => "{$role} head", 'phone_number' => '0711000100', 'email' => "{$role}@example.test"]);

            $business = $this->businessOf($head);
            $this->assertNotNull($business, "{$role} has a business");
            $this->assertSame("{$role} head", $business->name);
            $this->assertSame('0711000100', $business->phone);
            $this->assertSame("{$role}@example.test", $business->email);
            $this->assertSame('free', $business->plan, 'a business nobody put on a plan has no limits');
            $this->assertNull($business->valid_until);
        }
    }

    public function test_staff_drivers_tenants_and_super_admins_have_no_business_of_their_own(): void
    {
        $owner = $this->owner('Owner');
        foreach (['manager', 'sales_officer', 'driver', 'tenant', 'caretaker', 'super_admin'] as $role) {
            $person = User::factory()->create(['role' => $role, 'created_by' => $owner->id]);
            $this->assertNull($this->businessOf($person), "{$role} is not a business");
        }

        $this->assertSame(1, Business::withoutAccountScope()->count(), 'only the owner');
    }

    public function test_promoting_someone_to_owner_gives_them_a_business_and_saving_again_adds_nothing(): void
    {
        $person = User::factory()->create(['role' => 'manager']);
        $this->assertNull($this->businessOf($person));

        $person->update(['role' => 'admin']);
        $this->assertNotNull($this->businessOf($person));

        $person->update(['name' => 'Renamed']);
        $this->assertSame(1, Business::withoutAccountScope()->where('owner_id', $person->id)->count());
    }

    public function test_a_business_record_is_one_per_owner(): void
    {
        $owner = $this->owner('Owner');

        $this->expectException(\Illuminate\Database\QueryException::class);
        DB::table('businesses')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(), 'owner_id' => $owner->id, 'name' => 'Twin',
            'plan' => 'free', 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    // ------------------------------------------------- registration + approval

    public function test_registering_fills_the_business_record_from_the_form(): void
    {
        $registration = $this->register();
        $business = $this->businessOf($registration->user);

        $this->assertSame('Asha Rentals', $business->name);
        $this->assertSame('Mikocheni B, Kinondoni, Dar es Salaam', $business->address);
        $this->assertSame('0743519100', $business->phone);
        $this->assertSame('asha@example.test', $business->email);
        $this->assertSame('retail', $business->inventory_type, 'the kind of stock business chosen on the form lands on the record');

        // The super admin reviews the same record.
        $row = $this->as($this->superAdmin(), 'GET', "/api/admin/registrations/{$registration->id}")->assertOk()->json('data.business');
        $this->assertSame('Asha Rentals', $row['name']);
    }

    public function test_approval_starts_a_trial_that_ends_after_the_configured_days(): void
    {
        $this->travelTo(now()->setDate(2026, 10, 15)->setTime(10, 0));
        config(['billing.trial_days' => 30]);

        $registration = $this->register();
        $this->approve($registration)->assertOk()->assertJsonPath('data.business.billing.plan', 'trial');

        $business = $this->businessOf($registration->user);
        $this->assertSame('trial', $business->plan);
        $this->assertSame('2026-11-14 23:59:59', $business->valid_until->format('Y-m-d H:i:s'), 'works through the end of the 30th day');
    }

    public function test_approval_can_choose_the_plan_and_the_date_or_no_date(): void
    {
        $paid = $this->register();
        $this->approve($paid, ['plan' => 'standard', 'valid_until' => '2027-03-31'])->assertOk();
        $this->assertSame('standard', $this->businessOf($paid->user)->plan);
        $this->assertSame('2027-03-31 23:59:59', $this->businessOf($paid->user)->valid_until->format('Y-m-d H:i:s'));

        $forever = $this->register(['email' => 'two@example.test', 'phone_number' => '0755000002']);
        $this->approve($forever, ['plan' => 'free'])->assertOk();
        $this->assertSame('free', $this->businessOf($forever->user)->plan);
        $this->assertNull($this->businessOf($forever->user)->valid_until, 'a free plan does not expire');

        $bad = $this->register(['email' => 'three@example.test', 'phone_number' => '0755000003']);
        $this->approve($bad, ['plan' => 'platinum-deluxe'])->assertStatus(422)->assertJsonValidationErrors('plan');
        $this->assertFalse($bad->fresh()->user->is_active, 'a refused approval changes nothing');
    }

    // ----------------------------------------------------------- reading it

    public function test_everyone_who_works_for_a_business_reads_it_and_nobody_else_does(): void
    {
        $alpha = $this->owner('Alpha');
        $bravo = $this->owner('Bravo');
        $this->businessOf($alpha)->update(['address' => 'Alpha Street', 'tin' => '111-111-111']);
        $staff = User::factory()->create(['role' => 'manager', 'created_by' => $alpha->id, 'is_active' => true]);
        $driver = User::factory()->create(['role' => 'driver', 'created_by' => $alpha->id, 'is_active' => true]);

        foreach ([$alpha, $staff, $driver] as $person) {
            $this->as($person, 'GET', '/api/business')->assertOk()
                ->assertJsonPath('data.name', 'Alpha')
                ->assertJsonPath('data.address', 'Alpha Street')
                ->assertJsonPath('data.tin', '111-111-111')
                ->assertJsonPath('data.billing.plan', 'free');
        }

        $this->as($bravo, 'GET', '/api/business')->assertOk()->assertJsonPath('data.name', 'Bravo');
        $this->as($this->superAdmin(), 'GET', '/api/business')->assertNotFound()->assertJsonPath('errors.code', 'no_business');
        $this->flushHeaders(); // the calls above carried a token
        $this->app['auth']->forgetGuards();
        $this->getJson('/api/business')->assertUnauthorized();
    }

    public function test_the_business_model_is_scoped_like_every_other_record(): void
    {
        $alpha = $this->owner('Alpha');
        $this->owner('Bravo');

        Sanctum::actingAs($alpha);
        $this->assertSame(['Alpha'], Business::query()->pluck('name')->all());
        $this->assertSame(1, Business::query()->count());
    }

    public function test_sign_in_and_the_user_endpoint_carry_the_business(): void
    {
        $owner = $this->owner('Alpha Traders', 'admin', ['phone_number' => '0722000001', 'password' => 'owner-pass-1']);
        $this->businessOf($owner)->update(['tin' => '222-222-222']);

        $this->postJson('/api/auth/login', ['email' => $owner->email, 'password' => 'owner-pass-1', 'phone_number' => '0722000001'])
            ->assertOk()
            ->assertJsonPath('data.user.business.name', 'Alpha Traders')
            ->assertJsonPath('data.user.business.tin', '222-222-222')
            ->assertJsonPath('data.user.business.billing.plan', 'free');

        $this->as($owner, 'GET', '/api/auth/user')->assertOk()->assertJsonPath('data.user.business.name', 'Alpha Traders');
    }

    // ---------------------------------------------------------- editing it

    public function test_the_owner_edits_the_profile_and_the_tin_is_tidied(): void
    {
        $owner = $this->owner('Alpha');

        $this->as($owner, 'PUT', '/api/business', [
            'name' => 'Alpha Traders Ltd', 'address' => 'Kariakoo, Dar', 'tin' => '123456789',
            'phone' => '0712345678', 'email' => 'info@alpha.example',
        ])->assertOk()->assertJsonPath('data.name', 'Alpha Traders Ltd')->assertJsonPath('data.tin', '123-456-789');

        $business = $this->businessOf($owner);
        $this->assertSame('Kariakoo, Dar', $business->address);
        $this->assertSame('0712345678', $business->phone);
        $this->assertSame('info@alpha.example', $business->email);

        // A partial edit leaves the rest alone; clearing a field clears it.
        $this->as($owner, 'PUT', '/api/business', ['tin' => '987 654 321', 'address' => null])->assertOk()->assertJsonPath('data.tin', '987-654-321');
        $business->refresh();
        $this->assertSame('Alpha Traders Ltd', $business->name);
        $this->assertNull($business->address);
    }

    public function test_a_bad_tin_phone_or_empty_name_is_refused_with_a_clear_message(): void
    {
        $owner = $this->owner('Alpha');

        $this->as($owner, 'PUT', '/api/business', ['tin' => '12-34'])->assertStatus(422)->assertJsonValidationErrors('tin');
        $this->as($owner, 'PUT', '/api/business', ['tin' => 'ABCDEFGHI'])->assertStatus(422)->assertJsonValidationErrors('tin');
        $this->as($owner, 'PUT', '/api/business', ['phone' => 'call me'])->assertStatus(422)->assertJsonValidationErrors('phone');
        $this->as($owner, 'PUT', '/api/business', ['email' => 'not-an-email'])->assertStatus(422)->assertJsonValidationErrors('email');
        $this->as($owner, 'PUT', '/api/business', ['name' => ''])->assertStatus(422)->assertJsonValidationErrors('name');

        $this->assertSame('Alpha', $this->businessOf($owner)->name, 'nothing was saved');
    }

    public function test_only_the_owner_can_edit_and_the_owner_can_never_touch_billing(): void
    {
        $owner = $this->owner('Alpha');
        $staff = User::factory()->create(['role' => 'manager', 'created_by' => $owner->id, 'is_active' => true]);

        $this->as($staff, 'PUT', '/api/business', ['name' => 'Hijacked'])->assertForbidden()->assertJsonPath('errors.code', 'owner_only');
        $this->as($this->superAdmin(), 'PUT', '/api/business', ['name' => 'Nope'])->assertForbidden();

        // The owner's own billing fields are simply not editable by them.
        $this->as($owner, 'PUT', '/api/business', ['name' => 'Alpha 2', 'plan' => 'premium', 'valid_until' => '2099-01-01'])->assertOk();
        $business = $this->businessOf($owner);
        $this->assertSame('Alpha 2', $business->name);
        $this->assertSame('free', $business->plan);
        $this->assertNull($business->valid_until);
    }

    public function test_one_business_cannot_be_edited_through_another(): void
    {
        $alpha = $this->owner('Alpha');
        $bravo = $this->owner('Bravo');

        $this->as($alpha, 'PUT', '/api/business', ['name' => 'Alpha Changed'])->assertOk();

        $this->assertSame('Alpha Changed', $this->businessOf($alpha)->name);
        $this->assertSame('Bravo', $this->businessOf($bravo)->name);
    }

    // ----------------------------------------------------------------- logo

    public function test_the_owner_uploads_replaces_and_removes_the_logo(): void
    {
        Storage::fake('public');
        $owner = $this->owner('Alpha');
        $png = fn (string $name) => UploadedFile::fake()->createWithContent($name, base64_decode(self::PNG));

        $first = $this->as($owner, 'POST', '/api/business/logo', ['logo' => $png('a.png')])->assertOk()->json('data.logo_url');
        $path1 = $this->businessOf($owner)->logo_path;
        $this->assertStringStartsWith('business_logos/', $path1);
        $this->assertStringContainsString('/api/files/public/' . $path1, $first);
        Storage::disk('public')->assertExists($path1);

        // Replacing deletes the old file, so logos do not pile up.
        $this->as($owner, 'POST', '/api/business/logo', ['logo' => $png('b.png')])->assertOk();
        $path2 = $this->businessOf($owner)->logo_path;
        $this->assertNotSame($path1, $path2);
        Storage::disk('public')->assertMissing($path1);
        Storage::disk('public')->assertExists($path2);

        $this->as($owner, 'DELETE', '/api/business/logo')->assertOk()->assertJsonPath('data.logo_url', null);
        Storage::disk('public')->assertMissing($path2);
        $this->assertNull($this->businessOf($owner)->logo_path);
    }

    public function test_the_logo_must_be_a_small_picture_and_only_the_owner_may_set_it(): void
    {
        Storage::fake('public');
        $owner = $this->owner('Alpha');
        $staff = User::factory()->create(['role' => 'manager', 'created_by' => $owner->id, 'is_active' => true]);

        // Real files, so the server really looks at what is inside (the fake ones report a type from their name).
        $this->as($owner, 'POST', '/api/business/logo', ['logo' => $this->realFile('x.png', '<?php echo 1;')])->assertStatus(422);
        $this->as($owner, 'POST', '/api/business/logo', ['logo' => $this->realFile('x.svg', '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')])->assertStatus(422);
        $this->as($owner, 'POST', '/api/business/logo', ['logo' => $this->realFile('big.png', base64_decode(self::PNG) . str_repeat("\0", 3 * 1024 * 1024))])->assertStatus(422);
        $this->as($staff, 'POST', '/api/business/logo', ['logo' => UploadedFile::fake()->createWithContent('a.png', base64_decode(self::PNG))])->assertForbidden();

        $this->assertNull($this->businessOf($owner)->logo_path);
        $this->assertSame([], Storage::disk('public')->allFiles('business_logos'));
    }

    // -------------------------------------------------------- super admin

    public function test_the_super_admin_lists_searches_and_filters_every_business(): void
    {
        $super = $this->superAdmin();
        $a = $this->owner('Alpha Traders', 'admin', ['email' => 'alpha@example.test']);
        $b = $this->owner('Bravo Rentals', 'landlord', ['email' => 'bravo@example.test']);
        $this->businessOf($a)->update(['plan' => 'basic', 'valid_until' => now()->subDays(3)]);
        $this->businessOf($b)->update(['plan' => 'standard', 'valid_until' => now()->addDays(5)]);
        User::factory()->create(['role' => 'manager', 'created_by' => $a->id]);

        $all = $this->as($super, 'GET', '/api/admin/businesses')->assertOk();
        $this->assertSame(['Alpha Traders', 'Bravo Rentals'], collect($all->json('data'))->pluck('name')->all());
        $this->assertSame(2, $all->json('meta.counts.total'));
        $this->assertSame(1, $all->json('meta.counts.expired'));
        $this->assertSame(1, $all->json('meta.counts.expiring'));
        $this->assertSame(config('billing.plans'), $all->json('meta.plans'));

        $row = collect($all->json('data'))->firstWhere('name', 'Alpha Traders');
        $this->assertSame('alpha@example.test', $row['owner']['email']);
        $this->assertEqualsCanonicalizing(['transport', 'rental', 'inventory'], $row['services']);
        $this->assertSame(1, $row['staff_count']);
        $this->assertTrue($row['billing']['is_expired']);

        $names = fn ($r) => collect($r->json('data'))->pluck('name')->all();
        $this->assertSame(['Alpha Traders'], $names($this->as($super, 'GET', '/api/admin/businesses?status=expired')));
        $this->assertSame(['Bravo Rentals'], $names($this->as($super, 'GET', '/api/admin/businesses?status=expiring')));
        $this->assertSame(['Bravo Rentals'], $names($this->as($super, 'GET', '/api/admin/businesses?plan=standard')));
        $this->assertSame(['Bravo Rentals'], $names($this->as($super, 'GET', '/api/admin/businesses?q=bravo@example')));
        $this->assertSame([], $names($this->as($super, 'GET', '/api/admin/businesses?status=no_expiry')));
    }

    public function test_only_a_super_admin_reaches_the_business_admin_endpoints(): void
    {
        $owner = $this->owner('Alpha');
        $id = $this->businessOf($owner)->id;

        $this->as($owner, 'GET', '/api/admin/businesses')->assertForbidden();
        $this->as($owner, 'GET', "/api/admin/businesses/{$id}")->assertForbidden();
        $this->as($owner, 'PUT', "/api/admin/businesses/{$id}", ['plan' => 'premium'])->assertForbidden();
        $this->assertSame('free', $this->businessOf($owner)->plan);
    }

    public function test_the_super_admin_sets_plan_and_valid_until_and_it_is_recorded(): void
    {
        $super = $this->superAdmin();
        $owner = $this->owner('Alpha');
        $id = $this->businessOf($owner)->id;

        $this->as($super, 'PUT', "/api/admin/businesses/{$id}", ['plan' => 'premium', 'valid_until' => '2027-06-30', 'tin' => '123456789'])
            ->assertOk()
            ->assertJsonPath('data.billing.plan', 'premium')
            ->assertJsonPath('data.tin', '123-456-789');

        $business = $this->businessOf($owner);
        $this->assertSame('2027-06-30 23:59:59', $business->valid_until->format('Y-m-d H:i:s'));

        $log = $this->unscoped(fn () => DB::table('inventory_audit_log')->where('entity_type', 'business')->where('action', 'billing_changed')->first());
        $this->assertNotNull($log, 'who changed whose plan, and when, is on record');
        $this->assertStringContainsString('premium', (string) $log->summary);

        // null clears the date (never expires); a plan that does not exist is refused.
        $this->as($super, 'PUT', "/api/admin/businesses/{$id}", ['valid_until' => null])->assertOk()->assertJsonPath('data.billing.days_left', null);
        $this->assertNull($this->businessOf($owner)->valid_until);
        $this->as($super, 'PUT', "/api/admin/businesses/{$id}", ['plan' => 'gold'])->assertStatus(422)->assertJsonValidationErrors('plan');
        $this->as($super, 'GET', "/api/admin/businesses/{$id}")->assertOk()->assertJsonPath('data.owner.name', 'Alpha');
    }

    // -------------------------------------------------------- the backfill

    public function test_the_backfill_gives_existing_owners_a_record_without_changing_anyones_access(): void
    {
        $registered = $this->owner('Mama Duka Owner');
        BusinessRegistration::create([
            'user_id' => $registered->id, 'business_name' => 'Mama Duka', 'requested_services' => ['inventory'],
            'address' => 'Mikocheni', 'district' => 'Kinondoni', 'region' => 'Dar', 'status' => 'approved',
        ]);
        $plain = $this->owner('Old Landlord', 'landlord');
        User::factory()->create(['role' => 'manager', 'created_by' => $plain->id]);

        // As if the table had just been added to a database that already had owners.
        DB::table('businesses')->delete();
        $this->assertSame(0, DB::table('businesses')->count());

        $migration = require database_path('migrations/2026_10_15_000300_backfill_businesses.php');
        $migration->up();

        $this->assertSame(2, DB::table('businesses')->count(), 'one per owner, none for staff');
        $mama = $this->businessOf($registered);
        $this->assertSame('Mama Duka', $mama->name, 'the registration form wins');
        $this->assertSame('Mikocheni, Kinondoni, Dar', $mama->address);
        $this->assertSame('Old Landlord', $this->businessOf($plain)->name);
        foreach ([$mama, $this->businessOf($plain)] as $business) {
            $this->assertSame('free', $business->plan);
            $this->assertNull($business->valid_until, 'nobody is put on a clock by the upgrade');
        }

        $migration->up(); // again
        $this->assertSame(2, DB::table('businesses')->count(), 'running it twice adds nothing');
    }

    // ------------------------------------------- the depot says who it is

    public function test_a_new_depot_starts_with_the_businesss_own_name_and_details(): void
    {
        $owner = User::factory()->create(['role' => 'admin', 'is_active' => true, 'name' => 'Mama Duka', 'phone_number' => '0711555000', 'email' => 'duka@example.test']);
        $this->businessOf($owner)->update(['address' => 'Sinza', 'tin' => '555-555-555']);
        $this->givenServices($owner, 'inventory');

        $settings = $this->as($owner, 'GET', '/api/inventory/settings')->assertOk()->json('data');
        $this->assertSame('Mama Duka', $settings['depot_name']);
        $this->assertSame('0711555000', $settings['depot_phone']);
        $this->assertSame('Sinza', $settings['depot_address']);
        $this->assertSame('555-555-555', $settings['receipt_tin']);
        $this->assertSame('duka@example.test', $settings['receipt_email']);
    }

    public function test_editing_the_business_updates_the_depot_receipt_unless_the_owner_customised_it(): void
    {
        $owner = $this->owner('Alpha', 'admin', ['phone_number' => '0711000111']);
        $this->as($owner, 'PUT', '/api/business', ['name' => 'Alpha Traders', 'address' => 'Kariakoo'])->assertOk();

        $read = fn () => $this->as($owner, 'GET', '/api/inventory/settings')->json('data');
        $this->assertSame('Alpha Traders', $read()['depot_name'], 'still what the business said, so it follows');
        $this->assertSame('Kariakoo', $read()['depot_address']);

        // The owner types a receipt heading of their own: from then on it is theirs.
        $this->as($owner, 'PUT', '/api/inventory/settings', ['depot_name' => 'ALPHA DRINKS DEPOT'])->assertOk();
        $this->as($owner, 'PUT', '/api/business', ['name' => 'Alpha Group', 'address' => 'Upanga'])->assertOk();

        $this->assertSame('ALPHA DRINKS DEPOT', $read()['depot_name'], 'a custom heading is never overwritten');
        $this->assertSame('Upanga', $read()['depot_address'], 'the rest still follows');
    }

    public function test_another_business_never_sees_or_changes_a_depots_receipt_settings(): void
    {
        $alpha = $this->owner('Alpha');
        $bravo = $this->owner('Bravo');

        $this->as($alpha, 'PUT', '/api/business', ['name' => 'Alpha Traders'])->assertOk();

        $this->assertSame('Bravo', $this->as($bravo, 'GET', '/api/inventory/settings')->json('data.depot_name'));
    }
}
