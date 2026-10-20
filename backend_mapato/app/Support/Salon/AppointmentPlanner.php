<?php

namespace App\Support\Salon;

use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * The rules for a salon's appointments, in one place: who may be booked when, how a booking moves between states, and
 * the reminder text. Runs for ONE business (the tenant grammar limits every query to its rows).
 */
final class AppointmentPlanner
{
    /** The states in which an appointment still takes up its stylist's time. */
    public const ACTIVE = ['booked', 'confirmed', 'in_progress'];

    /** From each state, where it may go next. Done, cancelled and no-show are final. */
    public const NEXT = [
        'booked' => ['confirmed', 'in_progress', 'done', 'cancelled', 'no_show'],
        'confirmed' => ['in_progress', 'done', 'cancelled', 'no_show'],
        'in_progress' => ['done', 'cancelled'],
        'done' => [],
        'cancelled' => [],
        'no_show' => [],
    ];

    public const DEFAULT_MINUTES = 60;

    /** The salon's clock: Tanzania. Appointment times are kept as the wall-clock time the salon sees. */
    public const TIMEZONE = 'Africa/Dar_es_Salaam';

    private const KEY_REMINDERS = 'salon_appointment_reminders';

    public static function remindersOn(): bool
    {
        return DB::table('inventory_settings')->where('key', self::KEY_REMINDERS)->value('value') === '1';
    }

    public static function saveReminders(bool $on): void
    {
        DB::table('inventory_settings')->updateOrInsert(
            ['key' => self::KEY_REMINDERS],
            ['value' => $on ? '1' : '0', 'updated_at' => now()],
        );
    }

    /**
     * Another active appointment of this stylist that overlaps the time asked for, or null. Back-to-back is fine:
     * one that ends at 10:00 does not collide with one that starts at 10:00.
     */
    public static function clash(?string $staffId, Carbon $start, Carbon $end, ?int $ignoreId = null): ?object
    {
        if ($staffId === null || $staffId === '') {
            return null;
        }

        return DB::table('inventory_appointments')
            ->where('staff_id', $staffId)
            ->whereIn('status', self::ACTIVE)
            ->where('starts_at', '<', $end->format('Y-m-d H:i:s'))
            ->where('ends_at', '>', $start->format('Y-m-d H:i:s'))
            ->when($ignoreId !== null, fn ($q) => $q->where('id', '!=', $ignoreId))
            ->orderBy('starts_at')
            ->first();
    }

    /** The reminder text, Swahili then English like every text this app sends. */
    public static function message(string $clientName, string $when, array $serviceNames, string $business): string
    {
        $first = trim((string) (preg_split('/\s+/u', trim($clientName))[0] ?? ''));
        $first = $first === '' ? '' : mb_convert_case(mb_strtolower($first, 'UTF-8'), MB_CASE_TITLE, 'UTF-8');
        $business = self::shorten($business !== '' ? $business : 'saluni yetu', 40);
        $what = self::shorten(implode(', ', array_slice($serviceNames, 0, 3)) ?: 'huduma', 50);
        $swHello = $first !== '' ? "Habari {$first}," : 'Habari,';
        $enHello = $first !== '' ? "Hello {$first}," : 'Hello,';

        return "{$swHello} ukumbusho: una miadi {$business} kesho saa {$when} ({$what}). Karibu! / "
            . "{$enHello} reminder: your appointment at {$business} is tomorrow at {$when} ({$what}). See you!";
    }

    private static function shorten(string $text, int $max): string
    {
        $text = trim((string) preg_replace('/\s+/u', ' ', $text));

        // Plain "..." (one character outside the SMS alphabet would make the whole text count as 70-character parts).
        return mb_strlen($text) > $max ? rtrim(mb_substr($text, 0, $max - 3)) . '...' : $text;
    }
}
