<?php

namespace App\Http\Controllers\API\Inventory;

use Illuminate\Http\Request;
use App\Support\InventoryDefaults;
use App\Support\Pagination;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

/**
 * Areas 12 and 13 — alerts, the audit trail viewer and depot settings.
 */
class AlertController extends Controller
{
    #[OA\Get(
        path: '/inventory/alerts',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Inventory / Alert'],
        parameters: [
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string', default: 'open')),
            new OA\Parameter(name: 'type', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function index(Request $request)
    {
        if ($request->boolean('refresh', true)) {
            $this->rebuild();
        }

        $query = DB::table('inventory_alerts');
        if ($status = $request->query('status', 'open')) {
            $query->where('status', $status);
        }
        if ($type = $request->query('type')) {
            $query->where('type', $type);
        }

        // A portable severity ordering (FIELD() is MySQL-only and breaks
        // under the sqlite connection tests run against).
        $rows = $query->orderByRaw(
            "CASE severity WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END",
        )->orderByDesc('created_at')->limit(200)->get();

        return response()->json([
            'data' => $rows,
            'meta' => [
                'open' => DB::table('inventory_alerts')->where('status', 'open')->count(),
                'critical' => DB::table('inventory_alerts')
                    ->where('status', 'open')->where('severity', 'critical')->count(),
            ],
        ]);
    }

    /**
     * Recompute the alert set from live data. Alerts are keyed on
     * type + entity, so a repeat run refreshes rather than duplicates, and a
     * condition that has cleared is resolved automatically.
     */
    public function rebuild(): int
    {
        $settings = DB::table('inventory_settings')->pluck('value', 'key');
        $expiryDays = (int) ($settings['expiry_alert_days'] ?? 30);
        $overdueDays = (int) ($settings['overdue_alert_days'] ?? 7);

        $found = [];

        foreach ($this->lowStock() as $alert) {
            $found[] = $this->upsert($alert);
        }
        foreach ($this->nearExpiry($expiryDays) as $alert) {
            $found[] = $this->upsert($alert);
        }
        foreach ($this->overCreditLimit() as $alert) {
            $found[] = $this->upsert($alert);
        }
        foreach ($this->overdueInvoices($overdueDays) as $alert) {
            $found[] = $this->upsert($alert);
        }
        foreach ($this->pendingApprovals() as $alert) {
            $found[] = $this->upsert($alert);
        }

        // Anything previously open that no longer applies has been dealt with.
        $stale = DB::table('inventory_alerts')->where('status', 'open');
        if ($found !== []) {
            $stale->whereNotIn('id', $found);
        }
        $stale->update(['status' => 'resolved', 'resolved_at' => now()]);

        return count($found);
    }

    private function upsert(array $alert): int
    {
        $existing = DB::table('inventory_alerts')
            ->where('type', $alert['type'])
            ->where('entity_type', $alert['entity_type'])
            ->where('entity_id', $alert['entity_id'])
            ->first();

        if ($existing) {
            DB::table('inventory_alerts')->where('id', $existing->id)->update([
                'title' => $alert['title'],
                'body' => $alert['body'],
                'severity' => $alert['severity'],
                'status' => 'open',
                'resolved_at' => null,
            ]);

            return (int) $existing->id;
        }

        return (int) DB::table('inventory_alerts')->insertGetId($alert + [
            'status' => 'open',
            'created_at' => now(),
        ]);
    }

    private function lowStock(): array
    {
        return DB::table('inventory_products')
            ->whereColumn('quantity', '<', 'min_stock')
            ->where('is_service', false)
            ->where('status', 'active')
            ->get(['id', 'name', 'quantity', 'min_stock'])
            ->map(fn ($p) => [
                'type' => 'low_stock',
                'severity' => $p->quantity <= 0 ? 'critical' : 'warning',
                'title' => "Low stock: {$p->name}",
                'body' => "{$p->quantity} left, minimum is {$p->min_stock}",
                'entity_type' => 'product',
                'entity_id' => (int) $p->id,
            ])->all();
    }

    private function nearExpiry(int $days): array
    {
        return DB::table('inventory_batches as b')
            ->join('inventory_products as p', 'p.id', '=', 'b.product_id')
            ->where('b.quantity', '>', 0)
            ->whereNotNull('b.expiry_date')
            ->whereDate('b.expiry_date', '<=', now()->addDays($days)->toDateString())
            ->get(['b.id', 'b.batch_number', 'b.expiry_date', 'b.quantity', 'p.name'])
            ->map(function ($b) {
                $expired = $b->expiry_date < now()->toDateString();

                return [
                    'type' => $expired ? 'expired' : 'near_expiry',
                    'severity' => $expired ? 'critical' : 'warning',
                    'title' => ($expired ? 'Expired: ' : 'Expiring soon: ') . $b->name,
                    'body' => "Batch {$b->batch_number}, {$b->quantity} units, {$b->expiry_date}",
                    'entity_type' => 'batch',
                    'entity_id' => (int) $b->id,
                ];
            })->all();
    }

    private function overCreditLimit(): array
    {
        return DB::table('inventory_customers as c')
            ->join('inventory_sales as s', 's.customer_id', '=', 'c.id')
            ->whereIn('s.payment_status', ['debt', 'partial'])
            ->where('c.credit_limit', '>', 0)
            ->groupBy('c.id', 'c.name', 'c.credit_limit')
            ->havingRaw('SUM(s.total - s.paid_total) > c.credit_limit')
            ->get([
                'c.id', 'c.name', 'c.credit_limit',
                DB::raw('SUM(s.total - s.paid_total) as balance'),
            ])
            ->map(fn ($c) => [
                'type' => 'over_credit_limit',
                'severity' => 'critical',
                'title' => "Over credit limit: {$c->name}",
                'body' => 'Owes ' . number_format((float) $c->balance, 0)
                    . ' against a limit of ' . number_format((float) $c->credit_limit, 0),
                'entity_type' => 'customer',
                'entity_id' => (int) $c->id,
            ])->all();
    }

    private function overdueInvoices(int $days): array
    {
        return DB::table('inventory_sales as s')
            ->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->whereIn('s.payment_status', ['debt', 'partial'])
            ->whereNotNull('s.due_date')
            ->whereDate('s.due_date', '<', now()->subDays($days)->toDateString())
            ->limit(100)
            ->get(['s.id', 's.number', 's.due_date', 's.total', 's.paid_total', 'c.name'])
            ->map(fn ($s) => [
                'type' => 'overdue_invoice',
                'severity' => 'warning',
                'title' => "Overdue: {$s->number}",
                'body' => ($s->name ?? 'Walk-in') . ' owes '
                    . number_format((float) $s->total - (float) $s->paid_total, 0)
                    . ", due {$s->due_date}",
                'entity_type' => 'sale',
                'entity_id' => (int) $s->id,
            ])->all();
    }

    private function pendingApprovals(): array
    {
        $alerts = [];

        $writeOffs = DB::table('inventory_write_offs')->where('status', 'pending')->count();
        if ($writeOffs > 0) {
            $alerts[] = [
                'type' => 'pending_approval',
                'severity' => 'info',
                'title' => "{$writeOffs} write-off(s) awaiting approval",
                'body' => 'Damages, breakages or expired goods need a decision',
                'entity_type' => 'write_off',
                'entity_id' => 0,
            ];
        }

        $returns = DB::table('inventory_sale_returns')->where('status', 'pending')->count();
        if ($returns > 0) {
            $alerts[] = [
                'type' => 'pending_approval',
                'severity' => 'info',
                'title' => "{$returns} return(s) awaiting approval",
                'body' => 'Returns or cancellations need a decision',
                'entity_type' => 'sale_return',
                'entity_id' => 0,
            ];
        }

        return $alerts;
    }

    #[OA\Post(

        path: '/inventory/alerts/{id}/acknowledge',

        summary: 'Acknowledge',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Alert'],

        parameters: [

            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),

        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function acknowledge(int $id)
    {
        $updated = DB::table('inventory_alerts')->where('id', $id)
            ->update(['status' => 'acknowledged']);

        return $updated
            ? response()->json(['message' => 'Alert acknowledged'])
            : response()->json(['message' => 'Not found'], 404);
    }

    // ---------------------------------------------------- Area 13: audit log

    #[OA\Get(

        path: '/inventory/audit-log',

        summary: 'Audit log',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Alert'],
        parameters: [
            new OA\Parameter(name: 'entity_type', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'entity_id', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'user_id', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'per_page', in: 'query', schema: new OA\Schema(type: 'string', default: '50')),
        ],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function auditLog(Request $request)
    {
        $query = DB::table('inventory_audit_log');

        if ($entityType = $request->query('entity_type')) {
            $query->where('entity_type', $entityType);
        }
        if ($entityId = $request->query('entity_id')) {
            $query->where('entity_id', (int) $entityId);
        }
        if ($userId = $request->query('user_id')) {
            $query->where('user_id', (int) $userId);
        }
        if ($from = $request->query('from')) {
            $query->whereDate('created_at', '>=', $from);
        }
        if ($to = $request->query('to')) {
            $query->whereDate('created_at', '<=', $to);
        }

        $rows = $query->orderByDesc('id')
            ->paginate(Pagination::perPage($request, 50));

        return response()->json([
            'data' => $rows->items(),
            'meta' => [
                'current_page' => $rows->currentPage(),
                'last_page' => $rows->lastPage(),
                'total' => $rows->total(),
            ],
        ]);
    }

    // ---------------------------------------------------- Area 13: settings

    #[OA\Get(

        path: '/inventory/settings',

        summary: 'Settings',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Alert'],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function settings()
    {
        // Stored values win; any setting that has no row yet reads as its default (with the
        // business's own name, contact and TIN where it has them).
        $viewer = \App\Support\Tenancy\TenantContext::viewer();

        return response()->json([
            'data' => array_merge(
                InventoryDefaults::defaultsFor($viewer),
                DB::table('inventory_settings')->pluck('value', 'key')->all(),
                // What kind of business this is (retail, wholesale, mixed, depot). Read from the business,
                // never stored with the settings; an unset one is a depot.
                // (A salon's books are always a retail business's.)
                ['inventory_type' => \App\Support\Tenancy\TenantContext::service() === 'salon' ? 'retail' : (\App\Models\Business::forUser($viewer)?->inventory_type ?: 'depot')],
            ),
        ]);
    }

    #[OA\Put(

        path: '/inventory/settings',

        summary: 'Update settings',

        security: [['bearerAuth' => []]],

        tags: ['Inventory / Alert'],

        responses: [new OA\Response(response: 200, description: 'Success')],

    )]

    public function updateSettings(Request $request)
    {
        // Known settings can always be saved (created on first save); anything else
        // is ignored unless it already exists.
        $allowed = array_unique(array_merge(
            array_keys(InventoryDefaults::SETTINGS),
            DB::table('inventory_settings')->pluck('key')->all(),
        ));
        $payload = $request->all();

        $saved = [];
        foreach ($payload as $key => $value) {
            if (! in_array($key, $allowed, true)) {
                continue;
            }
            DB::table('inventory_settings')->updateOrInsert(['key' => $key], [
                'value' => is_scalar($value) ? (string) $value : json_encode($value),
                'updated_at' => now(),
            ]);
            $saved[] = $key;
        }

        if ($saved === []) {
            return response()->json(['message' => 'Nothing to save'], 422);
        }

        app(\App\Services\Inventory\AuditTrail::class)
            ->record($request, 'settings', null, 'updated', null, $payload);

        return response()->json(['message' => 'Settings saved', 'data' => ['saved' => $saved]]);
    }
}
