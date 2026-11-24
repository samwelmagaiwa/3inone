<?php

namespace App\Http\Controllers\API\Groups;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupHires;
use App\Support\Groups\GroupMembers;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;

/**
 * What someone OUTSIDE the group can do with a code they were given: see the group's name (and who invited them), apply to join, and ask to
 * hire what the group hires out. Nothing else of the group is shown: no members, no money. The code finds its group; everything written is
 * written as that group. The routes are rate-limited; an application still waits for its joining payments and the chair's approval, and a
 * hire for the keeper's confirmation and the payment.
 */
class GroupPublicController extends Controller
{
    /** The live invitation for [code], with its group's head, or null. */
    private function invitation(string $code): ?array
    {
        $code = strtoupper(trim($code));
        if (preg_match('/^[A-Z0-9]{6,12}$/', $code) !== 1) {
            return null;
        }
        $inv = TenantContext::withoutScope(fn () => DB::table('group_invitations')->where('code', $code)->where('active', true)->first());
        if ($inv === null) {
            return null;
        }
        $head = User::query()->withoutGlobalScopes()->find($inv->owner_id);
        if ($head === null || !$head->is_active || !$head->canUseService('groups')) {
            return null;
        }
        $business = Business::forUser($head);
        if ($business !== null && method_exists($business, 'blocksAccess') && $business->blocksAccess()) {
            return null;
        }

        return ['inv' => $inv, 'head' => $head, 'group' => $business?->name ?? $head->name];
    }

    private function unknown(): JsonResponse
    {
        return response()->json(['success' => false, 'code' => 'unknown_code', 'message' => 'Namba hii ya mwaliko haipo au imesitishwa. / This invitation code does not exist or was stopped.'], 404);
    }

    /** The group's name, who invited, and what can be hired. */
    public function show(string $code): JsonResponse
    {
        $found = $this->invitation($code);
        if ($found === null) {
            return $this->unknown();
        }

        return TenantContext::runAs($found['head'], function () use ($found) {
            $inviter = $found['inv']->member_id === null ? null : DB::table('group_members')->where('id', $found['inv']->member_id)->where('status', GroupMembers::ACTIVE)->value('full_name');
            $today = now()->toDateString();
            $assets = DB::table('group_assets')->where('status', 'active')->where('visible', true)->whereNotNull('hire_rate')->orderBy('name')->get()
                ->map(fn ($a) => ['id' => (int) $a->id, 'name' => $a->name, 'description' => $a->description, 'hire_rate' => (float) $a->hire_rate, 'free_today' => GroupHires::available($a, $today, $today)])
                ->values();

            return response()->json(['success' => true, 'data' => [
                'group' => $found['group'],
                // Only the first name of whoever invited: enough to recognise, nothing more.
                'invited_by' => $inviter === null ? null : trim(explode(' ', trim((string) $inviter))[0]),
                'assets' => $assets,
            ]]);
        });
    }

    public function availability(Request $request, string $code, int $assetId): JsonResponse
    {
        $data = $request->validate(['from' => 'required|date|after_or_equal:today', 'to' => 'required|date|after_or_equal:from']);
        $found = $this->invitation($code);
        if ($found === null) {
            return $this->unknown();
        }

        return TenantContext::runAs($found['head'], function () use ($data, $assetId) {
            $a = DB::table('group_assets')->where('id', $assetId)->where('status', 'active')->where('visible', true)->whereNotNull('hire_rate')->first();
            if ($a === null) {
                return response()->json(['success' => false, 'message' => 'Haipo. / Not found.'], 404);
            }

            return response()->json(['success' => true, 'data' => [
                'free' => GroupHires::available($a, $data['from'], $data['to']), 'days' => GroupHires::days($data['from'], $data['to']), 'rate' => (float) $a->hire_rate,
            ]]);
        });
    }

    /** Apply to join. The application waits for its payments and approval like any other; a member's code names them as the referrer. */
    public function apply(Request $request, string $code): JsonResponse
    {
        $found = $this->invitation($code);
        if ($found === null) {
            return $this->unknown();
        }
        $members = new GroupMemberController();
        $rules = $members->detailRules(true);
        unset($rules['referrer_id'], $rules['notes']);
        $data = $request->validate($rules + ['consent' => 'required|accepted']);

        return TenantContext::runAs($found['head'], function () use ($found, $members, $data) {
            $inv = $found['inv'];
            $referrer = $inv->member_id !== null && DB::table('group_members')->where('id', $inv->member_id)->where('status', GroupMembers::ACTIVE)->exists()
                ? (int) $inv->member_id : null;
            $data['referrer_id'] = $referrer;
            if ($problem = $members->checkDetails($data, null)) {
                return $problem;
            }
            $id = DB::transaction(function () use ($members, $data, $inv) {
                $id = (int) DB::table('group_members')->insertGetId($members->columns($data) + [
                    'application_ref' => GroupMembers::newApplicationRef(),
                    'status' => GroupMembers::SUBMITTED,
                    'source' => $inv->kind === 'member' ? 'invitation' : 'group_code',
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
                GroupMembers::event($id, 'status', null, GroupMembers::SUBMITTED, 'applied with code ' . $inv->code, null);
                DB::table('group_invitations')->where('id', $inv->id)->increment('used');

                return $id;
            });
            GroupAudit::record(null, 'member_applied', 'Application of ' . $data['full_name'] . ' with code ' . $inv->code, 'member', $id);
            // The management is told a request waits (it came from the person themselves, with a member's code or the group's).
            $by = $referrer !== null ? (string) DB::table('group_members')->where('id', $referrer)->value('full_name') : 'mwombaji mwenyewe / the applicant';
            \App\Support\Groups\GroupApprovals::requested($id, (string) $data['full_name'], $by, $referrer);
            $row = DB::table('group_members')->where('id', $id)->first(['application_ref']);

            return response()->json(['success' => true, 'data' => ['application_ref' => $row->application_ref, 'group' => $found['group']]], 201);
        });
    }

    /** Ask to hire, from outside the group: the keeper confirms, then it is paid before anything is handed over. */
    public function hire(Request $request, string $code): JsonResponse
    {
        $data = $request->validate([
            'asset_id' => 'required|integer',
            'quantity' => 'required|integer|min:1|max:100000',
            'start_date' => 'required|date|after_or_equal:today',
            'end_date' => 'required|date|after_or_equal:start_date',
            'purpose' => 'nullable|string|max:255',
            'name' => 'required|string|min:2|max:150',
            'phone' => ['required', 'string', 'regex:/^(0\d{9}|\+\d{9,15})$/'],
        ]);
        $found = $this->invitation($code);
        if ($found === null) {
            return $this->unknown();
        }

        return TenantContext::runAs($found['head'], function () use ($data, $found) {
            $asset = DB::table('group_assets')->where('id', (int) $data['asset_id'])->where('status', 'active')->where('visible', true)->whereNotNull('hire_rate')->first();
            if ($asset === null) {
                return response()->json(['success' => false, 'code' => 'not_for_hire', 'message' => 'Haikodishwi. / Not for hire.'], 422);
            }
            $free = GroupHires::available($asset, $data['start_date'], $data['end_date']);
            if ((int) $data['quantity'] > $free) {
                return response()->json(['success' => false, 'code' => 'not_enough', 'message' => "Zipo {$free} tu kwa siku hizo. / Only {$free} are free on those days.", 'free' => $free], 422);
            }
            $days = GroupHires::days($data['start_date'], $data['end_date']);
            $id = (int) DB::table('group_hires')->insertGetId([
                'reference' => GroupHires::newReference(),
                'asset_id' => (int) $asset->id,
                'customer_name' => trim($data['name']),
                'customer_phone' => str_replace(' ', '', $data['phone']),
                'purpose' => $data['purpose'] ?? null,
                'quantity' => (int) $data['quantity'],
                'start_date' => $data['start_date'],
                'end_date' => $data['end_date'],
                'days' => $days,
                'rate' => (float) $asset->hire_rate,
                'amount' => round((int) $data['quantity'] * (float) $asset->hire_rate * $days, 2),
                'status' => 'requested',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            GroupAudit::record(null, 'hire_requested', 'From outside: ' . $data['quantity'] . ' x ' . $asset->name . ' for ' . trim($data['name']), 'hire', $id);
            $hire = DB::table('group_hires')->where('id', $id)->first();

            return response()->json(['success' => true, 'data' => [
                'reference' => $hire->reference, 'amount' => (float) $hire->amount, 'days' => $days, 'group' => $found['group'],
            ]], 201);
        });
    }
}
