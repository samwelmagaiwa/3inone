<?php

namespace App\Http\Controllers\API\Rental;

use App\Http\Controllers\Controller;
use App\Support\Pagination;
use App\Support\TemporaryPassword;
use App\Models\Rental\MaintenanceRequest;
use App\Models\Rental\WorkOrder;
use App\Models\Rental\Vendor;
use App\Models\Rental\PreventiveMaintenance;
use App\Models\Rental\Property;
use App\Models\Rental\House;
use App\Models\Rental\RentalAgreement;
use App\Models\User;
use App\Http\Resources\MaintenanceRequestResource;
use App\Http\Resources\WorkOrderResource;
use App\Http\Resources\VendorResource;
use App\Helpers\ResponseHelper;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Carbon;
use OpenApi\Attributes as OA;

class MaintenanceController extends Controller
{
    /**
     * Maintenance requests the caller may see:
     *  - super_admin: all;
     *  - vendor: only those with a work order assigned to their vendor profile;
     *  - tenant: only their own;
     *  - caretaker: those on properties they are assigned to;
     *  - everyone else (landlord, admin, their staff): those on properties the
     *    account owns. An admin is not exempt -- they see their own account only.
     */
    private function visibleRequests(Request $request)
    {
        $user = $request->user();
        $query = MaintenanceRequest::query();

        if ($user->isSuperAdmin()) {
            return $query;
        }

        return match ($user->role) {
            'vendor' => $query->whereHas('workOrder.vendor', fn ($v) => $v->where('user_id', $user->id)),
            'tenant' => $query->where('tenant_id', $user->id),
            'caretaker' => $query->whereHas('property', fn ($p) => $p->where('caretaker_id', $user->id)),
            default => $query->whereHas('property', fn ($p) => $p->whereIn('owner_id', $user->accountMemberIds())),
        };
    }

    /**
     * Can this user open or raise work on the given property? (Owner/staff: the
     * account owns it; caretaker: assigned to it; tenant: has a lease there.)
     */
    private function canWorkOn(User $user, string $propertyId): bool
    {
        if ($user->isSuperAdmin()) {
            return Property::whereKey($propertyId)->exists();
        }

        return match ($user->role) {
            'tenant' => RentalAgreement::where('tenant_id', $user->id)
                ->whereIn('status', ['active', 'notice', 'defaulter'])
                ->whereHas('house', fn ($h) => $h->where('property_id', $propertyId))
                ->exists(),
            'caretaker' => Property::whereKey($propertyId)->where('caretaker_id', $user->id)->exists(),
            'vendor' => false,
            default => Property::whereKey($propertyId)->whereIn('owner_id', $user->accountMemberIds())->exists(),
        };
    }

    /**
     * The saved-vendor roster belongs to the account, not the individual: it is
     * kept on the account head so staff and the head share one list.
     */
    private function rosterOwner(User $user): User
    {
        $headId = $user->accountHeadId();

        return $headId === (string) $user->id ? $user : (User::find($headId) ?? $user);
    }

    /**
     * List all maintenance requests.
     */
    #[OA\Get(
        path: '/rental/maintenance/requests',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Maintenance'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function index(Request $request)
    {
        $query = $this->visibleRequests($request)
            ->with(['property', 'house', 'tenant', 'workOrder.vendor']);

        if ($request->has('status')) {
            $query->where('status', $request->status);
        }

        if ($request->has('property_id')) {
            $query->where('property_id', $request->property_id);
        }

        $requests = $query->latest()->paginate(Pagination::perPage($request, 15));

        return ResponseHelper::paginate($requests, MaintenanceRequestResource::class);
    }

    /**
     * Store a new maintenance request.
     */
    #[OA\Post(
        path: '/rental/maintenance/requests',
        summary: 'Create a resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Maintenance'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['property_id', 'category', 'priority', 'description'],
                properties: [
                new OA\Property(property: 'property_id', type: 'string'),
                new OA\Property(property: 'house_id', type: 'string', nullable: true),
                new OA\Property(property: 'category', type: 'string'),
                new OA\Property(property: 'priority', type: 'string', enum: ['low', 'medium', 'high', 'emergency']),
                new OA\Property(property: 'description', type: 'string'),
                new OA\Property(property: 'photo', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function store(Request $request)
    {
        $request->validate([
            'property_id' => 'required|exists:rental_properties,id',
            'house_id' => 'nullable|exists:rental_houses,id',
            'category' => 'required|string',
            'priority' => 'required|in:low,medium,high,emergency',
            'description' => 'required|string',
            'photo' => 'nullable|image|max:5120', // 5MB max
        ]);

        // `exists:` accepts any property in the system; the caller must actually
        // be able to work on this one (own it, be assigned to it, or lease there).
        if (!$this->canWorkOn($request->user(), (string) $request->property_id)) {
            return ResponseHelper::error('Property not found', 404);
        }
        if ($request->house_id
            && !House::whereKey($request->house_id)->where('property_id', $request->property_id)->exists()) {
            return ResponseHelper::error('That unit does not belong to the selected property', 422);
        }

        $data = $request->all();
        $data['tenant_id'] = $request->user()->id;
        $data['status'] = 'open';

        if ($request->hasFile('photo')) {
            $path = \App\Support\PrivateFile::store($request->file('photo'), 'maintenance');
            $data['photo_url'] = $path;
        }

        $maintenanceRequest = MaintenanceRequest::create($data);

        return ResponseHelper::success(
            new MaintenanceRequestResource($maintenanceRequest),
            'Ombi la matengenezo limepokelewa',
            201
        );
    }

    /**
     * Show a single maintenance request.
     */
    #[OA\Get(
        path: '/rental/maintenance/requests/{id}',
        summary: 'Get a single resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Maintenance'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function show(Request $request, string $id)
    {
        $maintenanceRequest = $this->visibleRequests($request)
            ->with(['property', 'house', 'tenant', 'workOrder.vendor'])
            ->findOrFail($id);

        return ResponseHelper::success(new MaintenanceRequestResource($maintenanceRequest));
    }

    /**
     * Assign a vendor and create a work order.
     */
    #[OA\Post(
        path: '/rental/maintenance/requests/{id}/assign',
        summary: 'Assign',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Maintenance'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['vendor_id', 'title'],
                properties: [
                new OA\Property(property: 'vendor_id', type: 'string'),
                new OA\Property(property: 'title', type: 'string'),
                new OA\Property(property: 'instructions', type: 'string', nullable: true),
                new OA\Property(property: 'estimated_cost', type: 'number', nullable: true),
                new OA\Property(property: 'scheduled_date', type: 'string', format: 'date', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function assign(Request $request, string $id)
    {
        $maintenanceRequest = $this->visibleRequests($request)->findOrFail($id);

        $request->validate([
            'vendor_id' => 'required|exists:rental_vendors,id',
            'title' => 'required|string',
            'instructions' => 'nullable|string',
            'estimated_cost' => 'nullable|numeric|min:0',
            'scheduled_date' => 'nullable|date',
        ]);

        $workOrder = WorkOrder::updateOrCreate(
            ['maintenance_request_id' => $id],
            [
                'vendor_id' => $request->vendor_id,
                'title' => $request->title,
                'instructions' => $request->instructions,
                'estimated_cost' => $request->estimated_cost ?? 0,
                'scheduled_date' => $request->scheduled_date,
                'status' => 'scheduled',
            ]
        );

        $maintenanceRequest->update(['status' => 'pending']);

        return ResponseHelper::success(
            new WorkOrderResource($workOrder->load('vendor')),
            'Fundi amepangiwa kazi'
        );
    }

    /**
     * Update request/work order status.
     */
    #[OA\Put(
        path: '/rental/maintenance/requests/{id}/status',
        summary: 'Update status',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Maintenance'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['status'],
                properties: [
                new OA\Property(property: 'status', type: 'string', enum: ['open', 'pending', 'in_progress', 'resolved', 'cancelled']),
                new OA\Property(property: 'actual_cost', type: 'number', nullable: true),
                new OA\Property(property: 'completion_date', type: 'string', format: 'date', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function updateStatus(Request $request, string $id)
    {
        $maintenanceRequest = $this->visibleRequests($request)->findOrFail($id);

        if ($request->user()->role === 'vendor') {
            if (!$maintenanceRequest->workOrder || !$maintenanceRequest->workOrder->vendor || $maintenanceRequest->workOrder->vendor->user_id !== $request->user()->id) {
                return ResponseHelper::error('Hauruhusiwi kubadilisha hali ya kazi hii.', 403);
            }
        }

        $request->validate([
            'status' => 'required|in:open,pending,in_progress,resolved,cancelled',
            'actual_cost' => 'nullable|numeric|min:0',
            'completion_date' => 'nullable|date',
        ]);

        $maintenanceRequest->update([
            'status' => $request->status,
            'resolved_at' => $request->status === 'resolved' ? now() : $maintenanceRequest->resolved_at,
        ]);

        if ($maintenanceRequest->workOrder) {
            $woStatus = match ($request->status) {
                'resolved' => 'completed',
                'cancelled' => 'cancelled',
                'in_progress' => 'in_progress',
                default => $maintenanceRequest->workOrder->status
            };

            $maintenanceRequest->workOrder->update([
                'status' => $woStatus,
                'actual_cost' => $request->actual_cost ?? $maintenanceRequest->workOrder->actual_cost,
                'completion_date' => $request->completion_date ?? $maintenanceRequest->workOrder->completion_date,
            ]);
        }

        return ResponseHelper::success(
            new MaintenanceRequestResource($maintenanceRequest->load('workOrder')),
            'Hali imesasishwa'
        );
    }

    /**
     * Vendor management methods.
     */
    #[OA\Get(
        path: '/rental/maintenance/vendors',
        summary: 'Get vendors',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Maintenance'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getVendors(Request $request)
    {
        $user = $request->user();

        if ($user->role === 'tenant') {
            $landlordId = Property::whereHas('houses.rentalAgreements', function ($q) use ($user) {
                $q->where('tenant_id', $user->id);
            })->value('owner_id');

            if (!$landlordId)
                return ResponseHelper::success([]);

            $vendors = Vendor::whereHas('landlords', function ($q) use ($landlordId) {
                $q->where('landlord_id', $landlordId);
            })->where('is_active', true)->get();

            return ResponseHelper::success(VendorResource::collection($vendors));
        }

        if ($user->isSuperAdmin()) {
            $vendors = Vendor::where('is_active', true)->get();
            return ResponseHelper::success(VendorResource::collection($vendors));
        }

        // Landlords, admins, caretakers and staff get their account's saved roster
        // (kept on the account head). An admin no longer sees every vendor in the
        // system -- the shared marketplace has its own endpoint.
        $vendors = $this->rosterOwner($user)->savedVendors()->where('is_active', true)->get();
        return ResponseHelper::success(VendorResource::collection($vendors));
    }

    #[OA\Get(

        path: '/rental/maintenance/marketplace/vendors',

        summary: 'Get marketplace vendors',

        security: [['bearerAuth' => []]],

        tags: ['Rental / Maintenance'],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function getMarketplaceVendors(Request $request)
    {
        // Public marketplace returns global vendors
        $vendors = Vendor::where('is_global', true)->where('is_active', true)->get();
        return ResponseHelper::success(VendorResource::collection($vendors));
    }

    #[OA\Post(

        path: '/rental/maintenance/vendors/{id}/save',

        summary: 'Save to roster',

        security: [['bearerAuth' => []]],

        tags: ['Rental / Maintenance'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function saveToRoster(Request $request, $id)
    {
        $vendor = Vendor::findOrFail($id);
        $this->rosterOwner($request->user())->savedVendors()->syncWithoutDetaching([$vendor->id]);
        return ResponseHelper::success(null, 'Fundi ameongezwa kwenye orodha yako');
    }

    #[OA\Post(

        path: '/rental/maintenance/vendors/{id}/remove',

        summary: 'Remove from roster',

        security: [['bearerAuth' => []]],

        tags: ['Rental / Maintenance'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function removeFromRoster(Request $request, $id)
    {
        $vendor = Vendor::findOrFail($id);
        $this->rosterOwner($request->user())->savedVendors()->detach($vendor->id);
        return ResponseHelper::success(null, 'Fundi ameondolewa kwenye orodha yako');
    }

    #[OA\Post(

        path: '/rental/maintenance/vendors',

        summary: 'Store vendor',

        security: [['bearerAuth' => []]],

        tags: ['Rental / Maintenance'],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['name', 'phone'],
                properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'phone', type: 'string'),
                new OA\Property(property: 'specialty', type: 'string', nullable: true),
                new OA\Property(property: 'experience', type: 'string', nullable: true),
                new OA\Property(property: 'business_name', type: 'string', nullable: true),
                new OA\Property(property: 'email', type: 'string', format: 'email', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function storeVendor(Request $request)
    {
        $request->validate([
            'name' => 'required|string',
            'phone' => 'required|string',
            'specialty' => 'nullable|string',
            'experience' => 'nullable|string',
            'business_name' => 'nullable|string',
            'email' => 'nullable|email',
        ]);

        $phone = $request->phone;

        // Vendors are a shared marketplace. When one already exists for this phone
        // number, reuse it as it is: adding a vendor must never overwrite another
        // account's vendor record or change who created it -- it only joins this
        // account's roster.
        $existing = Vendor::where('phone', $phone)->first();
        if ($existing) {
            $this->rosterOwner($request->user())->savedVendors()->syncWithoutDetaching([$existing->id]);

            return ResponseHelper::success(new VendorResource($existing), 'Fundi ameongezwa');
        }

        // Find existing user or create a new one. The email is the sign-in name, so it finds the
        // same person whoever asks. A phone number only finds another FUNDI: a business's driver,
        // tenant or staff may share the number, and must never be turned into a vendor's login.
        $user = \App\Models\User::query()
            ->where(function ($query) use ($request, $phone) {
                $query->where(function ($byPhone) use ($phone) {
                    $byPhone->where('role', 'vendor')->where('phone_number', $phone);
                });
                if ($request->email) {
                    $query->orWhere('email', $request->email);
                }
            })->first();

        // Set only when this call creates the sign-in for the fundi: a one-time password,
        // returned once so it can be handed over, replaced by theirs at first sign-in.
        $temporaryPassword = null;

        if (!$user) {
            $dummyEmail = $request->email ?? strtolower(str_replace(' ', '', $request->name)) . rand(100, 999) . '@vendor.mapato.com';
            $temporaryPassword = TemporaryPassword::generate();
            $user = new \App\Models\User([
                'name' => $request->name,
                'email' => $dummyEmail,
                'phone_number' => $phone,
                'password' => bcrypt($temporaryPassword),
                'role' => 'vendor',
                'is_active' => true,
            ]);
            $user->must_change_password = true;
            $user->save();
        }

        $data = $request->all();
        $data['user_id'] = $user->id;
        $data['is_active'] = true;

        // No vendor exists for this phone yet (checked above), so this is a new record.
        $vendor = Vendor::create($data);

        // Assign authorship and automatically attach to the account's saved roster
        $vendor->created_by = $request->user()->id;
        $vendor->is_global = true;
        $vendor->save();

        $this->rosterOwner($request->user())->savedVendors()->syncWithoutDetaching([$vendor->id]);

        return ResponseHelper::success(
            array_merge((new VendorResource($vendor))->resolve(), ['temporary_password' => $temporaryPassword]),
            'Fundi ameongezwa',
            201
        );
    }

    /**
     * Preventive Maintenance methods.
     */
    #[OA\Get(
        path: '/rental/maintenance/preventive',
        summary: 'Get preventive',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Maintenance'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getPreventive(Request $request)
    {
        $user = $request->user();
        $schedules = PreventiveMaintenance::when(!$user->seesAllAccounts(), function ($q) use ($user) {
            $q->whereHas('property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->with(['property', 'house'])->get();

        return ResponseHelper::success($schedules);
    }

    #[OA\Post(

        path: '/rental/maintenance/preventive',

        summary: 'Store preventive',

        security: [['bearerAuth' => []]],

        tags: ['Rental / Maintenance'],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['property_id', 'description', 'frequency', 'next_run'],
                properties: [
                new OA\Property(property: 'property_id', type: 'string'),
                new OA\Property(property: 'house_id', type: 'string', nullable: true),
                new OA\Property(property: 'description', type: 'string'),
                new OA\Property(property: 'frequency', type: 'string', enum: ['monthly', 'quarterly', 'semi_annual', 'annual']),
                new OA\Property(property: 'next_run', type: 'string', format: 'date'),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function storePreventive(Request $request)
    {
        $request->validate([
            'property_id' => 'required|exists:rental_properties,id',
            'house_id' => 'nullable|exists:rental_houses,id',
            'description' => 'required|string',
            'frequency' => 'required|in:monthly,quarterly,semi_annual,annual',
            'next_run' => 'required|date',
        ]);

        // Schedules may only be set on properties (and units) this account owns.
        if (!$this->canWorkOn($request->user(), (string) $request->property_id)) {
            return ResponseHelper::error('Property not found', 404);
        }
        if ($request->house_id
            && !House::whereKey($request->house_id)->where('property_id', $request->property_id)->exists()) {
            return ResponseHelper::error('That unit does not belong to the selected property', 422);
        }

        $pm = PreventiveMaintenance::create($request->all());
        return ResponseHelper::success($pm, 'Ratiba imepangwa', 201);
    }
}
