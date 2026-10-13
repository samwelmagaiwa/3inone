<?php

return [
    // How long a signed link to a private upload (lease document, tenant photo, repair photo,
    // report) keeps working after the API hands it out. Long enough for a screen left open;
    // short enough that a link someone forwards soon stops working.
    'link_hours' => (int) env('UPLOAD_LINK_HOURS', 6),
];
