<?php

namespace App\Console\Commands;

use App\Models\Business;
use App\Services\SmsService;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every afternoon: remind each client who is booked TOMORROW (by the salon's clock, Tanzania). Safe to run any number
 * of times: an appointment is claimed (`reminder_sent_at`) before its text goes out, so it is texted once even if two
 * runs overlap, and a text that could not be sent gives the claim back for the next run. Skipped: a salon that has
 * not switched appointment reminders on or whose plan has ended, a client with no phone or who asked not to be
 * texted, and an appointment that is no longer active. Each text goes out under that salon's own sender name.
 */
class SendAppointmentReminders extends Command
{
    protected $signature = 'salon:remind-appointments {--dry-run : list who would be texted, send nothing}';

    protected $description = "Text salon clients about tomorrow's appointments";

    /** More than this in one day for one salon is a mistake, not a day's diary. */
    private const MAX_PER_BUSINESS = 150;

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');
        $tomorrow = Carbon::now(AppointmentPlanner::TIMEZONE)->addDay()->toDateString();
        $sent = 0;
        $found = 0;
        $salons = 0;

        foreach (Business::withoutAccountScope()->with('owner')->get() as $business) {
            $owner = $business->owner;
            if ($owner === null || !$owner->is_active || !in_array('salon', $business->serviceTypes(), true) || $business->blocksAccess()) {
                continue;
            }

            // (plain closures, not arrow functions: the counters must be shared, not copied)
            TenantContext::runAs($owner, function () use ($business, $tomorrow, $dry, &$sent, &$found, &$salons) {
                TenantContext::runInService('salon', function () use ($business, $tomorrow, $dry, &$sent, &$found, &$salons) {
                    if (!AppointmentPlanner::remindersOn()) {
                        return;
                    }
                    $salons++;

                    $rows = DB::table('inventory_appointments as a')
                        ->leftJoin('inventory_customers as c', 'c.id', '=', 'a.customer_id')
                        ->whereIn('a.status', AppointmentPlanner::ACTIVE)
                        ->whereNull('a.reminder_sent_at')
                        ->where('a.starts_at', '>=', $tomorrow . ' 00:00:00')
                        ->where('a.starts_at', '<=', $tomorrow . ' 23:59:59')
                        ->orderBy('a.starts_at')
                        ->limit(self::MAX_PER_BUSINESS + 1)
                        ->get(['a.id', 'a.client_name', 'a.client_phone', 'a.starts_at', 'a.services', 'c.phone as customer_phone', 'c.sms_opt_out']);

                    if ($rows->count() > self::MAX_PER_BUSINESS) {
                        $this->warn("{$business->name}: more than " . self::MAX_PER_BUSINESS . ' appointments tomorrow, the rest are not texted');
                        $rows = $rows->take(self::MAX_PER_BUSINESS);
                    }

                    foreach ($rows as $row) {
                        $phone = trim((string) ($row->client_phone ?: $row->customer_phone));
                        if ($phone === '' || (bool) $row->sms_opt_out) {
                            continue;
                        }
                        $found++;

                        $names = array_map(fn ($s) => (string) ($s['name'] ?? ''), json_decode((string) $row->services, true) ?: []);
                        $when = Carbon::parse($row->starts_at)->format('H:i');
                        if ($dry) {
                            $this->line("would text: {$business->name} -> {$row->client_name} at {$when}");
                            continue;
                        }

                        // Claim it first, so two runs at the same moment cannot both send it.
                        $claimed = DB::table('inventory_appointments')->where('id', $row->id)->whereNull('reminder_sent_at')->update(['reminder_sent_at' => now()]);
                        if ($claimed === 0) {
                            $found--;
                            continue;
                        }

                        if (!SmsService::sendFor($business, $phone, AppointmentPlanner::message((string) $row->client_name, $when, $names, (string) $business->name))) {
                            DB::table('inventory_appointments')->where('id', $row->id)->update(['reminder_sent_at' => null]);
                            $this->warn("could not text {$row->client_name} ({$business->name})");
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
