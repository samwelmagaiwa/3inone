<?php

namespace Tests\Feature;

use App\Console\Commands\SendShopDailySummary;
use App\Console\Commands\SendShopDebtReminders;
use App\Jobs\RunBusinessTaskJob;
use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Queue;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * The nightly commands no longer go through every business in one long run: each queues ONE job per business it is for, and the queue
 * workers share them out. The job does exactly that business's work, as that business; one that no longer qualifies is skipped.
 */
class NightlyJobsPerBusinessTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function setUp(): void
    {
        parent::setUp();
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);
        Carbon::setTestNow(Carbon::parse('2026-11-20 23:59:00', 'Africa/Dar_es_Salaam')->utc());
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function shop(string $name, string $service = 'inventory', bool $active = true, ?string $phone = 'auto'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => $active,
            'phone_number' => $phone === 'auto' ? '0726' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT) : $phone,
        ]), $service);
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    public function test_the_command_queues_one_job_per_business_it_is_for_and_sends_nothing_itself(): void
    {
        $a = $this->shop('Asha Shop');
        $b = $this->shop('Baraka Shop');
        $this->shop('Glow Salon', 'salon');                 // another service: not this command's
        $this->shop('Closed Shop', 'inventory', false);    // owner switched off
        $this->shop('No Phone Shop', 'inventory', true, ''); // a summary needs the owner's phone

        Queue::fake();
        $this->artisan('inventory:daily-summary')->expectsOutputToContain('2 business(es) queued')->assertSuccessful();

        $this->assertCount(0, $this->sms->sent, 'the command itself sends nothing');
        $jobs = Queue::pushed(RunBusinessTaskJob::class);
        $this->assertCount(2, $jobs);
        $this->assertEqualsCanonicalizing(
            [Business::forOwnerId($a->id)->id, Business::forOwnerId($b->id)->id],
            $jobs->map(fn ($j) => $j->businessId)->all()
        );
        $this->assertSame(SendShopDailySummary::class, $jobs->first()->command);
        $this->assertSame(1, $jobs->first()->tries, 'never retried: no text twice');
        $this->assertSame('nightly', $jobs->first()->queue, 'behind the till texts, never in front of them');
        // The moment is fixed when the command starts, so a job that runs after midnight still reports the day that ended.
        $this->assertStringStartsWith('2026-11-20T23:59:00', $jobs->first()->context['now']);

        // A worker runs them: each owner gets their own night summary.
        $jobs->each(fn ($j) => $j->handle());
        $this->assertCount(1, $this->sms->to((string) $a->phone_number));
        $this->assertCount(1, $this->sms->to((string) $b->phone_number));
        $this->assertStringContainsString('Leo Asha Shop', $this->sms->to((string) $a->phone_number)[0]['message']);
    }

    public function test_a_job_for_a_business_that_no_longer_qualifies_does_nothing(): void
    {
        $a = $this->shop('Asha Shop');

        Queue::fake();
        $this->artisan('inventory:daily-summary')->assertSuccessful();
        $job = Queue::pushed(RunBusinessTaskJob::class)->first();

        $a->update(['is_active' => false]); // switched off between the queueing and the running
        $job->handle();

        $this->assertCount(0, $this->sms->sent);
    }

    public function test_a_dry_run_still_runs_here_and_prints_without_queueing_or_sending(): void
    {
        $this->shop('Asha Shop');

        Queue::fake();
        $this->artisan('inventory:daily-summary', ['--dry-run' => true])
            ->expectsOutputToContain('would text Asha Shop')
            ->expectsOutputToContain('dry run: 1 summary(ies)')
            ->assertSuccessful();

        Queue::assertNothingPushed();
        $this->assertCount(0, $this->sms->sent);
    }

    public function test_every_nightly_command_that_goes_through_the_businesses_queues_per_business(): void
    {
        $this->shop('Asha Shop');
        $this->shop('Glow Salon', 'salon');

        Queue::fake();
        foreach (['inventory:debt-reminders', 'inventory:low-stock', 'inventory:daily-summary', 'inventory:month-close', 'salon:daily-summary', 'salon:remind-rebooking', 'salon:remind-appointments', 'salon:birthday-offers'] as $command) {
            $this->artisan($command)->expectsOutputToContain('1 business(es) queued')->assertSuccessful();
        }
        $this->assertCount(8, Queue::pushed(RunBusinessTaskJob::class));
        $this->assertContains(SendShopDebtReminders::class, Queue::pushed(RunBusinessTaskJob::class)->map(fn ($j) => $j->command)->all());
    }
}
