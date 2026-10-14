<?php

namespace App\Console\Commands;

use App\Models\Business;
use App\Services\SmsService;
use App\Support\SuperAdminPhones;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Tell people a plan is about to end (or has), by text message. Runs every morning.
 *
 * For each business with an end date it works out where it stands today:
 *   d7 / d3 / d1  7, 3 or 1 days (or fewer) left      d0       ends today
 *   expired       ended, still inside the grace days   blocked  ended and past the grace days
 * and sends THAT reminder once for that end date. Every reminder goes to the business owner; everything new
 * from this run is also listed in one text to the super admin(s), so one message covers all customers.
 *
 * Safe to run any number of times: a reminder is claimed in `billing_reminders` before it is sent, so it goes
 * out once; a renewal gives the business a new end date and so a fresh set of reminders. A text that could
 * not be sent is released and tried again on the next run.
 */
class SendBillingReminders extends Command
{
    protected $signature = 'billing:remind {--dry-run : list what would be sent, send nothing}';

    protected $description = 'Text business owners and the super admin about plans that are ending or have ended';

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');
        $digest = [];
        $sent = 0;

        $businesses = Business::withoutAccountScope()->with('owner')->whereNotNull('valid_until')->get();

        foreach ($businesses as $business) {
            $kind = $this->kindFor($business);
            if ($kind === null) {
                continue;
            }

            $date = $business->valid_until->toDateString();
            $row = ['business_id' => $business->id, 'valid_until_date' => $date, 'kind' => $kind];

            if (DB::table('billing_reminders')->where($row)->exists()) {
                continue;
            }

            $digest[] = [$business, $kind];

            if ($dry) {
                $this->line("would remind: {$business->name} ({$kind}, ends {$date})");
                continue;
            }

            // Claim it first, so two runs at the same moment cannot both send it.
            if (DB::table('billing_reminders')->insertOrIgnore($row + ['sent_at' => now(), 'created_at' => now(), 'updated_at' => now()]) === 0) {
                array_pop($digest);
                continue;
            }

            $phone = $business->owner?->phone_number ?: $business->phone;
            if ($phone && !SmsService::send($phone, $this->ownerText($business, $kind))) {
                // Not sent: let the next run try again, and keep it out of the super admin's list for now.
                DB::table('billing_reminders')->where($row)->delete();
                array_pop($digest);
                $this->warn("could not text {$business->name}");
                continue;
            }
            $sent++;
        }

        if ($digest !== [] && !$dry) {
            $text = $this->digestText($digest);
            foreach (SuperAdminPhones::all() as $phone) {
                SmsService::send($phone, $text);
            }
        }

        $this->info(($dry ? 'dry run: ' : '') . count($digest) . ' reminder(s)' . ($dry ? '' : ", {$sent} owner text(s) sent"));

        return self::SUCCESS;
    }

    /** Which reminder is due for this business today, or null when it is not near its end. */
    public function kindFor(Business $business): ?string
    {
        $days = $business->daysLeft();
        if ($days === null) {
            return null;
        }

        return match (true) {
            $business->pastGrace() => 'blocked',
            $days < 0 => 'expired',
            $days === 0 => 'd0',
            $days === 1 => 'd1',
            $days <= 3 => 'd3',
            $days <= 7 => 'd7',
            default => null,
        };
    }

    private function ownerText(Business $business, string $kind): string
    {
        $name = $business->name;
        $date = $business->valid_until->format('d/m/Y');
        $days = max($business->daysLeft() ?? 0, 0);
        $grace = max((int) config('billing.grace_days', 7), 0);
        $enforced = (bool) config('billing.enforce', false);
        $contact = trim((string) config('billing.contact_phone', ''));
        $reach = $contact !== '' ? " Wasiliana: {$contact}. / Contact: {$contact}." : '';

        $text = match ($kind) {
            'd0' => "Usajili wa \"{$name}\" unaisha leo ({$date}). Lipia ili uendelee. / Your subscription for \"{$name}\" ends today ({$date}). Pay to keep using it.",
            'd1', 'd3', 'd7' => "Usajili wa \"{$name}\" unaisha baada ya siku {$days} ({$date}). Lipia ili uendelee. / Your subscription for \"{$name}\" ends in {$days} day(s) ({$date}). Pay to keep using it.",
            'expired' => $enforced
                ? "Usajili wa \"{$name}\" umeisha ({$date}). Lipia ndani ya siku {$grace} ili huduma zisisimame. / The subscription for \"{$name}\" ended on {$date}. Pay within {$grace} days so the service is not stopped."
                : "Usajili wa \"{$name}\" umeisha ({$date}). Tafadhali lipia ili uendelee. / The subscription for \"{$name}\" ended on {$date}. Please pay to continue.",
            default => $enforced
                ? "Huduma za \"{$name}\" zimesimamishwa kwa sababu usajili uliisha ({$date}). Lipia ili uendelee mara moja. / Services for \"{$name}\" are stopped because the subscription ended on {$date}. Pay to continue right away."
                : "Usajili wa \"{$name}\" uliisha ({$date}) na haujalipiwa. Tafadhali lipia. / The subscription for \"{$name}\" ended on {$date} and is unpaid. Please pay.",
        };

        return '3 in One: ' . $text . $reach;
    }

    /** @param  array<int, array{0: Business, 1: string}>  $items */
    private function digestText(array $items): string
    {
        $label = function (Business $b, string $kind): string {
            return match ($kind) {
                'd0' => 'leo/today',
                'blocked' => 'imesimamishwa/stopped',
                'expired' => 'imeisha/expired',
                default => 'siku ' . max($b->daysLeft() ?? 0, 0) . '/' . max($b->daysLeft() ?? 0, 0) . 'd',
            };
        };

        $shown = array_slice($items, 0, 6);
        $parts = array_map(fn (array $i) => $i[0]->name . ' (' . $label($i[0], $i[1]) . ')', $shown);
        $more = count($items) - count($shown);

        return '3 in One: Mipango inayoisha / Plans ending: ' . implode(', ', $parts)
            . ($more > 0 ? " +{$more} zaidi/more" : '') . '.';
    }
}
