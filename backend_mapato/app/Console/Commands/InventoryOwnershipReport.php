<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Support\Tenancy\TenantContext;
use App\Support\Tenancy\TenantTables;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Post-deploy check for inventory isolation: how many rows each business owns
 * per table, and whether any row has no owner (invisible to every business).
 * Read-only.
 */
class InventoryOwnershipReport extends Command
{
    protected $signature = 'inventory:ownership-report';

    protected $description = 'Show how many inventory rows each business owns, and any rows with no owner';

    public function handle(): int
    {
        $owners = [];
        $unowned = 0;

        TenantContext::withoutScope(function () use (&$owners, &$unowned) {
            foreach (TenantTables::INVENTORY as $table) {
                $unowned += DB::table($table)->whereNull(TenantTables::OWNER_COLUMN)->count();

                foreach (DB::table($table)->whereNotNull(TenantTables::OWNER_COLUMN)
                    ->select(TenantTables::OWNER_COLUMN, DB::raw('count(*) as total'))
                    ->groupBy(TenantTables::OWNER_COLUMN)->get() as $row) {
                    $owners[$row->owner_id][$table] = (int) $row->total;
                }
            }
        });

        if ($owners === []) {
            $this->line('No inventory rows belong to any business yet.');
        }

        foreach ($owners as $ownerId => $tables) {
            $owner = User::query()->find($ownerId);
            $this->info(($owner ? "{$owner->name} <{$owner->email}>" : "unknown user {$ownerId}") . ': ' . array_sum($tables) . ' rows');
            foreach ($tables as $table => $count) {
                $this->line("    {$table}: {$count}");
            }
        }

        if ($unowned > 0) {
            $this->error("{$unowned} rows have NO owner and are invisible to every business. Fix: php artisan inventory:assign-owner <email>");

            return self::FAILURE;
        }

        $this->info('Every inventory row has an owner.');

        return self::SUCCESS;
    }
}
