<?php

namespace App\Console\Commands;

use App\Models\Business;
use App\Services\SmsService;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\BirthdayOffer;
use App\Support\Salon\ClientSegments;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every morning: wish each salon client whose birthday it is (with the owner's offer). Safe to run any number of times:
 * a wish is CLAIMED per client per year before it is sent, and a text that could not be sent gives its claim back.
 * Skipped: a salon that has not switched it on or whose plan has ended, a client with no phone or who asked not to be
 * texted. Each text goes out under that salon's own sender name.
 */
class SendBirthdayOffers extends Command
{
    protected $signature = 'salon:birthday-offers {--dry-run : list who would be texted, send nothing}';

    protected $description = 'Wish salon clients a happy birthday, with the salon\'s offer';

    private const MAX_PER_BUSINESS = 100;

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

            // (plain closures, not arrow functions: the counters must be shared, not copied)
            TenantContext::runAs($owner, function () use ($business, $today, $dry, &$sent, &$found) {
                TenantContext::runInService('salon', function () use ($business, $today, $dry, &$sent, &$found) {
                    if (!BirthdayOffer::isOn()) {
                        return;
                    }
                    $offer = BirthdayOffer::text();
                    $celebrating = ClientSegments::clients()
                        ->filter(fn ($c) => $c['can_text'] && $c['birthday'] !== null && substr($c['birthday'], 5) === $today->format('m-d'))
                        ->take(self::MAX_PER_BUSINESS);

                    foreach ($celebrating as $client) {
                        $found++;
                        if ($dry) {
                            $this->line("would text: {$business->name} -> {$client['name']}");
                            continue;
                        }

                        // Claim this year's wish first, so two runs at the same moment cannot both send it.
                        $claimed = DB::table('inventory_birthday_wishes')->insertOrIgnore([
                            'customer_id' => $client['id'],
                            'year' => (int) $today->format('Y'),
                            'sent_at' => now(),
                            'created_at' => now(),
                            'updated_at' => now(),
                        ]);
                        if ($claimed === 0) {
                            $found--;
                            continue;
                        }
                        if (!SmsService::sendFor($business, $client['phone'], BirthdayOffer::message($client['name'], (string) $business->name, $offer))) {
                            DB::table('inventory_birthday_wishes')->where('customer_id', $client['id'])->where('year', (int) $today->format('Y'))->delete();
                            $this->warn("could not text {$client['name']} ({$business->name})");
                            continue;
                        }
                        $sent++;
                    }
                });
            });
        }

        $this->info(($dry ? 'dry run: ' : '') . "{$found} wish(es)" . ($dry ? '' : ", {$sent} sent"));

        return self::SUCCESS;
    }
}
