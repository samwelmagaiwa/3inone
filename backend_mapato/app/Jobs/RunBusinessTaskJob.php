<?php

namespace App\Jobs;

use App\Models\Business;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;

/**
 * One business's share of a nightly command (its debt reminders, its night summary, its month close ...), run by a queue worker.
 * See {@see \App\Console\Concerns\RunsPerBusiness}. The command's own code does the work, as that business ({@see TenantContext::runAs()}
 * inside runForBusiness), so nothing about what is sent changes; only who runs it and when.
 *
 * Tried once only: each command claims a text before sending and gives the claim back when it fails, so a failure is simply picked up
 * by the next day's run, and a customer is never texted twice.
 */
class RunBusinessTaskJob implements ShouldQueue
{
    use Queueable;

    public int $tries = 1;

    /** One business's texts, at the provider's timeout each, stay well inside this. */
    public int $timeout = 600;

    /**
     * @param  class-string  $command
     * @param  array<string, mixed>  $context
     */
    public function __construct(public string $command, public string $businessId, public array $context)
    {
        // Their own queue: the workers take the till's texts (the "default" queue) first, so a receipt never waits behind
        // hundreds of nightly jobs.
        $this->onQueue('nightly');
    }

    public function handle(): void
    {
        $business = Business::withoutAccountScope()->with('owner')->find($this->businessId);
        if ($business === null) {
            return;
        }

        $command = app($this->command);
        // Checked again: the owner may have been switched off, or the business held back, since the command queued it.
        if (!$command->qualifies($business)) {
            return;
        }

        $command->runForBusiness($business, $this->context, false);
    }
}
