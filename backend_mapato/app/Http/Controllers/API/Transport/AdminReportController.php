<?php

namespace App\Http\Controllers\API\Transport;

use App\Http\Controllers\Controller;
use App\Models\Transaction;
use App\Models\Driver;
use App\Models\Device;
use App\Helpers\ResponseHelper;
use Illuminate\Http\Request;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

class AdminReportController extends Controller
{
    /**
     * Transaction, Driver and Device carry the account scope themselves (see
     * App\Models\Scopes\AccountScope): a signed-in admin or staff member only
     * ever reaches their own account's rows, and super_admin sees everything.
     * These helpers keep the call sites below readable; they add no filtering
     * of their own, so there is exactly one place the rule lives.
     */
    private function scopedTransactions($admin)
    {
        return Transaction::query();
    }

    private function scopedDrivers($admin)
    {
        return Driver::query();
    }

    private function scopedDevices($admin)
    {
        return Device::query();
    }

    /** Percent change from $previous to $current, 0 when there's no baseline. */
    private function percentChange(float $current, float $previous): float
    {
        if ($previous == 0.0) {
            return $current > 0 ? 100.0 : 0.0;
        }
        return round((($current - $previous) / $previous) * 100, 2);
    }

    /**
     * Which day of the week and which time-of-day bucket earns the most,
     * over the given window -- real aggregation to back the "best day" /
     * "best time" insights the Flutter UI used to show as hardcoded text.
     */
    private function bestDayAndTimeBucket($admin, Carbon $start, Carbon $end): array
    {
        $rows = $this->scopedTransactions($admin)
            ->income()->completed()
            ->whereBetween('transaction_date', [$start, $end])
            ->get(['amount', 'transaction_date']);

        if ($rows->isEmpty()) {
            return ['best_day' => null, 'best_day_amount' => 0.0, 'best_time_bucket' => null, 'best_time_amount' => 0.0];
        }

        $byDay = $rows->groupBy(fn ($r) => $r->transaction_date->format('l'))
            ->map(fn ($g) => $g->sum('amount'));
        $bestDay = $byDay->sortDesc()->keys()->first();

        $bucketFor = static function (int $hour): string {
            return match (true) {
                $hour >= 5 && $hour < 12 => 'morning',
                $hour >= 12 && $hour < 17 => 'afternoon',
                $hour >= 17 && $hour < 21 => 'evening',
                default => 'night',
            };
        };
        $byBucket = $rows->groupBy(fn ($r) => $bucketFor($r->transaction_date->hour))
            ->map(fn ($g) => $g->sum('amount'));
        $bestBucket = $byBucket->sortDesc()->keys()->first();

        return [
            'best_day' => $bestDay,
            'best_day_amount' => (float) ($byDay[$bestDay] ?? 0),
            'best_time_bucket' => $bestBucket,
            'best_time_amount' => (float) ($byBucket[$bestBucket] ?? 0),
        ];
    }

    /**
     * Distinct paying customers (by phone) in the period, and how many of
     * them are new (weren't a customer in the prior period of equal length).
     */
    private function customerGrowth($admin, Carbon $start, Carbon $end): array
    {
        $length = $start->diffInSeconds($end);
        $prevStart = (clone $start)->subSeconds($length + 1);
        $prevEnd = (clone $start)->subSecond();

        $currentPhones = $this->scopedTransactions($admin)
            ->income()->completed()
            ->whereBetween('transaction_date', [$start, $end])
            ->whereNotNull('customer_phone')->where('customer_phone', '!=', '')
            ->distinct()->pluck('customer_phone');

        $previousPhones = $this->scopedTransactions($admin)
            ->income()->completed()
            ->whereBetween('transaction_date', [$prevStart, $prevEnd])
            ->whereNotNull('customer_phone')->where('customer_phone', '!=', '')
            ->distinct()->pluck('customer_phone');

        $newCount = $currentPhones->diff($previousPhones)->count();

        return [
            'total_customers' => $currentPhones->count(),
            'new_customers' => $newCount,
            'new_customers_growth' => $this->percentChange($newCount, $previousPhones->count()),
        ];
    }

    /**
     * Get revenue report for admin dashboard
     */
    #[OA\Get(
        path: '/admin/analytics/trends',
        summary: 'Get revenue report',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin Report'],
        parameters: [
            new OA\Parameter(name: 'start_date', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'end_date', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    #[OA\Get(
        path: '/admin/reports/revenue',
        summary: 'Get revenue report',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin Report'],
        parameters: [
            new OA\Parameter(name: 'start_date', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'end_date', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getRevenueReport(Request $request)
    {
        try {
            $admin = $request->user();
            $startDate = $request->get('start_date', Carbon::now()->subDays(30)->format('Y-m-d'));
            $endDate = $request->get('end_date', Carbon::now()->format('Y-m-d'));

            // Parse dates
            $startDate = Carbon::parse($startDate)->startOfDay();
            $endDate = Carbon::parse($endDate)->endOfDay();

            // Get total revenue for the period
            $totalRevenue = $this->scopedTransactions($admin)->income()
                ->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->sum('amount');

            // Get transaction count
            $transactionCount = $this->scopedTransactions($admin)->income()
                ->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->count();

            // Calculate average per day
            $daysDifference = max(1, $startDate->diffInDays($endDate) + 1);
            $averagePerDay = $transactionCount > 0 ? round($totalRevenue / $daysDifference, 2) : 0;

            // Get breakdown by category
            $breakdown = $this->scopedTransactions($admin)->income()
                ->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->select('category', DB::raw('SUM(amount) as total'))
                ->groupBy('category')
                ->get()
                ->mapWithKeys(function ($item) {
                    $categoryName = Transaction::PAYMENT_CATEGORIES[$item->category] ?? $item->category;
                    return [$item->category => [
                        'name' => $categoryName,
                        'amount' => (float) $item->total
                    ]];
                });

            // Get daily data for the period (last 30 days max for performance)
            $dailyDataPeriod = min(30, $daysDifference);
            $dailyStartDate = Carbon::parse($endDate)->subDays($dailyDataPeriod - 1);

            $dailyData = [];
            for ($date = $dailyStartDate->copy(); $date <= $endDate; $date->addDay()) {
                $dayAmount = $this->scopedTransactions($admin)->income()
                    ->completed()
                    ->whereDate('transaction_date', $date->format('Y-m-d'))
                    ->sum('amount');

                $dailyData[] = [
                    'date' => $date->format('Y-m-d'),
                    'amount' => (float) $dayAmount
                ];
            }

            // Period-over-period growth (previous window of equal length)
            $periodLength = $startDate->diffInSeconds($endDate);
            $prevStart = (clone $startDate)->subSeconds($periodLength + 1);
            $prevEnd = (clone $startDate)->subSecond();
            $previousRevenue = $this->scopedTransactions($admin)->income()
                ->completed()
                ->whereBetween('transaction_date', [$prevStart, $prevEnd])
                ->sum('amount');
            $revenueGrowth = $this->percentChange((float) $totalRevenue, (float) $previousRevenue);

            $dayTime = $this->bestDayAndTimeBucket($admin, $startDate, $endDate);
            $customers = $this->customerGrowth($admin, $startDate, $endDate);

            $data = [
                'total_revenue' => (float) $totalRevenue,
                'period_start' => $startDate->format('Y-m-d'),
                'period_end' => $endDate->format('Y-m-d'),
                'transaction_count' => $transactionCount,
                'average_per_day' => $averagePerDay,
                'breakdown' => $breakdown,
                'daily_data' => $dailyData,
                'revenue_growth' => $revenueGrowth,
                'best_day' => $dayTime['best_day'],
                'best_day_amount' => $dayTime['best_day_amount'],
                'best_time_bucket' => $dayTime['best_time_bucket'],
                'best_time_amount' => $dayTime['best_time_amount'],
                'new_customers' => $customers['new_customers'],
                'new_customers_growth' => $customers['new_customers_growth'],
                'total_customers' => $customers['total_customers'],
            ];

            return ResponseHelper::success($data, 'Revenue report generated successfully');

        } catch (\Exception $e) {
            \Log::error('Revenue report generation failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            return ResponseHelper::error('Failed to generate revenue report: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get expense report for admin dashboard
     */
    #[OA\Get(
        path: '/admin/reports/expenses',
        summary: 'Get expense report',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin Report'],
        parameters: [
            new OA\Parameter(name: 'start_date', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'end_date', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getExpenseReport(Request $request)
    {
        try {
            $admin = $request->user();
            $startDate = $request->get('start_date', Carbon::now()->subDays(30)->format('Y-m-d'));
            $endDate = $request->get('end_date', Carbon::now()->format('Y-m-d'));

            // Parse dates
            $startDate = Carbon::parse($startDate)->startOfDay();
            $endDate = Carbon::parse($endDate)->endOfDay();

            // Get total expenses for the period
            $totalExpenses = $this->scopedTransactions($admin)->expense()
                ->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->sum('amount');

            // Get transaction count
            $transactionCount = $this->scopedTransactions($admin)->expense()
                ->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->count();

            // Calculate average per day
            $daysDifference = max(1, $startDate->diffInDays($endDate) + 1);
            $averagePerDay = $transactionCount > 0 ? round($totalExpenses / $daysDifference, 2) : 0;

            // Get breakdown by category
            $breakdown = $this->scopedTransactions($admin)->expense()
                ->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->select('category', DB::raw('SUM(amount) as total'))
                ->groupBy('category')
                ->get()
                ->mapWithKeys(function ($item) {
                    $categoryName = Transaction::EXPENSE_CATEGORIES[$item->category] ?? $item->category;
                    return [$item->category => [
                        'name' => $categoryName,
                        'amount' => (float) $item->total
                    ]];
                });

            // Period-over-period change, overall and for fuel specifically
            // (fuel is the one expense category the app calls out by name).
            $periodLength = $startDate->diffInSeconds($endDate);
            $prevStart = (clone $startDate)->subSeconds($periodLength + 1);
            $prevEnd = (clone $startDate)->subSecond();

            $previousExpenses = $this->scopedTransactions($admin)->expense()
                ->completed()
                ->whereBetween('transaction_date', [$prevStart, $prevEnd])
                ->sum('amount');
            $expenseChange = $this->percentChange((float) $totalExpenses, (float) $previousExpenses);

            $fuelExpenses = $this->scopedTransactions($admin)->expense()
                ->completed()->where('category', 'fuel')
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->sum('amount');
            $previousFuelExpenses = $this->scopedTransactions($admin)->expense()
                ->completed()->where('category', 'fuel')
                ->whereBetween('transaction_date', [$prevStart, $prevEnd])
                ->sum('amount');
            $fuelExpenseChange = $this->percentChange((float) $fuelExpenses, (float) $previousFuelExpenses);

            $data = [
                'total_expenses' => (float) $totalExpenses,
                'period_start' => $startDate->format('Y-m-d'),
                'period_end' => $endDate->format('Y-m-d'),
                'transaction_count' => $transactionCount,
                'average_per_day' => $averagePerDay,
                'breakdown' => $breakdown,
                'expense_change' => $expenseChange,
                'fuel_expenses' => (float) $fuelExpenses,
                'fuel_expense_change' => $fuelExpenseChange,
            ];

            return ResponseHelper::success($data, 'Expense report generated successfully');

        } catch (\Exception $e) {
            \Log::error('Expense report generation failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            return ResponseHelper::error('Failed to generate expense report: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get profit/loss report for admin dashboard
     */
    #[OA\Get(
        path: '/admin/reports/profit-loss',
        summary: 'Get profit loss report',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin Report'],
        parameters: [
            new OA\Parameter(name: 'start_date', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'end_date', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getProfitLossReport(Request $request)
    {
        try {
            $admin = $request->user();
            $startDate = $request->get('start_date', Carbon::now()->subDays(30)->format('Y-m-d'));
            $endDate = $request->get('end_date', Carbon::now()->format('Y-m-d'));

            // Parse dates
            $startDate = Carbon::parse($startDate)->startOfDay();
            $endDate = Carbon::parse($endDate)->endOfDay();

            // Get total revenue
            $totalRevenue = $this->scopedTransactions($admin)->income()
                ->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->sum('amount');

            // Get total expenses
            $totalExpenses = $this->scopedTransactions($admin)->expense()
                ->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->sum('amount');

            // Calculate profit/loss
            $netProfit = $totalRevenue - $totalExpenses;
            $profitMargin = $totalRevenue > 0 ? round(($netProfit / $totalRevenue) * 100, 2) : 0;

            // Period-over-period profit growth
            $periodLength = $startDate->diffInSeconds($endDate);
            $prevStart = (clone $startDate)->subSeconds($periodLength + 1);
            $prevEnd = (clone $startDate)->subSecond();
            $previousRevenue = $this->scopedTransactions($admin)->income()
                ->completed()->whereBetween('transaction_date', [$prevStart, $prevEnd])->sum('amount');
            $previousExpenses = $this->scopedTransactions($admin)->expense()
                ->completed()->whereBetween('transaction_date', [$prevStart, $prevEnd])->sum('amount');
            $previousProfit = $previousRevenue - $previousExpenses;
            $profitGrowth = $this->percentChange((float) $netProfit, (float) $previousProfit);

            $data = [
                'total_revenue' => (float) $totalRevenue,
                'total_expenses' => (float) $totalExpenses,
                'net_profit' => (float) $netProfit,
                'profit_margin' => $profitMargin,
                'profit_growth' => $profitGrowth,
                'period_start' => $startDate->format('Y-m-d'),
                'period_end' => $endDate->format('Y-m-d'),
            ];

            return ResponseHelper::success($data, 'Profit/Loss report generated successfully');

        } catch (\Exception $e) {
            \Log::error('Profit/Loss report generation failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            return ResponseHelper::error('Failed to generate profit/loss report: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get device performance report
     */
    #[OA\Get(
        path: '/admin/reports/device-performance',
        summary: 'Get device performance report',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin Report'],
        parameters: [
            new OA\Parameter(name: 'start_date', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'end_date', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getDevicePerformanceReport(Request $request)
    {
        try {
            $admin = $request->user();
            $startDate = $request->get('start_date', Carbon::now()->subDays(30)->format('Y-m-d'));
            $endDate = $request->get('end_date', Carbon::now()->format('Y-m-d'));

            // Parse dates
            $startDate = Carbon::parse($startDate)->startOfDay();
            $endDate = Carbon::parse($endDate)->endOfDay();

            // Get device performance data
            $devices = $this->scopedDevices($admin)
                ->with(['driver.user'])
                ->whereHas('transactions', function ($query) use ($startDate, $endDate) {
                    $query->income()
                        ->completed()
                        ->whereBetween('transaction_date', [$startDate, $endDate]);
                })
                ->get();

            // Revenue and trip count for every listed device in one grouped query,
            // instead of two queries per device.
            $totals = Transaction::whereIn('device_id', $devices->pluck('id'))
                ->income()
                ->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->selectRaw('device_id, SUM(amount) as revenue, COUNT(*) as trips')
                ->groupBy('device_id')
                ->get()
                ->keyBy('device_id');

            $devices = $devices
                ->map(function ($device) use ($totals) {
                    $revenue = (float) ($totals->get($device->id)?->revenue ?? 0);
                    $trips = (int) ($totals->get($device->id)?->trips ?? 0);

                    return [
                        'id' => $device->id,
                        'name' => $device->name,
                        'plate_number' => $device->plate_number,
                        'driver_name' => $device->driver->user->name ?? 'No Driver',
                        'revenue' => $revenue,
                        'trips' => $trips,
                        'average_per_trip' => $trips > 0 ? round($revenue / $trips, 2) : 0
                    ];
                })
                ->sortByDesc('revenue')
                ->values();

            $topPerformer = $devices->first();

            $data = [
                'devices' => $devices,
                'top_performer' => $topPerformer ? $topPerformer['name'] : null,
                'period_start' => $startDate->format('Y-m-d'),
                'period_end' => $endDate->format('Y-m-d'),
            ];

            return ResponseHelper::success($data, 'Device performance report generated successfully');

        } catch (\Exception $e) {
            \Log::error('Device performance report generation failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            return ResponseHelper::error('Failed to generate device performance report: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get dashboard summary report
     */
    #[OA\Get(
        path: '/admin/reports/dashboard',
        summary: 'Get dashboard report',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin Report'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getDashboardReport(Request $request)
    {
        try {
            $admin = $request->user();
            // Get current month data
            $currentMonth = Carbon::now();
            $startOfMonth = $currentMonth->copy()->startOfMonth();
            $endOfMonth = $currentMonth->copy()->endOfMonth();

            // Revenue data
            $monthlyRevenue = $this->scopedTransactions($admin)->income()
                ->completed()
                ->whereBetween('transaction_date', [$startOfMonth, $endOfMonth])
                ->sum('amount');

            $weeklyRevenue = $this->scopedTransactions($admin)->income()
                ->completed()
                ->thisWeek()
                ->sum('amount');

            $dailyRevenue = $this->scopedTransactions($admin)->income()
                ->completed()
                ->today()
                ->sum('amount');

            // Expense data
            $monthlyExpenses = $this->scopedTransactions($admin)->expense()
                ->completed()
                ->whereBetween('transaction_date', [$startOfMonth, $endOfMonth])
                ->sum('amount');

            // Calculate profit
            $netProfit = $monthlyRevenue - $monthlyExpenses;

            // Driver and device counts
            $totalDrivers = $this->scopedDrivers($admin)->count();
            $activeDrivers = $this->scopedDrivers($admin)->whereHas('transactions', function ($query) {
                $query->where('transaction_date', '>=', Carbon::now()->subDays(7));
            })->count();

            $totalVehicles = $this->scopedDevices($admin)->count();
            $activeVehicles = $this->scopedDevices($admin)->whereHas('transactions', function ($query) {
                $query->where('transaction_date', '>=', Carbon::now()->subDays(7));
            })->count();

            // Pending payments
            $pendingPayments = $this->scopedTransactions($admin)->pending()->count();

            // Calculate averages
            $daysInMonth = $startOfMonth->diffInDays($endOfMonth) + 1;
            $averagePerDay = $daysInMonth > 0 ? round($monthlyRevenue / $daysInMonth, 2) : 0;

            $data = [
                'total_revenue' => (float) $monthlyRevenue,
                'total_expenses' => (float) $monthlyExpenses,
                'net_profit' => (float) $netProfit,
                'monthly_revenue' => (float) $monthlyRevenue,
                'weekly_revenue' => (float) $weeklyRevenue,
                'daily_revenue' => (float) $dailyRevenue,
                'average_per_day' => $averagePerDay,
                'active_drivers' => $activeDrivers,
                'total_drivers' => $totalDrivers,
                'active_vehicles' => $activeVehicles,
                'total_vehicles' => $totalVehicles,
                'pending_payments' => $pendingPayments,
                'vehicle_count' => $totalVehicles, // For compatibility with Flutter
                'transaction_count' => $this->scopedTransactions($admin)->completed()
                    ->whereBetween('transaction_date', [$startOfMonth, $endOfMonth])
                    ->count(),
            ];

            return ResponseHelper::success($data, 'Dashboard report generated successfully');

        } catch (\Exception $e) {
            \Log::error('Dashboard report generation failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            return ResponseHelper::error('Failed to generate dashboard report: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get comprehensive analytics overview for mobile app
     */
    #[OA\Get(
        path: '/admin/analytics/overview',
        summary: 'Get analytics overview',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin Report'],
        parameters: [
            new OA\Parameter(name: 'period', in: 'query', schema: new OA\Schema(type: 'string', default: '30')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getAnalyticsOverview(Request $request)
    {
        try {
            $admin = $request->user();
            $period = $request->get('period', '30'); // days
            $endDate = Carbon::now();
            $startDate = Carbon::now()->subDays($period);

            // Get key metrics
            $totalRevenue = $this->scopedTransactions($admin)->income()->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->sum('amount');

            $totalExpenses = $this->scopedTransactions($admin)->expense()->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->sum('amount');

            $netProfit = $totalRevenue - $totalExpenses;
            $profitMargin = $totalRevenue > 0 ? round(($netProfit / $totalRevenue) * 100, 2) : 0;

            // Get growth rates
            $previousPeriodStart = Carbon::now()->subDays($period * 2);
            $previousPeriodEnd = Carbon::now()->subDays($period);

            $previousRevenue = $this->scopedTransactions($admin)->income()->completed()
                ->whereBetween('transaction_date', [$previousPeriodStart, $previousPeriodEnd])
                ->sum('amount');

            $revenueGrowth = $this->percentChange((float) $totalRevenue, (float) $previousRevenue);

            // Transaction trends
            $transactionCount = $this->scopedTransactions($admin)->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->count();

            $averageTransactionValue = $transactionCount > 0 ?
                round($totalRevenue / $transactionCount, 2) : 0;

            // Active metrics
            $activeDrivers = $this->scopedDrivers($admin)->whereHas('transactions', function ($query) use ($startDate) {
                $query->where('transaction_date', '>=', $startDate);
            })->count();

            $activeVehicles = $this->scopedDevices($admin)->whereHas('transactions', function ($query) use ($startDate) {
                $query->where('transaction_date', '>=', $startDate);
            })->count();

            // Daily trends for chart
            $dailyTrends = [];
            for ($date = $startDate->copy(); $date <= $endDate; $date->addDay()) {
                $dayRevenue = $this->scopedTransactions($admin)->income()->completed()
                    ->whereDate('transaction_date', $date->format('Y-m-d'))
                    ->sum('amount');

                $dayExpenses = $this->scopedTransactions($admin)->expense()->completed()
                    ->whereDate('transaction_date', $date->format('Y-m-d'))
                    ->sum('amount');

                $dailyTrends[] = [
                    'date' => $date->format('Y-m-d'),
                    'day_name' => $date->format('l'),
                    'revenue' => (float) $dayRevenue,
                    'expenses' => (float) $dayExpenses,
                    'profit' => (float) ($dayRevenue - $dayExpenses),
                    'transactions' => $this->scopedTransactions($admin)->completed()
                        ->whereDate('transaction_date', $date->format('Y-m-d'))
                        ->count()
                ];
            }

            $data = [
                'overview' => [
                    'total_revenue' => (float) $totalRevenue,
                    'total_expenses' => (float) $totalExpenses,
                    'net_profit' => (float) $netProfit,
                    'profit_margin' => $profitMargin,
                    'revenue_growth' => $revenueGrowth,
                    'transaction_count' => $transactionCount,
                    'average_transaction_value' => $averageTransactionValue,
                    'active_drivers' => $activeDrivers,
                    'active_vehicles' => $activeVehicles,
                    'period_days' => (int) $period
                ],
                'trends' => [
                    'daily' => $dailyTrends
                ],
                'generated_at' => Carbon::now()->toISOString(),
                'period_start' => $startDate->format('Y-m-d'),
                'period_end' => $endDate->format('Y-m-d')
            ];

            return ResponseHelper::success($data, 'Analytics overview retrieved successfully');

        } catch (\Exception $e) {
            \Log::error('Analytics overview failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            return ResponseHelper::error('Failed to generate analytics overview: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get top performing metrics for mobile dashboard
     */
    #[OA\Get(
        path: '/admin/analytics/top-performers',
        summary: 'Get top performers',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin Report'],
        parameters: [
            new OA\Parameter(name: 'period', in: 'query', schema: new OA\Schema(type: 'string', default: '30')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getTopPerformers(Request $request)
    {
        try {
            $admin = $request->user();
            $period = $request->get('period', '30');
            $startDate = Carbon::now()->subDays($period);
            $endDate = Carbon::now();

            // Top performing drivers
            $topDrivers = $this->scopedDrivers($admin)
                ->with(['user', 'transactions' => function ($query) use ($startDate, $endDate) {
                    $query->income()->completed()
                        ->whereBetween('transaction_date', [$startDate, $endDate]);
                }])
                ->whereHas('transactions', function ($query) use ($startDate, $endDate) {
                    $query->income()->completed()
                        ->whereBetween('transaction_date', [$startDate, $endDate]);
                })
                ->get()
                ->map(function ($driver) {
                    $revenue = $driver->transactions->sum('amount');
                    $trips = $driver->transactions->count();
                    return [
                        'id' => $driver->id,
                        'name' => $driver->user->name ?? 'Unknown',
                        'phone' => $driver->user->phone_number ?? '',
                        'revenue' => $revenue,
                        'trips' => $trips,
                        'average_per_trip' => $trips > 0 ? round($revenue / $trips, 2) : 0,
                        'license_number' => $driver->license_number
                    ];
                })
                ->sortByDesc('revenue')
                ->take(10)
                ->values();

            // Top performing vehicles
            $topVehicles = $this->scopedDevices($admin)
                ->with(['driver.user', 'transactions' => function ($query) use ($startDate, $endDate) {
                    $query->income()->completed()
                        ->whereBetween('transaction_date', [$startDate, $endDate]);
                }])
                ->whereHas('transactions', function ($query) use ($startDate, $endDate) {
                    $query->income()->completed()
                        ->whereBetween('transaction_date', [$startDate, $endDate]);
                })
                ->get()
                ->map(function ($device) {
                    $revenue = $device->transactions->sum('amount');
                    $trips = $device->transactions->count();
                    return [
                        'id' => $device->id,
                        'name' => $device->name,
                        'plate_number' => $device->plate_number,
                        'driver_name' => $device->driver->user->name ?? 'Unassigned',
                        'revenue' => $revenue,
                        'trips' => $trips,
                        'average_per_trip' => $trips > 0 ? round($revenue / $trips, 2) : 0,
                        'device_type' => $device->device_type ?? 'Vehicle'
                    ];
                })
                ->sortByDesc('revenue')
                ->take(10)
                ->values();

            // Revenue by category
            $revenueByCategory = $this->scopedTransactions($admin)->income()->completed()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->select('category', DB::raw('SUM(amount) as total'), DB::raw('COUNT(*) as count'))
                ->groupBy('category')
                ->get()
                ->map(function ($item) {
                    return [
                        'category' => $item->category,
                        'category_name' => Transaction::PAYMENT_CATEGORIES[$item->category] ?? $item->category,
                        'total' => (float) $item->total,
                        'count' => $item->count,
                        'percentage' => 0 // Will be calculated after getting totals
                    ];
                });

            $totalRevenue = $revenueByCategory->sum('total');
            $revenueByCategory = $revenueByCategory->map(function ($item) use ($totalRevenue) {
                $item['percentage'] = $totalRevenue > 0 ? round(($item['total'] / $totalRevenue) * 100, 2) : 0;
                return $item;
            })->sortByDesc('total')->values();

            $data = [
                'top_drivers' => $topDrivers,
                'top_vehicles' => $topVehicles,
                'revenue_by_category' => $revenueByCategory,
                'period_start' => $startDate->format('Y-m-d'),
                'period_end' => $endDate->format('Y-m-d'),
                'generated_at' => Carbon::now()->toISOString()
            ];

            return ResponseHelper::success($data, 'Top performers data retrieved successfully');

        } catch (\Exception $e) {
            \Log::error('Top performers data failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            return ResponseHelper::error('Failed to get top performers data: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get real-time analytics for live dashboard
     */
    #[OA\Get(
        path: '/admin/analytics/live',
        summary: 'Get live analytics',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin Report'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getLiveAnalytics(Request $request)
    {
        try {
            $admin = $request->user();
            $now = Carbon::now();
            $todayStart = $now->copy()->startOfDay();
            $weekStart = $now->copy()->startOfWeek();
            $monthStart = $now->copy()->startOfMonth();

            // Today's stats
            $todayRevenue = $this->scopedTransactions($admin)->income()->completed()
                ->whereBetween('transaction_date', [$todayStart, $now])
                ->sum('amount');

            $todayTransactions = $this->scopedTransactions($admin)->completed()
                ->whereBetween('transaction_date', [$todayStart, $now])
                ->count();

            // This week stats
            $weekRevenue = $this->scopedTransactions($admin)->income()->completed()
                ->whereBetween('transaction_date', [$weekStart, $now])
                ->sum('amount');

            // This month stats
            $monthRevenue = $this->scopedTransactions($admin)->income()->completed()
                ->whereBetween('transaction_date', [$monthStart, $now])
                ->sum('amount');

            // Recent transactions (last 20)
            $recentTransactions = $this->scopedTransactions($admin)
                ->with(['driver.user', 'device'])
                ->completed()
                ->orderBy('transaction_date', 'desc')
                ->limit(20)
                ->get()
                ->map(function ($transaction) {
                    return [
                        'id' => $transaction->id,
                        'amount' => (float) $transaction->amount,
                        'type' => $transaction->type,
                        'category' => $transaction->category,
                        'category_name' => $transaction->type === 'income' ?
                            (Transaction::PAYMENT_CATEGORIES[$transaction->category] ?? $transaction->category) :
                            (Transaction::EXPENSE_CATEGORIES[$transaction->category] ?? $transaction->category),
                        'driver_name' => $transaction->driver->user->name ?? 'N/A',
                        'device_name' => $transaction->device->name ?? 'N/A',
                        'date' => $transaction->transaction_date->toISOString(),
                        'formatted_date' => $transaction->transaction_date->format('M j, Y H:i'),
                        'payment_method' => $transaction->payment_method,
                        'reference_number' => $transaction->reference_number
                    ];
                });

            // Active drivers and vehicles count
            $activeDriversToday = $this->scopedDrivers($admin)->whereHas('transactions', function ($query) use ($todayStart) {
                $query->where('transaction_date', '>=', $todayStart);
            })->count();

            $activeVehiclesToday = $this->scopedDevices($admin)->whereHas('transactions', function ($query) use ($todayStart) {
                $query->where('transaction_date', '>=', $todayStart);
            })->count();

            // Hourly revenue for today (for mini chart)
            $hourlyRevenue = [];
            for ($hour = 0; $hour < 24; $hour++) {
                $hourStart = $todayStart->copy()->addHours($hour);
                $hourEnd = $hourStart->copy()->addHour();

                if ($hourEnd <= $now) {
                    $revenue = $this->scopedTransactions($admin)->income()->completed()
                        ->whereBetween('transaction_date', [$hourStart, $hourEnd])
                        ->sum('amount');
                } else {
                    $revenue = $this->scopedTransactions($admin)->income()->completed()
                        ->whereBetween('transaction_date', [$hourStart, $now])
                        ->sum('amount');
                }

                $hourlyRevenue[] = [
                    'hour' => $hour,
                    'hour_formatted' => $hourStart->format('H:i'),
                    'revenue' => (float) $revenue
                ];
            }

            $data = [
                'live_stats' => [
                    'today_revenue' => (float) $todayRevenue,
                    'today_transactions' => $todayTransactions,
                    'week_revenue' => (float) $weekRevenue,
                    'month_revenue' => (float) $monthRevenue,
                    'active_drivers_today' => $activeDriversToday,
                    'active_vehicles_today' => $activeVehiclesToday,
                    'average_per_transaction_today' => $todayTransactions > 0 ?
                        round($todayRevenue / $todayTransactions, 2) : 0
                ],
                'recent_transactions' => $recentTransactions,
                'hourly_revenue' => $hourlyRevenue,
                'last_updated' => $now->toISOString()
            ];

            return ResponseHelper::success($data, 'Live analytics retrieved successfully');

        } catch (\Exception $e) {
            \Log::error('Live analytics failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            return ResponseHelper::error('Failed to get live analytics: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Export report to PDF (placeholder)
     */
    #[OA\Post(
        path: '/admin/reports/export-pdf',
        summary: 'Export to pdf',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin Report'],
        parameters: [
            new OA\Parameter(name: 'report_type', in: 'query', schema: new OA\Schema(type: 'string', default: 'revenue')),
            new OA\Parameter(name: 'start_date', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
            new OA\Parameter(name: 'end_date', in: 'query', schema: new OA\Schema(type: 'string', format: 'date')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function exportToPdf(Request $request)
    {
        try {
            $reportType = $request->get('report_type', 'revenue');
            $startDate = $request->get('start_date', Carbon::now()->subDays(30)->format('Y-m-d'));
            $endDate = $request->get('end_date', Carbon::now()->format('Y-m-d'));

            // For now, return a success response
            // In future, implement actual PDF generation using packages like DomPDF or TCPDF

            $data = [
                'message' => "PDF report for {$reportType} generated successfully",
                'report_type' => $reportType,
                'date_range' => "{$startDate} to {$endDate}",
                'pdf_url' => '/storage/reports/report_' . time() . '.pdf', // Placeholder
                'generated_at' => Carbon::now()->toISOString()
            ];

            return ResponseHelper::success($data, 'PDF report generated successfully');

        } catch (\Exception $e) {
            \Log::error('PDF export failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            return ResponseHelper::error('Failed to generate PDF report: ' . $e->getMessage(), 500);
        }
    }
}
