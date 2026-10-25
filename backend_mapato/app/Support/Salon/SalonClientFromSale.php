<?php

namespace App\Support\Salon;

use App\Support\Tenancy\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * A client typed at the till (a name, a phone number) without being picked from the list becomes a real client of the salon:
 * saved once, found again by the number next time (however it is written: 0743..., +255743..., 255743...), and linked to the
 * sale, so the visit appears on her page and the thank-you text with the feedback link can reach her.
 */
final class SalonClientFromSale
{
    /** The salon's client for what was typed on this sale, or null when nothing (or nothing usable) was typed. */
    public static function resolve(Request $request): ?int
    {
        if (TenantContext::service() !== 'salon' || $request->filled('customer_id')) {
            return null;
        }
        $name = trim((string) $request->input('customer_name_override', ''));
        $phone = trim((string) $request->input('customer_phone', ''));
        if ($name === '' && $phone === '') {
            return null;
        }

        $found = $phone !== '' ? self::byPhone($phone) : self::byNameOnly($name);
        if ($found !== null) {
            return $found;
        }

        return (int) DB::table('inventory_customers')->insertGetId([
            'name' => $name !== '' ? $name : $phone,
            // The column does not take an empty value: a client with no number is saved with a blank one.
            'phone' => $phone,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    /** The numbers a phone may be written as: 0743519104, 743519104, 255743519104, +255743519104. */
    public static function spellings(string $phone): array
    {
        $digits = preg_replace('/\D/', '', $phone) ?? '';
        if (strlen($digits) < 9) {
            return [trim($phone)];
        }
        $nine = substr($digits, -9);

        return array_values(array_unique([trim($phone), "0{$nine}", $nine, "255{$nine}", "+255{$nine}"]));
    }

    private static function byPhone(string $phone): ?int
    {
        $id = DB::table('inventory_customers')->whereIn('phone', self::spellings($phone))->orderBy('id')->value('id');

        return $id === null ? null : (int) $id;
    }

    /** Only a name was typed: the same name with no number is the same person; otherwise a new client. */
    private static function byNameOnly(string $name): ?int
    {
        $id = DB::table('inventory_customers')
            ->whereRaw('LOWER(name) = ?', [mb_strtolower($name)])
            ->where(fn ($q) => $q->whereNull('phone')->orWhere('phone', ''))
            ->orderBy('id')->value('id');

        return $id === null ? null : (int) $id;
    }
}
