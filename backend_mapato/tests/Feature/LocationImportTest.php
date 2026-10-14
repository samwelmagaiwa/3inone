<?php

namespace Tests\Feature;

use App\Support\LocationImporter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\DataProvider;
use RuntimeException;
use Tests\TestCase;

/**
 * The Region / District / Ward pickers in the app (Add Property, registration) read the `states`, `lgas`, `wards`,
 * `villages` and `places` tables. Nothing in the migrations fills them, and on the live server they were EMPTY, so
 * the pickers could not be opened. These tests pin down the loader that fills them from location-files/*.csv, and
 * the state of the real files.
 */
class LocationImportTest extends TestCase
{
    use RefreshDatabase;

    private const HEADER = 'region,regioncode,district,districtcode,ward,wardcode,street,places';

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'locations_' . uniqid();
        mkdir($this->dir);
    }

    protected function tearDown(): void
    {
        foreach (glob($this->dir . DIRECTORY_SEPARATOR . '*') ?: [] as $file) {
            unlink($file);
        }
        rmdir($this->dir);

        parent::tearDown();
    }

    /** @param  array<int, string>  $lines  CSV lines without the header; Windows line endings, like the real files */
    private function csv(string $file, array $lines): void
    {
        file_put_contents($this->dir . DIRECTORY_SEPARATOR . $file, implode("\r\n", [self::HEADER, ...$lines]) . "\r\n");
    }

    private function import(): array
    {
        return (new LocationImporter($this->dir))->import();
    }

    private function names(string $table): array
    {
        return DB::table($table)->orderBy('name')->pluck('name')->all();
    }

    // ------------------------------------------------------------------ cleaning one name

    #[DataProvider('cleanedNames')]
    public function test_a_name_from_the_files_is_tidied(?string $raw, ?string $expected): void
    {
        $this->assertSame($expected, LocationImporter::clean($raw));
    }

    public static function cleanedNames(): array
    {
        return [
            'line break inside a name' => ["DODOMA\r\nCBD", 'Dodoma Cbd'],
            'doubled and outer spaces' => ['  LINDI   CBD ', 'Lindi Cbd'],
            'upper case' => ['KIVUKONI', 'Kivukoni'],
            'a letter in straight quotes' => ['KOMBO "A"', 'Kombo "A"'],
            'a letter in curly quotes' => ['MAJENGO “A”', 'Majengo “A”'],
            'a letter in single curly quotes' => ['KIKWAKWARU ‘A’', 'Kikwakwaru ‘A’'],
            'brackets' => ['MGULANI (KEKO JUU)', 'Mgulani (Keko Juu)'],
            'slash' => ['K/CENTRE', 'K/Centre'],
            'hyphen at a line break' => ["MAHANGO-\r\nMADIBIRA", 'Mahango- Madibira'],
            'hyphen joining two words' => ['DAR-ES-SALAAM', 'Dar-Es-Salaam'],
            'apostrophe inside a word' => ["NYANG'HWALE", "Nyang'hwale"],
            'curly apostrophe inside a word' => ['CHANG’OMBE', 'Chang’ombe'],
            'apostrophe at the end' => ["HANANG'", "Hanang'"],
            'a digit before a letter' => ['MTAA WA 3B', 'Mtaa Wa 3b'],
            'a tab' => ["KIWANJA CHA\tNDEGE", 'Kiwanja Cha Ndege'],
            'non-breaking space' => ["KIWANJA\u{00A0}CHA NDEGE", 'Kiwanja Cha Ndege'],
            'empty' => ['', null],
            'only spaces and breaks' => [" \r\n ", null],
            'null' => [null, null],
        ];
    }

    // ------------------------------------------------------------------ the defects found in the real files

    public function test_a_district_name_broken_over_two_lines_is_one_clean_district(): void
    {
        // dodoma.csv writes "DODOMA\r\nCBD" inside quotes, and spells the same district both ways
        $this->csv('dodoma.csv', [
            "DODOMA,41,\"DODOMA\r\nCBD\",411,UHURU,41101,KIPANDE,",
            'DODOMA,41,DODOMA  CBD,411,UHURU,41101,MAJENGO,',
            'DODOMA,41,DODOMA CBD,411,MAKOLE,41102,MAKOLE KATI,',
        ]);

        $this->import();

        $this->assertSame(['Dodoma Cbd'], $this->names('lgas'), 'three spellings of one district must become one');
        $this->assertSame(['Makole', 'Uhuru'], $this->names('wards'));
        $this->assertSame(['Kipande', 'Majengo', 'Makole Kati'], $this->names('villages'));
    }

    public function test_wanging_ombe_is_not_split_into_two_words(): void
    {
        // njombe.csv: "WANGING'O\r\nMBE" for the whole district
        $this->csv('njombe.csv', ["NJOMBE,53,\"WANGING'O\r\nMBE\",531,IGIMA,53101,IGIMA KATI,"]);

        $this->import();

        $this->assertSame(["Wanging'ombe"], $this->names('lgas'));
    }

    public function test_dar_es_salaam_and_mpanda_are_spelt_as_the_app_spells_them(): void
    {
        $this->csv('dar-es-salaam.csv', ['DAR-ES-SALAAM,11,ILALA CBD,11,KIVUKONI,11101,KIVUKONI,']);
        $this->csv('katavi.csv', ['KATAVI,45,MPANDA -CBD,451,KAZIMA,45101,KAZIMA KATI,']);

        $this->import();

        $this->assertSame(['Dar es Salaam', 'Katavi'], $this->names('states'));
        $this->assertSame(['Ilala Cbd', 'Mpanda Cbd'], $this->names('lgas'));
    }

    public function test_a_ward_listed_under_several_post_codes_appears_once(): void
    {
        $this->csv('kagera.csv', [
            'KAGERA,35,BUKOBA CBD,351,KASHAI,35108,KASHAI A,',
            'KAGERA,35,BUKOBA CBD,351,KASHAI,35109,KASHAI B,',
            'KAGERA,35,BUKOBA CBD,351,KASHAI,35110,KASHAI A,',   // a repeated street
        ]);

        $this->import();

        $this->assertSame(['Kashai'], $this->names('wards'));
        $this->assertSame(['Kashai A', 'Kashai B'], $this->names('villages'));
    }

    public function test_a_line_without_a_ward_cannot_be_placed_and_is_counted_as_skipped(): void
    {
        $this->csv('tanga.csv', [
            'TANGA,21,TANGA CBD,211,,21101,SOMEWHERE,',
            'TANGA,21,TANGA CBD,211,CHUDA,21102,CHUDA KATI,',
        ]);

        $result = $this->import();

        $this->assertSame(1, $result['found']['skipped']);
        $this->assertSame(2, $result['found']['rows']);
        $this->assertSame(['Chuda'], $this->names('wards'));
    }

    public function test_places_belong_to_their_street_and_a_street_can_have_none(): void
    {
        $this->csv('arusha.csv', [
            'ARUSHA,23,ARUSHA CBD,231,SEKEI,23101,SANAWARI,"KOMBO ""A"""',
            'ARUSHA,23,ARUSHA CBD,231,SEKEI,23101,SANAWARI,KOMBO "A"',   // same place again
            'ARUSHA,23,ARUSHA CBD,231,SEKEI,23101,NAUREI,',               // no place
        ]);

        $this->import();

        $this->assertSame(['Kombo "A"'], $this->names('places'));
        $this->assertSame(
            'Sanawari',
            DB::table('villages')->where('id', DB::table('places')->value('village_id'))->value('name'),
        );
    }

    // ------------------------------------------------------------------ safe to run again, and all or nothing

    public function test_running_it_again_adds_nothing(): void
    {
        $this->csv('arusha.csv', [
            'ARUSHA,23,ARUSHA CBD,231,SEKEI,23101,SANAWARI,KOMBO A',
            'ARUSHA,23,MERU,232,KATI,23201,KATI KATI,',
        ]);

        $first = $this->import();
        $before = array_map(fn (string $t) => DB::table($t)->count(), ['states', 'lgas', 'wards', 'villages', 'places']);
        $second = $this->import();

        $this->assertSame(['states' => 1, 'lgas' => 2, 'wards' => 2, 'villages' => 2, 'places' => 1], $first['added']);
        $this->assertSame(['states' => 0, 'lgas' => 0, 'wards' => 0, 'villages' => 0, 'places' => 0], $second['added']);
        $this->assertSame($before, array_map(fn (string $t) => DB::table($t)->count(), ['states', 'lgas', 'wards', 'villages', 'places']));
    }

    public function test_rows_that_are_already_there_keep_their_ids_and_are_not_doubled(): void
    {
        $stateId = DB::table('states')->insertGetId(['country_code' => 'TZ', 'name' => 'ARUSHA', 'created_at' => now(), 'updated_at' => now()]);
        $lgaId = DB::table('lgas')->insertGetId(['state_id' => $stateId, 'name' => 'Arusha Cbd', 'created_at' => now(), 'updated_at' => now()]);
        $wardId = DB::table('wards')->insertGetId(['lga_id' => $lgaId, 'name' => 'Sekei', 'created_at' => now(), 'updated_at' => now()]);
        $villageId = DB::table('villages')->insertGetId(['ward_id' => $wardId, 'name' => 'Sanawari', 'created_at' => now(), 'updated_at' => now()]);
        DB::table('places')->insert(['village_id' => $villageId, 'name' => 'Kombo A', 'created_at' => now(), 'updated_at' => now()]);

        $this->csv('arusha.csv', ['ARUSHA,23,ARUSHA CBD,231,SEKEI,23101,SANAWARI,KOMBO A', 'ARUSHA,23,ARUSHA CBD,231,SEKEI,23101,SANAWARI,KOMBO B']);
        $result = $this->import();

        $this->assertSame(1, DB::table('states')->count(), 'ARUSHA and Arusha are the same region');
        $this->assertSame($stateId, (int) DB::table('states')->value('id'));
        $this->assertSame('ARUSHA', DB::table('states')->value('name'), 'an existing row is never rewritten');
        $this->assertSame(['states' => 0, 'lgas' => 0, 'wards' => 0, 'villages' => 0, 'places' => 1], $result['added']);
        $this->assertSame(['Kombo A', 'Kombo B'], $this->names('places'));
    }

    public function test_a_failure_part_way_leaves_nothing_behind(): void
    {
        $this->csv('arusha.csv', ['ARUSHA,23,ARUSHA CBD,231,SEKEI,23101,SANAWARI,KOMBO A']);

        // the very last step (places) fails; the regions, districts, wards and streets before it must be undone
        DB::listen(function ($query) {
            if (str_starts_with(strtolower($query->sql), 'insert') && str_contains($query->sql, 'places')) {
                throw new RuntimeException('disk full');
            }
        });

        try {
            $this->import();
            $this->fail('the import should have failed');
        } catch (RuntimeException $e) {
            $this->assertSame('disk full', $e->getMessage());
        }

        foreach (['states', 'lgas', 'wards', 'villages', 'places'] as $table) {
            $this->assertSame(0, DB::table($table)->count(), "{$table} must be left empty");
        }
    }

    public function test_a_folder_without_csv_files_is_an_error_never_a_silent_success(): void
    {
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessage('there are no .csv files');

        $this->import();
    }

    // ------------------------------------------------------------------ the command deploy.sh runs

    public function test_the_command_loads_the_files(): void
    {
        $this->csv('arusha.csv', ['ARUSHA,23,ARUSHA CBD,231,SEKEI,23101,SANAWARI,']);

        $this->artisan('locations:import', ['--path' => $this->dir])
            ->expectsOutputToContain('regions in the database now: 1')
            ->assertExitCode(0);

        $this->assertSame(['Arusha'], $this->names('states'));
    }

    public function test_dry_run_reads_the_files_and_writes_nothing(): void
    {
        $this->csv('arusha.csv', ['ARUSHA,23,ARUSHA CBD,231,SEKEI,23101,SANAWARI,']);

        $this->artisan('locations:import', ['--path' => $this->dir, '--dry-run' => true])
            ->expectsOutputToContain('regions=1')
            ->assertExitCode(0);

        $this->assertSame(0, DB::table('states')->count());
    }

    public function test_if_empty_does_nothing_once_regions_exist_and_loads_when_there_are_none(): void
    {
        $this->csv('arusha.csv', ['ARUSHA,23,ARUSHA CBD,231,SEKEI,23101,SANAWARI,']);

        $this->artisan('locations:import', ['--path' => $this->dir, '--if-empty' => true])->assertExitCode(0);
        $this->assertSame(1, DB::table('states')->count(), 'empty tables: it loads');

        $this->csv('mwanza.csv', ['MWANZA,33,ILEMELA,331,BUHONGWA,33101,BUHONGWA KATI,']);
        $this->artisan('locations:import', ['--path' => $this->dir, '--if-empty' => true])
            ->expectsOutputToContain('already loaded')
            ->assertExitCode(0);
        $this->assertSame(['Arusha'], $this->names('states'), 'regions exist: it leaves them alone, even if a new file appeared');
    }

    public function test_the_command_fails_loudly_and_changes_nothing_when_it_cannot_load(): void
    {
        $this->artisan('locations:import', ['--path' => $this->dir])
            ->expectsOutputToContain('NOT loaded')
            ->assertExitCode(1);
    }

    // ------------------------------------------------------------------ what the app actually calls

    public function test_the_public_endpoints_walk_down_from_region_to_place(): void
    {
        $this->csv('arusha.csv', [
            'ARUSHA,23,ARUSHA CBD,231,SEKEI,23101,SANAWARI,KOMBO A',
            'ARUSHA,23,MERU,232,KATI,23201,KATI KATI,',
        ]);
        $this->import();

        $region = $this->getJson('/api/locations/regions')->assertOk()->assertJsonPath('data.0.name', 'Arusha')->json('data.0.id');
        $districts = $this->getJson("/api/locations/districts?region_id={$region}")->assertOk()->json('data');
        $this->assertSame(['Arusha Cbd', 'Meru'], array_column($districts, 'name'));

        $ward = $this->getJson('/api/locations/wards?district_id=' . $districts[0]['id'])->assertOk()->assertJsonPath('data.0.name', 'Sekei')->json('data.0.id');
        $street = $this->getJson("/api/locations/streets?ward_id={$ward}")->assertOk()->assertJsonPath('data.0.name', 'Sanawari')->json('data.0.id');
        $this->getJson("/api/locations/places?village_id={$street}")->assertOk()->assertJsonPath('data.0.name', 'Kombo A');
    }

    public function test_with_nothing_loaded_the_regions_list_is_empty(): void
    {
        // the situation that made the pickers unusable: an empty list, and no error to explain it
        $this->getJson('/api/locations/regions')->assertOk()->assertExactJson(['success' => true, 'data' => []]);
    }

    // ------------------------------------------------------------------ the real files

    private function realFiles(): LocationImporter
    {
        return new LocationImporter(base_path('location-files'));
    }

    public function test_every_real_file_is_one_region_named_like_its_file_and_every_line_is_usable(): void
    {
        $files = glob(base_path('location-files') . DIRECTORY_SEPARATOR . '*.csv');
        $this->assertCount(31, $files, 'Tanzania has 31 regions: one file each');

        foreach ($files as $file) {
            $dir = sys_get_temp_dir() . DIRECTORY_SEPARATOR . 'one_' . uniqid();
            mkdir($dir);
            copy($file, $dir . DIRECTORY_SEPARATOR . basename($file));
            try {
                $parsed = (new LocationImporter($dir))->parse();
            } finally {
                unlink($dir . DIRECTORY_SEPARATOR . basename($file));
                rmdir($dir);
            }

            $name = basename($file);
            $this->assertCount(1, $parsed['tree'], "{$name} must hold exactly one region");
            $region = array_values($parsed['tree'])[0]['name'];
            $this->assertSame(
                strtolower(str_replace(['-', '_', ' '], '', pathinfo($file, PATHINFO_FILENAME))),
                strtolower(str_replace(['-', '_', ' '], '', $region)),
                "{$name} holds the wrong region ({$region})",
            );
            $this->assertSame(0, $parsed['stats']['skipped'], "{$name} has lines that cannot be placed (no district or ward)");
            $this->assertGreaterThan(0, $parsed['stats']['wards'], $name);
        }
    }

    public function test_the_real_files_load_clean(): void
    {
        // 68,000 lines, and this process has already run the rest of the suite: do not let PHP's default 128 MB decide
        ini_set('memory_limit', '512M');

        $result = $this->realFiles()->import();

        $this->assertSame(31, DB::table('states')->count());
        $this->assertSame(0, $result['found']['skipped']);
        // what is in the files is what is in the tables
        $this->assertSame($result['found']['districts'], DB::table('lgas')->count());
        $this->assertSame($result['found']['wards'], DB::table('wards')->count());
        $this->assertSame($result['found']['streets'], DB::table('villages')->count());
        $this->assertSame($result['found']['places'], DB::table('places')->count());
        $this->assertGreaterThan(160, DB::table('lgas')->count());
        $this->assertGreaterThan(3900, DB::table('wards')->count());

        // no name in any table carries a line break, a tab, a doubled space or an outer space
        foreach (['states', 'lgas', 'wards', 'villages', 'places'] as $table) {
            $bad = array_values(array_filter($this->names($table), fn (string $n) => preg_match('/[\r\n\t]|\s{2,}|^\s|\s$/u', $n) === 1));
            $this->assertSame([], array_slice($bad, 0, 5), "{$table} has untidy names");
        }

        // the places a user will look for
        $regions = $this->names('states');
        foreach (['Dar es Salaam', 'Arusha', 'Dodoma', 'Mjini Magharibi', 'Pemba Kaskazini', 'Unguja Kusini', 'Mwanza'] as $expected) {
            $this->assertContains($expected, $regions);
        }
        $this->assertNotContains('Dar-es-salaam', $regions);

        // the districts that used to be broken
        $njombe = DB::table('states')->where('name', 'Njombe')->value('id');
        $njombeDistricts = DB::table('lgas')->where('state_id', $njombe)->pluck('name')->all();
        $this->assertContains("Wanging'ombe", $njombeDistricts);
        $this->assertSame([], preg_grep('/^Wanging.o /i', $njombeDistricts));
        $wanging = DB::table('lgas')->where('state_id', $njombe)->where('name', "Wanging'ombe")->value('id');
        $this->assertGreaterThan(5, DB::table('wards')->where('lga_id', $wanging)->count());
        $dodoma = DB::table('states')->where('name', 'Dodoma')->value('id');
        $this->assertContains('Dodoma Cbd', DB::table('lgas')->where('state_id', $dodoma)->pluck('name')->all());
        $katavi = DB::table('states')->where('name', 'Katavi')->value('id');
        $this->assertContains('Mpanda Cbd', DB::table('lgas')->where('state_id', $katavi)->pluck('name')->all());

        // every region has districts, every district has wards: no empty branch to get stuck on
        $this->assertSame(0, DB::table('states')->whereNotExists(fn ($q) => $q->select(DB::raw(1))->from('lgas')->whereColumn('lgas.state_id', 'states.id'))->count());
        $this->assertSame(0, DB::table('lgas')->whereNotExists(fn ($q) => $q->select(DB::raw(1))->from('wards')->whereColumn('wards.lga_id', 'lgas.id'))->count());

        // and loading them again changes nothing
        $again = $this->realFiles()->import();
        $this->assertSame(['states' => 0, 'lgas' => 0, 'wards' => 0, 'villages' => 0, 'places' => 0], $again['added']);
    }
}
