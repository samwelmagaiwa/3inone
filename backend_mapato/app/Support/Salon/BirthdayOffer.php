<?php

namespace App\Support\Salon;

use Illuminate\Support\Facades\DB;

/**
 * The text a client gets on their birthday, with an offer the owner writes ("10% off this week"). Off until the owner
 * switches it on (it is an SMS, and SMS cost money). One text per client per year.
 */
final class BirthdayOffer
{
    private const KEY_ON = 'salon_birthday_on';

    private const KEY_TEXT = 'salon_birthday_text';

    public static function isOn(): bool
    {
        return DB::table('inventory_settings')->where('key', self::KEY_ON)->value('value') === '1';
    }

    public static function text(): string
    {
        return (string) (DB::table('inventory_settings')->where('key', self::KEY_TEXT)->value('value') ?? '');
    }

    public static function save(?bool $on, ?string $text): void
    {
        $write = fn (string $key, string $value) => DB::table('inventory_settings')->updateOrInsert(['key' => $key], ['value' => $value, 'updated_at' => now()]);
        if ($on !== null) {
            $write(self::KEY_ON, $on ? '1' : '0');
        }
        if ($text !== null) {
            $write(self::KEY_TEXT, trim($text));
        }
    }

    public static function message(string $clientName, string $business, string $offer): string
    {
        $first = ClientSegments::firstName($clientName);
        $business = trim((string) preg_replace('/\s+/u', ' ', $business)) ?: 'saluni yetu';
        $offer = trim((string) preg_replace('/\s+/u', ' ', $offer));
        $extra = $offer === '' ? '' : " {$offer}.";
        $swHello = $first !== '' ? "Habari {$first}," : 'Habari,';
        $enHello = $first !== '' ? "Happy birthday {$first}" : 'Happy birthday';

        return "{$swHello} heri ya kuzaliwa kutoka {$business}!{$extra} Karibu! / {$enHello} from {$business}!{$extra} Welcome!";
    }
}
