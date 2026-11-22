<?php

namespace App\Support\Groups;

/**
 * The verification token printed on a receipt (as a QR code): the group, the receipt number and a signature over what the receipt says, so
 * a receipt that was made up or changed does not verify. Anyone with the token may check it, and sees only that it is genuine, its number,
 * kind, amount and date: never a name.
 */
final class GroupReceipts
{
    private static function mac(string $ownerId, object $tx): string
    {
        $text = implode('|', [$ownerId, $tx->receipt_number, number_format((float) $tx->amount, 2, '.', ''), $tx->category, $tx->direction]);

        return substr(hash_hmac('sha256', $text, (string) config('app.key')), 0, 16);
    }

    /** owner.receipt.signature -- URL-safe. */
    public static function token(object $tx): string
    {
        return $tx->owner_id . '.' . $tx->receipt_number . '.' . self::mac((string) $tx->owner_id, $tx);
    }

    public static function url(object $tx): string
    {
        return rtrim((string) config('app.url'), '/') . '/api/public/groups/receipts/' . self::token($tx);
    }

    /** True when [signature] is what [tx] signs to. */
    public static function genuine(object $tx, string $signature): bool
    {
        return $tx->receipt_number !== null && hash_equals(self::mac((string) $tx->owner_id, $tx), $signature);
    }
}
