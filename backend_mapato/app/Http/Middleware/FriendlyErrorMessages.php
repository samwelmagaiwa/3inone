<?php

namespace App\Http\Middleware;

use App\Support\FriendlyMessages;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * An error a controller wrote in English only ("Sale already cancelled") reaches the person as a clear two-language sentence that says
 * what to do next. Matched by the exact words, so nothing else changes and an unknown message is left exactly as it was.
 */
class FriendlyErrorMessages
{
    public function handle(Request $request, Closure $next)
    {
        $response = $next($request);

        if ($response instanceof JsonResponse && $response->getStatusCode() >= 400 && $response->getStatusCode() < 500) {
            $data = $response->getData(true);
            if (is_array($data) && isset($data['message']) && is_string($data['message']) && !str_contains($data['message'], ' / ')) {
                $better = FriendlyMessages::text($data['message']);
                if ($better !== null) {
                    $data['message'] = $better;
                    $response->setData($data);
                }
            }
        }

        return $response;
    }
}
