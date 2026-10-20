<?php

namespace App\Support\Salon;

use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;

/**
 * "Come back" reminders for a salon: who should be texted today because it is time for their next visit.
 *
 * The rule, in plain words:
 *  - Only a client whose LAST service visit counts (a newer visit replaces an older one), and only a visit that was
 *    not cancelled. Buying shampoo is not a visit; having a service done is.
 *  - How long to wait comes from the services of that visit: each service can say "come back after N weeks" (a
 *    wash 2, braids 6); a service that says nothing uses the business's own number (4 by default). When a visit had
 *    several services, the LONGEST wait wins: the main treatment sets the pace, not the quick add-on.
 *  - The text goes out on the day the wait is over. If the daily job missed that day it is still sent for the next
 *    {@see self::GRACE_DAYS} days; after that the visit is left alone, so nobody gets "it has been 4 weeks" three
 *    months late.
 *  - A visit is texted ONCE (the table inventory_rebook_reminders), a client with no phone number or who asked not
 *    to be texted is never texted, and the whole thing is OFF until the owner switches it on.
 *
 * Everything here runs for ONE business: the caller signs in as that business (TenantContext::runAs) and the tenant
 * query grammar limits every query to its rows, so one salon can never see or text another salon's clients.
 */
final class RebookPlanner
{
    public const DEFAULT_WEEKS = 4;

    public const MAX_WEEKS = 52;

    /** How long after the day it was due a reminder may still go out. */
    public const GRACE_DAYS = 14;

    private const KEY_ENABLED = 'salon_rebook_enabled';

    private const KEY_WEEKS = 'salon_rebook_weeks';

    /**
     * @return array{enabled: bool, weeks: int}
     */
    public static function settings(): array
    {
        $rows = DB::table('inventory_settings')->whereIn('key', [self::KEY_ENABLED, self::KEY_WEEKS])->pluck('value', 'key');
        $weeks = (int) ($rows[self::KEY_WEEKS] ?? self::DEFAULT_WEEKS);

        return [
            'enabled' => ($rows[self::KEY_ENABLED] ?? '0') === '1',
            'weeks' => min(self::MAX_WEEKS, max(1, $weeks > 0 ? $weeks : self::DEFAULT_WEEKS)),
        ];
    }

    public static function save(?bool $enabled, ?int $weeks): void
    {
        $write = fn (string $key, string $value) => DB::table('inventory_settings')->updateOrInsert(
            ['key' => $key],
            ['value' => $value, 'updated_at' => now()],
        );

        if ($enabled !== null) {
            $write(self::KEY_ENABLED, $enabled ? '1' : '0');
        }
        if ($weeks !== null) {
            $write(self::KEY_WEEKS, (string) min(self::MAX_WEEKS, max(1, $weeks)));
        }
    }

    /**
     * The clients whose "come back" day has come (and has not passed its grace days), for the business signed in.
     *
     * @return array<int, array{customer_id: int, name: string, phone: string, sale_id: int, visit_on: string, due_on: string, weeks_waited: int, rule_weeks: int, service: string, sent: bool, can_text: bool, skip_reason: ?string}>
     */
    public static function due(CarbonInterface $today, bool $includeSent = false): array
    {
        $today = Carbon::instance($today)->startOfDay();
        $defaultWeeks = self::settings()['weeks'];
        // The longest wait there can be, plus the grace days: anything older can never be due again.
        $since = $today->copy()->subDays(self::MAX_WEEKS * 7 + self::GRACE_DAYS);

        $lines = DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->join('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->where('si.is_service', true)
            ->whereNull('s.cancelled_at')
            ->where('s.created_at', '>=', $since)
            ->get([
                'si.sale_id', 'si.total', 'p.name as product_name', 'p.rebook_after_weeks',
                's.created_at as sale_at', 's.customer_id',
                'c.name as customer_name', 'c.phone as customer_phone', 'c.sms_opt_out',
            ]);

        // Each client's last service visit: the newest sale that has a service on it.
        $lastSale = [];
        foreach ($lines as $line) {
            $rank = [Carbon::parse($line->sale_at)->timestamp, (int) $line->sale_id];
            $key = (int) $line->customer_id;
            if (!isset($lastSale[$key]) || $rank > $lastSale[$key]) {
                $lastSale[$key] = $rank;
            }
        }

        $visits = [];
        foreach ($lines as $line) {
            if ($lastSale[(int) $line->customer_id][1] === (int) $line->sale_id) {
                $visits[(int) $line->customer_id][] = $line;
            }
        }

        $sentKeys = [];
        if ($visits !== []) {
            foreach (DB::table('inventory_rebook_reminders')->whereIn('customer_id', array_keys($visits))->get(['customer_id', 'visit_on']) as $r) {
                $sentKeys[(int) $r->customer_id . '|' . substr((string) $r->visit_on, 0, 10)] = true;
            }
        }

        $rows = [];
        foreach ($visits as $customerId => $visitLines) {
            $first = $visitLines[0];
            ['visit_on' => $visitOn, 'due_on' => $dueOn, 'rule_weeks' => $ruleWeeks, 'main' => $main] = self::visit($visitLines, $defaultWeeks);
            if ($today->lt($dueOn) || $today->gt($dueOn->copy()->addDays(self::GRACE_DAYS))) {
                continue;
            }

            $sent = isset($sentKeys[$customerId . '|' . $visitOn->toDateString()]);
            if ($sent && !$includeSent) {
                continue;
            }

            $phone = trim((string) $first->customer_phone);
            $skip = $phone === '' ? 'no_phone' : ((bool) $first->sms_opt_out ? 'opted_out' : null);

            $rows[] = [
                'customer_id' => $customerId,
                'name' => (string) $first->customer_name,
                'phone' => $phone,
                'sale_id' => (int) $first->sale_id,
                'visit_on' => $visitOn->toDateString(),
                'due_on' => $dueOn->toDateString(),
                'weeks_waited' => intdiv((int) $visitOn->diffInDays($today), 7),
                'rule_weeks' => $ruleWeeks,
                'service' => (string) ($main->product_name ?? ''),
                'sent' => $sent,
                'can_text' => $skip === null,
                'skip_reason' => $skip,
            ];
        }

        usort($rows, fn ($a, $b) => [$a['due_on'], $a['name']] <=> [$b['due_on'], $b['name']]);

        return $rows;
    }

    /**
     * One client's last service visit and when the next one is due, whether or not that day has come (for the
     * client's page). Null when they have never had a service.
     *
     * @return array{visit_on: string, due_on: string, rule_weeks: int, service: string}|null
     */
    public static function nextVisit(int $customerId): ?array
    {
        $lines = DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->where('si.is_service', true)
            ->whereNull('s.cancelled_at')
            ->where('s.customer_id', $customerId)
            ->orderByDesc('s.created_at')
            ->orderByDesc('s.id')
            ->get(['si.sale_id', 'si.total', 'p.name as product_name', 'p.rebook_after_weeks', 's.created_at as sale_at']);
        if ($lines->isEmpty()) {
            return null;
        }

        $lastSaleId = (int) $lines->first()->sale_id;
        $visit = self::visit($lines->filter(fn ($l) => (int) $l->sale_id === $lastSaleId)->values()->all(), self::settings()['weeks']);

        return [
            'visit_on' => $visit['visit_on']->toDateString(),
            'due_on' => $visit['due_on']->toDateString(),
            'rule_weeks' => $visit['rule_weeks'],
            'service' => (string) ($visit['main']->product_name ?? ''),
        ];
    }

    /**
     * The facts of one visit from its service lines: the day, how many weeks to wait (the longest any of its
     * services asks for, else the business's number), the day that wait ends, and the main service.
     *
     * @param  array<int, object>  $visitLines
     * @return array{visit_on: Carbon, due_on: Carbon, rule_weeks: int, main: object}
     */
    private static function visit(array $visitLines, int $defaultWeeks): array
    {
        $visitOn = Carbon::parse($visitLines[0]->sale_at)->startOfDay();
        $ruleWeeks = max(array_map(fn ($l) => (int) ($l->rebook_after_weeks ?: $defaultWeeks), $visitLines));

        // The main treatment of the visit: the service that was paid the most for.
        $main = $visitLines[0];
        foreach ($visitLines as $l) {
            if ((float) $l->total > (float) $main->total) {
                $main = $l;
            }
        }

        return [
            'visit_on' => $visitOn,
            'due_on' => $visitOn->copy()->addDays($ruleWeeks * 7),
            'rule_weeks' => $ruleWeeks,
            'main' => $main,
        ];
    }

    /**
     * The text, in Swahili and English like every other text this app sends. The number of weeks is how long it
     * has really been; Swahili agrees with it: "Imepita wiki moja" for one, "Zimepita wiki 4" for more.
     */
    public static function message(string $customerName, string $service, int $weeksWaited, string $business): string
    {
        $weeks = max(1, $weeksWaited);
        $first = trim((string) (preg_split('/\s+/u', trim($customerName))[0] ?? ''));
        $first = $first === '' ? '' : mb_convert_case(mb_strtolower($first, 'UTF-8'), MB_CASE_TITLE, 'UTF-8');
        $service = self::shorten($service !== '' ? $service : 'huduma', 40);
        $business = self::shorten($business !== '' ? $business : 'saluni yetu', 40);

        $swWeeks = $weeks === 1 ? 'Imepita wiki moja' : "Zimepita wiki {$weeks}";
        $enWeeks = $weeks === 1 ? 'one week' : "{$weeks} weeks";
        $swHello = $first !== '' ? "Habari {$first}," : 'Habari,';
        $enHello = $first !== '' ? "Hello {$first}," : 'Hello,';

        return "{$swHello} {$swWeeks} tangu ulipohudumiwa kwa {$service} katika {$business}. Karibu tena! / "
            . "{$enHello} it has been {$enWeeks} since your {$service} at {$business}. We would love to see you again!";
    }

    private static function shorten(string $text, int $max): string
    {
        $text = trim((string) preg_replace('/\s+/u', ' ', $text));

        // Plain "..." and not the single character: that one is outside the SMS alphabet and would make the whole
        // text count as 70-character segments instead of 160.
        return mb_strlen($text) > $max ? rtrim(mb_substr($text, 0, $max - 3)) . '...' : $text;
    }
}
