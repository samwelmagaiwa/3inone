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

    /** The owner's morning text about goods running low (on unless switched off). */
    public static function lowStockOn(): bool
    {
        return DB::table('inventory_settings')->where('key', 'inv_low_stock_sms')->value('value') !== '0';
    }

    /** The owner's text when a month has ended (on unless switched off). */
    public static function monthOn(): bool
    {
        return DB::table('inventory_settings')->where('key', 'inv_month_sms')->value('value') !== '0';
    }

    /** The weekly text to customers who have owed for a while (on unless switched off; the customer texts switch must be on too). */
    public static function debtRemindersOn(): bool
    {
        return self::customersOn() && DB::table('inventory_settings')->where('key', 'inv_debt_reminder_sms')->value('value') !== '0';
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

    /**
     * "DUKA LA MAMA ASHA: bidhaa 4 zimebaki chache: Sukari (3), Mchele (5), Mafuta (2) na nyingine 1."
     *
     * @param  array<int, array{name: string, quantity: float|int|string}>  $items
     */
    public static function lowStockMessage(string $business, array $items): string
    {
        $business = self::clean($business, 'duka lako');
        $shown = array_slice($items, 0, 5);
        $more = count($items) - count($shown);
        $list = implode(', ', array_map(fn ($i) => self::clean((string) $i['name'], 'bidhaa') . ' (' . rtrim(rtrim(number_format((float) $i['quantity'], 2, '.', ''), '0'), '.') . ')', $shown));

        return "{$business}: bidhaa " . count($items) . " zimebaki chache: {$list}" . ($more > 0 ? " na nyingine {$more}" : '') . '. Ongeza stoo.';
    }

    private const MONTHS = ['Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni', 'Julai', 'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba'];

    /**
     * "DUKA LA MAMA ASHA: Oktoba 2026 umeisha. Faida TSh 2,140,000 (imepanda 12%). Lengo la TSh 2,000,000 limefikiwa. Fungua app uone ripoti kamili."
     *
     * @param  array<string, mixed>  $report  {@see \App\Support\Inventory\MonthlyReport::build()}
     */
    public static function monthMessage(string $business, string $month, array $report): string
    {
        $business = self::clean($business, 'duka lako');
        [$year, $m] = array_pad(explode('-', $month), 2, '1');
        $name = (self::MONTHS[max((int) $m, 1) - 1] ?? $month) . " {$year}";
        $profit = (float) $report['figures']['net_profit'];
        $p = $report['compare']['net_profit'] ?? [];
        $trend = ($p['direction'] ?? '') === 'up' ? 'imepanda' : (($p['direction'] ?? '') === 'down' ? 'imeshuka' : '');
        $pct = isset($p['percent']) && $p['percent'] !== null ? ' ' . abs((float) $p['percent']) . '%' : '';
        $text = "{$business}: {$name} umeisha. " . ($profit >= 0 ? 'Faida ' : 'Hasara ') . self::tsh(abs($profit)) . ($trend !== '' ? " ({$trend}{$pct})" : '') . '.';

        $target = $report['target'] ?? null;
        if (is_array($target)) {
            $text .= ($target['status'] ?? '') === 'reached'
                ? ' Lengo la ' . self::tsh((float) $target['profit_target']) . ' limefikiwa.'
                : ' Lengo la ' . self::tsh((float) $target['profit_target']) . ' halikufikiwa, upungufu ' . self::tsh((float) $target['left']) . '.';
        }

        return $text . ' Fungua app uone ripoti kamili.';
    }

    /** "Habari Juma, unadaiwa TSh 15,000 na DUKA LA MAMA ASHA. Tafadhali lipa ukipata nafasi. Asante!" */
    public static function debtReminderMessage(string $client, string $business, float $owed): string
    {
        $first = ClientSegments::firstName($client);
        $business = self::clean($business, 'duka letu');

        return ($first !== '' ? "Habari {$first}, " : 'Habari, ') . 'unadaiwa ' . self::tsh($owed) . " na {$business}. Tafadhali lipa ukipata nafasi. Asante!";
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

    /** The owner's morning text about goods running low. Never throws; true when it went out. */
    public static function sendLowStock(Business $business, string $phone, array $items): bool
    {
        try {
            return SmsService::sendFor($business, $phone, self::lowStockMessage((string) $business->name, $items));
        } catch (\Throwable) {
            return false;
        }
    }

    /** The owner's text when a month has ended. Never throws. */
    public static function sendMonth(string $month, array $report): void
    {
        try {
            if (!self::active() || !self::monthOn()) {
                return;
            }
            $business = self::business();
            $phone = trim((string) ($business?->owner?->phone_number ?? ''));
            if ($business === null || $phone === '') {
                return;
            }
            SmsService::sendFor($business, $phone, self::monthMessage((string) $business->name, $month, $report));
        } catch (\Throwable) {
            // The report stands; the text is a courtesy.
        }
    }

    /**
     * The owner asked to remind a customer of what they owe. Returns [sent, owed, reason]: reason is 'no_phone', 'opted_out', 'owes_nothing' or null.
     *
     * @return array{sent: bool, owed: float, reason: ?string}
     */
    public static function remindDebt(int $customerId): array
    {
        $c = DB::table('inventory_customers')->where('id', $customerId)->first();
        $owed = CustomerDebt::left($customerId);
        if ($c === null || trim((string) ($c->phone ?? '')) === '') {
            return ['sent' => false, 'owed' => $owed, 'reason' => 'no_phone'];
        }
        if ((bool) ($c->sms_opt_out ?? false)) {
            return ['sent' => false, 'owed' => $owed, 'reason' => 'opted_out'];
        }
        if ($owed <= 0) {
            return ['sent' => false, 'owed' => $owed, 'reason' => 'owes_nothing'];
        }
        $business = self::business();
        if ($business === null) {
            return ['sent' => false, 'owed' => $owed, 'reason' => null];
        }
        if ($business->smsPaused()) {
            return ['sent' => false, 'owed' => $owed, 'reason' => 'sms_paused'];
        }
        $sent = SmsService::sendFor($business, trim((string) $c->phone), self::debtReminderMessage((string) $c->name, (string) $business->name, $owed));

        return ['sent' => $sent, 'owed' => $owed, 'reason' => null];
    }

    /** A debt that is this many days old (or past its due date) is reminded about, and then again no sooner than this many days later. */
    public const DEBT_REMIND_AFTER_DAYS = 7;

    /** Most customers reminded in one run, per business (a guard on the cost of texts). */
    public const DEBT_REMIND_MAX = 100;

    /**
     * The customers who are due a reminder: they owe, have a phone and have not asked for no texts, their debt is at least a week old (or past
     * its due date, or an old debt from before the app that began a week ago), and they were not reminded in the last week.
     *
     * @return array<int, int> customer ids
     */
    public static function customersDueDebtReminder(Carbon $today): array
    {
        $cut = $today->copy()->subDays(self::DEBT_REMIND_AFTER_DAYS);
        $fromSales = DB::table('inventory_sales')->whereNull('cancelled_at')->whereNotNull('customer_id')->whereIn('payment_status', ['debt', 'partial'])
            ->where(fn ($q) => $q->where('created_at', '<=', $cut->copy()->utc()->format('Y-m-d H:i:s'))->orWhere(fn ($w) => $w->whereNotNull('due_date')->where('due_date', '<', $today->toDateString())))
            ->distinct()->pluck('customer_id')->all();
        $fromOld = Schema::hasTable('inventory_opening_debts')
            ? DB::table('inventory_opening_debts')->where('kind', OpeningDebts::RECEIVABLE)->whereNotNull('customer_id')->whereRaw('amount - paid_amount > 0')
                ->where('started_on', '<=', $cut->toDateString())->distinct()->pluck('customer_id')->all()
            : [];
        $ids = array_values(array_unique(array_map('intval', array_merge($fromSales, $fromOld))));
        if ($ids === []) {
            return [];
        }

        $last = DB::table('inventory_settings')->where('key', 'like', 'inv_debt_reminded_%')->pluck('value', 'key')->all();
        $due = [];
        foreach (DB::table('inventory_customers')->whereIn('id', $ids)->where(fn ($q) => $q->whereNull('sms_opt_out')->orWhere('sms_opt_out', false))
            ->whereNotNull('phone')->where('phone', '!=', '')->orderBy('id')->pluck('id') as $id) {
            $when = $last['inv_debt_reminded_' . $id] ?? null;
            if ($when !== null && $when > $cut->toDateString()) {
                continue;
            }
            $due[] = (int) $id;
        }

        return $due;
    }

    /** Remember that a customer was reminded today (so it is a week before the next one). */
    public static function markDebtReminded(int $customerId, Carbon $today): void
    {
        DB::table('inventory_settings')->updateOrInsert(['key' => 'inv_debt_reminded_' . $customerId], ['value' => $today->toDateString(), 'updated_at' => now()]);
    }
}
