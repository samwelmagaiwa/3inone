<?php

namespace App\Console\Commands;

use App\Console\Concerns\RunsPerBusiness;
use App\Models\Business;
use App\Services\SmsService;
use App\Support\Salon\AppointmentPlanner;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every afternoon: remind each client who is booked TOMORROW (by the salon's clock, Tanzania). Safe to run any number
 * of times: an appointment is claimed (`reminder_sent_at`) before its text goes out, so it is texted once even if two
 * runs overlap, and a text that could not be sent gives the claim back for the next run. Skipped: a salon that has
 * not switched appointment reminders on or whose plan has ended, a client with no phone or who asked not to be
 * texted, and an appointment that is no longer active. Each text goes out under that salon's own sender name.
 * One queued job per salon ({@see RunsPerBusiness}); "tomorrow" is fixed when the command starts.
 */
class SendAppointmentReminders extends Command
{
    use RunsPerBusiness;

    protected $signature = 'salon:remind-appointments {--dry-run : list who would be texted, send nothing}';

    protected $description = "Text salon clients about tomorrow's appointments";

    /** More than this in one day for one salon is a mistake, not a day's diary. */
    private const MAX_PER_BUSINESS = 150;

    public function handle(): int
    {
        return $this->runPerBusiness('reminder(s)');
    }

    protected function businessService(): string
    {
        return 'salon';
    }

    protected function businessContext(): array
    {
        return ['tomorrow' => Carbon::now(AppointmentPlanner::TIMEZONE)->addDay()->toDateString()];
    }

    public function forBusiness(Business $business, array $context, bool $dry): array
    {
        $found = 0;
        $sent = 0;
        $tomorrow = (string) $context['tomorrow'];
        if (!AppointmentPlanner::remindersOn()) {
            return ['found' => 0, 'sent' => 0];
        }

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
            $this->note("{$business->name}: more than " . self::MAX_PER_BUSINESS . ' appointments tomorrow, the rest are not texted', true);
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
                $this->note("would text: {$business->name} -> {$row->client_name} at {$when}");
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
                $this->note("could not text {$row->client_name} ({$business->name})", true);
                continue;
            }
            $sent++;
        }

        return ['found' => $found, 'sent' => $sent];
    }
}
