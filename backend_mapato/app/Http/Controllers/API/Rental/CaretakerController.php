<?php

namespace App\Http\Controllers\API\Rental;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\Rental\Property;
use App\Helpers\ResponseHelper;
use App\Rules\InAccount;
use App\Rules\UniquePhoneInBusiness;
use App\Support\Tenancy\TenantContext;
use App\Support\TemporaryPassword;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

class CaretakerController extends Controller
{
    /**
     * List caretakers for a landlord.
     */
    #[OA\Get(
        path: '/rental/caretakers',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Caretaker'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function index(Request $request)
    {
        $caretakers = User::where('role', 'caretaker')
            ->when(!$request->user()->isSuperAdmin(), fn($q) => $q->whereIn('created_by', $request->user()->accountMemberIds()))
            ->select('id', 'name', 'email', 'phone_number', 'is_active', 'created_at')
            ->get();
        
        return ResponseHelper::success($caretakers);
    }

    /**
     * Create a caretaker account.
     */
    #[OA\Post(
        path: '/rental/caretakers',
        summary: 'Create a resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Caretaker'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['name', 'phone_number', 'email'],
                properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'phone_number', type: 'string'),
                new OA\Property(property: 'email', type: 'string', format: 'email'),
                new OA\Property(property: 'password', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function store(Request $request)
    {
        // The email is required, not optional: it is what the caretaker signs in with, and the
        // users table does not accept an account without one (it used to fail with a 500).
        $request->validate([
            'name' => 'required|string',
            // The phone only has to be unique inside this business; the email is the sign-in name
            // and stays unique across the platform.
            'phone_number' => ['required', 'string', new UniquePhoneInBusiness(TenantContext::writeOwner())],
            'email' => 'required|email|unique:users',
            'password' => 'nullable|string|min:8',
        ]);

        // No shared default password: unless one is given, a one-time password is generated
        // and returned once, to hand over. Either way it must be replaced at first sign-in.
        $temporaryPassword = $request->filled('password') ? null : TemporaryPassword::generate();

        $caretaker = new User([
            'name' => $request->name,
            'email' => $request->email,
            'phone_number' => $request->phone_number,
            'password' => bcrypt($request->filled('password') ? $request->password : $temporaryPassword),
            'role' => 'caretaker',
            'created_by' => $request->user()->id,
            'is_active' => true,
        ]);
        $caretaker->must_change_password = true;
        $caretaker->save();

        return ResponseHelper::success(
            array_merge($caretaker->toArray(), ['temporary_password' => $temporaryPassword]),
            'Caretaker created successfully',
            201
        );
    }

    /**
     * Assign properties to a caretaker.
     */
    #[OA\Post(
        path: '/rental/caretakers/{id}/assign',
        summary: 'Assign properties',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Caretaker'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['property_ids'],
                properties: [
                new OA\Property(property: 'property_ids', type: 'array', items: new OA\Items(type: 'string')),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function assignProperties(Request $request, $caretakerId)
    {
        $caretaker = User::where('role', 'caretaker')
            ->when(!$request->user()->isSuperAdmin(), fn($q) => $q->whereIn('created_by', $request->user()->accountMemberIds()))
            ->findOrFail($caretakerId);

        // `present`, not `required`: an empty list is how every property is taken away.
        // InAccount asks the (account-scoped) model, so another business's property
        // fails exactly like one that does not exist.
        $request->validate([
            'property_ids' => 'present|array',
            'property_ids.*' => [new InAccount(Property::class)],
        ]);

        $ids = array_values(array_unique(array_map('strval', $request->input('property_ids'))));

        // A caretaker looks after the properties of the business that employs them. The
        // scope already keeps an owner to their own; this also covers a super admin, who
        // sees every business and could otherwise mix them.
        $headId = $caretaker->accountHeadId();
        $foreign = Property::whereIn('id', $ids)->pluck('owner_id')
            ->unique()
            ->filter(fn ($ownerId) => (string) User::find($ownerId)?->accountHeadId() !== $headId);
        if ($foreign->isNotEmpty()) {
            throw ValidationException::withMessages([
                'property_ids' => 'A caretaker can only be assigned properties of the business that employs them.',
            ]);
        }

        // The assignment IS properties.caretaker_id (it is also what gives the caretaker
        // access to the property). Replace the caretaker's set: release what is no longer
        // listed, take what is, in one step so a failure leaves the old set intact.
        // Unscoped on purpose: every id was checked above through the scoped model, and the
        // account scope is a sub-select on this same table, which MySQL refuses inside an
        // UPDATE ("can't specify target table"). Listed ids only, so nothing else is touched.
        DB::transaction(function () use ($caretaker, $ids) {
            Property::withoutAccountScope()->where('caretaker_id', $caretaker->id)->whereNotIn('id', $ids)->update(['caretaker_id' => null]);
            Property::withoutAccountScope()->whereIn('id', $ids)->update(['caretaker_id' => $caretaker->id]);
        });

        return ResponseHelper::success(
            array_merge($caretaker->only(['id', 'name', 'email', 'phone_number', 'is_active']), ['property_ids' => $ids]),
            'Properties assigned to caretaker'
        );
    }

    /**
     * Update caretaker status.
     */
    #[OA\Put(
        path: '/rental/caretakers/{id}',
        summary: 'Update a resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Caretaker'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'name', type: 'string', nullable: true),
                new OA\Property(property: 'is_active', type: 'boolean', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function update(Request $request, $id)
    {
        $caretaker = User::where('role', 'caretaker')
            ->when(!$request->user()->isSuperAdmin(), fn($q) => $q->whereIn('created_by', $request->user()->accountMemberIds()))
            ->findOrFail($id);

        $request->validate([
            'name' => 'sometimes|string',
            'is_active' => 'sometimes|boolean',
        ]);

        $caretaker->update($request->only(['name', 'is_active']));

        return ResponseHelper::success($caretaker, 'Caretaker updated');
    }

    /**
     * Delete a caretaker.
     */
    #[OA\Delete(
        path: '/rental/caretakers/{id}',
        summary: 'Delete a resource',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Caretaker'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function destroy(Request $request, $id)
    {
        $caretaker = User::where('role', 'caretaker')
            ->when(!$request->user()->isSuperAdmin(), fn($q) => $q->whereIn('created_by', $request->user()->accountMemberIds()))
            ->findOrFail($id);

        $caretaker->delete();

        return ResponseHelper::success(null, 'Caretaker deleted');
    }
}