<?php

namespace App\Http\Controllers\API\Groups;

use App\Models\Business;
use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupReceipts;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;

/**
 * Receipts. A member reads the receipt of their OWN verified payment, an officer who sees the group's finances reads any; the app turns it
 * into a document (with a QR code made from the verification link). Anyone holding the link or code may check that a receipt is genuine.
 */
class GroupReceiptController extends Controller
{
    private function groupName(string $ownerId): string
    {
        return Business::forOwnerId($ownerId)?->name ?? 'Group';
    }

    /** A verified payment's receipt: the payment, the group's name and the link the QR code carries. */
    public function show(Request $request, int $id): JsonResponse
    {
        $row = GroupLedger::listQuery()->where('t.id', $id)->first();
        $me = GroupAccess::member($request->user());
        $mine = $row !== null && $me !== null && $row->member_id !== null && (int) $row->member_id === (int) $me['id'];
        if ($row === null || $row->status !== GroupLedger::VERIFIED || $row->receipt_number === null || (!$mine && !GroupAccess::can($request->user(), 'view_finance'))) {
            return response()->json(['success' => false, 'code' => 'not_found', 'message' => 'Risiti haipo. / Receipt not found.'], 404);
        }

        return response()->json(['success' => true, 'data' => ['receipt' => [
            'transaction' => GroupLedger::payload($row),
            'group' => $this->groupName((string) $row->owner_id),
            'verify_url' => GroupReceipts::url($row),
            'reversed' => $row->reversed_by_id !== null,
            // So the receipt can be sent to the member: the one it is for, or whoever sees the group's finances (checked above).
            'member_phone' => $row->member_id === null ? null : DB::table('group_members')->where('id', $row->member_id)->value('phone'),
        ]]]);
    }

    /**
     * No sign-in: whether a receipt is genuine. A browser gets a small page, an app gets JSON. Only the group's name, the receipt number,
     * the kind, the amount and the date are shown; never a name. Limited per address.
     */
    public function verify(Request $request, string $token): Response|JsonResponse
    {
        $parts = explode('.', $token);
        $tx = null;
        if (count($parts) === 3 && preg_match('/^[0-9a-f-]{36}$/i', $parts[0]) === 1 && preg_match('/^[A-Z0-9-]{3,20}$/', $parts[1]) === 1) {
            $tx = TenantContext::withoutScope(fn () => DB::table('group_transactions')->where('owner_id', $parts[0])->where('receipt_number', $parts[1])->where('status', GroupLedger::VERIFIED)->first());
        }
        $valid = $tx !== null && GroupReceipts::genuine($tx, $parts[2]);
        $facts = $valid ? [
            'group' => $this->groupName((string) $tx->owner_id), 'receipt_number' => $tx->receipt_number, 'category' => $tx->category, 'direction' => $tx->direction,
            'amount' => (float) $tx->amount, 'date' => substr((string) ($tx->verified_at ?? $tx->paid_on), 0, 10), 'reversed' => $tx->reversed_by_id !== null,
        ] : null;
        if (str_contains((string) $request->header('Accept'), 'text/html')) {
            $e = fn ($v) => htmlspecialchars((string) $v, ENT_QUOTES, 'UTF-8');
            $body = $valid
                ? '<h1 style="color:#1b8a3a">&#10003; Risiti halali / Genuine receipt</h1><p><b>' . $e($facts['group']) . '</b></p><p>' . $e($facts['receipt_number']) . '<br>'
                    . $e($facts['category']) . ' &middot; TSh ' . number_format($facts['amount']) . '<br>' . $e($facts['date']) . ($facts['reversed'] ? '<br><b style="color:#b00020">Imerekebishwa / Reversed</b>' : '') . '</p>'
                : '<h1 style="color:#b00020">&#10007; Risiti hii haikuthibitika / This receipt could not be verified</h1>';

            return response('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Receipt</title></head>'
                . '<body style="font-family:sans-serif;max-width:420px;margin:40px auto;padding:0 16px">' . $body . '</body></html>', $valid ? 200 : 404)->header('Content-Type', 'text/html; charset=UTF-8');
        }

        return response()->json(['success' => $valid, 'data' => $facts], $valid ? 200 : 404);
    }
}
