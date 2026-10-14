<?php

namespace App\Http\Controllers\API\Rental;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\Rental\TenantProfile;
use App\Models\Rental\RentalAgreement;
use App\Models\Rental\RentBill;
use App\Models\Rental\RentalPayment;
use App\Models\Rental\RentalReceipt;
use App\Models\Rental\House;
use App\Services\Rental\RentalService;
use App\Services\SmsService;
use App\Helpers\ResponseHelper;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

#[OA\Tag(name: 'Rental / Tenants', description: 'Tenant profiles, agreements, bills, and payments.')]
class TenantController extends Controller
{
    protected $rentalService;

    public function __construct(RentalService $rentalService)
    {
        $this->rentalService = $rentalService;
    }

    /**
     * List all tenants for landlord's properties.
     */
    #[OA\Get(
        path: '/rental/tenants',
        summary: "List tenants for the caller's properties",
        security: [['bearerAuth' => []]],
        tags: ['Rental / Tenants'],
        responses: [
            new OA\Response(response: 200, description: 'Tenant list'),
        ],
    )]
    public function index(Request $request)
    {
        $user = $request->user();

        $agreements = RentalAgreement::when(!$user->isSuperAdmin(), function ($aq) use ($user) {
            $aq->whereHas('house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->with('tenant.profile', 'house.property', 'house.block')->get();

        $tenants = $agreements->map(function ($agreement) {
            return [
                'id' => $agreement->tenant->id,
                'name' => $agreement->tenant->name,
                'email' => $agreement->tenant->email,
                'phone_number' => $agreement->tenant->phone_number,
                'profile' => $agreement->tenant->profile,
                'house' => [
                    'id' => $agreement->house->id,
                    'house_number' => $agreement->house->house_number,
                    'property_name' => $agreement->house->property->name,
                    'block_name' => $agreement->house->block?->name,
                    'rent_amount' => $agreement->rent_amount,
                ],
                'agreement' => [
                    'id' => $agreement->id,
                    'start_date' => $agreement->start_date,
                    'end_date' => $agreement->end_date,
                    'rent_cycle' => $agreement->rent_cycle,
                    'status' => $agreement->status,
                    'rent_amount' => $agreement->rent_amount,
                ],
            ];
        });

        return ResponseHelper::success($tenants);
    }

    /**
     * Search available system tenants
     */
    #[OA\Get(
        path: '/rental/tenants/system',
        summary: 'Available system tenants',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Tenants'],
        parameters: [
            new OA\Parameter(name: 'query', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function availableSystemTenants(Request $request)
    {
        $user = $request->user();
        $search = $request->query('query');

        // Return ONLY users created by this landlord who have the 'tenant' role
        // (super_admin sees every tenant regardless of who created them)
        $query = User::when(!$user->isSuperAdmin(), fn($q) => $q->whereIn('created_by', $user->accountMemberIds()))
            ->where('role', 'tenant');

        if ($search) {
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%$search%")
                    ->orWhere('email', 'like', "%$search%")
                    ->orWhere('phone_number', 'like', "%$search%");
            });
        }

        return ResponseHelper::success($query->limit(20)->get());
    }

    /**
     * Show single tenant details.
     */
    #[OA\Get(
        path: '/rental/tenants/{id}',
        summary: 'Get a single resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Tenants'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function show(Request $request, $id)
    {
        $isSuperAdmin = $request->user()->isSuperAdmin();

        $agreement = RentalAgreement::when(!$isSuperAdmin, function ($aq) use ($request) {
            $aq->whereHas('house.property', function ($query) use ($request) {
                $query->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->where('tenant_id', $id)
            ->with('tenant.profile', 'house.property', 'house.block', 'bills', 'payments.receipt')
            ->first();

        if ($agreement) {
            return ResponseHelper::success([
                'tenant' => $agreement->tenant,
                'profile' => $agreement->tenant->profile,
                'house' => $agreement->house,
                'agreement' => $agreement,
                'bills' => $agreement->bills,
                'payments' => $agreement->payments,
            ]);
        }

        // If no agreement exists, check if this is a valid tenant for this
        // landlord (super_admin can view any tenant, no ownership check).
        $tenantQuery = User::where('id', $id)->where('role', 'tenant');
        if (!$isSuperAdmin) {
            $tenantQuery->where(function ($query) use ($request) {
                $query->whereIn('created_by', $request->user()->accountMemberIds())
                    ->orWhereExists(function ($q) use ($request) {
                        $q->select(DB::raw(1))
                            ->from('rental_houses')
                            ->join('rental_properties', 'rental_houses.property_id', '=', 'rental_properties.id')
                            ->whereColumn('rental_houses.current_tenant_id', 'users.id')
                            ->where('rental_properties.owner_id', $request->user()->id);
                    });
            });
        }
        $tenant = $tenantQuery->with('profile')->firstOrFail();

        // Check if they are currently assigned to any house
        $house = House::where('current_tenant_id', $id)
            ->when(!$isSuperAdmin, function ($query) use ($request) {
                $query->whereHas('property', function ($q) use ($request) {
                    $q->whereIn('owner_id', $request->user()->accountMemberIds());
                });
            })->with('property', 'block')->first();

        return ResponseHelper::success([
            'tenant' => $tenant,
            'profile' => $tenant->profile,
            'house' => $house,
            'agreement' => null,
            'bills' => [],
            'payments' => [],
        ]);
    }

    /**
     * Onboard a new tenant.
     */
    #[OA\Post(
        path: '/rental/tenants/onboard',
        summary: 'Onboard',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Tenants'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['first_name', 'last_name', 'email', 'phone', 'rental_house_id', 'rent_amount'],
                properties: [
                new OA\Property(property: 'first_name', type: 'string'),
                new OA\Property(property: 'last_name', type: 'string'),
                new OA\Property(property: 'email', type: 'string', format: 'email'),
                new OA\Property(property: 'phone', type: 'string'),
                new OA\Property(property: 'rental_house_id', type: 'string'),
                new OA\Property(property: 'rent_amount', type: 'number'),
                new OA\Property(property: 'start_date', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'gender', type: 'string', nullable: true),
                new OA\Property(property: 'dob', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'nida', type: 'string', nullable: true),
                new OA\Property(property: 'emergency_contact', type: 'array', items: new OA\Items(type: 'string'), nullable: true),
                new OA\Property(property: 'id_details', type: 'array', items: new OA\Items(type: 'string'), nullable: true),
                new OA\Property(property: 'employment', type: 'array', items: new OA\Items(type: 'string'), nullable: true),
                new OA\Property(property: 'history', type: 'array', items: new OA\Items(type: 'string'), nullable: true),
                new OA\Property(property: 'occupants', type: 'array', items: new OA\Items(type: 'string'), nullable: true),
                new OA\Property(property: 'pets', type: 'array', items: new OA\Items(type: 'string'), nullable: true),
                new OA\Property(property: 'tenant_photo', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function onboard(Request $request)
    {
        $request->validate([
            'first_name' => 'required|string',
            'last_name' => 'required|string',
            'email' => 'required|email',
            'phone' => 'required|string',
            'rental_house_id' => 'required|exists:rental_houses,id',
            'rent_amount' => 'required|numeric',
            'start_date' => 'sometimes|date',
            'gender' => 'nullable|string',
            'dob' => 'nullable|date',
            'nida' => 'nullable|string',
            'emergency_contact' => 'nullable|array',
            'id_details' => 'nullable|array',
            'employment' => 'nullable|array',
            'history' => 'nullable|array',
            'occupants' => 'nullable|array',
            'pets' => 'nullable|array',
            'tenant_photo' => 'nullable|image|max:2048', // 2MB max
        ]);

        // `exists:` accepts any landlord's house; the house must be on a property
        // this account owns (super_admin may onboard into any).
        $actor = $request->user();
        $house = House::query()
            ->when(!$actor->seesAllAccounts(), fn ($q) => $q->whereHas(
                'property',
                fn ($p) => $p->whereIn('owner_id', $actor->accountMemberIds())
            ))
            ->findOrFail($request->rental_house_id);

        try {
            $data = $request->all();
            $data['created_by'] = $actor->id;

            // Multipart sends JSON arrays as strings, so we must decode them
            $jsonFields = ['emergency_contact', 'id_details', 'employment', 'history', 'occupants', 'pets'];
            foreach ($jsonFields as $field) {
                if (isset($data[$field]) && is_string($data[$field])) {
                    $decoded = json_decode($data[$field], true);
                    if (json_last_error() === JSON_ERROR_NONE) {
                        $data[$field] = $decoded;
                    }
                }
            }

            // Map common fields for backward compatibility or Service expected names
            $data['name'] = ($data['first_name'] ?? '') . ' ' . ($data['last_name'] ?? '');
            $data['phone_number'] = $data['phone'] ?? null;
            $data['house_id'] = $data['rental_house_id'] ?? null;

            // Handle Photo Upload
            if ($request->hasFile('tenant_photo')) {
                $path = \App\Support\PrivateFile::store($request->file('tenant_photo'), 'tenant_photos');
                $data['photo_url'] = $path;
            }
            $result = $this->rentalService->onboardTenant($data);

            // Send welcome SMS (the house was resolved and checked above; the app
            // sends `rental_house_id`, not `house_id`).
            // From the landlord's business, under its own registered sender name when it has one.
            SmsService::sendTenantWelcome(
                $result['user'],
                $house,
                \App\Models\Business::forProperty($house->property) ?? \App\Models\Business::identityForProperty($house->property),
            );

            return ResponseHelper::success($result, 'Tenant onboarded successfully', 201);
        } catch (\InvalidArgumentException $e) {
            return ResponseHelper::error($e->getMessage(), 422);
        } catch (\Exception $e) {
            return ResponseHelper::error($e->getMessage(), 500);
        }
    }

    /**
     * Update tenant status (active, notice, terminated, defaulter).
     */
    #[OA\Put(
        path: '/rental/tenants/{id}/status',
        summary: 'Update status',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Tenants'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['status'],
                properties: [
                new OA\Property(property: 'status', type: 'string', enum: ['active', 'notice', 'terminated', 'defaulter']),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function updateStatus(Request $request, $id)
    {
        $request->validate([
            'status' => 'required|in:active,notice,terminated,defaulter',
        ]);

        $isSuperAdmin = $request->user()->isSuperAdmin();

        $agreement = RentalAgreement::when(!$isSuperAdmin, function ($aq) use ($request) {
            $aq->whereHas('house.property', function ($query) use ($request) {
                $query->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->where('tenant_id', $id)->first();

        if ($agreement) {
            $agreement->update(['status' => $request->status]);

            // If terminated, free up the house
            if ($request->status === 'terminated') {
                $agreement->house->update(['status' => 'vacant', 'current_tenant_id' => null]);
            }
        } else {
            // No agreement, but if terminating, free up the house
            if ($request->status === 'terminated') {
                $house = House::when(!$isSuperAdmin, function ($query) use ($request) {
                    $query->whereHas('property', function ($q) use ($request) {
                        $q->whereIn('owner_id', $request->user()->accountMemberIds());
                    });
                })->where('current_tenant_id', $id)->first();

                if ($house) {
                    $house->update(['status' => 'vacant', 'current_tenant_id' => null]);
                } else {
                    return ResponseHelper::error('Tenant agreement not found', 404);
                }
            } else {
                return ResponseHelper::error('Tenant agreement not found', 404);
            }
        }

        return ResponseHelper::success($agreement, 'Tenant status updated');
    }

    /**
     * Terminate tenant (delete agreement).
     */
    #[OA\Delete(
        path: '/rental/tenants/{id}',
        summary: 'Terminate',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Tenants'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function terminate(Request $request, $id)
    {
        $isSuperAdmin = $request->user()->isSuperAdmin();

        $agreement = RentalAgreement::when(!$isSuperAdmin, function ($aq) use ($request) {
            $aq->whereHas('house.property', function ($query) use ($request) {
                $query->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->where('tenant_id', $id)->first();

        if ($agreement) {
            // Free up the house
            $agreement->house->update(['status' => 'vacant', 'current_tenant_id' => null]);

            // Delete the agreement
            $agreement->delete();
        } else {
            // If there's no agreement, but there's a house currently occupied by this tenant
            $house = House::when(!$isSuperAdmin, function ($query) use ($request) {
                $query->whereHas('property', function ($q) use ($request) {
                    $q->whereIn('owner_id', $request->user()->accountMemberIds());
                });
            })->where('current_tenant_id', $id)->first();

            if ($house) {
                $house->update(['status' => 'vacant', 'current_tenant_id' => null]);
            } else {
                // If there's no agreement and no house, but the user is a tenant, check access
                $user = User::where('id', $id)
                    ->where('role', 'tenant')
                    ->when(!$isSuperAdmin, fn($q) => $q->whereIn('created_by', $request->user()->accountMemberIds()))
                    ->first();

                if (!$user) {
                    return ResponseHelper::error('Tenant not found', 404);
                }
            }
        }

        return ResponseHelper::success(null, 'Tenant terminated successfully');
    }

    // ========== Tenant Self-Service Endpoints ==========

    /**
     * Get tenant's own bills.
     */
    #[OA\Get(
        path: '/rental/tenant/bills',
        summary: 'My bills',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Tenants'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function myBills(Request $request)
    {
        $bills = RentBill::whereHas('agreement', function ($query) use ($request) {
            $query->where('tenant_id', $request->user()->id);
        })->with('agreement.house.property')->get();

        return ResponseHelper::success($bills);
    }

    /**
     * Get tenant's own payments.
     */
    #[OA\Get(
        path: '/rental/tenant/payments',
        summary: 'My payments',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Tenants'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function myPayments(Request $request)
    {
        $payments = RentalPayment::where('tenant_id', $request->user()->id)
            ->with('bill.agreement.house.property', 'receipt', 'collector')
            ->orderBy('payment_date', 'desc')
            ->get();

        return ResponseHelper::success($payments);
    }

    /**
     * Get tenant's own receipts.
     */
    #[OA\Get(
        path: '/rental/tenant/receipts',
        summary: 'My receipts',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Tenants'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function myReceipts(Request $request)
    {
        $receipts = RentalReceipt::where('is_dispatched', true)
            ->whereHas('payment', function ($query) use ($request) {
                $query->where('tenant_id', $request->user()->id);
            })
            ->with('payment.bill.agreement.house.property', 'payment.tenant', 'payment.collector')
            ->orderBy('created_at', 'desc')->get();

        return ResponseHelper::success($receipts);
    }
}
