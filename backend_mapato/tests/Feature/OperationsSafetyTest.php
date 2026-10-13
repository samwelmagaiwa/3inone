<?php

namespace Tests\Feature;

use App\Logging\BusinessContextProcessor;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Monolog\Level;
use Monolog\LogRecord;
use Tests\TestCase;

/**
 * Smaller operational safeguards: log lines that say which business they belong to, a loud
 * warning if service enforcement is left off in production, and the new indexes.
 */
class OperationsSafetyTest extends TestCase
{
    use RefreshDatabase;

    private function record(): LogRecord
    {
        return new LogRecord(new \DateTimeImmutable(), 'app', Level::Info, 'something happened');
    }

    public function test_log_lines_in_a_signed_in_request_carry_the_business_and_user(): void
    {
        $owner = User::factory()->create(['role' => 'admin', 'is_active' => true]);
        $staff = User::factory()->create(['role' => 'manager', 'is_active' => true, 'created_by' => $owner->id]);

        $this->actingAs($staff);
        $extra = (new BusinessContextProcessor())($this->record())->extra;

        $this->assertSame((string) $staff->id, $extra['user_id']);
        $this->assertSame((string) $owner->id, $extra['business_id'], 'staff are logged under their business, not their own id');
    }

    public function test_log_lines_outside_a_request_are_left_alone(): void
    {
        $extra = (new BusinessContextProcessor())($this->record())->extra;

        $this->assertArrayNotHasKey('business_id', $extra);
        $this->assertArrayNotHasKey('user_id', $extra);
    }

    public function test_the_file_log_channels_use_the_business_context(): void
    {
        foreach (['single', 'daily'] as $channel) {
            $this->assertContains(\App\Logging\AddBusinessContext::class, config("logging.channels.{$channel}.tap"), $channel);
        }
    }

    public function test_leaving_service_enforcement_off_in_production_is_logged_as_critical(): void
    {
        config(['tenancy.enforce_services' => false]);
        $this->app['env'] = 'production';
        Log::spy();

        (new \App\Providers\TenancyServiceProvider($this->app))->boot();

        Log::shouldHaveReceived('critical')->withArgs(fn ($message) => str_contains((string) $message, 'SERVICE_ENFORCEMENT is OFF'))->once();
    }

    public function test_no_warning_when_enforcement_is_on_or_when_not_in_production(): void
    {
        Log::spy();

        (new \App\Providers\TenancyServiceProvider($this->app))->boot(); // testing env, enforcement on
        config(['tenancy.enforce_services' => false]);
        (new \App\Providers\TenancyServiceProvider($this->app))->boot(); // off, but not production

        Log::shouldNotHaveReceived('critical');
    }

    public function test_report_files_in_public_storage_cannot_be_guessed(): void
    {
        $first = \App\Services\ReportService::reportFilename('driver_summary');
        $second = \App\Services\ReportService::reportFilename('driver_summary');

        // Type, the time to the second (all anyone could guess), then 24 random characters.
        $this->assertMatchesRegularExpression('/^report_driver_summary_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_[A-Za-z0-9]{24}\.html$/', $first);
        $this->assertNotSame($first, $second, 'two reports in the same second still get different names');
        $this->assertMatchesRegularExpression('/^report_[a-z0-9_]+_\d{4}/', \App\Services\ReportService::reportFilename('../../etc/passwd'), 'the type cannot smuggle in a path');
        $this->assertStringNotContainsString('/', \App\Services\ReportService::reportFilename('../../etc/passwd'));
    }

    public function test_the_busy_inventory_tables_have_their_business_date_indexes(): void
    {
        foreach ([
            'inventory_sales' => 'inv_sales_owner_created_idx',
            'inventory_stock_movements' => 'inv_stock_mov_owner_created_idx',
            'inventory_expenses' => 'inv_expenses_owner_created_idx',
            'inventory_customers' => 'inv_customers_owner_name_idx',
        ] as $table => $index) {
            $this->assertTrue(Schema::hasIndex($table, $index), "{$table} should have {$index}");
        }
    }
}
