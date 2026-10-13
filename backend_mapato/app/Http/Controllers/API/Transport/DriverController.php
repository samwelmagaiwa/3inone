<?php

namespace App\Http\Controllers\API\Transport;

use App\Http\Controllers\Controller;
use App\Models\Driver;
use App\Helpers\ResponseHelper;
use App\Rules\PerBusiness;
use Illuminate\Http\Request;

class DriverController extends Controller
{
    /**
     * Get driver profile
     */
    public function profile(Request $request)
    {
        try {
            $driver = $request->user()->driver;
            $driver->load('user', 'devices');

            return ResponseHelper::success($driver, 'Driver profile retrieved successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve driver profile: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Update driver profile
     */
    public function updateProfile(Request $request)
    {
        try {
            $request->validate([
                // Unique inside this driver's business only.
                'license_number' => ['sometimes', 'string', PerBusiness::unique(
                    'drivers', 'license_number', $request->user()->driver->owner_id, $request->user()->driver->id
                )],
                'license_expiry' => 'sometimes|date|after:today',
                'address' => 'sometimes|string|max:255',
                'emergency_contact' => 'sometimes|string|max:20',
            ]);

            $driver = $request->user()->driver;
            $driver->update($request->only([
                'license_number',
                'license_expiry',
                'address',
                'emergency_contact',
            ]));

            // Update user info if provided
            if ($request->has('name') || $request->has('phone')) {
                $request->validate([
                    'name' => 'sometimes|string|max:255',
                    'phone' => 'sometimes|string|max:20',
                ]);

                $driver->user->update($request->only(['name', 'phone']));
            }

            $driver->load('user');

            return ResponseHelper::success($driver, 'Driver profile updated successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to update driver profile: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get driver dashboard statistics
     */
    public function dashboard(Request $request)
    {
        try {
            $driver = $request->user()->driver;

            $stats = [
                'total_devices' => $driver->devices()->count(),
                'active_devices' => $driver->devices()->where('is_active', true)->count(),
                'total_transactions' => $driver->transactions()->count(),
                'total_revenue' => $driver->transactions()
                    ->where('type', 'income')
                    ->where('status', 'completed')
                    ->sum('amount'),
                'total_expenses' => $driver->transactions()
                    ->where('type', 'expense')
                    ->where('status', 'completed')
                    ->sum('amount'),
                'today_revenue' => $driver->transactions()
                    ->where('type', 'income')
                    ->where('status', 'completed')
                    ->whereDate('created_at', today())
                    ->sum('amount'),
                'this_week_revenue' => $driver->transactions()
                    ->where('type', 'income')
                    ->where('status', 'completed')
                    ->whereBetween('created_at', [now()->startOfWeek(), now()->endOfWeek()])
                    ->sum('amount'),
                'this_month_revenue' => $driver->transactions()
                    ->where('type', 'income')
                    ->where('status', 'completed')
                    ->whereMonth('created_at', now()->month)
                    ->whereYear('created_at', now()->year)
                    ->sum('amount'),
                'pending_transactions' => $driver->transactions()
                    ->where('status', 'pending')
                    ->count(),
                'recent_transactions' => $driver->transactions()
                    ->with('device')
                    ->latest()
                    ->take(5)
                    ->get(),
            ];

            return ResponseHelper::success($stats, 'Dashboard statistics retrieved successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve dashboard statistics: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get driver activity summary
     */
    public function activity(Request $request)
    {
        try {
            $driver = $request->user()->driver;
            $period = $request->get('period', 'week'); // week, month, year

            $startDate = match($period) {
                'week' => now()->startOfWeek(),
                'month' => now()->startOfMonth(),
                'year' => now()->startOfYear(),
                default => now()->startOfWeek(),
            };

            $endDate = match($period) {
                'week' => now()->endOfWeek(),
                'month' => now()->endOfMonth(),
                'year' => now()->endOfYear(),
                default => now()->endOfWeek(),
            };

            $transactions = $driver->transactions()
                ->whereBetween('created_at', [$startDate, $endDate])
                ->selectRaw('DATE(created_at) as date, type, SUM(amount) as total, COUNT(*) as count')
                ->groupBy('date', 'type')
                ->orderBy('date')
                ->get();

            $activity = $transactions->groupBy('date')->map(function ($dayTransactions) {
                $income = $dayTransactions->where('type', 'income')->first();
                $expense = $dayTransactions->where('type', 'expense')->first();

                return [
                    'income' => $income ? $income->total : 0,
                    'expense' => $expense ? $expense->total : 0,
                    'income_count' => $income ? $income->count : 0,
                    'expense_count' => $expense ? $expense->count : 0,
                ];
            });

            return ResponseHelper::success([
                'period' => $period,
                'start_date' => $startDate->toDateString(),
                'end_date' => $endDate->toDateString(),
                'activity' => $activity,
            ], 'Driver activity retrieved successfully');

        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve driver activity: ' . $e->getMessage(), 500);
        }
    }
}