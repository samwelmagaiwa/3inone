<?php

namespace App\Console\Commands;

use App\Console\Concerns\RunsPerBusiness;
use App\Models\Business;
use App\Support\Inventory\ShopTexts;
use App\Support\Salon\AppointmentPlanner;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every morning (10:00 in Tanzania): text each shop's customers who have owed for a week or more what they owe, under THAT business's own
 * sender name. A customer is reminded at most once a week, only with a phone and without having asked for no texts; at most
 * {@see ShopTexts::DEBT_REMIND_MAX} a day per business; a business can switch it off. A text that could not be sent is tried again next run.
 * One queued job per business ({@see RunsPerBusiness}).
 */
class SendShopDebtReminders extends Command
{
    use RunsPerBusiness;

    protected $signature = 'inventory:debt-reminders {--dry-run : list who would be texted, send nothing}';

    protected $description = 'Remind shop customers who have owed for a week what they owe';

    public function handle(): int
    {
        return $this->runPerBusiness('debt reminder(s)');
    }

    protected function businessService(): string
    {
        return 'inventory';
    }

    protected function businessContext(): array
    {
        return ['today' => Carbon::now(AppointmentPlanner::TIMEZONE)->toDateString()];
    }

    public function forBusiness(Business $business, array $context, bool $dry): array
    {
        $found = 0;
        $sent = 0;
        if (!ShopTexts::debtRemindersOn()) {
            return ['found' => 0, 'sent' => 0];
        }
        $today = Carbon::parse($context['today'], AppointmentPlanner::TIMEZONE)->startOfDay();

        foreach (array_slice(ShopTexts::customersDueDebtReminder($today), 0, ShopTexts::DEBT_REMIND_MAX) as $customerId) {
            $found++;
            if ($dry) {
                $this->note("would remind customer {$customerId} of {$business->name}");

                continue;
            }
            // Claim first, so two runs at the same moment cannot both text; give it back when the text fails.
            ShopTexts::markDebtReminded($customerId, $today);
            $r = ShopTexts::remindDebt($customerId);
            if ($r['sent']) {
                $sent++;
            } else {
                DB::table('inventory_settings')->where('key', 'inv_debt_reminded_' . $customerId)->delete();
            }
        }

        return ['found' => $found, 'sent' => $sent];
    }
}
