<?php

return [

    /*
    | Server-side service access.
    |
    | A business owner is given services (inventory / rental / transport / salon) by a
    | super admin, and the API only serves the services a user -- and the
    | account head above them -- has been given. Before this, only the mobile
    | app hid the other services; the server answered anyone who called them.
    |
    | SERVICE_ENFORCEMENT=false is an emergency switch that stops the API from
    | checking. Leave it on.
    */
    'enforce_services' => env('SERVICE_ENFORCEMENT', true),

    /** The services a business can be given. Salon runs on the same sales engine as inventory. */
    'services' => ['inventory', 'rental', 'transport', 'salon'],

];
