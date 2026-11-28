<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupContributions;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupLoans;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Previous data: what a member held and owed BEFORE the group used the app, entered by any leader (the Mwenyekiti, the treasurer, ...).
 *
 *   - Totals (savings, shares, joining fee, and each kind of contribution: JAMII, a refundable project contribution, a welfare fund, ...)
 *     as of a date. They count at once (no second check, as the group chose) and fill the member's balances and statement, but they are
 *     records, NOT cash: the group's real cash then is its opening balance, entered once. They are never reversed; a mistake is removed.
 *   - A loan that was already running: what is still owed, the instalment and the next due date. It starts from what is left (no cash out
 *     here), and its repayments are then recorded under Payments like any loan.
 *
 * A leader never enters their own previous data (another leader does), like a payment is never verified by its own payer.
 */
class GroupPreviousController extends Controller
{
    private function fail(string $code, string $message, int $status = 422): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => $message], $status);
    }

    /** null when the caller may enter previous data for [member]; otherwise the refusal. */
    private function refuse(Request $request, ?object $member): ?JsonResponse
    {
        $user = $request->user();
        if (!GroupAccess::holdsOffice($user)) {
            return $this->fail('leaders_only', 'Ni viongozi tu wanaoweza kuingiza taarifa za awali. / Only leaders can enter previous data.', 403);
        }
        if ($member === null) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }
        $me = GroupAccess::member($user);
        if ($me !== null && (int) $me['id'] === (int) $member->id) {
            return $this->fail('own_record', 'Kiongozi mwingine aingize taarifa zako za awali. / Another leader enters your own previous data.', 403);
        }

        return null;
    }

    /** What was entered for [id] so far, and the kinds of contribution to choose from. */
    public function index(Request $request, int $id): JsonResponse
    {
        $member = DB::table('group_members')->where('id', $id)->first(['id', 'full_name', 'member_number', 'status', 'joined_on']);
        if (!GroupAccess::holdsOffice($request->user())) {
            return $this->fail('leaders_only', 'Ni viongozi tu wanaoweza kuona taarifa za awali. / Only leaders can see previous data.', 403);
        }
        if ($member === null) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }

        return response()->json(['success' => true, 'data' => [
            'member' => (array) $member,
            'types' => DB::table('group_contribution_types')->orderBy('name')->get()->map(fn ($t) => GroupContributions::typePayload($t))->values(),
            'entries' => GroupLedger::listQuery()->where('t.member_id', $id)->where('t.brought_forward', true)->orderBy('t.paid_on')->orderBy('t.id')->get()
                ->map(fn ($r) => GroupLedger::payload($r))->values(),
            'loans' => GroupLoans::query()->where('l.member_id', $id)->where('l.brought_forward', true)->orderBy('l.id')->get()
                ->map(fn ($l) => GroupLoans::payload($l) + ['repaid' => GroupLoans::repaid((int) $l->id)])->values(),
            'balances' => GroupLedger::balances($id),
            'refundable' => GroupLedger::refundable($id),
        ]]);
    }

    /** Totals as of a date: savings, shares, joining fee and any kinds of contribution. Each amount becomes one record. */
    public function store(Request $request, int $id): JsonResponse
    {
        $member = DB::table('group_members')->where('id', $id)->first();
        if ($refusal = $this->refuse($request, $member)) {
            return $refusal;
        }
        $data = $request->validate([
            'as_of' => 'required|date|before_or_equal:today',
            'savings' => 'nullable|numeric|min:0|max:10000000000',
            'shares' => 'nullable|numeric|min:0|max:10000000000',
            'joining_fee' => 'nullable|numeric|min:0|max:10000000000',
            'contributions' => 'nullable|array|max:30',
            'contributions.*.type_id' => 'required|integer',
            'contributions.*.amount' => 'required|numeric|min:0|max:10000000000',
            'note' => 'nullable|string|max:255',
        ]);
        $rows = [];
        foreach (['savings', 'shares', 'joining_fee'] as $kind) {
            if ((float) ($data[$kind] ?? 0) > 0) {
                $rows[] = ['category' => $kind, 'amount' => (float) $data[$kind], 'type' => null];
            }
        }
        foreach ($data['contributions'] ?? [] as $c) {
            if ((float) $c['amount'] <= 0) {
                continue;
            }
            if (!DB::table('group_contribution_types')->where('id', (int) $c['type_id'])->exists()) {
                return $this->fail('type_not_found', 'Aina ya mchango haipo. / That kind of contribution does not exist.');
            }
            $rows[] = ['category' => 'contribution', 'amount' => (float) $c['amount'], 'type' => (int) $c['type_id']];
        }
        if ($rows === []) {
            return $this->fail('nothing_entered', 'Weka angalau kiasi kimoja. / Enter at least one amount.');
        }

        $by = (string) $request->user()->id;
        $day = Carbon::parse($data['as_of'])->toDateString();
        $ids = DB::transaction(function () use ($rows, $id, $by, $day, $data) {
            $ids = [];
            foreach ($rows as $r) {
                $ids[] = (int) DB::table('group_transactions')->insertGetId([
                    'reference' => 'BF-' . strtoupper(Str::random(8)),
                    'member_id' => $id,
                    'category' => $r['category'],
                    'contribution_type_id' => $r['type'],
                    'direction' => 'in',
                    'amount' => round($r['amount'], 2),
                    'method' => 'other',
                    'paid_on' => $day,
                    'status' => GroupLedger::VERIFIED,
                    'note' => $data['note'] ?? null,
                    'brought_forward' => true,
                    'submitted_by' => $by,
                    'submitted_at' => now(),
                    // dated on the day it stood, so the statement shows it first, before anything paid in the app
                    'verified_by' => $by,
                    'verified_at' => $day . ' 00:00:00',
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            return $ids;
        });
        GroupAudit::record($by, 'previous_entered', 'Previous data for ' . $member->full_name . ' as of ' . $day . ': ' . implode(', ', array_map(
            fn ($r) => ($r['type'] ? 'contribution #' . $r['type'] : $r['category']) . ' ' . number_format($r['amount']), $rows
        )), 'member', $id);

        return response()->json(['success' => true, 'data' => ['created' => count($ids)]], 201);
    }

    /** A loan that was already running before the app: it starts from what is still owed, paid back by the instalment from the next due date. */
    public function loan(Request $request, int $id): JsonResponse
    {
        $member = DB::table('group_members')->where('id', $id)->first();
        if ($refusal = $this->refuse($request, $member)) {
            return $refusal;
        }
        $data = $request->validate([
            'amount' => 'required|numeric|min:1|max:10000000000',
            'remaining' => 'required|numeric|min:1|max:10000000000',
            'instalment' => 'required|numeric|min:1|max:10000000000',
            'next_due' => 'required|date',
            'issued_on' => 'nullable|date|before_or_equal:today',
            'purpose' => 'nullable|string|max:255',
        ]);
        $remaining = round((float) $data['remaining'], 2);
        $instalment = min(round((float) $data['instalment'], 2), $remaining);
        $count = (int) ceil($remaining / $instalment);
        if ($count > GroupLoans::MAX_INSTALMENTS) {
            return $this->fail('too_many_instalments', 'Kiasi cha kila mwezi ni kidogo mno kwa deni hili. / The instalment is too small for what is owed.');
        }

        $by = (string) $request->user()->id;
        $loanId = DB::transaction(function () use ($data, $id, $by, $remaining, $instalment, $count) {
            $loanId = (int) DB::table('group_loans')->insertGetId([
                'reference' => GroupLoans::newReference(),
                'member_id' => $id,
                'amount_requested' => round((float) $data['amount'], 2),
                'amount_approved' => round((float) $data['amount'], 2),
                'purpose' => trim((string) ($data['purpose'] ?? '')) ?: 'Mkopo wa awali / Previous loan',
                'term_months' => $count,
                'interest_rate' => 0,
                'interest_method' => 'flat',
                'repayment_every' => 'monthly',
                'status' => 'active',
                'brought_forward' => true,
                'approved_by' => $by,
                'approved_at' => now(),
                'disbursed_on' => $data['issued_on'] ?? null,
                'created_by' => $by,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            // What is left, in equal instalments a month apart from the next due date (the last one takes the rest); interest is in the figure.
            $first = Carbon::parse($data['next_due']);
            $left = $remaining;
            for ($n = 1; $n <= $count; $n++) {
                $part = $n === $count ? round($left, 2) : $instalment;
                $left = round($left - $part, 2);
                DB::table('group_loan_schedule')->insert([
                    'loan_id' => $loanId, 'number' => $n, 'due_date' => $first->copy()->addMonthsNoOverflow($n - 1)->toDateString(),
                    'principal_due' => $part, 'interest_due' => 0,
                ]);
            }

            return $loanId;
        });
        GroupAudit::record($by, 'previous_loan_entered', 'Previous loan for ' . $member->full_name . ': ' . number_format($remaining) . ' left of ' . number_format((float) $data['amount']), 'loan', $loanId);

        return response()->json(['success' => true, 'data' => ['loan' => GroupLoans::payload(GroupLoans::query()->where('l.id', $loanId)->first())]], 201);
    }

    /** Remove a previous total entered by mistake (only previous data: a payment made in the app is reversed, never removed). */
    public function removeEntry(Request $request, int $txId): JsonResponse
    {
        $tx = DB::table('group_transactions')->where('id', $txId)->where('brought_forward', true)->first();
        if ($tx === null) {
            return $this->fail('not_found', 'Taarifa hiyo haipo. / That entry does not exist.', 404);
        }
        $member = DB::table('group_members')->where('id', $tx->member_id)->first();
        if ($refusal = $this->refuse($request, $member)) {
            return $refusal;
        }
        DB::table('group_transactions')->where('id', $txId)->delete();
        GroupAudit::record((string) $request->user()->id, 'previous_removed', 'Removed previous ' . $tx->category . ' ' . number_format((float) $tx->amount) . ' of ' . $member->full_name, 'member', (int) $member->id);

        return response()->json(['success' => true]);
    }

    /** Remove a previous loan entered by mistake, while nothing has been repaid on it here. */
    public function removeLoan(Request $request, int $loanId): JsonResponse
    {
        $loan = DB::table('group_loans')->where('id', $loanId)->where('brought_forward', true)->first();
        if ($loan === null) {
            return $this->fail('not_found', 'Mkopo huo haupo. / That loan does not exist.', 404);
        }
        $member = DB::table('group_members')->where('id', $loan->member_id)->first();
        if ($refusal = $this->refuse($request, $member)) {
            return $refusal;
        }
        if (DB::table('group_transactions')->where('loan_id', $loanId)->whereIn('status', [GroupLedger::PENDING, GroupLedger::VERIFIED])->exists()) {
            return $this->fail('loan_has_repayments', 'Mkopo huu una marejesho tayari; hauwezi kuondolewa. / This loan has repayments already; it cannot be removed.', 409);
        }
        DB::transaction(function () use ($loanId) {
            DB::table('group_loan_schedule')->where('loan_id', $loanId)->delete();
            DB::table('group_loans')->where('id', $loanId)->delete();
        });
        GroupAudit::record((string) $request->user()->id, 'previous_loan_removed', 'Removed previous loan ' . $loan->reference . ' of ' . $member->full_name, 'member', (int) $member->id);

        return response()->json(['success' => true]);
    }
}
