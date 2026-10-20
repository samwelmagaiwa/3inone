<?php

namespace App\Http\Controllers\API\Inventory;

use App\Support\Salon\SalonAccess;
use App\Support\Salon\SalonBranch;
use App\Support\Salon\SalonBranchStock;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * Where the goods are: for each product the salon's whole stock, what each branch holds and what is still in the main
 * store, and moving goods between them. Owner, managers and the stock manager move stock; everyone in the salon can look.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Goods stock by branch')]
class SalonBranchStockController extends Controller
{
    private function requireKeeper(Request $request): void
    {
        $role = (string) $request->user()->role;
        abort_unless(SalonAccess::isManager($request->user()) || $role === 'stock_manager', 403, 'Ni mmiliki, meneja au msimamizi wa bidhaa tu. / Only the owner, a manager or the stock manager.');
    }

    #[OA\Get(path: '/inventory/salon/branch-stock', summary: 'Goods with what each branch holds', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function index(Request $request): JsonResponse
    {
        $branches = DB::table('inventory_branches')->where('active', true)->orderBy('name')->get(['id', 'name']);
        $stock = DB::table('inventory_branch_stock')->get()->groupBy('product_id');

        $rows = DB::table('inventory_products')
            ->where(fn ($q) => $q->where('is_service', false)->orWhereNull('is_service'))
            ->where('status', 'active')
            ->orderBy('name')
            ->get(['id', 'name', 'quantity', 'min_stock'])
            ->map(function ($p) use ($stock, $branches) {
                $held = ($stock[$p->id] ?? collect())->pluck('quantity', 'branch_id');
                $allocated = (int) $held->sum();
                $whole = (int) $p->quantity;

                return [
                    'id' => (int) $p->id,
                    'name' => $p->name,
                    'total' => $whole,
                    'unallocated' => max(0, $whole - $allocated),
                    // More is allocated to branches than the salon has (stock was written off or counted down elsewhere).
                    'over_allocated' => $allocated > $whole,
                    'branches' => $branches->map(fn ($b) => ['branch_id' => (int) $b->id, 'name' => $b->name, 'quantity' => (int) ($held[$b->id] ?? 0)])->values(),
                ];
            })->values();

        return response()->json(['data' => ['branches' => $branches->map(fn ($b) => ['id' => (int) $b->id, 'name' => $b->name])->values(), 'products' => $rows, 'selected' => SalonBranch::selected($request)]]);
    }

    #[OA\Post(path: '/inventory/salon/branch-stock/transfer', summary: 'Move goods between the main store and branches, or between branches', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function transfer(Request $request): JsonResponse
    {
        $this->requireKeeper($request);
        $data = $request->validate([
            'product_id' => 'required|integer',
            'from_branch_id' => 'nullable|integer',
            'to_branch_id' => 'nullable|integer',
            'quantity' => 'required|integer|min:1|max:1000000',
        ]);
        $from = $data['from_branch_id'] ?? null;
        $to = $data['to_branch_id'] ?? null;
        if ($from === $to) {
            throw ValidationException::withMessages(['to_branch_id' => ['Chagua mahali tofauti. / Choose a different place.']]);
        }
        $product = DB::table('inventory_products')->where('id', $data['product_id'])->where(fn ($q) => $q->where('is_service', false)->orWhereNull('is_service'))->first();
        if ($product === null) {
            throw ValidationException::withMessages(['product_id' => ['Chagua bidhaa (si huduma). / Choose goods (not a service).']]);
        }
        foreach ([$from, $to] as $b) {
            if ($b !== null && DB::table('inventory_branches')->where('id', $b)->where('active', true)->doesntExist()) {
                throw ValidationException::withMessages(['to_branch_id' => ['Tawi hilo halipo au limezimwa. / That branch does not exist or is switched off.']]);
            }
        }

        $qty = (int) $data['quantity'];
        DB::transaction(function () use ($product, $from, $to, $qty) {
            $have = $from === null ? SalonBranchStock::unallocated((int) $product->id, (int) $product->quantity) : SalonBranchStock::at((int) $product->id, (int) $from);
            if ($qty > $have) {
                throw ValidationException::withMessages(['quantity' => ["Hakuna bidhaa za kutosha mahali hapo (zipo {$have}). / Not enough there ({$have} held)."]]);
            }
            if ($from !== null) {
                SalonBranchStock::take((int) $product->id, (int) $from, $qty);
            }
            if ($to !== null) {
                SalonBranchStock::add((int) $product->id, (int) $to, $qty);
            }
        });

        return response()->json(['message' => 'Saved']);
    }
}
