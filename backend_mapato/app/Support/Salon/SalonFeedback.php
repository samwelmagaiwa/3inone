<?php

namespace App\Support\Salon;

use App\Models\Business;
use App\Models\User;
use App\Services\Inventory\InventoryNotifier;
use App\Services\SmsService;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * What clients say, and how they are asked. After a visit with a service, a client with a phone number (who has not asked
 * not to be texted) gets one text with a private link to rate the visit and leave a comment or a complaint; the link
 * works once and for {@see self::VALID_DAYS} days. It is on unless the owner switches it off (it is an SMS).
 *
 * The link is opened by someone who is not signed in, so everything here that touches a salon's rows first signs in
 * AS that salon ({@see TenantContext::runAs}) from the token: one salon can never read or write another's feedback.
 */
final class SalonFeedback
{
    private const KEY = 'salon_feedback_sms';

    public const VALID_DAYS = 14;

    /** On by default: a client whose bill is cleared is thanked, unless the owner has switched it off. */
    public static function isOn(): bool
    {
        return DB::table('inventory_settings')->where('key', self::KEY)->value('value') !== '0';
    }

    public static function save(bool $on): void
    {
        DB::table('inventory_settings')->updateOrInsert(['key' => self::KEY], ['value' => $on ? '1' : '0', 'updated_at' => now()]);
    }

    public static function active(): bool
    {
        return TenantContext::service() === 'salon' && Schema::hasTable('inventory_feedback_requests');
    }

    /** The link a client opens (a plain page, no app needed). */
    public static function url(string $token): string
    {
        return rtrim((string) config('app.url'), '/') . '/f/' . $token;
    }

    /**
     * The one text a client gets when a visit is paid: what they paid for, then (at the bottom) the link to say how it went.
     *
     * @param  array<int, string>  $services
     */
    public static function message(string $clientName, string $business, string $url, float $paid = 0, array $services = []): string
    {
        $first = ClientSegments::firstName($clientName);
        $business = trim((string) preg_replace('/\s+/u', ' ', $business)) ?: 'saluni yetu';
        $what = trim(mb_substr(implode(', ', $services), 0, 60));
        $amount = 'TSh ' . number_format($paid, 0, '.', ',');
        // The client is thanked for being a customer; what was paid follows; the link to say how it went is the last line.
        $sw = ($first !== '' ? "Asante {$first} kwa kuwa mteja wetu, tunathamini mchango wako!" : 'Asante kwa kuwa mteja wetu, tunathamini mchango wako!')
            . ($paid > 0 ? " Umelipa {$amount}" . ($what !== '' ? " kwa {$what}" : '') . " - {$business}." : " Karibu tena {$business}.");
        $en = ($first !== '' ? "Thank you {$first} for being our customer, we appreciate your support!" : 'Thank you for being our customer, we appreciate your support!')
            . ($paid > 0 ? " You paid {$amount}" . ($what !== '' ? " for {$what}" : '') . " at {$business}." : " See you again at {$business}.");

        return "{$sw}\n{$en}\n\nTupe maoni yako / Your feedback: {$url}";
    }

    /**
     * A visit has been paid for: ask the client how it went. Once per sale; never for goods only, a client with no phone
     * or who opted out, or when the owner has switched it off. A text that cannot be sent leaves no link behind.
     */
    public static function afterPaid(int $saleId): void
    {
        if (!self::active() || !self::isOn() || DB::table('inventory_feedback_requests')->where('sale_id', $saleId)->exists()) {
            return;
        }
        $sale = DB::table('inventory_sales')->where('id', $saleId)->first();
        if ($sale === null || $sale->customer_id === null || !empty($sale->cancelled_at)) {
            return;
        }
        $client = DB::table('inventory_customers')->where('id', $sale->customer_id)->first();
        $phone = trim((string) ($client->phone ?? ''));
        if ($client === null || $phone === '' || (bool) ($client->sms_opt_out ?? false)) {
            return;
        }

        // The visit's stylist: whoever did the most expensive service on it.
        $line = DB::table('inventory_sale_items')->where('sale_id', $saleId)->where('is_service', true)->orderByDesc('total')->orderBy('id')->first(['staff_id', 'staff_name']);
        if ($line === null) {
            return;
        }

        $token = Str::random(40);
        $viewer = TenantContext::viewer();
        $business = $viewer === null ? null : Business::forUser($viewer);
        $id = DB::table('inventory_feedback_requests')->insertGetId([
            'token' => $token,
            'customer_id' => (int) $sale->customer_id,
            'sale_id' => $saleId,
            'staff_id' => $line->staff_id,
            'staff_name' => $line->staff_name,
            'expires_at' => now()->addDays(self::VALID_DAYS),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        try {
            $sent = SmsService::sendFor($business, $phone, self::message((string) $client->name, (string) ($business?->name ?? ''), self::url($token), (float) $sale->total, DB::table('inventory_sale_items as si')->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')->where('si.sale_id', $saleId)->where('si.is_service', true)->pluck('p.name')->filter()->unique()->values()->all()));
        } catch (\Throwable) {
            $sent = false;
        }
        if (!$sent) {
            DB::table('inventory_feedback_requests')->where('id', $id)->delete();
        }
    }

    /**
     * What the page shows a client who opens their link, or null when the link is not (or no longer) good.
     *
     * @return array{business: string, services: array<int, string>, stylist: ?string, client: ?string}|null
     */
    public static function lookup(string $token): ?array
    {
        $found = self::find($token);
        if ($found === null) {
            return null;
        }
        [$owner, $row] = $found;

        return TenantContext::runAs($owner, fn () => TenantContext::runInService('salon', function () use ($owner, $row) {
            $client = $row->customer_id ? DB::table('inventory_customers')->where('id', $row->customer_id)->value('name') : null;

            // The services the client had on this visit, so the review is about them.
            $services = $row->sale_id === null ? [] : DB::table('inventory_sale_items as si')
                ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
                ->where('si.sale_id', $row->sale_id)->where('si.is_service', true)
                ->pluck('p.name')->filter()->unique()->values()->all();

            return [
                'business' => (string) (Business::forOwnerId((string) $owner->id)?->name ?? ''),
                'services' => $services,
                'stylist' => $row->staff_name,
                'client' => $client === null ? null : ClientSegments::firstName((string) $client),
            ];
        }));
    }

    /**
     * The client's answer. Saved as the salon's own feedback; a complaint also tells the owner and managers at once. The
     * link is used up.
     *
     * @param  array{rating?: ?int, message?: ?string, complaint?: bool}  $answer
     */
    public static function submit(string $token, array $answer): void
    {
        $found = self::find($token);
        if ($found === null) {
            throw ValidationException::withMessages(['token' => ['Kiungo hiki si sahihi au kimeisha muda. / This link is not valid, or has expired.']]);
        }
        [$owner, $row] = $found;
        $rating = isset($answer['rating']) ? (int) $answer['rating'] : null;
        $message = trim((string) ($answer['message'] ?? ''));
        $complaint = (bool) ($answer['complaint'] ?? false);
        if (($rating === null || $rating < 1 || $rating > 5) && $message === '') {
            throw ValidationException::withMessages(['rating' => ['Chagua nyota au andika maoni. / Choose a rating or write a comment.']]);
        }

        TenantContext::runAs($owner, fn () => TenantContext::runInService('salon', function () use ($row, $rating, $message, $complaint, $owner) {
            // Claim the link first, so two taps cannot both count.
            $claimed = DB::table('inventory_feedback_requests')->where('id', $row->id)->whereNull('used_at')->update(['used_at' => now(), 'updated_at' => now()]);
            if ($claimed === 0) {
                throw ValidationException::withMessages(['token' => ['Kiungo hiki kimeshatumika. / This link has already been used.']]);
            }
            $id = DB::table('inventory_feedback')->insertGetId([
                'customer_id' => $row->customer_id,
                'sale_id' => $row->sale_id,
                'staff_id' => $row->staff_id,
                'staff_name' => $row->staff_name,
                'kind' => $complaint ? 'complaint' : 'review',
                'rating' => $rating !== null && $rating >= 1 && $rating <= 5 ? $rating : null,
                'message' => $message === '' ? null : mb_substr($message, 0, 500),
                'status' => 'new',
                'source' => 'link',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            if ($complaint) {
                self::tellAboutComplaint((int) $id, (string) ($row->staff_name ?? ''), $message, null, self::who($row->customer_id));
            }
        }));
    }

    /** A complaint is told to everyone who can act on it, the moment it is made. */
    /** Who is complaining, as the owner should read it: "Neema (0711000001)", or nothing when there is no client on it. */
    public static function who(mixed $customerId): string
    {
        if ($customerId === null) {
            return '';
        }
        $c = DB::table('inventory_customers')->where('id', $customerId)->first(['name', 'phone']);
        if ($c === null) {
            return '';
        }

        return trim($c->name . (trim((string) $c->phone) !== '' ? " ({$c->phone})" : ''));
    }

    public static function tellAboutComplaint(int $id, string $about, string $message, ?string $exclude = null, string $client = ''): void
    {
        $parts = array_filter([$client, $about !== '' ? "kuhusu / about {$about}" : '']);
        app(InventoryNotifier::class)->notifyByPermission(
            ['inv_view_reports'],
            'salon_complaint',
            'Malalamiko mapya / A new complaint',
            trim(implode(' · ', $parts) . ($parts === [] ? '' : ': ') . Str::limit($message, 80)),
            ['feedback_id' => $id],
            excludeUserId: $exclude,
        );
    }

    /**
     * The salon a token belongs to and its row; null when unknown, used or expired.
     *
     * @return array{0: User, 1: object}|null
     */
    private static function find(string $token): ?array
    {
        if (!Schema::hasTable('inventory_feedback_requests') || strlen($token) < 20) {
            return null;
        }
        // Nobody is signed in: the lookup itself must see every salon's links.
        $row = TenantContext::withoutScope(fn () => DB::table('inventory_feedback_requests')->where('token', $token)->first());
        if ($row === null || $row->used_at !== null || Carbon::parse($row->expires_at)->isPast() || $row->owner_id === null) {
            return null;
        }
        $owner = User::query()->where('id', $row->owner_id)->where('is_active', true)->first();

        return $owner === null ? null : [$owner, $row];
    }
}
