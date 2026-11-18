<?php

namespace App\Support\Inventory;

use App\Models\Business;
use App\Services\SmsService;
use App\Support\Salon\ClientSegments;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The texts of a SHOP or DEPOT (the inventory service): a receipt to the customer when they buy, a thank-you when they pay a debt, and
 * the day's figures to the owner every night. Each goes out through THE BUSINESS WHOSE TILL IT WAS ({@see SmsService::sendFor()}: its own
 * sender name and account), and names the business as it was registered, so one business never speaks for another.
 *
 * A customer with no phone, or who asked for no texts, is never texted; a text that cannot be sent never blocks the sale or the payment.
 * The owner can switch the customer texts off (setting `inv_customer_sms` = 0); the night summary has its own switch (`inv_daily_summary` = 0).
 */
final class ShopTexts
{
    private const CUSTOMER_KEY = 'inv_customer_sms';

    private const SUMMARY_KEY = 'inv_daily_summary';

    /** Only the shop and depot: a salon has its own texts. */
    public static function active(): bool
    {
        return TenantContext::service() === 'inventory';
    }

    public static function customersOn(): bool
    {
        return DB::table('inventory_settings')->where('key', self::CUSTOMER_KEY)->value('value') !== '0';
    }

    public static function summaryOn(): bool
    {
        return DB::table('inventory_settings')->where('key', self::SUMMARY_KEY)->value('value') !== '0';
    }

    public static function saveCustomersOn(bool $on): void
    {
        DB::table('inventory_settings')->updateOrInsert(['key' => self::CUSTOMER_KEY], ['value' => $on ? '1' : '0', 'updated_at' => now()]);
    }

    public static function saveSummaryOn(bool $on): void
    {
        DB::table('inventory_settings')->updateOrInsert(['key' => self::SUMMARY_KEY], ['value' => $on ? '1' : '0', 'updated_at' => now()]);
    }

    private static function tsh(float $v): string
    {
        return 'TSh ' . number_format($v, 0, '.', ',');
    }

    private static function clean(string $text, string $fallback): string
    {
        return trim((string) preg_replace('/\s+/u', ' ', $text)) ?: $fallback;
    }

    // ------------------------------------------------------------------ the words

    /**
     * "Habari Juma, umenunua Sukari kwa TSh 45,000 kwa DUKA LA MAMA ASHA. Umelipa TSh 30,000, bado TSh 15,000. Asante, karibu tena!"
     *
     * @param  array<int, string>  $items  the names of what was bought
     */
    public static function receiptMessage(string $client, string $business, array $items, float $total, float $paid): string
    {
        $first = ClientSegments::firstName($client);
        $business = self::clean($business, 'duka letu');
        $names = array_values(array_filter(array_map(fn ($n) => self::clean((string) $n, ''), $items)));
        $shown = array_slice($names, 0, 3);
        $more = count($names) - count($shown);
        $what = $shown === [] ? 'bidhaa' : implode(', ', $shown) . ($more > 0 ? " na nyingine {$more}" : '');
        $left = max(round($total - $paid, 2), 0);

        return ($first !== '' ? "Habari {$first}, " : 'Habari, ') . "umenunua {$what} kwa " . self::tsh($total) . " kwa {$business}. "
            . ($left > 0 ? 'Umelipa ' . self::tsh($paid) . ', bado ' . self::tsh($left) . '.' : 'Umelipa kikamilifu.') . ' Asante, karibu tena!';
    }

    /** "Asante Juma, tumepokea TSh 10,000. Deni lililobaki: TSh 5,000. Karibu DUKA LA MAMA ASHA!" */
    public static function debtPaidMessage(string $client, string $business, float $received, float $left): string
    {
        $first = ClientSegments::firstName($client);
        $business = self::clean($business, 'duka letu');
        $left = max(round($left, 2), 0);

        return ($first !== '' ? "Asante {$first}, " : 'Asante, ') . 'tumepokea ' . self::tsh($received) . '. '
            . ($left > 0 ? 'Deni lililobaki: ' . self::tsh($left) . '.' : 'Deni lako limelipwa lote.') . " Karibu {$business}!";
    }

    /**
     * The owner's night text. `$today` and `$yesterday` are {@see dayFigures()}; the difference said is the profit's only. Personal spending is
     * not the business's: when there was some it is named apart and is not in the profit (as in the monthly report).
     *
     * @param  array<string, float>  $today
     * @param  array<string, float>  $yesterday
     */
    public static function summaryMessage(string $business, array $today, array $yesterday): string
    {
        $business = self::clean($business, 'duka lako');
        $profit = $today['profit'];
        $d = $profit - $yesterday['profit'];
        $own = $today['personal'] > 0 ? ' Matumizi binafsi ' . self::tsh($today['personal']) . ' hayahesabiwi kwenye faida.' : '';

        return "Leo {$business}: mauzo " . self::tsh($today['sales']) . ', ' . ($profit >= 0 ? 'faida ' : 'hasara ') . self::tsh(abs($profit))
            . ', matumizi ' . self::tsh($today['expenses']) . ', madeni mapya ' . self::tsh($today['new_debts'])
            . '. Tofauti ya faida na jana: ' . ($d < 0 ? '-' : '+') . self::tsh(abs($d)) . '.' . $own;
    }

    // ------------------------------------------------------------------ the figures

    /**
     * One day of the business (the day as it is in Tanzania): what was sold, what it cost, the spending, the profit left and the debts made.
     *
     * @return array{sales: float, cost: float, expenses: float, profit: float, new_debts: float, personal: float}
     */
    public static function dayFigures(Carbon $day, string $timezone): array
    {
        $from = $day->copy()->setTimezone($timezone)->startOfDay()->utc()->format('Y-m-d H:i:s');
        $to = $day->copy()->setTimezone($timezone)->endOfDay()->utc()->format('Y-m-d H:i:s');
        $date = $day->copy()->setTimezone($timezone)->toDateString();

        $sales = fn () => DB::table('inventory_sales as s')->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')->whereBetween('s.created_at', [$from, $to]);
        $revenue = (float) $sales()->sum('s.total');
        $debts = (float) $sales()->whereRaw('s.total > s.paid_total')->sum(DB::raw('s.total - s.paid_total'));
        $cost = (float) DB::table('inventory_sale_items as si')->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->whereNull('s.cancelled_at')->where('s.payment_status', '!=', 'cancelled')->whereBetween('s.created_at', [$from, $to])
            ->sum(DB::raw('si.unit_cost_snapshot * si.quantity'));
        $expenses = (float) DB::table('inventory_expenses')->where('expense_date', $date)
            ->when(Schema::hasColumn('inventory_expenses', 'status'), fn ($q) => $q->where('status', 'approved'))
            ->when(Schema::hasColumn('inventory_expenses', 'is_personal'), fn ($q) => $q->where('is_personal', false))
            ->sum('amount');

        return ['sales' => $revenue, 'cost' => $cost, 'expenses' => $expenses, 'profit' => round($revenue - $cost - $expenses, 2), 'new_debts' => $debts, 'personal' => self::personalOn($date)];
    }

    /** What the owner spent on themselves (family, drawings) on a day: never part of the business's spending or profit. */
    public static function personalOn(string $date): float
    {
        if (!Schema::hasColumn('inventory_expenses', 'is_personal')) {
            return 0.0;
        }

        return (float) DB::table('inventory_expenses')->where('expense_date', $date)->where('is_personal', true)
            ->when(Schema::hasColumn('inventory_expenses', 'status'), fn ($q) => $q->where('status', 'approved'))->sum('amount');
    }

    // ------------------------------------------------------------------ the sending

    private static function business(): ?Business
    {
        $viewer = TenantContext::viewer();

        return $viewer === null ? null : Business::forUser($viewer);
    }

    /** @return array{name: string, phone: string}|null the customer, when they can be texted */
    private static function textable(?int $customerId): ?array
    {
        if ($customerId === null) {
            return null;
        }
        $c = DB::table('inventory_customers')->where('id', $customerId)->first();
        $phone = trim((string) ($c->phone ?? ''));
        if ($c === null || $phone === '' || (bool) ($c->sms_opt_out ?? false)) {
            return null;
        }

        return ['name' => (string) $c->name, 'phone' => $phone];
    }

    /** A sale has been made: the customer gets their receipt. Never throws. */
    public static function afterSale(int $saleId): void
    {
        try {
            if (!self::active() || !self::customersOn()) {
                return;
            }
            $sale = DB::table('inventory_sales')->where('id', $saleId)->first();
            if ($sale === null || !empty($sale->cancelled_at)) {
                return;
            }
            $client = self::textable($sale->customer_id === null ? null : (int) $sale->customer_id);
            if ($client === null) {
                return;
            }
            $business = self::business();
            if ($business === null) {
                return;
            }
            $items = DB::table('inventory_sale_items as si')->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
                ->where('si.sale_id', $saleId)->orderByDesc('si.total')->pluck('p.name')->filter()->unique()->values()->all();

            SmsService::sendFor($business, $client['phone'], self::receiptMessage($client['name'], (string) $business->name, $items, (float) $sale->total, (float) $sale->paid_total));
        } catch (\Throwable) {
            // The sale stands; the text is a courtesy.
        }
    }

    /** A customer has paid something on what they owe: thank them and say what is left. Never throws. */
    public static function afterDebtPayment(int $customerId, float $received): void
    {
        try {
            if (!self::active() || !self::customersOn() || $received <= 0) {
                return;
            }
            $client = self::textable($customerId);
            $business = self::business();
            if ($client === null || $business === null) {
                return;
            }

            SmsService::sendFor($business, $client['phone'], self::debtPaidMessage($client['name'], (string) $business->name, $received, CustomerDebt::left($customerId)));
        } catch (\Throwable) {
            // The payment stands.
        }
    }
}
