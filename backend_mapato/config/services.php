<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    // Sign in with Google: the ids of this app's OAuth clients (the Web one is the audience of every token the phone sends; the Android
    // one is kept for completeness). They are public identifiers, not secrets.
    'google' => [
        'client_ids' => array_values(array_filter(array_map('trim', explode(',', (string) env(
            'GOOGLE_CLIENT_IDS',
            '427281190551-t67r5mg72ccnso67epg96srp3jkn36cg.apps.googleusercontent.com,427281190551-ctkma33d44dtdpa3kborjmskb71tp1li.apps.googleusercontent.com'
        ))))),
    ],

    'postmark' => [
        'token' => env('POSTMARK_TOKEN'),
    ],

    'resend' => [
        'key' => env('RESEND_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    // The business adviser (inventory > monthly report > Where to improve). Without a key the advice is written by plain rules.
    // Gemini is used when its key is set, otherwise Anthropic.
    'gemini' => [
        'key' => env('GEMINI_API_KEY'),
        'model' => env('GEMINI_MODEL', 'gemini-3.5-flash-lite'),
        // Tried in order when the model above runs out of quota or is overloaded (comma separated); unset = the built-in list.
        'models' => env('GEMINI_MODELS'),
    ],

    'anthropic' => [
        'key' => env('ANTHROPIC_API_KEY'),
        'model' => env('ANTHROPIC_MODEL', 'claude-sonnet-5-5'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

];
