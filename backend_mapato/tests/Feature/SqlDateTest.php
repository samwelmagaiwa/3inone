<?php

namespace Tests\Feature;

use App\Support\SqlDate;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * SqlDate::yearWeek() must give the same answer on EVERY SQLite, not only the newest one.
 *
 * It once used strftime('%U'), which exists from SQLite 3.46: it passed on a developer machine and failed on
 * the CI runner, whose SQLite is older and answers NULL for it. These tests do not depend on the version.
 */
class SqlDateTest extends TestCase
{
    private function skipUnlessSqlite(string $why): void
    {
        if (DB::connection()->getDriverName() !== 'sqlite') {
            $this->markTestSkipped($why);
        }
    }

    /** @return array<string, array{string, int}> */
    public static function weeks(): array
    {
        // Weeks start on Sunday and week 1 is the one holding the year's first Sunday; the days before
        // it are week 0 (what strftime's %U says).
        return [
            'a Thursday on 1 January is still week 0'  => ['2026-01-01', 202600],
            'the Saturday before the first Sunday'     => ['2026-01-03', 202600],
            'the first Sunday starts week 1'           => ['2026-01-04', 202601],
            'a Sunday in October starts a week'        => ['2026-10-04', 202640],
            'the Monday after it is the same week'     => ['2026-10-05', 202640],
            'the Saturday ends that week'              => ['2026-10-10', 202640],
            'the next Sunday starts the next week'     => ['2026-10-11', 202641],
            'the last day of the year'                 => ['2026-12-31', 202652],
            'a leap day'                               => ['2028-02-29', 202809],
            'a timestamp, not just a date'             => ['2026-10-05 13:45:00', 202640],
        ];
    }

    #[DataProvider('weeks')]
    public function test_year_week_is_right_for_known_days(string $day, int $expected): void
    {
        $this->skipUnlessSqlite('these are the numbers of the SQLite formula; MySQL/MariaDB use YEARWEEK(), which numbers early January differently');
        $row = DB::selectOne('select ' . SqlDate::yearWeek('d') . " as yw from (select '{$day}' as d) t");

        $this->assertSame($expected, (int) $row->yw, "year-week of {$day}");
    }

    public function test_year_week_agrees_with_sqlites_own_week_where_sqlite_has_one(): void
    {
        $this->skipUnlessSqlite('strftime() exists only in SQLite');
        $native = DB::selectOne("select strftime('%U', '2026-10-05') as w")->w;
        if ($native === null) {
            $this->markTestSkipped('This SQLite is older than 3.46 and has no %U: the known-days test covers it.');
        }

        // Six years of days: our arithmetic and SQLite's %U must never disagree.
        $mismatches = DB::select(
            "with recursive d(x) as (select '2024-01-01' union all select date(x, '+1 day') from d where x < '2029-12-31') "
            . 'select x from d where ' . SqlDate::yearWeek('x') . " != cast(strftime('%Y%U', x) as integer)"
        );

        $this->assertSame([], array_map(fn ($r) => $r->x, $mismatches), 'days where the two disagree');
    }

    public function test_the_year_week_sql_uses_only_formats_every_sqlite_has(): void
    {
        $this->assertSame([], $this->newerOnlyFormatsIn(SqlDate::yearWeek('d')));
        $this->assertSame([], $this->newerOnlyFormatsIn(SqlDate::year('d') . SqlDate::month('d') . SqlDate::day('d')));
    }

    public function test_no_code_uses_a_strftime_format_that_needs_a_new_sqlite(): void
    {
        $offenders = [];
        $files = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator(app_path(), \FilesystemIterator::SKIP_DOTS));
        foreach ($files as $file) {
            if ($file->getExtension() !== 'php') {
                continue;
            }
            if ($this->newerOnlyFormatsIn((string) file_get_contents($file->getPathname())) !== []) {
                $offenders[] = str_replace(base_path() . DIRECTORY_SEPARATOR, '', $file->getPathname());
            }
        }

        $this->assertSame([], $offenders, 'strftime with %U, %V, %G, %g or %u only works on SQLite 3.46 and newer');
    }

    /** @return list<string> the strftime specifiers in $text that SQLite only learned in 3.46 */
    private function newerOnlyFormatsIn(string $text): array
    {
        preg_match_all("/strftime\\(\\s*'([^']*)'/", $text, $calls);
        $found = [];
        foreach ($calls[1] as $format) {
            if (preg_match_all('/%[UVGgu]/', $format, $m)) {
                array_push($found, ...$m[0]);
            }
        }

        return $found;
    }
}
