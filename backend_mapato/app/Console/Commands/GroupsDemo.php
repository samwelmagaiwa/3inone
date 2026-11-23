<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Support\Groups\DemoGroup;
use Illuminate\Console\Command;

/**
 * A complete demo savings group (Vikundi) for showing the app to stakeholders (see App\Support\Groups\DemoGroup): a business of its own with an
 * administrator and twenty members with every detail filled in, a year of contributions, savings, loans, welfare, hires, projects, expenses,
 * a dividend, meetings and notices, made through the app's own endpoints. It never touches another business, sends no SMS, and `--remove` takes
 * away exactly that business and nothing else.
 */
class GroupsDemo extends Command
{
    protected $signature = 'groups:demo
        {--months=12 : how many months of history to make (12 to 18)}
        {--seed=2026 : the same number always makes the same group}
        {--password= : the password every demo person signs in with (made up when left out)}
        {--fresh : take the demo group away first, if it is already here}
        {--remove : only take the demo group away}
        {--force : needed on a live server (production), where this adds a business to the real database}';

    protected $description = 'Make (or remove) a complete demo savings group with twenty members and a year of believable data, separate from every real business';

    public function handle(): int
    {
        if ($this->option('remove')) {
            $gone = DemoGroup::remove();
            $this->info($gone > 0 ? "The demo group is gone ({$gone} rows)." : 'There is no demo group here.');

            return self::SUCCESS;
        }

        if (app()->isProduction() && !$this->option('force')) {
            $this->error('This is a live server: the demo group would be added to the REAL database (as a business of its own). Run again with --force if that is what you want, or --remove to take it away.');

            return self::FAILURE;
        }

        if (User::query()->withoutGlobalScopes()->where('email', DemoGroup::ADMIN_EMAIL)->exists()) {
            if (!$this->option('fresh')) {
                $this->error('The demo group is already here. Use --fresh to make it again, or --remove to take it away.');

                return self::FAILURE;
            }
            $this->line('Taking away the old demo group first ...');
            DemoGroup::remove();
        }

        $demo = new DemoGroup((int) $this->option('months'), (int) $this->option('seed'));
        if ((string) $this->option('password') !== '') {
            $demo->password = (string) $this->option('password');
        }
        $demo->onProgress(fn (string $line) => $this->line($line));

        $this->info('Making the demo group. This takes a few minutes: every payment goes through the app like a real one.');
        try {
            $s = $demo->build();
        } catch (\Throwable $e) {
            $this->error('It stopped: ' . $e->getMessage());
            $this->line('Whatever was made is still there: run again with --fresh (or --remove) to clear it.');

            return self::FAILURE;
        }

        $this->newLine();
        $this->info("{$s['business']}: {$s['from']} to {$s['to']}");
        foreach ($s['made'] as $what => $n) {
            $this->line(sprintf('  %-10s %d', $what, $n));
        }
        $this->newLine();
        $this->info('Sign in with (the phone number or the e-mail, and the password):');
        foreach ($s['sign_in'] as $p) {
            $this->line(sprintf('  %-24s %-34s %s', $p['role'], $p['name'], $p['login']));
        }
        $this->line("  password: {$s['password']}  (shown once, kept nowhere else)");

        return self::SUCCESS;
    }
}
