<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\ClientTime;
use App\Support\GroupColumns;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * The production database is MariaDB; the tests (and CI) run on SQLite, which forgives what MariaDB refuses. Two
 * things went wrong there and are pinned down here:
 *
 *  - a hand-written GROUP BY list (`select c.*` ... `group by c.id, c.name, ...`) misses every column added later,
 *    and MariaDB answers error 1055 -> categories, brands, customers and suppliers returned 500;
 *  - an ISO-8601 time with a zone suffix ("...T13:49:20+00:00") written as it came into a DATETIME column is
 *    error 1292 on MariaDB -> a sale with a payment could not be saved.
 *
 * Running the whole suite against a MariaDB container (see docs/DEPLOY.md) is the real check; these tests keep the
 * same mistakes from coming back on SQLite too.
 */
class MariaDbCompatibilityTest extends TestCase
{
    use RefreshDatabase;

    // ------------------------------------------------------------------ GROUP BY lists

    public function test_group_columns_are_every_column_of_the_table_so_a_new_column_cannot_break_a_query(): void
    {
        $columns = GroupColumns::of('inventory_categories', 'c');

        $this->assertSame(count(Schema::getColumnListing('inventory_categories')), count($columns));
        $this->assertContains('c.id', $columns);
        $this->assertContains('c.owner_id', $columns, 'the column that broke the hand-written lists');
        foreach ($columns as $column) {
            $this->assertStringStartsWith('c.', $column);
        }
    }

    public function test_no_query_selects_every_column_and_then_groups_by_a_hand_written_list(): void
    {
        // One query builder statement that selects 'x.*' and then calls ->groupBy('literal', ...) before it is run.
        // (`->get()->groupBy('id')` is the collection's method, in PHP: it is not SQL and is not what this is about.)
        $pattern = <<<'REGEX'
/->select\((?:(?!->get\(|->first\(|->paginate\(|->pluck\(|->cursor\(|;).)*?'[a-z_]+\.\*'(?:(?!->get\(|->first\(|->paginate\(|->pluck\(|->cursor\(|;).)*?->groupBy\(\s*'/s
REGEX;

        // the check itself: it catches the old code, and leaves the collection method alone
        $this->assertSame(1, preg_match($pattern, "DB::table('inventory_categories as c')->leftJoin('inventory_products as p', 'p.category_id', '=', 'c.id')->select('c.*', DB::raw('COUNT(p.id) as products_count'))->groupBy('c.id', 'c.name', 'c.created_at');"));
        $this->assertSame(0, preg_match($pattern, "DB::table('inventory_sale_items as si')->select('si.*', 'p.name as product_name')->get()->groupBy('sale_id');"));
        $this->assertSame(0, preg_match($pattern, "DB::table('inventory_categories as c')->select('c.*', DB::raw('COUNT(p.id) as n'))->groupBy(GroupColumns::of('inventory_categories', 'c'));"));

        $offenders = [];
        $files = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator(app_path('Http/Controllers'), \FilesystemIterator::SKIP_DOTS));
        foreach ($files as $file) {
            if ($file->getExtension() !== 'php') {
                continue;
            }
            if (preg_match($pattern, (string) file_get_contents($file->getPathname())) === 1) {
                $offenders[] = str_replace(base_path() . DIRECTORY_SEPARATOR, '', $file->getPathname());
            }
        }

        $this->assertSame([], $offenders, 'use GroupColumns::of() instead of listing the columns by hand (see App\Support\GroupColumns)');
    }

    // ------------------------------------------------------------------ client times

    public function test_a_time_with_a_zone_suffix_is_converted_to_the_application_zone(): void
    {
        $parsed = ClientTime::parse('2026-10-13T13:49:20+00:00');

        $this->assertInstanceOf(Carbon::class, $parsed);
        $this->assertSame(config('app.timezone'), $parsed->getTimezone()->getName());
        $this->assertSame('2026-10-13 13:49:20', $parsed->copy()->utc()->format('Y-m-d H:i:s'), 'the same instant');
    }

    public function test_zulu_time_is_the_same_instant(): void
    {
        $this->assertSame('2026-10-13 13:49:20', ClientTime::parse('2026-10-13T13:49:20Z')->copy()->utc()->format('Y-m-d H:i:s'));
    }

    public function test_a_local_time_with_microseconds_is_read_in_the_application_zone(): void
    {
        // what the app sends: DateTime.now().toIso8601String() has no zone and microseconds
        $parsed = ClientTime::parse('2026-10-13T16:49:20.123456');

        $this->assertSame('2026-10-13 16:49:20', $parsed->format('Y-m-d H:i:s'));
        $this->assertSame(config('app.timezone'), $parsed->getTimezone()->getName());
    }

    public function test_no_time_means_now(): void
    {
        foreach ([null, ''] as $nothing) {
            $this->assertEqualsWithDelta(now()->timestamp, ClientTime::parse($nothing)->timestamp, 5);
        }
    }

    // ------------------------------------------------------------------ a sale with a payment, end to end

    public function test_a_sale_with_a_zone_suffixed_payment_time_is_saved_in_the_databases_own_format(): void
    {
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true]), 'inventory');
        $token = $owner->createToken('test')->plainTextToken;
        $api = fn (string $method, string $uri, array $body = []) => $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);

        $productId = $api('POST', '/api/inventory/products', [
            'name' => 'Soda', 'cost_price' => 500, 'selling_price' => 1000, 'quantity' => 40, 'min_stock' => 5, 'status' => 'active',
        ])->assertCreated()->json('data.id');

        $this->app['auth']->forgetGuards();
        $saleId = $api('POST', '/api/inventory/sales', [
            'payment_status' => 'paid', 'subtotal' => 2000, 'discount' => 0, 'tax' => 0, 'total' => 2000, 'paid_total' => 2000,
            'items' => [['product_id' => $productId, 'quantity' => 2, 'unit_price' => 1000, 'unit_cost_snapshot' => 500]],
            'payments' => [['amount' => 2000, 'method' => 'cash', 'paid_at' => '2026-10-13T13:49:20+00:00']],
        ])->assertCreated()->json('data.id');

        $stored = TenantContext::runAs($owner, fn () => (string) DB::table('inventory_sale_payments')->where('sale_id', $saleId)->value('paid_at'));

        $this->assertMatchesRegularExpression('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $stored, 'stored as a plain date-time: no "T", no zone');
        $this->assertSame('2026-10-13 13:49:20', Carbon::parse($stored, config('app.timezone'))->utc()->format('Y-m-d H:i:s'), 'and it is still the same instant');
    }
}
