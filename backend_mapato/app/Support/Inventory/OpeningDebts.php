<?php

namespace App\Support\Inventory;

use App\Support\Salon\SalonClientFromSale;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

/**
 * Debts that began before the business used the app: what customers already owed it (receivable) and what it already owed
 * suppliers or lenders (payable). They are kept apart from sales and supplier invoices so they never count as this month's
 * sales or purchases, but they join every debt total, the debtors ageing and a customer's credit balance.
 */
final class OpeningDebts
{
    public const RECEIVABLE = 'receivable';

    public const PAYABLE = 'payable';

    public static function active(): bool
    {
        return Schema::hasTable('inventory_opening_debts');
    }

    /** What is still unpaid, of one kind. */
    public static function outstanding(string $kind): float
    {
        if (!self::active()) {
            return 0.0;
        }

        return round((float) DB::table('inventory_opening_debts')->where('kind', $kind)->sum(DB::raw('amount - paid_amount')), 2);
    }

    /** What one customer still owes from before the app. */
    public static function customerOwes(int $customerId): float
    {
        if (!self::active()) {
            return 0.0;
        }

        return round((float) DB::table('inventory_opening_debts')->where('kind', self::RECEIVABLE)->where('customer_id', $customerId)->sum(DB::raw('amount - paid_amount')), 2);
    }

    /**
     * The debts of one kind, unpaid ones first, each with what is left and how late it is.
     *
     * @return Collection<int, array<string, mixed>>
     */
    public static function list(string $kind, bool $includePaid = false): Collection
    {
        if (!self::active()) {
            return collect();
        }
        $today = Carbon::now('Africa/Dar_es_Salaam')->startOfDay();

        return DB::table('inventory_opening_debts')->where('kind', $kind)
            ->when(!$includePaid, fn ($q) => $q->whereRaw('amount - paid_amount > 0'))
            ->orderByRaw('CASE WHEN amount - paid_amount > 0 THEN 0 ELSE 1 END')->orderBy('started_on')->orderBy('id')
            ->get()
            ->map(function ($d) use ($today) {
                $left = round((float) $d->amount - (float) $d->paid_amount, 2);
                $due = $d->due_on === null ? null : Carbon::parse($d->due_on, 'Africa/Dar_es_Salaam')->startOfDay();

                return [
                    'id' => (int) $d->id,
                    'kind' => $d->kind,
                    'customer_id' => $d->customer_id === null ? null : (int) $d->customer_id,
                    'supplier_id' => $d->supplier_id === null ? null : (int) $d->supplier_id,
                    'name' => $d->party_name,
                    'phone' => $d->party_phone,
                    'amount' => (float) $d->amount,
                    'paid' => (float) $d->paid_amount,
                    'left' => $left,
                    'started_on' => (string) $d->started_on,
                    'due_on' => $d->due_on === null ? null : (string) $d->due_on,
                    'days_late' => $left > 0 && $due !== null && $due->lt($today) ? (int) $due->diffInDays($today) : 0,
                    'note' => $d->note,
                ];
            })->values();
    }

    /**
     * Write one old debt down. A customer's debt is tied to a real customer: the one named by `customer_id`, or the one
     * found by the phone number (written any way) or the name, or a new one. A payable one may name a supplier.
     *
     * @param  array<string, mixed>  $d
     */
    public static function add(string $kind, array $d, ?string $userId): int
    {
        $name = trim((string) ($d['name'] ?? ''));
        $phone = trim((string) ($d['phone'] ?? ''));
        $customerId = null;
        $supplierId = null;

        if ($kind === self::RECEIVABLE) {
            if (!empty($d['customer_id'])) {
                $c = DB::table('inventory_customers')->where('id', (int) $d['customer_id'])->first(['id', 'name', 'phone']);
                if ($c === null) {
                    throw ValidationException::withMessages(['customer_id' => ['Mteja huyo hayupo. / That customer does not exist.']]);
                }
                $customerId = (int) $c->id;
                $name = $name !== '' ? $name : (string) $c->name;
                $phone = $phone !== '' ? $phone : (string) $c->phone;
            } else {
                if ($name === '') {
                    throw ValidationException::withMessages(['name' => ['Andika jina la mdaiwa. / Write the debtor\'s name.']]);
                }
                $customerId = self::findOrCreateCustomer($name, $phone);
            }
        } else {
            if (!empty($d['supplier_id'])) {
                $s = DB::table('inventory_suppliers')->where('id', (int) $d['supplier_id'])->first(['id', 'name', 'phone']);
                if ($s === null) {
                    throw ValidationException::withMessages(['supplier_id' => ['Msambazaji huyo hayupo. / That supplier does not exist.']]);
                }
                $supplierId = (int) $s->id;
                $name = $name !== '' ? $name : (string) $s->name;
                $phone = $phone !== '' ? $phone : (string) ($s->phone ?? '');
            } elseif ($name === '') {
                throw ValidationException::withMessages(['name' => ['Andika unayemdai. / Write who you owe.']]);
            }
        }

        return (int) DB::table('inventory_opening_debts')->insertGetId([
            'kind' => $kind,
            'customer_id' => $customerId,
            'supplier_id' => $supplierId,
            'party_name' => mb_substr($name, 0, 160),
            'party_phone' => $phone === '' ? null : mb_substr($phone, 0, 40),
            'amount' => round((float) $d['amount'], 2),
            'paid_amount' => 0,
            'started_on' => $d['started_on'] ?? Carbon::now('Africa/Dar_es_Salaam')->toDateString(),
            'due_on' => $d['due_on'] ?? null,
            'note' => isset($d['note']) && trim((string) $d['note']) !== '' ? mb_substr(trim((string) $d['note']), 0, 255) : null,
            'created_by' => $userId,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    /** Take a payment (all or part) against an old debt. Never more than what is left. */
    public static function pay(int $id, float $amount, ?string $method, ?string $paidOn, ?string $note, ?string $userId): array
    {
        $debt = DB::table('inventory_opening_debts')->where('id', $id)->first();
        if ($debt === null) {
            abort(404, 'Not found');
        }
        $left = round((float) $debt->amount - (float) $debt->paid_amount, 2);
        if ($amount <= 0 || $amount > $left + 0.001) {
            throw ValidationException::withMessages(['amount' => ["Kiasi lazima kiwe kati ya 1 na {$left}. / The amount must be between 1 and {$left}."]]);
        }

        DB::transaction(function () use ($id, $amount, $method, $paidOn, $note, $userId) {
            DB::table('inventory_opening_payments')->insert([
                'debt_id' => $id,
                'amount' => round($amount, 2),
                'method' => $method,
                'paid_on' => $paidOn ?: Carbon::now('Africa/Dar_es_Salaam')->toDateString(),
                'note' => $note !== null && trim($note) !== '' ? mb_substr(trim($note), 0, 255) : null,
                'created_by' => $userId,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            DB::table('inventory_opening_debts')->where('id', $id)->increment('paid_amount', round($amount, 2), ['updated_at' => now()]);
        });

        return ['left' => round($left - $amount, 2)];
    }

    /** A debt nobody has paid anything on may be removed (a wrong entry); one with payments stays, as a record. */
    public static function delete(int $id): void
    {
        $debt = DB::table('inventory_opening_debts')->where('id', $id)->first();
        if ($debt === null) {
            abort(404, 'Not found');
        }
        if ((float) $debt->paid_amount > 0) {
            throw ValidationException::withMessages(['id' => ['Deni lenye malipo haliwezi kufutwa. / A debt that has payments cannot be deleted.']]);
        }
        DB::table('inventory_opening_debts')->where('id', $id)->delete();
    }

    private static function findOrCreateCustomer(string $name, string $phone): int
    {
        if ($phone !== '') {
            $id = DB::table('inventory_customers')->whereIn('phone', SalonClientFromSale::spellings($phone))->orderBy('id')->value('id');
        } else {
            $id = DB::table('inventory_customers')->whereRaw('LOWER(name) = ?', [mb_strtolower($name)])->where(fn ($q) => $q->whereNull('phone')->orWhere('phone', ''))->orderBy('id')->value('id');
        }
        if ($id !== null) {
            return (int) $id;
        }

        return (int) DB::table('inventory_customers')->insertGetId(['name' => $name, 'phone' => $phone, 'created_at' => now(), 'updated_at' => now()]);
    }
}
