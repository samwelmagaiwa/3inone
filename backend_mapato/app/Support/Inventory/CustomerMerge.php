<?php

namespace App\Support\Inventory;

use App\Services\Inventory\AuditTrail;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Two customer records that are really one person become one: everything the second one has (sales and their payments, debts from
 * before the app, crates, appointments, salon history) is moved onto the first, and the second goes to the Trash. Nothing is lost and
 * no amount changes: the debts, payments and profit of both simply add up on one customer account.
 */
final class CustomerMerge
{
    /** Tables whose rows simply point at a customer: moving them is one update each. */
    private const MOVE = [
        'inventory_sales',
        'inventory_opening_debts',
        'inventory_parked_sales',
        'inventory_crate_movements',
        'inventory_appointments',
        'inventory_price_changes',
        'inventory_client_photos',
        'inventory_loyalty_ledger',
        'inventory_client_packages',
        'inventory_feedback',
        'inventory_feedback_requests',
        'inventory_walkins',
    ];

    /** Tables where one customer may have only one row for some key: a row that would clash is dropped (the kept customer's row wins). */
    private const ONE_PER = [
        'inventory_product_prices' => ['product_unit_id', 'tier'],
        'inventory_rebook_reminders' => ['owner_id', 'visit_on'],
        'inventory_birthday_wishes' => ['owner_id', 'service', 'year'],
    ];

    /**
     * @return array{kept: int, moved: array<string, int>}
     */
    public static function merge(Request $request, int $keepId, int $dropId): array
    {
        if ($keepId === $dropId) {
            throw ValidationException::withMessages(['into_id' => ['Chagua mteja mwingine. / Choose a different customer.']]);
        }
        $keep = DB::table('inventory_customers')->where('id', $keepId)->first();
        $drop = DB::table('inventory_customers')->where('id', $dropId)->first();
        if ($keep === null || $drop === null) {
            abort(404, 'Not found');
        }

        $moved = [];
        DB::transaction(function () use ($keepId, $dropId, $keep, $drop, &$moved): void {
            foreach (self::MOVE as $table) {
                $n = DB::table($table)->where('customer_id', $dropId)->update(['customer_id' => $keepId]);
                if ($n > 0) {
                    $moved[$table] = $n;
                }
            }
            foreach (self::ONE_PER as $table => $columns) {
                $moved[$table] = 0;
                foreach (DB::table($table)->where('customer_id', $dropId)->get() as $row) {
                    $clash = DB::table($table)->where('customer_id', $keepId);
                    foreach ($columns as $c) {
                        $row->$c === null ? $clash->whereNull($c) : $clash->where($c, $row->$c);
                    }
                    if ($clash->exists()) {
                        DB::table($table)->where('id', $row->id)->delete();
                    } else {
                        DB::table($table)->where('id', $row->id)->update(['customer_id' => $keepId]);
                        $moved[$table]++;
                    }
                }
                if ($moved[$table] === 0) {
                    unset($moved[$table]);
                }
            }

            // what the kept record lacks, the other one gives: the number, the address, a credit limit
            $fill = [];
            if (trim((string) $keep->phone) === '' && trim((string) $drop->phone) !== '') {
                $fill['phone'] = $drop->phone;
            }
            if (trim((string) ($keep->address ?? '')) === '' && trim((string) ($drop->address ?? '')) !== '') {
                $fill['address'] = $drop->address;
            }
            if ((float) ($keep->credit_limit ?? 0) <= 0 && (float) ($drop->credit_limit ?? 0) > 0) {
                $fill['credit_limit'] = $drop->credit_limit;
            }
            if ($fill !== []) {
                DB::table('inventory_customers')->where('id', $keepId)->update($fill + ['updated_at' => now()]);
            }
        });

        RecordTrash::trash($request, 'customers', $dropId, "Merged into #{$keepId} ({$keep->name})");
        app(AuditTrail::class)->record($request, 'customer', $keepId, 'merged', ['merged_from' => $dropId], ['moved' => $moved], (string) $keep->name);

        return ['kept' => $keepId, 'moved' => $moved];
    }
}
