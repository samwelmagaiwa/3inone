<?php

namespace App\Support;

/**
 * How a payment was made. The stored `method` stays one of the three the whole system has always known (cash,
 * mobile money, bank transfer: reports and the cash drawer read it); the particular channel (M-Pesa, Mixx by Yas,
 * Airtel Money, HaloPesa) is kept beside it in `method_extended`. A caller may send either; this turns it into the two.
 */
final class PaymentChannels
{
    /** channel => the method it counts as */
    public const MOBILE = [
        'mpesa' => 'mobile_money',
        'mixx' => 'mobile_money',
        'airtel_money' => 'mobile_money',
        'halopesa' => 'mobile_money',
    ];

    public const METHODS = ['cash', 'mobile_money', 'bank_transfer'];

    /** @return string[] everything a payment may be called */
    public static function all(): array
    {
        return array_merge(self::METHODS, array_keys(self::MOBILE));
    }

    /** @return array{0: string, 1: ?string} the stored method, and the channel when it is a particular one */
    public static function split(?string $name): array
    {
        $name = $name === null || $name === '' ? 'cash' : $name;

        return isset(self::MOBILE[$name]) ? [self::MOBILE[$name], $name] : [$name, null];
    }
}
