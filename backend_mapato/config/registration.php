<?php

return [
    /*
     * A business must say where it is: the applicant captures the spot with their phone, standing at the business, when asking to use the
     * system, and the super admin opens it on a map to decide. Turn off only for a client that cannot read a location.
     */
    'require_location' => (bool) env('REGISTRATION_REQUIRE_LOCATION', true),
];
