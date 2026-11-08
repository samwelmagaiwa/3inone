<?php

namespace App\Http\Middleware;

use App\Support\Salon\SalonAccess;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * The administrator's side of attendance (approve phones, offices and places, the log, the on/off switch) is each its own right, in the
 * salon AND in the shop or depot. Unlike `salon_module` (which lets everyone through outside a salon, because the salon's rights do not
 * exist elsewhere) this one always asks: a shop's cashier must never be able to approve a phone or read the log. The owner and managers
 * hold all four by default; the owner can give or take each back for one person on the access screen.
 */
class EnsureAttendanceRight
{
    public function handle(Request $request, Closure $next, string ...$rights): Response
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['message' => 'Unauthenticated.'], 401);
        }

        foreach ($rights as $right) {
            if (SalonAccess::can($user, trim($right))) {
                return $next($request);
            }
        }

        return response()->json([
            'message' => 'Hauna ruhusa ya sehemu hii. Muulize mmiliki wa biashara. / You do not have access to this section. Ask the business owner.',
            'code' => 'module_not_allowed',
            'required_any' => $rights,
        ], 403);
    }
}
