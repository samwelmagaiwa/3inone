<?php

namespace App\Support\Inventory;

use App\Support\Salon\SalonClientFromSale;
use Illuminate\Support\Facades\DB;

/**
 * Is this the same customer as one already saved? One answer for every place that can create a customer (the customers screen, an old
 * debt, a sale, the salon), so the same person is not saved twice just because it was typed with a different capital letter, a space
 * or a different way of writing the phone number.
 *
 * The same person: the same phone number (however written) and the same name; or the same name when only one side has a number.
 * Two people who share a name but have different numbers stay two people (they can still be merged by hand if they are one).
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
     * The customer already saved for this name and phone, or null. With [$phoneAlone] the number alone is enough (an old debt is typed with
     * a short form of the name); otherwise the name must agree too.
     *
     * A saved customer with no number is given the number that was typed.
     */
    public static function find(string $name, string $phone, bool $phoneAlone = false): ?int
    {
        $name = trim($name);
        $phone = trim($phone);
        $wanted = self::name($name);

        // by number: the same number and the same name
        if ($phone !== '') {
            $byPhone = DB::table('inventory_customers')->whereIn('phone', SalonClientFromSale::spellings($phone))->orderBy('id')->get(['id', 'name']);
            foreach ($byPhone as $c) {
                if ($phoneAlone || $wanted === '' || self::name((string) $c->name) === $wanted) {
                    return (int) $c->id;
                }
            }
            if ($byPhone->isNotEmpty() && $wanted === '') {
                return (int) $byPhone->first()->id;
            }
        }

        if ($wanted === '') {
            return null;
        }

        // by name: only when there is no number to tell people apart, on one side or the other
        $named = DB::table('inventory_customers')->whereRaw('LOWER(TRIM(name)) = ?', [mb_strtolower($name)])->orderBy('id')->get(['id', 'name', 'phone']);
        $named = $named->filter(fn ($c) => self::name((string) $c->name) === $wanted)->values();
        if ($named->isEmpty()) {
            return null;
        }
        if ($phone === '') {
            // nothing typed but the name: it is the one customer with that name, when there is only one
            return $named->count() === 1 ? (int) $named->first()->id : null;
        }
        $blank = $named->first(fn ($c) => self::phoneKey($c->phone) === '' && trim((string) $c->phone) === '');
        if ($blank !== null) {
            DB::table('inventory_customers')->where('id', $blank->id)->update(['phone' => $phone, 'updated_at' => now()]);

            return (int) $blank->id;
        }

        return null;
    }

    public static function findOrCreate(string $name, string $phone, ?string $address = null, bool $phoneAlone = false): int
    {
        $id = self::find($name, $phone, $phoneAlone);
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
