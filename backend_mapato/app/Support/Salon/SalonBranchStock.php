<?php

namespace App\Support\Salon;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Goods stock by branch. The product's quantity is the salon's whole stock; each branch holds a share of it, and what is
 * not allocated to a branch is in the main store. A sale in a branch takes from that branch first (the rest comes from the
 * main store: a sale is never stopped for this), and a cancelled sale puts the goods back on that branch's shelf.
 */
final class SalonBranchStock
{
    public static function active(): bool
    {
        return Schema::hasTable('inventory_branch_stock');
    }

    public static function at(int $productId, int $branchId): int
    {
        return (int) DB::table('inventory_branch_stock')->where('product_id', $productId)->where('branch_id', $branchId)->value('quantity');
    }

    public static function allocated(int $productId): int
    {
        return (int) DB::table('inventory_branch_stock')->where('product_id', $productId)->sum('quantity');
    }

    /** What is in the main store: the whole stock less what branches hold (never below nothing). */
    public static function unallocated(int $productId, int $whole): int
    {
        return max(0, $whole - self::allocated($productId));
    }

    public static function add(int $productId, int $branchId, int $qty): void
    {
        if ($qty < 1) {
            return;
        }
        $row = DB::table('inventory_branch_stock')->where('product_id', $productId)->where('branch_id', $branchId)->first();
        if ($row === null) {
            DB::table('inventory_branch_stock')->insert(['product_id' => $productId, 'branch_id' => $branchId, 'quantity' => $qty, 'created_at' => now(), 'updated_at' => now()]);

            return;
        }
        DB::table('inventory_branch_stock')->where('id', $row->id)->update(['quantity' => (int) $row->quantity + $qty, 'updated_at' => now()]);
    }

    /** Take up to `$qty` from the branch's own share (what it does not have comes from the main store, not from here). */
    public static function take(int $productId, int $branchId, int $qty): void
    {
        if (!self::active() || $qty < 1) {
            return;
        }
        $row = DB::table('inventory_branch_stock')->where('product_id', $productId)->where('branch_id', $branchId)->first();
        if ($row === null) {
            return;
        }
        $after = max(0, (int) $row->quantity - $qty);
        DB::table('inventory_branch_stock')->where('id', $row->id)->update(['quantity' => $after, 'updated_at' => now()]);
        self::warnIfLow($productId, $branchId, (int) $row->quantity, $after, $row->min_quantity ?? null);
    }

    /** A shelf has just dropped to (or below) its level: tell the owner and managers once, not on every sale after. */
    private static function warnIfLow(int $productId, int $branchId, int $before, int $after, mixed $min): void
    {
        if ($min === null || (int) $min < 0 || $before <= (int) $min || $after > (int) $min) {
            return;
        }
        try {
            $product = (string) DB::table('inventory_products')->where('id', $productId)->value('name');
            $branch = (string) DB::table('inventory_branches')->where('id', $branchId)->value('name');
            app(\App\Services\Inventory\InventoryNotifier::class)->notifyByPermission(
                ['inv_view_reports'],
                'salon_branch_low_stock',
                'Bidhaa zinaisha kwenye tawi / Running low in a branch',
                "{$branch}: {$product} " . ($after === 0 ? 'zimeisha / out' : "zimebaki / left {$after}"),
                ['product_id' => $productId, 'branch_id' => $branchId, 'quantity' => $after],
            );
        } catch (\Throwable) {
            // An alert never stops a sale.
        }
    }

    /** Say what a branch's shelf of a product should not fall below (null = no alert). */
    public static function setLevel(int $productId, int $branchId, ?int $min): void
    {
        $row = DB::table('inventory_branch_stock')->where('product_id', $productId)->where('branch_id', $branchId)->first();
        if ($row === null) {
            DB::table('inventory_branch_stock')->insert(['product_id' => $productId, 'branch_id' => $branchId, 'quantity' => 0, 'min_quantity' => $min, 'created_at' => now(), 'updated_at' => now()]);

            return;
        }
        DB::table('inventory_branch_stock')->where('id', $row->id)->update(['min_quantity' => $min, 'updated_at' => now()]);
    }

    /** A cancelled sale: the goods are back on the shelf of the branch they were sold from. */
    public static function giveBack(int $productId, int $branchId, int $qty): void
    {
        if (self::active()) {
            self::add($productId, $branchId, $qty);
        }
    }
}
