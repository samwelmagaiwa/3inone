<?php

namespace App\Http\Controllers\API\Inventory;

use App\Services\Inventory\InventoryNotifier;
use App\Support\Salon\AppointmentPlanner;
use App\Support\Salon\SalonAccess;
use App\Support\Salon\SalonBooks;
use App\Support\Salon\SalonFinance;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * The owner's books: the cashbook (cash, mobile money, bank: opening balance, what came in and went out, what the owner
 * put in or took out, and counts that show a difference) and the analytics (trends, new against returning clients,
 * how many come back, the best days and hours). Owner, managers and the accountant only.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Cashbook and analytics')]
class SalonBooksController extends Controller
{
    private function requireManager(Request $request): void
    {
        abort_unless(SalonAccess::isManager($request->user()), 403, 'Ni mmiliki, meneja au mhasibu tu. / Only the owner, a manager or an accountant.');
    }

    private function today(): Carbon
    {
        return Carbon::now(AppointmentPlanner::TIMEZONE)->startOfDay();
    }

    #[OA\Get(path: '/inventory/salon/cashbook', summary: 'The cashbook for a period', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function cashbook(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate(['from' => 'nullable|date_format:Y-m-d', 'to' => 'nullable|date_format:Y-m-d|after_or_equal:from']);
        $today = $this->today();
        $from = $data['from'] ?? $today->copy()->startOfMonth()->toDateString();
        $to = $data['to'] ?? $today->toDateString();

        $moves = DB::table('inventory_cash_moves')->whereBetween('moved_on', [$from, $to])->orderByDesc('moved_on')->orderByDesc('id')->get()->map(fn ($m) => [
            'id' => (int) $m->id,
            'kind' => $m->kind,
            'method' => $m->method,
            'amount' => SalonFinance::money($m->amount),
            'moved_on' => Carbon::parse($m->moved_on)->toDateString(),
            'note' => $m->note,
        ])->values();

        return response()->json(['data' => SalonBooks::book($from, $to) + ['moves' => $moves]]);
    }

    #[OA\Post(path: '/inventory/salon/cashbook/moves', summary: 'Money the owner put in or took out, or the opening balance', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function storeMove(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate([
            'kind' => ['required', Rule::in(['opening', 'owner_deposit', 'owner_withdrawal'])],
            'method' => ['required', Rule::in(SalonBooks::BUCKETS)],
            'amount' => 'required|numeric|gt:0|max:1000000000',
            'moved_on' => 'nullable|date_format:Y-m-d|before_or_equal:' . \Carbon\Carbon::now(\App\Support\Salon\AppointmentPlanner::TIMEZONE)->toDateString(),
            'note' => 'nullable|string|max:160',
        ]);
        $on = $data['moved_on'] ?? $this->today()->toDateString();

        // Taking out more than the book says is there is refused: that is a mistake or a missing entry.
        if ($data['kind'] === 'owner_withdrawal') {
            $held = (float) SalonBooks::book($on, $on)['places'][$data['method']]['closing'];
            if ((float) $data['amount'] > $held + 0.009) {
                throw ValidationException::withMessages(['amount' => ['Kiasi kinazidi kilichopo kwenye kitabu (' . number_format($held) . '). / More than the book says is held (' . number_format($held) . ').']]);
            }
        }

        $id = DB::table('inventory_cash_moves')->insertGetId([
            'kind' => $data['kind'], 'method' => $data['method'], 'amount' => $data['amount'], 'moved_on' => $on,
            'note' => !empty($data['note']) ? trim($data['note']) : null, 'created_by' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Saved', 'data' => ['id' => (int) $id]], 201);
    }

    #[OA\Delete(path: '/inventory/salon/cashbook/moves/{id}', summary: 'Remove an entry made by mistake', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function destroyMove(Request $request, int $id): JsonResponse
    {
        $this->requireManager($request);
        abort_if(DB::table('inventory_cash_moves')->where('id', $id)->doesntExist(), 404, 'Entry not found');
        DB::table('inventory_cash_moves')->where('id', $id)->delete();

        return response()->json(['message' => 'Deleted']);
    }

    #[OA\Post(path: '/inventory/salon/cashbook/counts', summary: 'Count what is really held and compare it with the book', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function storeCount(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate([
            'method' => ['required', Rule::in(SalonBooks::BUCKETS)],
            'counted' => 'required|numeric|min:0|max:1000000000',
            'counted_on' => 'nullable|date_format:Y-m-d|before_or_equal:' . \Carbon\Carbon::now(\App\Support\Salon\AppointmentPlanner::TIMEZONE)->toDateString(),
            'note' => 'nullable|string|max:160',
        ]);
        $on = $data['counted_on'] ?? $this->today()->toDateString();
        $expected = (float) SalonBooks::book($on, $on)['places'][$data['method']]['closing'];
        $difference = round((float) $data['counted'] - $expected, 2);

        $id = DB::table('inventory_cash_counts')->insertGetId([
            'counted_on' => $on, 'method' => $data['method'], 'expected' => $expected, 'counted' => $data['counted'], 'difference' => $difference,
            'note' => !empty($data['note']) ? trim($data['note']) : null, 'created_by' => (string) $request->user()->id, 'created_at' => now(), 'updated_at' => now(),
        ]);

        if (abs($difference) >= 0.01) {
            $short = $difference < 0;
            $amount = number_format(abs($difference));
            app(InventoryNotifier::class)->notifyByPermission(
                ['inv_view_reports'],
                'salon_book_difference',
                $short ? 'Kitabu kinazidi kilichopo / The book says more than is held' : 'Kilichopo kinazidi kitabu / More is held than the book says',
                strtoupper($data['method']) . ': ' . ($short ? "pungufu / short {$amount}" : "zaidi / over {$amount}") . ' (TSh)',
                ['count_id' => $id, 'method' => $data['method'], 'difference' => $difference],
                excludeUserId: (string) $request->user()->id,
            );
        }

        return response()->json(['message' => 'Saved', 'data' => ['id' => (int) $id, 'expected' => SalonFinance::money($expected), 'difference' => SalonFinance::money($difference)]], 201);
    }

    // ------------------------------------------------------------------ analytics

    #[OA\Get(path: '/inventory/salon/analytics', summary: 'Trends, new against returning clients, retention, best days and hours', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function analytics(Request $request): JsonResponse
    {
        $this->requireManager($request);
        $data = $request->validate(['months' => 'nullable|integer|min:1|max:12']);
        $months = (int) ($data['months'] ?? 6);
        $tz = AppointmentPlanner::TIMEZONE;
        $today = $this->today();
        $start = $today->copy()->startOfMonth()->subMonths($months - 1);

        // Every service visit ever: who, when (the salon's own clock). A client with no name on the sale counts only for the
        // takings, never as a "client".
        $visits = DB::table('inventory_sales as s')
            ->whereNull('s.cancelled_at')
            ->whereExists(fn ($q) => $q->select(DB::raw(1))->from('inventory_sale_items as si')->whereColumn('si.sale_id', 's.id')->where('si.is_service', true))
            ->orderBy('s.created_at')
            ->get(['s.id', 's.customer_id', 's.created_at'])
            ->map(fn ($v) => ['id' => (int) $v->id, 'client' => $v->customer_id === null ? null : (int) $v->customer_id, 'at' => Carbon::parse($v->created_at, 'UTC')->setTimezone($tz)]);

        $first = [];
        foreach ($visits as $v) {
            if ($v['client'] !== null && !isset($first[$v['client']])) {
                $first[$v['client']] = $v['at'];
            }
        }

        $trend = [];
        for ($i = 0; $i < $months; $i++) {
            $from = $start->copy()->addMonths($i);
            $to = $from->copy()->endOfMonth()->startOfDay();
            if ($to->gt($today)) {
                $to = $today;
            }
            $key = $from->format('Y-m');
            $inMonth = $visits->filter(fn ($v) => $v['at']->format('Y-m') === $key);
            $clients = $inMonth->pluck('client')->filter()->unique();
            $new = $clients->filter(fn ($c) => $first[$c]->format('Y-m') === $key)->count();
            $summary = SalonFinance::summary($from, $to);
            $trend[] = [
                'month' => $key,
                'revenue' => $summary['revenue'],
                'net_profit' => $summary['net_profit'],
                'visits' => $inMonth->count(),
                'clients' => $clients->count(),
                'new_clients' => $new,
                'returning_clients' => $clients->count() - $new,
            ];
        }

        // Of the clients who first came at least 60 days ago, how many came again within 60 days of that first visit.
        $cut = $today->copy()->subDays(60);
        $eligible = collect($first)->filter(fn ($at) => $at->lte($cut));
        $came = $eligible->filter(function ($at, $client) use ($visits) {
            return $visits->contains(fn ($v) => $v['client'] === $client && $v['at']->gt($at) && $v['at']->lte($at->copy()->addDays(60)));
        })->count();

        $recent = $visits->filter(fn ($v) => $v['at']->gte($start));
        $weekday = array_fill(1, 7, 0);
        $hour = [];
        foreach ($recent as $v) {
            $weekday[(int) $v['at']->dayOfWeekIso]++;
            $hour[(int) $v['at']->format('G')] = ($hour[(int) $v['at']->format('G')] ?? 0) + 1;
        }
        ksort($hour);

        $services = DB::table('inventory_sale_items as si')
            ->join('inventory_sales as s', 's.id', '=', 'si.sale_id')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'si.product_id')
            ->whereNull('s.cancelled_at')->where('si.is_service', true)
            ->whereDate('s.created_at', '>=', $start->toDateString())
            ->groupBy('si.product_id', 'p.name')
            ->selectRaw('p.name as name, SUM(COALESCE(si.unit_qty, si.quantity)) as times, SUM(si.total) as total')
            ->orderByRaw('SUM(si.total) DESC')->limit(10)->get()
            ->map(fn ($r) => ['name' => (string) $r->name, 'times' => (int) $r->times, 'total' => SalonFinance::money($r->total)])->values();

        return response()->json(['data' => [
            'months' => $months,
            'trend' => $trend,
            'retention' => [
                'eligible' => $eligible->count(),
                'came_back' => $came,
                'rate' => $eligible->count() === 0 ? null : round($came * 100 / $eligible->count(), 1),
                'days' => 60,
            ],
            'busiest' => [
                'weekdays' => collect($weekday)->map(fn ($n, $d) => ['day' => (int) $d, 'visits' => $n])->values(),
                'hours' => collect($hour)->map(fn ($n, $h) => ['hour' => (int) $h, 'visits' => $n])->values(),
            ],
            'top_services' => $services,
        ]]);
    }
}
