<?php

namespace App\Support\Inventory;

use App\Models\User;
use App\Services\Inventory\AuditTrail;
use App\Support\Tenancy\TenantContext;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * The Trash of the records an owner or admin manages: expenses, customers, debts from before the app, products and services.
 *
 * "Deleting" one of these only marks it (deleted_at, who, why). The query grammar then keeps it out of every list, total, report and
 * the till, while an old sale still shows the name of a customer or product trashed afterwards. Restore brings it back exactly as it was;
 * removing it for good is a separate, explicit step that is refused whenever the record has history that must be kept.
 */
final class RecordTrash
{
    /** Marks a product's trashed SKU so a new product may use the same SKU; stripped again on restore. */
    private const SKU_TOMB = '~trash~';

    /** type => table */
    public const TYPES = [
        'expenses' => 'inventory_expenses',
        'customers' => 'inventory_customers',
        'debts' => 'inventory_opening_debts',
        'products' => 'inventory_products',
    ];

    /** Everyone who may look into the Trash, restore from it and remove for good: the owner and the admins of the business. */
    public static function mayManage(?User $user): bool
    {
        if ($user === null) {
            return false;
        }

        return $user->isSuperAdmin()
            || (bool) $user->full_access
            || in_array(strtolower((string) $user->role), ['admin', 'administrator'], true)
            || (string) $user->id === $user->accountHeadId();
    }

    public static function requireManager(Request $request): void
    {
        if (!self::mayManage($request->user())) {
            abort(403, 'Ni mmiliki au msimamizi tu anayeweza kutumia Takataka. / Only the owner or an admin can use the Trash.');
        }
    }

    /** What the person sees for a record in the Trash: a title and a line under it. */
    private static function describe(string $type, object $r): array
    {
        return match ($type) {
            'expenses' => ['title' => (string) $r->description, 'subtitle' => trim(((string) $r->category) . ' · ' . substr((string) $r->expense_date, 0, 10), ' ·'), 'amount' => (float) $r->amount],
            'customers' => ['title' => (string) $r->name, 'subtitle' => (string) ($r->phone ?? ''), 'amount' => null],
            'debts' => ['title' => (string) $r->party_name, 'subtitle' => $r->kind === 'receivable' ? 'owed to me' : 'I owe', 'amount' => (float) $r->amount],
            default => ['title' => (string) $r->name, 'subtitle' => preg_replace('/' . preg_quote(self::SKU_TOMB, '/') . '\d+$/', '', (string) $r->sku), 'amount' => (float) $r->selling_price],
        };
    }

    // ------------------------------------------------------------------ into the Trash

    /** Move one record to the Trash. The caller has already checked it is the caller's to delete and that nothing forbids it. */
    public static function trash(Request $request, string $type, int $id, ?string $reason = null): void
    {
        $table = self::TYPES[$type];
        $row = DB::table($table)->where('id', $id)->first();
        if ($row === null) {
            abort(404, 'Not found');
        }

        $update = [
            'deleted_at' => now(),
            'deleted_by' => $request->user() === null ? null : (string) $request->user()->id,
            'delete_reason' => $reason === null || trim($reason) === '' ? null : mb_substr(trim($reason), 0, 255),
            'updated_at' => now(),
        ];
        if ($type === 'products') {
            // a new product may now take the same SKU; restore gives it back
            $update['sku'] = $row->sku . self::SKU_TOMB . $id;
        }

        DB::table($table)->where('id', $id)->update($update);
        app(AuditTrail::class)->record($request, self::entity($type), $id, 'trashed', (array) $row, ['deleted_at' => (string) $update['deleted_at']], self::describe($type, $row)['title']);
    }

    private static function entity(string $type): string
    {
        return ['expenses' => 'expense', 'customers' => 'customer', 'debts' => 'opening_debt', 'products' => 'product'][$type];
    }

    // ------------------------------------------------------------------ looking into it

    /** @return array<string, int> how many records of each kind are in the Trash (and how many sales were cancelled) */
    public static function counts(): array
    {
        return TenantContext::withTrashed(function () {
            $out = [];
            foreach (self::TYPES as $type => $table) {
                $out[$type] = (int) DB::table($table)->whereNotNull('deleted_at')->count();
            }
            $out['sales'] = (int) DB::table('inventory_sales')->whereNotNull('cancelled_at')->count();

            return $out;
        });
    }

    /** @return array{rows: array<int, array<string, mixed>>, total: int} */
    public static function list(string $type, int $page, int $perPage): array
    {
        return TenantContext::withTrashed(function () use ($type, $page, $perPage) {
            if ($type === 'sales') {
                return self::cancelledSales($page, $perPage);
            }

            $table = self::TYPES[$type];
            $q = DB::table($table . ' as t')->whereNotNull('t.deleted_at');
            $total = (int) (clone $q)->count();
            $rows = $q->leftJoin('users as u', 'u.id', '=', 't.deleted_by')
                ->select('t.*', 'u.name as deleted_by_name')
                ->orderByDesc('t.deleted_at')->orderByDesc('t.id')
                ->forPage($page, $perPage)->get();

            return [
                'total' => $total,
                'rows' => $rows->map(fn ($r) => [
                    'id' => (int) $r->id,
                    'type' => $type,
                    ...self::describe($type, $r),
                    'deleted_at' => (string) $r->deleted_at,
                    'deleted_by_name' => $r->deleted_by_name,
                    'reason' => $r->delete_reason,
                    'can_restore' => true,
                    'can_remove' => true,
                ])->values()->all(),
            ];
        });
    }

    /** Cancelled sales: shown for the record (what was cancelled, when, why), never restored: their stock and payments were reversed. */
    private static function cancelledSales(int $page, int $perPage): array
    {
        $q = DB::table('inventory_sales as s')->whereNotNull('s.cancelled_at');
        $total = (int) (clone $q)->count();
        $rows = $q->leftJoin('inventory_customers as c', 'c.id', '=', 's.customer_id')
            ->select('s.id', 's.number', 's.total', 's.cancelled_at', 's.cancellation_reason', DB::raw('COALESCE(c.name, s.customer_name_override) as customer_name'))
            ->orderByDesc('s.cancelled_at')->forPage($page, $perPage)->get();

        return [
            'total' => $total,
            'rows' => $rows->map(fn ($r) => [
                'id' => (int) $r->id,
                'type' => 'sales',
                'title' => (string) $r->number,
                'subtitle' => (string) ($r->customer_name ?? ''),
                'amount' => (float) $r->total,
                'deleted_at' => (string) $r->cancelled_at,
                'deleted_by_name' => null,
                'reason' => $r->cancellation_reason,
                'can_restore' => false,
                'can_remove' => false,
            ])->values()->all(),
        ];
    }

    // ------------------------------------------------------------------ out of the Trash

    /** Bring a record back exactly as it was. A product whose SKU was taken meanwhile needs a new one ([newSku]). */
    public static function restore(Request $request, string $type, int $id, ?string $newSku = null): array
    {
        return TenantContext::withTrashed(function () use ($request, $type, $id, $newSku) {
            $table = self::TYPES[$type];
            $row = DB::table($table)->where('id', $id)->whereNotNull('deleted_at')->first();
            if ($row === null) {
                abort(404, 'Not in the Trash');
            }

            $update = ['deleted_at' => null, 'deleted_by' => null, 'delete_reason' => null, 'updated_at' => now()];
            if ($type === 'products') {
                $sku = $newSku !== null && trim($newSku) !== '' ? trim($newSku) : (string) preg_replace('/' . preg_quote(self::SKU_TOMB, '/') . '\d+$/', '', (string) $row->sku);
                $taken = DB::table('inventory_products')->where('sku', $sku)->where('id', '!=', $id)->whereNull('deleted_at')->exists();
                if ($taken) {
                    throw ValidationException::withMessages(['sku' => ["SKU '{$sku}' imetumika na bidhaa nyingine. Weka SKU mpya. / The SKU '{$sku}' is used by another product now. Give it a new SKU."]]);
                }
                $update['sku'] = $sku;
            }

            DB::table($table)->where('id', $id)->update($update);
            app(AuditTrail::class)->record($request, self::entity($type), $id, 'restored', null, null, self::describe($type, $row)['title']);

            return ['id' => $id, 'type' => $type];
        });
    }

    /**
     * Remove a trashed record for good. Refused for anything that has history the business needs (a product that was sold or counted, a
     * customer with sales or debts, a debt that was paid on): that stays in the Trash for the record.
     */
    public static function remove(Request $request, string $type, int $id): void
    {
        TenantContext::withTrashed(function () use ($request, $type, $id) {
            $table = self::TYPES[$type];
            $row = DB::table($table)->where('id', $id)->whereNotNull('deleted_at')->first();
            if ($row === null) {
                abort(404, 'Not in the Trash');
            }

            $why = self::keepBecause($type, $id);
            if ($why !== null) {
                throw ValidationException::withMessages(['id' => [$why]]);
            }

            DB::transaction(function () use ($table, $type, $id) {
                if ($type === 'debts') {
                    DB::table('inventory_opening_payments')->where('debt_id', $id)->delete();
                }
                DB::table($table)->where('id', $id)->delete();
            });
            app(AuditTrail::class)->record($request, self::entity($type), $id, 'removed_for_good', (array) $row, null, self::describe($type, $row)['title']);
        });
    }

    private static function keepBecause(string $type, int $id): ?string
    {
        $keep = static fn (string $en, string $sw): string => "{$sw} / {$en}";

        if ($type === 'products') {
            $used = DB::table('inventory_sale_items')->where('product_id', $id)->exists()
                || DB::table('inventory_stock_movements')->where('product_id', $id)->exists()
                || DB::table('inventory_batches')->where('product_id', $id)->exists();
            if ($used) {
                return $keep('It has been sold or stocked, so it stays in the Trash for your records.', 'Imeuzwa au kuwekwa dukani, kwa hiyo inabaki Takataka kwa kumbukumbu.');
            }
        }

        if ($type === 'customers') {
            $used = DB::table('inventory_sales')->where('customer_id', $id)->exists()
                || DB::table('inventory_opening_debts')->where('customer_id', $id)->exists()
                || DB::table('inventory_crate_movements')->where('customer_id', $id)->exists();
            if ($used) {
                return $keep('This customer has sales or debts on record, so it stays in the Trash for your records.', 'Mteja huyu ana mauzo au madeni kwenye kumbukumbu, kwa hiyo anabaki Takataka.');
            }
        }

        if ($type === 'debts' && DB::table('inventory_opening_payments')->where('debt_id', $id)->exists()) {
            return $keep('Payments were recorded on this debt, so it stays in the Trash for your records.', 'Malipo yalirekodiwa kwenye deni hili, kwa hiyo linabaki Takataka kwa kumbukumbu.');
        }

        return null;
    }
}
