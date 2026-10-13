<?php

namespace App\Http\Controllers\API\Rental;

use App\Http\Controllers\Controller;
use App\Support\Pagination;
use App\Models\Rental\RentalAgreement;
use App\Models\Rental\House;
use App\Models\User;
use App\Services\Rental\RentalService;
use App\Helpers\ResponseHelper;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use OpenApi\Attributes as OA;

class AgreementController extends Controller
{
    protected RentalService $rentalService;

    public function __construct(RentalService $rentalService)
    {
        $this->rentalService = $rentalService;
    }

    /**
     * List all agreements for the landlord's properties.
     */
    #[OA\Get(
        path: '/rental/agreements',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Agreement'],
        parameters: [
            new OA\Parameter(name: 'per_page', in: 'query', schema: new OA\Schema(type: 'string', default: '15')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function index(Request $request)
    {
        $query = RentalAgreement::when(!$request->user()->isSuperAdmin(), function ($hq) use ($request) {
            $hq->whereHas('house.property', function ($q) use ($request) {
                $q->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->with('tenant', 'house.property', 'house.block');

        // Filter by status
        if ($request->status) {
            $query->where('status', $request->status);
        }

        // Search by tenant name or house number
        if ($request->search) {
            $search = $request->search;
            $query->where(function ($q) use ($search) {
                $q->whereHas('tenant', function ($sq) use ($search) {
                    $sq->where('name', 'like', "%{$search}%");
                })->orWhereHas('house', function ($sq) use ($search) {
                    $sq->where('house_number', 'like', "%{$search}%");
                });
            });
        }

        // Expiring soon filter
        if ($request->expiring_soon) {
            $query->where('status', 'active')
                ->where('end_date', '>=', now())
                ->where('end_date', '<=', now()->addDays(30));
        }

        $perPage = Pagination::perPage($request, 15);
        return ResponseHelper::paginate($query->orderBy('created_at', 'desc')->paginate($perPage));
    }

    /**
     * Get single agreement with full details.
     */
    #[OA\Get(
        path: '/rental/agreements/{id}',
        summary: 'Get a single resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Agreement'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function show(Request $request, string $id)
    {
        $agreement = RentalAgreement::when(!$request->user()->isSuperAdmin(), function ($hq) use ($request) {
            $hq->whereHas('house.property', function ($q) use ($request) {
                $q->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->with('tenant', 'tenant.profile', 'house.property', 'house.block', 'bills', 'payments.receipt')->findOrFail($id);

        return ResponseHelper::success($agreement);
    }

    /**
     * Create a new agreement.
     */
    #[OA\Post(
        path: '/rental/agreements',
        summary: 'Create a resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Agreement'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['tenant_id', 'property_id', 'house_id', 'start_date', 'end_date', 'rent_amount'],
                properties: [
                new OA\Property(property: 'tenant_id', type: 'string'),
                new OA\Property(property: 'property_id', type: 'string'),
                new OA\Property(property: 'house_id', type: 'string'),
                new OA\Property(property: 'start_date', type: 'string', format: 'date'),
                new OA\Property(property: 'end_date', type: 'string', format: 'date'),
                new OA\Property(property: 'rent_amount', type: 'number'),
                new OA\Property(property: 'deposit_amount', type: 'number', nullable: true),
                new OA\Property(property: 'deposit_paid', type: 'number', nullable: true),
                new OA\Property(property: 'rent_cycle', type: 'string', enum: ['monthly', 'quarterly', 'semi_annual', 'annual'], nullable: true),
                new OA\Property(property: 'due_day', type: 'integer', nullable: true),
                new OA\Property(property: 'grace_period_days', type: 'integer', nullable: true),
                new OA\Property(property: 'late_fee_type', type: 'string', enum: ['percentage', 'fixed', 'none'], nullable: true),
                new OA\Property(property: 'late_fee_amount', type: 'number', nullable: true),
                new OA\Property(property: 'utility_charges', type: 'array', items: new OA\Items(type: 'string'), nullable: true),
                new OA\Property(property: 'rules', type: 'array', items: new OA\Items(type: 'string'), nullable: true),
                new OA\Property(property: 'terms', type: 'string', nullable: true),
                new OA\Property(property: 'notes', type: 'string', nullable: true),
                new OA\Property(property: 'notice_period_days', type: 'integer', nullable: true),
                new OA\Property(property: 'auto_renew', type: 'boolean', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function store(Request $request)
    {
        $request->validate([
            'tenant_id' => 'required|exists:users,id',
            'property_id' => 'required|exists:rental_properties,id',
            'house_id' => 'required|exists:rental_houses,id',
            'start_date' => 'required|date',
            'end_date' => 'required|date|after:start_date',
            'rent_amount' => 'required|numeric|min:0',
            'deposit_amount' => 'sometimes|numeric|min:0',
            'deposit_paid' => 'sometimes|numeric|min:0',
            'rent_cycle' => 'sometimes|in:monthly,quarterly,semi_annual,annual',
            'due_day' => 'sometimes|integer|min:1|max:31',
            'grace_period_days' => 'sometimes|integer|min:0',
            'late_fee_type' => 'sometimes|in:percentage,fixed,none',
            'late_fee_amount' => 'sometimes|numeric|min:0',
            'utility_charges' => 'nullable|array',
            'rules' => 'nullable|array',
            'terms' => 'nullable|string|max:2000',
            'notes' => 'nullable|string|max:1000',
            'notice_period_days' => 'sometimes|integer|min:0',
            'auto_renew' => 'sometimes|boolean',
        ]);

        // Verify property ownership (super_admin can create agreements on
        // any landlord's house)
        $house = House::when(!$request->user()->isSuperAdmin(), function ($hq) use ($request) {
            $hq->whereHas('property', function ($q) use ($request) {
                $q->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->findOrFail($request->house_id);

        if ($house->status !== 'vacant' && $request->get('force') != true) {
            return ResponseHelper::error('House is not vacant', 400);
        }

        $agreement = DB::transaction(function () use ($request, $house) {
            // Generate agreement number if not provided
            $agreementNumber = $request->agreement_number ?? 'AGR-' . strtoupper(Str::random(10));

            $agreement = RentalAgreement::create([
                'agreement_number' => $agreementNumber,
                'tenant_id' => $request->tenant_id,
                'property_id' => $request->property_id,
                'house_id' => $request->house_id,
                'start_date' => $request->start_date,
                'end_date' => $request->end_date,
                'rent_amount' => $request->rent_amount,
                'deposit_amount' => $request->deposit_amount ?? $house->deposit_amount ?? 0,
                'deposit_paid' => $request->deposit_paid ?? 0,
                'rent_cycle' => $request->rent_cycle ?? 'monthly',
                'due_day' => $request->due_day ?? 5,
                'grace_period_days' => $request->grace_period_days ?? 0,
                'late_fee_type' => $request->late_fee_type ?? 'none',
                'late_fee_amount' => $request->late_fee_amount ?? 0,
                'utility_charges' => $request->utility_charges,
                'rules' => $request->rules,
                'status' => 'active',
                'terms' => $request->terms,
                'notes' => $request->notes,
                'notice_period_days' => $request->notice_period_days ?? 30,
                'auto_renew' => $request->auto_renew ?? false,
                'created_by' => $request->user()->id,
            ]);

            // Mark house as occupied
            $house->update([
                'status' => 'occupied',
                'current_tenant_id' => $request->tenant_id,
            ]);

            // Generate first bill
            $this->rentalService->generateBillForAgreement($agreement, \Carbon\Carbon::parse($agreement->start_date));

            return $agreement;
        });

        return ResponseHelper::success($agreement->load('tenant', 'house', 'property'), 'Agreement created successfully', 201);
    }

    /**
     * Renew an agreement (extend end date).
     */
    #[OA\Post(
        path: '/rental/agreements/{id}/renew',
        summary: 'Renew',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Agreement'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['new_end_date'],
                properties: [
                new OA\Property(property: 'new_end_date', type: 'string', format: 'date'),
                new OA\Property(property: 'new_rent_amount', type: 'number', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function renew(Request $request, string $id)
    {
        $agreement = RentalAgreement::when(!$request->user()->isSuperAdmin(), function ($hq) use ($request) {
            $hq->whereHas('house.property', function ($q) use ($request) {
                $q->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->findOrFail($id);

        $request->validate([
            'new_end_date' => 'required|date|after:end_date',
            'new_rent_amount' => 'sometimes|numeric|min:0',
        ]);

        $agreement->update([
            'status' => 'active',
            'end_date' => $request->new_end_date,
            'rent_amount' => $request->new_rent_amount ?? $agreement->rent_amount,
            'renewal_date' => now(),
        ]);

        return ResponseHelper::success($agreement, 'Agreement renewed successfully');
    }

    /**
     * Terminate an agreement early.
     */
    #[OA\Post(
        path: '/rental/agreements/{id}/terminate',
        summary: 'Terminate',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Agreement'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['termination_reason'],
                properties: [
                new OA\Property(property: 'termination_reason', type: 'string'),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function terminate(Request $request, string $id)
    {
        $agreement = RentalAgreement::when(!$request->user()->isSuperAdmin(), function ($hq) use ($request) {
            $hq->whereHas('house.property', function ($q) use ($request) {
                $q->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->findOrFail($id);

        $request->validate([
            'termination_reason' => 'required|string|max:500',
        ]);

        DB::transaction(function () use ($agreement, $request) {
            $agreement->update([
                'status' => 'terminated',
                'notes' => $request->termination_reason . ($agreement->notes ? "\n" . $agreement->notes : ''),
            ]);

            // Free up the house
            $agreement->house->update([
                'status' => 'vacant',
                'current_tenant_id' => null,
            ]);
        });

        return ResponseHelper::success($agreement, 'Agreement terminated');
    }

    /**
     * Upload document to an agreement.
     */
    #[OA\Post(
        path: '/rental/agreements/{id}/documents',
        summary: 'Upload document',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Agreement'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['document', 'document_type'],
                properties: [
                new OA\Property(property: 'document', type: 'string'),
                new OA\Property(property: 'document_type', type: 'string', enum: ['signed_contract', 'id_card', 'receipt', 'other']),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function uploadDocument(Request $request, string $id)
    {
        $agreement = RentalAgreement::when(!$request->user()->isSuperAdmin(), function ($hq) use ($request) {
            $hq->whereHas('house.property', function ($q) use ($request) {
                $q->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->findOrFail($id);

        $request->validate([
            'document' => 'required|file|mimes:pdf,jpg,png|max:10240',
            'document_type' => 'required|in:signed_contract,id_card,receipt,other',
        ]);

        // Store the document
        $path = \App\Support\PrivateFile::store($request->file('document'), 'agreements/' . $agreement->id);

        $documents = $agreement->documents ?? [];
        $documents[] = [
            'type' => $request->document_type,
            'path' => $path,
            'name' => $request->file('document')->getClientOriginalName(),
            'uploaded_at' => now()->toDateTimeString(),
        ];

        $agreement->update(['documents' => $documents]);

        return ResponseHelper::success($agreement, 'Document uploaded');
    }

    /**
     * Get expiring agreements for notifications.
     */
    #[OA\Get(
        path: '/rental/agreements/expiring',
        summary: 'Get expiring',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Agreement'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getExpiring(Request $request)
    {
        $agreements = RentalAgreement::when(!$request->user()->isSuperAdmin(), function ($hq) use ($request) {
            $hq->whereHas('house.property', function ($q) use ($request) {
                $q->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->where('status', 'active')
            ->where('end_date', '>=', now())
            ->where('end_date', '<=', now()->addDays(30))
            ->with('tenant', 'house')
            ->get();

        return ResponseHelper::success($agreements);
    }
}