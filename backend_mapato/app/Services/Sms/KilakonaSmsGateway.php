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
    /** The provider answered the last send but did not accept it. */
    private bool $refused = false;

    public function lastSendWasRefused(): bool
    {
        return $this->refused;
    }

    public function delivers(): bool
    {
        return (bool) config('sms.enabled')
            && (string) config('sms.kilakona.api_key') !== ''
            && (string) config('sms.kilakona.secret_key') !== '';
    }

    public function send(string $to, string $message, bool $sensitive = false, ?string $senderId = null, ?array $credentials = null): bool
    {
        $this->refused = false;
        $number = PhoneNumber::international($to);
        $masked = PhoneNumber::mask($number);

        if ($number === '') {
            Log::warning('SMS not sent: the phone number is empty or invalid.');

            return false;
        }

        if (!$this->delivers()) {
            // Switched off or not configured: behave like the logging stand-in, so a
            // developer machine without credentials never fails because of SMS.
            return (new LogSmsGateway())->send($number, $message, $sensitive, $senderId, $credentials);
        }

        try {
            // A business with an account of its own pays and is named from it; everyone else uses the platform's.
            $key = trim((string) ($credentials['api_key'] ?? '')) !== '' ? (string) $credentials['api_key'] : (string) config('sms.kilakona.api_key');
            $secret = trim((string) ($credentials['api_secret'] ?? '')) !== '' ? (string) $credentials['api_secret'] : (string) config('sms.kilakona.secret_key');

            $response = Http::withHeaders([
                'api-key' => $key,
                'api_secret' => $secret,
            ])
                ->acceptJson()
                ->asJson()
                ->timeout((int) config('sms.kilakona.timeout', 10))
                ->post((string) config('sms.kilakona.api_url'), [
                    // A business's own registered name when one is given, else the platform's.
                    'senderId' => ($senderId !== null && $senderId !== '') ? $senderId : (string) config('sms.kilakona.sender_id'),
                    'messageType' => 'text',
                    'contacts' => $number,
                    'message' => $message,
                ]);

            if (!$response->successful()) {
                $this->refused = true;
                Log::error("Kilakona SMS to {$masked} failed: HTTP {$response->status()}");

                return false;
            }

            $body = $response->json() ?? [];
            $sent = ($body['success'] ?? false) === true
                || (isset($body['code']) && (int) $body['code'] === 200);

            if (!$sent) {
                $this->refused = true;
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
