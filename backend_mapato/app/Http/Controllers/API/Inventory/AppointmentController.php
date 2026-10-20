<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\User;
use App\Support\Salon\AppointmentPlanner;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use App\Support\PaymentChannels;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * A salon's diary: who is booked with which stylist, when, for what. Every query runs against the signed-in business's
 * salon only (the inventory tables are limited to it automatically). The rules (clashes, which state may follow which)
 * are in {@see AppointmentPlanner}.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Salon appointments')]
class AppointmentController extends Controller
{
    #[OA\Get(path: '/inventory/salon/appointments', summary: 'The appointments of a day (default today), or of a period', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'date' => 'nullable|date',
            'from' => 'nullable|date',
            'to' => 'nullable|date|after_or_equal:from',
            'staff_id' => 'nullable|string|max:64',
        ]);

        $from = Carbon::parse($data['from'] ?? $data['date'] ?? now(AppointmentPlanner::TIMEZONE))->toDateString();
        $to = Carbon::parse($data['to'] ?? $data['date'] ?? $from)->toDateString();

        $rows = DB::table('inventory_appointments')
            ->where('starts_at', '>=', $from . ' 00:00:00')
            ->where('starts_at', '<=', $to . ' 23:59:59')
            ->when(!empty($data['staff_id']), fn ($q) => $q->where('staff_id', $data['staff_id']))
            ->when(\App\Support\Salon\SalonBranch::selected($request) !== null, fn ($q) => $q->where('branch_id', \App\Support\Salon\SalonBranch::selected($request)))
            // A stylist sees their own diary only.
            ->when($this->isStylist($request), fn ($q) => $q->where('staff_id', (string) $request->user()->id))
            ->orderBy('starts_at')
            ->orderBy('id')
            ->get()
            ->map(fn ($r) => $this->present($r))
            ->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Post(path: '/inventory/salon/appointments', summary: 'Book an appointment', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created'), new OA\Response(response: 422, description: 'Invalid, or the stylist is already booked then')])]
    public function store(Request $request): JsonResponse
    {
        $this->refuseStylist($request);
        $fields = $this->fields($request, null);
        // The branch it is for: the one chosen, else the stylist's own, else the booker's.
        $branch = \App\Support\Salon\SalonBranch::selected($request) ?? (\App\Support\Salon\SalonBranch::homeOf((string) ($fields['staff_id'] ?? '')) ?? \App\Support\Salon\SalonBranch::forNew($request));
        $id = DB::table('inventory_appointments')->insertGetId(($branch !== null && \Illuminate\Support\Facades\Schema::hasColumn('inventory_appointments', 'branch_id') ? ['branch_id' => $branch] : []) + $fields + [
            'status' => 'booked',
            'created_by' => (string) $request->user()->id,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // The stylist booked for it is told, unless they booked it themselves.
        if (!empty($fields['staff_id']) && (string) $fields['staff_id'] !== (string) $request->user()->id) {
            $when = Carbon::parse($fields['starts_at'])->format('d/m H:i');
            app(\App\Services\Inventory\InventoryNotifier::class)->notifyUser(
                (string) $fields['staff_id'],
                'salon_new_booking',
                'Miadi mpya / New appointment',
                "{$fields['client_name']} - {$when}",
                ['appointment_id' => (int) $id],
            );
        }

        return response()->json(['message' => 'Appointment booked', 'data' => $this->present(DB::table('inventory_appointments')->find($id))], 201);
    }

    #[OA\Put(path: '/inventory/salon/appointments/{id}', summary: 'Change or move an appointment', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function update(Request $request, int $id): JsonResponse
    {
        $this->refuseStylist($request);
        $row = DB::table('inventory_appointments')->find($id);
        abort_if($row === null, 404, 'Appointment not found');
        if (!in_array($row->status, AppointmentPlanner::ACTIVE, true)) {
            throw ValidationException::withMessages(['status' => ['A finished appointment can no longer be changed.']]);
        }

        DB::table('inventory_appointments')->where('id', $id)->update($this->fields($request, $row) + ['updated_at' => now()]);

        return response()->json(['message' => 'Appointment updated', 'data' => $this->present(DB::table('inventory_appointments')->find($id))]);
    }

    #[OA\Post(path: '/inventory/salon/appointments/{id}/status', summary: 'Confirm, start, finish, cancel or mark a no-show', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function status(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'status' => 'required|in:confirmed,in_progress,done,cancelled,no_show',
        ]);

        $row = DB::table('inventory_appointments')->find($id);
        abort_if($row === null, 404, 'Appointment not found');
        // A stylist may move their own appointments along (start, finish), never someone else's.
        abort_if($this->isStylist($request) && (string) $row->staff_id !== (string) $request->user()->id, 403, 'Hii si miadi yako. / This is not your appointment.');
        if (!in_array($data['status'], AppointmentPlanner::NEXT[$row->status] ?? [], true)) {
            throw ValidationException::withMessages(['status' => ["An appointment that is {$row->status} cannot become {$data['status']}."]]);
        }

        DB::table('inventory_appointments')->where('id', $id)->update(['status' => $data['status'], 'updated_at' => now()] + $this->settleDeposit($row, $data['status']));

        return response()->json(['message' => 'Appointment updated', 'data' => $this->present(DB::table('inventory_appointments')->find($id))]);
    }

    /**
     * What happens to a deposit when the appointment ends: put into the sale when it is done; kept when the client did
     * not come, or cancelled too late (inside the salon's cancellation hours); given back otherwise.
     *
     * @return array<string, mixed>
     */
    private function settleDeposit(object $row, string $status): array
    {
        if (!Schema::hasColumn('inventory_appointments', 'deposit_status') || ($row->deposit_status ?? 'none') !== 'held') {
            return [];
        }

        $outcome = match ($status) {
            'done' => 'applied',
            'no_show' => 'forfeited',
            'cancelled' => ($hours = AppointmentPlanner::cancelHours()) > 0 && Carbon::parse($row->starts_at, AppointmentPlanner::TIMEZONE)->diffInHours(now(AppointmentPlanner::TIMEZONE), false) > -$hours ? 'forfeited' : 'refunded',
            default => null,
        };

        return $outcome === null ? [] : ['deposit_status' => $outcome, 'deposit_resolved_at' => now()];
    }

    /** The people who do the work themselves: hair stylists, nail technicians, lash and makeup artists. */
    private function isStylist(Request $request): bool
    {
        return in_array(strtolower((string) $request->user()->role), ['hair_stylist', 'nail_technician', 'lash_makeup_artist'], true);
    }

    /** Booking is for the reception and the owner; a stylist works the diary, they do not write it. */
    private function refuseStylist(Request $request): void
    {
        abort_if($this->isStylist($request), 403, 'Mapokezi au meneja ndiye anayeweka miadi. / Reception or a manager books appointments.');
    }

    /**
     * Check a booking and work out what is stored. The services are read from the business's own list (never trusted
     * from the app): their names and minutes are copied as they are now, and the price is the one asked for when it
     * is one of the service's price options or its own.
     *
     * @return array<string, mixed>
     */
    private function fields(Request $request, ?object $existing): array
    {
        $data = $request->validate([
            'customer_id' => 'nullable|integer',
            'client_name' => ($existing === null ? 'required_without:customer_id' : 'sometimes') . '|nullable|string|max:120',
            'client_phone' => 'nullable|string|max:30',
            'staff_id' => 'nullable|string|max:64',
            'starts_at' => ($existing === null ? 'required' : 'sometimes') . '|date_format:Y-m-d H:i',
            'services' => ($existing === null ? 'required' : 'sometimes') . '|array|min:1|max:12',
            'services.*.product_id' => 'required|integer',
            'services.*.price' => 'nullable|numeric|min:0',
            'services.*.label' => 'nullable|string|max:40',
            'duration_minutes' => 'nullable|integer|min:5|max:1440',
            // A deposit taken to hold the booking (kept, given back or put into the sale when it is settled).
            'deposit_amount' => 'nullable|numeric|min:0|max:100000000',
            'deposit_method' => ['nullable', Rule::in(PaymentChannels::all())],
            'notes' => 'nullable|string|max:1000',
            'force' => 'sometimes|boolean',
        ]);

        // Who is being booked.
        $customerId = array_key_exists('customer_id', $data) ? $data['customer_id'] : ($existing->customer_id ?? null);
        $name = array_key_exists('client_name', $data) ? trim((string) $data['client_name']) : ($existing->client_name ?? '');
        $phone = array_key_exists('client_phone', $data) ? trim((string) $data['client_phone']) : ($existing->client_phone ?? '');
        if ($customerId !== null) {
            $client = DB::table('inventory_customers')->where('id', $customerId)->first();
            if ($client === null) {
                throw ValidationException::withMessages(['customer_id' => ['That client does not exist.']]);
            }
            $name = $name !== '' ? $name : (string) $client->name;
            $phone = $phone !== '' ? $phone : (string) ($client->phone ?? '');
        }
        if ($name === '') {
            throw ValidationException::withMessages(['client_name' => ['Say who the appointment is for.']]);
        }

        // The services, as the business has them now.
        $existingServices = $existing ? (json_decode((string) $existing->services, true) ?: []) : [];
        $asked = $data['services'] ?? array_map(fn ($s) => ['product_id' => $s['product_id'], 'price' => $s['price'] ?? null, 'label' => $s['label'] ?? null], $existingServices);
        $lines = [];
        $minutes = 0;
        $total = 0.0;
        foreach ($asked as $line) {
            $product = DB::table('inventory_products')->where('id', $line['product_id'])->where('is_service', true)->first();
            if ($product === null) {
                throw ValidationException::withMessages(['services' => ['One of the services does not exist (or is goods, not a service).']]);
            }
            $price = isset($line['price']) ? (float) $line['price'] : (float) $product->selling_price;
            $own = (int) ($product->duration_minutes ?? 0);
            $minutes += $own > 0 ? $own : 0;
            $total += $price;
            $lines[] = array_filter([
                'product_id' => (int) $product->id,
                'name' => (string) $product->name,
                'price' => $price,
                'minutes' => $own > 0 ? $own : null,
                'label' => !empty($line['label']) ? (string) $line['label'] : null,
            ], fn ($v) => $v !== null);
        }
        $minutes = (int) ($data['duration_minutes'] ?? ($minutes > 0 ? $minutes : AppointmentPlanner::DEFAULT_MINUTES));

        // When, and who with.
        $start = Carbon::createFromFormat('Y-m-d H:i', $data['starts_at'] ?? Carbon::parse($existing->starts_at)->format('Y-m-d H:i'));
        $end = $start->copy()->addMinutes($minutes);
        $staffId = array_key_exists('staff_id', $data) ? ($data['staff_id'] ?: null) : ($existing->staff_id ?? null);
        $staffName = null;
        if ($staffId !== null) {
            $member = User::query()->whereIn('id', $request->user()->accountMemberIds())->where('is_active', true)->where('id', $staffId)->first(['id', 'name']);
            if ($member === null) {
                throw ValidationException::withMessages(['staff_id' => ['That person cannot be booked.']]);
            }
            $staffName = $member->name;
        }

        // Not on a day off, not on a day they do not work, not outside their hours (unless the owner says book anyway).
        $unavailable = AppointmentPlanner::availability($staffId, (string) $staffName, $start);
        if ($unavailable !== null && empty($data['force'])) {
            throw ValidationException::withMessages(['staff_id' => [$unavailable]]);
        }

        $clash = AppointmentPlanner::clash($staffId, $start, $end, $existing->id ?? null);
        if ($clash !== null && empty($data['force'])) {
            $at = Carbon::parse($clash->starts_at)->format('H:i') . '-' . Carbon::parse($clash->ends_at)->format('H:i');
            throw ValidationException::withMessages(['staff_id' => ["{$staffName} ana miadi saa {$at} ({$clash->client_name}). / {$staffName} is already booked {$at} ({$clash->client_name})."]]);
        }

        // The deposit: held from the moment it is taken; once settled (sale, kept or given back) it cannot be changed.
        $deposit = [];
        if (Schema::hasColumn('inventory_appointments', 'deposit_status')) {
            $settled = $existing !== null && in_array($existing->deposit_status, ['applied', 'forfeited', 'refunded'], true);
            if (!$settled) {
                $amount = array_key_exists('deposit_amount', $data) ? (float) ($data['deposit_amount'] ?? 0) : (float) ($existing->deposit_amount ?? 0);
                $method = array_key_exists('deposit_method', $data) ? ($data['deposit_method'] ?: null) : ($existing->deposit_method ?? null);
                if ($amount > 0 && $method === null) {
                    throw ValidationException::withMessages(['deposit_method' => ['Sema amana ililipwa kwa njia gani. / Say how the deposit was paid.']]);
                }
                $deposit = ['deposit_amount' => $amount, 'deposit_method' => $amount > 0 ? $method : null, 'deposit_status' => $amount > 0 ? 'held' : 'none'];
            }
        }

        return $deposit + [
            'customer_id' => $customerId,
            'client_name' => $name,
            'client_phone' => $phone !== '' ? $phone : null,
            'staff_id' => $staffId,
            'staff_name' => $staffName,
            'starts_at' => $start->format('Y-m-d H:i:s'),
            'ends_at' => $end->format('Y-m-d H:i:s'),
            'services' => json_encode($lines),
            'notes' => array_key_exists('notes', $data) ? ($data['notes'] ?: null) : ($existing->notes ?? null),
            'total' => $total,
            // A moved appointment is reminded again.
            'reminder_sent_at' => $existing !== null && ($data['starts_at'] ?? null) !== null && Carbon::parse($existing->starts_at)->format('Y-m-d H:i') !== $data['starts_at'] ? null : ($existing->reminder_sent_at ?? null),
        ];
    }

    /** @return array<string, mixed> */
    private function present(object $r): array
    {
        return [
            'id' => (int) $r->id,
            'customer_id' => $r->customer_id === null ? null : (int) $r->customer_id,
            'client_name' => (string) $r->client_name,
            'client_phone' => $r->client_phone,
            'staff_id' => $r->staff_id,
            'staff_name' => $r->staff_name,
            'starts_at' => Carbon::parse($r->starts_at)->format('Y-m-d H:i'),
            'ends_at' => Carbon::parse($r->ends_at)->format('Y-m-d H:i'),
            'status' => (string) $r->status,
            'source' => (string) ($r->source ?? 'staff'),
            'branch_id' => isset($r->branch_id) ? (int) $r->branch_id : null,
            'deposit' => (float) ($r->deposit_amount ?? 0) > 0 ? [
                'amount' => (float) $r->deposit_amount == floor((float) $r->deposit_amount) ? (int) $r->deposit_amount : (float) $r->deposit_amount,
                'method' => $r->deposit_method,
                'status' => $r->deposit_status,
            ] : null,
            'services' => json_decode((string) $r->services, true) ?: [],
            'notes' => $r->notes,
            'total' => (float) $r->total == floor((float) $r->total) ? (int) $r->total : (float) $r->total,
        ];
    }
}
