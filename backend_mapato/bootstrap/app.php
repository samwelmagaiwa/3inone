<?php

use Illuminate\Auth\AuthenticationException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withCommands([
        \App\Console\Commands\MakeSuperAdmin::class,
    ])
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->api(prepend: [
            \Laravel\Sanctum\Http\Middleware\EnsureFrontendRequestsAreStateful::class,
        ], append: [
            \App\Http\Middleware\FriendlyErrorMessages::class,
            // Does nothing unless BILLING_ENFORCE is on (config/billing.php).
            \App\Http\Middleware\EnsureSubscriptionActive::class,
        ]);
        
        $middleware->alias([
            'role'     => \App\Http\Middleware\RoleMiddleware::class,
            'role_any' => \App\Http\Middleware\RoleAny::class,
            'inv_perm' => \App\Http\Middleware\CheckInventoryPermission::class,
            'service'  => \App\Http\Middleware\EnsureServiceAccess::class,
        ]);
        
        $middleware->validateCsrfTokens(except: [
            'api/*',
        ]);

        // The container sits behind aaPanel's nginx, so every request reaches us
        // from the Docker gateway (172.20.0.1) and request()->ip() was the same
        // for every client -- which made per-IP rate limits and audit/login logs
        // useless. Trust forwarded headers ONLY from private/loopback addresses
        // (the proxy), never from a client on the public internet, so the
        // X-Forwarded-For header can't be spoofed to dodge a limit.
        $middleware->trustProxies(at: [
            '127.0.0.1',
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
        ]);

        // API-only backend: there is no 'login' route. Laravel's
        // ApplicationBuilder pre-registers a default redirect callback of
        // `fn () => route('login')`; Authenticate::unauthenticated() calls
        // that callback EAGERLY while building the AuthenticationException
        // whenever the request doesn't look like it expects JSON (a mobile
        // HTTP client that omits Accept: application/json, say) -- so it
        // throws RouteNotFoundException before the AuthenticationException
        // even exists, crashing as a raw 500 instead of reaching any
        // exception render callback. Overriding it to return null stops
        // that eager crash; the render() below turns the resulting
        // AuthenticationException into a proper 401 JSON response.
        $middleware->redirectGuestsTo(fn () => null);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // API-only backend: there is no 'login' route to redirect guests to.
        // Laravel's default Handler::unauthenticated() falls back to
        // route('login') whenever the request doesn't look like it expects
        // JSON (e.g. a mobile HTTP client that omits Accept: application/json)
        // -- that route doesn't exist here, so it throws RouteNotFoundException
        // and a plain unauthenticated request crashes as a raw 500 instead of
        // the intended 401. Render it as JSON unconditionally instead.
        // Validation: the message is the first thing wrong, in plain words (not "... (and 2 more errors)"), the full list stays in errors.
        $exceptions->render(function (\Illuminate\Validation\ValidationException $e, Request $request) {
            if (!$request->expectsJson() && !$request->is('api/*')) {
                return null;
            }
            $first = collect($e->errors())->flatten()->first();

            return response()->json(['message' => $first ?? $e->getMessage(), 'errors' => $e->errors()], $e->status);
        });
        $exceptions->render(function (AuthenticationException $e, Request $request) {
            return response()->json(['message' => $e->getMessage()], 401);
        });
    })->create();
