<?php

namespace App\Services\Sms;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Kilakona (messaging.kilakona.co.tz). Credentials come from config('sms.kilakona'),
 * which reads them from the environment -- they are never in the code.
 *
 * Request: POST JSON with the headers `api-key` and `api_secret`; body
 * {senderId, messageType: "text", contacts: "2557...", message}. A reply is a success
 * when it says {"success": true} or {"code": 200}.
 */
class KilakonaSmsGateway implements SmsGateway
{
    public function delivers(): bool
    {
        return (bool) config('sms.enabled')
            && (string) config('sms.kilakona.api_key') !== ''
            && (string) config('sms.kilakona.secret_key') !== '';
    }

    public function send(string $to, string $message, bool $sensitive = false): bool
    {
        $number = PhoneNumber::international($to);
        $masked = PhoneNumber::mask($number);

        if ($number === '') {
            Log::warning('SMS not sent: the phone number is empty or invalid.');

            return false;
        }

        if (!$this->delivers()) {
            // Switched off or not configured: behave like the logging stand-in, so a
            // developer machine without credentials never fails because of SMS.
            return (new LogSmsGateway())->send($number, $message, $sensitive);
        }

        try {
            $response = Http::withHeaders([
                'api-key' => (string) config('sms.kilakona.api_key'),
                'api_secret' => (string) config('sms.kilakona.secret_key'),
            ])
                ->acceptJson()
                ->asJson()
                ->timeout((int) config('sms.kilakona.timeout', 10))
                ->post((string) config('sms.kilakona.api_url'), [
                    'senderId' => (string) config('sms.kilakona.sender_id'),
                    'messageType' => 'text',
                    'contacts' => $number,
                    'message' => $message,
                ]);

            if (!$response->successful()) {
                Log::error("Kilakona SMS to {$masked} failed: HTTP {$response->status()}");

                return false;
            }

            $body = $response->json() ?? [];
            $sent = ($body['success'] ?? false) === true
                || (isset($body['code']) && (int) $body['code'] === 200);

            if (!$sent) {
                // The provider's own answer is logged, never the message (it may hold a code).
                Log::warning("Kilakona SMS to {$masked} was not accepted: " . substr($response->body(), 0, 300));
            }

            return $sent;
        } catch (\Throwable $e) {
            Log::error("Kilakona SMS to {$masked} failed: " . $e->getMessage());

            return false;
        }
    }
}
