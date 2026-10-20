<?php

namespace App\Console\Commands;

use App\Models\Business;
use App\Services\SmsService;
use App\Support\Salon\RebookPlanner;
use App\Support\Tenancy\TenantContext;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every day: text the clients of each salon whose time for the next visit has come ("it has been 4 weeks since your
 * braiding"). The rules are in {@see RebookPlanner}; this is only the daily round.
 *
 * Safe to run any number of times. A reminder is CLAIMED in `inventory_rebook_reminders` before it is sent, so a visit
 * is texted once even if two runs overlap; a text that could not be sent gives its claim back, so tomorrow's run
 * tries again (inside the grace days). It does nothing for a salon that has not switched reminders on, whose plan has
 * ended, or whose client has no phone number or asked not to be texted. Each text goes out under that salon's own
 * sender name.
 */
class SendRebookReminders extends Command
{
    protected $signature = 'salon:remind-rebooking {--dry-run : list who would be texted, send nothing}';

    protected $description = 'Text salon clients whose time for the next visit has come';

    /** More than this in one day for one salon is a mistake (or a data import), not a day's visits. */
    private const MAX_PER_BUSINESS = 150;

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');
        $today = now()->startOfDay();
        $sent = 0;
        $found = 0;
        $salons = 0;

        $businesses = Business::withoutAccountScope()->with('owner')->get();
        foreach ($businesses as $business) {
            $owner = $business->owner;
            if ($owner === null || !$owner->is_active || !in_array('salon', $business->serviceTypes(), true) || $business->blocksAccess()) {
                continue;
            }

            // The salon's own books: its clients, its sales (never the shop's).
            // (a plain closure, not an arrow function: the counters must be shared, not copied)
            TenantContext::runAs($owner, function () use ($business, $today, $dry, &$sent, &$found, &$salons) {
                TenantContext::runInService('salon', function () use ($business, $today, $dry, &$sent, &$found, &$salons) {
                if (!RebookPlanner::settings()['enabled']) {
                    return;
                }
                $salons++;

                $count = 0;
                foreach (RebookPlanner::due($today) as $row) {
                    if (!$row['can_text']) {
                        continue;
                    }
                    if ($count >= self::MAX_PER_BUSINESS) {
                        $this->warn("{$business->name}: more than " . self::MAX_PER_BUSINESS . ' reminders today, the rest wait for tomorrow');
                        break;
                    }
                    $found++;
                    $count++;

                    if ($dry) {
                        $this->line("would text: {$business->name} -> {$row['name']} ({$row['service']}, visit {$row['visit_on']})");
                        continue;
                    }

                    // Claim it first, so two runs at the same moment cannot both send it.
                    $claimed = DB::table('inventory_rebook_reminders')->insertOrIgnore([
                        'customer_id' => $row['customer_id'],
                        'sale_id' => $row['sale_id'],
                        'visit_on' => $row['visit_on'],
                        'weeks' => $row['weeks_waited'],
                        'sent_at' => now(),
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                    if ($claimed === 0) {
                        $found--;
                        continue;
                    }

                    $text = RebookPlanner::message($row['name'], $row['service'], $row['weeks_waited'], (string) $business->name);
                    if (!SmsService::sendFor($business, $row['phone'], $text)) {
                        // Not sent: give the claim back so the next run tries again.
                        DB::table('inventory_rebook_reminders')
                            ->where('customer_id', $row['customer_id'])
                            ->where('visit_on', $row['visit_on'])
                            ->delete();
                        $this->warn("could not text {$row['name']} ({$business->name})");
                        continue;
                    }
                    $sent++;
                }
                });
            });
        }

        $this->info(($dry ? 'dry run: ' : '') . "{$found} reminder(s) for {$salons} salon(s)" . ($dry ? '' : ", {$sent} sent"));

        return self::SUCCESS;
    }
}
