<?php

namespace App\Console\Commands;

use App\Console\Concerns\RunsPerBusiness;
use App\Models\Business;
use App\Services\SmsService;
use App\Support\Inventory\ShopTexts;
use App\Support\Salon\AppointmentPlanner;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every night, just before the day turns (23:59 in Tanzania): text each shop or depot owner how the day went and how it compares with
 * yesterday. Only for businesses with the shop service, whose plan has not ended, whose owner has a phone number and who have not switched
 * it off; sent under THAT business's own sender name, naming it as registered. Running it twice in a day texts once (the day is claimed
 * first), and a text that could not be sent gives the claim back. One queued job per business ({@see RunsPerBusiness}); the moment is fixed
 * when the command starts, so a job that runs just after midnight still reports the day that ended.
 */
class SendShopDailySummary extends Command
{
    use RunsPerBusiness;

    protected $signature = 'inventory:daily-summary {--dry-run : show what would be sent, send nothing}';

    protected $description = 'Text each shop owner how the day went';

    public function handle(): int
    {
        return $this->runPerBusiness('summary(ies)');
    }

    protected function businessService(): string
    {
        return 'inventory';
    }

    protected function needsOwnerPhone(): bool
    {
        return true;
    }

    protected function businessContext(): array
    {
        return ['now' => Carbon::now(AppointmentPlanner::TIMEZONE)->toIso8601String()];
    }

    public function forBusiness(Business $business, array $context, bool $dry): array
    {
        $now = Carbon::parse($context['now'])->setTimezone(AppointmentPlanner::TIMEZONE);
        $phone = trim((string) $business->owner->phone_number);
        if (!ShopTexts::summaryOn()) {
            return ['found' => 0, 'sent' => 0];
        }
        $text = ShopTexts::summaryMessage(
            (string) $business->name,
            ShopTexts::dayFigures($now, AppointmentPlanner::TIMEZONE),
            ShopTexts::dayFigures($now->copy()->subDay(), AppointmentPlanner::TIMEZONE),
        );
        if ($dry) {
            $this->note("would text {$business->name}: {$text}");

            return ['found' => 1, 'sent' => 0];
        }

        // Claim the day first, so a second run the same day sends nothing.
        $today = $now->toDateString();
        if (DB::table('inventory_settings')->where('key', 'inv_daily_summary_last')->value('value') === $today) {
            return ['found' => 0, 'sent' => 0];
        }
        DB::table('inventory_settings')->updateOrInsert(['key' => 'inv_daily_summary_last'], ['value' => $today, 'updated_at' => now()]);
        if (!SmsService::sendFor($business, $phone, $text)) {
            DB::table('inventory_settings')->where('key', 'inv_daily_summary_last')->delete();
            $this->note("could not text {$business->name}", true);

            return ['found' => 1, 'sent' => 0];
        }

        return ['found' => 1, 'sent' => 1];
    }
}
