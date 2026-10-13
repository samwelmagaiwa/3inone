<?php

namespace Tests\Feature;

use App\Models\Rental\Property;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Backup and restore of the whole system.
 *
 * Before this, the backup listed table names by hand and silently skipped every one that
 * did not exist -- so most Transport and Rental data was never in it -- the app called a
 * route that did not exist, and any `full_access` user could overwrite any table.
 */
class BackupRestoreTest extends TestCase
{
    use RefreshDatabase;

    private User $super;

    private User $owner;

    protected function setUp(): void
    {
        parent::setUp();

        Storage::fake('local'); // never write backups into the real storage folder

        $this->super = User::factory()->create(['role' => 'super_admin', 'is_active' => true]);
        $this->owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'name' => 'Asha Owner']), 'inventory', 'rental', 'transport');
    }

    private function as(User $user, string $method, string $uri, array $body = [], array $files = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        // call() (needed for file uploads) ignores withHeader(); the token goes in as a server variable.
        return $this->call($method, $uri, $body, [], $files, [
            'HTTP_AUTHORIZATION' => "Bearer {$token}",
            'HTTP_ACCEPT' => 'application/json',
        ]);
    }

    /** A little of everything: a vehicle, a property, a product -- one per service. */
    private function seedBusinessData(): void
    {
        DB::table('devices')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid(), 'created_by' => $this->owner->id, 'name' => 'Bajaji One', 'type' => 'bajaji',
            'plate_number' => 'BKP-001', 'is_active' => 1, 'created_at' => now(), 'updated_at' => now(),
        ]);
        Property::create(['owner_id' => $this->owner->id, 'name' => 'Asha Plaza']);
        TenantContext::runAs($this->owner, fn () => DB::table('inventory_products')->insert([
            'name' => 'Backup Soda', 'sku' => 'BKP-SODA', 'cost_price' => 500, 'selling_price' => 800, 'unit' => 'bottle',
            'quantity' => 10, 'min_stock' => 1, 'status' => 'active', 'created_at' => now(), 'updated_at' => now(),
        ]));
    }

    private function backup(): string
    {
        $filename = $this->as($this->super, 'POST', '/api/auth/admin/backup')->assertOk()->json('data.filename');
        $this->assertNotEmpty($filename);

        return $filename;
    }

    private function snapshot(string $filename): array
    {
        return json_decode(Storage::disk('local')->get("backups/{$filename}"), true, 512, JSON_THROW_ON_ERROR);
    }

    private function restore(string $filename, array $extra = [])
    {
        return $this->as($this->super, 'POST', '/api/auth/admin/restore', ['filename' => $filename, 'confirm' => 'RESTORE'] + $extra);
    }

    // ------------------------------------------------------------ who may

    public function test_only_the_super_admin_may_back_up_or_restore_not_even_full_access_staff(): void
    {
        $fullAccess = User::factory()->create(['role' => 'admin', 'is_active' => true, 'full_access' => true]);
        $filename = $this->backup();

        foreach ([$this->owner, $fullAccess] as $who) {
            $this->as($who, 'GET', '/api/auth/admin/backup')->assertForbidden();
            $this->as($who, 'POST', '/api/auth/admin/backup')->assertForbidden();
            $this->as($who, 'POST', '/api/auth/admin/restore', ['filename' => $filename, 'confirm' => 'RESTORE'])->assertForbidden();
        }
        $this->app['auth']->forgetGuards();
        $this->postJson('/api/auth/admin/backup')->assertUnauthorized();
    }

    // ------------------------------------------------------ what it holds

    public function test_a_backup_holds_every_table_so_nothing_can_be_forgotten(): void
    {
        $this->seedBusinessData();

        $data = $this->snapshot($this->backup());

        $this->assertSame('2.0', $data['version']);
        // The tables the old hand-written list never even named.
        foreach (['users', 'devices', 'rental_properties', 'inventory_products', 'user_services'] as $table) {
            $this->assertArrayHasKey($table, $data['tables'], "{$table} is in the backup");
        }
        $this->assertSame(['Backup Soda'], array_column($data['tables']['inventory_products'], 'name'));
        $this->assertSame(['Asha Plaza'], array_column($data['tables']['rental_properties'], 'name'));
        $this->assertSame(['Bajaji One'], array_column($data['tables']['devices'], 'name'));

        // The strongest guarantee: EVERY table that exists (and is not a temporary or secret one) is covered.
        $excluded = ['migrations', 'cache', 'cache_locks', 'sessions', 'jobs', 'job_batches', 'failed_jobs',
            'personal_access_tokens', 'password_reset_tokens', 'password_reset_codes', 'sms_codes'];
        foreach (array_column(Schema::getTables(), 'name') as $table) {
            if (in_array($table, $excluded, true) || str_starts_with($table, 'sqlite_') || !Schema::hasColumn($table, 'id')) {
                continue;
            }
            $this->assertArrayHasKey($table, $data['tables'], "the table {$table} is missing from the backup");
        }
    }

    public function test_secrets_and_sessions_are_never_in_a_backup(): void
    {
        $this->owner->createToken('phone');
        DB::table('sms_codes')->insert(['user_id' => $this->owner->id, 'purpose' => 'password_reset', 'code_hash' => 'x', 'expires_at' => now()->addMinutes(5), 'created_at' => now(), 'updated_at' => now()]);

        $data = $this->snapshot($this->backup());

        foreach (['personal_access_tokens', 'sms_codes', 'password_reset_codes', 'sessions', 'cache', 'jobs', 'migrations'] as $table) {
            $this->assertArrayNotHasKey($table, $data['tables'], "{$table} must not be backed up");
        }
    }

    public function test_the_backup_is_listed_with_its_date_and_size(): void
    {
        $filename = $this->backup();

        $list = $this->as($this->super, 'GET', '/api/auth/admin/backup')->assertOk()->json('data');

        $this->assertSame(1, $list['total']);
        $this->assertSame($filename, $list['backups'][0]['filename']);
        $this->assertGreaterThan(0, $list['backups'][0]['size_bytes']);
        $this->assertSame('backup', $list['backups'][0]['kind']);
    }

    // ---------------------------------------------------------- restoring

    public function test_a_restore_brings_back_changed_and_deleted_rows_but_deletes_nothing(): void
    {
        $this->seedBusinessData();
        $filename = $this->backup();

        // After the backup: a name is changed, a vehicle is deleted, a new property is added.
        Property::query()->withoutGlobalScopes()->where('name', 'Asha Plaza')->update(['name' => 'Renamed By Mistake']);
        DB::table('devices')->delete();
        TenantContext::runAs($this->owner, fn () => DB::table('inventory_products')->update(['name' => 'Wrongly Edited']));
        Property::create(['owner_id' => $this->owner->id, 'name' => 'Built After The Backup']);

        $this->restore($filename)->assertOk()->assertJsonPath('success', true);

        $this->assertTrue(Property::withoutGlobalScopes()->where('owner_id', $this->owner->id)->where('name', 'Asha Plaza')->exists(), 'the changed name came back');
        $this->assertFalse(Property::withoutGlobalScopes()->where('name', 'Renamed By Mistake')->exists(), 'and the wrong one is gone');
        $this->assertSame(1, DB::table('devices')->count(), 'the deleted vehicle came back');
        $this->assertSame('Backup Soda', TenantContext::withoutScope(fn () => DB::table('inventory_products')->value('name')), 'inventory restores too');
        $this->assertTrue(Property::withoutGlobalScopes()->where('name', 'Built After The Backup')->exists(), 'a restore never deletes what was added since');
    }

    public function test_a_restore_must_be_confirmed_and_must_name_a_backup(): void
    {
        $filename = $this->backup();

        $this->as($this->super, 'POST', '/api/auth/admin/restore', ['filename' => $filename])->assertStatus(422);                       // no confirm
        $this->as($this->super, 'POST', '/api/auth/admin/restore', ['filename' => $filename, 'confirm' => 'yes'])->assertStatus(422);    // wrong word
        $this->as($this->super, 'POST', '/api/auth/admin/restore', ['confirm' => 'RESTORE'])->assertStatus(422);                         // no backup
        $this->as($this->super, 'POST', '/api/auth/admin/restore', ['filename' => '../../.env', 'confirm' => 'RESTORE'])->assertStatus(422); // path trick
        $this->as($this->super, 'POST', '/api/auth/admin/restore', ['filename' => 'nope.json', 'confirm' => 'RESTORE'])->assertNotFound();
    }

    public function test_a_restore_first_keeps_a_snapshot_of_what_is_there_now(): void
    {
        $this->seedBusinessData();
        $filename = $this->backup();
        Property::create(['owner_id' => $this->owner->id, 'name' => 'Only In The Present']);

        $response = $this->restore($filename)->assertOk();

        $safety = $response->json('data.safety_snapshot');
        $this->assertStringStartsWith('pre_restore_', $safety);
        $names = array_column($this->snapshot($safety)['tables']['rental_properties'], 'name');
        $this->assertContains('Only In The Present', $names, 'the state before the restore can itself be restored');
    }

    public function test_a_restore_ignores_tables_that_must_never_be_restored(): void
    {
        $upload = UploadedFile::fake()->createWithContent('evil.json', json_encode([
            'version' => '2.0', 'created_at' => now()->toISOString(),
            'tables' => [
                'personal_access_tokens' => [['id' => 999, 'tokenable_type' => 'App\\Models\\User', 'tokenable_id' => $this->super->id, 'name' => 'x', 'token' => str_repeat('a', 64), 'abilities' => '["*"]', 'created_at' => now()->toDateTimeString(), 'updated_at' => now()->toDateTimeString()]],
                'not_a_real_table' => [['id' => 1, 'x' => 'y']],
            ],
        ]));

        $response = $this->as($this->super, 'POST', '/api/auth/admin/restore', ['confirm' => 'RESTORE'], ['backup_file' => $upload])->assertOk();

        $this->assertFalse(DB::table('personal_access_tokens')->where('id', 999)->exists(), 'no login token can be smuggled in');
        $this->assertArrayHasKey('personal_access_tokens', $response->json('data.skipped_tables'));
        $this->assertArrayHasKey('not_a_real_table', $response->json('data.skipped_tables'));
        $this->assertSame(0, $response->json('data.restored_tables'), $response->getContent());
    }

    public function test_a_failing_restore_changes_nothing_at_all(): void
    {
        $upload = UploadedFile::fake()->createWithContent('broken.json', json_encode([
            'version' => '2.0', 'created_at' => now()->toISOString(),
            'tables' => [
                // This one is fine and comes first...
                'users' => [array_merge($this->owner->only(['id', 'email', 'role', 'is_active']), ['name' => 'Changed By Restore', 'password' => $this->owner->password])],
                // ...this one breaks (a product must have a name): the whole restore is undone.
                'inventory_products' => [['id' => 777, 'name' => null, 'sku' => 'BAD', 'cost_price' => 1, 'selling_price' => 2]],
            ],
        ]));

        $this->as($this->super, 'POST', '/api/auth/admin/restore', ['confirm' => 'RESTORE'], ['backup_file' => $upload])->assertStatus(500);

        $this->assertSame('Asha Owner', $this->owner->fresh()->name, 'the user change was rolled back with the rest');
    }

    public function test_foreign_key_checking_is_back_on_after_a_restore(): void
    {
        if (DB::getDriverName() !== 'sqlite') {
            $this->markTestSkipped('Checked on SQLite only.');
        }
        $this->seedBusinessData();
        $filename = $this->backup();

        $this->restore($filename)->assertOk();

        $this->assertSame(1, (int) DB::selectOne('PRAGMA foreign_keys')->foreign_keys);
    }

    public function test_a_business_still_cannot_use_bulk_writes_on_its_own_inventory(): void
    {
        // The restore may upsert inventory rows only because it runs as the platform; a business may not.
        $this->expectException(\LogicException::class);

        TenantContext::runAs($this->owner, fn () => DB::table('inventory_products')->upsert(
            [['id' => 1, 'name' => 'X', 'sku' => 'X']], ['id'], ['name']
        ));
    }
}
