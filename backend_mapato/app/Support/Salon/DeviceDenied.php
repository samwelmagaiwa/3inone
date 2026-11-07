<?php

namespace App\Support\Salon;

/** An attendance request that failed a mandatory check: `outcome` is the status code the apps show and the log keeps. */
final class DeviceDenied extends \RuntimeException
{
    public function __construct(public readonly string $outcome, string $message)
    {
        parent::__construct($message);
    }
}
