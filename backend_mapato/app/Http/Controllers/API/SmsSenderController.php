<?php

namespace App\Http\Controllers\API;

use App\Helpers\ResponseHelper;
use App\Http\Controllers\Controller;
use App\Models\Business;
use App\Models\User;
use App\Services\Inventory\AuditTrail;
use App\Services\SmsService;
use App\Support\Pagination;
use App\Support\SmsSenderName;
use App\Support\SuperAdminPhones;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;

/**
 * The SMS sender name of each business: the name a customer's phone shows instead of a number.
 *
 *   Super admin   GET  /admin/sms-senders              every business with its name, status, what it sent
 *                 PUT  /admin/sms-senders/{id}         set the name / display name / status / note
 *                 POST /admin/sms-senders/{id}/test    one real text under the name, to see if the provider accepts it
 *   Owner         POST   /business/sms-sender          ask for a name (it then waits for the super admin)
 *                 DELETE /business/sms-sender          withdraw a request
 *
 * A name works only after the super admin registered it with the SMS provider and marked it `approved`. Until
 * then (and whenever the provider stops accepting it) the business's texts go out under the platform's name.
 */
class SmsSenderController extends Controller
{
    public function __construct(private readonly AuditTrail $audit)
    {
    }

    // ------------------------------------------------------------------ super admin

    public function index(Request $request): JsonResponse
    {
        $query = Business::withoutAccountScope()->with('owner');

        if ($search = trim((string) $request->query('q', ''))) {
            $query->where(function ($q) use ($search) {
                $q->where('businesses.name', 'like', "%{$search}%")
                    ->orWhere('businesses.tin', 'like', "%{$search}%")
                    ->orWhere('businesses.sms_sender_id', 'like', "%{$search}%")
                    ->orWhere('businesses.sms_display_name', 'like', "%{$search}%")
                    ->orWhereHas('owner', function ($owner) use ($search) {
                        $owner->where('name', 'like', "%{$search}%")
                            ->orWhere('phone_number', 'like', "%{$search}%");
                    });
            });
        }

        $status = (string) $request->query('status', 'all');
        if ($status === 'attention') {
            $query->where('sms_sender_status', 'approved')->whereNotNull('sms_last_error')->where('sms_last_error', '!=', '');
        } elseif (in_array($status, Business::SMS_SENDER_STATUSES, true)) {
            $query->where('sms_sender_status', $status);
        }

        // What needs the super admin first: names waiting for approval, then names that stopped working.
        $page = $query
            ->orderByRaw("CASE WHEN sms_sender_status = 'pending' THEN 0 WHEN sms_sender_status = 'approved' AND sms_last_error IS NOT NULL AND sms_last_error <> '' THEN 1 WHEN sms_sender_status = 'approved' THEN 2 WHEN sms_sender_status = 'rejected' THEN 3 ELSE 4 END")
            ->orderBy('name')
            ->paginate(Pagination::perPage($request, 30));

        $byStatus = Business::withoutAccountScope()
            ->selectRaw('sms_sender_status as status, COUNT(*) as total')
            ->groupBy('sms_sender_status')
            ->pluck('total', 'status');

        $attention = Business::withoutAccountScope()
            ->where('sms_sender_status', 'approved')->whereNotNull('sms_last_error')->where('sms_last_error', '!=', '')
            ->count();

        return ResponseHelper::withMeta(
            $page->getCollection()->map(fn (Business $b) => $this->payload($b))->values(),
            [
                'counts' => [
                    'total' => (int) $byStatus->sum(),
                    'none' => (int) ($byStatus['none'] ?? 0),
                    'pending' => (int) ($byStatus['pending'] ?? 0),
                    'approved' => (int) ($byStatus['approved'] ?? 0),
                    'rejected' => (int) ($byStatus['rejected'] ?? 0),
                    'attention' => $attention,
                ],
                'platform_sender' => (string) config('sms.kilakona.sender_id', ''),
                'sms_delivering' => SmsService::delivers(),
                'pagination' => [
                    'current_page' => $page->currentPage(),
                    'last_page' => $page->lastPage(),
                    'per_page' => $page->perPage(),
                    'total' => $page->total(),
                    'has_more_pages' => $page->hasMorePages(),
                ],
            ],
            'Sender names retrieved successfully'
        );
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $business = Business::withoutAccountScope()->with('owner')->findOrFail($id);

        $data = $request->validate([
            'sender_id' => 'sometimes|nullable|string|max:40',
            'display_name' => 'sometimes|nullable|string|max:40',
            'status' => ['sometimes', Rule::in(Business::SMS_SENDER_STATUSES)],
            'note' => 'sometimes|nullable|string|max:255',
            // The business's OWN account with the SMS provider. Sent only when the super admin typed something;
            // nothing here is ever returned (see Business::smsSenderDetails).
            'api_key' => 'sometimes|nullable|string|max:255',
            'api_secret' => 'sometimes|nullable|string|max:255',
            'clear_credentials' => 'sometimes|boolean',
            'fallback_platform' => 'sometimes|boolean',
        ]);

        $before = $business->smsSenderSummary();
        $previousStatus = (string) ($business->sms_sender_status ?: 'none');

        $sender = array_key_exists('sender_id', $data) ? $this->clean($data['sender_id']) : $this->clean($business->sms_sender_id);
        $changed = $sender !== $this->clean($business->sms_sender_id);
        $given = $data['status'] ?? null;

        if ($sender === null && in_array($given, ['pending', 'approved', 'rejected'], true)) {
            return $this->problem('Weka jina la mtumaji kwanza. / Enter the sender name first.');
        }

        if ($sender !== null && ($changed || $given === 'approved')) {
            if ($message = SmsSenderName::problem($sender, $business->id)) {
                return $this->problem($message);
            }
        }

        $newKey = $this->clean($data['api_key'] ?? null);
        $newSecret = $this->clean($data['api_secret'] ?? null);
        if ($newSecret !== null && $newKey === null && $business->smsCredentials() === null && !$request->boolean('clear_credentials')) {
            return $this->problem('Weka API key pamoja na secret. / Enter the API key together with the secret.');
        }

        if ($sender === null) {
            $status = 'none';
        } else {
            $status = $given ?? ($changed ? 'pending' : $previousStatus);
            if ($status === 'none') {
                $status = 'pending'; // a name is set, so it is at least waiting
            }
        }

        $business->sms_sender_id = $sender;
        $business->sms_sender_status = $status;
        if (array_key_exists('display_name', $data)) {
            $business->sms_display_name = $this->clean($data['display_name']);
        }

        // The business's own account. A name that is cleared takes its key with it (no forgotten secrets).
        $hadOwnAccount = $business->smsCredentials() !== null;
        $credentialsChanged = false;
        if ($sender === null || $request->boolean('clear_credentials')) {
            if ($hadOwnAccount || $business->getRawOriginal('sms_api_key') !== null || $business->getRawOriginal('sms_api_secret') !== null) {
                $credentialsChanged = true;
            }
            $business->sms_api_key = null;
            $business->sms_api_secret = null;
            $business->sms_fallback_platform = true;
        } else {
            if ($newKey !== null) {
                $business->sms_api_key = $newKey;
                $credentialsChanged = true;
            }
            if ($newSecret !== null) {
                $business->sms_api_secret = $newSecret;
                $credentialsChanged = true;
            }
            // Moving to an account of its own should not quietly spend the platform's SMS credit when that
            // account fails: say so explicitly (fallback_platform: true) to allow it.
            if ($newKey !== null && !$hadOwnAccount && !array_key_exists('fallback_platform', $data)) {
                $business->sms_fallback_platform = false;
            }
        }
        if (array_key_exists('fallback_platform', $data) && $sender !== null) {
            $business->sms_fallback_platform = $request->boolean('fallback_platform');
        }

        $business->sms_sender_note = array_key_exists('note', $data)
            ? $this->clean($data['note'])
            : (($changed || $status === 'approved') ? null : $business->sms_sender_note);

        $business->sms_sender_requested_at = $sender === null ? null : ($business->sms_sender_requested_at ?? now());
        $business->sms_sender_approved_at = $status === 'approved'
            ? (($previousStatus === 'approved' && !$changed && $business->sms_sender_approved_at) ? $business->sms_sender_approved_at : now())
            : null;

        // The super admin has looked at it: an old "the provider refused this name" no longer applies.
        if ($changed || $credentialsChanged || $status !== 'approved' || $previousStatus !== 'approved') {
            $business->sms_last_error = null;
        }

        try {
            $business->save();
        } catch (QueryException $e) {
            if ($sender !== null && SmsSenderName::takenByAnother($sender, $business->id)) {
                return $this->problem('Jina hili tayari linatumiwa na biashara nyingine. / This sender name is already used by another business.');
            }
            throw $e;
        }

        $this->audit->record(
            $request, 'business', null, 'sms_sender_changed', $before, $business->smsSenderSummary(),
            "{$request->user()->name} set the SMS sender name of \"{$business->name}\" to " . ($sender ?? '(none)') . " ({$status})"
                . ($credentialsChanged ? ($business->smsCredentials() !== null ? ', own SMS account key changed' : ', own SMS account key removed') : ''),
        );

        if ($status !== $previousStatus && in_array($status, ['approved', 'rejected'], true)) {
            $this->tellOwner($business, $status);
        }

        return ResponseHelper::success($this->payload($business->fresh('owner')), 'Sender name saved');
    }

    public function test(Request $request, string $id): JsonResponse
    {
        $business = Business::withoutAccountScope()->findOrFail($id);

        $data = $request->validate([
            'phone' => 'sometimes|nullable|string|max:30',
            'sender_id' => 'sometimes|nullable|string|max:40',
            // What was just typed on the page, so a key can be tried before it is saved.
            'api_key' => 'sometimes|nullable|string|max:255',
            'api_secret' => 'sometimes|nullable|string|max:255',
        ]);

        $sender = $this->clean($data['sender_id'] ?? null) ?? $this->clean($business->sms_sender_id);
        if ($sender === null) {
            return $this->problem('Weka jina la mtumaji kwanza. / Enter the sender name first.');
        }
        if (!SmsSenderName::validFormat($sender)) {
            return $this->problem('Jina la mtumaji lazima liwe na herufi 3 hadi 11 (herufi na tarakimu tu), likianza na herufi. / The sender name must be 3 to 11 letters or digits and start with a letter.');
        }

        $phone = $this->clean($data['phone'] ?? null) ?? $this->clean($request->user()->phone_number);
        if ($phone === null) {
            return $this->problem('Weka namba ya simu ya kutumia jaribio. / Enter a phone number to send the test to.');
        }

        $typedKey = $this->clean($data['api_key'] ?? null);
        $credentials = $typedKey !== null
            ? ['api_key' => $typedKey, 'api_secret' => $this->clean($data['api_secret'] ?? null)]
            : $business->smsCredentials();

        $result = SmsService::sendTest(
            $phone,
            $sender,
            "Jaribio: jina la mtumaji {$sender} linafanya kazi. / Test: the sender name {$sender} works.",
            $credentials
        );

        // The provider took the name again: whatever stopped it before is over.
        if ($result['outcome'] === 'accepted' && $business->sms_sender_status === 'approved'
            && strcasecmp((string) $business->sms_sender_id, $sender) === 0) {
            DB::table('businesses')->where('id', $business->id)->update(['sms_last_error' => null]);
        }

        return ResponseHelper::success(
            $result + [
                'sender_id' => $sender,
                'platform_sender' => (string) config('sms.kilakona.sender_id', ''),
                'own_account' => $credentials !== null,
            ],
            'Test finished'
        );
    }

    // ------------------------------------------------------------------ owner

    public function request(Request $request): JsonResponse
    {
        $business = $this->ownBusiness($request);
        if ($business instanceof JsonResponse) {
            return $business;
        }

        $data = $request->validate([
            'sender_id' => 'required|string|max:40',
            'display_name' => 'sometimes|nullable|string|max:40',
        ]);

        if ($business->sms_sender_status === 'approved') {
            return ResponseHelper::error(
                'Jina lako la mtumaji limeshaidhinishwa. Wasiliana na msimamizi ili libadilishwe. / '
                . 'Your sender name is already approved. Contact your administrator to change it.',
                422,
                ['code' => 'sender_locked']
            );
        }

        $sender = $this->clean($data['sender_id']);
        if ($message = SmsSenderName::problem((string) $sender, $business->id)) {
            return $this->problem($message);
        }

        $before = $business->smsSenderSummary();
        $notify = $business->sms_sender_status !== 'pending' || strcasecmp((string) $business->sms_sender_id, (string) $sender) !== 0;

        $business->sms_sender_id = $sender;
        $business->sms_sender_status = 'pending';
        $business->sms_sender_note = null;
        $business->sms_sender_requested_at = now();
        $business->sms_sender_approved_at = null;
        $business->sms_last_error = null;
        if (array_key_exists('display_name', $data)) {
            $business->sms_display_name = $this->clean($data['display_name']);
        }

        try {
            $business->save();
        } catch (QueryException $e) {
            if (SmsSenderName::takenByAnother((string) $sender, $business->id)) {
                return $this->problem('Jina hili tayari linatumiwa na biashara nyingine. / This sender name is already used by another business.');
            }
            throw $e;
        }

        $this->audit->record(
            $request, 'business', null, 'sms_sender_requested', $before, $business->smsSenderSummary(),
            "{$request->user()->name} asked for the SMS sender name {$sender} for \"{$business->name}\"",
        );

        if ($notify) {
            $this->tellSuperAdmins($business);
        }

        return ResponseHelper::success($business->fresh()->toApiArray(), 'Sender name requested');
    }

    public function withdraw(Request $request): JsonResponse
    {
        $business = $this->ownBusiness($request);
        if ($business instanceof JsonResponse) {
            return $business;
        }

        if ($business->sms_sender_status === 'approved') {
            return ResponseHelper::error(
                'Jina lako la mtumaji limeshaidhinishwa. Wasiliana na msimamizi ili libadilishwe. / '
                . 'Your sender name is already approved. Contact your administrator to change it.',
                422,
                ['code' => 'sender_locked']
            );
        }

        $before = $business->smsSenderSummary();
        $business->sms_sender_id = null;
        $business->sms_sender_status = 'none';
        $business->sms_sender_note = null;
        $business->sms_sender_requested_at = null;
        $business->sms_sender_approved_at = null;
        $business->save();

        $this->audit->record($request, 'business', null, 'sms_sender_withdrawn', $before, $business->smsSenderSummary(), "{$request->user()->name} withdrew the SMS sender name request of \"{$business->name}\"");

        return ResponseHelper::success($business->fresh()->toApiArray(), 'Request withdrawn');
    }

    // ------------------------------------------------------------------ helpers

    /** @return array<string, mixed> */
    private function payload(Business $b): array
    {
        return [
            'id' => $b->id,
            'name' => $b->name,
            'tin' => (string) $b->tin,
            'phone' => (string) $b->phone,
            'plan' => $b->plan,
            'owner' => $b->owner ? ['name' => $b->owner->name, 'phone_number' => $b->owner->phone_number] : null,
            'sms_sender' => $b->smsSenderDetails(),
        ];
    }

    private function problem(string $message): JsonResponse
    {
        return ResponseHelper::error($message, 422, ['code' => 'sender_invalid']);
    }

    private function clean(mixed $value): ?string
    {
        $text = trim((string) $value);

        return $text === '' ? null : $text;
    }

    /** The caller's own business if they own it, else the error response to send. */
    private function ownBusiness(Request $request): Business|JsonResponse
    {
        $user = $request->user();

        if (!in_array(strtolower((string) $user->role), User::ACCOUNT_HEAD_ROLES, true)) {
            return ResponseHelper::error(
                'Ni mmiliki wa biashara tu anayeweza kuomba jina la mtumaji. / Only the owner of the business can ask for a sender name.',
                403,
                ['code' => 'owner_only']
            );
        }

        return Business::forUser($user)
            ?? ResponseHelper::error('This account does not belong to a business.', 404, ['code' => 'no_business']);
    }

    /** Tell the owner, from the platform, that their name was approved or turned down. Never breaks the request. */
    private function tellOwner(Business $business, string $status): void
    {
        try {
            $phone = $business->owner?->phone_number ?: $business->phone;
            if (!$phone) {
                return;
            }

            $name = $business->sms_sender_id;
            $why = trim((string) $business->sms_sender_note);

            $message = $status === 'approved'
                ? "3 in One: Jina la mtumaji \"{$name}\" la \"{$business->name}\" limeidhinishwa. Ujumbe kwa wateja wako sasa utaonekana kutoka {$name}."
                    . " / The sender name \"{$name}\" for \"{$business->name}\" is approved. Your customers' texts now show {$name}."
                : "3 in One: Jina la mtumaji \"{$name}\" la \"{$business->name}\" halikukubaliwa." . ($why !== '' ? " {$why}." : '') . ' Tafadhali chagua jina jingine.'
                    . " / The sender name \"{$name}\" for \"{$business->name}\" was not approved." . ($why !== '' ? " {$why}." : '') . ' Please choose another name.';

            SmsService::send($phone, $message);
        } catch (\Throwable $e) {
            Log::warning('Could not text the owner about their sender name: ' . $e->getMessage());
        }
    }

    /** Tell the super admins that a business asked for a sender name. Never breaks the request. */
    private function tellSuperAdmins(Business $business): void
    {
        try {
            $message = "3 in One: \"{$business->name}\" imeomba jina la mtumaji \"{$business->sms_sender_id}\". Lisajili kisha liidhinishe kwenye programu."
                . " / \"{$business->name}\" asked for the SMS sender name \"{$business->sms_sender_id}\". Register it, then approve it in the app.";

            foreach (SuperAdminPhones::all() as $phone) {
                SmsService::send($phone, $message);
            }
        } catch (\Throwable $e) {
            Log::warning('Could not text the super admins about a sender name request: ' . $e->getMessage());
        }
    }
}
