<?php

namespace App\Http\Middleware;

use App\Support\Groups\GroupAccess;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * "ME": the Vikundi app sends X-Group-View: member while a leader looks at the group as an ordinary member. From then on this request is
 * answered as for a plain member (no office rights, no leaders' lists or notices). It can only take rights away from the caller, never add any.
 */
class GroupViewAs
{
    public function handle(Request $request, Closure $next): Response
    {
        GroupAccess::viewAsMember(strtolower((string) $request->header('X-Group-View')) === 'member');

        return $next($request);
    }
}
