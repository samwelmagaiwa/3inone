<?php

namespace Tests\Unit;

use App\Database\MySqlConnection57;
use App\Database\TenantSQLiteConnection;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Database\Connection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use LogicException;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * The per-business query scope, checked at the level of the SQL it generates --
 * for both the database the tests run on (SQLite) and the one production runs on
 * (MySQL), so a grammar difference can never hide a leak. No tables are needed:
 * statements are compiled, not executed.
 */
class TenantQueryScopeTest extends TestCase
{
    private string $ownerId;

    private User $business;

    private User $superAdmin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->ownerId = (string) Str::uuid();
        $this->business = (new User())->forceFill(['id' => $this->ownerId, 'role' => 'admin']);
        $this->superAdmin = (new User())->forceFill(['id' => (string) Str::uuid(), 'role' => 'super_admin']);
    }

    /** @return array<string, array{0: Connection, 1: string}> connection and its identifier quote */
    public static function connections(): array
    {
        return [
            // Built explicitly, like the MySQL one, so this still means SQLite when the whole suite is run on MySQL.
            'sqlite' => [fn () => new TenantSQLiteConnection(fn () => null, ':memory:'), '"'],
            'mysql' => [fn () => new MySqlConnection57(fn () => null, 'depot'), '`'],
        ];
    }

    /** Compile as $user and return the SQL. */
    private function sql(callable $connection, ?User $user, callable $query): string
    {
        $build = fn () => $query($connection());

        return $user === null ? $build() : TenantContext::runAs($user, $build);
    }

    #[DataProvider('connections')]
    public function test_a_business_only_reaches_its_own_rows(callable $connection, string $q): void
    {
        $sql = $this->sql($connection, $this->business, fn ($c) => $c->table('inventory_products')->where('id', 1)->toSql());

        $this->assertSame(
            "select * from {$q}inventory_products{$q} where ({$q}id{$q} = ?) and {$q}inventory_products{$q}.{$q}owner_id{$q} = '{$this->ownerId}'",
            $sql
        );
    }

    #[DataProvider('connections')]
    public function test_nothing_is_scoped_without_a_signed_in_user_or_for_a_super_admin(callable $connection, string $q): void
    {
        $plain = "select * from {$q}inventory_products{$q} where {$q}id{$q} = ?";

        $this->assertSame($plain, $this->sql($connection, null, fn ($c) => $c->table('inventory_products')->where('id', 1)->toSql()));
        $this->assertSame($plain, $this->sql($connection, $this->superAdmin, fn ($c) => $c->table('inventory_products')->where('id', 1)->toSql()));
    }

    #[DataProvider('connections')]
    public function test_an_or_condition_cannot_escape_the_scope(callable $connection, string $q): void
    {
        $sql = $this->sql($connection, $this->business, fn ($c) => $c->table('inventory_sales')
            ->where('status', 'open')->orWhere('payment_status', 'debt')->toSql());

        $this->assertSame(
            "select * from {$q}inventory_sales{$q} where ({$q}status{$q} = ? or {$q}payment_status{$q} = ?) "
            . "and {$q}inventory_sales{$q}.{$q}owner_id{$q} = '{$this->ownerId}'",
            $sql,
            'the OR must stay inside the parentheses'
        );
    }

    #[DataProvider('connections')]
    public function test_an_aliased_table_is_scoped_through_its_alias(callable $connection, string $q): void
    {
        $sql = $this->sql($connection, $this->business, fn ($c) => $c->table('inventory_sales as s')->where('s.id', 4)->toSql());

        $this->assertStringContainsString("{$q}s{$q}.{$q}owner_id{$q} = '{$this->ownerId}'", $sql);
        $this->assertStringNotContainsString("{$q}inventory_sales{$q}.{$q}owner_id", $sql);
    }

    #[DataProvider('connections')]
    public function test_joined_tables_are_scoped_inside_the_join_so_a_left_join_stays_a_left_join(callable $connection, string $q): void
    {
        $sql = $this->sql($connection, $this->business, fn ($c) => $c->table('inventory_sales as s')
            ->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->leftJoin('users as u', 'u.id', '=', 's.created_by') // not a registered table
            ->toSql());

        $this->assertStringContainsString(
            "left join {$q}inventory_customers{$q} as {$q}c{$q} on ({$q}c{$q}.{$q}id{$q} = {$q}s{$q}.{$q}customer_id{$q}) "
            . "and {$q}c{$q}.{$q}owner_id{$q} = '{$this->ownerId}'",
            $sql
        );
        $this->assertStringContainsString("{$q}s{$q}.{$q}owner_id{$q} = '{$this->ownerId}'", $sql, 'the main table is scoped too');
        $this->assertStringNotContainsString("{$q}u{$q}.{$q}owner_id", $sql, 'tables that are not per-business are left alone');
    }

    #[DataProvider('connections')]
    public function test_subqueries_and_validation_style_lookups_are_scoped(callable $connection, string $q): void
    {
        $sql = $this->sql($connection, $this->business, fn ($c) => $c->table('inventory_sales')
            ->whereIn('customer_id', fn ($sub) => $sub->select('id')->from('inventory_customers')->where('blocked', 1))
            ->toSql());

        // Both the outer statement and the sub-select carry the scope.
        $this->assertSame(2, substr_count($sql, "{$q}owner_id{$q} = '{$this->ownerId}'"));
    }

    #[DataProvider('connections')]
    public function test_updates_and_deletes_are_scoped_too(callable $connection, string $q): void
    {
        $update = $this->sql($connection, $this->business, function ($c) {
            $query = $c->table('inventory_products')->where('id', 3);

            return $query->getGrammar()->compileUpdate($query, ['quantity' => 5]);
        });
        $delete = $this->sql($connection, $this->business, function ($c) {
            $query = $c->table('inventory_products')->where('id', 3);

            return $query->getGrammar()->compileDelete($query);
        });

        foreach ([$update, $delete] as $sql) {
            $this->assertStringContainsString("{$q}owner_id{$q} = '{$this->ownerId}'", $sql);
            $this->assertStringContainsString("({$q}id{$q} = ?)", $sql);
        }
    }

    #[DataProvider('connections')]
    public function test_other_tables_are_never_touched(callable $connection, string $q): void
    {
        $sql = $this->sql($connection, $this->business, fn ($c) => $c->table('users')->where('id', 1)->toSql());

        $this->assertSame("select * from {$q}users{$q} where {$q}id{$q} = ?", $sql);
    }

    public function test_the_context_is_restored_after_runAs_even_when_it_throws(): void
    {
        $inside = null;
        try {
            TenantContext::runAs($this->business, function () use (&$inside) {
                $inside = TenantContext::readOwner();
                throw new \RuntimeException('boom');
            });
        } catch (\RuntimeException) {
        }

        $this->assertSame($this->ownerId, $inside);
        $this->assertNull(TenantContext::readOwner(), 'back to "nobody signed in"');
    }

    public function test_a_malformed_owner_id_stops_the_query_instead_of_being_spliced_into_sql(): void
    {
        $this->expectException(LogicException::class);

        $evil = (new User())->forceFill(['id' => "x' or '1'='1", 'role' => 'admin']);
        TenantContext::runAs($evil, fn () => DB::connection()->table('inventory_products')->toSql());
    }
}
