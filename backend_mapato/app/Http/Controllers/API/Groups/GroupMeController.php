<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupContributions;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupMembers;
use App\Support\Groups\GroupOffices;
use App\Support\Groups\GroupPromises;
use App\Support\Groups\GroupSettings;
use App\Support\Groups\GroupStatement;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;

/**
 * What the signed-in person sees of their group: who they are in it (owner, leader, member), what they may do, the group's fees and how
 * to pay, their own file and money, and -- for leaders -- how much waits for them. A member only ever reads their own records here.
 */
class GroupMeController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $user = $request->user();
        GroupAccess::forget();
        $member = GroupAccess::member($user);
        $rights = GroupAccess::rights($user);
        $settings = GroupSettings::all();

        // What waits for THIS person: never their own request, payment or loan, which they may not decide.
        $mid = $member === null ? null : (int) $member['id'];
        $uid = (string) $user->id;
        $notMine = fn ($q, string $column) => $mid === null ? $q : $q->where(fn ($w) => $w->whereNull($column)->orWhere($column, '!=', $mid));

        $waiting = [];
        if (in_array('verify_payments', $rights, true)) {
            $waiting['payments_to_verify'] = $notMine(DB::table('group_transactions')->where('status', GroupLedger::PENDING)
                ->where(fn ($w) => $w->whereNull('submitted_by')->orWhere('submitted_by', '!=', $uid)), 'member_id')->count();
        }
        if (in_array('approve_members', $rights, true)) {
            $waiting['applications'] = DB::table('group_members')->where('status', GroupMembers::SUBMITTED)->count();
        }
        if (in_array('view_finance', $rights, true)) {
            $waiting['members_overdue'] = GroupContributions::owing(GroupContributions::query())
                ->where('o.due_date', '<', now()->toDateString())->distinct()->count('o.member_id');
        }

        if (in_array('recommend_loans', $rights, true)) {
            $waiting['loans_to_recommend'] = $notMine(DB::table('group_loans')->where('status', 'under_review'), 'member_id')->count();
        }
        if (in_array('approve_loans', $rights, true)) {
            $waiting['loans_to_approve'] = $notMine(DB::table('group_loans')->where('status', 'recommended'), 'member_id')->count();
        }
        if (in_array('record_payouts', $rights, true)) {
            $waiting['loans_to_disburse'] = $notMine(DB::table('group_loans')->where('status', 'approved'), 'member_id')->count();
        }
        if (in_array('approve_benefits', $rights, true)) {
            $waiting['benefits_to_decide'] = $notMine(DB::table('group_benefit_requests')->where('status', 'submitted'), 'member_id')->count();
        }

        if (in_array('recommend_projects', $rights, true)) {
            $waiting['projects_to_review'] = $notMine(DB::table('group_projects')->where('status', 'proposed'), 'proposed_by_member_id')->count();
        }
        if (in_array('approve_projects', $rights, true)) {
            $waiting['projects_to_approve'] = $notMine(DB::table('group_projects')->where('status', 'proposed'), 'proposed_by_member_id')->count();
        }
        if (in_array('approve_expenses', $rights, true)) {
            $waiting['expenses_to_approve'] = $notMine(DB::table('group_expense_requests')->where('status', 'requested')
                ->where(fn ($w) => $w->whereNull('requested_by')->orWhere('requested_by', '!=', $uid)), 'requested_by_member_id')->count();
        }
        if (in_array('record_payouts', $rights, true)) {
            $waiting['expenses_to_pay'] = $notMine(DB::table('group_expense_requests as e')->where('e.status', 'approved')
                ->where(fn ($w) => $w->whereNull('e.requested_by')->orWhere('e.requested_by', '!=', $uid)), 'e.requested_by_member_id')
                ->whereNotExists(fn ($q) => $q->select(DB::raw(1))->from('group_transactions as t')->whereColumn('t.expense_id', 'e.id')->where('t.direction', 'out')
                    ->whereIn('t.status', ['pending', 'verified'])->whereNull('t.reversed_by_id')->whereNull('t.reverses_id'))->count();
        }
        if (in_array('approve_dividends', $rights, true)) {
            $waiting['dividends_to_approve'] = DB::table('group_dividend_runs')->where('status', 'draft')->count();
        }
        if (in_array('approve_minutes', $rights, true)) {
            $waiting['minutes_to_approve'] = DB::table('group_meetings')->where('status', 'held')->whereNull('minutes_approved_at')->count();
        }
        if (in_array('record_meetings', $rights, true)) {
            $overdue = DB::table('group_meeting_items as i')->join('group_meetings as g', 'g.id', '=', 'i.meeting_id')->where('i.kind', 'action')->where('i.status', 'open')
                ->whereNotNull('g.minutes_approved_at')->whereNotNull('i.due_date')->where('i.due_date', '<', now()->toDateString())->count();
            if ($overdue > 0) {
                $waiting['actions_overdue'] = $overdue;
            }
        }
        if (GroupAccess::member($user) !== null) {
            $mine = DB::table('group_meeting_items as i')->join('group_meetings as g', 'g.id', '=', 'i.meeting_id')->where('i.kind', 'action')->where('i.status', 'open')
                ->whereNotNull('g.minutes_approved_at')->where('i.assignee_member_id', (int) GroupAccess::member($user)['id'])->count();
            if ($mine > 0) {
                $waiting['my_actions'] = $mine;
            }
        }
        if (in_array('record_meetings', $rights, true)) {
            $waiting['meetings_to_record'] = DB::table('group_meetings')->where('status', 'scheduled')->where('starts_at', '<', now())->count();
        }
        if (in_array('decide_hire_charges', $rights, true)) {
            $waiting['hire_charges'] = DB::table('group_hires')->where('status', 'returned')->where('damage_status', 'pending')->count();
        }

        $memberId = $member === null ? null : (int) $member['id'];
        // Open votings this member may vote in and has not voted in yet.
        if ($memberId !== null) {
            $toVote = DB::table('group_votings as v')->join('group_voting_eligible as e', function ($j) use ($memberId) {
                $j->on('e.voting_id', '=', 'v.id')->where('e.member_id', '=', $memberId);
            })->where('v.status', 'open')->where('v.closes_at', '>', now())
                ->whereNotExists(fn ($q) => $q->select(DB::raw(1))->from('group_voting_turnout as t')->whereColumn('t.voting_id', 'v.id')->where('t.member_id', $memberId))->count();
            if ($toVote > 0) {
                $waiting['votes_to_cast'] = $toVote;
            }
        }
        // Hires waiting for the keeper of an asset (or whoever manages assets): to confirm, or out past their day.
        $kept = in_array('manage_assets', $rights, true) ? null : ($memberId === null ? [] : DB::table('group_assets')->where('custodian_id', $memberId)->pluck('id')->all());
        if ($kept === null || $kept !== []) {
            $hires = DB::table('group_hires')->when($kept !== null, fn ($q) => $q->whereIn('asset_id', $kept));
            $toDecide = (clone $hires)->where('status', 'requested')->count();
            $late = (clone $hires)->where('status', 'issued')->where('end_date', '<', now()->toDateString())->count();
            if ($toDecide > 0 || $kept === null) {
                $waiting['hires_to_decide'] = $toDecide;
            }
            if ($late > 0) {
                $waiting['hires_overdue'] = $late;
            }
        }
        $isKeeper = $kept === null || $kept !== [];
        // Anyone asked to guarantee a loan sees it, whatever their office.
        if ($memberId !== null) {
            $asked = DB::table('group_loan_guarantors as g')->join('group_loans as l', 'l.id', '=', 'g.loan_id')
                ->where('g.member_id', $memberId)->where('g.status', 'pending')->where('l.status', 'awaiting_guarantors')->count();
            if ($asked > 0) {
                $waiting['guarantees'] = $asked;
            }
        }

        return response()->json(['success' => true, 'data' => [
            'is_owner' => GroupAccess::isOwner($user),
            'rights' => $rights,
            'offices' => GroupOffices::OFFICES,
            'member' => $member === null ? null : GroupMembers::payload($member, true),
            'balances' => $memberId === null ? null : GroupLedger::balances($memberId),
            'pending' => $memberId === null ? 0 : DB::table('group_transactions')->where('member_id', $memberId)->where('status', GroupLedger::PENDING)->count(),
            // What they still owe (contributions), oldest first, and the promises they made.
            'owing' => $memberId === null ? [] : GroupStatement::owing($memberId),
            'promises' => $memberId === null ? [] : GroupPromises::query()->where('p.member_id', $memberId)->where('p.status', 'open')->orderBy('p.promised_on')->get()
                ->map(fn ($p) => GroupPromises::payload($p))->values()->all(),
            'settings' => [
                'joining_fee' => (float) $settings['joining_fee'],
                'share_amount' => (float) $settings['share_amount'],
                'shares_required_for' => $settings['shares_required_for'],
                'payment_instructions' => $settings['payment_instructions'],
            ],
            // Where to pay, for each method the group authorises (empty until the group has chosen: then every method is accepted).
            'payment_methods' => \App\Support\Groups\GroupPaymentMethods::payload(),
            'waiting' => $waiting,
            // Keeps (or manages) assets: the hires section is theirs.
            'keeps_assets' => $isKeeper,
            // The next meeting and the newest notice, for everyone's home.
            'next_meeting' => DB::table('group_meetings')->where('status', 'scheduled')->where('starts_at', '>=', now())->orderBy('starts_at')
                ->first(['id', 'title', 'starts_at', 'venue']),
            'notices' => DB::table('group_announcements')
                ->when(!($member !== null && !empty($member['office'])) && !GroupAccess::isOwner($user), fn ($q) => $q->where('audience', 'all'))
                ->where(fn ($q) => $q->whereNull('expires_on')->orWhere('expires_on', '>=', now()->toDateString()))->count(),
            'group' => ['name' => optional(\App\Models\Business::forUser($user))->name],
        ]]);
    }

    /** The member's own payments, newest first. */
    public function transactions(Request $request): JsonResponse
    {
        $member = GroupAccess::member($request->user());
        if ($member === null) {
            return response()->json(['success' => true, 'data' => ['transactions' => []]]);
        }
        $rows = GroupLedger::listQuery()->where('t.member_id', (int) $member['id'])->orderByDesc('t.id')->limit(200)->get();

        return response()->json(['success' => true, 'data' => ['transactions' => $rows->map(fn ($r) => GroupLedger::payload($r))->values()]]);
    }

    /** The member says they paid (joining fee or shares), with how and its reference. It waits for the treasurer's verification. */
    public function pay(Request $request): JsonResponse
    {
        $member = GroupAccess::member($request->user());
        if ($member === null || !in_array($member['status'], [GroupMembers::SUBMITTED, GroupMembers::ACTIVE, GroupMembers::SUSPENDED], true)) {
            return response()->json(['success' => false, 'code' => 'member_not_open', 'message' => 'Huna uanachama unaoweza kupokea malipo. / You have no membership that can take payments.'], 422);
        }
        $data = $request->validate(GroupTransactionController::paymentRules());

        return GroupTransactionController::submitFor($request, (object) $member, $data);
    }
}
