<?php

namespace App\Console\Commands;

use App\Console\Concerns\RunsPerBusiness;
use App\Models\Business;
use App\Services\SmsService;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\BirthdayOffer;
use App\Support\Salon\ClientSegments;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every morning: wish each salon client whose birthday it is (with the owner's offer). Safe to run any number of times:
 * a wish is CLAIMED per client per year before it is sent, and a text that could not be sent gives its claim back.
 * Skipped: a salon that has not switched it on or whose plan has ended, a client with no phone or who asked not to be
 * texted. Each text goes out under that salon's own sender name. One queued job per salon ({@see RunsPerBusiness}).
 */
class SendBirthdayOffers extends Command
{
    use RunsPerBusiness;

    protected $signature = 'salon:birthday-offers {--dry-run : list who would be texted, send nothing}';

    protected $description = 'Wish salon clients a happy birthday, with the salon\'s offer';

    private const MAX_PER_BUSINESS = 100;

    public function handle(): int
    {
        return $this->runPerBusiness('wish(es)');
    }

    protected function businessService(): string
    {
        return 'salon';
    }

    protected function businessContext(): array
    {
        return ['today' => Carbon::now(AppointmentPlanner::TIMEZONE)->toDateString()];
    }

    public function forBusiness(Business $business, array $context, bool $dry): array
    {
        $found = 0;
        $sent = 0;
        if (!BirthdayOffer::isOn()) {
            return ['found' => 0, 'sent' => 0];
        }
        $today = Carbon::parse($context['today'], AppointmentPlanner::TIMEZONE)->startOfDay();
        $offer = BirthdayOffer::text();
        $celebrating = ClientSegments::clients()
            ->filter(fn ($c) => $c['can_text'] && $c['birthday'] !== null && substr($c['birthday'], 5) === $today->format('m-d'))
            ->take(self::MAX_PER_BUSINESS);

        foreach ($celebrating as $client) {
            $found++;
            if ($dry) {
                $this->note("would text: {$business->name} -> {$client['name']}");
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
                $this->note("could not text {$client['name']} ({$business->name})", true);
                continue;
            }
            $sent++;
        }

        return ['found' => $found, 'sent' => $sent];
    }
}
