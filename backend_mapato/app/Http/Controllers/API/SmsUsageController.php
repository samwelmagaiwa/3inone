<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Models\Business;
use App\Models\User;
use App\Services\Inventory\AuditTrail;
use App\Support\SmsQuota;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use OpenApi\Attributes as OA;

/**
 * SMS used per business, against the limit the super admin sets (see App\Support\SmsQuota).
 *
 *   Owner        GET /business/sms-usage                 its own used / limit / left / this week (the ⋮ menu badge)
 *   Super admin  GET /admin/sms-usage                    every business with its counter
 *                GET /admin/sms-usage/{id}               one business: counter, this week, the texts of the last 3 days
 *                PUT /admin/sms-usage/{id}/limit         set the limit (null = none), optionally start the counter at 0 again
 */
class SmsUsageController extends Controller
{
    public function __construct(private readonly AuditTrail $audit)
    {
    }

    #[OA\Get(path: '/business/sms-usage', summary: 'SMS used by the signed-in owner\'s business against its limit', security: [['bearerAuth' => []]], tags: ['Business'], responses: [new OA\Response(response: 200, description: 'Success'), new OA\Response(response: 403, description: 'Only the owner')])]
    public function ownerShow(Request $request): JsonResponse
    {
        $user = $request->user();
        $business = Business::forUser($user);
        if ($business === null) {
            return response()->json(['message' => 'This account does not belong to a business.', 'code' => 'no_business'], 404);
        }
        if ((string) $business->owner_id !== (string) $user->id || !in_array(strtolower((string) $user->role), User::ACCOUNT_HEAD_ROLES, true)) {
            return response()->json(['message' => 'Ni mmiliki wa biashara tu. / Only the owner of the business.', 'code' => 'owner_only'], 403);
        }

        return response()->json(['data' => ['business_name' => $business->name] + SmsQuota::usage($business)]);
    }

    #[OA\Get(path: '/admin/sms-usage', summary: 'Every business with its SMS counter (super admin only)', security: [['bearerAuth' => []]], tags: ['Admin / SMS'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function adminIndex(Request $request): JsonResponse
    {
        // Business admins only: a business whose owner is a real, active, approved account head with at least one service.
        // Left out: a business record with no owner, an applicant who was never approved, a switched-off account.
        $query = Business::withoutAccountScope()->with('owner')->whereHas('owner', function ($owner) {
            $owner->whereIn('role', User::ACCOUNT_HEAD_ROLES)
                ->where('is_active', true)
                ->where(fn ($q) => $q->whereNull('is_applicant')->orWhere('is_applicant', false))
                ->whereHas('services');
        });
        if ($search = trim((string) $request->query('q', ''))) {
            $query->where(function ($q) use ($search) {
                $q->where('businesses.name', 'like', "%{$search}%")
                    ->orWhereHas('owner', function ($owner) use ($search) {
                        $owner->where('name', 'like', "%{$search}%")
                            ->orWhere('email', 'like', "%{$search}%")
                            ->orWhere('phone_number', 'like', "%{$search}%");
                    });
            });
        }

        $rows = $query->orderBy('name')->limit(500)->get()->map(fn (Business $b) => $this->row($b))->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Get(path: '/admin/sms-usage/{id}', summary: 'One business: SMS counter, this week and the texts of the last 3 days (super admin only)', security: [['bearerAuth' => []]], tags: ['Admin / SMS'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function adminShow(string $id): JsonResponse
    {
        $business = Business::withoutAccountScope()->with('owner')->findOrFail($id);

        return response()->json(['data' => $this->row($business) + [
            'log_days' => SmsQuota::LOG_DAYS,
            'recent' => SmsQuota::recent($business),
        ]]);
    }

    #[OA\Put(
        path: '/admin/sms-usage/{id}/limit',
        summary: 'Set the SMS limit of one business (super admin only)',
        description: 'sms_limit null = no limit. reset_used true starts the counter at 0 again (a new bundle was paid for). The owner is texted the new figures.',
        security: [['bearerAuth' => []]],
        tags: ['Admin / SMS'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        requestBody: new OA\RequestBody(content: new OA\JsonContent(properties: [
            new OA\Property(property: 'sms_limit', type: 'integer', nullable: true, example: 1000),
            new OA\Property(property: 'reset_used', type: 'boolean'),
        ])),
        responses: [new OA\Response(response: 200, description: 'Saved')],
    )]
    public function setLimit(Request $request, string $id): JsonResponse
    {
        $business = Business::withoutAccountScope()->with('owner')->findOrFail($id);
        $data = $request->validate([
            'sms_limit' => 'present|nullable|integer|min:0|max:100000000',
            'reset_used' => 'sometimes|boolean',
        ]);

        $before = SmsQuota::usage($business);
        $limit = $data['sms_limit'] === null ? null : (int) $data['sms_limit'];
        $fresh = SmsQuota::setLimit($business, $limit, $request->boolean('reset_used'));
        $after = SmsQuota::usage($fresh);

        $this->audit->record(
            $request, 'business', null, 'sms_limit_changed',
            ['used' => $before['used'], 'limit' => $before['limit']],
            ['used' => $after['used'], 'limit' => $after['limit']],
            "{$request->user()->name} set the SMS limit of \"{$business->name}\" to " . ($limit ?? 'no limit')
                . ($request->boolean('reset_used') ? ' and started its counter at 0' : '') . " ({$after['used']} used)",
        );

        return response()->json(['message' => 'Kikomo cha SMS kimehifadhiwa. / SMS limit saved.', 'data' => $this->row($fresh)]);
    }

    #[OA\Get(path: '/admin/users/{id}/sms-controls', summary: 'Every SMS control of the business this person owns, in one answer (super admin only)', security: [['bearerAuth' => []]], tags: ['Admin / SMS'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success'), new OA\Response(response: 404, description: 'Not a business owner')])]
    public function byOwner(string $id): JsonResponse
    {
        $user = User::query()->withoutGlobalScopes()->findOrFail($id);
        $business = Business::withoutAccountScope()->with('owner')->where('owner_id', (string) $user->id)->first();
        if ($user->isSuperAdmin() || $business === null) {
            return response()->json(['message' => 'Mtumiaji huyu si mmiliki wa biashara. / This person does not own a business.', 'code' => 'no_business'], 404);
        }
        $pausedBy = $business->sms_paused_by ? User::query()->withoutGlobalScopes()->find($business->sms_paused_by) : null;

        // The switch, the counter and limit, the sender name and the texts of the last 3 days. The changes go to the existing
        // endpoints with business_id: PUT /admin/businesses/{id}/sms-switch and PUT /admin/sms-usage/{id}/limit.
        return response()->json(['data' => $this->row($business) + [
            'switch' => [
                'enabled' => !$business->smsPaused(),
                'paused_at' => $business->sms_paused_at?->toIso8601String(),
                'paused_by' => $pausedBy?->name,
                'paused_by_platform' => $business->smsPaused() && (bool) ($business->sms_paused_by_platform ?? false),
                'confirm_word' => BusinessSmsSwitchController::CONFIRM_WORD,
            ],
            'sender' => $business->smsSenderSummary(),
            'log_days' => SmsQuota::LOG_DAYS,
            'recent' => SmsQuota::recent($business, 100),
        ]]);
    }

    /** @return array<string, mixed> */
    private function row(Business $b): array
    {
        return [
            'id' => $b->id,
            'name' => $b->name,
            'owner' => $b->owner ? ['name' => $b->owner->name, 'email' => $b->owner->email, 'phone_number' => $b->owner->phone_number] : null,
            'sms_paused' => $b->smsPaused(),
            'usage' => SmsQuota::usage($b),
        ];
    }
}
