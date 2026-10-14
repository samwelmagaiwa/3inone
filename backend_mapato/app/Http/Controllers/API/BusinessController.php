<?php

namespace App\Http\Controllers\API;

use App\Helpers\ResponseHelper;
use App\Http\Controllers\Controller;
use App\Models\Business;
use App\Models\User;
use App\Services\Inventory\AuditTrail;
use App\Support\InventoryDefaults;
use App\Support\PlanCatalog;
use App\Support\Pagination;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use OpenApi\Attributes as OA;

/**
 * The business itself: its name, address, TIN, logo (what receipts and text messages say) and
 * its plan / valid_until.
 *
 *   - Anyone who works for a business can READ it (GET /business).
 *   - Only its owner edits the profile and the logo (PUT /business, POST /business/logo).
 *   - Only a super admin sees every business and changes plan / valid_until (admin/businesses).
 *     An owner can never change their own billing.
 */
class BusinessController extends Controller
{
    private const TIN_MESSAGE = 'TIN lazima iwe na tarakimu 9 (mfano 123-456-789). / TIN must have 9 digits (e.g. 123-456-789).';

    public function __construct(private readonly AuditTrail $audit)
    {
    }

    // ------------------------------------------------------------------ own business

    #[OA\Get(
        path: '/business',
        summary: 'The signed-in user\'s business',
        description: 'Name, address, TIN, logo, contact and billing (plan, valid_until, days left). 404 for a super admin, who belongs to no business.',
        security: [['bearerAuth' => []]],
        tags: ['Business'],
        responses: [new OA\Response(response: 200, description: 'The business'), new OA\Response(response: 404, description: 'No business')],
    )]
    public function show(Request $request): JsonResponse
    {
        $business = Business::forUser($request->user());

        if ($business === null) {
            return ResponseHelper::error('This account does not belong to a business.', 404, ['code' => 'no_business']);
        }

        return ResponseHelper::success($business->toApiArray());
    }

    #[OA\Put(
        path: '/business',
        summary: 'Edit the business profile (owner only)',
        security: [['bearerAuth' => []]],
        tags: ['Business'],
        requestBody: new OA\RequestBody(content: new OA\JsonContent(properties: [
            new OA\Property(property: 'name', type: 'string'),
            new OA\Property(property: 'address', type: 'string', nullable: true),
            new OA\Property(property: 'tin', type: 'string', nullable: true, example: '123-456-789'),
            new OA\Property(property: 'phone', type: 'string', nullable: true),
            new OA\Property(property: 'email', type: 'string', nullable: true),
        ])),
        responses: [new OA\Response(response: 200, description: 'Updated'), new OA\Response(response: 403, description: 'Only the owner')],
    )]
    public function update(Request $request): JsonResponse
    {
        $business = $this->ownBusiness($request);
        if ($business instanceof JsonResponse) {
            return $business;
        }

        $data = $request->validate($this->profileRules(), $this->messages());

        $this->applyProfile($business, $data, $request);

        return ResponseHelper::success($business->fresh()->toApiArray(), 'Business updated');
    }

    #[OA\Post(
        path: '/business/logo',
        summary: 'Upload the business logo (owner only)',
        description: 'Multipart field `logo`: jpg, png or webp, up to 2 MB.',
        security: [['bearerAuth' => []]],
        tags: ['Business'],
        responses: [new OA\Response(response: 200, description: 'Logo saved')],
    )]
    public function uploadLogo(Request $request): JsonResponse
    {
        $business = $this->ownBusiness($request);
        if ($business instanceof JsonResponse) {
            return $business;
        }

        $request->validate(['logo' => 'required|file|image|mimes:jpg,jpeg,png,webp|max:2048']);

        $file = $request->file('logo');
        $extension = $file->guessExtension() ?: 'png';
        // A random name: a logo is shown on receipts, but its address should not be guessable.
        $path = $file->storeAs('business_logos', $business->id . '_' . Str::random(16) . '.' . $extension, 'public');

        $previous = $business->logo_path;
        $business->logo_path = $path;
        $business->save();

        if ($previous && $previous !== $path) {
            Storage::disk('public')->delete($previous);
        }

        $this->audit->record($request, 'business', null, 'logo_changed', null, null, "{$request->user()->name} changed the logo of \"{$business->name}\"");

        return ResponseHelper::success($business->toApiArray(), 'Logo saved');
    }

    #[OA\Delete(
        path: '/business/logo',
        summary: 'Remove the business logo (owner only)',
        security: [['bearerAuth' => []]],
        tags: ['Business'],
        responses: [new OA\Response(response: 200, description: 'Logo removed')],
    )]
    public function removeLogo(Request $request): JsonResponse
    {
        $business = $this->ownBusiness($request);
        if ($business instanceof JsonResponse) {
            return $business;
        }

        if ($business->logo_path) {
            Storage::disk('public')->delete($business->logo_path);
            $business->logo_path = null;
            $business->save();
        }

        return ResponseHelper::success($business->toApiArray(), 'Logo removed');
    }

    // ------------------------------------------------------------------ super admin

    #[OA\Get(
        path: '/admin/businesses',
        summary: 'Every business with its owner, services and plan (super admin only)',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Businesses'],
        parameters: [
            new OA\Parameter(name: 'q', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'plan', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'status', in: 'query', description: 'all | expired | expiring (within 14 days) | no_expiry', schema: new OA\Schema(type: 'string', default: 'all')),
        ],
        responses: [new OA\Response(response: 200, description: 'Businesses with counts')],
    )]
    public function adminIndex(Request $request): JsonResponse
    {
        $query = Business::withoutAccountScope()->with('owner');

        if ($search = trim((string) $request->query('q', ''))) {
            $query->where(function ($q) use ($search) {
                $q->where('businesses.name', 'like', "%{$search}%")
                    ->orWhere('businesses.tin', 'like', "%{$search}%")
                    ->orWhereHas('owner', function ($owner) use ($search) {
                        $owner->where('name', 'like', "%{$search}%")
                            ->orWhere('email', 'like', "%{$search}%")
                            ->orWhere('phone_number', 'like', "%{$search}%");
                    });
            });
        }

        if ($plan = $request->query('plan')) {
            $query->where('plan', (string) $plan);
        }

        match ((string) $request->query('status', 'all')) {
            'expired' => $query->whereNotNull('valid_until')->where('valid_until', '<', now()),
            'expiring' => $query->whereBetween('valid_until', [now(), now()->addDays(14)]),
            'no_expiry' => $query->whereNull('valid_until'),
            default => null,
        };

        $page = $query->orderBy('name')->paginate(Pagination::perPage($request, 20));

        $all = Business::withoutAccountScope();

        return ResponseHelper::withMeta(
            $page->getCollection()->map(fn (Business $b) => $this->adminPayload($b))->values(),
            [
                'counts' => [
                    'total' => (clone $all)->count(),
                    'expired' => (clone $all)->whereNotNull('valid_until')->where('valid_until', '<', now())->count(),
                    'expiring' => (clone $all)->whereBetween('valid_until', [now(), now()->addDays(14)])->count(),
                ],
                'plans' => config('billing.plans', []),
                'pagination' => [
                    'current_page' => $page->currentPage(),
                    'last_page' => $page->lastPage(),
                    'per_page' => $page->perPage(),
                    'total' => $page->total(),
                    'has_more_pages' => $page->hasMorePages(),
                ],
            ],
            'Businesses retrieved successfully'
        );
    }

    #[OA\Get(
        path: '/admin/businesses/{id}',
        summary: 'One business (super admin only)',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Businesses'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        responses: [new OA\Response(response: 200, description: 'The business')],
    )]
    public function adminShow(string $id): JsonResponse
    {
        return ResponseHelper::success($this->adminPayload(Business::withoutAccountScope()->with('owner')->findOrFail($id)));
    }

    #[OA\Put(
        path: '/admin/businesses/{id}',
        summary: 'Edit a business\'s profile and billing (super admin only)',
        description: 'plan must be one of the configured plans; valid_until is a date (the business works through the end of that day) or null for no expiry.',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Businesses'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        responses: [new OA\Response(response: 200, description: 'Updated')],
    )]
    public function adminUpdate(Request $request, string $id): JsonResponse
    {
        $business = Business::withoutAccountScope()->with('owner')->findOrFail($id);

        $data = $request->validate(array_merge($this->profileRules(), [
            'plan' => ['sometimes', 'string', Rule::in(config('billing.plans', []))],
            'valid_until' => 'sometimes|nullable|date',
        ]), $this->messages());

        // Moving a business onto a plan that covers fewer services than it has is refused (trial and free have no limit).
        if (array_key_exists('plan', $data) && $data['plan'] !== $business->plan) {
            $services = count($business->serviceTypes());
            if (!PlanCatalog::covers($data['plan'], $services)) {
                return ResponseHelper::error(
                    PlanCatalog::tooSmallMessage($data['plan'], $services),
                    422,
                    ['code' => 'plan_too_small', 'plan' => $data['plan'], 'services' => $services, 'recommended' => PlanCatalog::planFor($services)]
                );
            }
        }

        $before = ['plan' => $business->plan, 'valid_until' => $business->valid_until?->toDateString()];

        $this->applyProfile($business, $data, $request);

        if (array_key_exists('plan', $data)) {
            $business->plan = $data['plan'];
        }
        if ($request->exists('valid_until')) {
            $business->valid_until = !empty($data['valid_until']) ? Carbon::parse($data['valid_until'])->endOfDay() : null;
        }
        $business->save();

        $after = ['plan' => $business->plan, 'valid_until' => $business->valid_until?->toDateString()];
        if ($before !== $after) {
            $this->audit->record(
                $request, 'business', null, 'billing_changed', $before, $after,
                "{$request->user()->name} set \"{$business->name}\" to plan {$after['plan']}, valid until " . ($after['valid_until'] ?? 'no expiry'),
            );
        }

        return ResponseHelper::success($this->adminPayload($business->fresh('owner')), 'Business updated');
    }

    // ------------------------------------------------------------------ helpers

    /** The caller's own business if they own it, else the error response to send. */
    private function ownBusiness(Request $request): Business|JsonResponse
    {
        $user = $request->user();

        if (!in_array(strtolower((string) $user->role), User::ACCOUNT_HEAD_ROLES, true)) {
            return ResponseHelper::error(
                'Only the owner of the business can change its details. / Ni mmiliki wa biashara tu anayeweza kubadili taarifa zake.',
                403,
                ['code' => 'owner_only']
            );
        }

        return Business::forUser($user)
            ?? ResponseHelper::error('This account does not belong to a business.', 404, ['code' => 'no_business']);
    }

    /** @return array<string, mixed> */
    private function profileRules(): array
    {
        return [
            'name' => 'sometimes|required|string|max:255',
            'address' => 'sometimes|nullable|string|max:500',
            'tin' => ['sometimes', 'nullable', 'string', 'max:20', 'regex:/^\d{3}[-\s]?\d{3}[-\s]?\d{3}$/'],
            'phone' => ['sometimes', 'nullable', 'string', 'max:30', 'regex:/^(0\d{9}|\+\d{9,15})$/'],
            'email' => 'sometimes|nullable|email|max:255',
            // What kind of stock business this is. Changing it only moves the inventory settings that
            // still hold the old kind's starting values; no stock, price or sale changes.
            'inventory_type' => ['sometimes', 'nullable', 'string', Rule::in(Business::inventoryTypes())],
        ];
    }

    /** @return array<string, string> */
    private function messages(): array
    {
        return [
            'tin.regex' => self::TIN_MESSAGE,
            'phone.regex' => 'Namba ya simu si sahihi. Tumia namba ya ndani (mfano: 0743519100) au ya kimataifa (mfano: +255743519100).',
        ];
    }

    /** Save the profile fields that were sent, keep inventory's receipt settings in step, and audit. */
    private function applyProfile(Business $business, array $data, Request $request): void
    {
        $before = $business->only(Business::PROFILE_FIELDS);

        foreach (Business::PROFILE_FIELDS as $field) {
            if (!array_key_exists($field, $data)) {
                continue;
            }

            $value = $data[$field];
            if ($field === 'tin' && $value !== null && $value !== '') {
                $digits = preg_replace('/\D/', '', (string) $value);
                $value = substr($digits, 0, 3) . '-' . substr($digits, 3, 3) . '-' . substr($digits, 6, 3);
            }
            $business->{$field} = ($value === '' ? null : $value);
        }

        if (!$business->isDirty()) {
            return;
        }

        $business->save();
        $after = $business->only(Business::PROFILE_FIELDS);

        // The depot's receipts carry the business's name, contact and TIN unless the owner has
        // typed something different there; see InventoryDefaults::syncFromBusiness().
        InventoryDefaults::syncFromBusiness($business, $before);
        InventoryDefaults::applyType($business, $before['inventory_type'] ?? null);

        $this->audit->record(
            $request, 'business', null, 'profile_changed', $before, $after,
            "{$request->user()->name} updated the details of \"{$business->name}\"",
        );
    }

    /** What the super admin's list and detail screens show. */
    private function adminPayload(Business $business): array
    {
        $owner = $business->owner;

        return array_merge($business->toApiArray(), [
            'owner' => $owner ? [
                'id' => $owner->id,
                'name' => $owner->name,
                'email' => $owner->email,
                'phone_number' => $owner->phone_number,
                'is_active' => (bool) $owner->is_active,
            ] : null,
            'services' => $owner ? $owner->serviceTypes() : [],
            'staff_count' => $owner
                ? User::query()->whereIn('created_by', $owner->accountMemberIds())->count()
                : 0,
        ]);
    }
}
