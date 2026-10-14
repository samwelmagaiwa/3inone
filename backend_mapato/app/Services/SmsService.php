<?php

namespace App\Services;

use App\Models\Business;
use App\Services\Sms\SmsGateway;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

/**
 * The one place the app sends text messages from. What actually happens to a message
 * (a real provider, or just the log) is decided by the SmsGateway bound in the container,
 * from config/sms.php.
 */
class SmsService
{
    /**
     * Send an SMS. Never throws: a failing provider must not break a payment or a sign-up.
     * Returns whether the message was accepted.
     *
     * Platform messages (codes, registration, billing) go out under the platform's own sender name. A text on
     * behalf of a business goes through sendFor(), which uses that business's registered sender name.
     *
     * @param  bool  $sensitive  the text holds a one-time code: keep it out of production logs
     */
    public static function send($phone, $message, bool $sensitive = false, ?string $senderId = null): bool
    {
        try {
            return app(SmsGateway::class)->send((string) $phone, (string) $message, $sensitive, $senderId);
        } catch (\Throwable $e) {
            Log::warning('SMS could not be sent: ' . $e->getMessage());

            return false;
        }
    }

    /** True when a message sent now really reaches a phone (a real provider is switched on). */
    public static function delivers(): bool
    {
        try {
            return app(SmsGateway::class)->delivers();
        } catch (\Throwable) {
            return false;
        }
    }

    /**
     * Send a text on behalf of a business, to one of ITS customers, under the business's own sender name.
     *
     *   - A business with no approved sender name sends under the platform's (the text names the business).
     *   - If the provider answers that it does not accept the business's name (it was never registered, or was
     *     withdrawn), the text is sent once more under the platform's name, so the customer is still told, and the
     *     business is flagged so the super admin can fix the name.
     *   - If the provider gives NO answer (a timeout) nothing is resent: the message may already be on its way.
     *
     * Given an identity array (or nothing) there is no business to take a name from: a plain platform text.
     *
     * @param  Business|array<string, mixed>|null  $business
     */
    public static function sendFor($business, $phone, $message): bool
    {
        if (!$business instanceof Business) {
            return self::send($phone, $message);
        }

        try {
            $gateway = app(SmsGateway::class);
            $sender = $business->usableSmsSender();

            if ($sender === null) {
                $sent = $gateway->send((string) $phone, (string) $message, false, null);
                if ($sent) {
                    self::record($business, $gateway, own: false);
                }

                return $sent;
            }

            // Its own name, and its own account when it has one (the platform's otherwise).
            $own = $business->smsCredentials();
            if ($gateway->send((string) $phone, (string) $message, false, $sender, $own)) {
                self::record($business, $gateway, own: true);

                return true;
            }

            if (!$gateway->lastSendWasRefused()) {
                return false;
            }

            $whatSw = $own !== null ? "jina la mtumaji \"{$sender}\" au API key" : "jina la mtumaji \"{$sender}\"";
            $whatEn = $own !== null ? "the sender name \"{$sender}\" or the API key" : "the sender name \"{$sender}\"";

            // A business that has its own account may be set NOT to spend the platform's SMS credit when that
            // account runs dry or its key is wrong: then the text is lost, and the super admin is told.
            if (!$business->smsMayFallBack()) {
                self::record($business, $gateway, own: false, failure: "Kilakona haikukubali {$whatSw}. Ujumbe HAUKUTUMWA. / Kilakona did not accept {$whatEn}. The text was NOT sent.");

                return false;
            }

            $sent = $gateway->send((string) $phone, (string) $message, false, null);
            if ($sent) {
                // Only now do we know the NAME or key was the problem (the same text went through without them).
                self::record($business, $gateway, own: false, fallbackError: "Kilakona haikukubali {$whatSw}. Ujumbe unatoka kwa akaunti ya jukwaa hadi litakaporekebishwa. / Kilakona did not accept {$whatEn}. Texts go out through the platform until it is fixed.");
            }

            return $sent;
        } catch (\Throwable $e) {
            Log::warning('SMS for a business could not be sent: ' . $e->getMessage());

            return false;
        }
    }

    /**
     * Try a sender name with one real message, without falling back to another name, so a super admin can see
     * whether the provider accepts it before approving it.
     *
     * @return array{outcome: string, delivers: bool}  outcome: accepted | refused | no_answer | not_delivering
     */
    public static function sendTest(string $phone, string $senderId, string $message, ?array $credentials = null): array
    {
        try {
            $gateway = app(SmsGateway::class);
            if (!$gateway->delivers()) {
                return ['outcome' => 'not_delivering', 'delivers' => false];
            }

            $sent = $gateway->send($phone, $message, false, $senderId, $credentials);

            return [
                'outcome' => $sent ? 'accepted' : ($gateway->lastSendWasRefused() ? 'refused' : 'no_answer'),
                'delivers' => true,
            ];
        } catch (\Throwable $e) {
            Log::warning('SMS test could not be sent: ' . $e->getMessage());

            return ['outcome' => 'no_answer', 'delivers' => true];
        }
    }

    /**
     * Count one accepted business text, and remember whether the business's own name worked. Never breaks the send.
     * Nothing is counted while no real provider is switched on (the log stand-in "accepts" everything).
     */
    private static function record(Business $business, SmsGateway $gateway, bool $own, ?string $fallbackError = null, ?string $failure = null): void
    {
        try {
            if (!$gateway->delivers()) {
                return;
            }

            if ($failure !== null) {
                // Nothing was sent: only say why, so the super admin sees the name or key that stopped working.
                DB::table('businesses')->where('id', $business->id)->update(['sms_last_error' => $failure]);

                return;
            }

            $update = [
                'sms_sent_count' => DB::raw('sms_sent_count + 1'),
                'sms_last_sent_at' => now(),
            ];
            if ($own) {
                $update['sms_own_count'] = DB::raw('sms_own_count + 1');
                $update['sms_last_error'] = null;
            }
            if ($fallbackError !== null) {
                $update['sms_fallback_count'] = DB::raw('sms_fallback_count + 1');
                $update['sms_last_error'] = $fallbackError;
            }

            DB::table('businesses')->where('id', $business->id)->update($update);
        } catch (\Throwable $e) {
            Log::warning('SMS counters could not be updated: ' . $e->getMessage());
        }
    }

    // The messages below are from a business to its own customers. $business is the Business itself (so its
    // registered sender name is used) or, when it cannot be found, an identity array / nothing and the text goes
    // out under the platform's name. The text always names the business (its short display name when it set
    // one) and says how to reach it, so a customer knows who it is from whatever name the phone shows.

    public static function sendPaymentReceipt($phone, $amount, $receiptNo, $balance, $business = null)
    {
        $identity = self::identity($business);
        $message = "Dear Customer, payment of TZS " . number_format($amount) . " received" . self::by($identity)
            . ". Receipt No: {$receiptNo}. Remaining Balance: TZS " . number_format($balance) . ". Thank you." . self::contact($identity);
        return self::sendFor($business, $phone, $message);
    }

    public static function sendRentReminder($phone, $houseNo, $amount, $dueDate, $business = null)
    {
        $identity = self::identity($business);
        $message = self::from($identity) . "Reminder: Your rent for House {$houseNo} (TZS " . number_format($amount) . ") is due on {$dueDate}. Please pay on time to avoid penalties." . self::contact($identity);
        return self::sendFor($business, $phone, $message);
    }

    public static function sendOverdueAlert($phone, $houseNo, $balance, $business = null)
    {
        $identity = self::identity($business);
        $message = self::from($identity) . "URGENT: Your rent for House {$houseNo} is OVERDUE. Outstanding balance: TZS " . number_format($balance) . ". Please settle immediately." . self::contact($identity);
        return self::sendFor($business, $phone, $message);
    }

    public static function sendTenantWelcome($tenant, $house, $business = null)
    {
        $identity = self::identity($business);
        $message = self::from($identity) . "Welcome to {$house->property->name}! You have been registered " .
            "for House {$house->house_number}. Your monthly rent is TZS " .
            number_format($house->rent_amount) . ". Thank you." . self::contact($identity);
        return self::sendFor($business, $tenant->phone_number, $message);
    }

    /**
     * The name and phone a text carries. For a Business that is its short display name (or its name) and phone.
     *
     * @param  Business|array<string, mixed>|null  $business
     * @return array<string, mixed>|null
     */
    private static function identity($business): ?array
    {
        if ($business instanceof Business) {
            return ['name' => $business->smsName(), 'phone' => (string) $business->phone];
        }

        return is_array($business) ? $business : null;
    }

    /** "Mama Store: " -- the start of a message that is from a business. */
    private static function from(?array $business): string
    {
        $name = trim((string) ($business['name'] ?? ''));

        return $name !== '' ? "{$name}: " : '';
    }

    /** " by Mama Store" -- for a sentence that says what the business did. */
    private static function by(?array $business): string
    {
        $name = trim((string) ($business['name'] ?? ''));

        return $name !== '' ? " by {$name}" : '';
    }

    /** " Contact: 0712345678." -- how to reach the business, when it has said. */
    private static function contact(?array $business): string
    {
        $phone = trim((string) ($business['phone'] ?? ''));

        return $phone !== '' ? " Contact: {$phone}." : '';
    }
}
