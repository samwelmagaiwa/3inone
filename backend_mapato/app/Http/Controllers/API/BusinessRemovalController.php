<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Models\Business;
use App\Models\User;
use App\Services\Inventory\AuditTrail;
use App\Support\BusinessRemoval;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use OpenApi\Attributes as OA;

/**
 * Super admin: remove a whole business (Users & access > a business admin > "Remove this business").
 *
 *   GET  /admin/users/{id}/business-removal   what would go: the business, its people, its rows table by table (nothing changes),
 *                                             and a one-time confirmation code made up for this removal (15 minutes)
 *   POST /admin/users/{id}/business-removal   remove it: needs that code typed back, the super admin's password and a reason
 *
 * Before anything is deleted a full snapshot of the database is written (listed under Backup, restorable like any backup); if it cannot
 * be written nothing is deleted. The removal itself is all or nothing. The audit trail and the server log keep who, what and why.
 */
class BusinessRemovalController extends Controller
{
    /** The letters a confirmation code is made of: no 0/O, 1/I/L, so it is read and typed back without doubt. */
    private const CODE_LETTERS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

    private const CODE_LENGTH = 6;

    private const CODE_MINUTES = 15;

    public function __construct(private readonly AuditTrail $audit)
    {
    }

    #[OA\Get(path: '/admin/users/{id}/business-removal', summary: 'What removing this owner\'s business would delete, and a one-time code to confirm it (super admin only)', security: [['bearerAuth' => []]], tags: ['Admin / Users'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))], responses: [new OA\Response(response: 200, description: 'Success'), new OA\Response(response: 404, description: 'Not a business owner')])]
    public function show(Request $request, string $id): JsonResponse
    {
        $business = $this->businessOf($id);
        if ($business instanceof JsonResponse) {
            return $business;
        }

        // A new code each time the warning is opened: it only works for this super admin, this business and the next 15 minutes.
        $code = '';
        for ($i = 0; $i < self::CODE_LENGTH; $i++) {
            $code .= self::CODE_LETTERS[random_int(0, strlen(self::CODE_LETTERS) - 1)];
        }
        Cache::put($this->codeKey($request, $id), $code, now()->addMinutes(self::CODE_MINUTES));

        return response()->json(['data' => BusinessRemoval::plan($business) + ['confirm_word' => $code, 'confirm_minutes' => self::CODE_MINUTES]]);
    }

    #[OA\Post(
        path: '/admin/users/{id}/business-removal',
        summary: 'Remove this owner\'s whole business: the business, its people and its data (super admin only; the code from GET, password, reason)',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Users'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        requestBody: new OA\RequestBody(content: new OA\JsonContent(required: ['confirm', 'password', 'reason'], properties: [
            new OA\Property(property: 'confirm', type: 'string', example: 'K7QX3M'),
            new OA\Property(property: 'password', type: 'string'),
            new OA\Property(property: 'reason', type: 'string'),
        ])),
        responses: [new OA\Response(response: 200, description: 'Removed'), new OA\Response(response: 422, description: 'Wrong code, password or no reason')],
    )]
    public function destroy(Request $request, string $id): JsonResponse
    {
        $admin = $request->user();
        $business = $this->businessOf($id);
        if ($business instanceof JsonResponse) {
            return $business;
        }

        $data = $request->validate([
            'confirm' => 'required|string|max:20',
            'password' => 'required|string|max:255',
            'reason' => 'required|string|min:5|max:500',
        ], [
            'reason.required' => 'Andika sababu ya kuifuta biashara hii. / Write why this business is being removed.',
            'reason.min' => 'Andika sababu kwa ufupi (angalau herufi 5). / Write the reason in a few words (at least 5 letters).',
        ]);

        $expected = Cache::get($this->codeKey($request, $id));
        if (!is_string($expected) || $expected === '') {
            $word = 'Msimbo wa kuthibitisha umekwisha muda. Fungua onyo tena upate msimbo mpya. / The confirmation code has expired. Open the warning again for a new code.';

            return response()->json(['message' => $word, 'errors' => ['confirm' => [$word]]], 422);
        }
        if (!hash_equals($expected, trim((string) $data['confirm']))) {
            $word = 'Andika msimbo ' . $expected . ' kama ulivyoonyeshwa. / Type the code ' . $expected . ' exactly as shown.';

            return response()->json(['message' => $word, 'errors' => ['confirm' => [$word]]], 422);
        }
        if (!Hash::check((string) $data['password'], (string) $admin->password)) {
            return response()->json([
                'message' => 'Nenosiri si sahihi. / The password is wrong.',
                'errors' => ['password' => ['Nenosiri si sahihi. / The password is wrong.']],
            ], 422);
        }

        $reason = trim((string) $data['reason']);
        $plan = BusinessRemoval::plan($business);
        Cache::forget($this->codeKey($request, $id)); // used once

        // A full snapshot first: without it, nothing is deleted.
        try {
            $snapshot = app(BackupController::class)->safetySnapshot('before_removing_business');
        } catch (\Throwable $e) {
            Log::error('Business removal stopped: the safety snapshot failed: ' . $e->getMessage());

            return response()->json(['message' => 'Nakala ya usalama haikuweza kuandikwa, hivyo hakuna kilichofutwa. / The safety backup could not be written, so nothing was removed.'], 500);
        }

        try {
            $result = BusinessRemoval::remove($business);
        } catch (\Throwable $e) {
            Log::error('Business removal failed, nothing removed: ' . $e->getMessage(), ['business_id' => $business->id]);

            return response()->json(['message' => 'Biashara haikufutwa: ' . $e->getMessage() . ' / The business was not removed.'], 500);
        }

        $summary = "{$admin->name} (super admin) REMOVED the business \"{$business->name}\" (owner " . ($plan['business']['owner'] ?? '-') . ', '
            . count($plan['users']) . ' account(s), ' . array_sum($result['tables']) . " row(s)). Reason: {$reason}. Safety backup: {$snapshot['filename']}";
        $this->audit->record($request, 'business', null, 'business_removed', $plan['business'] + ['users' => $plan['users']], null, $summary);
        Log::warning($summary);

        return response()->json([
            'message' => 'Biashara imefutwa. / The business was removed.',
            'data' => [
                'business' => $plan['business'],
                'users_removed' => count($plan['users']),
                'rows_removed' => $result['tables'],
                'reason' => $reason,
                'safety_backup' => $snapshot['filename'],
            ],
        ]);
    }

    private function codeKey(Request $request, string $userId): string
    {
        return 'business-removal-code:' . $request->user()->id . ':' . $userId;
    }

    /** The business this user owns, or the response to send. */
    private function businessOf(string $userId): Business|JsonResponse
    {
        $user = User::query()->withoutGlobalScopes()->findOrFail($userId);
        $business = Business::withoutAccountScope()->with('owner')->where('owner_id', (string) $user->id)->first();
        if ($user->isSuperAdmin() || $business === null) {
            return response()->json([
                'message' => 'Mtumiaji huyu si mmiliki wa biashara. / This person does not own a business.',
                'code' => 'no_business',
            ], 404);
        }

        return $business;
    }
}
