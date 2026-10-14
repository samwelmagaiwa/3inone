<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Loads Tanzania's regions -> districts -> wards -> streets -> places from the CSV files in `location-files/`
 * into the `states`, `lgas`, `wards`, `villages` and `places` tables that the app's location pickers read.
 *
 * Safe to run again at any time: nothing is ever updated or deleted, a row that is already there is left alone
 * and only what is missing is added. Everything goes in ONE transaction, so a failure leaves the tables exactly
 * as they were (no half-loaded country). Rows go in by the hundred, not one query per row: the files hold about
 * 68,000 lines.
 *
 * The files are government/post-office exports and are not tidy, which is why names are cleaned (see clean()):
 * line breaks inside a name ("DODOMA\r\nCBD"), doubled spaces, upper case, and a few names that are broken or
 * misspelt in the source. Names are cleaned BEFORE they are compared, so "Dodoma\r\nCBD" and "DODOMA CBD" become
 * the one district they always were.
 */
final class LocationImporter
{
    /** Region spellings the source gets wrong. Key = the cleaned name in lower case. */
    private const REGIONS = [
        'dar-es-salaam' => 'Dar es Salaam',
    ];

    /** District spellings the source gets wrong. Key = the cleaned name in lower case. */
    private const DISTRICTS = [
        // njombe.csv breaks the word across two lines: "WANGING'O\r\nMBE" (525 rows, the whole district)
        "wanging'o mbe" => "Wanging'ombe",
        // katavi.csv: "MPANDA -CBD"
        'mpanda -cbd' => 'Mpanda Cbd',
    ];

    private const COUNTRY = 'TZ';

    /** Rows per INSERT: 4 columns x 200 stays under the 999-variable limit of older SQLite builds, and is far below MariaDB's. */
    private const CHUNK = 200;

    public function __construct(private readonly string $directory)
    {
    }

    /**
     * Tidy one name from a CSV: any run of white space (including a line break) becomes a single space, the ends
     * are trimmed, and each word gets a capital letter. A capital also follows - / ( and quotes, so "KOMBO "A""
     * and "MGULANI (KEKO JUU)" read properly; an apostrophe inside a word (NYANG'HWALE) does not start a new word.
     */
    public static function clean(?string $value): ?string
    {
        $value = trim((string) preg_replace('/[\s\x{00A0}]+/u', ' ', (string) $value));
        if ($value === '') {
            return null;
        }

        $chars = preg_split('//u', mb_strtolower($value, 'UTF-8'), -1, PREG_SPLIT_NO_EMPTY) ?: [];
        $out = '';
        foreach ($chars as $i => $ch) {
            $prev = $i > 0 ? $chars[$i - 1] : null;
            $capital = false;
            if (preg_match('/\p{L}/u', $ch)) {
                if ($prev === null) {
                    $capital = true;
                } elseif (preg_match('/[\p{L}\p{N}]/u', $prev)) {
                    $capital = false; // inside a word, or right after a digit (3b)
                } elseif (in_array($prev, ["'", '’'], true) && $i > 1 && preg_match('/\p{L}/u', $chars[$i - 2])) {
                    $capital = false; // an apostrophe between two letters stays inside the word: NYANG'HWALE
                } else {
                    $capital = true;
                }
            }
            $out .= $capital ? mb_strtoupper($ch, 'UTF-8') : $ch;
        }

        return $out;
    }

    /**
     * Read every file and report what is in them, WITHOUT touching the database.
     *
     * @return array{tree: array, stats: array<string, int>}
     */
    public function parse(): array
    {
        $files = glob($this->directory . DIRECTORY_SEPARATOR . '*.csv') ?: [];
        sort($files);
        if ($files === []) {
            throw new RuntimeException("there are no .csv files in {$this->directory}");
        }

        $tree = [];
        $stats = ['files' => 0, 'rows' => 0, 'skipped' => 0];
        // The same region/district/ward/street is repeated on many lines: clean each distinct text once. (Place names
        // are nearly all different, so they are not kept: it would only cost memory.)
        $memo = [];
        $clean = function (?string $raw) use (&$memo): ?string {
            $raw = (string) $raw;

            return $memo[$raw] ??= self::clean($raw);
        };
        foreach ($files as $path) {
            $handle = fopen($path, 'r');
            if ($handle === false) {
                throw new RuntimeException("cannot read {$path}");
            }
            $stats['files']++;

            // Columns: region, regioncode, district, districtcode, ward, wardcode, street, places (+ a header line).
            fgetcsv($handle, 0, ',', '"', '');
            while (($row = fgetcsv($handle, 0, ',', '"', '')) !== false) {
                if ($row === [null]) {
                    continue; // a blank line
                }
                $stats['rows']++;
                $row = array_pad($row, 8, null);
                $region = $clean($row[0]);
                $region = $region === null ? null : (self::REGIONS[mb_strtolower($region)] ?? $region);
                $district = $clean($row[2]);
                $district = $district === null ? null : (self::DISTRICTS[mb_strtolower($district)] ?? $district);
                $ward = $clean($row[4]);
                $street = $clean($row[6]);
                $place = self::clean($row[7]);

                // A ward needs its district and region; without them it cannot be placed.
                if ($region === null || $district === null || $ward === null) {
                    $stats['skipped']++;
                    continue;
                }

                $rk = mb_strtolower($region);
                $dk = mb_strtolower($district);
                $wk = mb_strtolower($ward);
                $tree[$rk]['name'] = $region;
                $tree[$rk]['districts'][$dk]['name'] = $district;
                $tree[$rk]['districts'][$dk]['wards'][$wk]['name'] = $ward;
                if ($street !== null) {
                    $sk = mb_strtolower($street);
                    $tree[$rk]['districts'][$dk]['wards'][$wk]['streets'][$sk]['name'] = $street;
                    if ($place !== null) {
                        $tree[$rk]['districts'][$dk]['wards'][$wk]['streets'][$sk]['places'][mb_strtolower($place)] = $place;
                    }
                }
            }
            fclose($handle);
        }

        $stats += ['regions' => 0, 'districts' => 0, 'wards' => 0, 'streets' => 0, 'places' => 0];
        foreach ($tree as $region) {
            $stats['regions']++;
            foreach ($region['districts'] as $district) {
                $stats['districts']++;
                foreach ($district['wards'] as $ward) {
                    $stats['wards']++;
                    foreach ($ward['streets'] ?? [] as $street) {
                        $stats['streets']++;
                        $stats['places'] += count($street['places'] ?? []);
                    }
                }
            }
        }

        return ['tree' => $tree, 'stats' => $stats];
    }

    /**
     * Add what is missing. Returns how many rows each table gained (all zeros on a second run).
     *
     * @return array{found: array<string, int>, added: array<string, int>}
     */
    public function import(): array
    {
        ['tree' => $tree, 'stats' => $found] = $this->parse();
        $added = ['states' => 0, 'lgas' => 0, 'wards' => 0, 'villages' => 0, 'places' => 0];

        DB::transaction(function () use ($tree, &$added) {
            $regions = [];
            foreach ($tree as $rk => $r) {
                $regions[$rk] = ['parent' => null, 'name' => $r['name']];
            }
            $regionIds = $this->load('states', null, $regions, $added['states']);

            $districts = [];
            foreach ($tree as $rk => $r) {
                foreach ($r['districts'] as $dk => $d) {
                    $districts["$rk\0$dk"] = ['parent' => $regionIds[$rk], 'name' => $d['name']];
                }
            }
            $districtIds = $this->load('lgas', 'state_id', $districts, $added['lgas']);

            $wards = [];
            foreach ($tree as $rk => $r) {
                foreach ($r['districts'] as $dk => $d) {
                    foreach ($d['wards'] as $wk => $w) {
                        $wards["$rk\0$dk\0$wk"] = ['parent' => $districtIds["$rk\0$dk"], 'name' => $w['name']];
                    }
                }
            }
            $wardIds = $this->load('wards', 'lga_id', $wards, $added['wards']);

            $villages = [];
            foreach ($tree as $rk => $r) {
                foreach ($r['districts'] as $dk => $d) {
                    foreach ($d['wards'] as $wk => $w) {
                        foreach ($w['streets'] ?? [] as $sk => $s) {
                            $villages["$rk\0$dk\0$wk\0$sk"] = ['parent' => $wardIds["$rk\0$dk\0$wk"], 'name' => $s['name']];
                        }
                    }
                }
            }
            $villageIds = $this->load('villages', 'ward_id', $villages, $added['villages']);
            unset($regions, $regionIds, $districts, $districtIds, $wards, $wardIds, $villages);   // the server's PHP has 128 MB

            // `places` has no unique key, so only what is not already there is added (on a first load there is
            // nothing to compare with). They go in as they are found, not all collected first.
            $existing = [];
            if (DB::table('places')->exists()) {
                foreach (DB::table('places')->select('village_id', 'name')->cursor() as $row) {
                    $existing[$row->village_id . '|' . mb_strtolower($row->name)] = true;
                }
            }
            $now = now()->toDateTimeString();
            $batch = [];
            $flush = function () use (&$batch, &$added) {
                if ($batch !== []) {
                    DB::table('places')->insert($batch);
                    $added['places'] += count($batch);
                    $batch = [];
                }
            };
            foreach ($tree as $rk => $r) {
                foreach ($r['districts'] as $dk => $d) {
                    foreach ($d['wards'] as $wk => $w) {
                        foreach ($w['streets'] ?? [] as $sk => $s) {
                            foreach ($s['places'] ?? [] as $pk => $name) {
                                $villageId = $villageIds["$rk\0$dk\0$wk\0$sk"];
                                if (!isset($existing[$villageId . '|' . $pk])) {
                                    $batch[] = ['village_id' => $villageId, 'name' => $name, 'created_at' => $now, 'updated_at' => $now];
                                    if (count($batch) >= self::CHUNK) {
                                        $flush();
                                    }
                                }
                            }
                        }
                    }
                }
            }
            $flush();
        });

        return ['found' => $found, 'added' => $added];
    }

    /**
     * Insert the rows that are not there yet and hand back the id of every one of them, keyed like $rows.
     * The unique key on each table (name + parent) is what makes a second run add nothing.
     *
     * @param  array<string, array{parent: int|null, name: string}>  $rows
     * @return array<string, int>
     */
    private function load(string $table, ?string $parentColumn, array $rows, int &$added): array
    {
        // What is there already, matched by name with case ignored: MariaDB's unique key does that by itself, SQLite's
        // does not, and this must behave the same on both. The unique key then only guards against a second import
        // running at the very same moment (insertOrIgnore).
        $have = $this->idsByName($table, $parentColumn);

        $now = now()->toDateTimeString();
        $payload = [];
        foreach ($rows as $row) {
            if (isset($have[($row['parent'] ?? 0) . '|' . mb_strtolower($row['name'])])) {
                continue;
            }
            $payload[] = ($parentColumn !== null ? [$parentColumn => $row['parent']] : ['country_code' => self::COUNTRY])
                + ['name' => $row['name'], 'created_at' => $now, 'updated_at' => $now];
        }
        foreach (array_chunk($payload, self::CHUNK) as $chunk) {
            $added += DB::table($table)->insertOrIgnore($chunk);
        }

        $have = $payload === [] ? $have : $this->idsByName($table, $parentColumn);
        $ids = [];
        foreach ($rows as $key => $row) {
            $id = $have[($row['parent'] ?? 0) . '|' . mb_strtolower($row['name'])] ?? null;
            if ($id === null) {
                // Never carry on with a hole in the tree: this rolls the whole import back.
                throw new RuntimeException("{$table}: \"{$row['name']}\" could not be found after it was inserted");
            }
            $ids[$key] = $id;
        }

        return $ids;
    }

    /**
     * Every row of the table as "parent id|name in lower case" => id. If the same name somehow exists twice
     * (SQLite treats ARUSHA and Arusha as different), the oldest row wins, so a re-run keeps using it.
     *
     * @return array<string, int>
     */
    private function idsByName(string $table, ?string $parentColumn): array
    {
        $query = DB::table($table)->select(array_filter(['id', $parentColumn, 'name']));
        if ($parentColumn === null) {
            $query->where('country_code', self::COUNTRY);
        }

        $byKey = [];
        foreach ($query->orderBy('id')->cursor() as $row) {
            $byKey[($parentColumn !== null ? $row->{$parentColumn} : 0) . '|' . mb_strtolower($row->name)] ??= (int) $row->id;
        }

        return $byKey;
    }
}
