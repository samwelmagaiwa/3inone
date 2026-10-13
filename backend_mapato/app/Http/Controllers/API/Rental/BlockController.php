<?php

namespace App\Http\Controllers\API\Rental;

use App\Http\Controllers\Controller;
use App\Models\Rental\Block;
use App\Models\Rental\Property;
use App\Helpers\ResponseHelper;
use Illuminate\Http\Request;
use OpenApi\Attributes as OA;

class BlockController extends Controller
{
    /** Properties the caller's account owns (super_admin: all). */
    private function ownedProperties(Request $request)
    {
        $user = $request->user();

        return Property::query()->when(
            !$user->seesAllAccounts(),
            fn ($q) => $q->whereIn('owner_id', $user->accountMemberIds())
        );
    }

    /** Blocks that belong to a property the caller's account owns (super_admin: all). */
    private function ownedBlocks(Request $request)
    {
        $user = $request->user();

        return Block::query()->when(
            !$user->seesAllAccounts(),
            fn ($q) => $q->whereHas('property', fn ($p) => $p->whereIn('owner_id', $user->accountMemberIds()))
        );
    }

    #[OA\Get(
        path: '/rental/blocks/{propertyId}',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Block'],
        parameters: [
            new OA\Parameter(name: 'propertyId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function index(Request $request, $propertyId)
    {
        $property = $this->ownedProperties($request)->findOrFail($propertyId);

        $blocks = Block::where('property_id', $property->id)
            ->with('houses')
            ->get();
        return ResponseHelper::success($blocks);
    }

    #[OA\Post(

        path: '/rental/blocks/{propertyId}',

        summary: 'Create a resource',

        security: [['bearerAuth' => []]],

        tags: ['Rental / Block'],

        parameters: [

            new OA\Parameter(name: 'propertyId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['name'],
                properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'description', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function store(Request $request, $propertyId)
    {
        $request->validate([
            'name' => 'required|string',
            'description' => 'nullable|string',
        ]);

        $property = $this->ownedProperties($request)->findOrFail($propertyId);

        $block = Block::create([
            'property_id' => $property->id,
            'name' => $request->name,
            'description' => $request->description,
        ]);

        return ResponseHelper::success($block, 'Block created successfully', 201);
    }

    #[OA\Get(

        path: '/rental/blocks/block/{id}',

        summary: 'Get a single resource',

        security: [['bearerAuth' => []]],

        tags: ['Rental / Block'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function show(Request $request, $id)
    {
        $block = $this->ownedBlocks($request)->with(['property', 'houses'])->findOrFail($id);
        return ResponseHelper::success($block);
    }

    #[OA\Put(

        path: '/rental/blocks/block/{id}',

        summary: 'Update a resource',

        security: [['bearerAuth' => []]],

        tags: ['Rental / Block'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'name', type: 'string', nullable: true),
                new OA\Property(property: 'description', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function update(Request $request, $id)
    {
        $block = $this->ownedBlocks($request)->findOrFail($id);
        
        $request->validate([
            'name' => 'sometimes|string',
            'description' => 'nullable|string',
        ]);

        $block->update($request->only(['name', 'description']));
        
        return ResponseHelper::success($block, 'Block updated successfully');
    }

    #[OA\Delete(

        path: '/rental/blocks/block/{id}',

        summary: 'Delete a resource',

        security: [['bearerAuth' => []]],

        tags: ['Rental / Block'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function destroy(Request $request, $id)
    {
        $block = $this->ownedBlocks($request)->findOrFail($id);
        
        if ($block->houses()->count() > 0) {
            return ResponseHelper::error('Cannot delete block with houses. Remove houses first.', 400);
        }
        
        $block->delete();
        
        return ResponseHelper::success(null, 'Block deleted successfully');
    }
}