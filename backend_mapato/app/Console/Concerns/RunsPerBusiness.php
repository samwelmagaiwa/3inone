<?php

namespace App\Console\Concerns;

use App\Jobs\RunBusinessTaskJob;
use App\Models\Business;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Facades\Log;

/**
 * A nightly command that does the same work for every business (texts, summaries, the month's close), one business at a time.
 *
 * It used to go through every business in ONE process, sending as it went: with hundreds of businesses the 10:00 reminders could take
 * hours and hold up the jobs after them. Now the command only picks the businesses the work is for and queues ONE job per business
 * ({@see RunBusinessTaskJob}); the queue workers share them out, so one slow business (or a slow SMS provider) never holds up the others.
 *
 *   --dry-run   still runs here, at once, and prints what would happen (nothing is queued or sent)
 *
 * The command says which service the work is in, what it carries along (a day, a month: fixed when the command starts, so a job that runs
 * a little later still works on that day), whether the owner needs a phone, and the work for ONE business, run as that business.
 */
trait RunsPerBusiness
{
    /** 'inventory' or 'salon': the books the work reads. */
    abstract protected function businessService(): string;

    /** What every business's job carries (plain values only: it is stored with the queued job). @return array<string, mixed> */
    abstract protected function businessContext(): array;

    /**
     * The work for one business, run as its owner in {@see businessService()}. Returns what it found and sent, for the dry run's line.
     *
     * @param  array<string, mixed>  $context
     * @return array{found: int, sent: int}
     */
    abstract public function forBusiness(Business $business, array $context, bool $dry): array;

    /** Only owners with a phone (texts to the owner). */
    protected function needsOwnerPhone(): bool
    {
        return false;
    }

    /** The command's whole run: queue a job per business, or (dry run) do them all here and print. */
    protected function runPerBusiness(string $what): int
    {
        $dry = (bool) $this->option('dry-run');
        $context = $this->businessContext();
        $found = 0;
        $sent = 0;
        $queued = 0;

        Business::withoutAccountScope()->with('owner')->orderBy('id')->chunk(200, function ($businesses) use ($dry, $context, &$found, &$sent, &$queued) {
            foreach ($businesses as $business) {
                if (!$this->qualifies($business)) {
                    continue;
                }
                if ($dry) {
                    $r = $this->runForBusiness($business, $context, true);
                    $found += $r['found'];
                    $sent += $r['sent'];

                    continue;
                }
                RunBusinessTaskJob::dispatch(static::class, (string) $business->id, $context);
                $queued++;
            }
        });

        $this->info($dry ? "dry run: {$found} {$what}" : "{$queued} business(es) queued for {$what}");

        return self::SUCCESS;
    }

    /** Is the work for this business at all (an active owner, the service, not held back for payment, a phone when needed)? */
    public function qualifies(Business $business): bool
    {
        $owner = $business->owner;

        return $owner !== null
            && $owner->is_active
            && in_array($this->businessService(), $business->serviceTypes(), true)
            && !$business->blocksAccess()
            && (!$this->needsOwnerPhone() || trim((string) $owner->phone_number) !== '');
    }

    /**
     * One business, as that business, in this command's service.
     *
     * @param  array<string, mixed>  $context
     * @return array{found: int, sent: int}
     */
    public function runForBusiness(Business $business, array $context, bool $dry): array
    {
        return TenantContext::runAs($business->owner, fn () => TenantContext::runInService(
            $this->businessService(),
            fn () => $this->forBusiness($business, $context, $dry),
        ));
    }

    /** A line for whoever runs the command; in a queued job there is no one, so it goes to the log. */
    protected function note(string $line, bool $problem = false): void
    {
        if (isset($this->output)) {
            $problem ? $this->warn($line) : $this->line($line);
        } elseif ($problem) {
            Log::warning(static::class . ': ' . $line);
        }
    }
}
