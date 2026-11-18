<?php

namespace App\Console\Commands;

use App\Models\Business;
use App\Support\Inventory\ShopTexts;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Console\Command;

/**
 * Every morning (10:00 in Tanzania): text each shop's customers who have owed for a week or more what they owe, under THAT business's own
 * sender name. A customer is reminded at most once a week, only with a phone and without having asked for no texts; at most
 * {@see ShopTexts::DEBT_REMIND_MAX} a day per business; a business can switch it off. A text that could not be sent is tried again next run.
 */
class SendShopDebtReminders extends Command
{
    protected $signature = 'inventory:debt-reminders {--dry-run : list who would be texted, send nothing}';

    protected $description = 'Remind shop customers who have owed for a week what they owe';

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');
        $today = Carbon::now(AppointmentPlanner::TIMEZONE)->startOfDay();
        $sent = 0;
        $found = 0;

        foreach (Business::withoutAccountScope()->with('owner')->get() as $business) {
            $owner = $business->owner;
            if ($owner === null || !$owner->is_active || !in_array('inventory', $business->serviceTypes(), true) || $business->blocksAccess()) {
                continue;
            }

            TenantContext::runAs($owner, function () use ($business, $today, $dry, &$sent, &$found) {
                TenantContext::runInService('inventory', function () use ($business, $today, $dry, &$sent, &$found) {
                    if (!ShopTexts::debtRemindersOn()) {
                        return;
                    }
                    foreach (array_slice(ShopTexts::customersDueDebtReminder($today), 0, ShopTexts::DEBT_REMIND_MAX) as $customerId) {
                        $found++;
                        if ($dry) {
                            $this->line("would remind customer {$customerId} of {$business->name}");

                            continue;
                        }
                        // Claim first, so two runs at the same moment cannot both text; give it back when the text fails.
                        ShopTexts::markDebtReminded($customerId, $today);
                        $r = ShopTexts::remindDebt($customerId);
                        if ($r['sent']) {
                            $sent++;
                        } else {
                            \Illuminate\Support\Facades\DB::table('inventory_settings')->where('key', 'inv_debt_reminded_' . $customerId)->delete();
                        }
                    }
                });
            });
        }

        $this->info(($dry ? 'dry run: ' : '') . "{$found} customer(s) due" . ($dry ? '' : ", {$sent} texted"));

        return self::SUCCESS;
    }
}
