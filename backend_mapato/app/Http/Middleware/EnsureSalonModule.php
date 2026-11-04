<?php

namespace App\Http\Middleware;

use App\Support\Tenancy\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * The salon's sections are each their own right: ->middleware('salon_module:inv_salon_equipment') lets in only whoever holds that
 * right (their role's own, plus what the owner added, minus what the owner took back). It applies to the salon only: the same
 * controllers also serve a shop or depot, where these rights do not exist, and nothing changes there.
 */
class EnsureSalonModule
{
    public function handle(Request $request, Closure $next, string ...$modules): Response
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['message' => 'Unauthenticated.'], 401);
        }

        if (TenantContext::service() !== 'salon') {
            return $next($request);
        }

        foreach ($modules as $module) {
            if ($user->hasInventoryPermission(trim($module))) {
                return $next($request);
            }
        }

        return response()->json([
            'message' => 'Hauna ruhusa ya sehemu hii. Muulize mmiliki wa biashara. / You do not have access to this section. Ask the business owner.',
            'code' => 'module_not_allowed',
            'required_any' => $modules,
        ], 403);
    }
}
