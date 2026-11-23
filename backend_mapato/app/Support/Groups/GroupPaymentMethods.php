<?php

namespace App\Support\Groups;

use Illuminate\Support\Facades\DB;

/**
 * The payment methods a group authorises, and where members pay for each. The Mwenyekiti (or the Makamu) chooses them; a row exists only for a
 * method that is authorised. While no method is chosen the group is unconfigured and every method is accepted (as before); once one is chosen,
 * money is recorded only by the methods chosen -- members paying in, and the group paying out.
 */
final class GroupPaymentMethods
{
    /** What can be authorised, in the order they are offered. Cash needs no number; the rest do. */
    public const CHOICES = ['bank_transfer', 'mpesa', 'mixx', 'halopesa', 'airtel_money', 'cash'];

    /** @return array<int, object> the authorised methods, in order */
    public static function active(): array
    {
        return DB::table('group_payment_methods')->orderBy('sort')->orderBy('id')->get()->all();
    }

    public static function configured(): bool
    {
        return DB::table('group_payment_methods')->exists();
    }

    /** May money be recorded by [method]? Anything goes until the group has chosen its methods. */
    public static function permits(string $method): bool
    {
        return !self::configured() || DB::table('group_payment_methods')->where('method', $method)->exists();
    }

    /** @return array<int, array<string, mixed>> what the app shows: the method and where to pay */
    public static function payload(): array
    {
        return array_map(fn ($m) => [
            'method' => $m->method, 'number' => $m->number, 'account_name' => $m->account_name, 'bank_name' => $m->bank_name,
        ], self::active());
    }
}
