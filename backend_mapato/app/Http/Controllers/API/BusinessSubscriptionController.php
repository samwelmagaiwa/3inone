<?php

namespace App\Http\Controllers\API;

use App\Helpers\ResponseHelper;
use App\Http\Controllers\Controller;
use App\Models\Business;
use App\Models\User;
use App\Services\Inventory\AuditTrail;
use App\Services\SmsService;
use App\Support\PlanCatalog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\Rule;
use OpenApi\Attributes as OA;

/**
 * The subscription of a business: what it paid, when it started and when it ends.
 *
 *   - Anyone who works for a business reads its subscription (GET /business/subscription); only the
 *     owner also sees the payments and their amounts. It stays reachable when the business is held
 *     back for non-payment, so the owner can always see why and what to do.
 *   - Only a super admin records a payment (POST /admin/businesses/{id}/payments). Recording one
 *     moves `valid_until` on and opens everything again at once; the owner is told by text message.
 */
class BusinessSubscriptionController extends Controller
{
    private const METHODS = ['cash', 'mobile_money', 'bank_transfer', 'cheque', 'other'];

    public function __construct(private readonly AuditTrail $audit)
    {
    }

    #[OA\Get(
        path: '/business/subscription',
        summary: 'The signed-in business\'s subscription: plan, start, end, status, and (owner only) payments',
        security: [['bearerAuth' => []]],
        tags: ['Business'],
        responses: [new OA\Response(response: 200, description: 'The subscription'), new OA\Response(response: 404, description: 'No business')],
    )]
    public function show(Request $request): JsonResponse
    {
        $business = Business::forUser($request->user());

        if ($business === null) {
            return ResponseHelper::error('This account does not belong to a business.', 404, ['code' => 'no_business']);
        }

        $isOwner = in_array(strtolower((string) $request->user()->role), User::ACCOUNT_HEAD_ROLES, true);

        return ResponseHelper::success(array_merge(
            ['business_name' => $business->name, 'is_owner' => $isOwner],
            $business->subscriptionPayload($isOwner),
        ));
    }

    #[OA\Get(
        path: '/admin/businesses/{id}/payments',
        summary: 'Every payment recorded for a business (super admin only)',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Businesses'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        responses: [new OA\Response(response: 200, description: 'The subscription with its payments')],
    )]
    public function adminIndex(string $id): JsonResponse
    {
        $business = Business::withoutAccountScope()->findOrFail($id);

        return ResponseHelper::success(array_merge(['business_name' => $business->name], $business->subscriptionPayload(true)));
    }

    #[OA\Post(
        path: '/admin/businesses/{id}/payments',
        summary: 'Record a payment and move the business\'s paid-until date on (super admin only)',
        description: 'Paying while covered adds time after the current end; paying after it ran out starts today. Give `months` (default 1) '
            . 'or the exact `valid_until` date. The owner is told by text message, and a held-back business is open again at once.',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Businesses'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        responses: [new OA\Response(response: 201, description: 'Recorded'), new OA\Response(response: 422, description: 'Validation failed')],
    )]
    public function adminStore(Request $request, string $id): JsonResponse
    {
        $business = Business::withoutAccountScope()->with('owner')->findOrFail($id);

        $data = $request->validate([
            'amount' => 'required|numeric|gt:0|max:99999999999',
            'currency' => 'nullable|string|max:8',
            'method' => ['nullable', 'string', Rule::in(self::METHODS)],
            'reference' => 'nullable|string|max:100',
            'paid_at' => 'nullable|date|before_or_equal:tomorrow',
            'plan' => ['nullable', 'string', Rule::in(config('billing.plans', []))],
            'months' => 'nullable|integer|min:1|max:60',
            'valid_until' => 'nullable|date|after:today',
            'note' => 'nullable|string|max:500',
        ], [
            'valid_until.after' => 'Tarehe ya mwisho lazima iwe baada ya leo. / The end date must be after today.',
            'amount.gt' => 'Kiasi lazima kiwe zaidi ya sifuri. / The amount must be more than zero.',
        ]);

        // A plan covers a number of services: basic one, standard two, premium all three. A payment may not put a
        // business on a plan smaller than the services it has (trial and free are not limited).
        $services = count($business->serviceTypes());
        $plan = $data['plan'] ?? (in_array($business->plan, ['trial', 'free', ''], true) ? PlanCatalog::planFor($services) : $business->plan);
        if (!PlanCatalog::covers($plan, $services)) {
            return ResponseHelper::error(
                PlanCatalog::tooSmallMessage($plan, $services),
                422,
                ['code' => 'plan_too_small', 'plan' => $plan, 'services' => $services, 'recommended' => PlanCatalog::planFor($services)]
            );
        }

        $before = ['plan' => $business->plan, 'valid_until' => $business->valid_until?->toDateString()];
        $payment = $business->recordPayment($data, $request->user());
        $business->refresh();
        $after = ['plan' => $business->plan, 'valid_until' => $business->valid_until?->toDateString()];

        $this->audit->record(
            $request, 'business', null, 'payment_recorded', $before, $after + ['amount' => $payment->amount, 'currency' => $payment->currency],
            "{$request->user()->name} recorded {$payment->currency} " . number_format($payment->amount) . " from \"{$business->name}\": plan {$after['plan']}, valid until {$after['valid_until']}",
        );

        $this->tellOwner($business, $payment);

        return ResponseHelper::success([
            'payment' => $payment->toApiArray(),
            'business' => $business->toApiArray(),
            'subscription' => $business->subscriptionPayload(true),
        ], 'Payment recorded', 201);
    }

    /** Text the owner that the payment arrived and until when the business is covered. Never breaks the request. */
    private function tellOwner(Business $business, \App\Models\BusinessPayment $payment): void
    {
        try {
            $phone = $business->owner?->phone_number ?: $business->phone;
            if (!$phone) {
                return;
            }

            $until = $business->valid_until?->format('d/m/Y');
            $amount = $payment->currency . ' ' . number_format($payment->amount);
            $message = '3 in One: Malipo ya ' . $amount . ' ya "' . $business->name . '" yamepokelewa. Usajili wako (' . $payment->plan . ') ni hadi ' . $until . '. Asante.'
                . ' / Payment of ' . $amount . ' for "' . $business->name . '" received. Your subscription (' . $payment->plan . ') runs until ' . $until . '. Thank you.';

            SmsService::send($phone, $message);
        } catch (\Throwable $e) {
            Log::warning('Could not text the owner about a recorded payment: ' . $e->getMessage());
        }
    }
}
