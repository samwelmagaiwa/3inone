<?php

namespace App\Http\Controllers\API\Rental;

use App\Http\Controllers\Controller;
use App\Support\Pagination;
use App\Models\Rental\House;
use App\Models\Rental\Property;
use App\Helpers\ResponseHelper;
use Illuminate\Http\Request;
use OpenApi\Attributes as OA;

class HouseController extends Controller
{
    /**
     * Get all houses with optional filters and search.
     * GET /rental/houses
     */
    #[OA\Get(
        path: '/rental/houses',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Rental / House'],
        parameters: [
            new OA\Parameter(name: 'per_page', in: 'query', schema: new OA\Schema(type: 'string', default: '15')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    #[OA\Get(
        path: '/rental/reports/houses',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Rental / House'],
        parameters: [
            new OA\Parameter(name: 'per_page', in: 'query', schema: new OA\Schema(type: 'string', default: '15')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function index(Request $request)
    {
        $isSuperAdmin = $request->user()->isSuperAdmin();
        $query = House::query()->when(!$isSuperAdmin, function ($hq) use ($request) {
            $hq->whereHas('property', function ($q) use ($request) {
                $q->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        });

        // Filter by property
        if ($request->property_id) {
            $query->where('property_id', $request->property_id);
        }

        // Filter by block
        if ($request->block_id) {
            $query->where('block_id', $request->block_id);
        }

        // Filter by status
        if ($request->status) {
            $query->where('status', $request->status);
        }

        // Search by house number
        if ($request->search) {
            $query->where('house_number', 'like', "%{$request->search}%");
        }

        // Pagination
        $perPage = Pagination::perPage($request, 15);
        $houses = $query->with('property', 'block', 'currentTenant')->paginate($perPage);

        return ResponseHelper::paginate($houses);
    }

    /**
     * Get houses for a specific property.
     * GET /rental/properties/{propertyId}/houses
     */
    #[OA\Get(
        path: '/rental/properties/{id}/houses',
        summary: 'Get by property',
        security: [['bearerAuth' => []]],
        tags: ['Rental / House'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getByProperty(Request $request, $propertyId)
    {
        // Verify property belongs to user (skipped for super_admin, who can
        // see any landlord's properties)
        $property = Property::when(
            !$request->user()->isSuperAdmin(),
            fn($q) => $q->whereIn('owner_id', $request->user()->accountMemberIds())
        )->findOrFail($propertyId);

        $houses = House::where('property_id', $propertyId)
            ->with('block', 'currentTenant')
            ->get();

        return ResponseHelper::success($houses);
    }

    /**
     * Create a new house.
     * POST /rental/houses
     */
    #[OA\Post(
        path: '/rental/houses',
        summary: 'Create a resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / House'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['property_id', 'house_number', 'type', 'rent_amount'],
                properties: [
                new OA\Property(property: 'property_id', type: 'string'),
                new OA\Property(property: 'block_id', type: 'string', nullable: true),
                new OA\Property(property: 'house_number', type: 'string'),
                new OA\Property(property: 'type', type: 'string', enum: ['apartment', 'room', 'commercial', 'studio', 'bedsitter', 'one_bedroom', 'two_bedroom', 'three_bedroom']),
                new OA\Property(property: 'rent_amount', type: 'number'),
                new OA\Property(property: 'deposit_amount', type: 'number', nullable: true),
                new OA\Property(property: 'electricity_meter', type: 'string', nullable: true),
                new OA\Property(property: 'water_meter', type: 'string', nullable: true),
                new OA\Property(property: 'bedrooms', type: 'integer', nullable: true),
                new OA\Property(property: 'bathrooms', type: 'integer', nullable: true),
                new OA\Property(property: 'floor', type: 'integer', nullable: true),
                new OA\Property(property: 'square_meters', type: 'integer', nullable: true),
                new OA\Property(property: 'description', type: 'string', nullable: true),
                new OA\Property(property: 'kitchen_location', type: 'string', nullable: true),
                new OA\Property(property: 'distance_from_road', type: 'string', nullable: true),
                new OA\Property(property: 'electricity_type', type: 'string', nullable: true),
                new OA\Property(property: 'electricity_sharing_count', type: 'integer', nullable: true),
                new OA\Property(property: 'water_type', type: 'string', nullable: true),
                new OA\Property(property: 'water_sharing_count', type: 'integer', nullable: true),
                new OA\Property(property: 'maintenance_until', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'units_count', type: 'integer', nullable: true),
                new OA\Property(property: 'unit_names', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function store(Request $request)
    {
        $property = Property::when(
            !$request->user()->isSuperAdmin(),
            fn($q) => $q->whereIn('owner_id', $request->user()->accountMemberIds())
        )->findOrFail($request->property_id);

        $currentSum = House::where('property_id', $request->property_id)->sum('rent_amount');
        $remainingAllowed = max(0, $property->default_rent_amount - $currentSum);

        $request->validate([
            'property_id' => 'required|exists:rental_properties,id',
            'block_id' => ['nullable', new \App\Rules\BlockOnProperty($request->property_id)],
            'house_number' => 'required|string|max:50',
            'type' => 'required|in:apartment,room,commercial,studio,bedsitter,one_bedroom,two_bedroom,three_bedroom',
            'rent_amount' => [
                'required',
                'numeric',
                'min:0',
                function ($attribute, $value, $fail) use ($remainingAllowed) {
                    if ($value > $remainingAllowed) {
                        $fail("The house rent amount cannot exceed the remaining property target of " . number_format($remainingAllowed, 2));
                    }
                },
            ],
            'deposit_amount' => 'nullable|numeric|min:0',
            'electricity_meter' => 'nullable|string|max:50',
            'water_meter' => 'nullable|string|max:50',
            'bedrooms' => 'nullable|integer|min:0',
            'bathrooms' => 'nullable|integer|min:0',
            'floor' => 'nullable|integer|min:0',
            'square_meters' => 'nullable|integer|min:0',
            'description' => 'nullable|string|max:500',
            'images.*' => 'nullable|image',
            'kitchen_location' => 'nullable|string',
            'distance_from_road' => 'nullable|string',
            'electricity_type' => 'nullable|string',
            'electricity_sharing_count' => 'nullable|integer',
            'water_type' => 'nullable|string',
            'water_sharing_count' => 'nullable|integer',
            'maintenance_until' => 'nullable|date|after_or_equal:today',
            'units_count' => 'nullable|integer|min:0',
            'unit_names' => 'nullable|string',
        ]);

        $data = $request->except('images');

        $booleanFields = ['has_fence', 'has_tiles', 'has_sitting_room', 'has_master_bedroom', 'has_kitchen', 'landlord_lives_present'];
        foreach ($booleanFields as $field) {
            if ($request->has($field)) {
                $data[$field] = filter_var($request->get($field), FILTER_VALIDATE_BOOLEAN);
            }
        }

        $imagePaths = [];
        if ($request->hasFile('images')) {
            foreach ($request->file('images') as $image) {
                $imagePaths[] = $image->store('houses', 'public');
            }
        }
        $data['images'] = $imagePaths;

        // Parse image captions (double-pipe separated string from frontend)
        if ($request->has('image_captions') && !empty($request->image_captions)) {
            $data['image_captions'] = explode('||', $request->image_captions);
        }

        // Handle unit names
        if ($request->has('unit_names') && !empty($request->unit_names)) {
            $data['unit_names'] = is_array($request->unit_names)
                ? $request->unit_names
                : explode(',', $request->unit_names);
        }

        $data['status'] = 'vacant';

        $house = House::create($data);

        Property::find($request->property_id)->increment('total_units');

        return ResponseHelper::success($house, 'House created successfully', 201);
    }

    /**
     * Get single house details.
     * GET /rental/houses/{id}
     */
    #[OA\Get(
        path: '/rental/houses/{id}',
        summary: 'Get a single resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / House'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function show(Request $request, $id)
    {
        $house = House::when(!$request->user()->isSuperAdmin(), function ($hq) use ($request) {
            $hq->whereHas('property', function ($q) use ($request) {
                $q->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->with('property', 'block', 'currentTenant.tenantProfile', 'activeAgreement.tenant')
          ->findOrFail($id);

        // Append occupied_units only on single-house view (avoids N+1 on list endpoints)
        $house->append('occupied_units');

        return ResponseHelper::success($house);
    }

    /**
     * Update a house.
     * PUT /rental/houses/{id}
     */
    #[OA\Put(
        path: '/rental/houses/{id}',
        summary: 'Update a resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / House'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'house_number', type: 'string', nullable: true),
                new OA\Property(property: 'block_id', type: 'string', nullable: true),
                new OA\Property(property: 'type', type: 'string', enum: ['apartment', 'room', 'commercial', 'studio', 'bedsitter', 'one_bedroom', 'two_bedroom', 'three_bedroom'], nullable: true),
                new OA\Property(property: 'rent_amount', type: 'number', nullable: true),
                new OA\Property(property: 'deposit_amount', type: 'number', nullable: true),
                new OA\Property(property: 'electricity_meter', type: 'string', nullable: true),
                new OA\Property(property: 'water_meter', type: 'string', nullable: true),
                new OA\Property(property: 'bedrooms', type: 'integer', nullable: true),
                new OA\Property(property: 'bathrooms', type: 'integer', nullable: true),
                new OA\Property(property: 'floor', type: 'integer', nullable: true),
                new OA\Property(property: 'square_meters', type: 'integer', nullable: true),
                new OA\Property(property: 'status', type: 'string', enum: ['vacant', 'occupied', 'maintenance', 'reserved'], nullable: true),
                new OA\Property(property: 'description', type: 'string', nullable: true),
                new OA\Property(property: 'kitchen_location', type: 'string', nullable: true),
                new OA\Property(property: 'distance_from_road', type: 'string', nullable: true),
                new OA\Property(property: 'electricity_type', type: 'string', nullable: true),
                new OA\Property(property: 'electricity_sharing_count', type: 'integer', nullable: true),
                new OA\Property(property: 'water_type', type: 'string', nullable: true),
                new OA\Property(property: 'water_sharing_count', type: 'integer', nullable: true),
                new OA\Property(property: 'maintenance_until', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'units_count', type: 'integer', nullable: true),
                new OA\Property(property: 'unit_names', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function update(Request $request, $id)
    {
        $house = House::when(!$request->user()->isSuperAdmin(), function ($hq) use ($request) {
            $hq->whereHas('property', function ($q) use ($request) {
                $q->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->with('property')->findOrFail($id);

        $currentSum = House::where('property_id', $house->property_id)
            ->where('id', '!=', $id)
            ->sum('rent_amount');
        $remainingAllowed = max(0, $house->property->default_rent_amount - $currentSum);

        $request->validate([
            'house_number' => 'sometimes|string|max:50',
            'block_id' => ['nullable', new \App\Rules\BlockOnProperty($house->property_id)],
            'type' => 'sometimes|in:apartment,room,commercial,studio,bedsitter,one_bedroom,two_bedroom,three_bedroom',
            'rent_amount' => [
                'sometimes',
                'numeric',
                'min:0',
                function ($attribute, $value, $fail) use ($remainingAllowed) {
                    if ($value > $remainingAllowed) {
                        $fail("The house rent amount cannot exceed the remaining property target of " . number_format($remainingAllowed, 2));
                    }
                },
            ],
            'deposit_amount' => 'sometimes|numeric|min:0',
            'electricity_meter' => 'nullable|string|max:50',
            'water_meter' => 'nullable|string|max:50',
            'bedrooms' => 'nullable|integer|min:0',
            'bathrooms' => 'nullable|integer|min:0',
            'floor' => 'nullable|integer|min:0',
            'square_meters' => 'nullable|integer|min:0',
            'status' => 'sometimes|in:vacant,occupied,maintenance,reserved',
            'description' => 'nullable|string|max:500',
            'images.*' => 'nullable|image',
            'kitchen_location' => 'nullable|string',
            'distance_from_road' => 'nullable|string',
            'electricity_type' => 'nullable|string',
            'electricity_sharing_count' => 'nullable|integer',
            'water_type' => 'nullable|string',
            'water_sharing_count' => 'nullable|integer',
            'maintenance_until' => 'nullable|date|after_or_equal:today',
            'units_count' => 'nullable|integer|min:0',
            'unit_names' => 'nullable|string',
        ]);

        $data = $request->except('images');

        $booleanFields = ['has_fence', 'has_tiles', 'has_sitting_room', 'has_master_bedroom', 'has_kitchen', 'landlord_lives_present'];
        foreach ($booleanFields as $field) {
            if ($request->has($field)) {
                $data[$field] = filter_var($request->get($field), FILTER_VALIDATE_BOOLEAN);
            }
        }

        // Handle image management (deletions/reordering/re-captioning)
        $currentImages = is_array($house->images) ? $house->images : [];
        $currentCaptions = is_array($house->image_captions) ? $house->image_captions : [];

        if ($request->has('existing_images')) {
            $currentImages = is_array($request->existing_images) ? $request->existing_images : explode('||', $request->existing_images);
            // Ensure we filter out empty strings if any
            $currentImages = array_values(array_filter($currentImages));
            $data['images'] = $currentImages;
        }

        if ($request->has('existing_captions')) {
            $currentCaptions = is_array($request->existing_captions) ? $request->existing_captions : explode('||', $request->existing_captions);
            // We don't filter captions as they might be empty intentionally, but we align them
            $data['image_captions'] = $currentCaptions;
        }

        // Handle new uploads
        if ($request->hasFile('images')) {
            foreach ($request->file('images') as $image) {
                $currentImages[] = $image->store('houses', 'public');
            }
            $data['images'] = $currentImages;

            // Handle new captions if provided alongside new files
            if ($request->has('image_captions')) {
                $newCaptions = explode('||', $request->image_captions);
                $currentCaptions = array_merge($currentCaptions, $newCaptions);
                $data['image_captions'] = $currentCaptions;
            }
        }

        // Handle unit names in update
        if ($request->has('unit_names')) {
            $data['unit_names'] = is_array($request->unit_names)
                ? $request->unit_names
                : (empty($request->unit_names) ? [] : explode(',', $request->unit_names));
        }

        $house->update($data);

        return ResponseHelper::success($house, 'House updated successfully');
    }

    /**
     * Delete a house.
     * DELETE /rental/houses/{id}
     */
    #[OA\Delete(
        path: '/rental/houses/{id}',
        summary: 'Delete a resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / House'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function destroy(Request $request, $id)
    {
        $house = House::when(!$request->user()->isSuperAdmin(), function ($hq) use ($request) {
            $hq->whereHas('property', function ($q) use ($request) {
                $q->whereIn('owner_id', $request->user()->accountMemberIds());
            });
        })->findOrFail($id);

        if ($house->status === 'occupied') {
            return ResponseHelper::error('Cannot delete occupied house. Move out tenant first.', 400);
        }

        if ($house->agreements()->count() > 0) {
            return ResponseHelper::error('Cannot delete house with active agreements.', 400);
        }

        $propertyId = $house->property_id;
        $house->delete();

        // Update property total_units
        Property::find($propertyId)->decrement('total_units');

        return ResponseHelper::success(null, 'House deleted successfully');
    }

    /**
     * Public listing – no auth required.
     * Returns houses with images & features, excluding private meter data.
     * GET /api/public/houses
     */
    #[OA\Get(
        path: '/public/houses',
        summary: 'Public listing',
        tags: ['Rental / House'],
        parameters: [
            new OA\Parameter(name: 'per_page', in: 'query', schema: new OA\Schema(type: 'string', default: '20')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function publicListing(Request $request)
    {
        $query = House::with('property:id,name,property_type,address,region,district,ward,street');

        // Filter by status (Default: Exclude occupied)
        if ($request->status) {
            $query->where('status', $request->status);
        } else {
            $query->whereIn('status', ['vacant', 'maintenance', 'reserved']);
        }

        // Filter by type
        if ($request->type) {
            $query->where('type', $request->type);
        }

        // Search
        if ($request->search) {
            $query->where(function ($q) use ($request) {
                $q->where('house_number', 'like', "%{$request->search}%")
                    ->orWhereHas('property', function ($pq) use ($request) {
                        $pq->where('name', 'like', "%{$request->search}%")
                            ->orWhere('address', 'like', "%{$request->search}%")
                            ->orWhere('region', 'like', "%{$request->search}%")
                            ->orWhere('district', 'like', "%{$request->search}%")
                            ->orWhere('ward', 'like', "%{$request->search}%")
                            ->orWhere('street', 'like', "%{$request->search}%");
                    });
            });
        }

        // Advanced Filters
        if ($request->bedrooms) {
            $query->where('bedrooms', '>=', $request->bedrooms);
        }
        if ($request->bathrooms) {
            $query->where('bathrooms', '>=', $request->bathrooms);
        }

        if ($request->filled('max_distance')) {
            // Enhanced distance filtering to handle "km" and "m" suffixes correctly
            // Converts "1km" to 1000 and "200m" to 200 for numeric comparison
            $query->whereRaw("
                (CASE
                    WHEN LOWER(distance_from_road) LIKE '%km%' THEN CAST(REPLACE(REPLACE(LOWER(distance_from_road), 'km', ''), ' ', '') AS DECIMAL(10,2)) * 1000
                    WHEN LOWER(distance_from_road) LIKE '%m%' AND LOWER(distance_from_road) NOT LIKE '%km%' THEN CAST(REPLACE(REPLACE(LOWER(distance_from_road), 'm', ''), ' ', '') AS DECIMAL(10,2))
                    ELSE CAST(NULLIF(REPLACE(distance_from_road, ' ', ''), '') AS DECIMAL(10,2))
                END) <= ?
            ", [(float)$request->max_distance]);
        }

        if ($request->has_fence !== null) {
            $query->where('has_fence', $request->boolean('has_fence'));
        }
        if ($request->has_tiles !== null) {
            $query->where('has_tiles', $request->boolean('has_tiles'));
        }
        if ($request->has_kitchen !== null) {
            $query->where('has_kitchen', $request->boolean('has_kitchen'));
        }
        if ($request->has_master_bedroom !== null) {
            $query->where('has_master_bedroom', $request->boolean('has_master_bedroom'));
        }
        if ($request->has_sitting_room !== null) {
            $query->where('has_sitting_room', $request->boolean('has_sitting_room'));
        }

        $perPage = Pagination::perPage($request, 20);
        $houses = $query->latest()->paginate($perPage);

        // Strip private meter data from each house
        $houses->getCollection()->transform(function ($house) {
            $house->makeHidden([
                'electricity_meter',
                'water_meter',
                'electricity_sharing_count',
                'water_sharing_count',
                'square_meters', // Hide sqm as requested
            ]);
            return $house;
        });

        return ResponseHelper::paginate($houses);
    }
}
