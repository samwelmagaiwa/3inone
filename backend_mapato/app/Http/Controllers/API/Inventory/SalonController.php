<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\User;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\RebookPlanner;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * What a salon needs on top of the sales engine it shares with Inventory: who can serve a client, how each stylist
 * is doing, a client's history, and the "come back" reminders. Every query here runs against the signed-in
 * business only (the inventory tables are limited to the business automatically).
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Salon: stylists, their results, client history and "come back" reminders. Runs on the inventory sales engine.')]
class SalonController extends Controller
{
    #[OA\Get(path: '/inventory/salon/staff', summary: 'Who can serve a client (the business\'s own active staff and owner)', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function staff(Request $request): JsonResponse
    {
        $ids = $request->user()->accountMemberIds();

        $staff = User::query()
            ->whereIn('id', $ids)
            ->where('is_active', true)
            ->orderBy('name')
            ->get(['id', 'name', 'role'])
            ->map(fn ($u) => ['id' => (string) $u->id, 'name' => $u->name, 'role' => $u->role])
            ->values();

        return response()->json(['data' => $staff]);
    }

    /**
     * How each stylist did in a period: the services they did, what those brought in, how many visits and how many
     * different clients. The owner and managers see everyone; anyone else sees only their own line.
     */
    #[OA\Get(
        path: '/inventory/salon/stylists',
        summary: 'Results per stylist for a period (default: this month)',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Salon'],
        parameters: [
            new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
            new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function stylists(Request $request): JsonResponse
    {
        $data = $request->validate(['from' => 'nullable|date', 'to' => 'nullable|date|after_or_equal:from']);
        $from = isset($data['from']) ? Carbon::parse($data['from'])->toDateString() : now()->startOfMonth()->toDateString();
        $to = isset($data['to']) ? Carbon::parse($data['to'])->toDateString() : now()->toDateString();

        $viewer = $request->user();
        $sees = $viewer->seesAllAccounts() || in_array(strtolower((string) $viewer->role), ['admin', 'administrator', 'manager', 'accountant'], true);

        $query = DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->whereNull('s.cancelled_at')
            ->where('si.is_service', true)
            ->whereDate('s.created_at', '>=', $from)
            ->whereDate('s.created_at', '<=', $to);
        if (!$sees) {
            $query->where('si.staff_id', (string) $viewer->id);
        }

        // (A server that has not run the migration yet has no commission to add up.)
        $commission = \Illuminate\Support\Facades\Schema::hasColumn('inventory_sale_items', 'commission_amount') ? 'si.commission_amount' : '0';

        $rows = $query
            ->groupBy('si.staff_id')
            ->selectRaw(
                'si.staff_id as staff_id,
                 MAX(si.staff_name) as staff_name,
                 SUM(COALESCE(si.unit_qty, si.quantity)) as services,
                 COALESCE(SUM(si.total - COALESCE(s.discount * si.total / NULLIF(s.subtotal, 0), 0)), 0) as revenue,
                 COALESCE(SUM(COALESCE(s.discount * si.total / NULLIF(s.subtotal, 0), 0)), 0) as discount,
                 COALESCE(SUM(' . $commission . '), 0) as commission,
                 COUNT(DISTINCT s.id) as visits,
                 COUNT(DISTINCT s.customer_id) as clients'
            )
            ->orderByDesc('revenue')
            ->get()
            ->map(fn ($r) => [
                'staff_id' => $r->staff_id,
                'name' => $r->staff_name,
                'services' => (int) $r->services,
                'revenue' => self::money($r->revenue),
                'discount' => self::money($r->discount),
                'commission' => (float) $r->commission == floor((float) $r->commission) ? (int) $r->commission : (float) $r->commission,
                'visits' => (int) $r->visits,
                'clients' => (int) $r->clients,
            ])
            ->values();

        return response()->json(['data' => [
            'from' => $from,
            'to' => $to,
            'totals' => [
                'services' => $rows->sum('services'),
                'revenue' => $rows->sum('revenue'),
                'commission' => $rows->sum('commission'),
                'discount' => self::money($rows->sum('discount')),
                'visits' => $rows->sum('visits'),
            ],
            'stylists' => $rows,
        ]]);
    }

    /**
     * Every sale line behind one stylist's total (or behind "nobody named"): the client, the service, its value, the
     * share of the sale's discount it carried, what is left after it, what the stylist earns on it, and how it was
     * paid. The owner and managers may open anyone; anyone else only their own.
     */
    #[OA\Get(
        path: '/inventory/salon/stylists/{staffId}/transactions',
        summary: 'The services behind one stylist total for a period (default: this month); staffId "none" = nobody named',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Salon'],
        parameters: [
            new OA\Parameter(name: 'staffId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
            new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function stylistTransactions(Request $request, string $staffId): JsonResponse
    {
        $data = $request->validate(['from' => 'nullable|date', 'to' => 'nullable|date|after_or_equal:from']);
        $from = isset($data['from']) ? Carbon::parse($data['from'])->toDateString() : now()->startOfMonth()->toDateString();
        $to = isset($data['to']) ? Carbon::parse($data['to'])->toDateString() : now()->toDateString();

        $viewer = $request->user();
        $sees = $viewer->seesAllAccounts() || in_array(strtolower((string) $viewer->role), ['admin', 'administrator', 'manager', 'accountant'], true);
        abort_if(!$sees && $staffId !== (string) $viewer->id, 403, 'Huwezi kuona mapato ya mhudumu mwingine. / You cannot see another stylist\'s income.');

        $query = DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->whereNull('s.cancelled_at')
            ->where('si.is_service', true)
            ->whereDate('s.created_at', '>=', $from)
            ->whereDate('s.created_at', '<=', $to);
        $staffId === 'none' ? $query->whereNull('si.staff_id') : $query->where('si.staff_id', $staffId);

        $hasCommission = \Illuminate\Support\Facades\Schema::hasColumn('inventory_sale_items', 'commission_amount');
        $hasReason = \Illuminate\Support\Facades\Schema::hasColumn('inventory_sales', 'discount_reason');
        $lines = $query->orderByDesc('s.created_at')->orderByDesc('si.id')->get(array_merge([
            'si.id', 'si.sale_id', 'p.name as product_name', 'si.staff_name', 'si.quantity', 'si.unit_qty', 'si.total',
            's.number', 's.created_at', 's.subtotal', 's.discount', 's.payment_status',
            's.customer_name_override', 'c.name as customer_name',
        ], $hasCommission ? ['si.commission_amount'] : [], $hasReason ? ['s.discount_reason'] : []));

        $paid = DB::table('inventory_sale_payments')
            ->whereIn('sale_id', $lines->pluck('sale_id')->unique()->values())
            ->get(['sale_id', 'method', 'method_extended'])
            ->groupBy('sale_id')
            ->map(fn ($rows) => $rows->map(fn ($p) => $p->method_extended ?: $p->method)->unique()->values()->all());

        $rows = $lines->map(function ($l) use ($paid) {
            $discount = (float) $l->subtotal > 0 ? (float) $l->discount * (float) $l->total / (float) $l->subtotal : 0.0;

            return [
                'sale_id' => (int) $l->sale_id,
                'number' => $l->number,
                'date' => Carbon::parse($l->created_at)->format('Y-m-d H:i'),
                'client' => $l->customer_name ?: ($l->customer_name_override ?: null),
                'service' => $l->product_name,
                'qty' => (int) ($l->unit_qty ?? $l->quantity),
                'value' => self::money($l->total),
                'discount' => self::money($discount),
                'net' => self::money((float) $l->total - $discount),
                'commission' => self::money($l->commission_amount ?? 0),
                'discount_reason' => $l->discount_reason ?? null,
                'payment_status' => $l->payment_status,
                'methods' => $paid[$l->sale_id] ?? [],
            ];
        })->values();

        return response()->json(['data' => [
            'from' => $from,
            'to' => $to,
            'staff_id' => $staffId === 'none' ? null : $staffId,
            'name' => $lines->pluck('staff_name')->filter()->first(),
            'totals' => [
                'services' => $rows->sum('qty'),
                'value' => self::money($rows->sum('value')),
                'discount' => self::money($rows->sum('discount')),
                'net' => self::money($rows->sum('net')),
                'commission' => self::money($rows->sum('commission')),
            ],
            'transactions' => $rows,
        ]]);
    }

    /** A money amount as the app reads it: a whole number when it is one, else two decimals. */
    private static function money(mixed $v): int|float
    {
        $f = round((float) $v, 2);

        return $f == floor($f) ? (int) $f : $f;
    }

    /** A client's page: how often they come, what they spend, what they like, and when they are due back. */
    #[OA\Get(path: '/inventory/salon/clients/{id}/history', summary: 'A client\'s visits, totals and next visit', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function clientHistory(int $id): JsonResponse
    {
        $client = DB::table('inventory_customers')->where('id', $id)->first();
        if (!$client) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $sales = DB::table('inventory_sales')
            ->where('customer_id', $id)
            ->whereNull('cancelled_at')
            ->orderByDesc('created_at')->orderByDesc('id')
            ->get(['id', 'number', 'total', 'paid_total', 'payment_status', 'created_at']);

        $lines = $sales->isEmpty() ? collect() : DB::table('inventory_sale_items as si')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->whereIn('si.sale_id', $sales->pluck('id'))
            ->get(['si.sale_id', 'si.is_service', 'si.staff_name', 'si.total', DB::raw('COALESCE(si.unit_qty, si.quantity) as qty'), 'p.name as product_name'])
            ->groupBy('sale_id');

        $visits = $sales->map(fn ($s) => [
            'sale_id' => (int) $s->id,
            'number' => $s->number,
            'date' => Carbon::parse($s->created_at)->toDateString(),
            'total' => (float) $s->total,
            'paid' => (float) $s->paid_total,
            'payment_status' => $s->payment_status,
            'items' => ($lines[$s->id] ?? collect())->map(fn ($l) => [
                'name' => $l->product_name,
                'is_service' => (bool) $l->is_service,
                'staff_name' => $l->staff_name,
                'qty' => (int) $l->qty,
                'total' => (float) $l->total,
            ])->values(),
        ])->values();

        $serviceVisits = $visits->filter(fn ($v) => $v['items']->contains(fn ($i) => $i['is_service']));
        $referrer = !empty($client->referred_by ?? null) ? DB::table('inventory_customers')->where('id', $client->referred_by)->value('name') : null;
        $firstVisit = $serviceVisits->last()['date'] ?? null;

        // The service this client has had most often.
        $favourite = $lines->flatten(1)->where('is_service', 1)->groupBy('product_name')
            ->map(fn ($g) => $g->sum('qty'))->sortDesc()->keys()->first();

        return response()->json(['data' => [
            'client' => [
                'id' => (int) $client->id,
                'name' => $client->name,
                'phone' => $client->phone,
                'notes' => $client->notes ?? null,
                'sms_opt_out' => (bool) ($client->sms_opt_out ?? false),
                'birthday' => !empty($client->birthday ?? null) ? Carbon::parse($client->birthday)->toDateString() : null,
                'preferences' => json_decode((string) ($client->preferences ?? ''), true) ?: new \stdClass(),
                'referred_by' => !empty($client->referred_by ?? null) ? (int) $client->referred_by : null,
                'referred_by_name' => $referrer,
            ],
            'stats' => [
                // A client is "new" until they have come twice.
                'is_returning' => $serviceVisits->count() >= 2,
                'loyalty_points' => \App\Support\Salon\SalonPerks::active() && \App\Support\Salon\SalonPerks::settings()['on'] ? \App\Support\Salon\SalonPerks::balance($id) : null,
                'first_visit_on' => $firstVisit,
                'visits' => $serviceVisits->count(),
                'total_spent' => (float) $sales->sum('total'),
                'last_visit_on' => $serviceVisits->first()['date'] ?? null,
                'favourite_service' => $favourite,
                'next_visit' => RebookPlanner::nextVisit($id),
            ],
            'visits' => $visits->take(30),
        ]]);
    }

    /** What the person at the till may change about a client: the notes, and whether they may be texted. */
    #[OA\Patch(path: '/inventory/salon/clients/{id}', summary: 'Client notes and SMS preference', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function updateClient(Request $request, int $id): JsonResponse
    {
        if (!DB::table('inventory_customers')->where('id', $id)->exists()) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'notes' => 'nullable|string|max:1000',
            'sms_opt_out' => 'sometimes|boolean',
            'birthday' => 'sometimes|nullable|date|before_or_equal:today',
            // What they like: {hairstyle, colour, nails, allergies}, each a short text.
            'preferences' => 'sometimes|nullable|array',
            'preferences.hairstyle' => 'nullable|string|max:160',
            'preferences.colour' => 'nullable|string|max:160',
            'preferences.nails' => 'nullable|string|max:160',
            'preferences.allergies' => 'nullable|string|max:200',
            'referred_by' => ['sometimes', 'nullable', 'integer', \Illuminate\Validation\Rule::notIn([$id])],
        ]);
        if (!empty($data['referred_by']) && !DB::table('inventory_customers')->where('id', $data['referred_by'])->exists()) {
            throw \Illuminate\Validation\ValidationException::withMessages(['referred_by' => ['That client does not exist.']]);
        }
        if (array_key_exists('notes', $data)) {
            $data['notes'] = $data['notes'] !== null ? trim($data['notes']) : null;
            $data['notes'] = $data['notes'] === '' ? null : $data['notes'];
        }
        if (array_key_exists('preferences', $data)) {
            $kept = array_filter(array_map(fn ($v) => is_string($v) ? trim($v) : '', (array) $data['preferences']), fn ($v) => $v !== '');
            $data['preferences'] = $kept === [] ? null : json_encode($kept, JSON_UNESCAPED_UNICODE);
        }
        // A column the server has not been migrated to yet is left out rather than failing the whole save.
        foreach (['birthday', 'preferences', 'referred_by'] as $column) {
            if (!\Illuminate\Support\Facades\Schema::hasColumn('inventory_customers', $column)) {
                unset($data[$column]);
            }
        }

        DB::table('inventory_customers')->where('id', $id)->update($data + ['updated_at' => now()]);

        return response()->json(['message' => 'Client updated']);
    }

    #[OA\Get(path: '/inventory/salon/settings', summary: 'The salon\'s "come back" reminder settings', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function settings(): JsonResponse
    {
        return response()->json(['data' => $this->settingsPayload()]);
    }

    #[OA\Put(path: '/inventory/salon/settings', summary: 'Switch "come back" reminders on or off and set the default wait', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function updateSettings(Request $request): JsonResponse
    {
        $data = $request->validate([
            'rebook_enabled' => 'sometimes|boolean',
            'rebook_weeks' => 'sometimes|integer|min:1|max:' . RebookPlanner::MAX_WEEKS,
            'appointment_reminders' => 'sometimes|boolean',
            'daily_summary' => 'sometimes|boolean',
            'birthday_offer' => 'sometimes|boolean',
            'cancel_hours' => 'sometimes|integer|min:0|max:168',
            'feedback_sms' => 'sometimes|boolean',
            'birthday_text' => 'sometimes|nullable|string|max:160',
        ]);

        if (array_key_exists('birthday_offer', $data) || array_key_exists('birthday_text', $data)) {
            \App\Support\Salon\BirthdayOffer::save(
                array_key_exists('birthday_offer', $data) ? (bool) $data['birthday_offer'] : null,
                array_key_exists('birthday_text', $data) ? (string) ($data['birthday_text'] ?? '') : null,
            );
        }

        if (array_key_exists('feedback_sms', $data)) {
            \App\Support\Salon\SalonFeedback::save((bool) $data['feedback_sms']);
        }

        if (array_key_exists('cancel_hours', $data)) {
            AppointmentPlanner::saveCancelHours((int) $data['cancel_hours']);
        }

        if (array_key_exists('daily_summary', $data)) {
            \App\Support\Salon\DailySummary::save((bool) $data['daily_summary']);
        }

        if (array_key_exists('appointment_reminders', $data)) {
            AppointmentPlanner::saveReminders((bool) $data['appointment_reminders']);
        }

        RebookPlanner::save(
            array_key_exists('rebook_enabled', $data) ? (bool) $data['rebook_enabled'] : null,
            array_key_exists('rebook_weeks', $data) ? (int) $data['rebook_weeks'] : null,
        );

        return response()->json(['message' => 'Settings saved', 'data' => $this->settingsPayload()]);
    }

    /** Who is due to be reminded now (and whether they were), so the owner can see what the daily job does. */
    #[OA\Get(path: '/inventory/salon/rebook/due', summary: 'Clients whose time for the next visit has come', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function rebookDue(): JsonResponse
    {
        return response()->json(['data' => [
            'settings' => $this->settingsPayload(),
            'clients' => RebookPlanner::due(now(), includeSent: true),
        ]]);
    }

    private function settingsPayload(): array
    {
        $s = RebookPlanner::settings();

        return [
            'rebook_enabled' => $s['enabled'],
            'rebook_weeks' => $s['weeks'],
            'appointment_reminders' => AppointmentPlanner::remindersOn(),
            'daily_summary' => \App\Support\Salon\DailySummary::isOn(),
            'cancel_hours' => AppointmentPlanner::cancelHours(),
            'feedback_sms' => \App\Support\Salon\SalonFeedback::isOn(),
            'birthday_offer' => \App\Support\Salon\BirthdayOffer::isOn(),
            'birthday_text' => \App\Support\Salon\BirthdayOffer::text(),
            'max_weeks' => RebookPlanner::MAX_WEEKS,
            'grace_days' => RebookPlanner::GRACE_DAYS,
        ];
    }
}
