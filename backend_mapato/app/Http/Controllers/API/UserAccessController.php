<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\Inventory\AuditTrail;
use App\Support\Access\Modules;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * What one person of the business may open, as switches the owner turns on and off. The role gives a starting set; the owner adds to
 * it or takes from it for this one person, and can put it back at any time. Who may do this is decided as for editing the person
 * (see UserManagementController::update): the platform owner for anyone, a business owner for the staff they created.
 */
class UserAccessController extends Controller
{
    public function __construct(private readonly AuditTrail $audit) {}

    /** The person, or a refusal: not theirs to configure. */
    private function target(Request $request, string $id): User
    {
        $auth = $request->user();
        $user = User::where('id', $id)->firstOrFail();

        if (!$auth->isSuperAdmin()) {
            abort_if($user->created_by !== $auth->id, 403, 'Unauthorized action.');
            abort_if(in_array(strtolower((string) $user->role), ['admin', 'administrator', 'super_admin'], true), 403, 'Only a super admin can edit admin accounts.');
        }

        return $user;
    }

    /** @return array<int, string> the services whose switches apply to this person */
    private function services(User $user): array
    {
        $services = $user->effectiveServiceTypes();

        return $services === [] ? ['inventory'] : $services;
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $user = $this->target($request, $id);

        return response()->json(['success' => true, 'data' => $this->payload($user)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $auth = $request->user();
        $user = $this->target($request, $id);
        $data = $request->validate([
            'on' => 'present|array',
            'on.*' => 'string|in:' . implode(',', User::INV_PERMISSIONS),
        ]);

        // An owner may only hand out what they can use themselves (the service scope rule of the staff form).
        $services = $this->services($user);
        if (!$auth->isSuperAdmin()) {
            $own = $auth->services()->pluck('service_type')->all();
            $covered = in_array('salon', $own, true) ? array_merge($own, ['inventory']) : $own;
            $outside = array_filter($data['on'], fn ($k) => !in_array(User::serviceForPermission((string) $k), $covered, true));
            abort_if($outside !== [], 403, 'You can only grant permissions for your assigned service(s).');
        }

        $before = ['permissions' => $user->permissions ?? [], 'denied_permissions' => $user->deniedPermissions()];
        $split = Modules::split((string) $user->role, $services, $data['on']);

        // Only the switches of these services are touched; whatever the owner set on others is kept as it was.
        $mine = array_column(Modules::forServices($services), 'key');
        $user->permissions = array_values(array_unique(array_merge(
            array_values(array_diff($user->permissions ?? [], $mine)),
            $split['permissions'],
        )));
        $user->denied_permissions = array_values(array_unique(array_merge(
            array_values(array_diff($user->deniedPermissions(), $mine)),
            $split['denied_permissions'],
        )));
        $user->save();

        $this->audit->record(
            $request, 'user', null, 'access_changed', $before,
            ['permissions' => $user->permissions, 'denied_permissions' => $user->denied_permissions],
            "{$auth->name} changed what \"{$user->name}\" may open",
        );

        return response()->json(['success' => true, 'message' => 'Access saved', 'data' => $this->payload($user)]);
    }

    /** Put the person back to exactly what their role gives. */
    public function reset(Request $request, string $id): JsonResponse
    {
        $user = $this->target($request, $id);
        $services = $this->services($user);
        $mine = array_column(Modules::forServices($services), 'key');
        $before = ['permissions' => $user->permissions ?? [], 'denied_permissions' => $user->deniedPermissions()];

        $user->permissions = array_values(array_diff($user->permissions ?? [], $mine));
        $user->denied_permissions = array_values(array_diff($user->deniedPermissions(), $mine));
        $user->save();

        $this->audit->record(
            $request, 'user', null, 'access_reset', $before,
            ['permissions' => $user->permissions, 'denied_permissions' => $user->denied_permissions],
            "{$request->user()->name} put \"{$user->name}\" back to what the role gives",
        );

        return response()->json(['success' => true, 'message' => 'Access put back to the role', 'data' => $this->payload($user)]);
    }

    /** @return array<string, mixed> */
    private function payload(User $user): array
    {
        $services = $this->services($user);

        return [
            'user' => ['id' => $user->id, 'name' => $user->name, 'role' => $user->role],
            'modules' => Modules::stateFor($user, $services),
            'effective_permissions' => $user->effectiveInventoryPermissions(),
        ];
    }
}
