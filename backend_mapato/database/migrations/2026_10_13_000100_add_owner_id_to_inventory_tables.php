<?php

use App\Support\Tenancy\TenantTables;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Inventory was one shared depot. To host several businesses every inventory
     * table gets an owner_id -- the account head's user id -- and the tenant query
     * grammar (App\Support\Tenancy) limits every statement to the signed-in
     * business's rows.
     *
     * Step 1 of 3 (schema only, additive): the column is nullable and indexed, so
     * rows written before the next steps still load, and nothing is dropped. The
     * settings table is rebuilt in step 2 (its primary key is the setting name),
     * and existing rows are given their owner in step 3.
     *
     * Unique constraints that used to be global become per business, because two
     * businesses must each be able to have a "Soda" category, an SKU "MAJ-WTR-500",
     * or a stock count made in the same second. A business can still not repeat
     * its own.
     */
    public function up(): void
    {
        foreach (TenantTables::INVENTORY as $table) {
            if ($table === 'inventory_settings') {
                continue; // rebuilt by the next migration
            }

            Schema::table($table, function (Blueprint $t) {
                $t->uuid(TenantTables::OWNER_COLUMN)->nullable()->index();
            });
        }

        foreach ($this->perBusinessUniques() as $table => $column) {
            Schema::table($table, function (Blueprint $t) use ($column) {
                $t->dropUnique([$column]);
                $t->unique([TenantTables::OWNER_COLUMN, $column]);
            });
        }
    }

    public function down(): void
    {
        foreach ($this->perBusinessUniques() as $table => $column) {
            Schema::table($table, function (Blueprint $t) use ($column) {
                $t->dropUnique([TenantTables::OWNER_COLUMN, $column]);
                $t->unique([$column]);
            });
        }

        foreach (TenantTables::INVENTORY as $table) {
            if ($table === 'inventory_settings') {
                continue;
            }

            Schema::table($table, function (Blueprint $t) {
                $t->dropIndex([TenantTables::OWNER_COLUMN]);
                $t->dropColumn(TenantTables::OWNER_COLUMN);
            });
        }
    }

    /**
     * Columns that were globally unique and must be unique per business instead.
     * Numbers derived from a row id (sales.number, barcode labels) stay global:
     * the id already makes them unique across businesses.
     *
     * @return array<string, string> table => column
     */
    private function perBusinessUniques(): array
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
        ];
    }
};
