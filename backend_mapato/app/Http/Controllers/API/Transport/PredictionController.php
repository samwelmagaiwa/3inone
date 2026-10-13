<?php

namespace App\Http\Controllers\API\Transport;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use App\Models\Driver;
use App\Models\DriverAgreement;
use App\Models\Payment;
use Carbon\Carbon;
use Illuminate\Support\Collection;
use OpenApi\Attributes as OA;

#[OA\Tag(name: 'Transport / Predictions', description: 'Regression-based forecast of when a driver will finish paying off their agreement.')]
class PredictionController extends Controller
{
    /**
     * Driver prediction endpoint.
     * Returns totals, agreement meta, and a simple predicted completion date.
     */
    #[OA\Get(
        path: '/admin/drivers/{driverId}/prediction',
        summary: 'Predict when a driver will finish paying off their agreement',
        description: 'Fits a regression (or EWMA/average fallback) over the driver\'s payment '
            . 'history to estimate a completion date and whether they\'re on track.',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Predictions'],
        parameters: [
            new OA\Parameter(name: 'days', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'max_points', in: 'query', schema: new OA\Schema(type: 'string', default: '0')),
            new OA\Parameter(name: 'driverId', in: 'path', required: true, schema: new OA\Schema(type: 'string', format: 'uuid')),
            new OA\Parameter(name: 'mode', in: 'query', schema: new OA\Schema(type: 'string', enum: ['auto', 'regression', 'average'], default: 'auto')),
            new OA\Parameter(name: 'from', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
            new OA\Parameter(name: 'to', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Prediction payload', content: new OA\JsonContent(properties: [
                new OA\Property(property: 'success', type: 'boolean'),
                new OA\Property(property: 'data', properties: [
                    new OA\Property(property: 'total_paid', type: 'number'),
                    new OA\Property(property: 'total_amount', type: 'number', nullable: true),
                    new OA\Property(property: 'predicted_date', type: 'string', format: 'date', nullable: true),
                    new OA\Property(property: 'on_track', type: 'boolean', nullable: true),
                    new OA\Property(property: 'estimated_delay_days', type: 'integer', nullable: true),
                    new OA\Property(property: 'payment_history', type: 'array', items: new OA\Items(properties: [
                        new OA\Property(property: 'date', type: 'string', format: 'date'),
                        new OA\Property(property: 'amount', type: 'number'),
                    ], type: 'object')),
                ], type: 'object'),
            ], type: 'object')),
        ],
    )]
    public function getDriverPrediction(string $driverId, Request $request): JsonResponse
    {
        try {
            // Accept drivers.id or users.id (the driver list hands the app a user
            // id) and resolve to the canonical driver. Driver is account-scoped,
            // so one outside the caller's account is "not found", not an empty
            // prediction.
            $driver = Driver::where('id', $driverId)->orWhere('user_id', $driverId)->first();
            if (!$driver) {
                return response()->json(['success' => false, 'message' => 'Driver not found'], 404);
            }
            $driverId = $driver->id;

            $mode = strtolower($request->query('mode', 'auto'));
            // Optional history window: from/to (YYYY-MM-DD) or days (int, defaults to 365)
            $fromParam = $request->query('from');
            $toParam = $request->query('to');
            $daysParam = $request->query('days');
            $fromDate = null; $toDate = null;
            if (!empty($fromParam)) { $fromDate = Carbon::parse($fromParam)->startOfDay(); }
            if (!empty($toParam)) { $toDate = Carbon::parse($toParam)->endOfDay(); }
            if (!$fromDate && !$toDate && is_numeric($daysParam)) {
                $d = max(1, (int) $daysParam);
                $toDate = Carbon::today()->endOfDay();
                $fromDate = Carbon::today()->subDays($d - 1)->startOfDay();
            }

            $agreement = DriverAgreement::where('driver_id', $driverId)
                ->where('status', 'active')
                ->first();

            // Sum of payments made by driver (completed/recorded payments)
            $totalPaid = (float) Payment::where('driver_id', $driverId)->sum('amount');

            // Agreement meta
            $startDate = $agreement?->start_date ? Carbon::parse($agreement->start_date) : null;
            $endDate = $agreement?->end_date ? Carbon::parse($agreement->end_date) : null;
            $totalAmount = $agreement?->faida_jumla !== null ? (float) $agreement->faida_jumla : null;
            $weekendsCountable = $agreement?->wikendi_zinahesabika ?? true;
            $satIncluded = $agreement?->jumamosi ?? true;
            $sunIncluded = $agreement?->jumapili ?? true;

            // Compute prediction if we have enough info
            $predictedDate = null;
            $onTrack = null;
            $estimatedDelayDays = null;
            $methodUsed = null;
            $r2 = null;

            // Build per-day sums for regression/average and for returning history
            $perDay = $this->getPerDayPayments($driverId, $fromDate, $toDate, (int) $request->query('max_points', 0));

            if ($startDate && $totalAmount !== null && $totalAmount > 0) {
                $today = Carbon::today();
                $remaining = max($totalAmount - $totalPaid, 0);

                if ($mode === 'regression' || $mode === 'auto') {
                    [$valid, $slope, $intercept, $r2val, $needDays] = $this->fitRegressionAndNeed($perDay, $startDate->copy(), $remaining, $weekendsCountable, $satIncluded, $sunIncluded);
                    if ($valid && $needDays !== null) {
                        $predictedDate = $this->addIncludedDays($today->copy(), $needDays, $weekendsCountable, $satIncluded, $sunIncluded);
                        $methodUsed = 'regression';
                        $r2 = $r2val;
                    } elseif ($mode === 'regression') {
                        // fallback to average if regression not valid
                        [$predictedDate, $methodUsed] = $this->predictUsingAverage($startDate->copy(), $today->copy(), $totalPaid, $remaining, $weekendsCountable, $satIncluded, $sunIncluded);
                    }
                }

                if ($predictedDate === null) {
                    // mode=average or auto fallback
                    [$predictedDate, $methodUsed] = $this->predictUsingAverage($startDate->copy(), $today->copy(), $totalPaid, $remaining, $weekendsCountable, $satIncluded, $sunIncluded);
                }

                if ($endDate && $predictedDate) {
                    $onTrack = !$predictedDate->gt($endDate);
                    $estimatedDelayDays = $onTrack ? 0 : $predictedDate->diffInDays($endDate, false) * -1;
                } else {
                    $onTrack = true;
                    $estimatedDelayDays = 0;
                }
            }

            $data = [
                'driver_id' => $driverId,
                'total_paid' => $totalPaid,
                'total_amount' => $totalAmount,
                'start_date' => $startDate?->toDateString(),
                'contract_end' => $endDate?->toDateString(),
                'weekends_countable' => (bool) $weekendsCountable,
                'saturday_included' => (bool) $satIncluded,
                'sunday_included' => (bool) $sunIncluded,
                'predicted_date' => $predictedDate?->toDateString(),
                'on_track' => $onTrack,
                'estimated_delay_days' => $estimatedDelayDays,
                'method_used' => $methodUsed,
                'r2' => $r2,
                // Keep empty; client builds detailed series from /payments/history
                'payment_history' => $this->toHistoryList($perDay),
                'history_from' => $fromDate?->toDateString(),
                'history_to' => $toDate?->toDateString(),
            ];

            return response()->json([
                'success' => true,
                'data' => $data,
                'message' => 'Driver prediction data',
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Error generating prediction data: ' . $e->getMessage(),
            ], 500);
        }
    }

    private function isIncluded(Carbon $d, bool $weekendsCountable, bool $satIncluded, bool $sunIncluded): bool
    {
        if (!$weekendsCountable) {
            return !($d->isSaturday() || $d->isSunday());
        }
        if ($d->isSaturday() && !$satIncluded) return false;
        if ($d->isSunday() && !$sunIncluded) return false;
        return true;
    }

    private function countIncludedDays(Carbon $start, Carbon $end, bool $weekendsCountable, bool $satIncluded, bool $sunIncluded): int
    {
        if ($end->lt($start)) { [$start, $end] = [$end, $start]; }
        $count = 0; $d = $start->copy();
        while ($d->lte($end)) {
            if ($this->isIncluded($d, $weekendsCountable, $satIncluded, $sunIncluded)) $count++;
            $d->addDay();
        }
        return $count > 0 ? $count : 1;
    }

    private function addIncludedDays(Carbon $from, int $need, bool $weekendsCountable, bool $satIncluded, bool $sunIncluded): Carbon
    {
        $d = $from->copy(); $added = 0;
        while ($added < $need) {
            $d->addDay();
            if ($this->isIncluded($d, $weekendsCountable, $satIncluded, $sunIncluded)) $added++;
        }
        return $d;
    }

    private function getPerDayPayments(string $driverId, ?Carbon $from = null, ?Carbon $to = null, int $maxPoints = 0): array
    {
        $query = Payment::selectRaw("DATE(COALESCE(payment_date, created_at)) as day, SUM(amount) as total")
            ->where('driver_id', $driverId);

        if ($from) {
            $query->whereRaw("DATE(COALESCE(payment_date, created_at)) >= ?", [$from->toDateString()]);
        }
        if ($to) {
            $query->whereRaw("DATE(COALESCE(payment_date, created_at)) <= ?", [$to->toDateString()]);
        }

        $query->groupBy('day')->orderBy('day');
        if ($maxPoints > 0) {
            $query->limit($maxPoints);
        }

        $rows = $query->get();
        $perDay = [];
        foreach ($rows as $r) {
            $day = Carbon::parse($r->day)->toDateString();
            $perDay[$day] = (float) $r->total;
        }
        return $perDay;
    }

    private function toHistoryList(array $perDay): array
    {
        ksort($perDay);
        $list = [];
        foreach ($perDay as $day => $amt) {
            $list[] = [ 'date' => $day, 'amount' => $amt ];
        }
        return $list;
    }

    /**
     * Linear regression of cumulative paid (y) vs included day index (x), then compute needed included days.
     * Returns [valid(bool), slope, intercept, r2, needDays(int|null)].
     */
    private function fitRegressionAndNeed(array $perDay, Carbon $start, float $remaining, bool $weekendsCountable, bool $satIncluded, bool $sunIncluded): array
    {
        if (empty($perDay) || $remaining <= 0) {
            return [false, 0, 0, null, null];
        }
        ksort($perDay);
        $running = 0.0;
        $xs = []; $ys = [];
        foreach ($perDay as $dayStr => $amt) {
            $running += (float) $amt;
            $d = Carbon::parse($dayStr);
            $x = $this->countIncludedDays($start->copy(), $d->copy(), $weekendsCountable, $satIncluded, $sunIncluded);
            $xs[] = (float) $x;
            $ys[] = $running;
        }
        $n = count($xs);
        if ($n < 2) return [false, 0, 0, null, null];

        $sumx = 0; $sumy = 0; $sumxy = 0; $sumx2 = 0;
        for ($i = 0; $i < $n; $i++) {
            $sumx += $xs[$i];
            $sumy += $ys[$i];
            $sumxy += $xs[$i] * $ys[$i];
            $sumx2 += $xs[$i] * $xs[$i];
        }
        $den = ($n * $sumx2) - ($sumx * $sumx);
        if (abs($den) < 1e-6) return [false, 0, 0, null, null];
        $a = (($n * $sumxy) - ($sumx * $sumy)) / $den; // slope per included day
        $b = ($sumy / $n) - $a * ($sumx / $n);
        if ($a <= 0) return [false, $a, $b, null, null];

        // R^2
        $ssTot = 0; $ssRes = 0; $yMean = $sumy / $n;
        for ($i = 0; $i < $n; $i++) {
            $yHat = $a * $xs[$i] + $b;
            $ssRes += pow($ys[$i] - $yHat, 2);
            $ssTot += pow($ys[$i] - $yMean, 2);
        }
        $r2 = abs($ssTot) < 1e-6 ? 0 : 1 - ($ssRes / $ssTot);

        // Required included days from now
        $xStar = ($remaining + 0 /* cumulative so far is folded into remaining */ + $sumy - $b) / $a; // solve for total x to reach total_amount
        // But since remaining excludes what was paid, compute need as ceil(xStar - xNow)
        $xNow = $this->countIncludedDays($start->copy(), Carbon::today(), $weekendsCountable, $satIncluded, $sunIncluded);
        if (!is_finite($xStar)) return [false, $a, $b, $r2, null];
        if ($xStar < $xNow) $xStar = (float) $xNow;
        $need = max(0, (int) ceil($xStar - $xNow));

        // In auto mode client used r2 >= 0.6; we'll accept this and expose r2
        $valid = $r2 >= 0.6;
        return [$valid, $a, $b, $r2, $need];
    }

    /**
     * Average-per-included-day fallback or requested mode.
     */
    private function predictUsingAverage(Carbon $start, Carbon $today, float $totalPaid, float $remaining, bool $weekendsCountable, bool $satIncluded, bool $sunIncluded): array
    {
        $includedDays = $this->countIncludedDays($start->copy(), $today->copy(), $weekendsCountable, $satIncluded, $sunIncluded);
        $includedDays = max(1, $includedDays);
        $rate = $totalPaid / $includedDays;
        if ($rate > 0 && $remaining > 0) {
            $need = (int) ceil($remaining / $rate);
            $pred = $this->addIncludedDays($today->copy(), $need, $weekendsCountable, $satIncluded, $sunIncluded);
            return [$pred, 'average'];
        }
        return [$today->copy(), 'average'];
    }
}
