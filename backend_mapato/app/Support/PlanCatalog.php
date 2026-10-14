<?php

namespace App\Support;

use App\Models\PlanPrice;

/**
 * The plans that are sold, how many services each one covers, and what each costs.
 *
 *   basic    one service
 *   standard two services
 *   premium  all three services
 *
 * `trial` and `free` are not sold and have no limit: they are what a business is on before it pays, or what it was
 * given by hand. The prices are the super admin's to set (the plan_prices table); the number of services a plan
 * covers is a rule of the product (config/billing.php), not something to edit per customer.
 */
class PlanCatalog
{
    /** @return array<int, string> the plans that can be bought, smallest first */
    public static function sellable(): array
    {
        return array_keys(self::limits());
    }

    /** @return array<string, int> plan => services it covers */
    public static function limits(): array
    {
        $limits = (array) config('billing.plan_services', ['basic' => 1, 'standard' => 2, 'premium' => 3]);
        asort($limits);

        return array_map('intval', $limits);
    }

    /** How many services a plan covers, or null when it has no limit (trial, free, anything unsold). */
    public static function servicesIncluded(string $plan): ?int
    {
        return self::limits()[$plan] ?? null;
    }

    /** Is a business with [$serviceCount] services within [$plan]? A plan without a limit covers any number. */
    public static function covers(string $plan, int $serviceCount): bool
    {
        $included = self::servicesIncluded($plan);

        return $included === null || $serviceCount <= $included;
    }

    /** The smallest plan that covers [$serviceCount] services (the biggest one when it is more than any covers). */
    public static function planFor(int $serviceCount): string
    {
        foreach (self::limits() as $plan => $included) {
            if ($serviceCount <= $included) {
                return $plan;
            }
        }

        return (string) array_key_last(self::limits());
    }

    /** @return array<int, int> the lengths of time a plan can be paid for, in months */
    public static function periods(): array
    {
        return array_values(array_map('intval', (array) config('billing.price_periods', [1, 3, 6, 12])));
    }

    public static function currency(): string
    {
        return (string) config('billing.currency', 'TZS');
    }

    /**
     * @return array<string, array<int, ?float>> plan => [months => price or null when none is set]
     */
    public static function prices(): array
    {
        $stored = PlanPrice::query()->get()->groupBy('plan');
        $table = [];

        foreach (self::sellable() as $plan) {
            $byMonths = ($stored[$plan] ?? collect())->keyBy('months');
            foreach (self::periods() as $months) {
                $table[$plan][$months] = $byMonths->has($months) ? (float) $byMonths[$months]->amount : null;
            }
        }

        return $table;
    }

    public static function priceFor(string $plan, int $months): ?float
    {
        return self::prices()[$plan][$months] ?? null;
    }

    /**
     * What the apps are given: every plan with the services it covers and its prices, and the number of days of
     * free trial a new business gets. Nothing in it is secret: the registration form shows it before sign-in.
     *
     * @return array<string, mixed>
     */
    public static function publicList(): array
    {
        $prices = self::prices();
        $plans = [];

        foreach (self::limits() as $plan => $included) {
            $plans[] = [
                'plan' => $plan,
                'services_included' => $included,
                'prices' => array_map(
                    fn (int $months) => ['months' => $months, 'amount' => $prices[$plan][$months]],
                    self::periods()
                ),
            ];
        }

        return [
            'currency' => self::currency(),
            'periods' => self::periods(),
            'trial_days' => max((int) config('billing.trial_days', 30), 0),
            'total_services' => count((array) config('billing.services', ['transport', 'rental', 'inventory'])),
            'plans' => $plans,
            // False until the super admin has priced at least one plan: the form then says prices are coming.
            'configured' => collect($prices)->flatten()->filter(fn ($p) => $p !== null)->isNotEmpty(),
        ];
    }

    /** A message, in both languages, for a plan that does not cover the services chosen. */
    public static function tooSmallMessage(string $plan, int $serviceCount): string
    {
        $included = (int) (self::servicesIncluded($plan) ?? 0);
        $better = self::planFor($serviceCount);
        $name = ucfirst($plan);
        $betterName = ucfirst($better);

        $sw = $included === 1
            ? "Mpango wa {$name} ni huduma MOJA tu, na umechagua {$serviceCount}. Chagua mpango wa {$betterName} au punguza huduma."
            : "Mpango wa {$name} unahusu huduma {$included} tu, na umechagua {$serviceCount}. Chagua mpango wa {$betterName} au punguza huduma.";
        $en = $included === 1
            ? "The {$name} plan covers ONE service only, and you chose {$serviceCount}. Choose the {$betterName} plan or fewer services."
            : "The {$name} plan covers {$included} services only, and you chose {$serviceCount}. Choose the {$betterName} plan or fewer services.";

        return "{$sw} / {$en}";
    }
}
