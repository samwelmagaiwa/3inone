<?php

namespace App\Services\Sms;

use App\Models\User;
use App\Services\SmsService;
use Illuminate\Support\Facades\DB;

/**
 * One-time codes sent to a person's phone, to prove they hold it.
 *
 * A code is 6 digits, lives 10 minutes, can be tried 5 times, and only a keyed hash of it
 * is stored. A new code cannot be requested more often than every 60 seconds, and issuing
 * one replaces any earlier unused code for the same purpose.
 */
class SmsCodes
{
    public const PASSWORD_RESET = 'password_reset';
    public const PHONE_VERIFICATION = 'phone_verification';

    public const SENT = 'sent';
    public const THROTTLED = 'throttled';
    public const UNAVAILABLE = 'unavailable';

    private const TTL_MINUTES = 10;
    private const MAX_ATTEMPTS = 5;
    private const RESEND_SECONDS = 60;

    /**
     * Whether codes can be sent at all right now. In production they cannot unless a
     * real SMS provider is switched on: a code that only goes to a log proves nothing.
     */
    public function available(): bool
    {
        return SmsService::delivers() || !app()->isProduction();
    }

    /**
     * Create a code for $user and text it to their phone. $text holds ":code" where the
     * code goes. Returns SENT, THROTTLED (asked again too soon) or UNAVAILABLE.
     */
    public function issue(User $user, string $purpose, string $text): string
    {
        if (!$this->available()) {
            return self::UNAVAILABLE;
        }

        $recent = DB::table('sms_codes')
            ->where('user_id', $user->id)
            ->where('purpose', $purpose)
            ->where('created_at', '>', now()->subSeconds(self::RESEND_SECONDS))
            ->exists();
        if ($recent) {
            return self::THROTTLED;
        }

        $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        DB::table('sms_codes')->where('user_id', $user->id)->where('purpose', $purpose)->delete();
        $id = DB::table('sms_codes')->insertGetId([
            'user_id' => $user->id,
            'purpose' => $purpose,
            'code_hash' => $this->hash($user, $purpose, $code),
            'attempts' => 0,
            'expires_at' => now()->addMinutes(self::TTL_MINUTES),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        if (!SmsService::send($user->phone_number, str_replace(':code', $code, $text), sensitive: true)) {
            // Not sent: a code nobody received must not sit there waiting to be guessed.
            DB::table('sms_codes')->where('id', $id)->delete();

            return self::UNAVAILABLE;
        }

        return self::SENT;
    }

    /** Check a code. A right code is used up; a wrong one counts against its 5 tries. */
    public function verify(User $user, string $purpose, string $code): bool
    {
        $row = DB::table('sms_codes')
            ->where('user_id', $user->id)
            ->where('purpose', $purpose)
            ->whereNull('consumed_at')
            ->where('expires_at', '>', now())
            ->orderByDesc('id')
            ->first();

        if ($row === null) {
            return false;
        }

        if ($row->attempts >= self::MAX_ATTEMPTS) {
            DB::table('sms_codes')->where('id', $row->id)->delete();

            return false;
        }

        if (!hash_equals($row->code_hash, $this->hash($user, $purpose, trim($code)))) {
            DB::table('sms_codes')->where('id', $row->id)->increment('attempts');

            return false;
        }

        DB::table('sms_codes')->where('id', $row->id)->update(['consumed_at' => now(), 'updated_at' => now()]);

        return true;
    }

    /** Keyed with the app key and bound to the person and purpose, so a hash is useless elsewhere. */
    private function hash(User $user, string $purpose, string $code): string
    {
        return hash_hmac('sha256', "{$user->id}|{$purpose}|{$code}", (string) config('app.key'));
    }
}
