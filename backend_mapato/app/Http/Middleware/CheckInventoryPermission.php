<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Gate inventory routes by granular permission key.
 *
 * Usage in routes:   ->middleware('inv_perm:inv_view_reports')
 *
 * Resolution order (mirrors Flutter UserPermissions.fromUser):
 *   1. super_admin / full_access           → always allowed
 *   2. Explicit per-user grant in users.permissions (JSON column)
 *   3. Role-default permission set (User::hasInventoryPermission)
 *
 * admin is NOT in the bypass — they go through the role-default list so
 * their inventory access is scoped to their assigned service(s).
 *
 * Multiple comma-separated permissions = ANY of them grants access:
 *   ->middleware('inv_perm:inv_view_expenses,inv_manage_expenses')
 */
class CheckInventoryPermission
{
    public function handle(Request $request, Closure $next, string ...$permissions): Response
    {
        $user = $request->user();

        if (!$user) {
            return response()->json(['message' => 'Unauthenticated.'], 401);
        }

        // Having a permission is not enough: the business must have been given the
        // inventory service at all (see User::canUseService). The Salon service runs on the same sales
        // engine (customers, sales, payments, cash, expenses), so it opens these routes too.
        if (!$user->canUseService('inventory') && !$user->canUseService('salon')) {
            return response()->json([
                'message' => 'Your account has not been given access to this service. Ask your administrator.',
                'code'    => 'service_not_assigned',
                'service' => ['inventory', 'salon'],
            ], 403);
        }

        // At least one of the required permissions must be satisfied
        foreach ($permissions as $perm) {
            if ($user->hasInventoryPermission(trim($perm))) {
                return $next($request);
            }
        }

        return response()->json([
            'message'             => 'Forbidden. Insufficient inventory permissions.',
            'required_any'        => $permissions,
            'user_role'           => $user->role,
            'user_explicit_perms' => is_array($user->permissions) ? $user->permissions : [],
        ], 403);
    }
}
