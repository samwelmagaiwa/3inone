<?php

namespace App\Support\Ai;

use App\Http\Controllers\API\Groups\GroupDashboardController;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupContributions;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupLoans;
use App\Support\Groups\GroupStatement;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * The Groups (Vikundi) service for the AI assistant: the group at a glance, who owes contributions, one member's account, loans, recent
 * payments and the person's own account. Every group_* query is already limited to the signed-in person's business by the query grammar;
 * which tool a person gets follows the same group rights as the matching screens (GroupAccess), and "ME" (looking as an ordinary member)
 * leaves only their own account. Money figures are verified rows only, as everywhere else in the service.
 */
final class GroupsTools
{
    /** The group at a glance: the leaders' dashboard, without the long chart series. */
    public static function overview(array $args, User $user): array
    {
        $request = Request::create('/api/groups/dashboard', 'GET', ['month' => AssistantTools::month($args)]);
        $request->setUserResolver(fn () => $user);
        $d = app(GroupDashboardController::class)->show($request)->getData(true)['data'] ?? [];
        $money = $d['money'] ?? null;
        if (is_array($money)) {
            unset($money['trend']);
        }
        $data = ['currency' => 'TSh', 'month' => $d['month'] ?? null, 'members' => $d['members'] ?? null, 'next_meeting' => $d['next_meeting'] ?? null, 'money' => $money ?? 'not_available_to_this_person', 'desk' => $d['desk'] ?? null];

        $rows = [['title' => 'Active members', 'value' => (string) ($d['members']['active'] ?? 0), 'note' => ($d['members']['applications'] ?? 0) . ' applications waiting']];
        if (is_array($money)) {
            $rows[] = ['title' => 'Cash on record', 'value' => AssistantTools::tsh($money['cash_on_record'] ?? 0)];
            $rows[] = ['title' => 'Savings', 'value' => AssistantTools::tsh($money['savings'] ?? 0), 'note' => 'shares ' . AssistantTools::tsh($money['shares'] ?? 0)];
            $c = $money['contributions'] ?? [];
            $rows[] = ['title' => 'Contributions this month', 'value' => AssistantTools::tsh($c['collected'] ?? 0) . ' / ' . AssistantTools::tsh($c['expected'] ?? 0), 'note' => ($c['overdue_members'] ?? 0) . ' members overdue'];
            $l = $money['loans'] ?? [];
            $rows[] = ['title' => 'Loans out', 'value' => AssistantTools::tsh(($l['principal'] ?? 0) + ($l['interest'] ?? 0)), 'note' => ($l['running'] ?? 0) . ' running, ' . ($l['overdue'] ?? 0) . ' late'];
        }

        return ['data' => $data, 'card' => ['type' => 'rows', 'title' => 'Group ' . ($d['month'] ?? ''), 'rows' => $rows]];
    }

    /** Members who owe contributions, most owed first, with how many and how late. */
    public static function whoOwes(array $args): array
    {
        $today = now()->toDateString();
        $q = GroupContributions::owing(GroupContributions::query());
        if (empty($args['include_not_yet_due'])) {
            $q->where('o.due_date', '<', $today);
        }
        $rows = $q->get()->groupBy('member_id')->map(fn ($g) => [
            'member' => $g->first()->member_name,
            'number' => $g->first()->member_number,
            'owed' => round($g->sum(fn ($o) => (float) $o->amount_due - (float) $o->paid), 2),
            'contributions' => $g->count(),
            'oldest_due' => (string) $g->min('due_date'),
            'days_late' => max(0, (int) \Illuminate\Support\Carbon::parse((string) $g->min('due_date'))->diffInDays(\Illuminate\Support\Carbon::parse($today), false)),
        ])->sortByDesc('owed')->values();
        $total = round($rows->sum('owed'), 2);
        $top = $rows->take(AssistantTools::limit($args))->all();

        return ['data' => ['currency' => 'TSh', 'members_owing' => $rows->count(), 'total_owed' => $total, 'members' => $top], 'card' => $top === [] ? null : ['type' => 'rows', 'title' => 'Contributions owed', 'rows' => array_map(
            fn ($m) => ['title' => $m['member'], 'value' => AssistantTools::tsh($m['owed']), 'note' => $m['contributions'] . ' unpaid · ' . $m['days_late'] . ' days'], $top
        )]];
    }

    /** One member by name: who they are in the group, and (as far as the person's rights go) what they hold, owe and borrowed. */
    public static function member(array $args, User $user): array
    {
        $name = AssistantTools::text($args['name'] ?? '', 60);
        if ($name === '') {
            return ['data' => ['error' => 'Give a member name or number.'], 'card' => null];
        }
        $like = '%' . AssistantTools::like($name) . '%';
        $found = DB::table('group_members')->where(fn ($q) => $q->where('full_name', 'like', $like)->orWhere('member_number', 'like', $like))
            ->orderBy('full_name')->limit(5)->get(['id', 'full_name', 'member_number', 'status', 'office', 'joined_on']);
        if ($found->isEmpty()) {
            return ['data' => ['error' => 'No member with that name.'], 'card' => null];
        }
        $money = GroupAccess::can($user, 'view_finance');
        $owing = $money || GroupAccess::can($user, 'manage_contributions');
        $loans = GroupAccess::can($user, 'view_loans');

        $data = $found->map(function ($m) use ($money, $owing, $loans) {
            $row = ['name' => $m->full_name, 'number' => $m->member_number, 'status' => $m->status, 'office' => $m->office, 'joined_on' => $m->joined_on];
            if ($money) {
                $row['balances'] = GroupLedger::balances((int) $m->id);
            }
            if ($owing) {
                $o = GroupStatement::owing((int) $m->id);
                $row['owes_contributions'] = round(array_sum(array_column($o, 'remaining')), 2);
                $row['unpaid_contributions'] = count($o);
            }
            if ($loans) {
                $row['loans'] = GroupLoans::query()->where('l.member_id', $m->id)->whereIn('l.status', ['active', 'approved', 'recommended', 'under_review', 'awaiting_guarantors'])->get()
                    ->map(fn ($l) => self::loanRow($l))->all();
            }

            return $row;
        })->all();

        return ['data' => ['currency' => 'TSh', 'members' => $data], 'card' => ['type' => 'rows', 'title' => 'Members', 'rows' => array_map(fn ($m) => [
            'title' => $m['name'] . ($m['number'] ? ' (' . $m['number'] . ')' : ''),
            'value' => isset($m['balances']) ? AssistantTools::tsh($m['balances']['savings'] ?? 0) : (string) $m['status'],
            'note' => isset($m['owes_contributions']) ? 'owes ' . AssistantTools::tsh($m['owes_contributions']) : (string) ($m['office'] ?? ''),
        ], $data)]];
    }

    /** Loans: running ones by default (what is left and what is late), or those at a given step. */
    public static function loans(array $args): array
    {
        $status = in_array($args['status'] ?? '', ['active', 'awaiting_guarantors', 'under_review', 'recommended', 'approved', 'rejected', 'cancelled'], true) ? $args['status'] : 'active';
        $rows = GroupLoans::query()->where('l.status', $status)->orderByDesc('l.id')->limit(60)->get()->map(fn ($l) => self::loanRow($l));
        if ($status === 'active') {
            $rows = $rows->filter(fn ($l) => ($l['outstanding'] ?? 0) > 0);
            if (!empty($args['late_only'])) {
                $rows = $rows->filter(fn ($l) => ($l['late'] ?? 0) > 0);
            }
            $rows = $rows->sortByDesc(fn ($l) => [$l['late'], $l['outstanding']]);
        }
        $rows = $rows->values();
        $top = $rows->take(AssistantTools::limit($args))->all();

        return ['data' => [
            'currency' => 'TSh', 'status' => $status, 'count' => $rows->count(),
            'outstanding_total' => round($rows->sum(fn ($l) => $l['outstanding'] ?? 0), 2), 'late_total' => round($rows->sum(fn ($l) => $l['late'] ?? 0), 2), 'loans' => $top,
        ], 'card' => $top === [] ? null : ['type' => 'rows', 'title' => 'Loans', 'rows' => array_map(fn ($l) => [
            'title' => $l['borrower'], 'value' => AssistantTools::tsh($l['outstanding'] ?? $l['amount']),
            'note' => ($l['late'] ?? 0) > 0 ? 'late ' . AssistantTools::tsh($l['late']) : ($l['next_due'] ?? $l['status']),
        ], $top)]];
    }

    /** Recent money in and out: verified by default, or the payments still waiting to be checked; totals by kind. */
    public static function payments(array $args): array
    {
        $days = max(1, min(92, (int) ($args['days'] ?? 30)));
        $status = ($args['status'] ?? '') === 'pending' ? GroupLedger::PENDING : GroupLedger::VERIFIED;
        $from = now()->subDays($days - 1)->toDateString();
        $q = DB::table('group_transactions as t')->leftJoin('group_members as m', 'm.id', '=', 't.member_id')->where('t.status', $status)->whereNull('t.reversed_by_id')
            ->when($status === GroupLedger::VERIFIED, fn ($q) => $q->where('t.paid_on', '>=', $from));
        $category = AssistantTools::text($args['category'] ?? '', 30);
        if ($category !== '') {
            $q->where('t.category', $category);
        }
        $byKind = (clone $q)->selectRaw("t.category, SUM(CASE WHEN t.direction = 'in' THEN t.amount ELSE 0 END) as money_in, SUM(CASE WHEN t.direction = 'out' THEN t.amount ELSE 0 END) as money_out, COUNT(*) as n")
            ->groupBy('t.category')->get()->map(fn ($r) => ['kind' => $r->category, 'in' => round((float) $r->money_in, 2), 'out' => round((float) $r->money_out, 2), 'count' => (int) $r->n])->values()->all();
        $list = $q->orderByDesc('t.paid_on')->orderByDesc('t.id')->limit(AssistantTools::limit($args))
            ->get(['t.paid_on', 't.category', 't.direction', 't.amount', 't.method', 't.payee', 'm.full_name'])
            ->map(fn ($t) => ['date' => (string) $t->paid_on, 'who' => $t->full_name ?? $t->payee, 'kind' => $t->category, 'direction' => $t->direction, 'amount' => round((float) $t->amount, 2), 'method' => $t->method])->all();

        return ['data' => ['currency' => 'TSh', 'status' => $status, 'days' => $status === GroupLedger::VERIFIED ? $days : null, 'by_kind' => $byKind, 'latest' => $list], 'card' => $list === [] ? null : ['type' => 'rows', 'title' => $status === GroupLedger::PENDING ? 'Waiting to be checked' : 'Payments', 'rows' => array_map(fn ($t) => [
            'title' => (string) ($t['who'] ?? $t['kind']), 'value' => ($t['direction'] === 'out' ? '-' : '+') . AssistantTools::tsh($t['amount']), 'note' => $t['kind'] . ' · ' . $t['date'],
        ], $list)]];
    }

    /** The signed-in person's own membership: what they hold, what they owe and by when, their loans and payments still waiting. */
    public static function myAccount(User $user): array
    {
        $me = GroupAccess::member($user);
        if ($me === null) {
            return ['data' => ['error' => 'This person is not a member of the group.'], 'card' => null];
        }
        $id = (int) $me['id'];
        $balances = GroupLedger::balances($id);
        $owing = GroupStatement::owing($id);
        $loans = GroupLoans::query()->where('l.member_id', $id)->whereNotIn('l.status', ['rejected', 'cancelled'])->get()->map(fn ($l) => self::loanRow($l))->all();
        $owed = round(array_sum(array_column($owing, 'remaining')), 2);
        $data = [
            'currency' => 'TSh', 'name' => $me['full_name'], 'number' => $me['member_number'], 'status' => $me['status'], 'office' => $me['office'],
            'balances' => $balances, 'owes_contributions' => $owed,
            'unpaid' => array_map(fn ($o) => ['what' => $o['label'] ?? $o['type_name'], 'left' => $o['remaining'], 'due_date' => $o['due_date'], 'state' => $o['state']], $owing),
            'loans' => $loans,
            'payments_waiting' => DB::table('group_transactions')->where('member_id', $id)->where('status', GroupLedger::PENDING)->count(),
        ];

        return ['data' => $data, 'card' => ['type' => 'rows', 'title' => $me['full_name'], 'rows' => [
            ['title' => 'Savings', 'value' => AssistantTools::tsh($balances['savings'] ?? 0)],
            ['title' => 'Shares', 'value' => AssistantTools::tsh($balances['shares'] ?? 0)],
            ['title' => 'Contributions owed', 'value' => AssistantTools::tsh($owed), 'note' => count($owing) . ' unpaid'],
        ]]];
    }

    /** @return array<string, mixed> */
    private static function loanRow(object $l): array
    {
        $row = [
            'borrower' => $l->member_name, 'reference' => $l->reference, 'status' => $l->status,
            'amount' => round((float) ($l->amount_approved ?? $l->amount_requested), 2), 'months' => (int) $l->term_months, 'purpose' => mb_substr((string) $l->purpose, 0, 80),
        ];
        if ($l->status === 'active') {
            $p = GroupLoans::position($l);
            $row += ['outstanding' => $p['outstanding'], 'late' => $p['arrears'], 'next_due' => $p['next'] === null ? null : $p['next']['due_date'] . ' ' . AssistantTools::tsh($p['next']['amount'])];
        }

        return $row;
    }
}
