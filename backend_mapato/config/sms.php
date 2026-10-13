<?php

/*
 | SMS delivery.
 |
 | Nothing here is a secret: the key and secret come from the environment (.env on the
 | server), never from this file or from git. With SMS_ENABLED false, or no key, the app
 | still works -- messages are only logged -- but anything that needs the phone to prove
 | who someone is (password reset, registration check) refuses to run in production.
 */
return [
    // 'kilakona' sends for real; anything else only logs.
    'driver' => env('SMS_DRIVER', 'log'),

    'enabled' => (bool) env('SMS_ENABLED', false),

    // Prefix for numbers written the local way (0743...). Tanzania is 255.
    'country_code' => env('SMS_COUNTRY_CODE', '255'),

    // Extra numbers (comma separated) texted when a business applies to register, on top of every
    // active super admin who has a phone number saved: an office phone, or an owner who is not a login.
    'admin_notify_phones' => env('SUPER_ADMIN_NOTIFY_PHONES', ''),

    'kilakona' => [
        'api_url' => env('SMS_API_URL', 'https://messaging.kilakona.co.tz/api/v1/vendor/message/send'),
        'api_key' => env('SMS_API_KEY', ''),
        'secret_key' => env('SMS_SECRET_KEY', ''),
        'sender_id' => env('SMS_SENDER_ID', ''),
        'timeout' => 10,
    ],
];
