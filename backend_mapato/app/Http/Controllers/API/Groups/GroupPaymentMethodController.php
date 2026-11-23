<?php

namespace App\Http\Controllers\API\Groups;

use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupPaymentMethods;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * The payment methods the group authorises and where each is paid. Everyone in the group reads them (a member needs to know where to pay);
 * only whoever holds `manage_payment_methods` (the Mwenyekiti and the Makamu) chooses them. A change replaces the list and is written to the
 * activity log with its reason. For a finance reader, the month's verified money per method is shown with each.
 */
class GroupPaymentMethodController extends Controller
{
    private function fail(string $code, string $message, int $status = 422): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => $message], $status);
    }

    /** @return array<string, mixed> */
    private function body(Request $request): array
    {
        $own = $request->user() !== null && \App\Support\Groups\GroupAccess::can($request->user(), 'view_finance');
        $methods = GroupPaymentMethods::payload();
        if ($own) {
            $month = now()->format('Y-m');
            $by = DB::table('group_transactions')->where('status', GroupLedger::VERIFIED)->whereBetween('paid_on', [$month . '-01', now()->endOfMonth()->toDateString()])
                ->selectRaw("method, SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END) as money_in, SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END) as money_out, COUNT(*) as n")
                ->groupBy('method')->get()->keyBy('method');
            $methods = array_map(fn ($m) => $m + ['month' => [
                'in' => round((float) ($by[$m['method']]->money_in ?? 0), 2), 'out' => round((float) ($by[$m['method']]->money_out ?? 0), 2), 'count' => (int) ($by[$m['method']]->n ?? 0),
            ]], $methods);
        }

        return ['configured' => GroupPaymentMethods::configured(), 'methods' => $methods, 'choices' => GroupPaymentMethods::CHOICES,
            'can_manage' => \App\Support\Groups\GroupAccess::can($request->user(), 'manage_payment_methods')];
    }

    public function index(Request $request): JsonResponse
    {
        return response()->json(['success' => true, 'data' => $this->body($request)]);
    }

    /** Replaces the authorised list. Each method needs its number and the name it is paid to; a bank also its name. */
    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'reason' => 'required|string|min:3|max:255',
            'methods' => 'required|array|min:1|max:6',
            'methods.*.method' => ['required', 'distinct', Rule::in(GroupPaymentMethods::CHOICES)],
            'methods.*.number' => ['nullable', 'string', 'max:40', 'regex:/^[0-9A-Za-z+\- ]{3,40}$/'],
            'methods.*.account_name' => 'nullable|string|min:2|max:100',
            'methods.*.bank_name' => 'nullable|string|min:2|max:80',
        ]);
        foreach ($data['methods'] as $m) {
            if ($m['method'] === 'cash') {
                continue;
            }
            if (trim((string) ($m['number'] ?? '')) === '') {
                return $this->fail('number_needed', 'Weka namba ya kulipia kwa kila njia. / Give the number to pay to for each method.', 422);
            }
            if (trim((string) ($m['account_name'] ?? '')) === '') {
                return $this->fail('name_needed', 'Weka jina la mwenye namba kwa kila njia. / Give the name the money is paid to for each method.', 422);
            }
            if ($m['method'] === 'bank_transfer' && trim((string) ($m['bank_name'] ?? '')) === '') {
                return $this->fail('bank_needed', 'Weka jina la benki. / Give the name of the bank.', 422);
            }
        }

        $userId = (string) $request->user()->id;
        DB::transaction(function () use ($data, $userId) {
            $keep = array_column($data['methods'], 'method');
            DB::table('group_payment_methods')->whereNotIn('method', $keep)->delete();
            foreach (array_values($data['methods']) as $i => $m) {
                $cash = $m['method'] === 'cash';
                $row = [
                    'number' => $cash ? null : trim((string) $m['number']), 'account_name' => $cash ? null : trim((string) $m['account_name']),
                    'bank_name' => $m['method'] === 'bank_transfer' ? trim((string) $m['bank_name']) : null, 'sort' => $i, 'updated_by' => $userId, 'updated_at' => now(),
                ];
                if (DB::table('group_payment_methods')->where('method', $m['method'])->exists()) {
                    DB::table('group_payment_methods')->where('method', $m['method'])->update($row);
                } else {
                    DB::table('group_payment_methods')->insert($row + ['method' => $m['method'], 'created_at' => now()]);
                }
            }
        });
        GroupAudit::record($userId, 'payment_methods_changed', implode(', ', array_column($data['methods'], 'method')) . ' (' . trim($data['reason']) . ')');

        return response()->json(['success' => true, 'data' => $this->body($request)]);
    }
}
