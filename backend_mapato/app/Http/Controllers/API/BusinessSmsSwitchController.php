<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Models\Business;
use App\Models\User;
use App\Services\Inventory\AuditTrail;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use OpenApi\Attributes as OA;

/**
 * The owner's master switch for the business's text messages (Settings > Notifications > SMS).
 *
 * Off: nothing the business sends goes out, in any service (receipts, debt reminders, summaries, low stock, campaigns, salon texts, rent
 * texts), until it is switched on again. Nothing is deleted: each text's own setting stays as it was and comes back with the switch.
 * Platform texts to a person about their own account (sign-in codes, password reset, billing) still go.
 *
 * Made hard to flip by accident: only the owner of the business (not staff, not a super admin), only with the owner's password, and
 * switching OFF also needs the word ZIMA typed. Every change is written to the audit trail. Wrong passwords are throttled by the route.
 */
class BusinessSmsSwitchController extends Controller
{
    /** The word the owner types to switch the texts off. */
    public const CONFIRM_WORD = 'ZIMA';

    public function __construct(private readonly AuditTrail $audit)
    {
    }

    #[OA\Get(path: '/business/sms-switch', summary: 'Whether the text messages of the business are on, and whether the caller may change that', security: [['bearerAuth' => []]], tags: ['Business'], responses: [new OA\Response(response: 200, description: 'Success'), new OA\Response(response: 404, description: 'No business')])]
    public function show(Request $request): JsonResponse
    {
        $user = $request->user();
        $business = Business::forUser($user);
        if ($business === null) {
            return response()->json(['message' => 'This account does not belong to a business.', 'code' => 'no_business'], 404);
        }

        return response()->json(['data' => $this->payload($business, $user)]);
    }

    #[OA\Put(
        path: '/business/sms-switch',
        summary: 'Switch the text messages of the business on or off (owner only, with password; off also needs the word ZIMA)',
        security: [['bearerAuth' => []]],
        tags: ['Business'],
        requestBody: new OA\RequestBody(content: new OA\JsonContent(required: ['enabled', 'password'], properties: [
            new OA\Property(property: 'enabled', type: 'boolean'),
            new OA\Property(property: 'password', type: 'string'),
            new OA\Property(property: 'confirm', type: 'string', example: 'ZIMA'),
        ])),
        responses: [new OA\Response(response: 200, description: 'Saved'), new OA\Response(response: 403, description: 'Only the owner'), new OA\Response(response: 422, description: 'Wrong password or word')],
    )]
    public function update(Request $request): JsonResponse
    {
        $user = $request->user();
        $business = Business::forUser($user);
        if ($business === null) {
            return response()->json(['message' => 'This account does not belong to a business.', 'code' => 'no_business'], 404);
        }
        if (!$this->isOwner($business, $user)) {
            return response()->json([
                'message' => 'Ni mmiliki wa biashara tu anayeweza kuwasha au kuzima SMS. / Only the owner of the business can switch its text messages on or off.',
                'code' => 'owner_only',
            ], 403);
        }

        $data = $request->validate([
            'enabled' => 'required|boolean',
            'password' => 'required|string|max:255',
            'confirm' => 'nullable|string|max:20',
        ]);

        if (!Hash::check((string) $data['password'], (string) $user->password)) {
            return response()->json([
                'message' => 'Nenosiri si sahihi. / The password is wrong.',
                'errors' => ['password' => ['Nenosiri si sahihi. / The password is wrong.']],
            ], 422);
        }

        $enable = (bool) $data['enabled'];
        if (!$enable && strtoupper(trim((string) ($data['confirm'] ?? ''))) !== self::CONFIRM_WORD) {
            $word = 'Andika neno ' . self::CONFIRM_WORD . ' kuthibitisha. / Type the word ' . self::CONFIRM_WORD . ' to confirm.';

            return response()->json(['message' => $word, 'errors' => ['confirm' => [$word]]], 422);
        }

        $wasPaused = $business->smsPaused();
        if ($wasPaused === $enable) {
            $business->forceFill([
                'sms_paused' => !$enable,
                'sms_paused_at' => $enable ? null : now(),
                'sms_paused_by' => $enable ? null : (string) $user->id,
            ])->save();

            $this->audit->record(
                $request,
                'business',
                null,
                $enable ? 'sms_switched_on' : 'sms_switched_off',
                ['sms_paused' => $wasPaused],
                ['sms_paused' => !$enable],
                "{$user->name} " . ($enable ? 'switched ON' : 'switched OFF') . " the text messages of \"{$business->name}\"",
            );
        }

        return response()->json([
            'message' => $enable ? 'SMS zimewashwa. / Text messages are on.' : 'SMS zimezimwa. / Text messages are off.',
            'data' => $this->payload($business->fresh(), $user),
        ]);
    }

    /** The owner of THIS business: its head, signed in as themself (not a staff member, not an admin made under it). */
    private function isOwner(Business $business, User $user): bool
    {
        return (string) $business->owner_id === (string) $user->id
            && in_array(strtolower((string) $user->role), User::ACCOUNT_HEAD_ROLES, true);
    }

    /** @return array<string, mixed> */
    private function payload(Business $business, User $user): array
    {
        $by = $business->sms_paused_by ? User::query()->withoutGlobalScopes()->find($business->sms_paused_by) : null;

        return [
            'enabled' => !$business->smsPaused(),
            'paused_at' => $business->sms_paused_at?->toIso8601String(),
            'paused_by' => $by?->name,
            'can_change' => $this->isOwner($business, $user),
            'confirm_word' => self::CONFIRM_WORD,
        ];
    }
}
