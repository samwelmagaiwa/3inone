<?php

namespace App\Services;

use App\Services\Sms\SmsGateway;
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
     * @param  bool  $sensitive  the text holds a one-time code: keep it out of production logs
     */
    public static function send($phone, $message, bool $sensitive = false): bool
    {
        try {
            return app(SmsGateway::class)->send((string) $phone, (string) $message, $sensitive);
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

    // The messages below go out under the platform's sender id (one id for everyone), so each one
    // names the business it is really from, and how to reach it. $business is a business identity
    // (Business::identity()): name and phone are used when present, and without one the text reads
    // as it always did.

    public static function sendPaymentReceipt($phone, $amount, $receiptNo, $balance, ?array $business = null)
    {
        $message = "Dear Customer, payment of TZS " . number_format($amount) . " received" . self::by($business)
            . ". Receipt No: {$receiptNo}. Remaining Balance: TZS " . number_format($balance) . ". Thank you." . self::contact($business);
        return self::send($phone, $message);
    }

    public static function sendRentReminder($phone, $houseNo, $amount, $dueDate, ?array $business = null)
    {
        $message = self::from($business) . "Reminder: Your rent for House {$houseNo} (TZS " . number_format($amount) . ") is due on {$dueDate}. Please pay on time to avoid penalties." . self::contact($business);
        return self::send($phone, $message);
    }

    public static function sendOverdueAlert($phone, $houseNo, $balance, ?array $business = null)
    {
        $message = self::from($business) . "URGENT: Your rent for House {$houseNo} is OVERDUE. Outstanding balance: TZS " . number_format($balance) . ". Please settle immediately." . self::contact($business);
        return self::send($phone, $message);
    }

    public static function sendTenantWelcome($tenant, $house, ?array $business = null)
    {
        $message = self::from($business) . "Welcome to {$house->property->name}! You have been registered " .
            "for House {$house->house_number}. Your monthly rent is TZS " .
            number_format($house->rent_amount) . ". Thank you." . self::contact($business);
        return self::send($tenant->phone_number, $message);
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
