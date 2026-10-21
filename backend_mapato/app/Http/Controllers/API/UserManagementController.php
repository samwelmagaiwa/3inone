<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Rules\UniquePhoneInBusiness;
use App\Services\Inventory\AuditTrail;
use App\Services\ServiceAssignment;
use App\Support\Tenancy\BusinessOwner;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rules\Password;
use OpenApi\Attributes as OA;

#[OA\Tag(name: 'Admin / Users', description: "Staff account management, shared by all three services. An admin sees only the staff they created; super_admin sees everyone.")]
class UserManagementController extends Controller
{
    public function __construct(
        private readonly AuditTrail $audit,
        private readonly ServiceAssignment $assignment,
    ) {
    }

    // List users visible to the authenticated user.
    //
    // super_admin → sees everyone.
    // everyone else → their own account: themself plus the users they or their
    //               staff created (see User::scopeInAccountOf).
    #[OA\Get(
        path: '/admin/users/mine',
        summary: 'List staff visible to the caller',
        description: 'super_admin sees everyone; anyone else sees themself plus the accounts '
            . 'they or their staff created.',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Users'],
        parameters: [
            new OA\Parameter(name: 'created_by', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'role', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'q', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'page', in: 'query', schema: new OA\Schema(type: 'string', default: '1')),
            new OA\Parameter(name: 'limit', in: 'query', schema: new OA\Schema(type: 'string', default: '20')),
            new OA\Parameter(name: 'service_type', in: 'query', schema: new OA\Schema(type: 'string', enum: ['inventory', 'rental', 'transport'])),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Staff list', content: new OA\JsonContent(
                type: 'array',
                items: new OA\Items(ref: '#/components/schemas/User'),
            )),
        ],
    )]
    #[OA\Get(
        path: '/admin/users',
        summary: 'List staff visible to the caller',
        description: 'super_admin sees everyone; anyone else sees themself plus the accounts '
            . 'they or their staff created.',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Users'],
        parameters: [
            new OA\Parameter(name: 'created_by', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'role', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'q', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'page', in: 'query', schema: new OA\Schema(type: 'string', default: '1')),
            new OA\Parameter(name: 'limit', in: 'query', schema: new OA\Schema(type: 'string', default: '20')),
            new OA\Parameter(name: 'service_type', in: 'query', schema: new OA\Schema(type: 'string', enum: ['inventory', 'rental', 'transport'])),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Staff list', content: new OA\JsonContent(
                type: 'array',
                items: new OA\Items(ref: '#/components/schemas/User'),
            )),
        ],
    )]
    public function myUsers(Request $request)
    {
        $user = $request->user();
        $query = User::query();

        if ($request->query('created_by') === 'me') {
            $query->where('created_by', $user->id);
        } elseif ($request->query('role') === 'super_admin') {
            // Only super admins may enumerate other super admin accounts.
            if (!$user->isSuperAdmin()) {
                return response()->json(['success' => false, 'message' => 'Forbidden.'], 403);
            }
            $query->where('role', 'super_admin');
        } elseif ($user->isSuperAdmin() || $user->full_access) {
            // no extra filter — see everyone
        } else {
            // Everyone else sees their own account only: themself, plus the users
            // they or their staff created. Sharing a service with another admin
            // does not make that admin's staff, drivers or tenants visible.
            $query->inAccountOf($user);
        }

        if ($role = $request->query('role')) {
            $query->where('role', $role);
        }

        if ($serviceType = $request->query('service_type')) {
            $query->whereHas('services', fn ($q) => $q->where('service_type', $serviceType));
        }

        if ($search = $request->query('q')) {
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                    ->orWhere('email', 'like', "%{$search}%")
                    ->orWhere('phone_number', 'like', "%{$search}%");
            });
        }

        $page = max((int) $request->query('page', 1), 1);
        $limit = max((int) $request->query('limit', 20), 1);

        $total = (clone $query)->count();
        $items = $query->with(['services', 'creator:id,name,email'])
            ->orderByDesc('created_at')
            ->skip(($page - 1) * $limit)
            ->take($limit)
            ->get(['id', 'name', 'email', 'phone_number', 'role', 'is_active', 'service_type', 'full_access', 'permissions', 'created_by', 'created_at'])
            ->each(function ($u) {
                $u->service_types = $u->services->pluck('service_type')->all();
                $u->created_by_name = $u->creator->name ?? null;
                $u->created_by_email = $u->creator->email ?? null;
                unset($u->services, $u->creator);
            });

        return response()->json([
            'success' => true,
            'data' => [
                'users' => $items,
                'pagination' => [
                    'page' => $page,
                    'limit' => $limit,
                    'total' => $total,
                    'has_more_pages' => ($page * $limit) < $total,
                ],
            ],
        ]);
    }

    /**
     * Super admin only: every user grouped by service, then by the admin who
     * manages them within that service -- "see all users as per service and
     * as per admins of that service."
     */
    #[OA\Get(
        path: '/admin/users/by-service',
        summary: 'Users by service',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Users'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function usersByService(Request $request)
    {
        $auth = $request->user();
        if (!$auth->isSuperAdmin()) {
            abort(403, 'Only super admin can view users grouped by service.');
        }

        $users = User::with(['services', 'creator:id,name,email'])
            ->orderBy('name')
            ->get(['id', 'name', 'email', 'phone_number', 'role', 'is_active', 'full_access', 'created_by', 'created_at']);

        $services = ['transport', 'rental', 'inventory', 'salon'];
        $grouped = [];

        foreach ($services as $service) {
            // Admins are grouped by service via their OWN service_types
            // binding, same as staff -- an admin with no service binding at
            // all is treated as a general/company-wide admin and listed
            // separately, not duplicated under every service.
            $usersInService = $users->filter(
                fn ($u) => $u->services->pluck('service_type')->contains($service)
            );

            $byAdmin = [];
            foreach ($usersInService as $u) {
                $adminId = $u->created_by ?? 'unassigned';
                $byAdmin[$adminId]['admin'] = $u->creator
                    ? ['id' => $u->creator->id, 'name' => $u->creator->name, 'email' => $u->creator->email]
                    : null;
                $byAdmin[$adminId]['users'][] = $this->userPayload($u, $u->services->pluck('service_type')->all());
            }

            $grouped[$service] = array_values($byAdmin);
        }

        $generalAdmins = $users->filter(
            fn ($u) => in_array($u->role, ['admin', 'super_admin'], true) && $u->services->isEmpty()
        )->map(fn ($u) => $this->userPayload($u, []))->values();

        return response()->json([
            'success' => true,
            'data' => [
                'by_service' => $grouped,
                'general_admins' => $generalAdmins,
            ],
        ]);
    }

    // Create a user (created_by = auth id)
    #[OA\Post(
        path: '/admin/users',
        summary: 'Create a staff account',
        description: 'created_by is set to the caller automatically, so this new user is scoped '
            . "to the caller's own staff list going forward.",
        security: [['bearerAuth' => []]],
        tags: ['Admin / Users'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'email', 'phone_number', 'password', 'role'],
                properties: [
                    new OA\Property(property: 'name', type: 'string'),
                    new OA\Property(property: 'email', type: 'string', format: 'email'),
                    new OA\Property(property: 'phone_number', type: 'string'),
                    new OA\Property(property: 'password', type: 'string', format: 'password'),
                    new OA\Property(property: 'role', type: 'string', example: 'sales_officer'),
                    new OA\Property(property: 'service_types', type: 'array', items: new OA\Items(type: 'string', enum: ['inventory', 'rental', 'transport'])),
                ],
            ),
        ),
        responses: [
            new OA\Response(response: 201, description: 'User created', content: new OA\JsonContent(ref: '#/components/schemas/User')),
            new OA\Response(response: 422, description: 'Validation failed', content: new OA\JsonContent(ref: '#/components/schemas/ValidationErrorResponse')),
        ],
    )]
    public function store(Request $request)
    {
        $auth = $request->user();
        $data = $request->only(['name', 'email', 'password', 'password_confirmation', 'phone_number', 'role', 'is_active', 'service_type', 'service_types', 'full_access', 'permissions', 'business_owner_id']);

        // The business the new account joins decides whose phone numbers it must not clash with: a
        // number only has to be unique inside one business. A brand-new owner starts a business of
        // their own, so there is nobody there yet to clash with.
        $joinsOwnerAccount = in_array($data['role'] ?? 'driver', ['super_admin', 'admin', 'administrator', 'landlord'], true);
        $phoneBusiness = ($auth->isSuperAdmin() && $joinsOwnerAccount)
            ? null
            : BusinessOwner::ofRequest($auth->isSuperAdmin() ? ($data['business_owner_id'] ?? null) : null);

        $validator = Validator::make($data, [
            // Super admin only: put the new account inside this business (see below).
            'business_owner_id' => 'nullable|uuid|exists:users,id',
            'name' => 'required|string|max:255',
            // The email is the sign-in name, so it is unique across the platform.
            'email' => 'required|email|unique:users,email',
            // Length-only: the app's own default-password generator
            // (surname repeated to 8 chars, e.g. "MAGAIWA" -> "MAGAIWAM")
            // is letters-only, so a letters()+numbers() complexity
            // requirement here would reject the app's own UX pattern.
            'password' => ['required', 'confirmed', Password::min(8)],
            // Required: login verifies the phone number, so an account without
            // one could never sign in.
            'phone_number' => ['required', 'string', 'max:50', new UniquePhoneInBusiness($phoneBusiness)],
            'role' => 'nullable|string|in:super_admin,admin,driver,landlord,caretaker,tenant,viewer,manager,operator,sales_officer,hair_stylist,nail_technician,lash_makeup_artist,accountant',
            'is_active' => 'nullable|boolean',
            // Legacy single value - still accepted for old clients.
            'service_type' => 'nullable|string|in:rental,transport,inventory,salon',
            // Preferred: a user can be bound to more than one service.
            'service_types' => 'nullable|array',
            'service_types.*' => 'string|in:rental,transport,inventory,salon',
            'full_access' => 'nullable|boolean',
            'permissions' => 'nullable|array',
            'permissions.*' => 'string|in:' . implode(',', User::grantablePermissions()),
        ]);
        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        // Non-super-admins cannot grant full_access flag.
        if (!$auth->isSuperAdmin() && !empty($data['full_access'])) {
            return response()->json(['success' => false, 'message' => 'Only super admin can grant full access.'], 403);
        }

        $role = $data['role'] ?? 'driver';
        $serviceTypes = $this->resolveServiceTypes($data);

        // An account bound to no service and with no admin-level role can
        // never do anything useful once created -- catch that at creation
        // time instead of shipping a silently broken login.
        if (empty($serviceTypes) && !in_array($role, ['admin', 'super_admin'], true)) {
            return response()->json([
                'success' => false,
                'message' => 'Select at least one service for this account.',
            ], 422);
        }

        if (!$auth->isSuperAdmin()) {
            // Only super admin may create account-owner roles. A business owner
            // creates STAFF; another owner (admin / landlord) is a separate
            // business that registers itself or is created by a super admin --
            // creating one here would hand out an account the creator can never see.
            if (in_array($role, ['admin', 'administrator', 'landlord', 'super_admin'], true)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Only a super admin can create admin or landlord accounts. You can create staff for your own business.',
                ], 403);
            }

            // Admin must have been bound to at least one service by a super_admin
            // before they can create staff. An unbound admin has no service scope
            // and therefore cannot create users for any service.
            $ownServices = $auth->services()->pluck('service_type')->all();
            if (empty($ownServices)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Your account has no service assigned. Ask your super admin to bind you to a service before you can create staff.',
                ], 403);
            }

            // Admin can only create staff within their assigned service(s).
            $outOfScope = array_diff($serviceTypes, $ownServices);
            if (!empty($outOfScope)) {
                return response()->json([
                    'success' => false,
                    'message' => 'You can only create staff for your assigned service(s): ' . implode(', ', $ownServices),
                ], 403);
            }

            if ($denied = $this->permissionScopeError($auth, $data['permissions'] ?? [])) {
                return $denied;
            }
        }

        // A super admin has no business of their own, so staff they create would belong to no
        // business and see an empty one. Naming the owner puts the new account inside that
        // business instead. Ignored for everyone else: an owner's staff always join their own.
        $creator = $auth;
        if ($auth->isSuperAdmin() && !empty($data['business_owner_id'])) {
            $business = User::query()->find($data['business_owner_id']);

            if (!$business || !in_array(strtolower((string) $business->role), User::ACCOUNT_HEAD_ROLES, true)) {
                return response()->json(['success' => false, 'message' => 'business_owner_id must be the owner (admin / landlord) of a business.'], 422);
            }
            if (in_array($role, ['super_admin', 'admin', 'administrator', 'landlord'], true)) {
                return response()->json(['success' => false, 'message' => 'An owner account cannot be placed inside another business.'], 422);
            }
            if (!empty(array_diff($serviceTypes, $business->serviceTypes()))) {
                return response()->json([
                    'success' => false,
                    'message' => 'That business was not given: ' . implode(', ', array_diff($serviceTypes, $business->serviceTypes())) . '.',
                ], 422);
            }

            $creator = $business;
        }

        $user = new User();
        $user->name = $data['name'];
        $user->email = $data['email'];
        $user->password = Hash::make($data['password']);
        $user->phone_number = $data['phone_number'] ?? null;
        $user->role = $role;
        $user->service_type = $serviceTypes[0] ?? null;
        $user->full_access = array_key_exists('full_access', $data) ? (bool) $data['full_access'] : false;
        $user->permissions = $data['permissions'] ?? [];
        $user->is_active = array_key_exists('is_active', $data) ? (bool) $data['is_active'] : true;
        $user->created_by = $creator->id;
        $user->must_change_password = true;
        $user->save();

        $this->syncServiceTypes($user, $serviceTypes);

        $this->audit->record(
            $request, 'user', null, 'created', null,
            ['name' => $user->name, 'email' => $user->email, 'role' => $role, 'service_types' => $serviceTypes],
            "{$auth->name} created {$role} account \"{$user->name}\" ({$user->email})",
        );

        return response()->json([
            'success' => true,
            'message' => 'User created',
            'data' => ['user' => $this->userPayload($user)],
        ], 201);
    }

    /**
     * A non-super-admin may only hand out permissions for services they are
     * themselves bound to (e.g. an inventory-only admin cannot grant Transport
     * or Rental access). Returns a 403 response, or null when everything is in scope.
     */
    private function permissionScopeError(User $auth, array $permissions)
    {
        $ownServices = $auth->services()->pluck('service_type')->all();
        // Salon runs on the inventory engine (sales, customers, cash), so the same permission keys cover it.
        $covered = in_array('salon', $ownServices, true) ? array_merge($ownServices, ['inventory']) : $ownServices;
        $outOfScope = array_filter(
            $permissions,
            fn ($perm) => !in_array(User::serviceForPermission((string) $perm), $covered, true)
        );
        if (empty($outOfScope)) {
            return null;
        }

        return response()->json([
            'success' => false,
            'message' => 'You can only grant permissions for your assigned service(s): ' . implode(', ', $ownServices),
            'out_of_scope' => array_values($outOfScope),
        ], 403);
    }

    /** Prefer the new `service_types` array; fall back to the legacy single value. */
    private function resolveServiceTypes(array $data): array
    {
        if (!empty($data['service_types'])) {
            return array_values(array_unique($data['service_types']));
        }
        if (!empty($data['service_type'])) {
            return [$data['service_type']];
        }
        return [];
    }

    /** Replace this user's bound services with exactly this set. */
    private function syncServiceTypes(User $user, array $serviceTypes): void
    {
        $user->services()->delete();
        foreach (array_unique($serviceTypes) as $type) {
            $user->services()->create(['service_type' => $type]);
        }

        // A business given inventory gets its own settings and default crate types.
        $this->assignment->prepareServices($user);
    }

    private function userPayload(User $user, ?array $serviceTypes = null): array
    {
        $payload = $user->only(['id', 'name', 'email', 'phone_number', 'role', 'is_active', 'service_type', 'full_access', 'permissions']);
        $payload['service_types'] = $serviceTypes ?? $user->services()->pluck('service_type')->all();
        return $payload;
    }

    // Update user (only fields allowed)
    #[OA\Put(
        path: '/admin/users/{id}',
        summary: 'Update a resource',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Users'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'name', type: 'string', nullable: true),
                new OA\Property(property: 'email', type: 'string', format: 'email', nullable: true),
                new OA\Property(property: 'phone_number', type: 'string', nullable: true),
                new OA\Property(property: 'role', type: 'string', enum: ['super_admin', 'admin', 'driver', 'landlord', 'caretaker', 'tenant', 'viewer', 'manager', 'operator', 'sales_officer'], nullable: true),
                new OA\Property(property: 'is_active', type: 'boolean', nullable: true),
                new OA\Property(property: 'service_type', type: 'string', enum: ['rental', 'transport', 'inventory'], nullable: true),
                new OA\Property(property: 'service_types', type: 'array', items: new OA\Items(type: 'string'), nullable: true),
                new OA\Property(property: 'full_access', type: 'boolean', nullable: true),
                new OA\Property(property: 'permissions', type: 'array', items: new OA\Items(type: 'string'), nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function update(Request $request, string $id)
    {
        $auth = $request->user();
        $user = User::where('id', $id)->firstOrFail();

        // Super admin can update anyone.
        // Admin can only update users they personally created AND who are not
        // admins/super_admins (peer-level accounts are super_admin territory).
        if (!$auth->isSuperAdmin()) {
            if ($user->created_by !== $auth->id) {
                abort(403, 'Unauthorized action.');
            }
            if (in_array(strtolower($user->role ?? ''), ['admin', 'administrator', 'super_admin'], true)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Only a super admin can edit admin accounts.',
                ], 403);
            }
        }

        $data = $request->only(['name', 'email', 'phone_number', 'role', 'is_active', 'service_type', 'service_types', 'full_access', 'permissions']);
        $validator = Validator::make($data, [
            'name' => 'sometimes|string|max:255',
            'email' => 'sometimes|email|unique:users,email,' . $user->id . ',id',
            // Unique inside this person's own business only.
            'phone_number' => ['sometimes', 'required', 'string', 'max:50', new UniquePhoneInBusiness(BusinessOwner::ofUser($user->id), (string) $user->id)],
            'role' => 'sometimes|string|in:super_admin,admin,driver,landlord,caretaker,tenant,viewer,manager,operator,sales_officer,hair_stylist,nail_technician,lash_makeup_artist,accountant',
            'is_active' => 'sometimes|boolean',
            'service_type' => 'nullable|string|in:rental,transport,inventory,salon',
            'service_types' => 'nullable|array',
            'service_types.*' => 'string|in:rental,transport,inventory,salon',
            'full_access' => 'sometimes|boolean',
            'permissions' => 'nullable|array',
            'permissions.*' => 'string|in:' . implode(',', User::grantablePermissions()),
        ]);
        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        // Non-super-admins cannot grant full_access flag.
        if (!$auth->isSuperAdmin() && array_key_exists('full_access', $data) && $data['full_access']) {
            return response()->json(['success' => false, 'message' => 'Only super admin can grant full access.'], 403);
        }

        if (!$auth->isSuperAdmin() && ($denied = $this->permissionScopeError($auth, $data['permissions'] ?? []))) {
            return $denied;
        }

        // Same escalation guard as store(): a plain admin editing an existing
        // account cannot promote it to admin/super_admin either.
        if (!$auth->isSuperAdmin() && array_key_exists('role', $data)
            && in_array($data['role'], ['admin', 'administrator', 'landlord', 'super_admin'], true)
            && $user->role !== $data['role']
        ) {
            return response()->json([
                'success' => false,
                'message' => 'Only a super admin can grant admin accounts.',
            ], 403);
        }

        $before = ['is_active' => $user->is_active, 'role' => $user->role, 'name' => $user->name, 'permissions' => $user->permissions];

        $touchesServices = array_key_exists('service_types', $data) || array_key_exists('service_type', $data);
        $validated = $validator->validated();
        unset($validated['service_types']);

        if ($touchesServices) {
            $serviceTypes = $this->resolveServiceTypes($data);
            $validated['service_type'] = $serviceTypes[0] ?? null;
        }

        $user->fill($validated);
        $user->save();

        // A deactivated account must not keep working on tokens it already holds.
        if (!$user->is_active) {
            $user->tokens()->delete();
        }

        if ($touchesServices) {
            $this->syncServiceTypes($user, $this->resolveServiceTypes($data));
        }

        // Deactivating/reactivating an account is the kind of action that
        // needs a clear "who and when" trail, not just a silent flag flip.
        if (array_key_exists('is_active', $data) && $before['is_active'] !== $user->is_active) {
            $this->audit->record(
                $request, 'user', null, $user->is_active ? 'activated' : 'deactivated', $before,
                ['is_active' => $user->is_active],
                "{$auth->name} " . ($user->is_active ? 'activated' : 'deactivated') . " \"{$user->name}\" ({$user->email})",
            );
        } elseif (array_key_exists('role', $data) && $before['role'] !== $user->role) {
            $this->audit->record(
                $request, 'user', null, 'role_changed', $before,
                ['role' => $user->role],
                "{$auth->name} changed \"{$user->name}\"'s role from {$before['role']} to {$user->role}",
            );
        }

        if (array_key_exists('permissions', $data)) {
            $this->audit->record(
                $request, 'user', null, 'permissions_changed',
                ['permissions' => $before['permissions'] ?? []],
                ['permissions' => $user->permissions ?? []],
                "{$auth->name} updated explicit permissions for \"{$user->name}\"",
            );
        }

        return response()->json([
            'success' => true,
            'message' => 'User updated',
            'data' => ['user' => $this->userPayload($user)],
        ]);
    }

    // Delete user
    #[OA\Delete(
        path: '/admin/users/{id}',
        summary: 'Delete a resource',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Users'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function destroy(Request $request, string $id)
    {
        $auth = $request->user();
        $user = User::where('id', $id)->firstOrFail();

        if (!$auth->isSuperAdmin()) {
            if ($user->created_by !== $auth->id) {
                abort(403, 'Unauthorized action.');
            }
            if (in_array(strtolower($user->role ?? ''), ['admin', 'administrator', 'super_admin'], true)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Only a super admin can delete admin accounts.',
                ], 403);
            }
        }

        $summary = "{$auth->name} deleted {$user->role} account \"{$user->name}\" ({$user->email})";
        $user->tokens()->delete();
        $user->delete();

        $this->audit->record(
            $request, 'user', null, 'deleted',
            ['name' => $user->name, 'email' => $user->email, 'role' => $user->role],
            null, $summary,
        );

        return response()->json([
            'success' => true,
            'message' => 'User deleted',
        ]);
    }

    /**
     * Super admin only: replace a user's service bindings with the supplied set.
     *
     * PUT /users/{id}/services   body: { "service_types": ["inventory","rental"] }
     *
     * Passing an empty array removes all bindings (effectively locks the user out
     * of all services until re-bound). This is intentional — super_admin can use
     * this to revoke an admin's access to a service without deleting the account.
     */
    #[OA\Put(
        path: '/admin/users/{id}/services',
        summary: 'Bind services',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Users'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['service_types'],
                properties: [
                new OA\Property(property: 'service_types', type: 'array', items: new OA\Items(type: 'string')),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function bindServices(Request $request, string $id)
    {
        $auth = $request->user();

        if (!$auth->isSuperAdmin()) {
            return response()->json([
                'success' => false,
                'message' => 'Only a super admin can manage service bindings.',
            ], 403);
        }

        $target = User::where('id', $id)->firstOrFail();

        $validator = Validator::make($request->all(), [
            'service_types'   => 'required|array',
            'service_types.*' => 'string|in:rental,transport,inventory,salon',
        ]);
        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors'  => $validator->errors(),
            ], 422);
        }

        $before   = $target->services()->pluck('service_type')->all();
        $newTypes = array_values(array_unique($request->input('service_types', [])));

        $this->syncServiceTypes($target, $newTypes);

        // Keep legacy single-value column in sync for older code paths.
        $target->service_type = $newTypes[0] ?? null;
        $target->save();

        $this->audit->record(
            $request, 'user', null, 'services_changed',
            ['service_types' => $before],
            ['service_types' => $newTypes],
            "{$auth->name} updated service bindings for \"{$target->name}\" ({$target->email}): "
            . (empty($newTypes) ? 'none' : implode(', ', $newTypes)),
        );

        return response()->json([
            'success'      => true,
            'message'      => 'Service bindings updated.',
            'data'         => [
                'user'         => $this->userPayload($target, $newTypes),
                'is_unbound'   => empty($newTypes),
            ],
        ]);
    }

    // Reset password to provided value
    #[OA\Post(
        path: '/admin/users/{id}/reset-password',
        summary: 'Reset password',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Users'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['password'],
                properties: [
                new OA\Property(property: 'password', type: 'string'),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function resetPassword(Request $request, string $id)
    {
        $auth = $request->user();
        $user = User::where('id', $id)->firstOrFail();
        if (!$auth->isSuperAdmin() && $user->created_by !== $auth->id) {
            abort(403, 'Unauthorized action.');
        }

        $data = $request->only(['password', 'password_confirmation']);
        $validator = Validator::make($data, [
            'password' => ['required', 'confirmed', Password::min(8)],
        ]);
        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user->password = Hash::make($data['password']);
        $user->must_change_password = true;
        $user->save();

        $this->audit->record(
            $request, 'user', null, 'password_reset', null, null,
            "{$auth->name} reset the password for \"{$user->name}\" ({$user->email})",
        );

        return response()->json([
            'success' => true,
            'message' => 'Password reset successfully',
        ]);
    }
}