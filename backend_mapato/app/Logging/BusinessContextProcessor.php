<?php

namespace App\Logging;

use App\Models\User;
use Monolog\LogRecord;

/**
 * Stamps every log line written during a signed-in request with WHO and WHICH BUSINESS,
 * so a problem report ("something odd happened to Asha's depot at 14:10") can be found in
 * the log by business id instead of by guessing. Lines written outside a request (queue
 * workers, artisan) are left as they are.
 */
class BusinessContextProcessor
{
    public function __invoke(LogRecord $record): LogRecord
    {
        try {
            $user = auth()->user();
        } catch (\Throwable) {
            return $record; // logging must never be the thing that fails
        }

        if (!$user instanceof User) {
            return $record;
        }

        try {
            $business = $user->accountHeadId();
        } catch (\Throwable) {
            $business = null;
        }

        return $record->with(extra: $record->extra + [
            'user_id' => (string) $user->id,
            'business_id' => $business,
        ]);
    }
}
