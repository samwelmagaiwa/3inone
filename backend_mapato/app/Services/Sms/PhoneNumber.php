<?php

namespace App\Services\Sms;

/**
 * Phone numbers as an SMS provider wants them: international, digits only.
 */
final class PhoneNumber
{
    /**
     * 0743519100, +255743519100, 255743519100 and 743519100 all become 255743519100.
     * Returns an empty string for something that cannot be a phone number.
     */
    public static function international(string $raw, ?string $countryCode = null): string
    {
        $country = $countryCode ?? (string) config('sms.country_code', '255');
        $digits = preg_replace('/\D/', '', $raw) ?? '';

        if ($digits === '') {
            return '';
        }
        if (str_starts_with(trim($raw), '+')) {
            return $digits;
        }
        if (str_starts_with($digits, '00')) {
            return substr($digits, 2);
        }
        if (str_starts_with($digits, '0')) {
            return $country . substr($digits, 1);
        }
        if (str_starts_with($digits, $country) && strlen($digits) > strlen($country) + 8) {
            return $digits;
        }

        return $country . $digits;
    }

    /** 255743519100 -> 2557*****100: enough to recognise, not enough to misuse, for logs. */
    public static function mask(string $number): string
    {
        $digits = preg_replace('/\D/', '', $number) ?? '';
        if (strlen($digits) <= 6) {
            return str_repeat('*', strlen($digits));
        }

        return substr($digits, 0, 4) . str_repeat('*', strlen($digits) - 7) . substr($digits, -3);
    }
}
