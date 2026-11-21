<?php

namespace App\Http\Middleware;

use App\Support\Groups\GroupAccess;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * ->middleware('group_right:verify_payments') lets in only whoever holds that right in their group (any one of several when more are
 * named). The rights come from the office a member holds; the business owner holds them all. See App\Support\Groups\GroupOffices.
 */
class EnsureGroupRight
{
    public function handle(Request $request, Closure $next, string ...$rights): Response
    {
        $user = $request->user();
        if (!$user) {
            return response()->json(['message' => 'Unauthenticated.'], 401);
        }

        // Each request reads the person's office and status afresh.
        GroupAccess::forget();

        foreach ($rights as $right) {
            if (GroupAccess::can($user, trim($right))) {
                return $next($request);
            }
        }

        return response()->json([
            'message' => 'Huna ruhusa ya sehemu hii ya kikundi. / You do not have access to this part of the group.',
            'code' => 'group_right_missing',
            'required_any' => $rights,
        ], 403);
    }
}
