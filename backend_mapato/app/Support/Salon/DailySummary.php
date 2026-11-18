<?php

namespace App\Support\Salon;

use Illuminate\Support\Facades\DB;

/**
 * The text the owner gets at the end of the day: what came in, what went out, what is left, how many clients. Off until
 * the owner switches it off.
 */
final class DailySummary
{
    private const KEY = 'salon_daily_summary';

    public static function isOn(): bool
    {
        // On from the start: only an owner who switched it off (a stored 0) goes without.
        return DB::table('inventory_settings')->where('key', self::KEY)->value('value') !== '0';
    }

    public static function save(bool $on): void
    {
        DB::table('inventory_settings')->updateOrInsert(['key' => self::KEY], ['value' => $on ? '1' : '0', 'updated_at' => now()]);
    }

    /**
     * "Leo GLOW: mapato TSh 185,000, matumizi TSh 42,000, faida TSh 143,000, wateja 9. Tofauti ya faida na jana: +TSh 12,000."
     * Personal spending is never taken off the profit; when there was some, the text says so.
     *
     * @param array<string, mixed> $s the day's {@see SalonFinance::summary()} (spending and profit already without personal spending)
     */
    public static function message(string $business, array $s, ?float $yesterdayProfit = null, float $personal = 0.0): string
    {
        $tsh = fn ($v) => number_format((float) $v, 0, '.', ',');
        $business = trim((string) preg_replace('/\s+/u', ' ', $business)) ?: 'saluni yako';
        $profit = (float) $s['net_profit'];
        $word = $profit >= 0 ? 'faida' : 'hasara';
        $diff = '';
        if ($yesterdayProfit !== null) {
            $d = $profit - $yesterdayProfit;
            $diff = ' Tofauti ya faida na jana: ' . ($d < 0 ? '-' : '+') . 'TSh ' . $tsh(abs($d)) . '.';
        }
        $own = $personal > 0 ? " Matumizi binafsi TSh {$tsh($personal)} hayahesabiwi kwenye faida." : '';

        return "Leo {$business}: mapato TSh {$tsh($s['revenue'])}, matumizi TSh {$tsh($s['expenses'])}, {$word} TSh {$tsh(abs($profit))}, wateja {$s['clients']}.{$diff}{$own}";
    }
}
