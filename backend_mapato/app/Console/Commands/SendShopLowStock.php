<?php

namespace App\Console\Commands;

use App\Console\Concerns\RunsPerBusiness;
use App\Models\Business;
use App\Support\Inventory\ShopTexts;
use App\Support\Salon\AppointmentPlanner;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Every morning (08:00 in Tanzania): text each shop or depot owner which goods are running low (below the minimum set on the product), under
 * THAT business's own sender name. Nothing is sent when nothing is low, and only once a day; a business can switch it off.
 * One queued job per business ({@see RunsPerBusiness}).
 */
class SendShopLowStock extends Command
{
    use RunsPerBusiness;

    protected $signature = 'inventory:low-stock {--dry-run : show what would be sent, send nothing}';

    protected $description = 'Text each shop owner which goods are running low';

    public function handle(): int
    {
        return $this->runPerBusiness('low-stock text(s)');
    }

    protected function businessService(): string
    {
        return 'inventory';
    }

    protected function needsOwnerPhone(): bool
    {
        return true;
    }

    protected function businessContext(): array
    {
        return ['day' => Carbon::now(AppointmentPlanner::TIMEZONE)->toDateString()];
    }

    public function forBusiness(Business $business, array $context, bool $dry): array
    {
        $day = (string) $context['day'];
        $phone = trim((string) $business->owner->phone_number);
        if (!ShopTexts::lowStockOn()) {
            return ['found' => 0, 'sent' => 0];
        }
        $items = DB::table('inventory_products')->whereColumn('quantity', '<', 'min_stock')->where('is_service', false)->where('status', 'active')
            ->orderBy('quantity')->orderBy('name')->get(['name', 'quantity'])->map(fn ($p) => ['name' => $p->name, 'quantity' => $p->quantity])->all();
        if ($items === []) {
            return ['found' => 0, 'sent' => 0];
        }
        if ($dry) {
            $this->note("would text {$business->name}: " . ShopTexts::lowStockMessage((string) $business->name, $items));

            return ['found' => 1, 'sent' => 0];
        }
        // Claim the day first, so a second run the same morning sends nothing.
        if (DB::table('inventory_settings')->where('key', 'inv_low_stock_last')->value('value') === $day) {
            return ['found' => 0, 'sent' => 0];
        }
        DB::table('inventory_settings')->updateOrInsert(['key' => 'inv_low_stock_last'], ['value' => $day, 'updated_at' => now()]);
        if (!ShopTexts::sendLowStock($business, $phone, $items)) {
            DB::table('inventory_settings')->where('key', 'inv_low_stock_last')->delete();
            $this->note("could not text {$business->name}", true);

            return ['found' => 1, 'sent' => 0];
        }

        return ['found' => 1, 'sent' => 1];
    }
}
