<?php

namespace App\Http\Controllers\API\Rental;

use App\Http\Controllers\Controller;
use App\Services\Rental\RentalService;
use App\Models\Rental\RentBill;
use App\Models\Rental\RentalPayment;
use App\Models\Rental\RentalReceipt;
use App\Models\Rental\RentalAgreement;
use App\Helpers\ResponseHelper;
use Illuminate\Http\Request;
use Carbon\Carbon;
use OpenApi\Attributes as OA;

class BillingController extends Controller
{
    protected $rentalService;

    public function __construct(RentalService $rentalService)
    {
        $this->rentalService = $rentalService;
    }

    /**
     * Get all bills (for landlord or tenant).
     */
    #[OA\Get(
        path: '/rental/billing/bills',
        summary: 'Get bills',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Billing'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getBills(Request $request)
    {
        $user = $request->user();

        if ($user->isSuperAdmin()) {
            // Sees every landlord's bills, not scoped to any single owner.
            $bills = RentBill::with('agreement.tenant', 'agreement.house.property', 'payments.receipt')->get();
        } elseif ($user->role === 'tenant') {
            $bills = RentBill::whereHas('agreement', function ($query) use ($user) {
                $query->where('tenant_id', $user->id);
            })->with('agreement.house.property', 'payments.receipt')->get();
        } elseif ($user->role === 'caretaker') {
            // A caretaker works only the properties they are assigned to.
            $bills = RentBill::whereHas('agreement.house.property', function ($query) use ($user) {
                $query->where('caretaker_id', $user->id);
            })->with('agreement.tenant', 'agreement.house.property', 'payments.receipt')->get();
        } else {
            // Landlord, admin, or staff of that account: the account's whole portfolio.
            $bills = $this->ownedBills($request)
                ->with('agreement.tenant', 'agreement.house.property', 'payments.receipt')->get();
        }

        return ResponseHelper::success($bills);
    }

    /** Bills on properties the caller's account owns (super_admin: every bill). */
    private function ownedBills(Request $request)
    {
        $user = $request->user();

        return RentBill::query()->when(
            !$user->seesAllAccounts(),
            fn ($q) => $q->whereHas('agreement.house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            })
        );
    }

    /** Receipts for payments on properties the caller's account owns (super_admin: all). */
    private function ownedReceipts(Request $request)
    {
        $user = $request->user();

        return RentalReceipt::query()->when(
            !$user->seesAllAccounts(),
            fn ($q) => $q->whereHas('payment.bill.agreement.house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            })
        );
    }

    /**
     * Get all payments.
     */
    #[OA\Get(
        path: '/rental/payments',
        summary: 'Get payments',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Billing'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getPayments(Request $request)
    {
        $user = $request->user();

        $payments = RentalPayment::when(!$user->isSuperAdmin(), function ($q) use ($user) {
            $q->whereHas('bill.agreement.house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->with('bill.agreement.house.property', 'tenant', 'collector', 'receipt')
            ->orderBy('payment_date', 'desc')
            ->get();

        return ResponseHelper::success($payments);
    }

    /**
     * Get all receipts.
     */
    #[OA\Get(
        path: '/rental/receipts',
        summary: 'Get receipts',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Billing'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getReceipts(Request $request)
    {
        $user = $request->user();

        $receipts = RentalReceipt::when(!$user->isSuperAdmin(), function ($q) use ($user) {
            $q->whereHas('payment.bill.agreement.house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->with('payment.tenant', 'payment.bill.agreement.house.property', 'payment.collector', 'payment.receipt')
            ->orderBy('created_at', 'desc')
            ->get();

        return ResponseHelper::success($receipts);
    }

    /**
     * Get single receipt details.
     */
    #[OA\Get(
        path: '/rental/receipts/{id}',
        summary: 'Get receipt',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Billing'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getReceipt(Request $request, $id)
    {
        $receipt = $this->ownedReceipts($request)
            ->with('payment.tenant', 'payment.bill.agreement.house.property', 'payment.collector', 'payment.receipt')
            ->findOrFail($id);

        return ResponseHelper::success($receipt);
    }

    /**
     * Record a new payment.
     */
    #[OA\Post(
        path: '/rental/payments/record',
        summary: 'Record payment',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Billing'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['bill_id', 'amount_paid', 'payment_method'],
                properties: [
                new OA\Property(property: 'bill_id', type: 'string'),
                new OA\Property(property: 'amount_paid', type: 'number'),
                new OA\Property(property: 'payment_method', type: 'string', enum: ['cash', 'bank_transfer', 'm-pesa', 'airtel_money', 'tigo_pesa']),
                new OA\Property(property: 'transaction_reference', type: 'string', nullable: true),
                new OA\Property(property: 'payment_date', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'notes', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function recordPayment(Request $request)
    {
        $request->validate([
            'bill_id' => 'required|exists:rental_bills,id',
            'amount_paid' => 'required|numeric|min:1',
            'payment_method' => 'required|string|in:cash,bank_transfer,m-pesa,airtel_money,tigo_pesa',
            'transaction_reference' => 'nullable|string',
            'payment_date' => 'nullable|date',
            'notes' => 'nullable|string',
        ]);

        // `exists:` only proves the bill exists somewhere; this proves it is on a
        // property this account owns before any money is recorded against it.
        $this->ownedBills($request)->findOrFail($request->bill_id);

        try {
            $data = $request->all();
            $data['collector_id'] = $request->user()->id;

            $payment = $this->rentalService->recordPayment($data);
            $payment->load('bill.agreement.house.property', 'tenant', 'receipt');

            // The tenant's SMS is sent once, by the service, after the payment is saved.
            return ResponseHelper::success($payment, 'Payment recorded successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error($e->getMessage(), 500);
        }
    }

    /**
     * Dispatch receipt to tenant repository.
     */
    #[OA\Post(
        path: '/rental/receipts/{id}/dispatch',
        summary: 'Dispatch receipt',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Billing'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function dispatchReceipt(Request $request, $id)
    {
        // Only a receipt on this account's own properties (super_admin: any).
        // An admin is not exempt: admin is an account, not a platform, role.
        $receipt = $this->ownedReceipts($request)->findOrFail($id);

        $receipt->update(['is_dispatched' => true]);

        return ResponseHelper::success($receipt, 'Receipt sent to tenant successfully');
    }

    /**
     * Get dashboard statistics.
     */
    #[OA\Get(
        path: '/rental/dashboard',
        summary: 'Get dashboard',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Billing'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getDashboard(Request $request)
    {
        $user = $request->user();
        // super_admin's dashboard aggregates across every landlord instead
        // of being scoped to properties they personally own (typically none).
        $isSuperAdmin = $user->isSuperAdmin();

        // Total properties
        $totalProperties = \App\Models\Rental\Property::when(!$isSuperAdmin, fn($q) => $q->whereIn('owner_id', $user->accountMemberIds()))->count();

        // Total houses
        $totalHouses = \App\Models\Rental\House::when(!$isSuperAdmin, function ($q) use ($user) {
            $q->whereHas('property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->count();

        // Occupied houses
        $occupiedHouses = \App\Models\Rental\House::when(!$isSuperAdmin, function ($q) use ($user) {
            $q->whereHas('property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->where('status', 'occupied')->count();

        // Active tenants
        $activeTenants = RentalAgreement::when(!$isSuperAdmin, function ($q) use ($user) {
            $q->whereHas('house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->where('status', 'active')->count();

        // Monthly revenue this month
        $thisMonth = Carbon::now()->format('m-Y');
        $monthlyRevenue = RentalPayment::when(!$isSuperAdmin, function ($q) use ($user) {
            $q->whereHas('bill.agreement.house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->whereHas('bill', function ($query) use ($thisMonth) {
            $query->where('month_year', $thisMonth);
        })->sum('amount_paid');

        // Pending bills (unpaid + partial)
        $pendingBills = RentBill::when(!$isSuperAdmin, function ($q) use ($user) {
            $q->whereHas('agreement.house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->whereIn('status', ['unpaid', 'partial'])->count();

        // Overdue bills
        $overdueBills = RentBill::when(!$isSuperAdmin, function ($q) use ($user) {
            $q->whereHas('agreement.house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->where('status', 'overdue')->count();

        // Total arrears amount
        $totalArrears = RentBill::when(!$isSuperAdmin, function ($q) use ($user) {
            $q->whereHas('agreement.house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->whereIn('status', ['unpaid', 'partial', 'overdue'])->sum('balance');

        // Recent payments
        $recentPayments = RentalPayment::when(!$isSuperAdmin, function ($q) use ($user) {
            $q->whereHas('bill.agreement.house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->with('tenant', 'bill.agreement.house')->orderBy('payment_date', 'desc')->limit(5)->get();

        return ResponseHelper::success([
            'total_properties' => $totalProperties,
            'total_houses' => $totalHouses,
            'occupied_houses' => $occupiedHouses,
            'vacant_houses' => $totalHouses - $occupiedHouses,
            'active_tenants' => $activeTenants,
            'monthly_revenue' => $monthlyRevenue,
            'pending_bills' => $pendingBills,
            'overdue_bills' => $overdueBills,
            'total_arrears' => $totalArrears,
            'recent_payments' => $recentPayments,
        ]);
    }

    /**
     * Get arrears report.
     */
    #[OA\Get(
        path: '/rental/reports/arrears',
        summary: 'Get arrears',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Billing'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getArrears(Request $request)
    {
        $user = $request->user();

        $arrears = RentBill::when(!$user->isSuperAdmin(), function ($q) use ($user) {
            $q->whereHas('agreement.house.property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->whereIn('status', ['unpaid', 'partial', 'overdue'])
            ->with('agreement.tenant.user', 'agreement.house.property')
            ->orderBy('due_date', 'asc')
            ->get();

        // Group by status
        $byStatus = [
            'overdue' => $arrears->where('status', 'overdue'),
            'unpaid' => $arrears->where('status', 'unpaid'),
            'partial' => $arrears->where('status', 'partial'),
        ];

        return ResponseHelper::success([
            'arrears' => $arrears,
            'by_status' => $byStatus,
            'total_arrears' => $arrears->sum('balance'),
            'count' => $arrears->count(),
        ]);
    }

    /**
     * Get revenue report.
     */
    #[OA\Get(
        path: '/rental/reports/revenue',
        summary: 'Get revenue',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Billing'],
        parameters: [
            new OA\Parameter(name: 'period', in: 'query', schema: new OA\Schema(type: 'string', default: 'monthly')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getRevenue(Request $request)
    {
        $user = $request->user();
        $period = $request->get('period', 'monthly'); // monthly or yearly

        $isSuperAdmin = $user->isSuperAdmin();

        if ($period === 'yearly') {
            // Last 12 months
            $payments = RentalPayment::when(!$isSuperAdmin, function ($q) use ($user) {
                $q->whereHas('bill.agreement.house.property', function ($query) use ($user) {
                    $query->whereIn('owner_id', $user->accountMemberIds());
                });
            })->where('payment_date', '>=', now()->subMonths(12))
                ->get();

            // Group by month
            $revenue = $payments->groupBy(function ($p) {
                return $p->payment_date->format('m-Y');
            })->map(function ($group) {
                return $group->sum('amount_paid');
            });
        } else {
            // Last 30 days
            $payments = RentalPayment::when(!$isSuperAdmin, function ($q) use ($user) {
                $q->whereHas('bill.agreement.house.property', function ($query) use ($user) {
                    $query->whereIn('owner_id', $user->accountMemberIds());
                });
            })->where('payment_date', '>=', now()->subDays(30))
                ->get();

            // Group by date
            $revenue = $payments->groupBy(function ($p) {
                return $p->payment_date->format('d-m');
            })->map(function ($group) {
                return $group->sum('amount_paid');
            });
        }

        return ResponseHelper::success([
            'period' => $period,
            'revenue' => $revenue,
            'total' => $payments->sum('amount_paid'),
        ]);
    }

    /**
     * Get occupancy report.
     * GET /rental/reports/occupancy
     */
    #[OA\Get(
        path: '/rental/reports/occupancy',
        summary: 'Get occupancy',
        security: [['bearerAuth' => []]],
        tags: ['Rental / Billing'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getOccupancy(Request $request)
    {
        $user = $request->user();

        $isSuperAdmin = $user->isSuperAdmin();

        // Get all properties with house counts
        $properties = \App\Models\Rental\Property::when(!$isSuperAdmin, fn($q) => $q->whereIn('owner_id', $user->accountMemberIds()))
            ->withCount('houses')
            ->get();

        $totalHouses = $properties->sum('houses_count');
        $occupiedHouses = \App\Models\Rental\House::when(!$isSuperAdmin, function ($q) use ($user) {
            $q->whereHas('property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->where('status', 'occupied')->count();

        $vacantHouses = $totalHouses - $occupiedHouses;
        $maintenanceHouses = \App\Models\Rental\House::when(!$isSuperAdmin, function ($q) use ($user) {
            $q->whereHas('property', function ($query) use ($user) {
                $query->whereIn('owner_id', $user->accountMemberIds());
            });
        })->where('status', 'maintenance')->count();

        // Per property occupancy
        $byProperty = $properties->map(function ($property) {
            $occupied = $property->houses()->where('status', 'occupied')->count();
            $total = $property->houses()->count();
            return [
                'property_id' => $property->id,
                'property_name' => $property->name,
                'total_units' => $total,
                'occupied' => $occupied,
                'vacant' => $total - $occupied,
                'occupancy_rate' => $total > 0 ? round(($occupied / $total) * 100, 1) : 0,
            ];
        });

        return ResponseHelper::success([
            'summary' => [
                'total_units' => $totalHouses,
                'occupied' => $occupiedHouses,
                'vacant' => $vacantHouses,
                'maintenance' => $maintenanceHouses,
                'occupancy_rate' => $totalHouses > 0 ? round(($occupiedHouses / $totalHouses) * 100, 1) : 0,
            ],
            'by_property' => $byProperty,
        ]);
    }
}
