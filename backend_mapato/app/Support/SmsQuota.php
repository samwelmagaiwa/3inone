<?php

namespace App\Support;

use App\Models\Business;
use App\Services\SmsService;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * How many SMS a business has used, the limit the super admin set for it, and what happens at the limit.
 *
 *   - Every text the business sends (through SmsService::sendFor, once the provider took it) adds to its counter `sms_used`, is written to
 *     `sms_logs` (kept 3 days, see prune()) and to `sms_daily_counts` (kept, for "this week"). Platform texts (sign-in codes, billing,
 *     these alerts) are not the business's and are not counted.
 *   - A count is in SMS parts, as the provider bills them (160 plain characters, 70 with other letters; longer texts in 153/67 pieces),
 *     unless `sms.count_by` is "messages".
 *   - No limit (NULL) = nothing is ever blocked: every business starts so.
 *   - At `sms.warn_at_percent` of the limit the owner and the super admin(s) are texted once; at the limit they are texted once more and the
 *     business's texts stop until the super admin raises the limit or starts the counter again.
 */
final class SmsQuota
{
    public const LOG_DAYS = 3;

    private const TIMEZONE = 'Africa/Dar_es_Salaam';

    // ------------------------------------------------------------------ counting

    /** How many SMS a text costs. */
    public static function parts(string $message): int
    {
        if ((string) config('sms.count_by', 'parts') === 'messages') {
            return 1;
        }
        $plain = preg_match('/^[\x{0020}-\x{007E}\r\n]*$/u', $message) === 1;
        $length = mb_strlen($message);
        if ($length === 0) {
            return 1;
        }
        [$single, $multi] = $plain ? [160, 153] : [70, 67];

        return $length <= $single ? 1 : (int) ceil($length / $multi);
    }

    /** The business may not send: it has a limit and has used it all. */
    public static function blocked(Business $business): bool
    {
        $limit = $business->sms_limit;

        return $limit !== null && (int) $business->sms_used >= (int) $limit;
    }

    /** A text was refused because the limit is used up: tell the owner and the super admin, once. Never throws. */
    public static function refused(Business $business): void
    {
        try {
            if ($business->sms_limit_reached_at !== null) {
                return;
            }
            $claimed = DB::table('businesses')->where('id', $business->id)->whereNull('sms_limit_reached_at')->update(['sms_limit_reached_at' => now()]);
            if ($claimed === 1) {
                $business->sms_limit_reached_at = now();
                self::alert($business->fresh('owner'), reached: true);
            }
        } catch (\Throwable $e) {
            Log::warning('SMS limit alert failed: ' . $e->getMessage());
        }
    }

    /** One text the provider accepted for the business: count it, log it, and tell people when a line is crossed. Never throws. */
    public static function record(Business $business, string $phone, string $message, ?string $sender): void
    {
        try {
            $parts = self::parts($message);
            $now = now();
            $day = Carbon::now(self::TIMEZONE)->toDateString();

            DB::table('businesses')->where('id', $business->id)->update(['sms_used' => DB::raw('sms_used + ' . $parts)]);
            DB::table('sms_logs')->insert([
                'business_id' => $business->id,
                'to_phone' => mb_substr($phone, 0, 32),
                'message' => $message,
                'parts' => $parts,
                'sender' => $sender !== null ? mb_substr($sender, 0, 40) : null,
                'sent_at' => $now,
            ]);
            DB::table('sms_daily_counts')->insertOrIgnore(['business_id' => $business->id, 'day' => $day, 'messages' => 0, 'parts' => 0]);
            DB::table('sms_daily_counts')->where('business_id', $business->id)->where('day', $day)->update([
                'messages' => DB::raw('messages + 1'),
                'parts' => DB::raw('parts + ' . $parts),
            ]);

            $fresh = Business::withoutAccountScope()->with('owner')->find($business->id);
            if ($fresh === null || $fresh->sms_limit === null) {
                return;
            }
            $business->sms_used = $fresh->sms_used;
            $used = (int) $fresh->sms_used;
            $limit = (int) $fresh->sms_limit;

            if ($used >= $limit) {
                self::refused($fresh);
            } elseif ($fresh->sms_limit_warned_at === null && $limit > 0 && $used * 100 >= $limit * self::warnPercent()) {
                $claimed = DB::table('businesses')->where('id', $fresh->id)->whereNull('sms_limit_warned_at')->update(['sms_limit_warned_at' => now()]);
                if ($claimed === 1) {
                    self::alert($fresh, reached: false);
                }
            }
        } catch (\Throwable $e) {
            Log::warning('SMS could not be counted: ' . $e->getMessage());
        }
    }

    private static function warnPercent(): int
    {
        return max(1, min(99, (int) config('sms.warn_at_percent', 90)));
    }

    // ------------------------------------------------------------------ the super admin sets it

    /**
     * Set the limit (null = none) and, when asked, start the counter at 0 again (a new SMS bundle was paid for). The "told" marks are cleared
     * when the business is back under them, so it is warned again next time. The owner is texted the new figures when there is a limit.
     */
    public static function setLimit(Business $business, ?int $limit, bool $resetUsed): Business
    {
        $used = $resetUsed ? 0 : (int) $business->sms_used;
        $update = ['sms_limit' => $limit];
        if ($resetUsed) {
            $update['sms_used'] = 0;
        }
        if ($limit === null || $used < $limit) {
            $update['sms_limit_reached_at'] = null;
        }
        if ($limit === null || $used * 100 < $limit * self::warnPercent()) {
            $update['sms_limit_warned_at'] = null;
        }
        DB::table('businesses')->where('id', $business->id)->update($update);

        $fresh = Business::withoutAccountScope()->with('owner')->findOrFail($business->id);
        if ($limit !== null) {
            self::tellOwner($fresh, self::bundleMessage($fresh));
        }

        return $fresh;
    }

    // ------------------------------------------------------------------ what is shown

    /** @return array<string, mixed> */
    public static function usage(Business $business): array
    {
        $used = (int) $business->sms_used;
        $limit = $business->sms_limit === null ? null : (int) $business->sms_limit;
        $weekStart = Carbon::now(self::TIMEZONE)->startOfWeek()->toDateString();
        $week = DB::table('sms_daily_counts')->where('business_id', $business->id)->where('day', '>=', $weekStart)
            ->selectRaw('COALESCE(SUM(messages), 0) as messages, COALESCE(SUM(parts), 0) as parts')->first();

        return [
            'used' => $used,
            'limit' => $limit,
            'remaining' => $limit === null ? null : max($limit - $used, 0),
            'percent' => ($limit === null || $limit === 0) ? null : min(100, (int) floor($used * 100 / $limit)),
            'blocked' => self::blocked($business),
            'warned' => $business->sms_limit_warned_at !== null,
            'week_messages' => (int) ($week->messages ?? 0),
            'week_parts' => (int) ($week->parts ?? 0),
            'counted_in' => (string) config('sms.count_by', 'parts') === 'messages' ? 'messages' : 'parts',
        ];
    }

    /** The texts the business sent in the last 3 days, newest first. @return array<int, array<string, mixed>> */
    public static function recent(Business $business, int $limit = 300): array
    {
        return DB::table('sms_logs')->where('business_id', $business->id)->orderByDesc('sent_at')->orderByDesc('id')->limit($limit)
            ->get(['id', 'to_phone', 'message', 'parts', 'sender', 'sent_at'])
            ->map(fn ($r) => [
                'id' => (int) $r->id,
                'to' => (string) $r->to_phone,
                'message' => (string) $r->message,
                'parts' => (int) $r->parts,
                'sender' => $r->sender,
                'sent_at' => Carbon::parse($r->sent_at)->toIso8601String(),
            ])->all();
    }

    /** Delete the logged texts older than 3 days. The counters stay. Returns how many rows went. */
    public static function prune(): int
    {
        return DB::table('sms_logs')->where('sent_at', '<', now()->subDays(self::LOG_DAYS))->delete();
    }

    // ------------------------------------------------------------------ the texts

    private static function alert(Business $business, bool $reached): void
    {
        $used = (int) $business->sms_used;
        $limit = (int) $business->sms_limit;
        $left = max($limit - $used, 0);
        $owner = trim((string) ($business->owner?->name ?? '')) ?: 'Mteja';

        $ownerText = "Ndugu {$owner}, mmiliki wa biashara ya {$business->name},\n\n"
            . ($reached
                ? "Tunakujulisha kuwa kifurushi chako cha SMS ({$limit}) kimeisha, hivyo SMS kwa wateja wako zimesimamishwa. Tafadhali wasiliana na Administrator kulipia na kuongeza SMS ili huduma iendelee."
                : "Tunakujulisha kuwa umetumia SMS {$used} kati ya {$limit}, zimebaki {$left}. Tafadhali wasiliana na Administrator kuongeza SMS kabla hazijaisha ili wateja wako waendelee kupata SMS.")
            . "\n\nAsante kwa kuwa mteja wetu.\n\n" . self::help();
        self::tellOwner($business, $ownerText);

        $who = trim($owner . ' ' . (string) ($business->owner?->phone_number ?? ''));
        $adminText = $reached
            ? "3inone SMS: \"{$business->name}\" ({$who}) imefikia kikomo cha SMS {$used}/{$limit}. SMS zake zimesimamishwa hadi uongeze kikomo."
            : "3inone SMS: \"{$business->name}\" ({$who}) imetumia SMS {$used}/{$limit}, zimebaki {$left}.";
        foreach (SuperAdminPhones::all() as $phone) {
            SmsService::send($phone, $adminText);
        }
    }

    private static function bundleMessage(Business $business): string
    {
        $owner = trim((string) ($business->owner?->name ?? '')) ?: 'Mteja';
        $used = (int) $business->sms_used;
        $limit = (int) $business->sms_limit;
        $left = max($limit - $used, 0);

        return "Ndugu {$owner}, mmiliki wa biashara ya {$business->name},\n\n"
            . "Tunakujulisha kuwa kifurushi chako cha SMS kimewekwa: SMS {$limit}. Umetumia {$used}, zimebaki {$left}.\n\n"
            . "Asante kwa kuwa mteja wetu.\n\n" . self::help();
    }

    private static function help(): string
    {
        return "Kwa msaada, wasiliana nasi kupitia:\n" . trim((string) config('sms.support_phones', '0617919104 / 0743519104'));
    }

    /** To the owner's phone (else the business's), under the PLATFORM's name: the business's own texts may be stopped. */
    private static function tellOwner(Business $business, string $text): void
    {
        $phone = trim((string) ($business->owner?->phone_number ?? '')) ?: trim((string) $business->phone);
        if ($phone !== '') {
            SmsService::send($phone, $text);
        }
    }
}
