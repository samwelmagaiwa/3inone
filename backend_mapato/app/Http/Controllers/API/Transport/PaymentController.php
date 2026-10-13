<?php

namespace App\Http\Controllers\API\Transport;

use App\Rules\InAccount;
use App\Http\Controllers\Controller;
use App\Models\Payment;
use App\Models\DebtRecord;
use App\Models\Driver;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Carbon\Carbon;
use OpenApi\Attributes as OA;

class PaymentController extends Controller
{
    /**
     * Get drivers with outstanding debts
     */
    #[OA\Get(
        path: '/admin/payments/drivers-with-debts',
        summary: 'Get drivers with debts',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Payment'],
        parameters: [
            new OA\Parameter(name: 'page', in: 'query', schema: new OA\Schema(type: 'string', default: '1')),
            new OA\Parameter(name: 'limit', in: 'query', schema: new OA\Schema(type: 'string', default: '50')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getDriversWithDebts(Request $request): JsonResponse
    {
        try {
            $page = max((int) $request->get('page', 1), 1);
            $limit = min((int) $request->get('limit', 50), 100);
            $onlyWithDebts = $request->boolean('only_with_debts', false);

            // Load all drivers with their unpaid debt records and user relation for name/phone
            $driversQuery = Driver::with([
                'user',
                'debtRecords' => function ($query) {
                    $query->where('is_paid', false)
                        ->orderBy('earning_date', 'desc');
                }
            ]);

            $drivers = $driversQuery->get();

            // Build formatted collection with totals and status
            $formatted = $drivers->map(function ($driver) {
                $unpaidRecords = $driver->debtRecords ?? collect();
                $totalDebt = (float) $unpaidRecords->sum(function ($r) {
                    // remaining_amount is an accessor (expected_amount - paid_amount)
                    return (float) $r->remaining_amount;
                });
                $unpaidCount = $unpaidRecords->count();

                return [
                    'id' => (string) $driver->id,
                    'name' => (string) ($driver->name ?? ''),
                    'email' => (string) ($driver->email ?? ''),
                    'phone' => (string) ($driver->phone ?? ''),
                    'vehicle_number' => $driver->vehicle_number,
                    'vehicle_type' => $driver->vehicle_type,
                    'status' => $driver->status,
                    'total_debt' => $totalDebt,
                    'unpaid_days' => $unpaidCount,
                    'overdue_days' => $unpaidRecords->where('is_overdue', true)->count(),
                    'has_debt' => $totalDebt > 0,
                    'status_text' => $totalDebt > 0 ? 'Ana deni' : 'Hana deni',
                ];
            });

            // Optionally filter to only those with debts
            if ($onlyWithDebts) {
                $formatted = $formatted->filter(fn($d) => $d['has_debt']);
            }

            // Sort: drivers with debts first, then by total debt desc, then by name asc
            $sorted = $formatted->sortBy([
                ['has_debt', 'desc'],
                ['total_debt', 'desc'],
                ['name', 'asc'],
            ])->values();

            // Manual pagination on the sorted collection
            $total = $sorted->count();
            $offset = ($page - 1) * $limit;
            $pagedDrivers = $sorted->slice($offset, $limit)->values();
            $totalPages = (int) ceil($total / $limit ?: 1);

            return response()->json([
                'success' => true,
                'message' => 'Drivers retrieved successfully',
                'data' => [
                    'drivers' => $pagedDrivers,
                    'pagination' => [
                        'current_page' => $page,
                        'per_page' => $limit,
                        'total' => $total,
                        'total_pages' => $totalPages,
                    ]
                ]
            ]);

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            Log::error('Error fetching drivers with debts: ' . $e->getMessage());

            return response()->json([
                'success' => false,
                'message' => 'Failed to fetch drivers',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Get debt summary for a specific driver
     */
    #[OA\Get(
        path: '/admin/payments/driver-debt-summary/{driverId}',
        summary: 'Get driver debt summary',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Payment'],
        parameters: [
            new OA\Parameter(name: 'driverId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getDriverDebtSummary(string $driverId): JsonResponse
    {
        try {
            // Accept either drivers.id or users.id and normalize to drivers.id
            $driver = Driver::where('id', $driverId)
                ->orWhere('user_id', $driverId)
                ->first();
            $summary = DebtRecord::getSummaryForDriver($driver?->id ?? $driverId);

            return response()->json([
                'success' => true,
                'message' => 'Driver debt summary retrieved successfully',
                'data' => array_merge($summary, [
                    'driver_name' => $driver->name,
                ])
            ]);

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            Log::error('Error fetching driver debt summary: ' . $e->getMessage());

            return response()->json([
                'success' => false,
                'message' => 'Failed to fetch driver debt summary',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Get debt records for a specific driver
     */
    #[OA\Get(
        path: '/admin/payments/driver-debts/{driverId}',
        summary: 'Get driver debt records',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Payment'],
        parameters: [
            new OA\Parameter(name: 'limit', in: 'query', schema: new OA\Schema(type: 'string', default: '100')),
            new OA\Parameter(name: 'driverId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getDriverDebtRecords(string $driverId, Request $request): JsonResponse
    {
        try {
            $unpaidOnly = $request->boolean('unpaid_only', true);
            $limit = min($request->get('limit', 100), 500);

            // Normalize driver id
            $driver = Driver::where('id', $driverId)
                ->orWhere('user_id', $driverId)
                ->first();

            $query = DebtRecord::byDriver($driver?->id ?? $driverId)
                ->with('payment')
                ->orderBy('earning_date', 'desc');

            if ($unpaidOnly) {
                $query->unpaid();
            }

            $debtRecords = $query->limit($limit)->get();

            return response()->json([
                'success' => true,
                'message' => 'Driver debt records retrieved successfully',
                'data' => [
                    'debt_records' => $debtRecords->map->toApiResponse(),
                    'count' => $debtRecords->count()
                ]
            ]);

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            Log::error('Error fetching driver debt records: ' . $e->getMessage());

            return response()->json([
                'success' => false,
                'message' => 'Failed to fetch driver debt records',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Record a new payment and update debt records
     */
    #[OA\Post(
        path: '/admin/payments/record',
        summary: 'Record payment',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Payment'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['driver_id', 'amount', 'payment_channel', 'covers_days'],
                properties: [
                new OA\Property(property: 'driver_id', type: 'string'),
                new OA\Property(property: 'amount', type: 'number'),
                new OA\Property(property: 'payment_channel', type: 'string', enum: ['cash', 'mpesa', 'bank', 'mobile', 'other']),
                new OA\Property(property: 'covers_days', type: 'array', items: new OA\Items(type: 'string')),
                new OA\Property(property: 'remarks', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function recordPayment(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'driver_id' => ['required', new InAccount(Driver::class)],
            'amount' => 'required|numeric|min:0.01',
            'payment_channel' => 'required|in:cash,mpesa,bank,mobile,other',
            'covers_days' => 'required|array|min:1',
            'covers_days.*' => 'required|date',
            'remarks' => 'nullable|string|max:1000',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors()
            ], 422);
        }

        DB::beginTransaction();

        try {
            $driverId = $request->driver_id;
            $amount = $request->amount;
            $coversDays = $request->covers_days;

            // Get or create debt records for the specified days
            $debtRecords = collect();
            $totalExpectedAmount = 0;

            foreach ($coversDays as $date) {
                // Find existing debt record or create a new one
                $debtRecord = DebtRecord::firstOrCreate(
                    [
                        'driver_id' => $driverId,
                        'earning_date' => Carbon::parse($date)->format('Y-m-d')
                    ],
                    [
                        'expected_amount' => 10000, // Default expected amount - should be configurable
                        'paid_amount' => 0,
                        'is_paid' => false,
                    ]
                );

                // Only include unpaid debt records
                if (!$debtRecord->is_paid) {
                    $debtRecords->push($debtRecord);
                    $totalExpectedAmount += $debtRecord->remaining_amount;
                }
            }

            if ($debtRecords->isEmpty()) {
                DB::rollBack();
                return response()->json([
                    'success' => false,
                    'message' => 'No unpaid debt records found for the selected dates',
                ], 400);
            }

            // Create payment record
            $payment = Payment::create([
                'driver_id' => $driverId,
                'amount' => $amount,
                'payment_channel' => $request->payment_channel,
                'covers_days' => $coversDays,
                'remarks' => $request->remarks,
                'status' => 'completed',
                'payment_date' => now(),
                'recorded_by' => auth()->id() ?? 1, // Default to admin if not authenticated
                'receipt_status' => 'pending',
            ]);

            // Update debt records as paid
            $remainingAmount = $amount;
            $paidDays = [];

            foreach ($debtRecords as $debtRecord) {
                if ($remainingAmount <= 0)
                    break;

                $amountToPay = min($remainingAmount, $debtRecord->remaining_amount);

                // Mark debt record as paid
                $debtRecord->markAsPaid($payment, $debtRecord->paid_amount + $amountToPay);

                $paidDays[] = $debtRecord->earning_date->format('d/m/Y');
                $remainingAmount -= $amountToPay;
            }

            // Receipt will be generated manually later via the admin interface
            // Keep payment in 'pending' status for receipt generation

            DB::commit();

            // Log the successful payment
            Log::info("Payment recorded successfully", [
                'payment_id' => $payment->id,
                'reference_number' => $payment->reference_number,
                'driver_id' => $driverId,
                'amount' => $amount,
                'paid_days' => $paidDays
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Payment recorded successfully',
                'data' => [
                    'payment' => $payment->toApiResponse(),
                    'paid_days' => $paidDays,
                    'covered_days_count' => count($paidDays),
                    'total_amount_applied' => $amount - $remainingAmount,
                    'remaining_amount' => $remainingAmount,
                ]
            ], 201);

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            DB::rollBack();
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error recording payment: ' . $e->getMessage(), [
                'driver_id' => $request->driver_id,
                'amount' => $request->amount,
                'covers_days' => $request->covers_days
            ]);

            return response()->json([
                'success' => false,
                'message' => 'Failed to record payment',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Get payment history
     */
    #[OA\Get(
        path: '/admin/payments/history',
        summary: 'Get payment history',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Payment'],
        parameters: [
            new OA\Parameter(name: 'page', in: 'query', schema: new OA\Schema(type: 'string', default: '1')),
            new OA\Parameter(name: 'limit', in: 'query', schema: new OA\Schema(type: 'string', default: '20')),
            new OA\Parameter(name: 'driver_id', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'start_date', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'end_date', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getPaymentHistory(Request $request): JsonResponse
    {
        try {
            $page = $request->get('page', 1);
            $limit = min($request->get('limit', 20), 100);
            $driverId = $request->get('driver_id');
            $startDate = $request->get('start_date');
            $endDate = $request->get('end_date');

            $query = Payment::with(['driver', 'recordedBy'])
                ->orderBy('payment_date', 'desc');

            if ($driverId) {
                // Normalize driver id if a user id was passed
                $driver = Driver::where('id', $driverId)
                    ->orWhere('user_id', $driverId)
                    ->first();
                $query->byDriver($driver?->id ?? $driverId);
            }

            if ($startDate && $endDate) {
                $query->dateRange($startDate, $endDate);
            }

            $payments = $query->paginate($limit, ['*'], 'page', $page);

            $items = collect($payments->items())->map(function ($p) {
                return method_exists($p, 'toApiResponse') ? $p->toApiResponse() : $p;
            })->values();

            return response()->json([
                'success' => true,
                'message' => 'Payment history retrieved successfully',
                'data' => [
                    'payments' => $items,
                    'pagination' => [
                        'current_page' => $payments->currentPage(),
                        'per_page' => $payments->perPage(),
                        'total' => $payments->total(),
                        'total_pages' => $payments->lastPage(),
                    ]
                ]
            ]);

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            Log::error('Error fetching payment history: ' . $e->getMessage());

            return response()->json([
                'success' => false,
                'message' => 'Failed to fetch payment history',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Update a payment record
     */
    #[OA\Put(
        path: '/admin/payments/{paymentId}',
        summary: 'Update payment',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Payment'],
        parameters: [
            new OA\Parameter(name: 'paymentId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'amount', type: 'number', nullable: true),
                new OA\Property(property: 'payment_channel', type: 'string', enum: ['cash', 'mpesa', 'bank', 'mobile', 'other'], nullable: true),
                new OA\Property(property: 'remarks', type: 'string', nullable: true),
                new OA\Property(property: 'status', type: 'string', enum: ['pending', 'completed', 'cancelled'], nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function updatePayment(int $paymentId, Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'amount' => 'sometimes|numeric|min:0.01',
            'payment_channel' => 'sometimes|in:cash,mpesa,bank,mobile,other',
            'remarks' => 'nullable|string|max:1000',
            'status' => 'sometimes|in:pending,completed,cancelled',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors()
            ], 422);
        }

        try {
            $payment = Payment::findOrFail($paymentId);
            $payment->update($request->only(['amount', 'payment_channel', 'remarks', 'status']));

            return response()->json([
                'success' => true,
                'message' => 'Payment updated successfully',
                'data' => $payment->toApiResponse()
            ]);
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            Log::error('Error updating payment: ' . $e->getMessage());
            return response()->json([
                'success' => false,
                'message' => 'Failed to update payment',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Delete a payment record
     */
    #[OA\Delete(
        path: '/admin/payments/{paymentId}',
        summary: 'Delete payment',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Payment'],
        parameters: [
            new OA\Parameter(name: 'paymentId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function deletePayment(int $paymentId): JsonResponse
    {
        DB::beginTransaction();

        try {
            $payment = Payment::findOrFail($paymentId);

            // Reset associated debt records
            DebtRecord::where('payment_id', $paymentId)
                ->update([
                    'is_paid' => false,
                    'payment_id' => null,
                    'paid_at' => null,
                ]);

            $payment->delete();

            DB::commit();

            return response()->json([
                'success' => true,
                'message' => 'Payment deleted successfully and debt records reset'
            ]);

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            DB::rollBack();
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('Error deleting payment: ' . $e->getMessage());

            return response()->json([
                'success' => false,
                'message' => 'Failed to delete payment',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Get payment summary statistics
     */
    #[OA\Get(
        path: '/admin/payments/summary',
        summary: 'Get payment summary',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Payment'],
        parameters: [
            new OA\Parameter(name: 'start_date', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'end_date', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getPaymentSummary(Request $request): JsonResponse
    {
        try {
            $startDate = $request->get('start_date', now()->startOfMonth());
            $endDate = $request->get('end_date', now()->endOfMonth());

            // Payments aggregates
            $paymentsQuery = Payment::dateRange($startDate, $endDate);
            $totalPayments = (float) $paymentsQuery->sum('amount');
            $paymentCount = (int) $paymentsQuery->count();
            $averagePayment = $paymentCount > 0 ? $totalPayments / $paymentCount : 0.0;

            $paymentsByChannel = Payment::dateRange($startDate, $endDate)
                ->selectRaw('payment_channel, SUM(amount) as total, COUNT(*) as count')
                ->groupBy('payment_channel')
                ->get();

            // Debts aggregates (use expression, not accessor)
            $totalDebtsAmount = (float) DebtRecord::where('is_paid', false)
                ->selectRaw('COALESCE(SUM(COALESCE(expected_amount,0) - COALESCE(paid_amount,0)),0) as total')
                ->value('total');
            $overdueDebtsAmount = (float) DebtRecord::where('is_paid', false)
                ->where('days_overdue', '>', 0)
                ->selectRaw('COALESCE(SUM(COALESCE(expected_amount,0) - COALESCE(paid_amount,0)),0) as total')
                ->value('total');
            $debtsCount = (int) DebtRecord::where('is_paid', false)->count();

            // Receipts counts based on receipt_status convention
            $pendingReceiptsCount = (int) Payment::completed()->pendingReceipt()->count();
            $receiptsCount = (int) Payment::completed()
                ->whereIn('receipt_status', ['generated', 'sent', 'delivered'])
                ->count();

            return response()->json([
                'status' => 'success',
                'message' => 'Payment summary retrieved successfully',
                'data' => [
                    'period' => [
                        'start_date' => $startDate,
                        'end_date' => $endDate,
                    ],
                    'total_payments' => $totalPayments,
                    'payment_count' => $paymentCount,
                    'average_payment' => $averagePayment,
                    'payments_by_channel' => $paymentsByChannel,
                    // Provide multiple key aliases for frontend compatibility
                    'total_debts' => $totalDebtsAmount,
                    'outstanding_debts' => $totalDebtsAmount,
                    'overdue_debts' => $overdueDebtsAmount,
                    'debts_count' => $debtsCount,
                    'receipts_count' => $receiptsCount,
                    'pending_receipts_count' => $pendingReceiptsCount,
                ]
            ], 200);

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            Log::error('Error fetching payment summary: ' . $e->getMessage(), [
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'status' => 'error',
                'message' => 'Failed to fetch payment summary',
            ], 500);
        }
    }

    /**
     * Mark specific debt record as paid
     */
    #[OA\Put(
        path: '/admin/payments/mark-debt-paid/{debtId}',
        summary: 'Mark debt as paid',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Payment'],
        parameters: [
            new OA\Parameter(name: 'debtId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['payment_id'],
                properties: [
                new OA\Property(property: 'payment_id', type: 'integer'),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function markDebtAsPaid(int $debtId, Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'payment_id' => ['required', 'integer', new InAccount(Payment::class)],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors()
            ], 422);
        }

        try {
            $debtRecord = DebtRecord::findOrFail($debtId);
            $payment = Payment::findOrFail($request->payment_id);

            $debtRecord->markAsPaid($payment);

            return response()->json([
                'success' => true,
                'message' => 'Debt record marked as paid successfully',
                'data' => $debtRecord->toApiResponse()
            ]);

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            Log::error('Error marking debt as paid: ' . $e->getMessage());

            return response()->json([
                'success' => false,
                'message' => 'Failed to mark debt as paid',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Store a new monthly payment (not tied to debt clearance)
     */
    #[OA\Post(
        path: '/admin/payments/new',
        summary: 'Store new payment',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Payment'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['driver_id', 'amount', 'payment_date'],
                properties: [
                new OA\Property(property: 'driver_id', type: 'string'),
                new OA\Property(property: 'amount', type: 'number'),
                new OA\Property(property: 'payment_date', type: 'string', format: 'date'),
                new OA\Property(property: 'month_for', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function storeNewPayment(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'driver_id' => 'required',
            'amount' => 'required|numeric|min:0.01',
            'payment_date' => 'required|date',
            'month_for' => 'nullable|string', // YYYY-MM
            'notes' => 'nullable|string|max:1000',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'success' => false,
                'message' => 'Validation failed',
                'errors' => $validator->errors()
            ], 422);
        }

        try {
            $payment = new Payment();
            $payment->driver_id = $request->driver_id;
            $payment->amount = $request->amount;
            $payment->payment_channel = $request->get('payment_channel', 'cash');
            $payment->remarks = $request->notes;
            $payment->covers_days = null;
            $payment->status = 'completed';
            $payment->payment_date = Carbon::parse($request->payment_date);
            // Optional classification
            if (Schema::hasColumn('payments', 'payment_type')) {
                $payment->payment_type = 'new_payment';
            }
            // Store optional month_for inside remarks JSON-ish if column does not exist
            if ($request->filled('month_for')) {
                $payment->remarks = trim(($payment->remarks ? $payment->remarks . ' ' : '') . '(month_for: ' . $request->month_for . ')');
            }
            // recorded_by if available
            if ($request->user()) {
                $payment->recorded_by = $request->user()->id;
            }
            $payment->save();

            return response()->json([
                'success' => true,
                'message' => 'Payment recorded',
                'data' => $payment->toApiResponse(),
            ], 201);
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            Log::error('Error saving new payment: ' . $e->getMessage());
            return response()->json([
                'success' => false,
                'message' => 'Failed to record payment',
            ], 500);
        }
    }

    /**
     * Map of drivers who have new payments in a given month
     * GET /admin/payments/new-payments-map?month=YYYY-MM
     */
    #[OA\Get(
        path: '/admin/payments/new-payments-map',
        summary: 'Get new payments map',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Payment'],
        parameters: [
            new OA\Parameter(name: 'month', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getNewPaymentsMap(Request $request): JsonResponse
    {
        $month = $request->get('month');
        try {
            if (!Schema::hasColumn('payments', 'payment_type')) {
                return response()->json([
                    'success' => true,
                    'message' => 'No payment_type column; assuming none',
                    'data' => [
                        'month' => $month,
                        'drivers' => [],
                    ]
                ]);
            }

            $start = $month ? Carbon::createFromFormat('Y-m', $month)->startOfMonth() : now()->startOfMonth();
            $end = (clone $start)->endOfMonth();

            $rows = Payment::where('payment_type', 'new_payment')
                ->whereBetween('payment_date', [$start, $end])
                ->select('driver_id', DB::raw('COUNT(*) as count'))
                ->groupBy('driver_id')
                ->get()
                ->map(function ($r) {
                    return [
                        'driver_id' => (string) $r->driver_id,
                        'count' => (int) $r->count,
                    ];
                });

            return response()->json([
                'success' => true,
                'message' => 'New payments map',
                'data' => [
                    'month' => $start->format('Y-m'),
                    'drivers' => $rows,
                ],
            ]);
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to fetch map: ' . $e->getMessage(),
            ], 500);
        }
    }

    private function formatPeriod(int $days): string
    {
        if ($days <= 0)
            return '';
        if ($days === 1)
            return 'Siku 1';
        if ($days < 7)
            return $days . ' siku';
        if ($days < 14)
            return 'Wiki 1';
        if ($days < 21)
            return 'Wiki 2';
        if ($days < 30)
            return 'Wiki ' . round($days / 7);
        return 'Mwezi ' . round($days / 30);
    }

    private function buildReceiptDataForPayment(Payment $payment, array $paidDays): array
    {
        $driver = $payment->driver;
        // Whose receipt it is: the driver's own business (name, address, phone, TIN, logo), not the
        // platform's name -- every business's customers would otherwise read "Boda Mapato".
        $company = \App\Models\Business::identityForDriver($driver instanceof \App\Models\Driver ? $driver : null);
        return [
            'company_name' => $company['name'],
            'company_address' => $company['address'],
            'company_phone' => $company['phone'],
            'company_tin' => $company['tin'],
            'company_email' => $company['email'],
            'company_logo_url' => $company['logo_url'],
            'issue_date' => now()->format('d/m/Y'),
            'issue_time' => now()->format('H:i'),
            'driver_name' => $driver->name ?? '',
            'driver_phone' => $driver->phone ?? '',
            'vehicle_info' => $driver->vehicle_number ?? '',
            'payment_amount' => number_format((float) $payment->amount, 0),
            'amount_in_words' => '',
            'payment_channel' => $payment->formatted_payment_channel,
            'payment_date' => optional($payment->payment_date)->format('d/m/Y') ?? '',
            'covered_period' => $this->formatPeriod(count($payment->covers_days ?? [])),
            'covered_days_list' => $payment->covers_days ?? $paidDays,
            'remarks' => $payment->remarks ?? '',
            'recorded_by' => $payment->recordedBy->name ?? '',
        ];
    }
}
