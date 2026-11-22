<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupContributions;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupLoans;
use App\Support\Groups\GroupMembers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * The group at a glance, for its officers: one call for the whole dashboard. Membership figures for whoever sees members; the money
 * (cash, savings, contributions, loans, the 12-month trend and this month's mix) only for whoever sees the group's money -- the rest is null.
 * Every money figure is read from verified rows only, like everywhere else in the service.
 */
class GroupDashboardController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $data = $request->validate(['month' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/']]);
        $user = $request->user();
        $month = $data['month'] ?? now()->format('Y-m');
        $start = $month . '-01';
        $end = Carbon::parse($start)->endOfMonth()->toDateString();
        $today = now()->toDateString();

        $counts = DB::table('group_members')->selectRaw('status, COUNT(*) as n')->groupBy('status')->pluck('n', 'status');
        $out = [
            'month' => $month,
            'members' => [
                'active' => (int) ($counts[GroupMembers::ACTIVE] ?? 0),
                'applications' => (int) ($counts[GroupMembers::SUBMITTED] ?? 0),
                'suspended' => (int) ($counts[GroupMembers::SUSPENDED] ?? 0),
                'joined_in_month' => DB::table('group_members')->whereBetween('joined_on', [$start, $end])->count(),
            ],
            'next_meeting' => DB::table('group_meetings')->where('status', 'scheduled')->where('starts_at', '>=', now())->orderBy('starts_at')->first(['id', 'title', 'starts_at', 'venue']),
            'money' => null,
        ];

        if (GroupAccess::can($user, 'view_finance')) {
            $verified = fn () => DB::table('group_transactions')->where('status', GroupLedger::VERIFIED);
            $signed = "SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END)";

            // The 12 months up to the chosen one: money in and out per month.
            $from = Carbon::parse($start)->subMonths(11)->toDateString();
            $trendRows = $verified()->whereBetween('paid_on', [$from, $end])->get(['paid_on', 'direction', 'amount']);
            $trend = [];
            for ($m = Carbon::parse($from); $m->toDateString() <= $end; $m->addMonth()) {
                $trend[$m->format('Y-m')] = ['month' => $m->format('Y-m'), 'in' => 0.0, 'out' => 0.0];
            }
            foreach ($trendRows as $r) {
                $key = substr((string) $r->paid_on, 0, 7);
                if (isset($trend[$key])) {
                    $trend[$key][$r->direction === 'in' ? 'in' : 'out'] += (float) $r->amount;
                }
            }

            $mix = $verified()->whereBetween('paid_on', [$start, $end])
                ->selectRaw("category, SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END) as money_in, SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END) as money_out")
                ->groupBy('category')->get()
                ->map(fn ($r) => ['category' => $r->category, 'in' => round((float) $r->money_in, 2), 'out' => round((float) $r->money_out, 2)])->values();

            $position = GroupContributions::position($month, $today);
            $loans = ['principal' => 0.0, 'interest' => 0.0, 'arrears' => 0.0, 'running' => 0, 'overdue' => 0];
            foreach (DB::table('group_loans')->where('status', 'active')->get() as $loan) {
                $p = GroupLoans::position($loan);
                if ($p['outstanding'] <= 0) {
                    continue;
                }
                $loans['principal'] += $p['outstanding_principal'];
                $loans['interest'] += $p['outstanding_interest'];
                $loans['arrears'] += $p['arrears'];
                $loans['running']++;
                $loans['overdue'] += $p['arrears'] > 0 ? 1 : 0;
            }
            $yearStart = substr($month, 0, 4) . '-01-01';
            $sum = fn (string $category, string $direction) => round((float) $verified()->where('category', $category)->where('direction', $direction)
                ->whereBetween('paid_on', [$yearStart, $end])->sum('amount'), 2);

            $out['money'] = [
                'cash_on_record' => round((float) $verified()->selectRaw("COALESCE({$signed}, 0) as t")->value('t'), 2),
                'month_in' => round(array_sum(array_column(array_values(array_filter($trend, fn ($t) => $t['month'] === $month)), 'in')), 2),
                'month_out' => round(array_sum(array_column(array_values(array_filter($trend, fn ($t) => $t['month'] === $month)), 'out')), 2),
                'savings' => round((float) $verified()->whereIn('category', ['savings', 'dividend'])->selectRaw("COALESCE({$signed}, 0) as t")->value('t'), 2),
                'shares' => round((float) $verified()->where('category', 'shares')->selectRaw("COALESCE({$signed}, 0) as t")->value('t'), 2),
                'contributions' => $position,
                'loans' => array_map(fn ($v) => is_float($v) ? round($v, 2) : $v, $loans),
                'pending_count' => DB::table('group_transactions')->where('status', GroupLedger::PENDING)->count(),
                'year' => [
                    'welfare_paid' => $sum('welfare', 'out'),
                    'dividends' => $sum('dividend', 'in'),
                    'hire_income' => round($sum('hire', 'in') - $sum('hire', 'out'), 2),
                    'expenses' => $sum('expense', 'out'),
                ],
                'trend' => array_values(array_map(fn ($t) => ['month' => $t['month'], 'in' => round($t['in'], 2), 'out' => round($t['out'], 2)], $trend)),
                'mix' => $mix,
            ];
        }

        return response()->json(['success' => true, 'data' => $out]);
    }
}
