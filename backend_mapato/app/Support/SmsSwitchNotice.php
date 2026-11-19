<?php

namespace App\Support;

use App\Models\Business;
use App\Services\SmsService;
use Illuminate\Support\Facades\Log;

/**
 * The text a business owner gets when the SUPER ADMIN switches the business's SMS off, or back on.
 *
 * It goes out under the PLATFORM's name (SmsService::send), never the business's: while the business's texts are off, a text through
 * the business would be blocked by its own switch. It is sent only when the state really changed, and never breaks the switch itself.
 * The owner moving their own switch gets no text: they did it themselves and see it on their screen.
 */
final class SmsSwitchNotice
{
    public static function offMessage(string $owner, string $business): string
    {
        return "Ndugu {$owner}, mmiliki wa biashara ya {$business},\n\n"
            . "Tunakujulisha kuwa huduma ya kutuma SMS kwa wateja wako imezimwa kwa muda. Tafadhali wasiliana na Administrator ili huduma hii iweze kurejeshwa na kuruhusu SMS kuendelea kuwafikia wateja wako.\n\n"
            . "Asante kwa kuwa mteja wetu.\n\n"
            . self::help();
    }

    public static function onMessage(string $owner, string $business): string
    {
        return "Ndugu {$owner}, mmiliki wa biashara ya {$business},\n\n"
            . "Tunakujulisha kuwa huduma ya kutuma SMS kwa wateja wako imewashwa tena. SMS zako sasa zinaendelea kuwafikia wateja wako kama kawaida.\n\n"
            . "Asante kwa kuwa mteja wetu.\n\n"
            . self::help();
    }

    private static function help(): string
    {
        return "Kwa msaada, wasiliana nasi kupitia:\n" . trim((string) config('sms.support_phones', '0617919104 / 0743519104'));
    }

    /** Text the owner of $business that its SMS are now off ($on false) or on again ($on true). True when the provider took it. */
    public static function send(Business $business, bool $on): bool
    {
        try {
            $owner = $business->owner;
            $phone = trim((string) ($owner?->phone_number ?? ''));
            if ($phone === '') {
                $phone = trim((string) $business->phone);
            }
            if ($phone === '') {
                Log::info('SMS switch notice not sent: the owner has no phone number.', ['business_id' => $business->id]);

                return false;
            }
            $name = trim((string) ($owner?->name ?? '')) ?: 'Mteja';
            $text = $on ? self::onMessage($name, (string) $business->name) : self::offMessage($name, (string) $business->name);

            return SmsService::send($phone, $text);
        } catch (\Throwable $e) {
            Log::warning('SMS switch notice could not be sent: ' . $e->getMessage());

            return false;
        }
    }
}
