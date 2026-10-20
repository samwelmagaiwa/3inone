<?php

namespace App\Support\Salon;

use App\Models\Business;
use App\Models\User;
use App\Services\Inventory\InventoryNotifier;
use App\Services\SmsService;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * A client booking for themselves, from the page at /book/<the salon's address>. Nobody is signed in, so every step
 * first signs in AS the salon the address belongs to (a salon that has not switched online booking on, or whose plan has
 * ended, does not exist as far as the public is concerned), and only ever shows what a client needs: the services, who
 * does them and the free times. The same rules as the salon's own diary apply (days off, hours, no double booking).
 */
final class OnlineBooking
{
    /** The people a client may choose: those who do the work themselves. */
    public const STYLIST_ROLES = ['hair_stylist', 'nail_technician', 'lash_makeup_artist'];

    private const STEP_MINUTES = 30;

    private const OPENING = '08:00';

    private const CLOSING = '18:00';

    /** A time must be at least this far ahead (the salon needs notice), and no further than this many days. */
    private const MIN_NOTICE_MINUTES = 60;

    private const MAX_DAYS_AHEAD = 60;

    /** One phone may hold this many coming online bookings at once. */
    private const MAX_OPEN_PER_PHONE = 3;

    /**
     * The salon an address belongs to, if it takes bookings.
     *
     * @return array{0: Business, 1: User}|null
     */
    public static function find(string $slug): ?array
    {
        $business = Business::withoutAccountScope()->where('booking_slug', strtolower($slug))->where('online_booking', true)->first();
        $owner = $business?->owner;
        if ($business === null || $owner === null || !$owner->is_active || !in_array('salon', $business->serviceTypes(), true) || $business->blocksAccess()) {
            return null;
        }

        return [$business, $owner];
    }

    /** Run something as that salon's own books. */
    private static function as(User $owner, \Closure $fn): mixed
    {
        return TenantContext::runAs($owner, fn () => TenantContext::runInService('salon', $fn));
    }

    /**
     * What the page shows: the salon, its services (with other prices) and its stylists.
     *
     * @return array<string, mixed>
     */
    public static function catalog(Business $business, User $owner): array
    {
        return self::as($owner, function () use ($business, $owner) {
            $services = DB::table('inventory_products')->where('is_service', true)->where('status', 'active')
                ->when(\Illuminate\Support\Facades\Schema::hasColumn('inventory_products', 'package_sessions'), fn ($q) => $q->whereNull('package_sessions'))
                ->orderBy('name')->get()->map(fn ($p) => array_filter([
                    'id' => (int) $p->id,
                    'name' => $p->name,
                    'price' => SalonFinance::money($p->selling_price),
                    'minutes' => $p->duration_minutes ? (int) $p->duration_minutes : null,
                    'options' => json_decode((string) ($p->price_options ?? ''), true) ?: null,
                ], fn ($v) => $v !== null))->values();

            $profiles = DB::table('inventory_staff_profiles')->get()->keyBy('staff_id');
            $stylists = User::query()->whereIn('id', $owner->accountMemberIds())->where('is_active', true)->whereIn('role', self::STYLIST_ROLES)->orderBy('name')->get(['id', 'name'])
                ->map(fn ($u) => array_filter(['id' => (string) $u->id, 'name' => $u->name, 'specialization' => $profiles[(string) $u->id]->specialization ?? null], fn ($v) => $v !== null))->values();

            return [
                'business' => ['name' => (string) $business->name, 'phone' => $business->phone],
                'services' => $services,
                'stylists' => $stylists,
                'cancel_hours' => AppointmentPlanner::cancelHours(),
                'max_days_ahead' => self::MAX_DAYS_AHEAD,
            ];
        });
    }

    /**
     * The free start times on a day for these services: each time, with who is free then.
     *
     * @param  array<int, int>  $serviceIds
     * @return array{date: string, minutes: int, slots: array<int, array{time: string, staff: array<int, array{id: string, name: string}>}>}
     */
    public static function slots(User $owner, array $serviceIds, string $date, ?string $staffId): array
    {
        return self::as($owner, function () use ($owner, $serviceIds, $date, $staffId) {
            ['lines' => $lines, 'minutes' => $minutes] = self::lines($serviceIds);
            $day = Carbon::createFromFormat('Y-m-d', $date, AppointmentPlanner::TIMEZONE)->startOfDay();
            self::assertDay($day);

            $candidates = self::candidates($owner, array_column($lines, 'product_id'), $staffId);
            $profiles = DB::table('inventory_staff_profiles')->get()->keyBy('staff_id');
            $earliest = Carbon::now(AppointmentPlanner::TIMEZONE)->addMinutes(self::MIN_NOTICE_MINUTES);

            $byTime = [];
            foreach ($candidates as $person) {
                [$from, $to] = self::hours($profiles[(string) $person->id] ?? null);
                for ($t = Carbon::parse("{$date} {$from}", AppointmentPlanner::TIMEZONE); ; $t->addMinutes(self::STEP_MINUTES)) {
                    $end = $t->copy()->addMinutes($minutes);
                    if ($end->format('Y-m-d H:i') > "{$date} {$to}") {
                        break;
                    }
                    if ($t->lt($earliest)
                        || AppointmentPlanner::availability((string) $person->id, (string) $person->name, $t) !== null
                        || AppointmentPlanner::clash((string) $person->id, $t, $end) !== null) {
                        continue;
                    }
                    $byTime[$t->format('H:i')][] = ['id' => (string) $person->id, 'name' => (string) $person->name];
                }
            }
            ksort($byTime);

            return [
                'date' => $date,
                'minutes' => $minutes,
                'slots' => collect($byTime)->map(fn ($staff, $time) => ['time' => (string) $time, 'staff' => $staff])->values()->all(),
            ];
        });
    }

    /**
     * Book it. Returns what the client is told.
     *
     * @param  array{name: string, phone: string, services: array<int, array{product_id: int, label?: ?string, price?: mixed}>, starts_at: string, staff_id?: ?string, notes?: ?string}  $in
     * @return array{id: int, starts_at: string, ends_at: string, staff_name: ?string, total: int|float}
     */
    public static function book(Business $business, User $owner, array $in): array
    {
        return self::as($owner, function () use ($business, $owner, $in) {
            ['lines' => $lines, 'minutes' => $minutes, 'total' => $total] = self::lines(array_column($in['services'], 'product_id'), $in['services']);
            $start = Carbon::createFromFormat('Y-m-d H:i', $in['starts_at'], AppointmentPlanner::TIMEZONE);
            self::assertDay($start->copy()->startOfDay());
            if ($start->lt(Carbon::now(AppointmentPlanner::TIMEZONE)->addMinutes(self::MIN_NOTICE_MINUTES))) {
                throw ValidationException::withMessages(['starts_at' => ['Chagua muda wa baadaye. / Choose a later time.']]);
            }
            $end = $start->copy()->addMinutes($minutes);

            // Who: the one asked for, or the first who is free then.
            $person = null;
            $profiles = DB::table('inventory_staff_profiles')->get()->keyBy('staff_id');
            foreach (self::candidates($owner, array_column($lines, 'product_id'), $in['staff_id'] ?? null) as $c) {
                [$from, $to] = self::hours($profiles[(string) $c->id] ?? null);
                $inside = $start->format('H:i') >= $from && $end->format('Y-m-d H:i') <= $start->format('Y-m-d') . ' ' . $to;
                if ($inside && AppointmentPlanner::availability((string) $c->id, (string) $c->name, $start) === null && AppointmentPlanner::clash((string) $c->id, $start, $end) === null) {
                    $person = $c;
                    break;
                }
            }
            if ($person === null) {
                throw ValidationException::withMessages(['starts_at' => ['Muda huu umechukuliwa. Chagua mwingine. / That time is taken. Please choose another.']]);
            }

            $phone = trim($in['phone']);
            $open = DB::table('inventory_appointments')->where('client_phone', $phone)->where('source', 'online')->whereIn('status', AppointmentPlanner::ACTIVE)->where('starts_at', '>', Carbon::now(AppointmentPlanner::TIMEZONE)->format('Y-m-d H:i:s'))->count();
            if ($open >= self::MAX_OPEN_PER_PHONE) {
                throw ValidationException::withMessages(['phone' => ['Una miadi ' . self::MAX_OPEN_PER_PHONE . ' tayari. Wasiliana na saluni. / You already have ' . self::MAX_OPEN_PER_PHONE . ' bookings. Please contact the salon.']]);
            }

            $name = trim($in['name']);
            $customer = DB::table('inventory_customers')->where('phone', $phone)->first();
            $customerId = $customer?->id ?? DB::table('inventory_customers')->insertGetId(['name' => $name, 'phone' => $phone, 'created_at' => now(), 'updated_at' => now()]);

            $id = DB::table('inventory_appointments')->insertGetId([
                'customer_id' => $customerId,
                'client_name' => $customer->name ?? $name,
                'client_phone' => $phone,
                'staff_id' => (string) $person->id,
                'staff_name' => $person->name,
                'starts_at' => $start->format('Y-m-d H:i:s'),
                'ends_at' => $end->format('Y-m-d H:i:s'),
                'status' => 'booked',
                'services' => json_encode($lines),
                'notes' => !empty($in['notes']) ? mb_substr(trim((string) $in['notes']), 0, 500) : null,
                'total' => $total,
                'source' => 'online',
                ...(\Illuminate\Support\Facades\Schema::hasColumn('inventory_appointments', 'branch_id') ? ['branch_id' => SalonBranch::homeOf((string) $person->id)] : []),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            $when = $start->format('d/m H:i');
            app(InventoryNotifier::class)->notifyByPermission(['inv_view_reports'], 'salon_online_booking', 'Miadi ya mtandaoni / Online booking', "{$name} - {$when} ({$person->name})", ['appointment_id' => (int) $id]);
            app(InventoryNotifier::class)->notifyUser((string) $person->id, 'salon_new_booking', 'Miadi mpya / New appointment', "{$name} - {$when}", ['appointment_id' => (int) $id]);

            try {
                $first = ClientSegments::firstName($name);
                SmsService::sendFor($business, $phone, ($first !== '' ? "Habari {$first}, " : 'Habari, ') . "miadi yako {$business->name} {$when} imepokelewa. Karibu! / "
                    . ($first !== '' ? "Hello {$first}, " : 'Hello, ') . "your appointment at {$business->name} on {$when} is booked. See you!");
            } catch (\Throwable) {
                // The booking stands; the text is a courtesy.
            }

            return ['id' => (int) $id, 'starts_at' => $start->format('Y-m-d H:i'), 'ends_at' => $end->format('Y-m-d H:i'), 'staff_name' => $person->name, 'total' => SalonFinance::money($total)];
        });
    }

    // ------------------------------------------------------------------ helpers

    /**
     * When a person can be booked: their own hours if the owner set them, else the salon's usual ones.
     *
     * @return array{0: string, 1: string}
     */
    private static function hours(?object $profile): array
    {
        $from = (string) ($profile->shift_start ?? '');
        $to = (string) ($profile->shift_end ?? '');

        return [$from !== '' ? $from : self::OPENING, $to !== '' ? $to : self::CLOSING];
    }

    /** The date must be today or later and not too far off. */
    private static function assertDay(Carbon $day): void
    {
        $today = Carbon::now(AppointmentPlanner::TIMEZONE)->startOfDay();
        if ($day->lt($today) || $day->gt($today->copy()->addDays(self::MAX_DAYS_AHEAD))) {
            throw ValidationException::withMessages(['date' => ['Chagua tarehe ndani ya siku ' . self::MAX_DAYS_AHEAD . ' zijazo. / Choose a date within the next ' . self::MAX_DAYS_AHEAD . ' days.']]);
        }
    }

    /**
     * The services, read from the salon's own list (never trusted from the page): names, minutes and the price for the
     * option chosen (only one the service really has).
     *
     * @param  array<int, mixed>  $ids
     * @param  array<int, array{product_id: int, label?: ?string}>|null  $asked
     * @return array{lines: array<int, array<string, mixed>>, minutes: int, total: float}
     */
    private static function lines(array $ids, ?array $asked = null): array
    {
        $ids = array_values(array_unique(array_map('intval', $ids)));
        if ($ids === [] || count($ids) > 8) {
            throw ValidationException::withMessages(['services' => ['Chagua huduma moja hadi nane. / Choose one to eight services.']]);
        }
        $products = DB::table('inventory_products')->whereIn('id', $ids)->where('is_service', true)->where('status', 'active')
            ->when(\Illuminate\Support\Facades\Schema::hasColumn('inventory_products', 'package_sessions'), fn ($q) => $q->whereNull('package_sessions'))->get()->keyBy('id');
        if ($products->count() !== count($ids)) {
            throw ValidationException::withMessages(['services' => ['Huduma moja haipatikani. / One of the services is not available.']]);
        }

        $labels = collect($asked ?? [])->pluck('label', 'product_id');
        $lines = [];
        $minutes = 0;
        $total = 0.0;
        foreach ($ids as $id) {
            $p = $products[$id];
            $price = (float) $p->selling_price;
            $label = $labels[$id] ?? null;
            if ($label !== null && $label !== '') {
                $option = collect(json_decode((string) ($p->price_options ?? ''), true) ?: [])->firstWhere('label', $label);
                if ($option === null) {
                    throw ValidationException::withMessages(['services' => ['Bei hiyo haipo kwa huduma hii. / That price is not offered for this service.']]);
                }
                $price = (float) $option['price'];
            } else {
                $label = null;
            }
            $own = (int) ($p->duration_minutes ?? 0);
            $minutes += max(0, $own);
            $total += $price;
            $lines[] = array_filter(['product_id' => (int) $p->id, 'name' => (string) $p->name, 'price' => $price, 'minutes' => $own > 0 ? $own : null, 'label' => $label], fn ($v) => $v !== null);
        }

        return ['lines' => $lines, 'minutes' => $minutes > 0 ? $minutes : AppointmentPlanner::DEFAULT_MINUTES, 'total' => $total];
    }

    /**
     * The people who could do ALL the chosen services: the one asked for if they can, else every stylist who can.
     *
     * @param  array<int, int>  $serviceIds
     * @return \Illuminate\Support\Collection<int, object>
     */
    private static function candidates(User $owner, array $serviceIds, ?string $staffId)
    {
        $limits = DB::table('inventory_products')->whereIn('id', $serviceIds)->pluck('staff_ids')
            ->map(fn ($v) => json_decode((string) $v, true) ?: [])->filter(fn ($l) => $l !== []);

        $people = User::query()->whereIn('id', $owner->accountMemberIds())->where('is_active', true)->whereIn('role', self::STYLIST_ROLES)
            ->when($staffId !== null && $staffId !== '', fn ($q) => $q->where('id', $staffId))->orderBy('name')->get(['id', 'name']);

        $able = $people->filter(fn ($u) => $limits->every(fn ($l) => in_array((string) $u->id, $l, true)))->values();
        if ($able->isEmpty() && $staffId !== null && $staffId !== '') {
            throw ValidationException::withMessages(['staff_id' => ['Mhudumu huyu hafanyi huduma hizi. / This person does not do these services.']]);
        }

        return $able;
    }
}
