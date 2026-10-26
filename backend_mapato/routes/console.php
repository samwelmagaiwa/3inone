<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// Nightly prediction job
Schedule::job(new \App\Jobs\PredictDriverCompletionJob())
    ->dailyAt('01:30');

// Rental billing - run on 1st of each month to generate bills
Schedule::command('rental:generate-bills')
    ->monthlyOn(1, '02:00');

// Rental - check for overdue bills daily at 6 AM
Schedule::command('rental:mark-overdue')
    ->dailyAt('06:00');

// Every morning: text the owners (and the super admin) about plans that are ending or have ended.
// Each reminder goes out once per end date, so running it again changes nothing.
Schedule::command('billing:remind')
    ->dailyAt('08:00')
    ->withoutOverlapping();

// Every morning (09:30 in Tanzania): text salon clients whose time for the next visit has come. A visit is
// texted once; a salon that has not switched reminders on is skipped.
Schedule::command('salon:remind-rebooking')
    ->dailyAt('06:30')
    ->withoutOverlapping();

// Every afternoon (18:00 in Tanzania): remind clients of tomorrow's appointments, once each, for salons that switched it on.
Schedule::command('salon:remind-appointments')
    ->dailyAt('15:00')
    ->withoutOverlapping();

// Every evening (19:30 in Tanzania): text each salon owner how the day went, for salons that switched it on.
Schedule::command('salon:daily-summary')
    ->dailyAt('16:30')
    ->withoutOverlapping();

// Every morning: remember each shop's position, and tell owners how the month ended (report ready, target reached or missed).
Schedule::command('inventory:month-close')
    ->dailyAt('04:30')
    ->withoutOverlapping();

// Every morning (08:30 in Tanzania): wish clients a happy birthday, for salons that switched it on.
Schedule::command('salon:birthday-offers')
    ->dailyAt('05:30')
    ->withoutOverlapping();

// Expired API tokens are already rejected; this just removes the dead rows.
Schedule::command('sanctum:prune-expired --hours=24')
    ->daily();

// Devices nobody has used for a very long time (SANCTUM_IDLE_DAYS, a year by default) are
// already refused; this removes their rows. A device in regular use is never touched.
Schedule::call(fn () => \App\Support\SessionPolicy::pruneIdle())
    ->name('prune-idle-device-sessions')
    ->daily();
