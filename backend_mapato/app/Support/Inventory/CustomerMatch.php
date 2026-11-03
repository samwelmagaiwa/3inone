<?php

namespace App\Support\Inventory;

use App\Support\Salon\SalonClientFromSale;
use Illuminate\Support\Facades\DB;

/**
 * Is this the same customer as one already saved? One answer for every place that can create a customer (the customers screen, an old
 * debt, a sale, the salon), so the same person is not saved twice just because it was typed with a different capital letter, a space
 * or a different way of writing the phone number.
 *
 * The same person: the same name (however written), or the same phone number (however written). A customer is saved once: typing a
 * name or a number that is already saved gives the customer who is there, never a second card.
 */
final class CustomerMatch
{
    /** A name as it is compared: no capitals, no extra spaces. "  Mama   CHALE " and "mama chale" are the same. */
    public static function name(string $name): string
    {
        return mb_strtolower(trim(preg_replace('/\s+/u', ' ', $name) ?? $name));
    }

    /** The part of a phone number that identifies it (its last 9 digits): 0743519104, 743519104 and +255743519104 are one number. '' when too short. */
    public static function phoneKey(?string $phone): string
    {
        $digits = preg_replace('/\D/', '', (string) $phone) ?? '';

        return strlen($digits) >= 9 ? substr($digits, -9) : '';
    }

    /**
     * The customer already saved for this name or this phone number, or null: the same name (however it is written) is the same
     * customer, and so is the same phone number (however it is written). One customer, one record, one card in every list.
     * When the saved one has no number and one was typed, it takes the number. $by says which of the two matched.
     */
    public static function find(string $name, string $phone, ?string &$by = null): ?int
    {
        $name = trim($name);
        $phone = trim($phone);

        if ($phone !== '') {
            $id = DB::table('inventory_customers')->whereIn('phone', SalonClientFromSale::spellings($phone))->orderBy('id')->value('id');
            if ($id !== null) {
                $by = 'phone';

                return (int) $id;
            }
        }

        $wanted = self::name($name);
        if ($wanted === '') {
            return null;
        }
        $named = DB::table('inventory_customers')->whereRaw('LOWER(TRIM(name)) = ?', [mb_strtolower($name)])->orderBy('id')->get(['id', 'name', 'phone']);
        $first = $named->first(fn ($c) => self::name((string) $c->name) === $wanted);
        if ($first === null) {
            return null;
        }
        if ($phone !== '' && trim((string) $first->phone) === '') {
            DB::table('inventory_customers')->where('id', $first->id)->update(['phone' => $phone, 'updated_at' => now()]);
        }
        $by = 'name';

        return (int) $first->id;
    }

    /** Is another customer (not [$exceptId]) already saved with this name or phone? Used when a customer is edited. */
    public static function takenBy(string $name, string $phone, int $exceptId): ?object
    {
        $phone = trim($phone);
        if ($phone !== '') {
            $row = DB::table('inventory_customers')->where('id', '!=', $exceptId)->whereIn('phone', SalonClientFromSale::spellings($phone))->orderBy('id')->first(['id', 'name', 'phone']);
            if ($row !== null) {
                return $row;
            }
        }
        $wanted = self::name($name);
        if ($wanted === '') {
            return null;
        }

        return DB::table('inventory_customers')->where('id', '!=', $exceptId)->whereRaw('LOWER(TRIM(name)) = ?', [mb_strtolower(trim($name))])->orderBy('id')->get(['id', 'name', 'phone'])
            ->first(fn ($c) => self::name((string) $c->name) === $wanted);
    }

    public static function findOrCreate(string $name, string $phone, ?string $address = null): int
    {
        $id = self::find($name, $phone);
        if ($id !== null) {
            return $id;
        }

        return (int) DB::table('inventory_customers')->insertGetId([
            'name' => trim($name),
            'phone' => trim($phone),
            'address' => $address,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    /**
     * Customers that look like one person saved more than once: the same name, or the same phone number. Each group lists its customers
     * with what they owe and how many sales they have, so the one to keep is easy to choose.
     *
     * @return list<array{customers: list<array<string, mixed>>}>
     */
    public static function duplicateGroups(): array
    {
        $all = DB::table('inventory_customers')->orderBy('id')->get(['id', 'name', 'phone', 'address', 'created_at']);
        if ($all->count() < 2) {
            return [];
        }

        // join customers that share a name or a number (a tiny union-find)
        $parent = [];
        $find = function (int $x) use (&$parent, &$find): int {
            return $parent[$x] === $x ? $x : ($parent[$x] = $find($parent[$x]));
        };
        foreach ($all as $c) {
            $parent[(int) $c->id] = (int) $c->id;
        }
        $seen = [];
        foreach ($all as $c) {
            foreach (array_filter([self::name((string) $c->name) !== '' ? 'n:' . self::name((string) $c->name) : '', self::phoneKey($c->phone) !== '' ? 'p:' . self::phoneKey($c->phone) : '']) as $key) {
                if (isset($seen[$key])) {
                    $parent[$find((int) $c->id)] = $find($seen[$key]);
                } else {
                    $seen[$key] = (int) $c->id;
                }
            }
        }
        $groups = [];
        foreach ($all as $c) {
            $groups[$find((int) $c->id)][] = $c;
        }
        $groups = array_values(array_filter($groups, fn ($g) => count($g) > 1));
        if ($groups === []) {
            return [];
        }

        $ids = collect($groups)->flatten(1)->pluck('id')->all();
        $salesCount = DB::table('inventory_sales')->whereIn('customer_id', $ids)->whereNull('cancelled_at')->groupBy('customer_id')->pluck(DB::raw('COUNT(*)'), 'customer_id');
        $owed = DB::table('inventory_sales')->whereIn('customer_id', $ids)->whereNull('cancelled_at')->whereIn('payment_status', ['debt', 'partial'])
            ->groupBy('customer_id')->pluck(DB::raw('SUM(total - paid_total)'), 'customer_id');

        return array_map(fn (array $g) => ['customers' => array_map(fn ($c) => [
            'id' => (int) $c->id,
            'name' => (string) $c->name,
            'phone' => (string) ($c->phone ?? ''),
            'sales' => (int) ($salesCount[$c->id] ?? 0),
            'owes' => round((float) ($owed[$c->id] ?? 0) + OpeningDebts::customerOwes((int) $c->id), 2),
        ], $g)], $groups);
    }
}
