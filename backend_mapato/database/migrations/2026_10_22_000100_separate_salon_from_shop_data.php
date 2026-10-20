<?php

use App\Support\Tenancy\TenantTables;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A business with both a shop and a salon must not see one's sales, clients, goods, cash or settings inside the
     * other. Every inventory table gets a `service` column: 'inventory' (what every existing row is, so nothing
     * changes for the shop) or 'salon'. The query scope (App\Support\Tenancy) then limits every statement to the
     * service the request works in, and stamps new rows with it.
     *
     * Keys that were unique per business (an SKU, a category name, a setting) become unique per business AND service:
     * the salon may have its own "Hair" category, its own settings.
     *
     * Every step checks first: MySQL has no transactional DDL, so a half-finished run must be safe to repeat.
     */
    public function up(): void
    {
        foreach (TenantTables::INVENTORY as $table) {
            if (!Schema::hasTable($table) || Schema::hasColumn($table, TenantTables::SERVICE_COLUMN)) {
                continue;
            }

            Schema::table($table, function (Blueprint $t) {
                $t->string(TenantTables::SERVICE_COLUMN, 20)->default('inventory')->index();
            });
        }

        foreach ($this->uniques() as $table => $column) {
            $this->swapUnique($table, [TenantTables::OWNER_COLUMN, $column], [TenantTables::OWNER_COLUMN, TenantTables::SERVICE_COLUMN, $column]);
        }

        TenantTables::forgetSplit();
    }

    public function down(): void
    {
        $salonRows = 0;
        foreach (TenantTables::INVENTORY as $table) {
            if (Schema::hasTable($table) && Schema::hasColumn($table, TenantTables::SERVICE_COLUMN)) {
                $salonRows += DB::table($table)->where(TenantTables::SERVICE_COLUMN, 'salon')->count();
            }
        }
        if ($salonRows > 0) {
            throw new RuntimeException("{$salonRows} salon rows exist: moving them back would mix them into the shop's books. Remove or export them first.");
        }

        foreach ($this->uniques() as $table => $column) {
            $this->swapUnique($table, [TenantTables::OWNER_COLUMN, TenantTables::SERVICE_COLUMN, $column], [TenantTables::OWNER_COLUMN, $column]);
        }

        foreach (TenantTables::INVENTORY as $table) {
            if (!Schema::hasTable($table) || !Schema::hasColumn($table, TenantTables::SERVICE_COLUMN)) {
                continue;
            }

            Schema::table($table, function (Blueprint $t) {
                $t->dropIndex([TenantTables::SERVICE_COLUMN]);
                $t->dropColumn(TenantTables::SERVICE_COLUMN);
            });
        }

        TenantTables::forgetSplit();
    }

    /**
     * Replace one unique key by another, whichever of them exists now. The key is found by its COLUMNS, not its
     * name: a table that was once renamed (inventory_settings) keeps the index name it was made with.
     */
    private function swapUnique(string $table, array $from, array $to): void
    {
        if (!Schema::hasTable($table)) {
            return;
        }

        $existing = fn (array $columns) => collect(Schema::getIndexes($table))->first(
            fn (array $i) => !empty($i['unique']) && empty($i['primary']) && $i['columns'] === $columns
        );

        if ($old = $existing($from)) {
            Schema::table($table, fn (Blueprint $t) => $t->dropUnique($old['name']));
        }
        if (!$existing($to)) {
            Schema::table($table, fn (Blueprint $t) => $t->unique($to));
        }
    }

    /** @return array<string, string> table => the column that is unique within a business (and now a service) */
    private function uniques(): array
    {
        return [
            'inventory_products' => 'sku',
            'inventory_categories' => 'name',
            'inventory_brands' => 'name',
            'inventory_crate_types' => 'name',
            'inventory_stock_counts' => 'reference',
            'inventory_write_offs' => 'reference',
            'inventory_purchase_orders' => 'number',
            'inventory_goods_receipts' => 'reference',
            'inventory_cash_sessions' => 'reference',
            'inventory_parked_sales' => 'reference',
            'inventory_sale_returns' => 'reference',
            'inventory_dispatches' => 'reference',
            'inventory_settings' => 'key',
        ];
    }
};
