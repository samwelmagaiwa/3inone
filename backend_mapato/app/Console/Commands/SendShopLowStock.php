<?php

namespace App\Console\Commands;

use App\Models\Business;
use App\Support\Inventory\ShopTexts;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every morning (08:00 in Tanzania): text each shop or depot owner which goods are running low (below the minimum set on the product), under
 * THAT business's own sender name. Nothing is sent when nothing is low, and only once a day; a business can switch it off.
 */
class SendShopLowStock extends Command
{
    protected $signature = 'inventory:low-stock {--dry-run : show what would be sent, send nothing}';

    protected $description = 'Text each shop owner which goods are running low';

    public function handle(): int
    {
        $dry = (bool) $this->option('dry-run');
        $day = Carbon::now(AppointmentPlanner::TIMEZONE)->toDateString();
        $sent = 0;
        $found = 0;

        foreach (Business::withoutAccountScope()->with('owner')->get() as $business) {
            $owner = $business->owner;
            if ($owner === null || !$owner->is_active || !in_array('inventory', $business->serviceTypes(), true) || $business->blocksAccess()) {
                continue;
            }
            $phone = trim((string) $owner->phone_number);
            if ($phone === '') {
                continue;
            }

            TenantContext::runAs($owner, function () use ($business, $phone, $day, $dry, &$sent, &$found) {
                TenantContext::runInService('inventory', function () use ($business, $phone, $day, $dry, &$sent, &$found) {
                    if (!ShopTexts::lowStockOn()) {
                        return;
                    }
                    $items = DB::table('inventory_products')->whereColumn('quantity', '<', 'min_stock')->where('is_service', false)->where('status', 'active')
                        ->orderBy('quantity')->orderBy('name')->get(['name', 'quantity'])->map(fn ($p) => ['name' => $p->name, 'quantity' => $p->quantity])->all();
                    if ($items === []) {
                        return;
                    }
                    $found++;
                    if ($dry) {
                        $this->line("would text {$business->name}: " . ShopTexts::lowStockMessage((string) $business->name, $items));

                        return;
                    }
                    // Claim the day first, so a second run the same morning sends nothing.
                    if (DB::table('inventory_settings')->where('key', 'inv_low_stock_last')->value('value') === $day) {
                        $found--;

                        return;
                    }
                    DB::table('inventory_settings')->updateOrInsert(['key' => 'inv_low_stock_last'], ['value' => $day, 'updated_at' => now()]);
                    if (!ShopTexts::sendLowStock($business, $phone, $items)) {
                        DB::table('inventory_settings')->where('key', 'inv_low_stock_last')->delete();
                        $this->warn("could not text {$business->name}");

                        return;
                    }
                    $sent++;
                });
            });
        }

        $this->info(($dry ? 'dry run: ' : '') . "{$found} low-stock text(s)" . ($dry ? '' : ", {$sent} sent"));

        return self::SUCCESS;
    }
}
