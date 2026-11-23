<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupContributions;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupMembers;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use InvalidArgumentException;

/**
 * The group's money as the treasurer works it: every payment, the queue waiting for verification, verifying, turning down and reversing.
 * A payment counts only once verified; nobody verifies their own; a verified payment is corrected by a reversal, never edited.
 */
class GroupTransactionController extends Controller
{
    private const PAGE = 50;

    /** The words for each refusal the ledger can give, both languages. */
    private const WORDS = [
        'method_not_authorized' => 'Njia hii ya malipo haijaidhinishwa na kikundi. / This payment method is not authorised by the group.',
        'reference_required' => 'Weka namba ya muamala (reference) kwa malipo yasiyo ya taslimu. / Enter the transaction reference for a non-cash payment.',
        'duplicate_reference' => 'Muamala wenye namba hii tayari umerekodiwa. / A payment with this reference is already recorded.',
        'not_pending' => 'Malipo haya hayasubiri tena uthibitisho. / This payment is no longer waiting for verification.',
        'cannot_reverse' => 'Malipo haya hayawezi kurudishwa. / This payment cannot be reversed.',
        'own_submission' => 'Huwezi kuthibitisha malipo uliyoyarekodi mwenyewe. / You cannot verify a payment you recorded yourself.',
        'own_payment' => 'Huwezi kuthibitisha malipo yako mwenyewe. / You cannot verify your own payment.',
        'member_not_open' => 'Mwanachama huyu hawezi kupokelewa malipo. / This member cannot take payments.',
        'cannot_pay_out' => 'Fedha zinazotoka ni kutoa akiba au matumizi ya kikundi tu. / Money goes out only as a savings withdrawal or a group expense.',
        'obligation_required' => 'Chagua mchango unaolipwa. / Choose the contribution being paid.',
        'more_than_owed' => 'Kiasi ni zaidi ya kinachodaiwa kwenye mchango huu. / The amount is more than is owed on this contribution.',
        'more_than_savings' => 'Kiasi ni zaidi ya akiba iliyopo. / The amount is more than the savings there are.',
        'payee_required' => 'Andika aliyelipwa. / Write who was paid.',
        'payout_right_needed' => 'Ni Mweka Hazina tu anayerekodi fedha zinazotoka. / Only the treasurer records money going out.',
        'loan_required' => 'Chagua mkopo wa mwanachama huyu. / Choose this member\'s loan.',
        'loan_not_ready' => 'Mkopo huu haujaidhinishwa au tayari umetolewa. / This loan is not approved, or was already paid out.',
        'amount_not_approved' => 'Kiasi lazima kiwe kile kilichoidhinishwa. / The amount must be the one approved.',
        'loan_not_running' => 'Mkopo huu hauko hai. / This loan is not running.',
        'more_than_loan' => 'Kiasi ni zaidi ya deni la mkopo. / The amount is more than is owed on the loan.',
        'benefit_required' => 'Chagua ombi la msaada. / Choose the welfare request.',
        'benefit_not_ready' => 'Ombi hili halijaidhinishwa au tayari limelipwa. / This request is not approved, or was already paid.',
        'hire_required' => 'Chagua ukodishaji unaolipwa. / Choose the hire being paid.',
        'hire_not_open' => 'Ukodishaji huu haupokei malipo. / This hire takes no payments.',
        'more_than_hire' => 'Kiasi ni zaidi ya kinachodaiwa kwa ukodishaji huu. / The amount is more than is owed for this hire.',
        'loan_has_repayments' => 'Mkopo una marejesho; hauwezi kurudishwa. / The loan has repayments; it cannot be reversed.',
        'expense_not_ready' => 'Ombi hili la matumizi halijaidhinishwa au tayari limelipwa. / This expense request is not approved, or was already paid.',
        'try_again' => 'Jaribu tena. / Try again.',
    ];

    /** The words for a refusal code, both languages (for the other group controllers too). */
    public static function word(string $code): string
    {
        return self::WORDS[$code] ?? $code;
    }

    private function fail(string $code, int $status = 422): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => self::WORDS[$code] ?? $code], $status);
    }

    /** Payments, newest first, a page at a time; filter by status, category, member or a search. */
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'status' => ['nullable', Rule::in([GroupLedger::PENDING, GroupLedger::VERIFIED, GroupLedger::REJECTED])],
            'category' => ['nullable', Rule::in(GroupLedger::CATEGORIES)],
            'direction' => ['nullable', Rule::in(['in', 'out'])],
            'member_id' => 'nullable|integer',
            'q' => 'nullable|string|max:100',
            'page' => 'nullable|integer|min:1',
        ]);
        $query = GroupLedger::listQuery()
            ->when($data['status'] ?? null, fn ($q, $s) => $q->where('t.status', $s))
            ->when($data['category'] ?? null, fn ($q, $c) => $q->where('t.category', $c))
            ->when($data['direction'] ?? null, fn ($q, $d) => $q->where('t.direction', $d))
            ->when($data['member_id'] ?? null, fn ($q, $m) => $q->where('t.member_id', (int) $m))
            ->when(trim((string) ($data['q'] ?? '')) !== '', function ($q) use ($data) {
                $term = '%' . trim((string) $data['q']) . '%';
                $q->where(fn ($w) => $w->where('m.full_name', 'like', $term)->orWhere('t.external_ref', 'like', $term)
                    ->orWhere('t.reference', 'like', $term)->orWhere('t.receipt_number', 'like', $term)->orWhere('m.member_number', 'like', $term));
            });
        $total = (clone $query)->count();
        $page = (int) ($data['page'] ?? 1);
        // The queue is read oldest first (first in, first checked); everything else newest first.
        $rows = (($data['status'] ?? null) === GroupLedger::PENDING ? $query->orderBy('t.id') : $query->orderByDesc('t.id'))
            ->forPage($page, self::PAGE)->get();

        return response()->json([
            'success' => true,
            'data' => ['transactions' => $rows->map(fn ($r) => GroupLedger::payload($r))->values()],
            'meta' => ['pagination' => ['page' => $page, 'per_page' => self::PAGE, 'total' => $total, 'has_more' => $page * self::PAGE < $total]],
        ]);
    }

    /**
     * The group's totals: verified money in each category (expenses as money out), what waits for verification, this month's contributions
     * (expected and collected), what is overdue, and the cash the records say the group holds (all money in minus all money out).
     */
    public function summary(Request $request): JsonResponse
    {
        $request->validate(['month' => ['nullable', 'regex:/^\d{4}-(0[1-9]|1[0-2])$/']]);
        $month = (string) $request->query('month', now()->format('Y-m'));
        $verified = DB::table('group_transactions')->where('status', GroupLedger::VERIFIED)
            ->selectRaw("category, SUM(CASE WHEN direction = 'in' THEN amount ELSE -amount END) as total")->groupBy('category')->pluck('total', 'category');
        $pending = DB::table('group_transactions')->where('status', GroupLedger::PENDING)->selectRaw('COUNT(*) as n, COALESCE(SUM(amount), 0) as amount')->first();
        $spentInMonth = (float) DB::table('group_transactions')->where('status', GroupLedger::VERIFIED)->where('category', 'expense')
            ->whereBetween('paid_on', [$month . '-01', \Illuminate\Support\Carbon::parse($month . '-01')->endOfMonth()->toDateString()])
            ->selectRaw("COALESCE(SUM(CASE WHEN direction = 'out' THEN amount ELSE -amount END), 0) as spent")->value('spent');

        return response()->json(['success' => true, 'data' => [
            'verified' => collect(GroupLedger::CATEGORIES)->mapWithKeys(fn ($c) => [$c => round((float) ($verified[$c] ?? 0), 2)]),
            'cash_on_record' => round((float) collect($verified)->sum(), 2),
            'pending_count' => (int) $pending->n,
            'pending_amount' => round((float) $pending->amount, 2),
            'month' => $month,
            'contributions' => GroupContributions::position($month, now()->toDateString()),
            'expenses_in_month' => round($spentInMonth, 2),
        ]]);
    }

    /** @return array<string, mixed> what a member may send for themself */
    public static function paymentRules(): array
    {
        return [
            'category' => ['required', Rule::in(GroupLedger::MEMBER_CATEGORIES)],
            'obligation_id' => 'nullable|integer|required_if:category,contribution',
            'loan_id' => 'nullable|integer|required_if:category,loan_repayment',
            'hire_id' => 'nullable|integer|required_if:category,hire',
            'amount' => 'required|numeric|min:1|max:1000000000',
            'method' => ['required', Rule::in(GroupLedger::METHODS)],
            'external_ref' => 'nullable|string|max:80',
            'paid_on' => 'nullable|date|before_or_equal:today',
            'note' => 'nullable|string|max:255',
        ];
    }

    /**
     * An officer records money a member paid in -- or, with the payout right, money going out: a member's savings withdrawal, or a group
     * expense (no member, a payee). Everything waits for someone else's verification.
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'category' => ['required', Rule::in(array_diff(GroupLedger::CATEGORIES, ['loan_disbursement', 'welfare', 'hire', 'dividend']))],
            'direction' => ['nullable', Rule::in(['in', 'out'])],
            'member_id' => 'nullable|integer|required_unless:category,expense',
            'payee' => 'nullable|string|max:150',
        ] + array_diff_key(self::paymentRules(), ['category' => true]));
        $direction = $data['category'] === 'expense' ? 'out' : ($data['direction'] ?? 'in');
        if ($direction === 'out' && !GroupAccess::can($request->user(), 'record_payouts')) {
            return $this->fail('payout_right_needed', 403);
        }
        $data['direction'] = $direction;
        if ($data['category'] === 'expense') {
            return self::submitFor($request, null, $data);
        }
        $member = DB::table('group_members')->where('id', (int) $data['member_id'])->first();
        if ($member === null || !in_array($member->status, [GroupMembers::SUBMITTED, GroupMembers::ACTIVE, GroupMembers::SUSPENDED], true)) {
            return $this->fail('member_not_open');
        }

        return self::submitFor($request, $member, $data);
    }

    /** Shared by the officer's form and a member paying for themself. [member] is null for a group expense. */
    public static function submitFor(Request $request, ?object $member, array $data): JsonResponse
    {
        try {
            $id = GroupLedger::submit(['member_id' => $member === null ? null : (int) $member->id] + $data, (string) $request->user()->id);
        } catch (InvalidArgumentException $e) {
            return response()->json(['success' => false, 'code' => $e->getMessage(), 'message' => self::WORDS[$e->getMessage()] ?? $e->getMessage()], 422);
        }
        GroupAudit::record((string) $request->user()->id, 'payment_submitted', (($data['direction'] ?? 'in') === 'out' ? 'Payout' : 'Payment') . ' of ' . number_format((float) $data['amount']) . ' (' . $data['category'] . ', ' . $data['method'] . ') ' . ($member === null ? 'to ' . ($data['payee'] ?? '') : 'for ' . $member->full_name), 'transaction', $id);

        return response()->json(['success' => true, 'data' => ['transaction' => GroupLedger::payload(GroupLedger::listQuery()->where('t.id', $id)->first())]], 201);
    }

    private function transaction(int $id): ?object
    {
        return DB::table('group_transactions')->where('id', $id)->first();
    }

    public function verify(Request $request, int $id): JsonResponse
    {
        $tx = $this->transaction($id);
        if ($tx === null) {
            return response()->json(['success' => false, 'message' => 'Malipo hayapo. / Payment not found.'], 404);
        }
        $user = $request->user();
        $me = GroupAccess::member($user);
        if ($why = GroupLedger::selfCheck($tx, (string) $user->id, $me === null ? null : (int) $me['id'])) {
            return $this->fail($why, 403);
        }
        try {
            $receipt = GroupLedger::verify($tx, (string) $user->id);
        } catch (InvalidArgumentException $e) {
            return $this->fail($e->getMessage(), 409);
        }
        GroupAudit::record((string) $user->id, 'payment_verified', 'Verified ' . $tx->reference . ' (' . number_format((float) $tx->amount) . ', ' . $tx->category . '), receipt ' . $receipt, 'transaction', $id);

        return response()->json(['success' => true, 'data' => ['transaction' => GroupLedger::payload(GroupLedger::listQuery()->where('t.id', $id)->first())]]);
    }

    public function reject(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['reason' => 'required|string|min:3|max:255']);
        $tx = $this->transaction($id);
        if ($tx === null) {
            return response()->json(['success' => false, 'message' => 'Malipo hayapo. / Payment not found.'], 404);
        }
        $user = $request->user();
        $me = GroupAccess::member($user);
        if ($why = GroupLedger::selfCheck($tx, (string) $user->id, $me === null ? null : (int) $me['id'])) {
            return $this->fail($why, 403);
        }
        try {
            GroupLedger::reject($tx, (string) $user->id, trim($data['reason']));
        } catch (InvalidArgumentException $e) {
            return $this->fail($e->getMessage(), 409);
        }
        GroupAudit::record((string) $user->id, 'payment_rejected', 'Turned down ' . $tx->reference . ': ' . trim($data['reason']), 'transaction', $id);

        return response()->json(['success' => true, 'data' => ['transaction' => GroupLedger::payload(GroupLedger::listQuery()->where('t.id', $id)->first())]]);
    }

    public function reverse(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['reason' => 'required|string|min:3|max:255']);
        $tx = $this->transaction($id);
        if ($tx === null) {
            return response()->json(['success' => false, 'message' => 'Malipo hayapo. / Payment not found.'], 404);
        }
        $me = GroupAccess::member($request->user());
        if ($me !== null && (int) $tx->member_id === (int) $me['id']) {
            return $this->fail('own_payment', 403);
        }
        try {
            $newId = GroupLedger::reverse($tx, (string) $request->user()->id, trim($data['reason']));
        } catch (InvalidArgumentException $e) {
            return $this->fail($e->getMessage(), 409);
        }
        GroupAudit::record((string) $request->user()->id, 'payment_reversed', 'Reversed ' . $tx->reference . ' (' . number_format((float) $tx->amount) . '): ' . trim($data['reason']), 'transaction', $newId);

        return response()->json(['success' => true, 'data' => ['transaction' => GroupLedger::payload(GroupLedger::listQuery()->where('t.id', $newId)->first())]]);
    }
}
