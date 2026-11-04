<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Support\Salon\DemoSalon;
use Illuminate\Console\Command;

/**
 * A complete demo salon for showing the app (see App\Support\Salon\DemoSalon): a business of its own with an owner, an accountant, stylists
 * and months of believable work, made through the app's own endpoints. It never touches another business, sends no SMS, and `--remove`
 * takes away exactly that business and nothing else.
 */
class SalonDemo extends Command
{
    protected $signature = 'salon:demo
        {--days=150 : how many days of work to make (7 to 400)}
        {--seed=2026 : the same number always makes the same salon}
        {--password= : the password every demo person signs in with (made up when left out)}
        {--fresh : take the demo salon away first, if it is already here}
        {--remove : only take the demo salon away}
        {--force : needed on a live server (production), where this adds a business to the real database}';

    protected $description = 'Make (or remove) a complete demo salon with months of believable data, separate from every real business';

    public function handle(): int
    {
        if ($this->option('remove')) {
            $gone = DemoSalon::remove();
            $this->info($gone > 0 ? "The demo salon is gone ({$gone} rows)." : 'There is no demo salon here.');

            return self::SUCCESS;
        }

        if (app()->isProduction() && !$this->option('force')) {
            $this->error('This is a live server: the demo salon would be added to the REAL database (as a business of its own). Run again with --force if that is what you want, or --remove to take it away later.');

            return self::FAILURE;
        }

        if (User::query()->where('email', DemoSalon::OWNER_EMAIL)->exists()) {
            if (!$this->option('fresh')) {
                $this->error('The demo salon is already here. Use --fresh to make it again, or --remove to take it away.');

                return self::FAILURE;
            }
            $this->line('Taking away the old demo salon first ...');
            DemoSalon::remove();
        }

        $demo = new DemoSalon((int) $this->option('days'), (int) $this->option('seed'));
        if ((string) $this->option('password') !== '') {
            $demo->password = (string) $this->option('password');
        }
        $demo->onProgress(fn (string $line) => $this->line($line));

        $this->info('Making the demo salon. This takes a few minutes: every visit goes through the app like a real one.');
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
        $this->line('  revenue    TSh ' . number_format($s['revenue']));
        $this->newLine();
        $this->info('Sign in with:');
        foreach ($s['sign_in'] as $p) {
            $this->line("  {$p['role']}: {$p['name']}  email {$p['email']}  phone {$p['phone']}");
        }
        $this->line("  password: {$s['password']}  (shown once, kept nowhere else)");

        return self::SUCCESS;
    }
}
