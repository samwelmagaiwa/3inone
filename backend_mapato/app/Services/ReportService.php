<?php

namespace App\Services;

use App\Models\Driver;
use App\Models\Transaction;
use App\Models\Device;
use App\Models\Receipt;
use App\Support\SqlDate;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\View;

class ReportService
{
    /**
     * Generate revenue report for a driver
     */
    public function generateRevenueReport(Driver $driver, string $startDate, string $endDate, ?int $deviceId = null, string $groupBy = 'day'): array
    {
        $query = $driver->incomeTransactions()
            ->whereBetween('transaction_date', [$startDate, $endDate]);

        if ($deviceId) {
            $query->where('device_id', $deviceId);
        }

        // Get total revenue
        $totalRevenue = $query->sum('amount');
        $transactionCount = $query->count();

        // Every breakdown below starts from its OWN copy of the filtered query. They used to share one
        // object, so the first one's select / group by / order by leaked into the next: MySQL refused
        // "group by period" with `period` no longer selected (a 500 on every revenue report), and the
        // later breakdowns were grouped by the earlier ones' columns as well.

        // Group data by specified period
        $groupedData = $this->groupTransactionsByPeriod(clone $query, $groupBy);

        // Get category breakdown
        $categoryBreakdown = (clone $query)->select('category', DB::raw('SUM(amount) as total'))
            ->groupBy('category')
            ->get()
            ->map(function ($item) {
                return [
                    'category' => $item->category,
                    'category_display' => Transaction::PAYMENT_CATEGORIES[$item->category] ?? $item->category,
                    'total' => (float) $item->total,
                ];
            });

        // Get payment method breakdown
        $paymentMethodBreakdown = (clone $query)->select('payment_method', DB::raw('SUM(amount) as total'))
            ->groupBy('payment_method')
            ->get()
            ->map(function ($item) {
                return [
                    'method' => $item->payment_method,
                    'method_display' => Transaction::PAYMENT_METHODS[$item->payment_method] ?? $item->payment_method,
                    'total' => (float) $item->total,
                ];
            });

        // Get device breakdown if no specific device is selected
        $deviceBreakdown = [];
        if (!$deviceId) {
            $deviceBreakdown = (clone $query)->with('device')
                ->select('device_id', DB::raw('SUM(amount) as total'))
                ->groupBy('device_id')
                ->get()
                ->map(function ($item) {
                    return [
                        'device_id' => $item->device_id,
                        'device_name' => $item->device->name ?? 'Unknown',
                        'device_type' => $item->device->type_display ?? 'Unknown',
                        'total' => (float) $item->total,
                    ];
                });
        }

        return [
            'period' => [
                'start_date' => $startDate,
                'end_date' => $endDate,
                'group_by' => $groupBy,
            ],
            'summary' => [
                'total_revenue' => (float) $totalRevenue,
                'transaction_count' => $transactionCount,
                'average_per_transaction' => $transactionCount > 0 ? (float) ($totalRevenue / $transactionCount) : 0,
            ],
            'grouped_data' => $groupedData,
            'category_breakdown' => $categoryBreakdown,
            'payment_method_breakdown' => $paymentMethodBreakdown,
            'device_breakdown' => $deviceBreakdown,
        ];
    }

    /**
     * Generate expense report for a driver
     */
    public function generateExpenseReport(Driver $driver, string $startDate, string $endDate, ?int $deviceId = null, ?string $category = null): array
    {
        $query = $driver->expenseTransactions()
            ->whereBetween('transaction_date', [$startDate, $endDate]);

        if ($deviceId) {
            $query->where('device_id', $deviceId);
        }

        if ($category) {
            $query->where('category', $category);
        }

        // Get total expenses
        $totalExpenses = $query->sum('amount');
        $transactionCount = $query->count();

        // Get category breakdown
        $categoryBreakdown = $driver->expenseTransactions()
            ->whereBetween('transaction_date', [$startDate, $endDate])
            ->when($deviceId, fn($q) => $q->where('device_id', $deviceId))
            ->select('category', DB::raw('SUM(amount) as total'), DB::raw('COUNT(*) as count'))
            ->groupBy('category')
            ->get()
            ->map(function ($item) {
                return [
                    'category' => $item->category,
                    'category_display' => Transaction::EXPENSE_CATEGORIES[$item->category] ?? $item->category,
                    'total' => (float) $item->total,
                    'count' => $item->count,
                    'average' => (float) ($item->total / $item->count),
                ];
            });

        // Get monthly trend
        $monthlyTrend = $driver->expenseTransactions()
            ->whereBetween('transaction_date', [$startDate, $endDate])
            ->when($deviceId, fn($q) => $q->where('device_id', $deviceId))
            ->when($category, fn($q) => $q->where('category', $category))
            ->select(
                DB::raw(SqlDate::year('transaction_date') . ' as year'),
                DB::raw(SqlDate::month('transaction_date') . ' as month'),
                DB::raw('SUM(amount) as total')
            )
            ->groupBy('year', 'month')
            ->orderBy('year')
            ->orderBy('month')
            ->get()
            ->map(function ($item) {
                return [
                    'period' => Carbon::create($item->year, $item->month)->format('M Y'),
                    'total' => (float) $item->total,
                ];
            });

        // Get recent transactions
        $recentTransactions = $query->with(['device'])
            ->orderBy('transaction_date', 'desc')
            ->limit(10)
            ->get()
            ->map(function ($transaction) {
                return [
                    'id' => $transaction->id,
                    'date' => $transaction->transaction_date->format('Y-m-d'),
                    'amount' => (float) $transaction->amount,
                    'category' => $transaction->category_display,
                    'description' => $transaction->description,
                    'device' => $transaction->device->name ?? 'N/A',
                    'payment_method' => $transaction->payment_method_display,
                ];
            });

        return [
            'period' => [
                'start_date' => $startDate,
                'end_date' => $endDate,
                'category_filter' => $category,
            ],
            'summary' => [
                'total_expenses' => (float) $totalExpenses,
                'transaction_count' => $transactionCount,
                'average_per_transaction' => $transactionCount > 0 ? (float) ($totalExpenses / $transactionCount) : 0,
            ],
            'category_breakdown' => $categoryBreakdown,
            'monthly_trend' => $monthlyTrend,
            'recent_transactions' => $recentTransactions,
        ];
    }

    /**
     * Generate profit/loss report for a driver
     */
    public function generateProfitLossReport(Driver $driver, string $startDate, string $endDate, ?int $deviceId = null): array
    {
        $incomeQuery = $driver->incomeTransactions()
            ->whereBetween('transaction_date', [$startDate, $endDate]);
        
        $expenseQuery = $driver->expenseTransactions()
            ->whereBetween('transaction_date', [$startDate, $endDate]);

        if ($deviceId) {
            $incomeQuery->where('device_id', $deviceId);
            $expenseQuery->where('device_id', $deviceId);
        }

        $totalIncome = $incomeQuery->sum('amount');
        $totalExpenses = $expenseQuery->sum('amount');
        $netProfit = $totalIncome - $totalExpenses;
        $profitMargin = $totalIncome > 0 ? ($netProfit / $totalIncome) * 100 : 0;

        // Monthly breakdown
        $monthlyData = [];
        $start = Carbon::parse($startDate);
        $end = Carbon::parse($endDate);

        while ($start->lte($end)) {
            $monthStart = $start->copy()->startOfMonth();
            $monthEnd = $start->copy()->endOfMonth();

            $monthIncome = $driver->incomeTransactions()
                ->whereBetween('transaction_date', [$monthStart, $monthEnd])
                ->when($deviceId, fn($q) => $q->where('device_id', $deviceId))
                ->sum('amount');

            $monthExpenses = $driver->expenseTransactions()
                ->whereBetween('transaction_date', [$monthStart, $monthEnd])
                ->when($deviceId, fn($q) => $q->where('device_id', $deviceId))
                ->sum('amount');

            $monthlyData[] = [
                'period' => $start->format('M Y'),
                'income' => (float) $monthIncome,
                'expenses' => (float) $monthExpenses,
                'profit' => (float) ($monthIncome - $monthExpenses),
                'margin' => $monthIncome > 0 ? (($monthIncome - $monthExpenses) / $monthIncome) * 100 : 0,
            ];

            $start->addMonth();
        }

        // Device comparison (if no specific device selected)
        $deviceComparison = [];
        if (!$deviceId) {
            $devices = $driver->activeDevices()->get();
            foreach ($devices as $device) {
                $deviceIncome = $driver->incomeTransactions()
                    ->where('device_id', $device->id)
                    ->whereBetween('transaction_date', [$startDate, $endDate])
                    ->sum('amount');

                $deviceExpenses = $driver->expenseTransactions()
                    ->where('device_id', $device->id)
                    ->whereBetween('transaction_date', [$startDate, $endDate])
                    ->sum('amount');

                $deviceComparison[] = [
                    'device_id' => $device->id,
                    'device_name' => $device->name,
                    'device_type' => $device->type_display,
                    'income' => (float) $deviceIncome,
                    'expenses' => (float) $deviceExpenses,
                    'profit' => (float) ($deviceIncome - $deviceExpenses),
                    'margin' => $deviceIncome > 0 ? (($deviceIncome - $deviceExpenses) / $deviceIncome) * 100 : 0,
                ];
            }
        }

        return [
            'period' => [
                'start_date' => $startDate,
                'end_date' => $endDate,
            ],
            'summary' => [
                'total_income' => (float) $totalIncome,
                'total_expenses' => (float) $totalExpenses,
                'net_profit' => (float) $netProfit,
                'profit_margin' => round($profitMargin, 2),
                'is_profitable' => $netProfit > 0,
            ],
            'monthly_breakdown' => $monthlyData,
            'device_comparison' => $deviceComparison,
        ];
    }

    /**
     * Generate daily summary report
     */
    public function generateDailySummary(Driver $driver, string $date): array
    {
        $startOfDay = Carbon::parse($date)->startOfDay();
        $endOfDay = Carbon::parse($date)->endOfDay();

        $income = $driver->incomeTransactions()
            ->whereBetween('transaction_date', [$startOfDay, $endOfDay])
            ->sum('amount');

        $expenses = $driver->expenseTransactions()
            ->whereBetween('transaction_date', [$startOfDay, $endOfDay])
            ->sum('amount');

        $transactionCount = $driver->transactions()
            ->whereBetween('transaction_date', [$startOfDay, $endOfDay])
            ->where('status', 'completed')
            ->count();

        // Hourly breakdown
        $hourlyData = [];
        for ($hour = 0; $hour < 24; $hour++) {
            $hourStart = Carbon::parse($date)->setHour($hour)->startOfHour();
            $hourEnd = Carbon::parse($date)->setHour($hour)->endOfHour();

            $hourIncome = $driver->incomeTransactions()
                ->whereBetween('transaction_date', [$hourStart, $hourEnd])
                ->sum('amount');

            $hourExpenses = $driver->expenseTransactions()
                ->whereBetween('transaction_date', [$hourStart, $hourEnd])
                ->sum('amount');

            $hourlyData[] = [
                'hour' => sprintf('%02d:00', $hour),
                'income' => (float) $hourIncome,
                'expenses' => (float) $hourExpenses,
                'net' => (float) ($hourIncome - $hourExpenses),
            ];
        }

        // Device performance for the day
        $devicePerformance = $driver->activeDevices()->get()->map(function ($device) use ($startOfDay, $endOfDay) {
            $deviceIncome = $device->incomeTransactions()
                ->whereBetween('transaction_date', [$startOfDay, $endOfDay])
                ->sum('amount');

            $deviceExpenses = $device->expenseTransactions()
                ->whereBetween('transaction_date', [$startOfDay, $endOfDay])
                ->sum('amount');

            return [
                'device_id' => $device->id,
                'device_name' => $device->name,
                'income' => (float) $deviceIncome,
                'expenses' => (float) $deviceExpenses,
                'net' => (float) ($deviceIncome - $deviceExpenses),
                'transaction_count' => $device->transactions()
                    ->whereBetween('transaction_date', [$startOfDay, $endOfDay])
                    ->where('status', 'completed')
                    ->count(),
            ];
        });

        return [
            'date' => $date,
            'summary' => [
                'total_income' => (float) $income,
                'total_expenses' => (float) $expenses,
                'net_profit' => (float) ($income - $expenses),
                'transaction_count' => $transactionCount,
            ],
            'hourly_breakdown' => $hourlyData,
            'device_performance' => $devicePerformance,
        ];
    }

    /**
     * Generate weekly summary report
     */
    public function generateWeeklySummary(Driver $driver, string $weekStart): array
    {
        $startOfWeek = Carbon::parse($weekStart)->startOfWeek();
        $endOfWeek = Carbon::parse($weekStart)->endOfWeek();

        $income = $driver->incomeTransactions()
            ->whereBetween('transaction_date', [$startOfWeek, $endOfWeek])
            ->sum('amount');

        $expenses = $driver->expenseTransactions()
            ->whereBetween('transaction_date', [$startOfWeek, $endOfWeek])
            ->sum('amount');

        // Daily breakdown for the week
        $dailyData = [];
        $currentDay = $startOfWeek->copy();

        while ($currentDay->lte($endOfWeek)) {
            $dayStart = $currentDay->copy()->startOfDay();
            $dayEnd = $currentDay->copy()->endOfDay();

            $dayIncome = $driver->incomeTransactions()
                ->whereBetween('transaction_date', [$dayStart, $dayEnd])
                ->sum('amount');

            $dayExpenses = $driver->expenseTransactions()
                ->whereBetween('transaction_date', [$dayStart, $dayEnd])
                ->sum('amount');

            $dailyData[] = [
                'date' => $currentDay->format('Y-m-d'),
                'day_name' => $currentDay->format('l'),
                'income' => (float) $dayIncome,
                'expenses' => (float) $dayExpenses,
                'net' => (float) ($dayIncome - $dayExpenses),
            ];

            $currentDay->addDay();
        }

        return [
            'week_start' => $startOfWeek->format('Y-m-d'),
            'week_end' => $endOfWeek->format('Y-m-d'),
            'summary' => [
                'total_income' => (float) $income,
                'total_expenses' => (float) $expenses,
                'net_profit' => (float) ($income - $expenses),
                'daily_average' => (float) (($income - $expenses) / 7),
            ],
            'daily_breakdown' => $dailyData,
        ];
    }

    /**
     * Generate monthly summary report
     */
    public function generateMonthlySummary(Driver $driver, int $month, int $year): array
    {
        $startOfMonth = Carbon::create($year, $month, 1)->startOfMonth();
        $endOfMonth = Carbon::create($year, $month, 1)->endOfMonth();

        $income = $driver->incomeTransactions()
            ->whereBetween('transaction_date', [$startOfMonth, $endOfMonth])
            ->sum('amount');

        $expenses = $driver->expenseTransactions()
            ->whereBetween('transaction_date', [$startOfMonth, $endOfMonth])
            ->sum('amount');

        // Weekly breakdown for the month
        $weeklyData = [];
        $currentWeek = $startOfMonth->copy()->startOfWeek();

        while ($currentWeek->lte($endOfMonth)) {
            $weekEnd = $currentWeek->copy()->endOfWeek();
            if ($weekEnd->gt($endOfMonth)) {
                $weekEnd = $endOfMonth->copy();
            }

            $weekIncome = $driver->incomeTransactions()
                ->whereBetween('transaction_date', [$currentWeek, $weekEnd])
                ->sum('amount');

            $weekExpenses = $driver->expenseTransactions()
                ->whereBetween('transaction_date', [$currentWeek, $weekEnd])
                ->sum('amount');

            $weeklyData[] = [
                'week_start' => $currentWeek->format('Y-m-d'),
                'week_end' => $weekEnd->format('Y-m-d'),
                'income' => (float) $weekIncome,
                'expenses' => (float) $weekExpenses,
                'net' => (float) ($weekIncome - $weekExpenses),
            ];

            $currentWeek->addWeek();
        }

        // Category breakdown for the month
        $categoryBreakdown = $driver->expenseTransactions()
            ->whereBetween('transaction_date', [$startOfMonth, $endOfMonth])
            ->select('category', DB::raw('SUM(amount) as total'))
            ->groupBy('category')
            ->get()
            ->map(function ($item) {
                return [
                    'category' => $item->category,
                    'category_display' => Transaction::EXPENSE_CATEGORIES[$item->category] ?? $item->category,
                    'total' => (float) $item->total,
                ];
            });

        return [
            'month' => $month,
            'year' => $year,
            'month_name' => Carbon::create($year, $month)->format('F Y'),
            'summary' => [
                'total_income' => (float) $income,
                'total_expenses' => (float) $expenses,
                'net_profit' => (float) ($income - $expenses),
                'days_in_month' => $endOfMonth->day,
                'daily_average' => (float) (($income - $expenses) / $endOfMonth->day),
            ],
            'weekly_breakdown' => $weeklyData,
            'expense_categories' => $categoryBreakdown,
        ];
    }

    /**
     * Generate device performance report
     */
    public function generateDevicePerformanceReport(Driver $driver, string $startDate, string $endDate): array
    {
        $devices = $driver->activeDevices()->get();
        $deviceData = [];

        foreach ($devices as $device) {
            $income = $device->incomeTransactions()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->sum('amount');

            $expenses = $device->expenseTransactions()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->sum('amount');

            $transactionCount = $device->transactions()
                ->whereBetween('transaction_date', [$startDate, $endDate])
                ->where('status', 'completed')
                ->count();

            $deviceData[] = [
                'device_id' => $device->id,
                'device_name' => $device->name,
                'device_type' => $device->type_display,
                'plate_number' => $device->plate_number,
                'income' => (float) $income,
                'expenses' => (float) $expenses,
                'net_profit' => (float) ($income - $expenses),
                'transaction_count' => $transactionCount,
                'average_per_transaction' => $transactionCount > 0 ? (float) ($income / $transactionCount) : 0,
                'profit_margin' => $income > 0 ? (($income - $expenses) / $income) * 100 : 0,
            ];
        }

        // Sort by net profit descending
        usort($deviceData, function ($a, $b) {
            return $b['net_profit'] <=> $a['net_profit'];
        });

        $totalIncome = array_sum(array_column($deviceData, 'income'));
        $totalExpenses = array_sum(array_column($deviceData, 'expenses'));

        return [
            'period' => [
                'start_date' => $startDate,
                'end_date' => $endDate,
            ],
            'summary' => [
                'total_devices' => count($deviceData),
                'total_income' => (float) $totalIncome,
                'total_expenses' => (float) $totalExpenses,
                'total_net_profit' => (float) ($totalIncome - $totalExpenses),
                'best_performing_device' => $deviceData[0] ?? null,
            ],
            'device_performance' => $deviceData,
        ];
    }

    /**
     * Get report dashboard data
     */
    public function getReportDashboard(Driver $driver): array
    {
        $today = now();
        $thisMonth = $today->copy()->startOfMonth();
        $lastMonth = $today->copy()->subMonth()->startOfMonth();
        $lastMonthEnd = $today->copy()->subMonth()->endOfMonth();

        // Today's data
        $todayIncome = $driver->incomeTransactions()->today()->sum('amount');
        $todayExpenses = $driver->expenseTransactions()->today()->sum('amount');

        // This month's data
        $thisMonthIncome = $driver->incomeTransactions()->thisMonth()->sum('amount');
        $thisMonthExpenses = $driver->expenseTransactions()->thisMonth()->sum('amount');

        // Last month's data for comparison
        $lastMonthIncome = $driver->incomeTransactions()
            ->whereBetween('transaction_date', [$lastMonth, $lastMonthEnd])
            ->sum('amount');
        $lastMonthExpenses = $driver->expenseTransactions()
            ->whereBetween('transaction_date', [$lastMonth, $lastMonthEnd])
            ->sum('amount');

        // Calculate growth percentages
        $incomeGrowth = $lastMonthIncome > 0 ? (($thisMonthIncome - $lastMonthIncome) / $lastMonthIncome) * 100 : 0;
        $expenseGrowth = $lastMonthExpenses > 0 ? (($thisMonthExpenses - $lastMonthExpenses) / $lastMonthExpenses) * 100 : 0;

        // Recent transactions
        $recentTransactions = $driver->transactions()
            ->with(['device'])
            ->where('status', 'completed')
            ->orderBy('transaction_date', 'desc')
            ->limit(5)
            ->get()
            ->map(function ($transaction) {
                return [
                    'id' => $transaction->id,
                    'type' => $transaction->type,
                    'amount' => (float) $transaction->amount,
                    'category' => $transaction->category_display,
                    'device' => $transaction->device->name ?? 'N/A',
                    'date' => $transaction->transaction_date->format('Y-m-d H:i'),
                ];
            });

        return [
            'today' => [
                'income' => (float) $todayIncome,
                'expenses' => (float) $todayExpenses,
                'net' => (float) ($todayIncome - $todayExpenses),
            ],
            'this_month' => [
                'income' => (float) $thisMonthIncome,
                'expenses' => (float) $thisMonthExpenses,
                'net' => (float) ($thisMonthIncome - $thisMonthExpenses),
                'income_growth' => round($incomeGrowth, 2),
                'expense_growth' => round($expenseGrowth, 2),
            ],
            'recent_transactions' => $recentTransactions,
        ];
    }

    /**
     * Export report to PDF (HTML version for now)
     */
    public function exportReportToPdf(Driver $driver, string $reportType, string $startDate, string $endDate, ?int $deviceId = null): string
    {
        $data = [];
        $title = '';

        switch ($reportType) {
            case 'revenue':
                $data = $this->generateRevenueReport($driver, $startDate, $endDate, $deviceId);
                $title = 'Ripoti ya Mapato';
                break;
            case 'expenses':
                $data = $this->generateExpenseReport($driver, $startDate, $endDate, $deviceId);
                $title = 'Ripoti ya Matumizi';
                break;
            case 'profit_loss':
                $data = $this->generateProfitLossReport($driver, $startDate, $endDate, $deviceId);
                $title = 'Ripoti ya Faida na Hasara';
                break;
            case 'device_performance':
                $data = $this->generateDevicePerformanceReport($driver, $startDate, $endDate);
                $title = 'Ripoti ya Utendaji wa Vifaa';
                break;
            default:
                throw new \InvalidArgumentException('Invalid report type');
        }

        // Generate HTML content
        $html = View::make('reports.pdf', [
            'title' => $title,
            'data' => $data,
            'driver' => $driver,
            'generated_at' => now()->format('d/m/Y H:i'),
        ])->render();

        $filename = self::reportFilename($reportType);
        $path = 'reports/' . $filename;

        // Private: reports hold a business's money figures and are only ever handed to the person
        // who asked for them (a download), never served from public storage.
        Storage::disk(\App\Support\PrivateFile::DISK)->put($path, $html);

        return Storage::disk(\App\Support\PrivateFile::DISK)->path($path);
    }

    /**
     * Name for a generated report file. Reports are written to the publicly served storage,
     * where anyone who can guess the URL can open them -- and "report_driver_<date and time to
     * the second>" is guessable (86,400 tries a day). The random part makes it unguessable.
     */
    public static function reportFilename(string $reportType): string
    {
        $type = preg_replace('/[^a-z0-9_]/i', '', $reportType) ?: 'report';

        return 'report_' . $type . '_' . date('Y_m_d_H_i_s') . '_' . \Illuminate\Support\Str::random(24) . '.html';
    }

    /**
     * Group transactions by period (day, week, month)
     */
    private function groupTransactionsByPeriod($query, string $groupBy): array
    {
        switch ($groupBy) {
            case 'day':
                return $query->select(
                    DB::raw('DATE(transaction_date) as period'),
                    DB::raw('SUM(amount) as total'),
                    DB::raw('COUNT(*) as count')
                )
                ->groupBy('period')
                ->orderBy('period')
                ->get()
                ->map(function ($item) {
                    return [
                        'period' => Carbon::parse($item->period)->format('Y-m-d'),
                        'period_display' => Carbon::parse($item->period)->format('d M Y'),
                        'total' => (float) $item->total,
                        'count' => $item->count,
                    ];
                })->toArray();

            case 'week':
                return $query->select(
                    DB::raw(SqlDate::yearWeek('transaction_date') . ' as period'),
                    DB::raw('SUM(amount) as total'),
                    DB::raw('COUNT(*) as count')
                )
                ->groupBy('period')
                ->orderBy('period')
                ->get()
                ->map(function ($item) {
                    $year = substr($item->period, 0, 4);
                    $week = substr($item->period, 4, 2);
                    $date = Carbon::now()->setISODate($year, $week);
                    
                    return [
                        'period' => $item->period,
                        'period_display' => 'Wiki ' . $week . ', ' . $year,
                        'total' => (float) $item->total,
                        'count' => $item->count,
                    ];
                })->toArray();

            case 'month':
                return $query->select(
                    DB::raw(SqlDate::year('transaction_date') . ' as year'),
                    DB::raw(SqlDate::month('transaction_date') . ' as month'),
                    DB::raw('SUM(amount) as total'),
                    DB::raw('COUNT(*) as count')
                )
                ->groupBy('year', 'month')
                ->orderBy('year')
                ->orderBy('month')
                ->get()
                ->map(function ($item) {
                    return [
                        'period' => $item->year . '-' . str_pad($item->month, 2, '0', STR_PAD_LEFT),
                        'period_display' => Carbon::create($item->year, $item->month)->format('M Y'),
                        'total' => (float) $item->total,
                        'count' => $item->count,
                    ];
                })->toArray();

            default:
                return [];
        }
    }
}