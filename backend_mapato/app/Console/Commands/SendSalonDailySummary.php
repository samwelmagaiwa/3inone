<?php

namespace App\Console\Commands;

use App\Models\Business;
use App\Services\SmsService;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\DailySummary;
use App\Support\Salon\SalonFinance;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every evening: text each salon's owner how the day went. Only for salons that switched it on, whose plan has not
 * ended and whose owner has a phone number; sent under that salon's own sender name. Running it twice in a day texts
 * once (the day is claimed first), and a text that could not be sent gives the claim back.
 */
class SendSalonDailySummary extends Command
{
    protected $signature = 'salon:daily-summary {--dry-run : show what would be sent, send nothing}';

    protected $description = 'Text each salon owner how the day went';

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');
        $today = Carbon::now(AppointmentPlanner::TIMEZONE)->startOfDay();
        $sent = 0;
        $found = 0;

        foreach (Business::withoutAccountScope()->with('owner')->get() as $business) {
            $owner = $business->owner;
            if ($owner === null || !$owner->is_active || !in_array('salon', $business->serviceTypes(), true) || $business->blocksAccess()) {
                continue;
            }
            $phone = trim((string) $owner->phone_number);
            if ($phone === '') {
                continue;
            }

            // (plain closures, not arrow functions: the counters must be shared, not copied)
            TenantContext::runAs($owner, function () use ($business, $phone, $today, $dry, &$sent, &$found) {
                TenantContext::runInService('salon', function () use ($business, $phone, $today, $dry, &$sent, &$found) {
                    if (!DailySummary::isOn()) {
                        return;
                    }
                    $found++;
                    $tomorrow = $today->copy()->addDay();
                    $booked = (int) DB::table('inventory_appointments')
                        ->whereIn('status', AppointmentPlanner::ACTIVE)
                        ->whereBetween('starts_at', [$tomorrow->format('Y-m-d 00:00:00'), $tomorrow->format('Y-m-d 23:59:59')])
                        ->count();
                    $text = DailySummary::message((string) $business->name, SalonFinance::summary($today, $today), $booked);
                    if ($dry) {
                        $this->line("would text {$business->name}: {$text}");

                        return;
                    }

                    // Claim the day first, so a second run the same day sends nothing.
                    if (DB::table('inventory_settings')->where('key', 'salon_daily_summary_last')->value('value') === $today->toDateString()) {
                        $found--;

                        return;
                    }
                    DB::table('inventory_settings')->updateOrInsert(['key' => 'salon_daily_summary_last'], ['value' => $today->toDateString(), 'updated_at' => now()]);
                    if (!SmsService::sendFor($business, $phone, $text)) {
                        DB::table('inventory_settings')->where('key', 'salon_daily_summary_last')->delete();
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
