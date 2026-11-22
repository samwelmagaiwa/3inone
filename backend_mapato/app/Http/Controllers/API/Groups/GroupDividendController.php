<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupDividends;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use InvalidArgumentException;

/**
 * Dividend runs: prepared by the treasurer with the formula the group chose, approved and posted by the chair (never the same person).
 */
class GroupDividendController extends Controller
{
    private const WORDS = [
        'period_paid' => 'Kipindi hiki tayari kimelipiwa gawio. / A dividend was already paid for this period.',
        'over_pool' => 'Jumla inazidi faida iliyoidhinishwa. / The total is more than the approved profit.',
        'not_draft' => 'Gawio hili si rasimu tena. / This dividend is no longer a draft.',
        'own_run' => 'Huwezi kuidhinisha gawio uliloandaa mwenyewe. / You cannot approve a dividend you prepared yourself.',
    ];

    private function fail(string $code, int $status = 422, array $extra = []): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => self::WORDS[$code] ?? $code] + $extra, $status);
    }

    public function index(): JsonResponse
    {
        return response()->json(['success' => true, 'data' => ['runs' => GroupDividends::query()->orderByDesc('r.period_to')->orderByDesc('r.id')->limit(50)->get()
            ->map(fn ($r) => GroupDividends::payload($r))->values()]]);
    }

    public function show(int $id): JsonResponse
    {
        $run = GroupDividends::query()->where('r.id', $id)->first();
        if ($run === null) {
            return response()->json(['success' => false, 'message' => 'Gawio halipo. / Not found.'], 404);
        }

        return response()->json(['success' => true, 'data' => ['run' => GroupDividends::payload($run, true)]]);
    }

    public function prepare(Request $request): JsonResponse
    {
        $data = $request->validate([
            'period_from' => 'required|date',
            'period_to' => 'required|date|after_or_equal:period_from|before_or_equal:today',
            'profit_pool' => 'required|numeric|min:1|max:100000000000',
            'base' => ['required', Rule::in(['closing', 'average'])],
            'method' => ['required', Rule::in(['rate', 'share'])],
            'rate' => 'nullable|numeric|min:0.001|max:100|required_if:method,rate',
            'note' => 'required|string|min:3|max:255',
        ]);
        try {
            $id = GroupDividends::prepare($data, (string) $request->user()->id);
        } catch (InvalidArgumentException $e) {
            [$code, $total] = array_pad(explode(':', $e->getMessage(), 2), 2, null);

            return $this->fail($code, 422, $total === null ? [] : ['total' => (float) $total]);
        }
        GroupAudit::record((string) $request->user()->id, 'dividend_prepared', $data['period_from'] . '..' . $data['period_to'] . ' (' . $data['base'] . ', ' . $data['method'] . ')', 'dividend', $id);

        return $this->show($id)->setStatusCode(201);
    }

    public function post(Request $request, int $id): JsonResponse
    {
        $run = DB::table('group_dividend_runs')->where('id', $id)->first();
        if ($run === null) {
            return response()->json(['success' => false, 'message' => 'Gawio halipo. / Not found.'], 404);
        }
        try {
            GroupDividends::post($run, (string) $request->user()->id);
        } catch (InvalidArgumentException $e) {
            return $this->fail($e->getMessage(), $e->getMessage() === 'own_run' ? 403 : 409);
        }
        GroupAudit::record((string) $request->user()->id, 'dividend_posted', $run->period_from . '..' . $run->period_to . ': ' . number_format((float) $run->total), 'dividend', $id);

        return $this->show($id);
    }

    public function discard(Request $request, int $id): JsonResponse
    {
        $done = DB::table('group_dividend_runs')->where('id', $id)->where('status', 'draft')->update(['status' => 'discarded', 'updated_at' => now()]);
        if ($done === 0) {
            return $this->fail('not_draft', 409);
        }
        GroupAudit::record((string) $request->user()->id, 'dividend_discarded', 'Draft #' . $id, 'dividend', $id);

        return $this->show($id);
    }

    /** The member's own dividends, from posted runs. */
    public function mine(Request $request): JsonResponse
    {
        $me = GroupAccess::member($request->user());
        $rows = $me === null ? collect() : DB::table('group_dividend_lines as l')->join('group_dividend_runs as r', 'r.id', '=', 'l.run_id')
            ->where('l.member_id', (int) $me['id'])->where('r.status', 'posted')->orderByDesc('r.period_to')
            ->get(['r.id', 'r.period_from', 'r.period_to', 'r.base', 'r.method', 'r.rate', 'l.base as my_base', 'l.amount', 'r.posted_at']);

        return response()->json(['success' => true, 'data' => ['dividends' => $rows->map(fn ($r) => [
            'run_id' => (int) $r->id, 'period_from' => (string) $r->period_from, 'period_to' => (string) $r->period_to, 'base' => $r->base, 'method' => $r->method,
            'rate' => $r->rate === null ? null : (float) $r->rate, 'my_base' => (float) $r->my_base, 'amount' => (float) $r->amount, 'posted_at' => (string) $r->posted_at,
        ])->values()]]);
    }
}
