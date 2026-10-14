<?php

namespace App\Http\Controllers\API;

use App\Helpers\ResponseHelper;
use App\Http\Controllers\Controller;
use App\Models\PlanPrice;
use App\Services\Inventory\AuditTrail;
use App\Support\PlanCatalog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * What each plan costs.
 *
 *   Anybody       GET /plans               the plans, how many services each covers and their prices (the
 *                                          registration form shows it before the person has an account)
 *   Super admin   GET /admin/plan-prices   the same, for the page where the prices are set
 *                 PUT /admin/plan-prices   set or clear prices; the registration form shows them at once
 *
 * A plan is a number of services (basic one, standard two, premium all three): that is a rule of the product, not
 * something set here. What is set here is the price of each plan for 1, 3, 6 and 12 months.
 */
class PlanPriceController extends Controller
{
    public function __construct(private readonly AuditTrail $audit)
    {
    }

    public function publicIndex(): JsonResponse
    {
        return ResponseHelper::success(PlanCatalog::publicList());
    }

    public function adminIndex(): JsonResponse
    {
        return ResponseHelper::success($this->payload());
    }

    public function adminUpdate(Request $request): JsonResponse
    {
        $request->validate(['prices' => 'required|array']);

        /** @var array<string, array<int|string, mixed>> $given */
        $given = (array) $request->input('prices', []);
        $periods = PlanCatalog::periods();
        $changes = [];

        foreach ($given as $plan => $byMonths) {
            if (!in_array($plan, PlanCatalog::sellable(), true) || !is_array($byMonths)) {
                return $this->problem("Mpango \"{$plan}\" haupo. / There is no plan \"{$plan}\".");
            }
            foreach ($byMonths as $months => $amount) {
                if (!in_array((int) $months, $periods, true)) {
                    return $this->problem("Muda wa miezi {$months} hauruhusiwi. / A period of {$months} months is not offered.");
                }
                $blank = $amount === null || (is_string($amount) && trim($amount) === '');
                if (!$blank && (!is_numeric($amount) || (float) $amount <= 0 || (float) $amount > 99999999999)) {
                    return $this->problem(
                        'Bei lazima iwe namba kubwa kuliko sifuri, au iachwe wazi. / A price must be a number above zero, or left empty.'
                    );
                }
                $changes[] = [$plan, (int) $months, $blank ? null : round((float) $amount, 2)];
            }
        }

        $before = PlanCatalog::prices();

        DB::transaction(function () use ($changes, $request) {
            foreach ($changes as [$plan, $months, $amount]) {
                if ($amount === null) {
                    PlanPrice::query()->where('plan', $plan)->where('months', $months)->delete();
                } else {
                    PlanPrice::query()->updateOrCreate(
                        ['plan' => $plan, 'months' => $months],
                        ['amount' => $amount, 'updated_by' => $request->user()->id]
                    );
                }
            }
        });

        $after = PlanCatalog::prices();
        $moved = [];
        $was = [];
        $now = [];
        foreach ($after as $plan => $byMonths) {
            foreach ($byMonths as $months => $amount) {
                if (($before[$plan][$months] ?? null) !== $amount) {
                    $was["{$plan}.{$months}m"] = $before[$plan][$months] ?? null;
                    $now["{$plan}.{$months}m"] = $amount;
                    $moved[] = ucfirst($plan) . " {$months}m " . ($amount === null ? 'cleared' : number_format($amount));
                }
            }
        }
        if ($moved !== []) {
            $this->audit->record($request, 'plan_prices', null, 'plan_prices_changed', $was, $now, "{$request->user()->name} changed plan prices: " . implode(', ', $moved));
        }

        return ResponseHelper::success($this->payload(), 'Prices saved');
    }

    /** @return array<string, mixed> */
    private function payload(): array
    {
        $updated = PlanPrice::query()->max('updated_at');

        return PlanCatalog::publicList() + ['updated_at' => $updated ? \Illuminate\Support\Carbon::parse($updated)->toIso8601String() : null];
    }

    private function problem(string $message): JsonResponse
    {
        return ResponseHelper::error($message, 422, ['code' => 'price_invalid']);
    }
}
