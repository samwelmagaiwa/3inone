<?php

namespace App\Support\Salon;

use Carbon\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * The salon's clients in groups, for messages and for the owner's eyes: everyone, brand new, coming back, gone quiet,
 * birthday this month, best spenders. Runs for ONE business's salon (the tenant grammar limits every query to its rows).
 *
 * A client who has no phone number, or asked not to be texted, is never in a group that gets a message.
 */
final class ClientSegments
{
    public const ALL = 'all';

    public const NEW = 'new';

    public const RETURNING = 'returning';

    public const INACTIVE = 'inactive';

    public const BIRTHDAY = 'birthday_month';

    public const TOP = 'top_spenders';

    public const SEGMENTS = [self::ALL, self::NEW, self::RETURNING, self::INACTIVE, self::BIRTHDAY, self::TOP];

    /** A client is "new" when their first service visit was this recent. */
    public const NEW_DAYS = 30;

    public const DEFAULT_INACTIVE_WEEKS = 8;

    public const TOP_COUNT = 10;

    /**
     * Every client with what they have done, one row each.
     *
     * @return Collection<int, array{id: int, name: string, phone: string, can_text: bool, birthday: ?string, visits: int, first_on: ?string, last_on: ?string, spent: float}>
     */
    public static function clients(): Collection
    {
        $stats = DB::table('inventory_sales as s')
            ->join('inventory_sale_items as si', 'si.sale_id', '=', 's.id')
            ->whereNull('s.cancelled_at')
            ->whereNotNull('s.customer_id')
            ->groupBy('s.customer_id')
            ->selectRaw('s.customer_id as customer_id, MIN(CASE WHEN si.is_service = 1 THEN s.created_at END) as first_at, '
                . 'MAX(CASE WHEN si.is_service = 1 THEN s.created_at END) as last_at, '
                . 'COUNT(DISTINCT CASE WHEN si.is_service = 1 THEN s.id END) as visits')
            ->get()
            ->keyBy('customer_id');

        $spent = DB::table('inventory_sales')->whereNull('cancelled_at')->whereNotNull('customer_id')->groupBy('customer_id')
            ->selectRaw('customer_id, SUM(total) as spent')->pluck('spent', 'customer_id');

        return DB::table('inventory_customers')->orderBy('name')->get()->map(function ($c) use ($stats, $spent) {
            $st = $stats[$c->id] ?? null;
            $phone = trim((string) ($c->phone ?? ''));

            return [
                'id' => (int) $c->id,
                'name' => (string) $c->name,
                'phone' => $phone,
                'can_text' => $phone !== '' && !(bool) ($c->sms_opt_out ?? false),
                'birthday' => !empty($c->birthday) ? Carbon::parse($c->birthday)->toDateString() : null,
                'visits' => (int) ($st->visits ?? 0),
                'first_on' => !empty($st?->first_at) ? Carbon::parse($st->first_at)->toDateString() : null,
                'last_on' => !empty($st?->last_at) ? Carbon::parse($st->last_at)->toDateString() : null,
                'spent' => (float) ($spent[$c->id] ?? 0),
            ];
        })->values();
    }

    /**
     * The clients in a group, as of $today.
     *
     * @return Collection<int, array<string, mixed>>
     */
    public static function members(string $segment, Carbon $today, ?int $inactiveWeeks = null): Collection
    {
        $all = self::clients();
        $weeks = max(1, $inactiveWeeks ?? self::DEFAULT_INACTIVE_WEEKS);

        return match ($segment) {
            self::NEW => $all->filter(fn ($c) => $c['first_on'] !== null && Carbon::parse($c['first_on'])->gte($today->copy()->subDays(self::NEW_DAYS)->startOfDay()))->values(),
            self::RETURNING => $all->filter(fn ($c) => $c['visits'] >= 2)->values(),
            self::INACTIVE => $all->filter(fn ($c) => $c['last_on'] !== null && Carbon::parse($c['last_on'])->lt($today->copy()->subWeeks($weeks)->startOfDay()))->values(),
            self::BIRTHDAY => $all->filter(fn ($c) => $c['birthday'] !== null && (int) substr($c['birthday'], 5, 2) === (int) $today->format('n'))->values(),
            self::TOP => $all->filter(fn ($c) => $c['spent'] > 0)->sortByDesc('spent')->take(self::TOP_COUNT)->values(),
            default => $all,
        };
    }

    /** Who a message to this group would reach. */
    public static function textable(string $segment, Carbon $today, ?int $inactiveWeeks = null): Collection
    {
        return self::members($segment, $today, $inactiveWeeks)->filter(fn ($c) => $c['can_text'])->values();
    }

    /** "Neema Juma" -> "Neema". */
    public static function firstName(string $name): string
    {
        $first = trim((string) (preg_split('/\s+/u', trim($name))[0] ?? ''));

        return $first === '' ? '' : mb_convert_case(mb_strtolower($first, 'UTF-8'), MB_CASE_TITLE, 'UTF-8');
    }
}
