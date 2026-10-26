<?php

namespace App\Console\Commands;

use App\Models\Business;
use App\Services\Inventory\InventoryNotifier;
use App\Support\Inventory\MonthlyFigures;
use App\Support\Inventory\MonthlyReport;
use App\Support\Tenancy\TenantContext;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every morning, for each shop: remember where the business stands (stock, debts, capital) so a month's closing position
 * is known later; and once a month has ended, tell the owner (in the app) that its report is ready and whether the profit
 * target was reached. Running it twice does nothing twice: what was told is marked first.
 */
class CloseInventoryMonth extends Command
{
    protected $signature = 'inventory:month-close {--dry-run : show what would be told, tell nobody}';

    protected $description = 'Remember each shop\'s position and tell owners how the month ended';

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');
        $told = 0;
        $seen = 0;
        $prev = MonthlyFigures::previousMonth(MonthlyFigures::currentMonth());

        foreach (Business::withoutAccountScope()->with('owner')->get() as $business) {
            $owner = $business->owner;
            if ($owner === null || !$owner->is_active || !in_array('inventory', $business->serviceTypes(), true) || $business->blocksAccess()) {
                continue;
            }
            $seen++;
            TenantContext::runAs($owner, function () use ($business, $prev, $dry, &$told) {
                TenantContext::runInService('inventory', function () use ($business, $prev, $dry, &$told) {
                    if (!$dry) {
                        MonthlyFigures::remember(MonthlyFigures::currentMonth());
                    }
                    $told += $this->tell($business, $prev, $dry);
                });
            });
        }

        $this->info(($dry ? 'dry run: ' : '') . "{$seen} shop(s), {$told} told");

        return self::SUCCESS;
    }

    /** The report of the month that has just ended, and the target's verdict, once each. */
    private function tell(Business $business, string $month, bool $dry): int
    {
        $told = 0;
        $key = 'month_report_told';
        $r = MonthlyReport::build($month);
        // Nothing to report for a month with no sales (a shop that has only just started).
        if (DB::table('inventory_settings')->where('key', $key)->value('value') !== $month && $r['figures']['sales_count'] > 0) {
            $p = $r['compare']['net_profit'];
            $trend = $p['direction'] === 'up' ? 'imepanda / up' : ($p['direction'] === 'down' ? 'imeshuka / down' : 'ile ile / same');
            $body = 'Faida / Profit: TSh ' . number_format($r['figures']['net_profit']) . ' (' . $trend . ($p['percent'] === null ? '' : ' ' . $p['percent'] . '%') . '). Mauzo / Sales: TSh ' . number_format($r['figures']['sales']) . '.';
            if ($dry) {
                $this->line("would tell {$business->name} ({$month}): {$body}");
            } else {
                DB::table('inventory_settings')->updateOrInsert(['key' => $key], ['value' => $month, 'updated_at' => now()]);
                app(InventoryNotifier::class)->notifyByPermission(['inv_view_reports'], 'inventory_month_report', "Ripoti ya {$month} iko tayari / The {$month} report is ready", $body, ['month' => $month]);
            }
            $told++;
        }

        $target = DB::table('inventory_targets')->where('month', $month)->whereNull('judged_at')->first();
        if ($target !== null) {
            $t = MonthlyReport::build($month)['target'];
            $reached = $t !== null && $t['status'] === 'reached';
            $title = $reached ? 'Lengo la faida limefikiwa / Profit target reached' : 'Lengo la faida halikufikiwa / Profit target missed';
            $body = $reached
                ? "{$month}: TSh " . number_format($t['profit']) . ' / ' . number_format($t['profit_target']) . ' (+' . number_format($t['over_by']) . ')'
                : "{$month}: TSh " . number_format($t['profit']) . ' / ' . number_format($t['profit_target']) . ' (-' . number_format($t['left']) . ')';
            if ($dry) {
                $this->line("would tell {$business->name}: {$title} {$body}");
            } else {
                DB::table('inventory_targets')->where('id', $target->id)->update(['judged_at' => now()]);
                app(InventoryNotifier::class)->notifyByPermission(['inv_view_reports'], 'inventory_target_result', $title, $body, ['month' => $month]);
            }
            $told++;
        }

        return $told;
    }
}
