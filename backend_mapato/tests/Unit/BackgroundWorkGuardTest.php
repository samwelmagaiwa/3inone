<?php

namespace Tests\Unit;

use PHPUnit\Framework\TestCase;

/**
 * Background work has nobody signed in, and with nobody signed in NOTHING IS SCOPED: an
 * inventory query sees every business, and a row it inserts gets no owner (so no business
 * ever sees it). A job or command that touches inventory tables must therefore say which
 * business it works for -- TenantContext::runAs() -- or, for platform-wide tooling,
 * TenantContext::withoutScope() on purpose.
 *
 * This fails when new background code touches inventory tables without doing either, so
 * the mistake is caught here instead of in someone's accounts. (Rental and Transport batch
 * jobs, such as billing, are platform-wide by design and not covered.)
 */
class BackgroundWorkGuardTest extends TestCase
{
    /** Background code that is allowed to touch inventory tables without TenantContext, and why. */
    private const EXEMPT = [
        'app/Console/Commands/PurgeTestData.php' =>
            'run by an operator on the server, interactive; deletes platform-wide on purpose (review its LIKE patterns before use)',
    ];

    public function test_background_code_that_touches_inventory_says_which_business_it_acts_for(): void
    {
        $root = dirname(__DIR__, 2);
        $offenders = [];

        foreach (['app/Jobs', 'app/Console', 'app/Listeners', 'app/Observers', 'routes/console.php'] as $where) {
            $path = "{$root}/{$where}";
            $files = is_file($path) ? [$path] : (is_dir($path) ? $this->phpFiles($path) : []);

            foreach ($files as $file) {
                $relative = str_replace('\\', '/', substr($file, strlen($root) + 1));
                $code = (string) file_get_contents($file);

                $touchesInventory = (bool) preg_match("/['\"]inventory_[a-z_]+['\"]/", $code);
                $namesBusiness = str_contains($code, 'TenantContext') || str_contains($code, 'InventoryOwnership');

                if ($touchesInventory && !$namesBusiness && !isset(self::EXEMPT[$relative])) {
                    $offenders[] = $relative;
                }
            }
        }

        $this->assertSame(
            [],
            $offenders,
            'These background files touch inventory tables without TenantContext::runAs()/withoutScope(): '
            . implode(', ', $offenders)
        );
    }

    public function test_every_exemption_is_still_needed(): void
    {
        $root = dirname(__DIR__, 2);

        foreach (array_keys(self::EXEMPT) as $relative) {
            $this->assertFileExists("{$root}/{$relative}", "{$relative} no longer exists: remove it from the exemptions");
            $this->assertMatchesRegularExpression(
                "/['\"]inventory_[a-z_]+['\"]/",
                (string) file_get_contents("{$root}/{$relative}"),
                "{$relative} no longer touches inventory: remove it from the exemptions"
            );
        }
    }

    /** @return array<int, string> */
    private function phpFiles(string $directory): array
    {
        $found = [];
        foreach (new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($directory, \FilesystemIterator::SKIP_DOTS)) as $file) {
            if ($file->isFile() && $file->getExtension() === 'php') {
                $found[] = $file->getPathname();
            }
        }

        return $found;
    }
}
