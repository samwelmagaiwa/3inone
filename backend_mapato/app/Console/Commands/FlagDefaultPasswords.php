<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Support\Tenancy\TenantContext;
use App\Support\TemporaryPassword;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;

/**
 * Earlier versions gave every tenant, driver, fundi and caretaker the same fixed password
 * ("tenant123", "password123", "caretaker123", "12345678"). New accounts no longer get one,
 * but the accounts that already exist still do. This finds them and makes each person choose
 * their own password the next time they sign in.
 *
 * It does NOT change anyone's password, so nobody is locked out: they sign in as usual and
 * the app then insists on a new one. Safe to run again; run with --dry-run first.
 */
class FlagDefaultPasswords extends Command
{
    protected $signature = 'users:flag-default-passwords {--dry-run : List who would be flagged and change nothing}';

    protected $description = 'Make accounts that still use a retired default password choose their own at next sign-in';

    public function handle(): int
    {
        $flagged = [];

        TenantContext::withoutScope(function () use (&$flagged) {
            User::query()
                ->where(fn ($q) => $q->where('must_change_password', false)->orWhereNull('must_change_password'))
                ->orderBy('id')
                ->chunk(200, function ($users) use (&$flagged) {
                    foreach ($users as $user) {
                        if (!$this->usesRetiredDefault($user)) {
                            continue;
                        }

                        $flagged[] = $user->email ?: $user->phone_number ?: (string) $user->id;

                        if (!$this->option('dry-run')) {
                            $user->must_change_password = true;
                            $user->save();
                        }
                    }
                });
        });

        if ($flagged === []) {
            $this->info('No account uses a retired default password.');

            return self::SUCCESS;
        }

        $this->line(($this->option('dry-run') ? 'Would flag ' : 'Flagged ') . count($flagged) . ' account(s):');
        foreach ($flagged as $who) {
            $this->line("  {$who}");
        }
        $this->option('dry-run')
            ? $this->warn('Dry run: nothing was changed.')
            : $this->info('Each will be asked to choose a new password at their next sign-in.');

        return self::SUCCESS;
    }

    private function usesRetiredDefault(User $user): bool
    {
        foreach (TemporaryPassword::RETIRED_DEFAULTS as $default) {
            try {
                if (Hash::check($default, (string) $user->password)) {
                    return true;
                }
            } catch (\RuntimeException) {
                return false; // not a hash this app made (so not one of the defaults)
            }
        }

        return false;
    }
}
