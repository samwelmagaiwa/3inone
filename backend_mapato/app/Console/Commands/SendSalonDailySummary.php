<?php

namespace App\Console\Commands;

use App\Console\Concerns\RunsPerBusiness;
use App\Models\Business;
use App\Services\SmsService;
use App\Support\Inventory\ShopTexts;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\DailySummary;
use App\Support\Salon\SalonFinance;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every evening: text each salon's owner how the day went. Only for salons that switched it on, whose plan has not
 * ended and whose owner has a phone number; sent under that salon's own sender name. Running it twice in a day texts
 * once (the day is claimed first), and a text that could not be sent gives the claim back. One queued job per salon
 * ({@see RunsPerBusiness}); the day is fixed when the command starts.
 */
class SendSalonDailySummary extends Command
{
    use RunsPerBusiness;

    protected $signature = 'salon:daily-summary {--dry-run : show what would be sent, send nothing}';

    protected $description = 'Text each salon owner how the day went';

    public function handle(): int
    {
        return $this->runPerBusiness('summary(ies)');
    }

    protected function businessService(): string
    {
        return 'salon';
    }

    protected function needsOwnerPhone(): bool
    {
        return true;
    }

    protected function businessContext(): array
    {
        return ['today' => Carbon::now(AppointmentPlanner::TIMEZONE)->toDateString()];
    }

    public function forBusiness(Business $business, array $context, bool $dry): array
    {
        $today = Carbon::parse($context['today'], AppointmentPlanner::TIMEZONE)->startOfDay();
        $phone = trim((string) $business->owner->phone_number);
        if (!DailySummary::isOn()) {
            return ['found' => 0, 'sent' => 0];
        }
        // Personal spending (family, drawings) is not the business's: it is left out of the spending and the profit, and named apart.
        $figures = function (Carbon $day): array {
            $s = SalonFinance::summary($day, $day);
            $personal = ShopTexts::personalOn($day->toDateString());
            $s['expenses'] = max((float) $s['expenses'] - $personal, 0);
            $s['net_profit'] = (float) $s['net_profit'] + $personal;

            return [$s, $personal];
        };
        [$s, $personal] = $figures($today);
        [$before] = $figures($today->copy()->subDay());
        $text = DailySummary::message((string) $business->name, $s, (float) $before['net_profit'], $personal);
        if ($dry) {
            $this->note("would text {$business->name}: {$text}");

            return ['found' => 1, 'sent' => 0];
        }

        // Claim the day first, so a second run the same day sends nothing.
        if (DB::table('inventory_settings')->where('key', 'salon_daily_summary_last')->value('value') === $today->toDateString()) {
            return ['found' => 0, 'sent' => 0];
        }
        DB::table('inventory_settings')->updateOrInsert(['key' => 'salon_daily_summary_last'], ['value' => $today->toDateString(), 'updated_at' => now()]);
        if (!SmsService::sendFor($business, $phone, $text)) {
            DB::table('inventory_settings')->where('key', 'salon_daily_summary_last')->delete();
            $this->note("could not text {$business->name}", true);

            return ['found' => 1, 'sent' => 0];
        }

        return ['found' => 1, 'sent' => 1];
    }
}
