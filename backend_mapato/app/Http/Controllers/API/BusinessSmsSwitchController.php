<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Models\Business;
use App\Models\User;
use App\Services\Inventory\AuditTrail;
use App\Support\SmsSwitchNotice;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use OpenApi\Attributes as OA;

/**
 * The master switch for a business's text messages (Settings > Notifications > SMS).
 *
 * Off: nothing the business sends goes out, in any service (receipts, debt reminders, summaries, low stock, campaigns, salon texts, rent
 * texts), until it is switched on again. Nothing is deleted: each text's own setting stays as it was and comes back with the switch.
 * Platform texts to a person about their own account (sign-in codes, password reset, billing) still go. Other businesses never notice.
 *
 * Two people can move it:
 *   - the OWNER of the business, for their own business (not staff);
 *   - a SUPER ADMIN, for any one business picked from the list. When the super admin switched it off, the owner cannot switch it back
 *     on: only a super admin can.
 *
 * Made hard to flip by accident: the password of whoever does it, and switching OFF also needs the word ZIMA typed. Every change is
 * written to the audit trail. Wrong passwords are throttled by the route.
 */
class BusinessSmsSwitchController extends Controller
{
    /** The word typed to switch the texts off. */
    public const CONFIRM_WORD = 'ZIMA';

    public function __construct(private readonly AuditTrail $audit)
    {
    }

    // ------------------------------------------------------------------ the owner, for their own business

    #[OA\Get(path: '/business/sms-switch', summary: 'Whether the text messages of the business are on, and whether the caller may change that', security: [['bearerAuth' => []]], tags: ['Business'], responses: [new OA\Response(response: 200, description: 'Success'), new OA\Response(response: 404, description: 'No business')])]
    public function show(Request $request): JsonResponse
    {
        $user = $request->user();
        $business = Business::forUser($user);
        if ($business === null) {
            return response()->json(['message' => 'This account does not belong to a business.', 'code' => 'no_business'], 404);
        }

        return response()->json(['data' => $this->payload($business, $this->isOwner($business, $user))]);
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
        responses: [new OA\Response(response: 200, description: 'Saved'), new OA\Response(response: 403, description: 'Only the owner, and not while the platform holds it off'), new OA\Response(response: 422, description: 'Wrong password or word')],
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
        if ($this->lockedByPlatform($business)) {
            return response()->json([
                'message' => 'SMS za biashara hii zimezimwa na msimamizi wa mfumo. Wasiliana naye ili ziwashwe. / The text messages of this business were switched off by the platform administrator. Contact them to switch them on.',
                'code' => 'paused_by_platform',
            ], 403);
        }

        $refused = $this->checkConfirmation($request, $user, $enable);
        if ($refused !== null) {
            return $refused;
        }

        $this->apply($request, $business, $user, $enable, byPlatform: false);

        return response()->json([
            'message' => $enable ? 'SMS zimewashwa. / Text messages are on.' : 'SMS zimezimwa. / Text messages are off.',
            'data' => $this->payload($business->fresh(), true),
        ]);
    }

    // ------------------------------------------------------------------ the super admin, for any one business

    #[OA\Get(path: '/admin/businesses/{id}/sms-switch', summary: 'The SMS switch of one business (super admin only)', security: [['bearerAuth' => []]], tags: ['Admin / Businesses'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function adminShow(string $id): JsonResponse
    {
        $business = Business::withoutAccountScope()->with('owner')->findOrFail($id);

        return response()->json(['data' => $this->adminPayload($business)]);
    }

    #[OA\Put(
        path: '/admin/businesses/{id}/sms-switch',
        summary: 'Switch the text messages of ONE business on or off (super admin only, with the super admin password; off also needs the word ZIMA)',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Businesses'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        requestBody: new OA\RequestBody(content: new OA\JsonContent(required: ['enabled', 'password'], properties: [
            new OA\Property(property: 'enabled', type: 'boolean'),
            new OA\Property(property: 'password', type: 'string'),
            new OA\Property(property: 'confirm', type: 'string', example: 'ZIMA'),
        ])),
        responses: [new OA\Response(response: 200, description: 'Saved'), new OA\Response(response: 422, description: 'Wrong password or word')],
    )]
    public function adminUpdate(Request $request, string $id): JsonResponse
    {
        $business = Business::withoutAccountScope()->with('owner')->findOrFail($id);

        $refused = $this->checkConfirmation($request, $request->user(), $enable);
        if ($refused !== null) {
            return $refused;
        }

        // The owner is told by text, under the platform's name, whenever the super admin really changed their SMS.
        if ($this->apply($request, $business, $request->user(), $enable, byPlatform: true)) {
            SmsSwitchNotice::send($business, $enable);
        }

        return response()->json([
            'message' => $enable ? 'SMS zimewashwa. / Text messages are on.' : 'SMS zimezimwa. / Text messages are off.',
            'data' => $this->adminPayload($business->fresh('owner')),
        ]);
    }

    // ------------------------------------------------------------------ helpers

    /** The password of the person acting, and (to switch OFF) the word ZIMA. Null when both are right; else the response to send. */
    private function checkConfirmation(Request $request, User $user, ?bool &$enable): ?JsonResponse
    {
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

        return null;
    }

    /** Move the switch. True when something changed (false when it already was as asked). */
    private function apply(Request $request, Business $business, User $user, bool $enable, bool $byPlatform): bool
    {
        $wasPaused = $business->smsPaused();
        $wasPlatform = $this->lockedByPlatform($business);
        $wantPaused = !$enable;
        $wantPlatform = $wantPaused && $byPlatform;
        if ($wasPaused === $wantPaused && $wasPlatform === $wantPlatform) {
            return false; // already as asked
        }

        $business->forceFill([
            'sms_paused' => !$enable,
            'sms_paused_at' => $enable ? null : ($wasPaused ? $business->sms_paused_at : now()),
            'sms_paused_by' => $enable ? null : (string) $user->id,
            'sms_paused_by_platform' => $wantPlatform,
        ])->save();

        $this->audit->record(
            $request,
            'business',
            null,
            $enable ? 'sms_switched_on' : 'sms_switched_off',
            ['sms_paused' => $wasPaused, 'by_platform' => $wasPlatform],
            ['sms_paused' => !$enable, 'by_platform' => !$enable && $byPlatform],
            "{$user->name} " . ($byPlatform ? '(super admin) ' : '') . ($enable ? 'switched ON' : 'switched OFF') . " the text messages of \"{$business->name}\"",
        );

        return true;
    }

    private function lockedByPlatform(Business $business): bool
    {
        return $business->smsPaused() && (bool) ($business->sms_paused_by_platform ?? false);
    }

    /** The owner of THIS business: its head, signed in as themself (not a staff member, not an admin made under it). */
    private function isOwner(Business $business, User $user): bool
    {
        return (string) $business->owner_id === (string) $user->id
            && in_array(strtolower((string) $user->role), User::ACCOUNT_HEAD_ROLES, true);
    }

    /** @return array<string, mixed> */
    private function payload(Business $business, bool $isOwner): array
    {
        $by = $business->sms_paused_by ? User::query()->withoutGlobalScopes()->find($business->sms_paused_by) : null;
        $locked = $this->lockedByPlatform($business);

        return [
            'enabled' => !$business->smsPaused(),
            'paused_at' => $business->sms_paused_at?->toIso8601String(),
            // Who switched it off. The owner is not told which super admin did it, only that it was the platform.
            'paused_by' => $locked ? null : $by?->name,
            'paused_by_platform' => $locked,
            'can_change' => $isOwner && !$locked,
            'confirm_word' => self::CONFIRM_WORD,
        ];
    }

    /** @return array<string, mixed> */
    private function adminPayload(Business $business): array
    {
        $by = $business->sms_paused_by ? User::query()->withoutGlobalScopes()->find($business->sms_paused_by) : null;

        return [
            'business_id' => $business->id,
            'business_name' => $business->name,
            'owner_name' => $business->owner?->name,
            'owner_email' => $business->owner?->email,
            'enabled' => !$business->smsPaused(),
            'paused_at' => $business->sms_paused_at?->toIso8601String(),
            'paused_by' => $by?->name,
            'paused_by_platform' => $this->lockedByPlatform($business),
            'can_change' => true,
            'confirm_word' => self::CONFIRM_WORD,
        ];
    }
}
