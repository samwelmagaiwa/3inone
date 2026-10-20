<?php

namespace App\Http\Controllers\API\Inventory;

use App\Support\Salon\SalonAccess;
use App\Support\Salon\SalonFinance;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use OpenApi\Attributes as OA;

/**
 * Setting the salon up: ready-made service categories, and the goods each service uses up (a tube of dye for a colour,
 * a towel pack for a wash) so stock goes down by itself when the service is sold. Owner, managers and the stock manager.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Categories and materials')]
class SalonSetupController extends Controller
{
    /** Standard categories for a salon (Swahili first, as the app shows them). */
    public const PRESETS = [
        ['Nywele / Hair', 'Cuts, styling, washing, treatments'],
        ['Kusuka / Braiding', 'Braids, twists, weaves, cornrows'],
        ['Rangi / Colour', 'Colouring, highlights, relaxers'],
        ['Kucha / Nails', 'Manicure, pedicure, gel, acrylic'],
        ['Make-up / Makeup', 'Day, evening and bridal makeup'],
        ['Kope / Lashes & Brows', 'Lash extensions, brows, tint'],
        ['Ngozi / Skin', 'Facials, waxing, scrubs'],
        ['Masaji / Massage', 'Body and head massage'],
        ['Kinyozi / Barber', 'Men\'s cuts, shave, beard'],
        ['Bidhaa / Products', 'Shampoo, oils, hair pieces and other goods'],
        ['Vifurushi / Packages', 'Several visits sold together'],
    ];

    private function requireKeeper(Request $request): void
    {
        $role = (string) $request->user()->role;
        abort_unless(SalonAccess::isManager($request->user()) || $role === 'stock_manager', 403, 'Ni mmiliki, meneja au msimamizi wa bidhaa tu. / Only the owner, a manager or the stock manager.');
    }

    #[OA\Post(path: '/inventory/salon/category-presets', summary: 'Add the standard salon categories that are not there yet', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function presets(Request $request): JsonResponse
    {
        $this->requireKeeper($request);
        $have = DB::table('inventory_categories')->pluck('name')->map(fn ($n) => mb_strtolower((string) $n))->all();
        $added = [];
        foreach (self::PRESETS as [$name, $about]) {
            if (in_array(mb_strtolower($name), $have, true)) {
                continue;
            }
            DB::table('inventory_categories')->insert([
                'name' => $name, 'description' => $about, 'status' => 'active',
                'created_by' => optional($request->user())->id, 'created_at' => now(), 'updated_at' => now(),
            ]);
            $added[] = $name;
        }

        return response()->json(['message' => 'Saved', 'data' => ['added' => $added, 'already' => count(self::PRESETS) - count($added)]]);
    }

    #[OA\Get(path: '/inventory/salon/services/{id}/materials', summary: 'The goods a service uses up', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function materials(Request $request, int $id): JsonResponse
    {
        $this->requireKeeper($request);
        abort_if(DB::table('inventory_products')->where('id', $id)->where('is_service', true)->doesntExist(), 404, 'Service not found');

        $rows = DB::table('inventory_service_materials as m')
            ->join('inventory_products as p', 'p.id', '=', 'm.material_product_id')
            ->where('m.service_product_id', $id)
            ->orderBy('p.name')
            ->get(['m.material_product_id', 'm.quantity', 'p.name', 'p.quantity as in_stock', 'p.cost_price'])
            ->map(fn ($r) => [
                'material_product_id' => (int) $r->material_product_id,
                'name' => $r->name,
                'quantity' => (int) $r->quantity,
                'in_stock' => (int) $r->in_stock,
                'cost' => SalonFinance::money($r->cost_price),
            ])->values();

        return response()->json(['data' => $rows]);
    }

    #[OA\Put(path: '/inventory/salon/services/{id}/materials', summary: 'Say which goods (and how many) a service uses up', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function saveMaterials(Request $request, int $id): JsonResponse
    {
        $this->requireKeeper($request);
        abort_if(DB::table('inventory_products')->where('id', $id)->where('is_service', true)->doesntExist(), 404, 'Service not found');
        $data = $request->validate([
            'items' => 'present|array|max:20',
            'items.*.material_product_id' => 'required|integer|distinct',
            'items.*.quantity' => 'required|integer|min:1|max:1000',
        ]);

        foreach ($data['items'] as $i => $item) {
            $ok = DB::table('inventory_products')->where('id', $item['material_product_id'])->where(fn ($q) => $q->where('is_service', false)->orWhereNull('is_service'))->exists();
            if (!$ok) {
                throw ValidationException::withMessages(["items.{$i}.material_product_id" => ['Chagua bidhaa (si huduma). / Choose goods (not a service).']]);
            }
        }

        DB::transaction(function () use ($id, $data) {
            DB::table('inventory_service_materials')->where('service_product_id', $id)->delete();
            foreach ($data['items'] as $item) {
                DB::table('inventory_service_materials')->insert([
                    'service_product_id' => $id, 'material_product_id' => (int) $item['material_product_id'], 'quantity' => (int) $item['quantity'],
                    'created_at' => now(), 'updated_at' => now(),
                ]);
            }
        });

        return response()->json(['message' => 'Saved']);
    }

    #[OA\Get(path: '/inventory/salon/materials-usage', summary: 'What the services used up in a period, and what it cost', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function usage(Request $request): JsonResponse
    {
        $this->requireKeeper($request);
        $data = $request->validate(['from' => 'nullable|date_format:Y-m-d', 'to' => 'nullable|date_format:Y-m-d|after_or_equal:from']);
        $from = $data['from'] ?? now()->startOfMonth()->toDateString();
        $to = $data['to'] ?? now()->toDateString();

        $rows = DB::table('inventory_service_usage as u')
            ->join('inventory_sales as s', 's.id', '=', 'u.sale_id')
            ->leftJoin('inventory_products as p', 'p.id', '=', 'u.material_product_id')
            ->whereNull('s.cancelled_at')
            ->whereDate('u.created_at', '>=', $from)->whereDate('u.created_at', '<=', $to)
            ->groupBy('u.material_product_id', 'p.name')
            ->selectRaw('p.name as name, SUM(u.quantity) as used, SUM(u.quantity * u.unit_cost) as cost')
            ->orderByRaw('SUM(u.quantity * u.unit_cost) DESC')->get()
            ->map(fn ($r) => ['name' => (string) $r->name, 'used' => (int) $r->used, 'cost' => SalonFinance::money($r->cost)])->values();

        return response()->json(['data' => ['from' => $from, 'to' => $to, 'materials' => $rows, 'cost' => SalonFinance::money($rows->sum('cost'))]]);
    }
}
