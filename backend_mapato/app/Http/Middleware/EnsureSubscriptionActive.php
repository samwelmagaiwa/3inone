<?php

namespace App\Http\Middleware;

use App\Helpers\ResponseHelper;
use App\Models\Business;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * A business whose paid-until date plus grace period has passed is told so -- once billing is
 * enforced (BILLING_ENFORCE, see config/billing.php).
 *
 * It answers HTTP 402 with the code `subscription_expired`, deliberately NOT 401: the device is
 * not signed out (nobody is logged out as a side effect of a late payment), the app can show a
 * "renew" screen, and the owner can still sign out, change their password and see the business
 * and its dates. Renewing (a super admin sets a new valid_until) opens everything again at once,
 * with nothing lost.
 *
 * Only the owner and staff are held to it. Drivers, tenants and vendors are the business's
 * customers: a late payment by the business does not take their own records away from them.
 * A super admin is never blocked.
 *
 * With enforcement off (the default) this does nothing, not even a query.
 */
class EnsureSubscriptionActive
{
    /** Always reachable, so a blocked person can still see why, sign out and reach their data. */
    private const ALWAYS_OPEN = ['api/auth/*', 'api/business', 'api/business/*', 'api/files/*', 'api/health', 'api/up'];

    public function handle(Request $request, Closure $next): Response
    {
        if (!config('billing.enforce', false) || !$request->bearerToken() || $request->is(...self::ALWAYS_OPEN)) {
            return $next($request);
        }

        $user = $request->user('sanctum');
        if ($user === null || $user->seesAllAccounts() || $user->isPortalUser()) {
            return $next($request);
        }

        $business = Business::forUser($user);
        if ($business !== null && $business->blocksAccess()) {
            return ResponseHelper::error(
                'Usajili wa biashara yako umeisha. Wasiliana na msimamizi ili kuuhuisha. / '
                . 'Your business subscription has expired. Contact your administrator to renew it.',
                402,
                ['code' => 'subscription_expired', 'plan' => $business->plan, 'valid_until' => $business->valid_until?->toIso8601String()]
            );
        }

        return $next($request);
    }
}
