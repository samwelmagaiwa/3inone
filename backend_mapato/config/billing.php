<?php

return [

    /*
    | Plans and the paid-until date of a business.
    |
    | Every business (see App\Models\Business) has a `plan` and a `valid_until`. A super admin
    | sets them; `valid_until` empty means the business never expires. Nothing is locked until
    | BILLING_ENFORCE is switched on, so recording the fields costs nobody access: turn it on
    | once you have decided how you will charge.
    |
    | When enforcement is on, a business whose `valid_until` plus the grace period has passed
    | cannot sign in, and a device that is already signed in gets HTTP 402 with the code
    | `subscription_expired` (NOT 401, so the app is never signed out as a side effect; it can
    | show "renew" and let the owner reach the profile and sign-out screens).
    */
    'enforce' => env('BILLING_ENFORCE', false),

    /** Days a business may keep working after valid_until before it is blocked. */
    'grace_days' => (int) env('BILLING_GRACE_DAYS', 7),

    /** Length of the trial a newly approved registration starts on. */
    'trial_days' => (int) env('BILLING_TRIAL_DAYS', 30),

    /**
     * The plans a super admin can choose from, in the order the app shows them.
     * `free` is also what every business that existed before plans did is given: no expiry.
     */
    'plans' => ['trial', 'free', 'basic', 'standard', 'premium'],

    /** What a business that was never given a plan starts with: no plan, no expiry, no lockout. */
    'default_plan' => 'free',

    /** Plan a freshly approved self-registration starts on (with trial_days of access). */
    'registration_plan' => 'trial',

    /**
     * Where a customer is told to reach you to pay (shown in "my subscription" and in the reminder texts).
     * Leave empty to say nothing; set BILLING_CONTACT_PHONE in the server's .env.
     */
    'contact_phone' => env('BILLING_CONTACT_PHONE', ''),

];
