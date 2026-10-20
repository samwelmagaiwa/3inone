<?php

namespace App\Support\Salon;

use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

/**
 * What makes a salon client come back, kept in one place and called from the sale only for a SALON:
 *  - loyalty points: earned when a sale is fully paid, spent as a discount, taken back if the sale is cancelled;
 *  - vouchers: a code worth a percent or an amount off, with an end date and a number of uses;
 *  - referrals: the client who sent someone earns points when that person first pays for a service;
 *  - packages: a service sold as N visits; each visit later is free at the till and uses one up.
 *
 * Nothing here runs for the shop (or any other service), and every column it needs is checked first so the code can be
 * released before the migration has run.
 */
final class SalonPerks
{
    private const KEY_ON = 'salon_loyalty_on';

    private const KEY_PER = 'salon_points_per';

    private const KEY_VALUE = 'salon_points_value';

    private const KEY_REFERRAL = 'salon_referral_points';

    public const DEFAULT_PER = 1000;

    public const DEFAULT_VALUE = 100;

    public const DEFAULT_REFERRAL = 50;

    public static function active(): bool
    {
        return TenantContext::service() === 'salon'
            && Schema::hasTable('inventory_loyalty_ledger')
            && Schema::hasColumn('inventory_sales', 'points_earned');
    }

    // ------------------------------------------------------------------ settings

    /** @return array{on: bool, per: int, value: int, referral: int} */
    public static function settings(): array
    {
        $rows = DB::table('inventory_settings')->whereIn('key', [self::KEY_ON, self::KEY_PER, self::KEY_VALUE, self::KEY_REFERRAL])->pluck('value', 'key');

        return [
            'on' => ($rows[self::KEY_ON] ?? '0') === '1',
            // TSh spent for one point; TSh off for one point spent; points a referrer earns.
            'per' => max(1, (int) ($rows[self::KEY_PER] ?? self::DEFAULT_PER)),
            'value' => max(0, (int) ($rows[self::KEY_VALUE] ?? self::DEFAULT_VALUE)),
            'referral' => max(0, (int) ($rows[self::KEY_REFERRAL] ?? self::DEFAULT_REFERRAL)),
        ];
    }

    public static function saveSettings(?bool $on, ?int $per, ?int $value, ?int $referral): void
    {
        $write = fn (string $key, string $v) => DB::table('inventory_settings')->updateOrInsert(['key' => $key], ['value' => $v, 'updated_at' => now()]);
        if ($on !== null) {
            $write(self::KEY_ON, $on ? '1' : '0');
        }
        if ($per !== null) {
            $write(self::KEY_PER, (string) max(1, $per));
        }
        if ($value !== null) {
            $write(self::KEY_VALUE, (string) max(0, $value));
        }
        if ($referral !== null) {
            $write(self::KEY_REFERRAL, (string) max(0, $referral));
        }
    }

    public static function balance(int $customerId): int
    {
        return (int) DB::table('inventory_loyalty_ledger')->where('customer_id', $customerId)->sum('points');
    }

    // ------------------------------------------------------------------ a sale: check first, then apply

    /**
     * Everything a salon sale asks of the perks, checked BEFORE anything is written: the voucher, the points to spend,
     * the package sessions to use. Throws a 422 in both languages; otherwise returns the plan {@see self::apply()}
     * carries out.
     *
     * @return array{voucher: ?object, voucher_discount: float, points: int, points_discount: float, redemptions: array<int, object>, uses: array<int, int>}
     */
    public static function check(Request $request): array
    {
        $plan = ['voucher' => null, 'voucher_discount' => 0.0, 'points' => 0, 'points_discount' => 0.0, 'redemptions' => [], 'uses' => []];
        if (!self::active()) {
            return $plan;
        }

        $subtotal = (float) $request->input('subtotal', 0);
        $customerId = $request->integer('customer_id', 0) ?: null;
        $today = Carbon::now(AppointmentPlanner::TIMEZONE)->toDateString();

        // ---- a voucher
        $code = strtoupper(trim((string) $request->input('voucher_code', '')));
        if ($code !== '' && Schema::hasTable('inventory_vouchers')) {
            $v = DB::table('inventory_vouchers')->where('code', $code)->first();
            $fail = fn (string $sw, string $en) => throw ValidationException::withMessages(['voucher_code' => ["{$sw} / {$en}"]]);
            if ($v === null || !$v->active) {
                $fail('Kuponi hii haipo au imezimwa.', 'This voucher does not exist or is switched off.');
            }
            if ($v->expires_on !== null && Carbon::parse($v->expires_on)->toDateString() < $today) {
                $fail('Kuponi hii imeisha muda.', 'This voucher has expired.');
            }
            if ($v->max_uses !== null && (int) $v->used_count >= (int) $v->max_uses) {
                $fail('Kuponi hii imeshatumika mara zote.', 'This voucher has been used up.');
            }
            $plan['voucher'] = $v;
            $plan['voucher_discount'] = self::voucherDiscount($v, $subtotal);
        }

        // ---- points
        $points = (int) $request->input('redeem_points', 0);
        if ($points > 0) {
            $s = self::settings();
            if (!$s['on']) {
                throw ValidationException::withMessages(['redeem_points' => ['Pointi hazijawashwa. / Loyalty points are not switched on.']]);
            }
            if ($customerId === null) {
                throw ValidationException::withMessages(['redeem_points' => ['Chagua mteja ili atumie pointi. / Choose a client to spend points.']]);
            }
            $have = self::balance($customerId);
            if ($points > $have) {
                throw ValidationException::withMessages(['redeem_points' => ["Mteja ana pointi {$have} tu. / The client only has {$have} points."]]);
            }
            $plan['points'] = $points;
            $plan['points_discount'] = round(min($points * $s['value'], max(0, $subtotal - $plan['voucher_discount'])), 2);
        }

        $required = $plan['voucher_discount'] + $plan['points_discount'];
        if ($required > 0 && (float) $request->input('discount', 0) + 0.01 < $required) {
            throw ValidationException::withMessages(['discount' => ['Punguzo halilingani na kuponi au pointi. / The discount does not match the voucher or points.']]);
        }

        // ---- package sessions used by lines of this sale
        $asked = [];
        foreach ((array) $request->input('items', []) as $index => $item) {
            if (empty($item['package_id'])) {
                continue;
            }
            if ($customerId === null) {
                throw ValidationException::withMessages(['items' => ['Chagua mteja ili atumie kifurushi. / Choose a client to use a package.']]);
            }
            $pkg = DB::table('inventory_client_packages')->where('id', (int) $item['package_id'])->first();
            $qty = max(1, (int) ($item['quantity'] ?? 1));
            $asked[(int) $item['package_id']] = ($asked[(int) $item['package_id']] ?? 0) + $qty;
            $bad = $pkg === null || (int) $pkg->customer_id !== $customerId || $pkg->status !== 'active'
                || (int) $pkg->service_product_id !== (int) ($item['product_id'] ?? 0)
                || ($pkg->expires_on !== null && Carbon::parse($pkg->expires_on)->toDateString() < $today)
                || $asked[(int) $item['package_id']] > (int) $pkg->sessions_left;
            if ($bad) {
                throw ValidationException::withMessages(['items' => ['Kifurushi hakiwezi kutumika kwa huduma hii (hakipo, kimeisha, au vikao vimeisha). / This package cannot be used for this service (not found, expired or no visits left).']]);
            }
            $plan['redemptions'][(int) $index] = $pkg;
            $plan['uses'][(int) $pkg->id] = $asked[(int) $pkg->id];
        }

        // A package sold to nobody would be lost: it must be sold to a client.
        if ($customerId === null && Schema::hasColumn('inventory_products', 'package_sessions')) {
            $ids = collect((array) $request->input('items', []))->pluck('product_id')->filter()->map(fn ($v) => (int) $v)->all();
            if ($ids !== [] && DB::table('inventory_products')->whereIn('id', $ids)->where('package_sessions', '>', 0)->exists()) {
                throw ValidationException::withMessages(['customer_id' => ['Chagua mteja kwa kifurushi. / Choose the client the package is for.']]);
            }
        }

        return $plan;
    }

    private static function voucherDiscount(object $v, float $subtotal): float
    {
        $off = $v->kind === 'percent' ? round($subtotal * (float) $v->value / 100, 2) : (float) $v->value;

        return round(min(max(0.0, $off), $subtotal), 2);
    }

    /**
     * What a voucher would take off a sale of this size (for the till to show before the sale is made).
     *
     * @return array{discount: float, label: string}
     */
    public static function preview(string $code, float $subtotal): array
    {
        $code = strtoupper(trim($code));
        $today = Carbon::now(AppointmentPlanner::TIMEZONE)->toDateString();
        $v = $code === '' ? null : DB::table('inventory_vouchers')->where('code', $code)->first();
        $fail = fn (string $sw, string $en) => throw ValidationException::withMessages(['code' => ["{$sw} / {$en}"]]);
        if ($v === null || !$v->active) {
            $fail('Kuponi hii haipo au imezimwa.', 'This voucher does not exist or is switched off.');
        }
        if ($v->expires_on !== null && Carbon::parse($v->expires_on)->toDateString() < $today) {
            $fail('Kuponi hii imeisha muda.', 'This voucher has expired.');
        }
        if ($v->max_uses !== null && (int) $v->used_count >= (int) $v->max_uses) {
            $fail('Kuponi hii imeshatumika mara zote.', 'This voucher has been used up.');
        }

        return ['discount' => self::voucherDiscount($v, $subtotal), 'label' => $v->kind === 'percent' ? ((float) $v->value == floor((float) $v->value) ? (int) $v->value : (float) $v->value) . '%' : 'TSh ' . number_format((float) $v->value)];
    }

    /**
     * Carry out the plan once the sale exists: record the voucher and the points spent, make the packages that were
     * sold, use up the sessions that were redeemed, and (if the sale is already paid) give the points earned.
     *
     * @param  array<string, mixed>  $plan
     */
    public static function apply(int $saleId, ?int $customerId, string $status, float $total, array $plan, ?string $userId): void
    {
        if (!self::active()) {
            return;
        }
        $now = Carbon::now(AppointmentPlanner::TIMEZONE);

        if ($plan['voucher'] !== null && Schema::hasColumn('inventory_sales', 'voucher_code')) {
            DB::table('inventory_vouchers')->where('id', $plan['voucher']->id)->increment('used_count');
            DB::table('inventory_sales')->where('id', $saleId)->update(['voucher_code' => $plan['voucher']->code]);
        }

        if ($plan['points'] > 0 && $customerId !== null) {
            DB::table('inventory_loyalty_ledger')->insert(self::row($customerId, -$plan['points'], 'redeem', $saleId, 'Pointi zilizotumika / Points spent', $userId));
            DB::table('inventory_sales')->where('id', $saleId)->update(['points_redeemed' => $plan['points']]);
        }

        // Packages sold by this sale: one for each unit of a package product.
        if ($customerId !== null && Schema::hasColumn('inventory_products', 'package_sessions')) {
            $sold = DB::table('inventory_sale_items as si')
                ->join('inventory_products as p', 'p.id', '=', 'si.product_id')
                ->where('si.sale_id', $saleId)
                ->where('p.package_sessions', '>', 0)
                ->whereNotNull('p.package_service_id')
                ->get(['p.id', 'p.name', 'p.package_sessions', 'p.package_service_id', 'p.package_valid_days', DB::raw('COALESCE(si.unit_qty, si.quantity) as qty')]);
            foreach ($sold as $line) {
                for ($i = 0; $i < max(1, (int) $line->qty); $i++) {
                    DB::table('inventory_client_packages')->insert([
                        'customer_id' => $customerId,
                        'product_id' => (int) $line->id,
                        'service_product_id' => (int) $line->package_service_id,
                        'name' => (string) $line->name,
                        'sessions_total' => (int) $line->package_sessions,
                        'sessions_left' => (int) $line->package_sessions,
                        'expires_on' => $line->package_valid_days ? $now->copy()->addDays((int) $line->package_valid_days)->toDateString() : null,
                        'status' => 'active',
                        'sale_id' => $saleId,
                        'created_by' => $userId === null ? null : (string) $userId,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }
            }
        }

        // Sessions used by this sale.
        foreach ($plan['uses'] as $packageId => $count) {
            DB::table('inventory_client_packages')->where('id', $packageId)->decrement('sessions_left', $count);
            DB::table('inventory_client_packages')->where('id', $packageId)->where('sessions_left', '<=', 0)->update(['status' => 'used', 'updated_at' => now()]);
        }

        if ($status === 'paid') {
            self::onPaid($saleId, $userId);
        }
    }

    /** A sale has just been paid in full: the points it earns, and the referral bonus on a client's first paid visit. */
    public static function onPaid(int $saleId, ?string $userId): void
    {
        if (!self::active()) {
            return;
        }
        $sale = DB::table('inventory_sales')->where('id', $saleId)->first();
        if ($sale === null || $sale->customer_id === null || !empty($sale->cancelled_at) || (int) ($sale->points_earned ?? 0) > 0) {
            return;
        }
        $s = self::settings();
        if (!$s['on']) {
            return;
        }
        $customerId = (int) $sale->customer_id;

        $earned = (int) floor((float) $sale->total / $s['per']);
        if ($earned > 0) {
            DB::table('inventory_loyalty_ledger')->insert(self::row($customerId, $earned, 'earn', $saleId, 'Pointi za mauzo / Points for a sale', $userId));
            DB::table('inventory_sales')->where('id', $saleId)->update(['points_earned' => $earned]);
        }

        // The client who sent this one earns points the first time they pay (once, ever).
        $referrer = DB::table('inventory_customers')->where('id', $customerId)->value('referred_by');
        if ($referrer !== null && $s['referral'] > 0 && !DB::table('inventory_loyalty_ledger')->where('kind', 'referral')->where('note', 'like', "%#{$customerId}")->exists()) {
            $name = (string) DB::table('inventory_customers')->where('id', $customerId)->value('name');
            DB::table('inventory_loyalty_ledger')->insert(self::row((int) $referrer, $s['referral'], 'referral', $saleId, "Alimleta {$name} / Referred {$name} #{$customerId}", $userId));
        }
    }

    /** A sale was cancelled: take back what it earned, give back what it spent, free its voucher and its sessions. */
    public static function onCancel(object $sale, ?string $userId): void
    {
        if (!self::active()) {
            return;
        }
        $customerId = $sale->customer_id === null ? null : (int) $sale->customer_id;
        $saleId = (int) $sale->id;

        if ($customerId !== null) {
            if ((int) ($sale->points_earned ?? 0) > 0) {
                DB::table('inventory_loyalty_ledger')->insert(self::row($customerId, -(int) $sale->points_earned, 'reverse', $saleId, 'Mauzo yamefutwa / Sale cancelled', $userId));
            }
            if ((int) ($sale->points_redeemed ?? 0) > 0) {
                DB::table('inventory_loyalty_ledger')->insert(self::row($customerId, (int) $sale->points_redeemed, 'reverse', $saleId, 'Mauzo yamefutwa: pointi zimerudi / Sale cancelled: points given back', $userId));
            }
        }
        if (!empty($sale->voucher_code)) {
            DB::table('inventory_vouchers')->where('code', $sale->voucher_code)->where('used_count', '>', 0)->decrement('used_count');
        }

        if (Schema::hasColumn('inventory_sale_items', 'package_id')) {
            // Sessions that lines of this sale used are given back.
            $used = DB::table('inventory_sale_items')->where('sale_id', $saleId)->whereNotNull('package_id')
                ->selectRaw('package_id, SUM(COALESCE(unit_qty, quantity)) as n')->groupBy('package_id')->get();
            foreach ($used as $u) {
                DB::table('inventory_client_packages')->where('id', $u->package_id)->increment('sessions_left', (int) $u->n);
                DB::table('inventory_client_packages')->where('id', $u->package_id)->where('status', 'used')->where('sessions_left', '>', 0)->update(['status' => 'active', 'updated_at' => now()]);
            }
            // Packages this sale sold are cancelled.
            DB::table('inventory_client_packages')->where('sale_id', $saleId)->update(['status' => 'cancelled', 'updated_at' => now()]);
        }
    }

    /** @return array<string, mixed> */
    private static function row(int $customerId, int $points, string $kind, ?int $saleId, string $note, ?string $userId): array
    {
        return [
            'customer_id' => $customerId,
            'points' => $points,
            'kind' => $kind,
            'sale_id' => $saleId,
            'note' => $note,
            'created_by' => $userId === null ? null : (string) $userId,
            'created_at' => now(),
            'updated_at' => now(),
        ];
    }
}
