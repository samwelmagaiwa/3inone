<?php

namespace App\Http\Controllers\API\Inventory;

use App\Services\Inventory\AuditTrail;
use App\Services\Inventory\ProductUnits;
use App\Services\Inventory\SkuGenerator;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Routing\Controller;
use OpenApi\Attributes as OA;

#[OA\Tag(name: 'Inventory / Products', description: 'Product catalog: create, list, price, and retire products.')]
class ProductController extends Controller
{
    public function __construct(
        private readonly SkuGenerator $skuGenerator,
        private readonly AuditTrail   $audit,
        private readonly ProductUnits $units,
    ) {
    }

    #[OA\Get(
        path: '/inventory/products',
        summary: 'List products',
        description: 'Paginated product list with search, status, and low-stock filters.',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Products'],
        parameters: [
            new OA\Parameter(name: 'q', in: 'query', description: 'Search name/SKU/barcode', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string', enum: ['active', 'inactive'])),
            new OA\Parameter(name: 'low_stock', in: 'query', schema: new OA\Schema(type: 'boolean')),
            new OA\Parameter(name: 'category_id', in: 'query', schema: new OA\Schema(type: 'integer')),
            new OA\Parameter(name: 'brand_id', in: 'query', schema: new OA\Schema(type: 'integer')),
            new OA\Parameter(name: 'family_id', in: 'query', description: 'Every size / colour of one product', schema: new OA\Schema(type: 'integer')),
            new OA\Parameter(name: 'with_units', in: 'query', description: 'Include each product\'s selling units and prices', schema: new OA\Schema(type: 'boolean')),
        ],
        responses: [
            new OA\Response(
                response: 200,
                description: 'Paginated product list',
                content: new OA\JsonContent(properties: [
                    new OA\Property(property: 'data', type: 'array', items: new OA\Items(type: 'object')),
                    new OA\Property(property: 'meta', ref: '#/components/schemas/PaginationMeta'),
                ], type: 'object'),
            ),
        ],
    )]
    #[OA\Get(
        path: '/products',
        summary: 'List products',
        description: 'Paginated product list with search, status, and low-stock filters.',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Products'],
        parameters: [
            new OA\Parameter(name: 'q', in: 'query', description: 'Search name/SKU/barcode', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string', enum: ['active', 'inactive'])),
            new OA\Parameter(name: 'low_stock', in: 'query', schema: new OA\Schema(type: 'boolean')),
            new OA\Parameter(name: 'category_id', in: 'query', schema: new OA\Schema(type: 'integer')),
            new OA\Parameter(name: 'brand_id', in: 'query', schema: new OA\Schema(type: 'integer')),
        ],
        responses: [
            new OA\Response(
                response: 200,
                description: 'Paginated product list',
                content: new OA\JsonContent(properties: [
                    new OA\Property(property: 'data', type: 'array', items: new OA\Items(type: 'object')),
                    new OA\Property(property: 'meta', ref: '#/components/schemas/PaginationMeta'),
                ], type: 'object'),
            ),
        ],
    )]
    public function index(Request $request)
    {
        $q = $request->query('q');
        $status = $request->query('status');
        $lowStock = (bool) $request->query('low_stock', false);

        $query = DB::table('inventory_products as p')
            ->leftJoin('inventory_categories as c', 'c.id', '=', 'p.category_id')
            ->leftJoin('inventory_brands as b', 'b.id', '=', 'p.brand_id')
            ->select(
                'p.*',
                'c.name as category_name',
                'b.name as brand_name',
                DB::raw('(p.cost_price * p.quantity) as total_cost_price'),
                DB::raw('(p.selling_price * p.quantity) as total_selling_price'),
                DB::raw('((p.selling_price - p.cost_price) * p.quantity) as total_expected_profit')
            );
        if ($q) {
            $query->where(function ($w) use ($q) {
                $w->where('p.name', 'like', "%$q%")
                    ->orWhere('p.sku', 'like', "%$q%")
                    ->orWhere('p.barcode', 'like', "%$q%");
            });
        }
        if ($status) {
            $query->where('p.status', $status);
        }
        if ($lowStock) {
            $query->whereColumn('p.quantity', '<', 'p.min_stock')->where('p.is_service', false);
        }
        // Salon: ?is_service=1 lists only services, ?is_service=0 only goods (shampoo, oils ...).
        if ($request->query('is_service') !== null && $request->query('is_service') !== '') {
            $query->where('p.is_service', $request->boolean('is_service'));
        }
        if ($categoryId = $request->query('category_id')) {
            $query->where('p.category_id', (int) $categoryId);
        }
        if ($brandId = $request->query('brand_id')) {
            $query->where('p.brand_id', (int) $brandId);
        }
        // Every size / colour of one product (the family is the id of its first member).
        if ($family = $request->query('family_id')) {
            $query->where(fn ($w) => $w->where('p.family_id', (int) $family)->orWhere('p.id', (int) $family));
        }

        $products = $query->orderByDesc('p.id')->paginate(20);
        $items = $products->items();

        // `with_units=1`: each product comes with its selling units and their prices, so the till can offer
        // "crate / bottle" or "kg / g" without asking for every product's units one by one.
        if ($request->boolean('with_units') && $items !== []) {
            $units = DB::table('inventory_product_units')
                ->whereIn('product_id', array_map(fn ($p) => $p->id, $items))
                ->orderByDesc('is_base')->orderBy('factor')
                ->get()
                ->groupBy('product_id');
            $prices = DB::table('inventory_product_prices')
                ->whereIn('product_unit_id', $units->flatten(1)->pluck('id'))
                ->get()
                ->groupBy('product_unit_id');

            foreach ($items as $product) {
                $product->units = ($units[$product->id] ?? collect())->map(function ($unit) use ($prices) {
                    $unit->prices = array_values(($prices[$unit->id] ?? collect())->all());

                    return $unit;
                })->values()->all();
            }
        }

        // A service's two lists are stored as JSON text; the app gets real lists.
        foreach ($items as $product) {
            foreach (['staff_ids', 'price_options'] as $list) {
                if (property_exists($product, $list)) {
                    $product->$list = json_decode((string) $product->$list, true) ?: [];
                }
            }
        }

        return response()->json([
            'data' => $items,
            'meta' => [
                'current_page' => $products->currentPage(),
                'last_page' => $products->lastPage(),
                'per_page' => $products->perPage(),
                'total' => $products->total(),
            ],
        ]);
    }

    #[OA\Post(
        path: '/inventory/products',
        summary: 'Create a product',
        description: 'SKU auto-generates from name/brand/unit when left blank. `unit_factor` sets '
            . 'how many of `unit` the cost/selling price cover (e.g. 5 for "per 5 KG").',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Products'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'cost_price', 'selling_price', 'quantity', 'min_stock', 'status'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', example: 'Coca-Cola 350ml'),
                    new OA\Property(property: 'description', type: 'string', nullable: true),
                    new OA\Property(property: 'sku', type: 'string', nullable: true, description: 'Leave blank to auto-generate'),
                    new OA\Property(property: 'category_id', type: 'integer', nullable: true),
                    new OA\Property(property: 'brand_id', type: 'integer', nullable: true),
                    new OA\Property(property: 'cost_price', type: 'number', format: 'float', example: 20000),
                    new OA\Property(property: 'selling_price', type: 'number', format: 'float', example: 25000),
                    new OA\Property(property: 'unit', type: 'string', example: 'crate'),
                    new OA\Property(property: 'unit_factor', type: 'integer', example: 1, description: 'How many of `unit` the prices above cover'),
                    new OA\Property(property: 'quantity', type: 'integer', example: 100),
                    new OA\Property(property: 'min_stock', type: 'integer', example: 10),
                    new OA\Property(property: 'status', type: 'string', enum: ['active', 'inactive']),
                    new OA\Property(property: 'barcode', type: 'string', nullable: true),
                    new OA\Property(property: 'price_tier', type: 'string', enum: ['retail', 'wholesale'], nullable: true),
                ],
            ),
        ),
        responses: [
            new OA\Response(response: 201, description: 'Product created', content: new OA\JsonContent(properties: [
                new OA\Property(property: 'message', type: 'string', example: 'Product created'),
                new OA\Property(property: 'data', properties: [
                    new OA\Property(property: 'id', type: 'integer'),
                    new OA\Property(property: 'sku', type: 'string'),
                ], type: 'object'),
            ], type: 'object')),
            new OA\Response(response: 422, description: 'Validation failed', content: new OA\JsonContent(ref: '#/components/schemas/ValidationErrorResponse')),
        ],
    )]
    public function store(Request $request)
    {
        $data = $request->validate(array_merge([
            'name' => 'required|string|max:255',
            'description' => 'nullable|string|max:1000',
            // Leave blank to have the depot generate one automatically.
            'sku' => 'nullable|string|max:255|unique:inventory_products,sku',
            'category' => 'nullable|string|max:255',
            'category_id' => 'nullable|integer|exists:inventory_categories,id',
            'brand_id' => 'nullable|integer|exists:inventory_brands,id',
            'cost_price' => 'required|numeric|min:0',
            'selling_price' => 'required|numeric|min:0',
            'unit' => 'nullable|string|max:32',
            // How many of this unit the cost/selling price cover, e.g. "per 5 KG".
            'unit_factor' => 'nullable|integer|min:1',
            // Whole numbers only, always: stock is counted in the smallest unit (pieces, grams, millilitres).
            'quantity' => 'required_without:variants|nullable|integer|min:0',
            'min_stock' => 'required|integer|min:0',
            'status' => 'required|in:active,inactive',
            'barcode' => 'nullable|string|max:255',
            'price_tier' => 'nullable|in:retail,wholesale',
        ], $this->extraRules()));

        $this->assertUnitNamesAreFree($data['unit'] ?? null, $data['units'] ?? [], $data['measure'] ?? 'count');

        $userId = optional($request->user())->id;
        $created = DB::transaction(function () use ($data, $userId) {
            $baseSku = $data['sku'] ?? $this->generateSku($data);

            if (empty($data['variants'])) {
                $row = $this->makeProduct($data, $baseSku, $userId);

                return ['id' => $row['id'], 'sku' => $row['sku'], 'ids' => [$row['id']]];
            }

            // Sizes / colours: each one is its own stock item (own SKU, barcode, quantity), all grouped
            // by family_id (the id of the first). Every one carries the same selling units.
            $ids = [];
            foreach ($data['variants'] as $variant) {
                $row = $this->makeProduct(
                    $this->variantRow($data, $variant),
                    $this->variantSku($baseSku, $variant),
                    $userId,
                );
                $ids[] = $row['id'];
            }
            DB::table('inventory_products')->whereIn('id', $ids)->update(['family_id' => $ids[0]]);

            return ['id' => $ids[0], 'sku' => $baseSku, 'ids' => $ids];
        });

        $this->audit->record($request, 'product', (int) $created['id'], 'created', null, [
            'name' => $data['name'],
            'sku'  => $created['sku'],
            'variants' => count($created['ids']) > 1 ? count($created['ids']) : null,
        ], $data['name']);

        return response()->json([
            'message' => 'Product created',
            'data' => ['id' => (int) $created['id'], 'sku' => $created['sku'], 'ids' => array_map('intval', $created['ids'])],
        ], 201);
    }

    /** The rules for everything beyond the basics: VAT, kind of goods, selling units and variants. */
    private function extraRules(): array
    {
        return [
            // This product's VAT rate; leave out to use the business's default (0 unless it set one).
            'tax_percent' => 'nullable|numeric|min:0|max:100',
            'measure' => 'nullable|in:count,weight,volume',
            'variant_label' => 'nullable|string|max:100',
            // Salon: a SERVICE has no stock; how long it takes, and after how many weeks the client should be
            // reminded to come back for it (empty = the business's own default).
            'is_service' => 'sometimes|boolean',
            'duration_minutes' => 'nullable|integer|min:1|max:1440',
            'rebook_after_weeks' => 'nullable|integer|min:1|max:52',
            // Salon: the share (percent) of a service's price the stylist who did it earns.
            'commission_percent' => 'nullable|numeric|min:0|max:100',
            // ... or a fixed amount each time it is done (the fixed amount wins when both are given).
            'commission_fixed' => 'nullable|numeric|min:0',
            // Salon: who may do this service (account ids; none = anyone) and its price options (short / medium / long hair).
            'staff_ids' => 'nullable|array|max:50',
            'staff_ids.*' => 'string|max:64',
            'price_options' => 'nullable|array|max:10',
            'price_options.*.label' => 'required|string|max:40',
            'price_options.*.price' => 'required|numeric|min:0',
            // The product's own unit's price at the OTHER level: `selling_price` is stored at the product's
            // price_tier (retail or wholesale); this is the same unit's price at the one that is left.
            'other_price' => 'nullable|numeric|min:0',

            // Extra ways to sell it, each holding a whole number of base units (a crate of 24, a kg of 1,000 g).
            'units' => 'nullable|array|max:10',
            'units.*.name' => 'required|string|max:32|distinct',
            'units.*.factor' => 'required|integer|min:1',
            'units.*.barcode' => 'nullable|string|max:255',
            'units.*.retail_price' => 'nullable|numeric|min:0',
            'units.*.wholesale_price' => 'nullable|numeric|min:0',

            // Sizes / colours, created together as separate stock.
            'variants' => 'nullable|array|max:100',
            'variants.*.label' => 'required|string|max:100|distinct',
            'variants.*.sku' => 'nullable|string|max:255|distinct|unique:inventory_products,sku',
            'variants.*.barcode' => 'nullable|string|max:255',
            'variants.*.quantity' => 'nullable|integer|min:0',
            'variants.*.min_stock' => 'nullable|integer|min:0',
            'variants.*.cost_price' => 'nullable|numeric|min:0',
            'variants.*.selling_price' => 'nullable|numeric|min:0',
        ];
    }

    /** The base unit's name: what was typed, else grams / millilitres for weighed goods, else pieces. */
    private function baseUnitName(?string $unit, string $measure): string
    {
        return $unit ?: (ProductUnits::MEASURES[$measure]['base'] ?? 'pcs');
    }

    /** A selling unit may not reuse the base unit's name (one product, one unit of each name). */
    private function assertUnitNamesAreFree(?string $unit, array $units, string $measure): void
    {
        $base = mb_strtolower($this->baseUnitName($unit, $measure));
        foreach ($units as $i => $extra) {
            if (mb_strtolower((string) $extra['name']) === $base) {
                throw \Illuminate\Validation\ValidationException::withMessages([
                    "units.{$i}.name" => ["\"{$extra['name']}\" is already this product's own unit."],
                ]);
            }
        }
    }

    /**
     * Insert one product with its base selling unit, the price that unit starts with, the change-log row,
     * and any extra selling units. Call inside a transaction.
     *
     * @return array{id: int, sku: string}
     */
    private function makeProduct(array $p, string $sku, int|string|null $userId): array
    {
        $extraUnits = $p['units'] ?? [];
        $measure = $p['measure'] ?? 'count';
        $unitName = $this->baseUnitName($p['unit'] ?? null, $measure);
        $unitFactor = $p['unit_factor'] ?? 1;
        $tier = $p['price_tier'] ?? 'retail';

        $id = DB::table('inventory_products')->insertGetId([
            'name' => $p['name'],
            'description' => $p['description'] ?? null,
            'sku' => $sku,
            'category' => $p['category'] ?? null,
            'category_id' => $p['category_id'] ?? null,
            'brand_id' => $p['brand_id'] ?? null,
            'cost_price' => $p['cost_price'],
            'selling_price' => $p['selling_price'],
            'unit' => $unitName,
            'unit_factor' => $unitFactor,
            // A service has no stock to count or to run low on.
            'quantity' => !empty($p['is_service']) ? 0 : ($p['quantity'] ?? 0),
            'min_stock' => !empty($p['is_service']) ? 0 : $p['min_stock'],
            'status' => $p['status'],
            'barcode' => $p['barcode'] ?? null,
            'price_tier' => $tier,
            'is_service' => !empty($p['is_service']),
            'duration_minutes' => $p['duration_minutes'] ?? null,
            'rebook_after_weeks' => $p['rebook_after_weeks'] ?? null,
            ...(\Illuminate\Support\Facades\Schema::hasColumn('inventory_products', 'commission_percent')
                ? ['commission_percent' => !empty($p['is_service']) ? ($p['commission_percent'] ?? null) : null]
                : []),
            ...(\Illuminate\Support\Facades\Schema::hasColumn('inventory_products', 'commission_fixed')
                ? ['commission_fixed' => !empty($p['is_service']) ? ($p['commission_fixed'] ?? null) : null]
                : []),
            ...(\Illuminate\Support\Facades\Schema::hasColumn('inventory_products', 'staff_ids')
                ? [
                    'staff_ids' => !empty($p['is_service']) ? self::jsonList($p['staff_ids'] ?? null) : null,
                    'price_options' => !empty($p['is_service']) ? self::jsonList($p['price_options'] ?? null) : null,
                ]
                : []),
            'tax_percent' => $p['tax_percent'] ?? null,
            'variant_label' => $p['variant_label'] ?? null,
            'measure' => $measure,
            'created_by' => $userId,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        // Every product needs a base selling unit so it can be priced and sold.
        $unitId = DB::table('inventory_product_units')->insertGetId([
            'product_id' => $id,
            'name' => $unitName,
            'factor' => $unitFactor,
            'is_base' => true,
            'barcode' => $p['barcode'] ?? null,
            'status' => 'active',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        DB::table('inventory_product_prices')->insert([
            'product_unit_id' => $unitId,
            'tier' => $tier,
            'customer_id' => null,
            'price' => $p['selling_price'],
            'effective_from' => now()->toDateString(),
            'created_by' => $userId,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        DB::table('inventory_price_changes')->insert([
            'product_unit_id' => $unitId,
            'tier' => $tier,
            'customer_id' => null,
            'old_price' => null,
            'new_price' => $p['selling_price'],
            'reason' => 'Product created',
            'changed_by' => $userId,
            'created_at' => now(),
        ]);

        if (isset($p['other_price'])) {
            $this->units->writePrice($unitId, $tier === 'wholesale' ? 'retail' : 'wholesale', null, (float) $p['other_price'], 'Product created', $userId);
        }

        foreach ($extraUnits as $extra) {
            $this->units->add($id, $extra, $userId, 'Product created');
        }

        return ['id' => (int) $id, 'sku' => $sku];
    }

    /** One variant's product row: the parent's details, with the variant's own name, stock and (optional) prices. */
    private function variantRow(array $parent, array $variant): array
    {
        return array_merge($parent, [
            'name' => $parent['name'] . ' — ' . trim($variant['label']),
            'variant_label' => trim($variant['label']),
            'barcode' => $variant['barcode'] ?? null,
            'quantity' => $variant['quantity'] ?? 0,
            'min_stock' => $variant['min_stock'] ?? $parent['min_stock'],
            'cost_price' => $variant['cost_price'] ?? $parent['cost_price'],
            'selling_price' => $variant['selling_price'] ?? $parent['selling_price'],
            'units' => $parent['units'] ?? [],
        ]);
    }

    /** "TSHIRT" + "M / Red" -> "TSHIRT-M-RED" (or the SKU the user typed), made unique within the business. */
    private function variantSku(string $baseSku, array $variant): string
    {
        if (! empty($variant['sku'])) {
            return $variant['sku'];
        }

        $suffix = strtoupper(trim(preg_replace('/[^A-Za-z0-9]+/', '-', $variant['label']) ?? '', '-')) ?: 'V';
        $sku = $baseSku . '-' . substr($suffix, 0, 24);
        $candidate = $sku;
        for ($n = 2; DB::table('inventory_products')->where('sku', $candidate)->exists(); $n++) {
            $candidate = $sku . '-' . $n;
        }

        return $candidate;
    }

    /**
     * POST /inventory/products/{id}/variants
     *
     * Add more sizes / colours to an existing product. Each one is a new stock item that copies the
     * product's details, prices and selling units, with its own label, SKU, barcode and quantity. The
     * product joins (or starts) a family so all its sizes / colours can be listed together.
     */
    #[OA\Post(
        path: '/inventory/products/{id}/variants',
        summary: 'Add sizes / colours to a product',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Products'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        responses: [new OA\Response(response: 201, description: 'Variants created')],
    )]
    public function addVariants(Request $request, int $id)
    {
        $source = DB::table('inventory_products')->where('id', $id)->first();
        if (! $source) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $data = $request->validate([
            'variants' => 'required|array|min:1|max:100',
            'variants.*.label' => 'required|string|max:100|distinct',
            'variants.*.sku' => 'nullable|string|max:255|distinct|unique:inventory_products,sku',
            'variants.*.barcode' => 'nullable|string|max:255',
            'variants.*.quantity' => 'nullable|integer|min:0',
            'variants.*.min_stock' => 'nullable|integer|min:0',
            'variants.*.cost_price' => 'nullable|numeric|min:0',
            'variants.*.selling_price' => 'nullable|numeric|min:0',
        ]);

        $familyId = (int) ($source->family_id ?: $source->id);
        $taken = DB::table('inventory_products')
            ->where(fn ($w) => $w->where('family_id', $familyId)->orWhere('id', $familyId))
            ->whereNotNull('variant_label')
            ->pluck('variant_label')
            ->map(fn ($l) => mb_strtolower(trim((string) $l)))
            ->all();
        foreach ($data['variants'] as $i => $variant) {
            if (in_array(mb_strtolower(trim($variant['label'])), $taken, true)) {
                return response()->json(['message' => "\"{$variant['label']}\" already exists for this product"], 422);
            }
        }

        $suffix = $source->variant_label ? ' — ' . $source->variant_label : null;
        $baseName = ($suffix && str_ends_with((string) $source->name, $suffix))
            ? substr((string) $source->name, 0, -strlen($suffix))
            : $source->name;

        $parent = [
            'name' => $baseName,
            'description' => $source->description,
            'category' => $source->category,
            'category_id' => $source->category_id,
            'brand_id' => $source->brand_id,
            'cost_price' => (float) $source->cost_price,
            'selling_price' => (float) $source->selling_price,
            'unit' => $source->unit,
            'unit_factor' => $source->unit_factor,
            'min_stock' => (int) $source->min_stock,
            'status' => $source->status,
            'price_tier' => $source->price_tier,
            'tax_percent' => $source->tax_percent,
            'measure' => $source->measure ?? 'count',
            'is_service' => (bool) ($source->is_service ?? false),
            'duration_minutes' => $source->duration_minutes ?? null,
            'rebook_after_weeks' => $source->rebook_after_weeks ?? null,
            'units' => $this->unitsOf($id),
        ];

        $userId = optional($request->user())->id;
        $baseSku = $this->familyBaseSku($source);

        $ids = DB::transaction(function () use ($data, $parent, $baseSku, $familyId, $source, $userId) {
            $ids = [];
            foreach ($data['variants'] as $variant) {
                $row = $this->makeProduct(
                    $this->variantRow($parent, $variant),
                    $this->variantSku($baseSku, $variant),
                    $userId,
                );
                $ids[] = $row['id'];
            }
            DB::table('inventory_products')->whereIn('id', $ids)->update(['family_id' => $familyId]);
            if (! $source->family_id) {
                DB::table('inventory_products')->where('id', $source->id)->update(['family_id' => $familyId]);
            }

            return $ids;
        });

        $this->audit->record($request, 'product', $id, 'variants_added', null, ['count' => count($ids)], $source->name);

        return response()->json([
            'message' => 'Variants created',
            'data' => ['ids' => array_map('intval', $ids), 'family_id' => $familyId],
        ], 201);
    }

    /** A product's extra selling units with their retail / wholesale prices, in the shape makeProduct() takes. */
    private function unitsOf(int $productId): array
    {
        $units = DB::table('inventory_product_units')->where('product_id', $productId)->where('is_base', false)->get();
        $prices = DB::table('inventory_product_prices')
            ->whereIn('product_unit_id', $units->pluck('id'))
            ->whereNull('customer_id')
            ->get()
            ->groupBy('product_unit_id');

        return $units->map(function ($u) use ($prices) {
            $byTier = ($prices[$u->id] ?? collect())->keyBy('tier');

            return [
                'name' => $u->name,
                'factor' => (int) $u->factor,
                'barcode' => null,
                'retail_price' => isset($byTier['retail']) ? (float) $byTier['retail']->price : null,
                'wholesale_price' => isset($byTier['wholesale']) ? (float) $byTier['wholesale']->price : null,
            ];
        })->values()->all();
    }

    /** The SKU a family's variants hang their suffix on: this product's, without its own size / colour suffix. */
    private function familyBaseSku(object $source): string
    {
        if ($source->variant_label) {
            $suffix = '-' . strtoupper(trim(preg_replace('/[^A-Za-z0-9]+/', '-', $source->variant_label) ?? '', '-'));
            if ($suffix !== '-' && str_ends_with(strtoupper((string) $source->sku), strtoupper(substr($suffix, 0, 25)))) {
                return substr((string) $source->sku, 0, -strlen(substr($suffix, 0, 25)));
            }
        }

        return (string) $source->sku;
    }

    /** Auto-generate a structured SKU: BRAND-PRODUCT-SIZE-UNIT. */
    private function generateSku(array $data): string
    {
        return $this->skuGenerator->generate(
            $data['name'],
            $data['brand_id'] ?? null,
            $data['unit'] ?? null,
        );
    }

    #[OA\Put(

        path: '/inventory/products/{id}',

        summary: 'Update a resource',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Products'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['name', 'cost_price', 'selling_price', 'quantity', 'min_stock', 'status'],
                properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'description', type: 'string', nullable: true),
                new OA\Property(property: 'category', type: 'string', nullable: true),
                new OA\Property(property: 'category_id', type: 'integer', nullable: true),
                new OA\Property(property: 'brand_id', type: 'integer', nullable: true),
                new OA\Property(property: 'cost_price', type: 'number'),
                new OA\Property(property: 'selling_price', type: 'number'),
                new OA\Property(property: 'unit', type: 'string', nullable: true),
                new OA\Property(property: 'unit_factor', type: 'integer', nullable: true),
                new OA\Property(property: 'quantity', type: 'integer'),
                new OA\Property(property: 'min_stock', type: 'integer'),
                new OA\Property(property: 'status', type: 'string', enum: ['active', 'inactive']),
                new OA\Property(property: 'barcode', type: 'string', nullable: true),
                new OA\Property(property: 'price_tier', type: 'string', enum: ['retail', 'wholesale'], nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function update(Request $request, int $id)
    {
        $existing = DB::table('inventory_products')->where('id', $id)->first();
        if (! $existing)
            return response()->json(['message' => 'Not found'], 404);

        $data = $request->validate([
            'name' => 'sometimes|required|string|max:255',
            'description' => 'nullable|string|max:1000',
            'sku' => 'sometimes|required|string|max:255|unique:inventory_products,sku,' . $id,
            'category' => 'nullable|string|max:255',
            'category_id' => 'nullable|integer|exists:inventory_categories,id',
            'brand_id' => 'nullable|integer|exists:inventory_brands,id',
            'cost_price' => 'sometimes|required|numeric|min:0',
            'selling_price' => 'sometimes|required|numeric|min:0',
            'unit' => 'nullable|string|max:32',
            'unit_factor' => 'nullable|integer|min:1',
            'quantity' => 'sometimes|required|integer|min:0',
            'min_stock' => 'sometimes|required|integer|min:0',
            'status' => 'sometimes|required|in:active,inactive',
            'barcode' => 'nullable|string|max:255',
            'price_tier' => 'nullable|in:retail,wholesale',
            'tax_percent' => 'nullable|numeric|min:0|max:100',
            'measure' => 'nullable|in:count,weight,volume',
            'variant_label' => 'nullable|string|max:100',
            'is_service' => 'sometimes|boolean',
            'duration_minutes' => 'nullable|integer|min:1|max:1440',
            'rebook_after_weeks' => 'nullable|integer|min:1|max:52',
            // Salon: the share (percent) of a service's price the stylist who did it earns.
            'commission_percent' => 'nullable|numeric|min:0|max:100',
            // ... or a fixed amount each time it is done (the fixed amount wins when both are given).
            'commission_fixed' => 'nullable|numeric|min:0',
            // Salon: who may do this service (account ids; none = anyone) and its price options (short / medium / long hair).
            'staff_ids' => 'nullable|array|max:50',
            'staff_ids.*' => 'string|max:64',
            'price_options' => 'nullable|array|max:10',
            'price_options.*.label' => 'required|string|max:40',
            'price_options.*.price' => 'required|numeric|min:0',
        ]);

        // Goods and services are told apart on every old sale line, so an item that has been sold cannot change
        // from one to the other: make a new item instead.
        if (array_key_exists('is_service', $data) && (bool) $data['is_service'] !== (bool) ($existing->is_service ?? false)) {
            if (DB::table('inventory_sale_items')->where('product_id', $id)->exists()) {
                return response()->json([
                    'message' => 'Bidhaa iliyokwisha uzwa haiwezi kubadilishwa kuwa huduma (wala huduma kuwa bidhaa). Tengeneza mpya. / '
                        . 'An item that has been sold cannot change between a product and a service. Create a new one.',
                ], 422);
            }
        }
        if (!empty($data['is_service'])) {
            $data['quantity'] = 0;
            $data['min_stock'] = 0;
        }

        // Renaming a size/colour renames the product too ("T-Shirt — M" -> "T-Shirt — L"), unless the
        // name was changed on purpose in the same request.
        if (array_key_exists('variant_label', $data) && ! array_key_exists('name', $data) && $existing->variant_label) {
            $suffix = ' — ' . $existing->variant_label;
            if (str_ends_with((string) $existing->name, $suffix)) {
                $label = trim((string) ($data['variant_label'] ?? ''));
                $data['name'] = substr((string) $existing->name, 0, -strlen($suffix)) . ($label !== '' ? ' — ' . $label : '');
            }
        }

        // A column the server has not been migrated to yet is left out rather than failing the whole save.
        foreach (['commission_percent', 'commission_fixed', 'staff_ids', 'price_options'] as $column) {
            if (!\Illuminate\Support\Facades\Schema::hasColumn('inventory_products', $column)) {
                unset($data[$column]);
            }
        }

        // The two lists of a service are kept as JSON; only a service has them.
        foreach (['staff_ids', 'price_options'] as $list) {
            if (array_key_exists($list, $data) || (array_key_exists('is_service', $data) && empty($data['is_service']))) {
                $data[$list] = !empty($data['is_service']) || (!array_key_exists('is_service', $data) && !empty($existing->is_service))
                    ? self::jsonList($data[$list] ?? null)
                    : null;
            }
        }

        DB::transaction(function () use ($id, $data) {
            DB::table('inventory_products')->where('id', $id)->update(array_merge($data, [
                'updated_at' => now(),
            ]));

            // Mirror unit/unit_factor onto the base selling unit so the
            // per-unit pricing table (inventory_product_units) stays in sync.
            if (isset($data['unit']) || isset($data['unit_factor'])) {
                $baseUpdate = ['updated_at' => now()];
                if (isset($data['unit'])) {
                    $baseUpdate['name'] = $data['unit'];
                }
                if (isset($data['unit_factor'])) {
                    $baseUpdate['factor'] = $data['unit_factor'];
                }
                DB::table('inventory_product_units')
                    ->where('product_id', $id)
                    ->where('is_base', true)
                    ->update($baseUpdate);
            }

            // Keep price-tier rows in sync: when the product's mode changes,
            // flip the tier on every base-unit price row so the app reads real data.
            if (isset($data['price_tier'])) {
                $newTier = $data['price_tier'];
                $oldTier = $newTier === 'wholesale' ? 'retail' : 'wholesale';
                $baseUnitIds = DB::table('inventory_product_units')
                    ->where('product_id', $id)
                    ->where('is_base', true)
                    ->pluck('id');
                if ($baseUnitIds->isNotEmpty()) {
                    DB::table('inventory_product_prices')
                        ->whereIn('product_unit_id', $baseUnitIds)
                        ->where('tier', $oldTier)
                        ->whereNull('customer_id')
                        ->update(['tier' => $newTier, 'updated_at' => now()]);
                }
            }
        });

        $this->audit->record($request, 'product', $id, 'updated', (array) $existing, $data, $existing->name);

        return response()->json(['message' => 'Product updated']);
    }

    /**
     * DELETE /inventory/products/{id}
     *
     * Hard-delete when no sales history exists.
     * Pass ?force=1 (admin-only) to archive (status=inactive) instead
     * of deleting a product that has sales history.
     */
    #[OA\Delete(
        path: '/inventory/products/{id}',
        summary: 'Delete a resource',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Products'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function destroy(Request $request, int $id)
    {
        $existing = DB::table('inventory_products')->where('id', $id)->first();
        if (! $existing) {
            return response()->json(['message' => 'Not found'], 404);
        }

        $force = filter_var($request->query('force', false), FILTER_VALIDATE_BOOLEAN);
        $sold  = DB::table('inventory_sale_items')->where('product_id', $id)->exists();

        if ($sold && ! $force) {
            return response()->json([
                'message'     => 'Product has sales history. Pass ?force=1 to archive (deactivate) instead.',
                'sales_count' => DB::table('inventory_sale_items')->where('product_id', $id)->count(),
            ], 422);
        }

        if ($sold && $force) {
            $user = $request->user();
            if (! $user || ! ($user->isSuperAdmin() || in_array($user->role, ['admin', 'manager']) || $user->full_access)) {
                return response()->json(['message' => 'Only admins may force-archive a product with sales history.'], 403);
            }
            // Archive rather than hard-delete to preserve financial integrity
            DB::table('inventory_products')->where('id', $id)->update([
                'status'     => 'inactive',
                'updated_at' => now(),
            ]);
            $this->audit->record($request, 'product', $id, 'archived', (array) $existing, ['status' => 'inactive'], $existing->name);
            return response()->json(['message' => 'Product archived (has sales history — cannot be hard-deleted)']);
        }

        DB::table('inventory_products')->where('id', $id)->delete();
        $this->audit->record($request, 'product', $id, 'deleted', (array) $existing, null, $existing->name);

        return response()->json(['message' => 'Product deleted']);
    }

    /** A list kept as JSON text; an empty one (or none) is stored as null. */
    private static function jsonList(mixed $list): ?string
    {
        if (!is_array($list) || $list === []) {
            return null;
        }

        return json_encode(array_values(array_unique($list, SORT_REGULAR)));
    }
}
