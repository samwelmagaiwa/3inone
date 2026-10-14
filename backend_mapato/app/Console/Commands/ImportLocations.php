<?php

namespace App\Console\Commands;

use App\Support\LocationImporter;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Throwable;

/**
 * Load the regions / districts / wards / streets / places the app's pickers show, from location-files/*.csv.
 *
 * Without this data the Region, District and Ward lists in "Add Property" (and the registration form) are empty
 * and cannot be opened. It is NOT part of the migrations, so a new server needs it run once. It adds only what is
 * missing, never changes or deletes a row, and does everything in one transaction.
 *
 *   php artisan locations:import --dry-run    read the files and say what they hold; changes nothing
 *   php artisan locations:import --if-empty   load them only when no region exists yet (what deploy.sh runs)
 *   php artisan locations:import              add whatever is missing
 */
class ImportLocations extends Command
{
    protected $signature = 'locations:import
        {--if-empty : do nothing when regions are already loaded}
        {--dry-run : read the files and report, write nothing}
        {--path= : folder holding the CSV files (default: location-files)}';

    protected $description = 'Load Tanzania regions, districts, wards, streets and places from location-files/*.csv';

    public function handle(): int
    {
        $importer = new LocationImporter((string) ($this->option('path') ?: base_path('location-files')));

        try {
            if ($this->option('dry-run')) {
                $this->report('in the files', $importer->parse()['stats']);
                $this->line('regions in the database now: ' . DB::table('states')->count());

                return self::SUCCESS;
            }

            $have = DB::table('states')->count();
            if ($this->option('if-empty') && $have > 0) {
                $this->info("locations already loaded ({$have} regions): nothing to do");

                return self::SUCCESS;
            }

            $result = $importer->import();
        } catch (Throwable $e) {
            $this->error('locations were NOT loaded (nothing was changed): ' . $e->getMessage());

            return self::FAILURE;
        }

        $this->report('in the files', $result['found']);
        $this->report('added to the database', $result['added']);
        $this->info('regions in the database now: ' . DB::table('states')->count());

        return self::SUCCESS;
    }

    /** @param  array<string, int>  $numbers */
    private function report(string $title, array $numbers): void
    {
        $this->line($title . ': ' . implode(', ', array_map(fn ($k, $v) => "{$k}={$v}", array_keys($numbers), $numbers)));
    }
}
