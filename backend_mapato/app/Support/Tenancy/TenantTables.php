<?php

namespace App\Support\Tenancy;

/**
 * The raw-SQL tables that belong to one business each.
 *
 * Inventory is written with the query builder (DB::table('inventory_...')), not
 * Eloquent models, so it cannot use model scopes. Instead every table listed
 * here carries an `owner_id` (the id of the business's account head) and the
 * query grammar adds `owner_id = <the signed-in business>` to every statement
 * that touches one of them -- selects, updates, deletes, joins, subqueries and
 * the `exists:` / `unique:` validation rules alike. A controller that forgets to
 * filter is therefore still safe, exactly like the Eloquent AccountScope does for
 * Transport and Rental.
 *
 * ADD EVERY NEW inventory_* TABLE HERE. A test fails if one is missing.
 */
final class TenantTables
{
    /** @var array<int, string> */
    public const INVENTORY = [
        'inventory_alerts',
        'inventory_appointments',
        'inventory_attendance',
        'inventory_audit_log',
        'inventory_barcode_labels',
        'inventory_batches',
        'inventory_birthday_wishes',
        'inventory_brands',
        'inventory_campaigns',
        'inventory_cash_expenses',
        'inventory_cash_sessions',
        'inventory_categories',
        'inventory_client_packages',
        'inventory_client_photos',
        'inventory_crate_movements',
        'inventory_crate_types',
        'inventory_customers',
        'inventory_dispatch_lines',
        'inventory_dispatches',
        'inventory_expenses',
        'inventory_goods_receipt_lines',
        'inventory_goods_receipts',
        'inventory_loyalty_ledger',
        'inventory_notifications',
        'inventory_parked_sales',
        'inventory_payment_allocations',
        'inventory_price_changes',
        'inventory_product_prices',
        'inventory_product_units',
        'inventory_products',
        'inventory_purchase_order_lines',
        'inventory_purchase_orders',
        'inventory_rebook_reminders',
        'inventory_reminders',
        'inventory_sale_items',
        'inventory_sale_payments',
        'inventory_sale_return_lines',
        'inventory_sale_returns',
        'inventory_sales',
        'inventory_salon_shifts',
        'inventory_settings',
        'inventory_staff_days_off',
        'inventory_staff_payouts',
        'inventory_staff_profiles',
        'inventory_stock_count_lines',
        'inventory_stock_counts',
        'inventory_stock_movements',
        'inventory_supplier_invoices',
        'inventory_supplier_payments',
        'inventory_suppliers',
        'inventory_vouchers',
        'inventory_write_offs',
    ];

    /**
     * inventory_* tables that deliberately have no owner because nothing reads or
     * writes them: an unused sequence table, and the settings table as it was before
     * it became per-business (kept as a rollback backup; drop it by hand later).
     */
    public const UNSCOPED_INVENTORY = [
        'inventory_sku_sequences',
        'inventory_settings_legacy',
    ];

    /** The column that holds the owning business (the account head's user id). */
    public const OWNER_COLUMN = 'owner_id';

    /**
     * The column that says which SERVICE a row belongs to: 'inventory' (the shop or depot) or 'salon'. A business
     * that has both runs two separate sets of books on the same tables: the salon's sales, clients, goods,
     * settings and cash are never mixed with the shop's.
     */
    public const SERVICE_COLUMN = 'service';

    /** The services the inventory tables are split by. */
    public const SERVICES = ['inventory', 'salon'];

    private static ?bool $splitByService = null;

    private static int $splitCheckedAt = 0;

    /**
     * Do the tables have the service column yet? Asked again at most every 30 seconds, so the moments between a new
     * release starting and its migration finishing do not break every inventory query (the code is ready before the
     * column is), and a running server notices the column without being restarted.
     */
    public static function splitByService(): bool
    {
        $now = time();
        if (self::$splitByService === null || $now - self::$splitCheckedAt >= 30) {
            try {
                self::$splitByService = \Illuminate\Support\Facades\Schema::hasColumn('inventory_products', self::SERVICE_COLUMN);
            } catch (\Throwable) {
                self::$splitByService = false;
            }
            self::$splitCheckedAt = $now;
        }

        return self::$splitByService;
    }

    /** Forget what was learnt about the column (a test that has just migrated). */
    public static function forgetSplit(): void
    {
        self::$splitByService = null;
    }

    /** Fix the answer for a test that compiles SQL without a database (so it reads the same on every engine). */
    public static function pretendSplit(bool $split): void
    {
        self::$splitByService = $split;
        self::$splitCheckedAt = PHP_INT_MAX;
    }

    /** @var array<string, true>|null */
    private static ?array $lookup = null;

    /** @return array<int, string> */
    public static function all(): array
    {
        return self::INVENTORY;
    }

    public static function has(string $table): bool
    {
        self::$lookup ??= array_fill_keys(self::INVENTORY, true);

        return isset(self::$lookup[$table]);
    }

    /**
     * The registered table and the name its columns are qualified with, from a
     * query's `from` / join table ("inventory_sales", "inventory_sales as s"), or
     * null for anything else (other tables, raw expressions, sub-queries).
     *
     * @return array{0: string, 1: string}|null [table, alias]
     */
    public static function resolve(mixed $from): ?array
    {
        if (!is_string($from)) {
            return null;
        }

        if (preg_match('/^([A-Za-z0-9_]+)(?:\s+as\s+([A-Za-z0-9_]+))?$/i', trim($from), $m) !== 1) {
            return null;
        }

        $table = $m[1];
        if (!self::has($table)) {
            return null;
        }

        return [$table, $m[2] ?? $table];
    }
}
