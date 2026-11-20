<?php

namespace App\Console\Commands;

use App\Console\Concerns\RunsPerBusiness;
use App\Models\Business;
use App\Services\Inventory\InventoryNotifier;
use App\Support\Inventory\MonthlyFigures;
use App\Support\Inventory\MonthlyReport;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every morning, for each shop: remember where the business stands (stock, debts, capital) so a month's closing position
 * is known later; and once a month has ended, tell the owner (in the app) that its report is ready and whether the profit
 * target was reached. Running it twice does nothing twice: what was told is marked first. One queued job per shop
 * ({@see RunsPerBusiness}); the months are fixed when the command starts.
 */
class CloseInventoryMonth extends Command
{
    use RunsPerBusiness;

    protected $signature = 'inventory:month-close {--dry-run : show what would be told, tell nobody}';

    protected $description = 'Remember each shop\'s position and tell owners how the month ended';

    public function handle(): int
    {
        return $this->runPerBusiness('told');
    }

    protected function businessService(): string
    {
        return 'inventory';
    }

    protected function businessContext(): array
    {
        $current = MonthlyFigures::currentMonth();

        return ['current' => $current, 'previous' => MonthlyFigures::previousMonth($current)];
    }

    public function forBusiness(Business $business, array $context, bool $dry): array
    {
        if (!$dry) {
            MonthlyFigures::remember((string) $context['current']);
        }
        $told = $this->tell($business, (string) $context['previous'], $dry);

        return ['found' => $told, 'sent' => $dry ? 0 : $told];
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
                $this->note("would tell {$business->name} ({$month}): {$body}");
            } else {
                DB::table('inventory_settings')->updateOrInsert(['key' => $key], ['value' => $month, 'updated_at' => now()]);
                \App\Support\Inventory\ShopTexts::sendMonth($month, $r);
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
                $this->note("would tell {$business->name}: {$title} {$body}");
            } else {
                DB::table('inventory_targets')->where('id', $target->id)->update(['judged_at' => now()]);
                app(InventoryNotifier::class)->notifyByPermission(['inv_view_reports'], 'inventory_target_result', $title, $body, ['month' => $month]);
            }
            $told++;
        }

        return $told;
    }
}
