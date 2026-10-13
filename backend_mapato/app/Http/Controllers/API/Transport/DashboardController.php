<?php

namespace App\Http\Controllers\API\Transport;

use App\Http\Controllers\Controller;
use App\Models\Payment;
use App\Models\PaymentReceipt;
use App\Models\Driver;
use App\Models\Device;
use App\Models\DebtRecord;
use App\Models\User;
use App\Helpers\ResponseHelper;
use App\Support\SqlDate;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Carbon\Carbon;
use OpenApi\Attributes as OA;

class DashboardController extends Controller
{
    /**
     * Get comprehensive dashboard data
     */
    #[OA\Get(
        path: '/admin/dashboard-data',
        summary: 'List resources',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Dashboard'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function index(Request $request)
    {
        try {
            $data = [
                // Payments and Financial Data
                'total_drivers' => $this->getTotalDrivers(),
                'active_drivers' => $this->getActiveDrivers(),
                'total_vehicles' => $this->getTotalVehicles(),
                'active_vehicles' => $this->getActiveVehicles(),
                
                // Payment Statistics
                'monthly_revenue' => $this->getMonthlyRevenue(),
                'weekly_revenue' => $this->getWeeklyRevenue(),
                'daily_revenue' => $this->getDailyRevenue(),
                
                // Receipt Information
                'pending_receipts_count' => $this->getPendingReceiptsCount(),
                'receipts_count' => $this->getReceiptsCount(),
                
                // Debt Information
                'debts_count' => $this->getDebtsCount(),
                'total_outstanding_debt' => $this->getTotalOutstandingDebt(),
                
                // Recent Transactions/Payments
                'recent_payments' => $this->getRecentPayments(),
                
                // Chart Data
                'daily_revenue_chart' => $this->getDailyRevenueChart(),
                'monthly_payments_chart' => $this->getMonthlyPaymentsChart(),
                
                // Performance Metrics
                'net_profit' => $this->getNetProfit(),
                'saving_rate' => $this->getSavingRate(),
            ];

            return ResponseHelper::success($data, 'Dashboard data retrieved successfully');

        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve dashboard data: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get total number of drivers
     */
    private function getTotalDrivers(): int
    {
        return Driver::count();
    }

    /**
     * Get number of active drivers
     */
    private function getActiveDrivers(): int
    {
        return Driver::where('is_active', true)->count();
    }

    /**
     * Get total number of vehicles/devices
     */
    private function getTotalVehicles(): int
    {
        return Device::count();
    }

    /**
     * Get number of active vehicles
     */
    private function getActiveVehicles(): int
    {
        return Device::where('is_active', true)->count();
    }

    /**
     * Get monthly revenue from payments and debt records
     */
    private function getMonthlyRevenue(): float
    {
        // Revenue from debt_records (paid_amount)
        $debtRevenue = DebtRecord::whereMonth('paid_at', Carbon::now()->month)
                                ->whereYear('paid_at', Carbon::now()->year)
                                ->sum('paid_amount');
        
        // Revenue from payments (amount)
        $paymentRevenue = Payment::where('status', 'completed')
                                ->whereMonth('payment_date', Carbon::now()->month)
                                ->whereYear('payment_date', Carbon::now()->year)
                                ->sum('amount');
        
        return $debtRevenue + $paymentRevenue;
    }

    /**
     * Get weekly revenue from payments and debt records
     */
    private function getWeeklyRevenue(): float
    {
        // Revenue from debt_records (paid_amount)
        $debtRevenue = DebtRecord::whereBetween('paid_at', [
                                    Carbon::now()->startOfWeek(),
                                    Carbon::now()->endOfWeek()
                                ])
                                ->sum('paid_amount');
        
        // Revenue from payments (amount)
        $paymentRevenue = Payment::where('status', 'completed')
                                ->whereBetween('payment_date', [
                                    Carbon::now()->startOfWeek(),
                                    Carbon::now()->endOfWeek()
                                ])
                                ->sum('amount');
        
        return $debtRevenue + $paymentRevenue;
    }

    /**
     * Get daily revenue from payments and debt records
     */
    private function getDailyRevenue(): float
    {
        // Revenue from debt_records (paid_amount)
        $debtRevenue = DebtRecord::whereDate('paid_at', Carbon::today())
                                ->sum('paid_amount');
        
        // Revenue from payments (amount)
        $paymentRevenue = Payment::where('status', 'completed')
                                ->whereDate('payment_date', Carbon::today())
                                ->sum('amount');
        
        return $debtRevenue + $paymentRevenue;
    }

    /**
     * Get count of pending receipts (from payments table with receipt_status)
     */
    private function getPendingReceiptsCount(): int
    {
        // Receipts generated but not yet delivered
        return PaymentReceipt::whereIn('status', ['generated', 'sent'])->count();
    }

    /**
     * Get count of generated receipts (from payment_receipts table with status)
     */
    private function getReceiptsCount(): int
    {
        // Total receipts issued (all statuses)
        return PaymentReceipt::count();
    }

    /**
     * Get count of outstanding debts
     */
    private function getDebtsCount(): int
    {
        return DebtRecord::where('is_paid', false)->count();
    }

    /**
     * Get total outstanding debt amount
     */
    private function getTotalOutstandingDebt(): float
    {
        return DebtRecord::where('is_paid', false)
                        ->selectRaw('COALESCE(SUM(COALESCE(expected_amount, 0) - COALESCE(paid_amount, 0)), 0) as total')
                        ->value('total') ?? 0;
    }

    /**
     * Get recent payments for the dashboard
     */
    private function getRecentPayments(): array
    {
        return Payment::with(['driver.user'])
                     ->where('status', 'completed')
                     ->orderBy('payment_date', 'desc')
                     ->limit(5)
                     ->get()
                     ->map(function ($payment) {
                         return [
                             'id' => $payment->id,
                             'reference_number' => $payment->reference_number,
                             'driver_name' => $payment->driver->name ?? 'Unknown Driver',
                             'amount' => $payment->amount,
                             'payment_date' => $payment->payment_date->format('Y-m-d H:i:s'),
                             'payment_channel' => $payment->payment_channel,
                         ];
                     })->toArray();
    }

    /**
     * Get daily revenue for the last 30 days for chart
     */
    private function getDailyRevenueChart(): array
    {
        $thirtyDaysAgo = Carbon::now()->subDays(29);
        
        $dailyRevenue = Payment::where('status', 'completed')
                              ->where('payment_date', '>=', $thirtyDaysAgo)
                              ->selectRaw('DATE(payment_date) as date, SUM(amount) as amount')
                              ->groupBy(DB::raw('DATE(payment_date)'))
                              ->orderBy('date')
                              ->get();

        // Fill missing dates with zero values
        $result = [];
        for ($i = 29; $i >= 0; $i--) {
            $date = Carbon::now()->subDays($i)->format('Y-m-d');
            $revenue = $dailyRevenue->firstWhere('date', $date);
            
            $result[] = [
                'date' => $date,
                'amount' => $revenue ? (float) $revenue->amount : 0,
                'formatted_date' => Carbon::parse($date)->format('M d')
            ];
        }

        return $result;
    }

    /**
     * Get monthly payments chart for the last 12 months
     */
    private function getMonthlyPaymentsChart(): array
    {
        $twelveMonthsAgo = Carbon::now()->subMonths(11)->startOfMonth();
        
        $monthlyPayments = Payment::where('status', 'completed')
                                 ->where('payment_date', '>=', $twelveMonthsAgo)
                                 ->selectRaw(SqlDate::year('payment_date') . ' as year, ' . SqlDate::month('payment_date') . ' as month, SUM(amount) as amount, COUNT(*) as count')
                                 ->groupBy(DB::raw(SqlDate::year('payment_date') . ', ' . SqlDate::month('payment_date')))
                                 ->orderBy('year')
                                 ->orderBy('month')
                                 ->get();

        // Fill missing months with zero values
        $result = [];
        for ($i = 11; $i >= 0; $i--) {
            $date = Carbon::now()->subMonths($i);
            $year = $date->year;
            $month = $date->month;
            
            $payment = $monthlyPayments->first(function ($item) use ($year, $month) {
                return $item->year == $year && $item->month == $month;
            });
            
            $result[] = [
                'year' => $year,
                'month' => $month,
                'amount' => $payment ? (float) $payment->amount : 0,
                'count' => $payment ? (int) $payment->count : 0,
                'month_name' => $date->format('M Y')
            ];
        }

        return $result;
    }

    /**
     * Calculate net profit (simplified calculation)
     */
    private function getNetProfit(): float
    {
        $monthlyRevenue = $this->getMonthlyRevenue();
        // For now, assume 20% operational costs - this can be refined later
        $operationalCosts = $monthlyRevenue * 0.20;
        
        return $monthlyRevenue - $operationalCosts;
    }

    /**
     * Calculate saving rate (simplified calculation)
     */
    private function getSavingRate(): float
    {
        $monthlyRevenue = $this->getMonthlyRevenue();
        $netProfit = $this->getNetProfit();
        
        if ($monthlyRevenue > 0) {
            return ($netProfit / $monthlyRevenue) * 100;
        }
        
        return 0;
    }

    /**
     * Get statistics for admin report
     */
    #[OA\Get(
        path: '/admin/dashboard-stats',
        summary: 'Get stats',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Dashboard'],
        parameters: [
            new OA\Parameter(name: 'start_date', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'end_date', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getStats(Request $request)
    {
        try {
            $startDate = $request->get('start_date', Carbon::now()->startOfMonth()->toDateString());
            $endDate = $request->get('end_date', Carbon::now()->toDateString());

            $stats = [
                'drivers' => [
                    'total' => $this->getTotalDrivers(),
                    'active' => $this->getActiveDrivers(),
                    'inactive' => $this->getTotalDrivers() - $this->getActiveDrivers(),
                ],
                'vehicles' => [
                    'total' => $this->getTotalVehicles(),
                    'active' => $this->getActiveVehicles(),
                    'inactive' => $this->getTotalVehicles() - $this->getActiveVehicles(),
                ],
                'payments' => [
                    'total_amount' => Payment::where('status', 'completed')
                                            ->whereBetween('payment_date', [$startDate, $endDate])
                                            ->sum('amount'),
                    'count' => Payment::where('status', 'completed')
                                     ->whereBetween('payment_date', [$startDate, $endDate])
                                     ->count(),
                    'average' => Payment::where('status', 'completed')
                                       ->whereBetween('payment_date', [$startDate, $endDate])
                                       ->avg('amount') ?? 0,
                ],
                'debts' => [
                    'total_amount' => $this->getTotalOutstandingDebt(),
                    'count' => $this->getDebtsCount(),
                ],
                'receipts' => [
                    'generated' => $this->getReceiptsCount(),
                    'pending' => $this->getPendingReceiptsCount(),
                ],
            ];

            return ResponseHelper::success($stats, 'Statistics retrieved successfully');

        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve statistics: ' . $e->getMessage(), 500);
        }
    }

    // ====== INDIVIDUAL DASHBOARD ENDPOINTS FOR FLUTTER APP ======

    /**
     * Get active drivers count
     */
    #[OA\Get(
        path: '/admin/dashboard/active-drivers-count',
        summary: 'Get active drivers count',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Dashboard'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getActiveDriversCount()
    {
        try {
            $count = Driver::where('is_active', 1)->count();
            return ResponseHelper::success(['count' => $count], 'Active drivers count retrieved successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve active drivers count: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get active devices count
     */
    #[OA\Get(
        path: '/admin/dashboard/active-devices-count',
        summary: 'Get active devices count',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Dashboard'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getActiveDevicesCount()
    {
        try {
            $count = Device::where('is_active', 1)->count();
            return ResponseHelper::success(['count' => $count], 'Active devices count retrieved successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve active devices count: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get unpaid debts count
     */
    #[OA\Get(
        path: '/admin/dashboard/unpaid-debts-count',
        summary: 'Get unpaid debts count',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Dashboard'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getUnpaidDebtsCount()
    {
        try {
            $count = DebtRecord::where('is_paid', 0)->count();
            return ResponseHelper::success(['count' => $count], 'Unpaid debts count retrieved successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve unpaid debts count: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get generated receipts count
     */
    #[OA\Get(
        path: '/admin/dashboard/generated-receipts-count',
        summary: 'Get generated receipts count',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Dashboard'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getGeneratedReceiptsCount()
    {
        try {
            // Total receipts issued (all statuses)
            $count = PaymentReceipt::count();
            return ResponseHelper::success(['count' => $count], 'Generated receipts count retrieved successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve generated receipts count: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get pending receipts count (API endpoint)
     */
    #[OA\Get(
        path: '/admin/dashboard/pending-receipts-count',
        summary: 'Get pending receipts count api',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Dashboard'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getPendingReceiptsCountApi()
    {
        try {
            // Based on conversation summary: payments table has receipt_status column
            // Receipts generated but not delivered yet
            $count = PaymentReceipt::whereIn('status', ['generated', 'sent'])->count();
            return ResponseHelper::success(['count' => $count], 'Pending receipts count retrieved successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve pending receipts count: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get daily revenue (API endpoint)
     */
    #[OA\Get(
        path: '/admin/dashboard/daily-revenue',
        summary: 'Get daily revenue api',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Dashboard'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getDailyRevenueApi()
    {
        try {
            // Based on conversation summary: Revenue from paid_amount in debt_records + amount in payments
            $debtRevenue = DebtRecord::whereDate('paid_at', Carbon::today())
                                   ->sum('paid_amount');
            
            $paymentRevenue = Payment::where('status', 'completed')
                                   ->whereDate('payment_date', Carbon::today())
                                   ->sum('amount');
            
            $totalRevenue = $debtRevenue + $paymentRevenue;
            
            return ResponseHelper::success([
                'revenue' => $totalRevenue,
                'debt_revenue' => $debtRevenue,
                'payment_revenue' => $paymentRevenue
            ], 'Daily revenue retrieved successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve daily revenue: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get weekly revenue (API endpoint)
     */
    #[OA\Get(
        path: '/admin/dashboard/weekly-revenue',
        summary: 'Get weekly revenue api',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Dashboard'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getWeeklyRevenueApi()
    {
        try {
            // Revenue from debt_records (paid_amount)
            $debtRevenue = DebtRecord::whereBetween('paid_at', [
                                        Carbon::now()->startOfWeek(),
                                        Carbon::now()->endOfWeek()
                                    ])
                                    ->sum('paid_amount');
            
            // Revenue from payments (amount)
            $paymentRevenue = Payment::where('status', 'completed')
                                    ->whereBetween('payment_date', [
                                        Carbon::now()->startOfWeek(),
                                        Carbon::now()->endOfWeek()
                                    ])
                                    ->sum('amount');
            
            $totalRevenue = $debtRevenue + $paymentRevenue;
            
            return ResponseHelper::success([
                'revenue' => $totalRevenue,
                'debt_revenue' => $debtRevenue,
                'payment_revenue' => $paymentRevenue
            ], 'Weekly revenue retrieved successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve weekly revenue: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get monthly revenue (API endpoint)
     */
    #[OA\Get(
        path: '/admin/dashboard/monthly-revenue',
        summary: 'Get monthly revenue api',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Dashboard'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getMonthlyRevenueApi()
    {
        try {
            // Revenue from debt_records (paid_amount)
            $debtRevenue = DebtRecord::whereMonth('paid_at', Carbon::now()->month)
                                    ->whereYear('paid_at', Carbon::now()->year)
                                    ->sum('paid_amount');
            
            // Revenue from payments (amount)
            $paymentRevenue = Payment::where('status', 'completed')
                                    ->whereMonth('payment_date', Carbon::now()->month)
                                    ->whereYear('payment_date', Carbon::now()->year)
                                    ->sum('amount');
            
            $totalRevenue = $debtRevenue + $paymentRevenue;
            
            return ResponseHelper::success([
                'revenue' => $totalRevenue,
                'debt_revenue' => $debtRevenue,
                'payment_revenue' => $paymentRevenue
            ], 'Monthly revenue retrieved successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve monthly revenue: ' . $e->getMessage(), 500);
        }
    }
}