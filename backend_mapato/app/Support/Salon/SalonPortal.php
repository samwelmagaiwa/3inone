<?php

namespace App\Support\Salon;

use App\Models\Business;
use App\Models\User;
use App\Services\SmsService;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * A client's own page: the visits coming up (which they may cancel in time), their points, the packages they still have sessions in, what
 * they have had done and what they owe. It is opened from a private link (a long secret that belongs to that one client), by someone who is
 * not signed in, so everything here that touches a salon's rows first signs in AS that salon from the token: one salon can never show
 * another's clients, and one client never sees another client's page.
 */
final class SalonPortal
{
    /** The link a client opens (a plain page, no app needed). */
    public static function url(string $token): string
    {
        return rtrim((string) config('app.url'), '/') . '/me/' . $token;
    }

    /** The client's secret, made once and kept (called while signed in as the salon's staff). */
    public static function tokenFor(int $customerId): string
    {
        $have = DB::table('inventory_customers')->where('id', $customerId)->value('portal_token');
        if (is_string($have) && strlen($have) >= 30) {
            return $have;
        }
        $token = Str::random(40);
        DB::table('inventory_customers')->where('id', $customerId)->update(['portal_token' => $token]);

        return $token;
    }

    public static function message(string $clientName, string $business, string $url): string
    {
        $first = ClientSegments::firstName($clientName);
        $business = trim((string) preg_replace('/\s+/u', ' ', $business)) ?: 'saluni yetu';
        $hello = $first !== '' ? "Habari {$first}!" : 'Habari!';
        $helloEn = $first !== '' ? "Hello {$first}!" : 'Hello!';

        return "{$hello} Ukurasa wako wa {$business}: miadi, pointi, vifurushi na historia yako.\n{$helloEn} Your page at {$business}: visits, points, packages and history.\n\n{$url}";
    }

    /**
     * The owner and the client row behind a link, or null when it is not a good link. Nobody is signed in: the lookup must see every salon.
     *
     * @return array{0: User, 1: object}|null
     */
    public static function find(string $token): ?array
    {
        if (!Schema::hasColumn('inventory_customers', 'portal_token') || strlen($token) < 30) {
            return null;
        }
        $row = TenantContext::withoutScope(fn () => DB::table('inventory_customers')->where('portal_token', $token)->first());
        if ($row === null || ($row->owner_id ?? null) === null) {
            return null;
        }
        $owner = User::query()->where('id', $row->owner_id)->where('is_active', true)->first();
        if ($owner === null) {
            return null;
        }
        $business = Business::forOwnerId((string) $owner->id);

        return $business !== null && $business->blocksAccess() ? null : [$owner, $row];
    }

    private static function as(User $owner, \Closure $fn): mixed
    {
        return TenantContext::runAs($owner, fn () => TenantContext::runInService('salon', $fn));
    }

    /** @return array<string, mixed>|null */
    public static function view(string $token): ?array
    {
        $found = self::find($token);
        if ($found === null) {
            return null;
        }
        [$owner, $client] = $found;

        return self::as($owner, function () use ($owner, $client) {
            $business = Business::forOwnerId((string) $owner->id);
            $now = now(AppointmentPlanner::TIMEZONE);
            $cancelHours = AppointmentPlanner::cancelHours();

            $upcoming = DB::table('inventory_appointments')
                ->where('customer_id', $client->id)
                ->whereIn('status', AppointmentPlanner::ACTIVE)
                ->where('starts_at', '>=', $now->format('Y-m-d H:i:s'))
                ->orderBy('starts_at')
                ->limit(10)
                ->get()
                ->map(function ($a) use ($now, $cancelHours) {
                    $services = json_decode((string) $a->services, true);
                    $held = Schema::hasColumn('inventory_appointments', 'deposit_status') && ($a->deposit_status ?? 'none') === 'held';
                    $late = $cancelHours > 0 && Carbon::parse($a->starts_at, AppointmentPlanner::TIMEZONE)->diffInHours($now, false) > -$cancelHours;

                    return [
                        'id' => (int) $a->id,
                        'starts_at' => substr((string) $a->starts_at, 0, 16),
                        'services' => is_array($services) ? array_values(array_filter(array_map(fn ($s) => $s['name'] ?? null, $services))) : [],
                        'staff_name' => $a->staff_name,
                        'status' => $a->status,
                        // A booking that holds a deposit cannot be cancelled here once it is inside the cancellation hours: the salon decides then.
                        'can_cancel' => !($held && $late),
                    ];
                })->values()->all();

            $perks = SalonPerks::settings();
            $points = SalonPerks::active() && $perks['on'] ? SalonPerks::balance((int) $client->id) : null;

            $packages = Schema::hasTable('inventory_client_packages')
                ? DB::table('inventory_client_packages')->where('customer_id', $client->id)->where('status', 'active')->where('sessions_left', '>', 0)
                    ->where(fn ($q) => $q->whereNull('expires_on')->orWhere('expires_on', '>=', $now->toDateString()))
                    ->orderBy('id')->get()
                    ->map(fn ($p) => ['name' => $p->name, 'sessions_left' => (int) $p->sessions_left, 'sessions_total' => (int) $p->sessions_total, 'expires_on' => $p->expires_on ? substr((string) $p->expires_on, 0, 10) : null])->values()->all()
                : [];

            $sales = DB::table('inventory_sales')->where('customer_id', $client->id)->whereNull('cancelled_at')->orderByDesc('id')->limit(10)->get(['id', 'number', 'total', 'paid_total', 'created_at']);
            $names = $sales->isEmpty() ? collect() : DB::table('inventory_sale_items as si')->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
                ->whereIn('si.sale_id', $sales->pluck('id'))->get(['si.sale_id', 'p.name'])->groupBy('sale_id');
            $visits = $sales->map(fn ($s) => [
                'number' => $s->number,
                'at' => Carbon::parse($s->created_at, 'UTC')->setTimezone(AppointmentPlanner::TIMEZONE)->format('Y-m-d'),
                'services' => ($names[$s->id] ?? collect())->pluck('name')->filter()->unique()->values()->all(),
                'total' => (float) $s->total,
                'paid' => (float) $s->paid_total,
            ])->values()->all();

            $owed = (float) DB::table('inventory_sales')->where('customer_id', $client->id)->whereNull('cancelled_at')->selectRaw('COALESCE(SUM(total - paid_total), 0) as due')->value('due');

            return [
                'business' => (string) ($business?->name ?? ''),
                'phone' => $business?->phone ?? null,
                'client' => ClientSegments::firstName((string) $client->name) ?: (string) $client->name,
                'upcoming' => $upcoming,
                'points' => $points,
                'packages' => $packages,
                'visits' => $visits,
                'owed' => max(0, round($owed, 2)),
                'booking_url' => $business !== null && $business->online_booking && $business->booking_slug ? rtrim((string) config('app.url'), '/') . '/book/' . $business->booking_slug : null,
            ];
        });
    }

    /** Cancel one of the client's own appointments (never anyone else's). */
    public static function cancel(string $token, int $appointmentId): void
    {
        $found = self::find($token);
        if ($found === null) {
            throw ValidationException::withMessages(['token' => ['Kiungo hiki si sahihi. / This link is not valid.']]);
        }
        [$owner, $client] = $found;
        self::as($owner, function () use ($client, $appointmentId) {
            $row = DB::table('inventory_appointments')->where('id', $appointmentId)->where('customer_id', $client->id)->first();
            if ($row === null) {
                throw ValidationException::withMessages(['appointment' => ['Miadi haipatikani. / That appointment was not found.']]);
            }
            if (!in_array('cancelled', AppointmentPlanner::NEXT[$row->status] ?? [], true)) {
                throw ValidationException::withMessages(['appointment' => ['Miadi hii haiwezi kufutwa tena. / This appointment can no longer be cancelled.']]);
            }
            $update = ['status' => 'cancelled', 'updated_at' => now()];
            if (Schema::hasColumn('inventory_appointments', 'deposit_status') && ($row->deposit_status ?? 'none') === 'held') {
                $hours = AppointmentPlanner::cancelHours();
                $late = $hours > 0 && Carbon::parse($row->starts_at, AppointmentPlanner::TIMEZONE)->diffInHours(now(AppointmentPlanner::TIMEZONE), false) > -$hours;
                if ($late) {
                    throw ValidationException::withMessages(['appointment' => ['Muda wa kughairi umepita na kuna amana. Piga simu kwa saluni. / Too late to cancel online (a deposit is held): please call the salon.']]);
                }
                $update += ['deposit_status' => 'refunded', 'deposit_resolved_at' => now()];
            }
            DB::table('inventory_appointments')->where('id', $row->id)->update($update);
        });
    }

    /** Send a client their link by text when they ask for it with their phone number. Says nothing about whether the number is known. */
    public static function sendLinkTo(Business $business, User $owner, string $phone): void
    {
        $digits = substr(preg_replace('/\D+/', '', $phone) ?? '', -9);
        if (strlen($digits) < 9) {
            return;
        }
        self::as($owner, function () use ($business, $digits) {
            $client = DB::table('inventory_customers')
                ->whereRaw("REPLACE(REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '+', ''), '(', '') LIKE ?", ['%' . $digits])
                ->first();
            if ($client === null || (bool) ($client->sms_opt_out ?? false)) {
                return;
            }
            $url = self::url(self::tokenFor((int) $client->id));
            try {
                SmsService::sendFor($business, (string) $client->phone, self::message((string) $client->name, (string) $business->name, $url));
            } catch (\Throwable) {
                // nothing to tell: the answer is the same either way
            }
        });
    }
}
