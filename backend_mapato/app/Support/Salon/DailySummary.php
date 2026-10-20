<?php

namespace App\Support\Salon;

use Illuminate\Support\Facades\DB;

/**
 * The text the owner gets at the end of the day: what came in, what went out, what is left, how many clients. Off until
 * the owner switches it on (it is an SMS, and SMS cost money).
 */
final class DailySummary
{
    private const KEY = 'salon_daily_summary';

    public static function isOn(): bool
    {
        return DB::table('inventory_settings')->where('key', self::KEY)->value('value') === '1';
    }

    public static function save(bool $on): void
    {
        DB::table('inventory_settings')->updateOrInsert(['key' => self::KEY], ['value' => $on ? '1' : '0', 'updated_at' => now()]);
    }

    /** @param array<string, mixed> $s the day's {@see SalonFinance::summary()} */
    public static function message(string $business, array $s, int $bookingsTomorrow): string
    {
        $tsh = fn ($v) => number_format((float) $v, 0, '.', ',');
        $business = trim((string) preg_replace('/\s+/u', ' ', $business)) ?: 'saluni yako';
        $profit = (float) $s['net_profit'];
        $sw = $profit >= 0 ? 'faida' : 'hasara';
        $en = $profit >= 0 ? 'profit' : 'loss';

        return "Leo {$business}: mapato TSh {$tsh($s['revenue'])}, matumizi TSh {$tsh($s['expenses'])}, {$sw} TSh {$tsh(abs($profit))}, wateja {$s['clients']}. Kesho miadi {$bookingsTomorrow}. / "
            . "Today at {$business}: revenue TSh {$tsh($s['revenue'])}, expenses TSh {$tsh($s['expenses'])}, {$en} TSh {$tsh(abs($profit))}, {$s['clients']} clients. {$bookingsTomorrow} booked tomorrow.";
    }
}
