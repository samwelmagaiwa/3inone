<?php

namespace App\Http\Controllers\API\Inventory;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Routing\Controller;
use OpenApi\Attributes as OA;

class ReminderController extends Controller
{
    #[OA\Get(
        path: '/inventory/reminders',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Reminder'],
        parameters: [
            new OA\Parameter(name: 'type', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function index(Request $request)
    {
        $type = $request->query('type'); // payment_due | low_stock
        $status = $request->query('status'); // open | snoozed | done

        // A reminder put away for a while comes back as open when that time has passed, so it asks again.
        DB::table('inventory_reminders')->where('status', 'snoozed')->whereNotNull('snooze_until')->where('snooze_until', '<=', now())
            ->update(['status' => 'open', 'snooze_until' => null, 'updated_at' => now()]);

        $q = DB::table('inventory_reminders')->orderByDesc('id');
        if ($type) { $q->where('type', $type); }
        if ($status) { $q->where('status', $status); }

        $reminders = $q->paginate(20);

        // A payment reminder says whose debt it is, how much is still owed and for how many days (what the phone reads aloud).
        $saleIds = collect($reminders->items())->where('type', 'payment_due')->pluck('related_id')->filter()->unique()->values();
        $sales = $saleIds->isEmpty() ? collect() : DB::table('inventory_sales as s')->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->whereIn('s.id', $saleIds)->get(['s.id', 's.total', 's.paid_total', 's.created_at', 's.due_date', 's.customer_name_override', 'c.name as customer_name'])->keyBy('id');
        $today = now('Africa/Dar_es_Salaam')->startOfDay();
        $items = collect($reminders->items())->map(function ($r) use ($sales, $today) {
            $s = $r->type === 'payment_due' && $r->related_id ? $sales->get($r->related_id) : null;
            if ($s === null) {
                return $r;
            }
            $since = \Carbon\Carbon::parse($s->created_at, 'UTC')->setTimezone('Africa/Dar_es_Salaam')->startOfDay();
            $r->customer_name = $s->customer_name ?: $s->customer_name_override;
            $r->amount_left = round(max(0, (float) $s->total - (float) $s->paid_total), 2);
            $r->days = max(0, (int) $since->diffInDays($today));
            $r->due_date = $s->due_date;

            return $r;
        })->all();

        return response()->json([
            'data' => $items,
            'meta' => [
                'current_page' => $reminders->currentPage(),
                'last_page' => $reminders->lastPage(),
                'per_page' => $reminders->perPage(),
                'total' => $reminders->total(),
            ],
        ]);
    }

    #[OA\Put(

        path: '/inventory/reminders/{id}/done',

        summary: 'Mark done',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Reminder'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function markDone($id)
    {
        $row = DB::table('inventory_reminders')->where('id', $id)->first();
        if (!$row) return response()->json(['message' => 'Not found'], 404);
        DB::table('inventory_reminders')->where('id', $id)->update([
            'status' => 'done',
            'updated_at' => now(),
        ]);
        return response()->json(['message' => 'Reminder marked done']);
    }

    #[OA\Put(

        path: '/inventory/reminders/{id}/snooze',

        summary: 'Snooze',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Reminder'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'minutes', type: 'integer', nullable: true),
                new OA\Property(property: 'until', type: 'string', format: 'date', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function snooze(Request $request, $id)
    {
        $v = Validator::make($request->all(), [
            'minutes' => 'nullable|integer|min:1',
            'until' => 'nullable|date',
        ]);
        if ($v->fails()) return response()->json(['message' => $v->errors()->first()], 422);

        $row = DB::table('inventory_reminders')->where('id', $id)->first();
        if (!$row) return response()->json(['message' => 'Not found'], 404);

        $until = $request->until ? now()->parse($request->until) : now()->addMinutes($request->input('minutes', 60));
        DB::table('inventory_reminders')->where('id', $id)->update([
            'status' => 'snoozed',
            'snooze_until' => $until,
            'updated_at' => now(),
        ]);
        return response()->json(['message' => 'Reminder snoozed']);
    }
}
