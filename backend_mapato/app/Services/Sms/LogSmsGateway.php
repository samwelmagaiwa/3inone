<?php

namespace App\Services\Sms;

use Illuminate\Support\Facades\Log;

/**
 * Stand-in used when no real provider is configured (local development, tests).
 * It writes the message to the log instead of sending it. A message that carries a
 * secret is written in full only outside production, so a developer can read a code
 * from the log, but a production log never holds one.
 */
class LogSmsGateway implements SmsGateway
{
    public function delivers(): bool
    {
        return false;
    }

    public function send(string $to, string $message, bool $sensitive = false): bool
    {
        $shown = $sensitive && app()->isProduction() ? '[withheld: sensitive]' : $message;
        Log::info('SMS not delivered (no provider): to ' . PhoneNumber::mask($to) . ": {$shown}");

        return true;
    }
}
