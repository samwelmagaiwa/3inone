<?php

use Laravel\Sanctum\Sanctum;

return [

    /*
    |--------------------------------------------------------------------------
    | Stateful Domains
    |--------------------------------------------------------------------------
    |
    | Requests from the following domains / hosts will receive stateful API
    | authentication cookies. Typically, these should include your local
    | and production domains which access your API via a frontend SPA.
    |
    */

    'stateful' => explode(',', env('SANCTUM_STATEFUL_DOMAINS', sprintf(
        '%s%s%s',
        'localhost,localhost:3000,127.0.0.1,127.0.0.1:8000,::1',
        Sanctum::currentApplicationUrlWithPort(),
        env('FRONTEND_URL') ? ','.parse_url(env('FRONTEND_URL'), PHP_URL_HOST) : ''
    ))),

    /*
    |--------------------------------------------------------------------------
    | Sanctum Guards
    |--------------------------------------------------------------------------
    |
    | This array contains the authentication guards that will be checked when
    | Sanctum is trying to authenticate a request. If none of these guards
    | are able to authenticate the request, Sanctum will use the bearer
    | token that's present on an incoming request for authentication.
    |
    */

    'guard' => ['web'],

    /*
    |--------------------------------------------------------------------------
    | Expiration Minutes
    |--------------------------------------------------------------------------
    |
    | This value controls the number of minutes until an issued token will be
    | considered expired. This will override any values set in the token's
    | "expires_at" attribute, but first-party sessions are not affected.
    |
    */

    // No fixed lifetime: a device stays signed in for as long as it is used (see
    // App\Support\SessionPolicy). Set minutes here only to bring back a hard limit, which
    // signs out everyone that long after they signed in, however busy they are.
    'expiration' => env('SANCTUM_TOKEN_EXPIRATION_MINUTES') ? (int) env('SANCTUM_TOKEN_EXPIRATION_MINUTES') : null,

    /*
    |--------------------------------------------------------------------------
    | Concurrent Sessions
    |--------------------------------------------------------------------------
    |
    | How many devices one account may be signed in on at once. 0 (the default) means
    | no limit: signing in on another device never ends any other. Set a number only
    | if you want a cap, in which case the OLDEST session is the one signed out.
    |
    */

    'max_sessions' => (int) env('SANCTUM_MAX_SESSIONS', 0),

    /*
    |--------------------------------------------------------------------------
    | Idle Limit
    |--------------------------------------------------------------------------
    |
    | Days a device may go completely unused before its session is dropped. Measured
    | from its last use, so a device in regular use never reaches it. 0 = never.
    |
    */

    'idle_days' => (int) env('SANCTUM_IDLE_DAYS', 365),

    /*
    |--------------------------------------------------------------------------
    | Token Renewal Grace
    |--------------------------------------------------------------------------
    |
    | When the app swaps its token for a fresh one, the old token keeps working for
    | this many minutes (7 days by default): if the reply is lost on a bad connection
    | and the phone is offline for a while, it must not wake up signed out.
    |
    */

    'refresh_grace_minutes' => (int) env('SANCTUM_REFRESH_GRACE_MINUTES', 60 * 24 * 7),

    /*
    |--------------------------------------------------------------------------
    | Password Change
    |--------------------------------------------------------------------------
    |
    | Changing the password keeps the device it was changed on signed in. With true
    | (the default) the person's OTHER devices are signed out, which is the point of
    | changing a password you think someone else knows; false leaves them signed in.
    |
    */

    'revoke_other_devices_on_password_change' => (bool) env('SANCTUM_REVOKE_OTHERS_ON_PASSWORD_CHANGE', true),

    /*
    |--------------------------------------------------------------------------
    | Token Prefix
    |--------------------------------------------------------------------------
    |
    | Sanctum can prefix new tokens in order to take advantage of numerous
    | security scanning initiatives maintained by open source platforms
    | that notify developers if they commit tokens into repositories.
    |
    | See: https://docs.github.com/en/code-security/secret-scanning/about-secret-scanning
    |
    */

    'token_prefix' => env('SANCTUM_TOKEN_PREFIX', ''),

    /*
    |--------------------------------------------------------------------------
    | Sanctum Middleware
    |--------------------------------------------------------------------------
    |
    | When authenticating your first-party SPA with Sanctum you may need to
    | customize some of the middleware Sanctum uses while processing the
    | request. You may change the middleware listed below as required.
    |
    */

    'middleware' => [
        'authenticate_session' => Laravel\Sanctum\Http\Middleware\AuthenticateSession::class,
        'encrypt_cookies' => Illuminate\Cookie\Middleware\EncryptCookies::class,
        'validate_csrf_token' => Illuminate\Foundation\Http\Middleware\ValidateCsrfToken::class,
    ],

];