<?php

namespace Tests\Feature;

use App\Http\Controllers\API\BackupController;
use App\Jobs\CreateBackupJob;
use App\Jobs\RemoveBusinessJob;
use App\Models\Business;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Copies of the whole database are written by the queue worker, not while a request waits: the super admin's backup and the safety copy
 * before "Remove this business" (and the removal itself). The file is named at once; only the newest few of each kind are kept.
 */
class BackgroundBackupsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        Storage::fake('local');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function superAdmin(): User
    {
        return User::factory()->create(['name' => 'Platform Admin', 'role' => 'super_admin', 'is_active' => true]);
    }

    public function test_a_backup_answers_at_once_with_its_name_and_the_worker_writes_that_file(): void
    {
        $admin = $this->superAdmin();
        Queue::fake();

        $res = $this->api($admin, 'POST', '/api/auth/admin/backup')->assertOk()->assertJsonPath('data.queued', true);
        $name = $res->json('data.filename');
        $this->assertMatchesRegularExpression('/^backup_\d{4}-\d{2}-\d{2}_\d{6}_[A-Za-z0-9]{6}\.json$/', $name);
        $this->assertSame([], Storage::disk('local')->allFiles('backups'), 'nothing written while the request waited');

        $job = Queue::pushed(CreateBackupJob::class)->first();
        $this->assertSame(1, $job->tries);
        $job->handle(app(\App\Services\Inventory\AuditTrail::class));

        Storage::disk('local')->assertExists('backups/' . $name);
        $this->assertStringContainsString('Platform Admin', Storage::disk('local')->get('backups/' . $name));
        $this->assertTrue(DB::table('inventory_audit_log')->where('action', 'backup_created')->where('summary', 'like', 'Platform Admin created a system backup%')->exists());
        $this->assertSame($name, $this->api($admin, 'GET', '/api/auth/admin/backup')->json('data.backups.0.filename'));
    }

    public function test_only_the_newest_five_of_each_kind_are_kept(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-11-20 08:00:00'));
        $controller = app(BackupController::class);
        $controller->safetySnapshot('pre_restore'); // another kind: never cleared by backups
        $written = [];
        for ($i = 0; $i < 7; $i++) {
            Carbon::setTestNow(now()->addMinute());
            $file = $controller->safetySnapshot('backup')['filename'];
            touch(Storage::disk('local')->path($file), now()->getTimestamp());
            $written[] = $file;
        }
        Carbon::setTestNow();

        $left = Storage::disk('local')->files('backups');
        $backups = array_values(array_filter($left, fn ($f) => str_starts_with(basename($f), 'backup_')));
        $this->assertCount(5, $backups);
        $this->assertEqualsCanonicalizing(array_slice($written, 2), $backups, 'the two oldest went');
        $this->assertCount(1, array_filter($left, fn ($f) => str_starts_with(basename($f), 'pre_restore_')));
    }

    public function test_removing_a_business_answers_at_once_and_the_worker_does_it_after_the_safety_copy(): void
    {
        $admin = $this->superAdmin();
        $owner = $this->givenServices(User::factory()->create(['name' => 'masai Owner', 'role' => 'admin', 'is_active' => true]), 'inventory');
        Business::forOwnerId($owner->id)->update(['name' => 'masai mitumba bora']);
        $url = "/api/admin/users/{$owner->id}/business-removal";
        $code = $this->api($admin, 'GET', $url)->assertOk()->json('data.confirm_word');

        Queue::fake();
        $res = $this->api($admin, 'POST', $url, ['confirm' => $code, 'password' => 'password', 'reason' => 'Mteja ameacha huduma'])
            ->assertStatus(202)->assertJsonPath('data.queued', true)->assertJsonPath('data.business.name', 'masai mitumba bora');

        $this->assertDatabaseHas('businesses', ['owner_id' => $owner->id]);
        $this->assertDatabaseHas('users', ['id' => $owner->id]);
        $job = Queue::pushed(RemoveBusinessJob::class)->first();
        $this->assertSame($res->json('data.safety_backup'), $job->snapshot);
        $this->assertSame('Mteja ameacha huduma', $job->reason);

        $job->handle(app(\App\Services\Inventory\AuditTrail::class));

        Storage::disk('local')->assertExists($job->snapshot);
        $this->assertDatabaseMissing('businesses', ['owner_id' => $owner->id]);
        $this->assertDatabaseMissing('users', ['id' => $owner->id]);
        $this->assertTrue(DB::table('inventory_audit_log')->where('action', 'business_removed')->where('summary', 'like', '%Platform Admin (super admin) REMOVED the business "masai mitumba bora"%Mteja ameacha huduma%')->exists());

        // A job for a business already gone does nothing.
        $job->handle(app(\App\Services\Inventory\AuditTrail::class));
    }
}
