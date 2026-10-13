<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Services\Inventory\InventoryOwnership;
use Illuminate\Console\Command;

/**
 * Safe, repeatable way to put inventory data in the right business's hands.
 *
 *   inventory:assign-owner <owner>
 *       gives rows that have NO owner (and orphaned inventory staff) to that business --
 *       for after the isolation migration found no obvious owner;
 *   inventory:assign-owner <owner> --from=<wrong-owner>
 *       moves a whole depot from one business to another -- the correction for when the
 *       migration picked the wrong owner.
 *
 * Always run with --dry-run first: it shows what would change and changes nothing.
 */
class AssignInventoryOwner extends Command
{
    protected $signature = 'inventory:assign-owner
                            {user : Email or id of the business owner who should own the depot (an admin or landlord)}
                            {--from= : Move the rows this owner has (email or id) instead of filling in unowned ones}
                            {--dry-run : Show what would change and change nothing}';

    protected $description = 'Give inventory rows with no owner (or a wrong one) to one business';

    public function handle(InventoryOwnership $ownership): int
    {
        $owner = $this->find((string) $this->argument('user'));
        if ($owner === null) {
            $this->error('No user with the id or email "' . $this->argument('user') . '".');

            return self::FAILURE;
        }

        if (!in_array(strtolower((string) $owner->role), User::ACCOUNT_HEAD_ROLES, true)) {
            $this->error("{$owner->email} is a {$owner->role}, not a business owner (admin / landlord). Choose the owner of the business.");

            return self::FAILURE;
        }

        $this->info("Owner: {$owner->name} <{$owner->email}>");

        $others = $ownership->candidates()->where('id', '!=', $owner->id);
        if ($others->isNotEmpty()) {
            $this->warn('Other active owners also hold the inventory service: ' . $others->pluck('email')->implode(', ')
                . '. Only one business can own the existing depot; they will not see it.');
        }

        if ($this->option('from') !== null && $this->option('from') !== '') {
            return $this->moveDepot($ownership, $owner);
        }

        return $this->fillUnowned($ownership, $owner);
    }

    private function fillUnowned(InventoryOwnership $ownership, User $owner): int
    {
        $unowned = array_filter($ownership->unownedRows());
        $orphans = $ownership->orphanStaff($owner);

        $this->line('Rows without an owner: ' . (array_sum($unowned) ?: 'none'));
        foreach ($unowned as $table => $count) {
            $this->line("  {$table}: {$count}");
        }
        $this->line('Inventory staff without a business: ' . ($orphans->isEmpty() ? 'none' : $orphans->pluck('email')->implode(', ')));

        if ($this->option('dry-run')) {
            $this->warn('Dry run: nothing was changed.');

            return self::SUCCESS;
        }

        $result = $ownership->assign($owner);
        $this->info('Done. Rows assigned: ' . array_sum($result['rows']) . '; staff moved: ' . count($result['adopted']) . '.');

        return self::SUCCESS;
    }

    private function moveDepot(InventoryOwnership $ownership, User $to): int
    {
        $from = $this->find((string) $this->option('from'));
        if ($from === null) {
            $this->error('No user with the id or email "' . $this->option('from') . '" to move the depot from.');

            return self::FAILURE;
        }
        if ((string) $from->id === (string) $to->id) {
            $this->error('The depot is already owned by that business.');

            return self::FAILURE;
        }

        $owned = array_filter($ownership->ownedBy($from));
        $this->line("Rows owned by {$from->email}: " . (array_sum($owned) ?: 'none'));
        foreach ($owned as $table => $count) {
            $this->line("  {$table}: {$count}");
        }

        if ($this->option('dry-run')) {
            $holds = $ownership->ownDepot($to);
            if ($holds !== []) {
                $this->error("Would be refused: {$to->email} already has its own inventory data (" . implode(', ', array_keys($holds)) . ').');

                return self::FAILURE;
            }
            $this->warn('Dry run: nothing was changed.');

            return self::SUCCESS;
        }

        try {
            $moved = $ownership->reassign($from, $to);
        } catch (\DomainException $e) {
            $this->error($e->getMessage());

            return self::FAILURE;
        }

        $this->info("Done. Moved " . array_sum($moved) . " rows from {$from->email} to {$to->email}.");

        return self::SUCCESS;
    }

    private function find(string $key): ?User
    {
        return User::query()->where('id', $key)->orWhere('email', $key)->first();
    }
}
