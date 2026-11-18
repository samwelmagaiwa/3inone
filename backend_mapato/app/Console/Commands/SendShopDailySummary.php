<?php

namespace App\Console\Commands;

use App\Models\Business;
use App\Services\SmsService;
use App\Support\Inventory\ShopTexts;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every night, just before the day turns (23:59 in Tanzania): text each shop or depot owner how the day went and how it compares with
 * yesterday. Only for businesses with the shop service, whose plan has not ended, whose owner has a phone number and who have not switched
 * it off; sent under THAT business's own sender name, naming it as registered. Running it twice in a day texts once (the day is claimed
 * first), and a text that could not be sent gives the claim back.
 */
class SendShopDailySummary extends Command
{
    protected $signature = 'inventory:daily-summary {--dry-run : show what would be sent, send nothing}';

    protected $description = 'Text each shop owner how the day went';

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');
        $now = Carbon::now(AppointmentPlanner::TIMEZONE);
        $sent = 0;
        $found = 0;

        foreach (Business::withoutAccountScope()->with('owner')->get() as $business) {
            $owner = $business->owner;
            if ($owner === null || !$owner->is_active || !in_array('inventory', $business->serviceTypes(), true) || $business->blocksAccess()) {
                continue;
            }
            $phone = trim((string) $owner->phone_number);
            if ($phone === '') {
                continue;
            }

            // (plain closures, not arrow functions: the counters must be shared, not copied)
            TenantContext::runAs($owner, function () use ($business, $phone, $now, $dry, &$sent, &$found) {
                TenantContext::runInService('inventory', function () use ($business, $phone, $now, $dry, &$sent, &$found) {
                    if (!ShopTexts::summaryOn()) {
                        return;
                    }
                    $found++;
                    $text = ShopTexts::summaryMessage(
                        (string) $business->name,
                        ShopTexts::dayFigures($now, AppointmentPlanner::TIMEZONE),
                        ShopTexts::dayFigures($now->copy()->subDay(), AppointmentPlanner::TIMEZONE),
                    );
                    if ($dry) {
                        $this->line("would text {$business->name}: {$text}");

                        return;
                    }

                    // Claim the day first, so a second run the same day sends nothing.
                    $today = $now->toDateString();
                    if (DB::table('inventory_settings')->where('key', 'inv_daily_summary_last')->value('value') === $today) {
                        $found--;

                        return;
                    }
                    DB::table('inventory_settings')->updateOrInsert(['key' => 'inv_daily_summary_last'], ['value' => $today, 'updated_at' => now()]);
                    if (!SmsService::sendFor($business, $phone, $text)) {
                        DB::table('inventory_settings')->where('key', 'inv_daily_summary_last')->delete();
                        $this->warn("could not text {$business->name}");

                        return;
                    }
                    $sent++;
                });
            });
        }

        $this->info(($dry ? 'dry run: ' : '') . "{$found} summary(ies)" . ($dry ? '' : ", {$sent} sent"));

        return self::SUCCESS;
    }
}
