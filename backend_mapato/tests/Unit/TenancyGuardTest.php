<?php

namespace Tests\Unit;

use App\Models\Concerns\ScopedToAccount;
use App\Support\Tenancy\TenantTables;
use Illuminate\Database\Eloquent\Model;
use Tests\TestCase;

/**
 * The tenancy contract has one rule for every service: data that belongs to a business
 * is fail-closed, so a forgotten filter cannot leak it.
 *
 *   Transport, Rental   Eloquent models use ScopedToAccount (AccountScope);
 *   Inventory           raw tables are listed in TenantTables (tenant query grammar).
 *
 * These tests fail the day someone adds a model or table and forgets to take a side,
 * which is exactly when a cross-business leak would otherwise be introduced.
 */
class TenancyGuardTest extends TestCase
{
    /**
     * Models that are deliberately NOT per-business, and why. Adding to this list is a
     * decision to make in review, not a way to silence the test.
     */
    private const EXEMPT = [
        'User' => 'identity: every service looks users up (login, staff); access is limited by User::scopeInAccountOf and the account helpers',
        'UserService' => 'the services a user was given; read through the user, written only by a super admin',
        'BusinessRegistration' => 'registrations are read and written only by super_admin routes',
        'LoginActivity' => "a user's own sign-in history, only ever read for the signed-in user",
        'Rental\\Vendor' => 'shared marketplace of tradespeople by design; each business keeps its own roster (landlord_vendor)',
        'State' => 'public reference data (locations)',
        'Lga' => 'public reference data (locations)',
        'Ward' => 'public reference data (locations)',
        'Village' => 'public reference data (locations)',
        'Place' => 'public reference data (locations)',
        'PlanPrice' => "the platform's price list: public reference data, written only by super_admin routes",
    ];

    /** @return array<string, class-string<Model>> short name => class */
    private function models(): array
    {
        $root = app_path('Models');
        $found = [];

        $iterator = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($root, \FilesystemIterator::SKIP_DOTS));
        foreach ($iterator as $file) {
            if ($file->getExtension() !== 'php') {
                continue;
            }

            $relative = str_replace(['/', '.php'], ['\\', ''], substr(str_replace('\\', '/', $file->getPathname()), strlen(str_replace('\\', '/', $root)) + 1));
            $class = 'App\\Models\\' . $relative;

            if (class_exists($class) && is_subclass_of($class, Model::class) && !(new \ReflectionClass($class))->isAbstract()) {
                $found[$relative] = $class;
            }
        }

        ksort($found);

        return $found;
    }

    public function test_every_model_is_account_scoped_or_deliberately_exempt(): void
    {
        $unscoped = [];

        foreach ($this->models() as $short => $class) {
            $scoped = in_array(ScopedToAccount::class, class_uses_recursive($class), true);

            if (!$scoped && !array_key_exists($short, self::EXEMPT)) {
                $unscoped[] = $short;
            }
        }

        $this->assertSame(
            [],
            $unscoped,
            "These models hold business data but have no account scope, so a controller that forgets a filter leaks across businesses.\n"
            . "Add `use ScopedToAccount` (or ScopedThroughDriver) and a constrainToAccount() rule, or list the model in TenancyGuardTest::EXEMPT with a reason."
        );
    }

    public function test_the_exemption_list_has_no_stale_entries(): void
    {
        $models = $this->models();

        foreach (self::EXEMPT as $short => $reason) {
            $this->assertArrayHasKey($short, $models, "EXEMPT lists {$short}, which does not exist any more.");
            $this->assertNotContains(
                ScopedToAccount::class,
                class_uses_recursive($models[$short]),
                "{$short} is scoped now: remove it from EXEMPT."
            );
        }
    }

    public function test_the_inventory_registry_has_no_duplicates_and_follows_the_naming_rule(): void
    {
        $this->assertSame(TenantTables::INVENTORY, array_values(array_unique(TenantTables::INVENTORY)));
        $this->assertSame(TenantTables::INVENTORY, collect(TenantTables::INVENTORY)->sort()->values()->all(), 'keep the list sorted so additions are easy to review');

        foreach (TenantTables::INVENTORY as $table) {
            $this->assertStringStartsWith('inventory_', $table);
        }
    }
}
