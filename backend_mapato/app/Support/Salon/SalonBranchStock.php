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
        DB::table('inventory_branch_stock')->where('id', $row->id)->update(['quantity' => max(0, (int) $row->quantity - $qty), 'updated_at' => now()]);
    }

    /** A cancelled sale: the goods are back on the shelf of the branch they were sold from. */
    public static function giveBack(int $productId, int $branchId, int $qty): void
    {
        if (self::active()) {
            self::add($productId, $branchId, $qty);
        }
    }
}
