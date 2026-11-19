<?php

namespace App\Console\Commands;

use App\Support\SmsQuota;
use Illuminate\Console\Command;

/**
 * Every night: delete the logged texts older than 3 days (the list the super admin reads). The counters
 * (businesses.sms_used and sms_daily_counts) are never touched, so "200/5000" and "this week" stay right.
 */
class PruneSmsLog extends Command
{
    protected $signature = 'sms:prune-log';

    protected $description = 'Delete logged business texts older than 3 days (counters are kept)';

    public function handle(): int
    {
        $this->info(SmsQuota::prune() . ' logged text(s) older than ' . SmsQuota::LOG_DAYS . ' days deleted');

        return self::SUCCESS;
    }
}
