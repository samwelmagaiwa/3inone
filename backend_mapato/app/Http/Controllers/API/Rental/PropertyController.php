<?php

namespace App\Http\Controllers\API\Rental;

use App\Http\Controllers\Controller;
use App\Support\Pagination;
use App\Http\Requests\StorePropertyRequest;
use App\Http\Requests\UpdatePropertyRequest;
use App\Http\Resources\PropertyResource;
use App\Services\Rental\PropertyService;
use App\Models\Rental\Property;
use App\Models\Rental\House;
use App\Helpers\ResponseHelper;
use Illuminate\Http\Request;
use OpenApi\Attributes as OA;

#[OA\Tag(name: 'Rental / Properties', description: 'Properties and the houses/units within them.')]
class PropertyController extends Controller
{
    protected PropertyService $propertyService;

    public function __construct(PropertyService $propertyService)
    {
        $this->propertyService = $propertyService;
    }

    /**
     * Get all properties with pagination and filters.
     * GET /rental/properties
     */
    #[OA\Get(
        path: '/rental/properties',
        summary: 'List properties',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Properties'],
        parameters: [
            new OA\Parameter(name: 'per_page', in: 'query', schema: new OA\Schema(type: 'string', default: '15')),
            new OA\Parameter(name: 'search', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'property_type', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'sort_by', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'sort_order', in: 'query', schema: new OA\Schema(type: 'string', enum: ['asc', 'desc'])),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Paginated property list'),
        ],
    )]
    public function index(Request $request)
    {
        $filters = $request->only(['search', 'status', 'property_type', 'sort_by', 'sort_order']);
        $perPage = Pagination::perPage($request, 15);

        $properties = $this->propertyService
            ->forUser($request->user())
            ->getAll($filters, $perPage);

        return ResponseHelper::paginate($properties, PropertyResource::class);
    }

    /**
     * Get property statistics.
     * GET /rental/properties/stats
     */
    #[OA\Get(
        path: '/rental/properties/stats',
        summary: 'Stats',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Properties'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function stats(Request $request)
    {
        $stats = $this->propertyService
            ->forUser($request->user())
            ->getStatistics();

        return ResponseHelper::success($stats);
    }

    /**
     * Show single property.
     * GET /rental/properties/{id}
     */
    #[OA\Get(
        path: '/rental/properties/{id}',
        summary: 'Get a single resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Properties'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function show(Request $request, string $id)
    {
        $property = $this->propertyService
            ->forUser($request->user())
            ->getById($id);

        return ResponseHelper::success(new PropertyResource($property));
    }

    /**
     * Create a new property.
     * POST /rental/properties
     */
    #[OA\Post(
        path: '/rental/properties',
        summary: 'Create a resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Properties'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['name', 'property_type', 'region', 'district', 'address', 'billing_cycle'],
                properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'property_type', type: 'string'),
                new OA\Property(property: 'region', type: 'string'),
                new OA\Property(property: 'district', type: 'string'),
                new OA\Property(property: 'ward', type: 'string', nullable: true),
                new OA\Property(property: 'street', type: 'string', nullable: true),
                new OA\Property(property: 'address', type: 'string'),
                new OA\Property(property: 'description', type: 'string', nullable: true),
                new OA\Property(property: 'billing_cycle', type: 'string'),
                new OA\Property(property: 'currency', type: 'string', nullable: true),
                new OA\Property(property: 'status', type: 'string', nullable: true),
                new OA\Property(property: 'total_units', type: 'integer', nullable: true),
                new OA\Property(property: 'number_of_blocks', type: 'integer', nullable: true),
                new OA\Property(property: 'caretaker_id', type: 'string', nullable: true),
                new OA\Property(property: 'default_rent_amount', type: 'number', nullable: true),
                new OA\Property(property: 'default_deposit_amount', type: 'number', nullable: true),
                new OA\Property(property: 'utility_billing_enabled', type: 'boolean', nullable: true),
                new OA\Property(property: 'cover_image', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function store(StorePropertyRequest $request)
    {
        try {
            $property = $this->propertyService
                ->forUser($request->user())
                ->create($request->validated());

            return ResponseHelper::success(
                new PropertyResource($property->load(['blocks', 'houses', 'caretaker'])),
                'Mali imeundwa vizuri',
                201
            );
        } catch (\Exception $e) {
            return ResponseHelper::error($e->getMessage(), 500);
        }
    }

    /**
     * Update a property.
     * PUT /rental/properties/{id}
     */
    #[OA\Put(
        path: '/rental/properties/{id}',
        summary: 'Update a resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Properties'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'name', type: 'string', nullable: true),
                new OA\Property(property: 'property_type', type: 'string', nullable: true),
                new OA\Property(property: 'region', type: 'string', nullable: true),
                new OA\Property(property: 'district', type: 'string', nullable: true),
                new OA\Property(property: 'ward', type: 'string', nullable: true),
                new OA\Property(property: 'street', type: 'string', nullable: true),
                new OA\Property(property: 'address', type: 'string', nullable: true),
                new OA\Property(property: 'description', type: 'string', nullable: true),
                new OA\Property(property: 'billing_cycle', type: 'string', nullable: true),
                new OA\Property(property: 'currency', type: 'string', nullable: true),
                new OA\Property(property: 'status', type: 'string', nullable: true),
                new OA\Property(property: 'total_units', type: 'integer', nullable: true),
                new OA\Property(property: 'number_of_blocks', type: 'integer', nullable: true),
                new OA\Property(property: 'caretaker_id', type: 'string', nullable: true),
                new OA\Property(property: 'default_rent_amount', type: 'number', nullable: true),
                new OA\Property(property: 'default_deposit_amount', type: 'number', nullable: true),
                new OA\Property(property: 'utility_billing_enabled', type: 'boolean', nullable: true),
                new OA\Property(property: 'cover_image', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function update(UpdatePropertyRequest $request, string $id)
    {
        try {
            $property = $this->propertyService
                ->forUser($request->user())
                ->update($id, $request->validated());

            return ResponseHelper::success(
                new PropertyResource($property),
                'Mali imesasurwa vizuri'
            );
        } catch (\Exception $e) {
            return ResponseHelper::error($e->getMessage(), 500);
        }
    }

    /**
     * Delete a property (soft delete).
     * DELETE /rental/properties/{id}
     */
    #[OA\Delete(
        path: '/rental/properties/{id}',
        summary: 'Delete a resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Properties'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function destroy(Request $request, string $id)
    {
        try {
            $this->propertyService
                ->forUser($request->user())
                ->delete($id);

            return ResponseHelper::success(null, 'Mali imefutwa');
        } catch (\Exception $e) {
            return ResponseHelper::error($e->getMessage(), 400);
        }
    }

    /**
     * Restore a deleted property.
     * POST /rental/properties/{id}/restore
     */
    #[OA\Post(
        path: '/rental/properties/{id}/restore',
        summary: 'Restore',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Properties'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function restore(Request $request, string $id)
    {
        try {
            $property = $this->propertyService
                ->forUser($request->user())
                ->restore($id);

            return ResponseHelper::success(
                new PropertyResource($property),
                'Mali imerejeshwa'
            );
        } catch (\Exception $e) {
            return ResponseHelper::error($e->getMessage(), 500);
        }
    }

    /**
     * Get deleted properties.
     * GET /rental/properties/trashed
     */
    #[OA\Get(
        path: '/rental/properties/trashed',
        summary: 'Trashed',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Properties'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function trashed(Request $request)
    {
        $properties = $this->propertyService
            ->forUser($request->user())
            ->getDeleted();

        return ResponseHelper::success(PropertyResource::collection($properties));
    }

    /**
     * Add a house to a property.
     * POST /rental/properties/{id}/houses
     */
    #[OA\Post(
        path: '/rental/properties/{id}/houses',
        summary: 'Add house',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Properties'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['house_number', 'rent_amount'],
                properties: [
                new OA\Property(property: 'house_number', type: 'string'),
                new OA\Property(property: 'rent_amount', type: 'number'),
                new OA\Property(property: 'type', type: 'string', enum: ['apartment', 'room', 'commercial', 'studio', 'bedsitter', 'one_bedroom', 'two_bedroom'], nullable: true),
                new OA\Property(property: 'deposit_amount', type: 'number', nullable: true),
                new OA\Property(property: 'block_id', type: 'string', nullable: true),
                new OA\Property(property: 'electricity_meter', type: 'string', nullable: true),
                new OA\Property(property: 'water_meter', type: 'string', nullable: true),
                new OA\Property(property: 'bedrooms', type: 'integer', nullable: true),
                new OA\Property(property: 'bathrooms', type: 'integer', nullable: true),
                new OA\Property(property: 'floor', type: 'integer', nullable: true),
                new OA\Property(property: 'status', type: 'string', enum: ['vacant', 'occupied', 'maintenance', 'reserved'], nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function addHouse(Request $request, string $propertyId)
    {
        $property = Property::when(
            !$request->user()->isSuperAdmin(),
            fn($q) => $q->whereIn('owner_id', $request->user()->accountMemberIds())
        )->findOrFail($propertyId);

        $request->validate([
            'house_number' => 'required|string|max:50',
            'rent_amount' => 'required|numeric|min:0',
            'type' => 'sometimes|in:apartment,room,commercial,studio,bedsitter,one_bedroom,two_bedroom',
            'deposit_amount' => 'sometimes|numeric|min:0',
            'block_id' => ['nullable', new \App\Rules\BlockOnProperty($property->id)],
            'electricity_meter' => 'nullable|string|max:50',
            'water_meter' => 'nullable|string|max:50',
            'bedrooms' => 'nullable|integer|min:0',
            'bathrooms' => 'nullable|integer|min:0',
            'floor' => 'nullable|integer|min:0',
            'status' => 'sometimes|in:vacant,occupied,maintenance,reserved',
        ]);

        $house = House::create(array_merge($request->all(), [
            'property_id' => $propertyId,
            'status' => $request->status ?? 'vacant',
            'deposit_amount' => $request->deposit_amount ?? ($property->default_deposit_amount ?? 0),
        ]));

        $property->increment('total_units');

        return ResponseHelper::success($house, 'Nyumba imeongezwa', 201);
    }
}