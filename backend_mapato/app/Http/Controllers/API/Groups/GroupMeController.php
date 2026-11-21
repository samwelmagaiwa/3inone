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
 * What the signed-in person sees of their group: who they are in it (owner, officer, member), what they may do, the group's fees and how
 * to pay, their own file and money, and -- for officers -- how much waits for them. A member only ever reads their own records here.
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

        $waiting = [];
        if (in_array('verify_payments', $rights, true)) {
            $waiting['payments_to_verify'] = DB::table('group_transactions')->where('status', GroupLedger::PENDING)->count();
        }
        if (in_array('approve_members', $rights, true)) {
            $waiting['applications'] = DB::table('group_members')->where('status', GroupMembers::SUBMITTED)->count();
        }
        if (in_array('view_finance', $rights, true)) {
            $waiting['members_overdue'] = GroupContributions::owing(GroupContributions::query())
                ->where('o.due_date', '<', now()->toDateString())->distinct()->count('o.member_id');
        }

        $memberId = $member === null ? null : (int) $member['id'];

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
            'waiting' => $waiting,
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
