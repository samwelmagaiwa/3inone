<?php

namespace App\Support;

use App\Models\User;

/**
 * The phone numbers that are texted when something needs the platform's super admin: every active super
 * admin who has a number saved, plus the comma-separated SUPER_ADMIN_NOTIFY_PHONES (an office phone, an owner
 * who is not a login). One number is listed once however many ways it is written.
 */
class SuperAdminPhones
{
    /** @return array<int, string> */
    public static function all(): array
    {
        $numbers = User::query()
            ->where('role', 'super_admin')
            ->where('is_active', true)
            ->whereNotNull('phone_number')
            ->pluck('phone_number')
            ->all();

        $numbers = array_merge($numbers, explode(',', (string) config('sms.admin_notify_phones', '')));

        $unique = [];
        foreach ($numbers as $number) {
            $number = trim((string) $number);
            $digits = preg_replace('/\D/', '', $number) ?? '';
            if (strlen($digits) < 9) {
                continue;
            }
            $unique[substr($digits, -9)] ??= $number;
        }

        return array_values($unique);
    }
}
