<?php

namespace Database\Seeders;

use App\Support\LocationImporter;
use Illuminate\Database\Seeder;

class TanzaniaLocationsFromCsvSeeder extends Seeder
{
    /**
     * Seed Tanzania's regions, districts, wards, streets and places from the CSV files in the "location-files"
     * folder at the project root. All the work (name cleaning, batching, one transaction, safe to re-run) is in
     * App\Support\LocationImporter; `php artisan locations:import` does the same from the command line.
     */
    public function run(): void
    {
        $result = (new LocationImporter(base_path('location-files')))->import();

        $this->command?->info('locations added: ' . json_encode($result['added']));
    }
}
