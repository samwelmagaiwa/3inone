<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Serve a service's routes only to users a super admin has given that service.
 *
 * Usage: ->middleware('service:transport')   (or several: any one is enough)
 *
 * See User::canUseService() for the rule. This is the server-side half of "each
 * business sees only its own services"; the app's picker hides the rest, but a
 * client can always call the API directly.
 */
class EnsureServiceAccess
{
    public function handle(Request $request, Closure $next, string ...$services): Response
    {
        $user = $request->user();

        if (!$user) {
            return response()->json(['message' => 'Unauthenticated.'], 401);
        }

        foreach ($services as $service) {
            if ($user->canUseService(trim($service))) {
                return $next($request);
            }
        }

        return response()->json([
            'message' => 'Your account has not been given access to this service. Ask your administrator.',
            'code' => 'service_not_assigned',
            'service' => $services,
        ], 403);
    }
}
