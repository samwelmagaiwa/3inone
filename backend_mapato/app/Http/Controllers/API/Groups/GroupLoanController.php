<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupLoans;
use App\Support\Groups\GroupMembers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use InvalidArgumentException;

/**
 * Loans, step by step, each step by the person whose job it is and never by the borrower:
 *
 *   the member applies (or an officer for them)  ->  each guarantor accepts or declines  ->  the projects committee recommends an amount
 *   ->  the chair approves (or anyone of them turns it down with the reason)  ->  the treasurer pays it out  ->  someone else verifies the
 *   payout, and the loan runs with its instalments  ->  repayments, each verified, until nothing is left.
 */
class GroupLoanController extends Controller
{
    private const PAGE = 50;

    private const WORDS = [
        'not_found' => 'Mkopo haupo. / Loan not found.',
        'not_eligible' => 'Hustahili mkopo kwa sasa. / Not eligible for a loan now.',
        'over_ceiling' => 'Kiasi ni zaidi ya kikomo cha mkopo. / The amount is over the loan ceiling.',
        'term_too_long' => 'Muda ni mrefu kuliko kikundi kinavyoruhusu. / The term is longer than the group allows.',
        'open_application' => 'Tayari kuna ombi la mkopo linaloendelea. / A loan application is already in progress.',
        'guarantors_needed' => 'Chagua wadhamini wanaohitajika. / Choose the guarantors needed.',
        'bad_guarantor' => 'Mdhamini lazima awe mwanachama hai, si mkopaji mwenyewe. / A guarantor must be an active member, not the borrower.',
        'own_loan' => 'Huwezi kuamua mkopo wako mwenyewe. / You cannot decide your own loan.',
        'wrong_status' => 'Hatua hii haiwezekani kwa hali ya sasa ya mkopo. / This step is not possible at the loan\'s stage.',
        'reason_required' => 'Andika sababu. / Write the reason.',
        'not_yours' => 'Huu si ombi lako. / This is not yours.',
    ];

    private function fail(string $code, int $status = 422, array $extra = []): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => self::WORDS[$code] ?? $code] + $extra, $status);
    }

    private function loan(int $id): ?object
    {
        return GroupLoans::query()->where('l.id', $id)->first();
    }

    private function myId(Request $request): ?int
    {
        $me = GroupAccess::member($request->user());

        return $me === null ? null : (int) $me['id'];
    }

    private function show(int $id, int $status = 200): JsonResponse
    {
        return response()->json(['success' => true, 'data' => ['loan' => GroupLoans::payload($this->loan($id), true)]], $status);
    }

    // ---------------------------------------------------------------- the member's side

    public function myEligibility(Request $request): JsonResponse
    {
        $id = $this->myId($request);

        return response()->json(['success' => true, 'data' => $id === null ? null : GroupLoans::eligibility($id)]);
    }

    /** The member's loans, and the guarantees others asked of them. */
    public function mine(Request $request): JsonResponse
    {
        $id = $this->myId($request);
        if ($id === null) {
            return response()->json(['success' => true, 'data' => ['loans' => [], 'guarantees' => []]]);
        }
        $loans = GroupLoans::query()->where('l.member_id', $id)->orderByDesc('l.id')->get()->map(fn ($l) => GroupLoans::payload($l, true))->values();
        $guarantees = DB::table('group_loan_guarantors as g')->join('group_loans as l', 'l.id', '=', 'g.loan_id')->join('group_members as m', 'm.id', '=', 'l.member_id')
            ->where('g.member_id', $id)->orderByDesc('g.id')->limit(50)
            ->get(['g.id', 'g.status', 'g.note', 'l.id as loan_id', 'l.reference', 'l.amount_requested', 'l.purpose', 'l.term_months', 'l.status as loan_status', 'm.full_name as borrower'])
            ->map(fn ($g) => (array) $g)->values();

        return response()->json(['success' => true, 'data' => ['loans' => $loans, 'guarantees' => $guarantees]]);
    }

    /** @return array<string, mixed> */
    private static function applyRules(): array
    {
        return [
            'amount' => 'required|numeric|min:1000|max:1000000000',
            'purpose' => 'required|string|min:3|max:255',
            'term_months' => 'required|integer|min:1|max:120',
            'guarantor_ids' => 'nullable|array|max:5',
            'guarantor_ids.*' => 'integer|distinct',
        ];
    }

    /** Apply for [memberId] (the member themself, or an officer for them). */
    private function applyFor(Request $request, int $memberId, array $data): JsonResponse
    {
        $eligibility = GroupLoans::eligibility($memberId);
        if (!$eligibility['eligible']) {
            return $this->fail('not_eligible', 422, ['reasons' => $eligibility['reasons'], 'eligibility' => $eligibility]);
        }
        if ((float) $data['amount'] > $eligibility['ceiling'] + 0.001) {
            return $this->fail('over_ceiling', 422, ['eligibility' => $eligibility]);
        }
        if ((int) $data['term_months'] > $eligibility['terms']['max_months']) {
            return $this->fail('term_too_long');
        }
        if (GroupLoans::instalmentCount((int) $data['term_months'], $eligibility['terms']['repayment'], $eligibility['terms']['repayment_days']) > GroupLoans::MAX_INSTALMENTS) {
            return $this->fail('too_many_instalments', 422, ['max' => GroupLoans::MAX_INSTALMENTS]);
        }
        if (DB::table('group_loans')->where('member_id', $memberId)->whereIn('status', GroupLoans::OPEN_STATUSES)->exists()) {
            return $this->fail('open_application', 409);
        }
        $guarantors = array_values(array_unique(array_map('intval', $data['guarantor_ids'] ?? [])));
        if (count($guarantors) < $eligibility['terms']['guarantors']) {
            return $this->fail('guarantors_needed', 422, ['needed' => $eligibility['terms']['guarantors']]);
        }
        $ok = DB::table('group_members')->whereIn('id', $guarantors)->where('status', GroupMembers::ACTIVE)->count();
        if ($ok !== count($guarantors) || in_array($memberId, $guarantors, true)) {
            return $this->fail('bad_guarantor');
        }

        $terms = $eligibility['terms'];
        $id = DB::transaction(function () use ($request, $memberId, $data, $guarantors, $terms, $eligibility) {
            $id = (int) DB::table('group_loans')->insertGetId([
                'reference' => GroupLoans::newReference(),
                'member_id' => $memberId,
                'amount_requested' => round((float) $data['amount'], 2),
                'purpose' => trim($data['purpose']),
                'term_months' => (int) $data['term_months'],
                'interest_rate' => $terms['rate'],
                'interest_method' => $terms['method'],
                'repayment_every' => $terms['repayment'],
                'repayment_days' => $terms['repayment'] === 'custom' ? $terms['repayment_days'] : null,
                'ceiling' => $eligibility['ceiling'],
                'status' => $guarantors === [] ? 'under_review' : 'awaiting_guarantors',
                'created_by' => (string) $request->user()->id,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            foreach ($guarantors as $g) {
                DB::table('group_loan_guarantors')->insert(['loan_id' => $id, 'member_id' => $g, 'status' => 'pending', 'created_at' => now(), 'updated_at' => now()]);
            }

            return $id;
        });
        GroupAudit::record((string) $request->user()->id, 'loan_applied', 'Loan application of ' . number_format((float) $data['amount']) . ' over ' . $data['term_months'] . ' month(s)', 'loan', $id);

        return $this->show($id, 201);
    }

    public function applyMine(Request $request): JsonResponse
    {
        $id = $this->myId($request);
        if ($id === null) {
            return $this->fail('not_eligible', 422, ['reasons' => ['not_active']]);
        }

        return $this->applyFor($request, $id, $request->validate(self::applyRules()));
    }

    public function applyForMember(Request $request): JsonResponse
    {
        $data = $request->validate(self::applyRules() + ['member_id' => 'required|integer']);

        return $this->applyFor($request, (int) $data['member_id'], $data);
    }

    /** A guarantor answers. When every guarantor has accepted, the loan goes to the projects committee. */
    public function respond(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['accept' => 'required|boolean', 'note' => 'nullable|string|max:255']);
        $g = DB::table('group_loan_guarantors')->where('id', $id)->first();
        if ($g === null || (int) $g->member_id !== $this->myId($request)) {
            return $this->fail('not_yours', 403);
        }
        $loan = DB::table('group_loans')->where('id', $g->loan_id)->first();
        if ($loan === null || $loan->status !== 'awaiting_guarantors' || $g->status !== 'pending') {
            return $this->fail('wrong_status', 409);
        }
        DB::transaction(function () use ($g, $data, $loan) {
            DB::table('group_loan_guarantors')->where('id', $g->id)->update([
                'status' => $data['accept'] ? 'accepted' : 'declined', 'note' => $data['note'] ?? null, 'responded_at' => now(), 'updated_at' => now(),
            ]);
            $waiting = DB::table('group_loan_guarantors')->where('loan_id', $loan->id)->where('status', '!=', 'accepted')->exists();
            if (!$waiting) {
                DB::table('group_loans')->where('id', $loan->id)->update(['status' => 'under_review', 'updated_at' => now()]);
            }
        });
        GroupAudit::record((string) $request->user()->id, $data['accept'] ? 'guarantee_accepted' : 'guarantee_declined', 'Guarantee for ' . $loan->reference, 'loan', (int) $loan->id);

        return $this->show((int) $loan->id);
    }

    /** The borrower names another guarantor (in place of one who declined). */
    public function addGuarantor(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['member_id' => 'required|integer']);
        $loan = DB::table('group_loans')->where('id', $id)->first();
        if ($loan === null || (int) $loan->member_id !== $this->myId($request)) {
            return $this->fail('not_yours', 403);
        }
        if ($loan->status !== 'awaiting_guarantors') {
            return $this->fail('wrong_status', 409);
        }
        $g = (int) $data['member_id'];
        if ($g === (int) $loan->member_id || !DB::table('group_members')->where('id', $g)->where('status', GroupMembers::ACTIVE)->exists()) {
            return $this->fail('bad_guarantor');
        }
        DB::table('group_loan_guarantors')->insertOrIgnore(['loan_id' => $id, 'member_id' => $g, 'status' => 'pending', 'created_at' => now(), 'updated_at' => now()]);

        return $this->show($id);
    }

    /** The borrower withdraws an application (any time before it is paid out). */
    public function cancel(Request $request, int $id): JsonResponse
    {
        $loan = DB::table('group_loans')->where('id', $id)->first();
        if ($loan === null || (int) $loan->member_id !== $this->myId($request)) {
            return $this->fail('not_yours', 403);
        }
        if (!in_array($loan->status, GroupLoans::OPEN_STATUSES, true)
            || DB::table('group_transactions')->where('loan_id', $id)->where('category', 'loan_disbursement')->where('status', GroupLedger::PENDING)->exists()) {
            return $this->fail('wrong_status', 409);
        }
        DB::table('group_loans')->where('id', $id)->update(['status' => 'cancelled', 'decided_at' => now(), 'updated_at' => now()]);
        GroupAudit::record((string) $request->user()->id, 'loan_cancelled', 'Withdrew ' . $loan->reference, 'loan', $id);

        return $this->show($id);
    }

    // ---------------------------------------------------------------- the officers' side

    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'status' => ['nullable', Rule::in(['awaiting_guarantors', 'under_review', 'recommended', 'approved', 'active', 'rejected', 'cancelled', 'open'])],
            'page' => 'nullable|integer|min:1',
        ]);
        $q = GroupLoans::query()
            ->when(($data['status'] ?? null) === 'open', fn ($w) => $w->whereIn('l.status', GroupLoans::OPEN_STATUSES))
            ->when(($data['status'] ?? null) !== null && ($data['status'] ?? null) !== 'open', fn ($w) => $w->where('l.status', $data['status']));
        $total = (clone $q)->count();
        $page = (int) ($data['page'] ?? 1);
        $rows = $q->orderByDesc('l.id')->forPage($page, self::PAGE)->get();

        // The portfolio: what was paid out and what is still owed, principal and interest apart.
        $portfolio = ['disbursed' => 0.0, 'principal_outstanding' => 0.0, 'interest_outstanding' => 0.0, 'interest_paid' => 0.0, 'arrears' => 0.0, 'active' => 0, 'overdue' => 0];
        foreach (DB::table('group_loans')->where('status', 'active')->get() as $loan) {
            $p = GroupLoans::position($loan);
            $portfolio['disbursed'] += (float) $loan->amount_approved;
            $portfolio['principal_outstanding'] += $p['outstanding_principal'];
            $portfolio['interest_outstanding'] += $p['outstanding_interest'];
            $portfolio['interest_paid'] += $p['interest_paid'];
            $portfolio['arrears'] += $p['arrears'];
            if ($p['outstanding'] > 0) {
                $portfolio['active']++;
            }
            if ($p['arrears'] > 0) {
                $portfolio['overdue']++;
            }
        }

        return response()->json([
            'success' => true,
            'data' => [
                'loans' => $rows->map(fn ($l) => GroupLoans::payload($l))->values(),
                'portfolio' => array_map(fn ($v) => is_float($v) ? round($v, 2) : $v, $portfolio),
                'waiting' => [
                    'to_recommend' => DB::table('group_loans')->where('status', 'under_review')->count(),
                    'to_approve' => DB::table('group_loans')->where('status', 'recommended')->count(),
                    'to_disburse' => DB::table('group_loans')->where('status', 'approved')->count(),
                ],
            ],
            'meta' => ['pagination' => ['page' => $page, 'per_page' => self::PAGE, 'total' => $total, 'has_more' => $page * self::PAGE < $total]],
        ]);
    }

    /** One loan: its officers, its borrower and its guarantors may read it. */
    public function detail(Request $request, int $id): JsonResponse
    {
        $loan = $this->loan($id);
        if ($loan === null) {
            return $this->fail('not_found', 404);
        }
        $me = $this->myId($request);
        $mine = $me !== null && ((int) $loan->member_id === $me || DB::table('group_loan_guarantors')->where('loan_id', $id)->where('member_id', $me)->exists());
        if (!$mine && !GroupAccess::can($request->user(), 'view_loans')) {
            return $this->fail('not_yours', 403);
        }

        return $this->show($id);
    }

    /** The projects committee's recommendation: an amount (never more than asked or than the ceiling now) and why. */
    public function recommend(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['amount' => 'required|numeric|min:1', 'note' => 'required|string|min:3|max:255']);
        $loan = DB::table('group_loans')->where('id', $id)->first();
        if ($loan === null) {
            return $this->fail('not_found', 404);
        }
        if ((int) $loan->member_id === $this->myId($request)) {
            return $this->fail('own_loan', 403);
        }
        if ($loan->status !== 'under_review') {
            return $this->fail('wrong_status', 409);
        }
        $ceiling = GroupLoans::eligibility((int) $loan->member_id, $id)['ceiling'];
        if ((float) $data['amount'] > (float) $loan->amount_requested + 0.001 || (float) $data['amount'] > $ceiling + 0.001) {
            return $this->fail('over_ceiling', 422, ['ceiling' => min($ceiling, (float) $loan->amount_requested)]);
        }
        DB::table('group_loans')->where('id', $id)->update([
            'status' => 'recommended', 'amount_approved' => round((float) $data['amount'], 2), 'recommendation' => trim($data['note']),
            'recommended_by' => (string) $request->user()->id, 'recommended_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'loan_recommended', $loan->reference . ': ' . number_format((float) $data['amount']) . ' (' . trim($data['note']) . ')', 'loan', $id);

        return $this->show($id);
    }

    /** The chair approves the recommended loan, at that amount or less. */
    public function approve(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['amount' => 'nullable|numeric|min:1']);
        $loan = DB::table('group_loans')->where('id', $id)->first();
        if ($loan === null) {
            return $this->fail('not_found', 404);
        }
        if ((int) $loan->member_id === $this->myId($request)) {
            return $this->fail('own_loan', 403);
        }
        if ($loan->status !== 'recommended') {
            return $this->fail('wrong_status', 409);
        }
        $amount = isset($data['amount']) ? round((float) $data['amount'], 2) : (float) $loan->amount_approved;
        if ($amount > (float) $loan->amount_approved + 0.001) {
            return $this->fail('over_ceiling', 422, ['ceiling' => (float) $loan->amount_approved]);
        }
        DB::table('group_loans')->where('id', $id)->update([
            'status' => 'approved', 'amount_approved' => $amount, 'approved_by' => (string) $request->user()->id, 'approved_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'loan_approved', $loan->reference . ' approved: ' . number_format($amount), 'loan', $id);

        return $this->show($id);
    }

    /** Turn a loan down at any step before it is paid out, with the reason. */
    public function reject(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['reason' => 'required|string|min:3|max:255']);
        $loan = DB::table('group_loans')->where('id', $id)->first();
        if ($loan === null) {
            return $this->fail('not_found', 404);
        }
        if ((int) $loan->member_id === $this->myId($request)) {
            return $this->fail('own_loan', 403);
        }
        if (!in_array($loan->status, GroupLoans::OPEN_STATUSES, true)
            || DB::table('group_transactions')->where('loan_id', $id)->where('category', 'loan_disbursement')->where('status', GroupLedger::PENDING)->exists()) {
            return $this->fail('wrong_status', 409);
        }
        DB::table('group_loans')->where('id', $id)->update([
            'status' => 'rejected', 'reject_reason' => trim($data['reason']), 'decided_by' => (string) $request->user()->id, 'decided_at' => now(), 'updated_at' => now(),
        ]);
        GroupAudit::record((string) $request->user()->id, 'loan_rejected', $loan->reference . ': ' . trim($data['reason']), 'loan', $id);

        return $this->show($id);
    }

    /** The treasurer pays the approved loan out. It runs once someone else verifies the payout. */
    public function disburse(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'method' => ['required', Rule::in(GroupLedger::METHODS)],
            'external_ref' => 'nullable|string|max:80',
            'note' => 'nullable|string|max:255',
        ]);
        $loan = DB::table('group_loans')->where('id', $id)->first();
        if ($loan === null) {
            return $this->fail('not_found', 404);
        }
        if ((int) $loan->member_id === $this->myId($request)) {
            return $this->fail('own_loan', 403);
        }
        try {
            $tx = GroupLedger::submit([
                'member_id' => (int) $loan->member_id, 'loan_id' => $id, 'category' => 'loan_disbursement', 'amount' => (float) $loan->amount_approved,
                'method' => $data['method'], 'external_ref' => $data['external_ref'] ?? null, 'note' => $data['note'] ?? $loan->reference,
            ], (string) $request->user()->id);
        } catch (InvalidArgumentException $e) {
            return response()->json(['success' => false, 'code' => $e->getMessage(), 'message' => GroupTransactionController::word($e->getMessage())], 422);
        }
        GroupAudit::record((string) $request->user()->id, 'loan_disbursed', $loan->reference . ': ' . number_format((float) $loan->amount_approved) . ' paid out, waiting for verification', 'transaction', $tx);

        return $this->show($id);
    }
}
