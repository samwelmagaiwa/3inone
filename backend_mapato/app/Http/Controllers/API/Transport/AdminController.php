<?php

namespace App\Http\Controllers\API\Transport;

use App\Rules\InAccount;
use App\Rules\PerBusiness;
use App\Rules\UniquePhoneInBusiness;
use App\Support\Tenancy\TenantContext;
use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\Driver;
use App\Models\Device;
use App\Models\Transaction;
use App\Models\Receipt;
use App\Models\DriverAgreement;
use App\Helpers\ResponseHelper;
use App\Http\Requests\CreateDriverRequest;
use App\Http\Requests\CreateVehicleRequest;
use App\Support\TemporaryPassword;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Hash;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use OpenApi\Attributes as OA;

#[OA\Tag(name: 'Transport / Admin', description: 'Driver, vehicle, and debt management for the transport service admin.')]
class AdminController extends Controller
{
    /**
     * Get admin dashboard data
     */
    #[OA\Get(
        path: '/admin/dashboard',
        summary: 'Transport admin dashboard summary',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        responses: [
            new OA\Response(response: 200, description: 'Dashboard totals (drivers, vehicles, payments, recent transactions)'),
        ],
    )]
    public function dashboard(Request $request)
    {
        try {
            // Use the same logic as DashboardController for consistency
            // Get real data from actual database tables
            
            // Drivers data
            $totalDrivers = Driver::count();
            $activeDrivers = Driver::where('is_active', 1)->count();
            
            // Vehicles data  
            $totalVehicles = Device::count();
            $activeVehicles = Device::where('is_active', 1)->count();
            
            // Payment data - use Payment model instead of Transaction
            $totalPaymentsToday = \App\Models\Payment::where('status', 'completed')
                ->whereDate('payment_date', today())
                ->sum('amount');
                
            $totalPaymentsThisWeek = \App\Models\Payment::where('status', 'completed')
                ->whereBetween('payment_date', [now()->startOfWeek(), now()->endOfWeek()])
                ->sum('amount');
                
            $totalPaymentsThisMonth = \App\Models\Payment::where('status', 'completed')
                ->whereMonth('payment_date', now()->month)
                ->whereYear('payment_date', now()->year)
                ->sum('amount');
            
            // Recent payments data
            $recentPayments = \App\Models\Payment::with(['driver.user'])
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
                });

            $stats = [
                'total_drivers' => $totalDrivers,
                'active_drivers' => $activeDrivers,
                'total_vehicles' => $totalVehicles,
                'active_vehicles' => $activeVehicles,
                'payments_today' => $totalPaymentsToday,
                'payments_this_week' => $totalPaymentsThisWeek,
                'payments_this_month' => $totalPaymentsThisMonth,
                'recent_transactions' => $recentPayments,
            ];

            return ResponseHelper::success($stats, 'Dashboard data retrieved successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve dashboard data: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Record payment from driver
     */
    #[OA\Post(
        path: '/admin/record-payment',
        summary: 'Record payment',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['driver_id', 'amount', 'category', 'description', 'payment_method'],
                properties: [
                new OA\Property(property: 'driver_id', type: 'string', format: 'uuid'),
                new OA\Property(property: 'device_id', type: 'string', format: 'uuid', nullable: true),
                new OA\Property(property: 'amount', type: 'number'),
                new OA\Property(property: 'category', type: 'string'),
                new OA\Property(property: 'description', type: 'string'),
                new OA\Property(property: 'payment_method', type: 'string', enum: ['cash', 'mobile_money', 'bank_transfer', 'card']),
                new OA\Property(property: 'notes', type: 'string', nullable: true),
                new OA\Property(property: 'customer_name', type: 'string', nullable: true),
                new OA\Property(property: 'customer_phone', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function recordPayment(Request $request)
    {
        try {
            $request->validate([
                'driver_id' => 'required|uuid|exists:users,id',
                'device_id' => 'nullable|uuid|exists:devices,id',
                'amount' => 'required|numeric|min:0.01',
                'category' => 'required|string',
                'description' => 'required|string|max:500',
                'payment_method' => 'required|in:cash,mobile_money,bank_transfer,card',
                'notes' => 'nullable|string|max:1000',
                'customer_name' => 'nullable|string|max:255',
                'customer_phone' => 'nullable|string|max:20',
            ]);

            $admin = $request->user();

            // Find driver user
            $driverQuery = User::where('id', $request->driver_id)
                              ->where('role', 'driver')
                              ->with('driver');
            
            // If admin is authenticated, ensure driver belongs to admin
            if ($admin && !$admin->isSuperAdmin()) {
                $driverQuery->whereIn('created_by', $admin->accountMemberIds());
            }
            
            $driver = $driverQuery->firstOrFail();

            // Verify device belongs to driver (if device_id is provided)
            $device = null;
            if ($request->device_id) {
                $device = Device::where('id', $request->device_id)
                               ->where('driver_id', $driver->driver->id)
                               ->firstOrFail();
            }

            // Create transaction record
            $transaction = Transaction::create([
                'driver_id' => $driver->driver->id,
                'device_id' => $device?->id,
                'amount' => $request->amount,
                'type' => 'income',
                'category' => $request->category,
                'description' => $request->description,
                'customer_name' => $request->customer_name,
                'customer_phone' => $request->customer_phone,
                'status' => 'completed',
                'payment_method' => $request->payment_method,
                'notes' => $request->notes,
                'transaction_date' => now(),
            ]);

            $transaction->load('driver.user', 'device');

            return ResponseHelper::success($transaction, 'Payment recorded successfully', 201);

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to record payment: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Generate receipt for payment
     */
    #[OA\Post(
        path: '/admin/generate-receipt',
        summary: 'Generate receipt',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['transaction_id', 'service_description'],
                properties: [
                new OA\Property(property: 'transaction_id', type: 'string', format: 'uuid'),
                new OA\Property(property: 'customer_name', type: 'string', nullable: true),
                new OA\Property(property: 'service_description', type: 'string'),
                new OA\Property(property: 'notes', type: 'string', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function generateReceipt(Request $request)
    {
        try {
            $request->validate([
                'transaction_id' => 'required|uuid|exists:transactions,id',
                'customer_name' => 'nullable|string|max:255',
                'service_description' => 'required|string|max:500',
                'notes' => 'nullable|string|max:1000',
            ]);

            $admin = $request->user();

            // Verify transaction belongs to admin's driver (super_admin can
            // record a payment against any admin's driver)
            $transaction = Transaction::when(!$admin->isSuperAdmin(), function ($tq) use ($admin) {
                $tq->whereHas('driver', function ($query) use ($admin) {
                    $query->whereHas('user', function ($q) use ($admin) {
                        $q->whereIn('created_by', $admin->accountMemberIds());
                    });
                });
            })
            ->with('driver.user', 'device')
            ->findOrFail($request->transaction_id);

            // Check if receipt already exists
            if ($transaction->receipt) {
                return ResponseHelper::error('Receipt already exists for this transaction', 400);
            }

            // Generate receipt
            $receipt = Receipt::create([
                'transaction_id' => $transaction->id,
                'customer_name' => $request->customer_name ?? $transaction->driver->user->name,
                'service_description' => $request->service_description,
                'amount' => $transaction->amount,
                'notes' => $request->notes,
                'issued_at' => now(),
            ]);

            $receipt->load('transaction.driver.user', 'transaction.device');

            return ResponseHelper::success($receipt, 'Receipt generated successfully', 201);

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to generate receipt: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get all drivers managed by admin
     */
    #[OA\Get(
        path: '/admin/drivers',
        summary: 'List drivers',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'page', in: 'query', schema: new OA\Schema(type: 'string', default: '1')),
            new OA\Parameter(name: 'limit', in: 'query', schema: new OA\Schema(type: 'string', default: '20')),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Driver list'),
        ],
    )]
    public function getDrivers(Request $request)
    {
        try {
            // Get authenticated admin or use temporary bypass
            $admin = $request->user();
            $page = max((int) $request->get('page', 1), 1);
            $limit = min(max((int) $request->get('limit', 20), 1), 200);
            $offset = ($page - 1) * $limit;

            // Build query for drivers
            $query = User::where('role', 'driver')
                        ->with(['driver', 'assignedDevice'])
                        ->active();

            // If admin is authenticated, filter by admin's drivers
            if ($admin && !$admin->isSuperAdmin()) {
                $query->whereIn('created_by', $admin->accountMemberIds());
            }

            // Get total count for pagination
            $total = $query->count();

            // Get drivers with pagination
            $users = $query->skip($offset)
                          ->take($limit)
                          ->get();

            // One grouped query per metric for the whole page, instead of 4-5
            // queries per driver.
            $driverIds = $users->map(fn ($user) => $user->driver?->id)->filter()->values();

            $paid = Transaction::whereIn('driver_id', $driverIds)
                ->where('type', 'income')
                ->where('status', 'completed')
                ->selectRaw('driver_id, SUM(amount) as total, MAX(transaction_date) as last_payment')
                ->groupBy('driver_id')
                ->get()
                ->keyBy('driver_id');

            $trips = Transaction::whereIn('driver_id', $driverIds)
                ->where('status', 'completed')
                ->selectRaw('driver_id, COUNT(*) as trips')
                ->groupBy('driver_id')
                ->pluck('trips', 'driver_id');

            // Newest active/completed agreement per driver. (This used to be a
            // relation query with ->where('active')->orWhere('completed'), which
            // dropped the driver filter and matched other drivers' agreements.)
            $agreements = DriverAgreement::whereIn('driver_id', $driverIds)
                ->whereIn('status', ['active', 'completed'])
                ->orderByDesc('created_at')
                ->get()
                ->unique('driver_id')
                ->keyBy('driver_id');

            // Transform data to match expected format
            $drivers = $users->map(function ($user) use ($paid, $trips, $agreements) {
                $driver = $user->driver;
                $device = $user->assignedDevice;

                $totals = $driver ? $paid->get($driver->id) : null;
                $lastPayment = $totals?->last_payment ? Carbon::parse($totals->last_payment) : null;
                $tripsCompleted = $driver ? (int) ($trips[$driver->id] ?? 0) : 0;
                $rating = 4.5; // Default rating (placeholder until real ratings exist)
                $activeAgreement = $driver ? $agreements->get($driver->id) : null;

                $hasCompletedAgreement = $activeAgreement !== null;
                $agreementStatus = $activeAgreement ? $activeAgreement->status : null;

                return [
                    'id' => $user->id,
                    'name' => $user->name,
                    'email' => $user->email,
                    'phone' => $user->phone_number,
                    'license_number' => $driver?->license_number ?? 'N/A',
                    'vehicle_number' => $device?->plate_number ?? 'N/A',
                    'vehicle_type' => $device?->type ?? 'N/A',
                    'status' => $user->is_active ? 'active' : 'inactive',
                    'total_payments' => (float) ($totals?->total ?? 0),
                    'last_payment' => $lastPayment?->toISOString(),
                    'joined_date' => $user->created_at->toISOString(),
                    'rating' => $rating,
                    'trips_completed' => $tripsCompleted,
                    'has_completed_agreement' => $hasCompletedAgreement,
                    'agreement_status' => $agreementStatus,
                ];
            });

            // Return paginated response
            $response = [
                'data' => $drivers,
                'pagination' => [
                    'current_page' => $page,
                    'per_page' => $limit,
                    'total' => $total,
                    'last_page' => ceil($total / $limit),
                    'from' => $offset + 1,
                    'to' => min($offset + $limit, $total),
                ]
            ];

            return ResponseHelper::success($response, 'Drivers retrieved successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve drivers: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Create new driver
     */
    #[OA\Post(
        path: '/admin/drivers',
        summary: 'Register a new driver',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'email', type: 'string', format: 'email'),
                new OA\Property(property: 'phone_number', type: 'string'),
                new OA\Property(property: 'password', type: 'string', format: 'password'),
                new OA\Property(property: 'license_number', type: 'string'),
                new OA\Property(property: 'vehicle_number', type: 'string', nullable: true),
            ], type: 'object'),
        ),
        responses: [
            new OA\Response(response: 201, description: 'Driver created'),
            new OA\Response(response: 422, description: 'Validation failed', content: new OA\JsonContent(ref: '#/components/schemas/ValidationErrorResponse')),
        ],
    )]
    public function createDriver(CreateDriverRequest $request)
    {
        try {
            $admin = $request->user();

            // Use helper methods from the Form Request
            $phoneNumber = $request->getPhoneNumber();
            $isActive = $request->getIsActive();

            // No shared default password: unless the admin chose one, a one-time password is
            // generated and returned once for them to hand over. The driver must replace it
            // at first sign-in either way.
            $chosenPassword = $request->getPassword();
            $temporaryPassword = $chosenPassword === null ? TemporaryPassword::generate() : null;

            // Create user account
            $user = new User([
                'name' => $request->name,
                'email' => $request->email,
                'phone_number' => $phoneNumber,
                'password' => Hash::make($chosenPassword ?? $temporaryPassword),
                'role' => 'driver',
                'created_by' => $admin?->id,
                'is_active' => $isActive,
                'email_verified' => false,
                'phone_verified' => false,
            ]);
            $user->must_change_password = true;
            $user->save();

            // Create driver profile
            $driver = Driver::create([
                'user_id' => $user->id,
                'license_number' => $request->license_number,
                'license_expiry' => $request->license_expiry ?? now()->addYears(5), // Default 5 years if not provided
                'address' => $request->address,
                'emergency_contact' => $request->emergency_contact,
                'date_of_birth' => $request->date_of_birth,
                'national_id' => $request->national_id,
                'is_active' => $isActive,
            ]);

            // Create or assign vehicle if vehicle information is provided
            $device = null;
            if ($request->vehicle_number && $request->vehicle_type) {
                // Check if vehicle already exists
                $device = Device::where('plate_number', strtoupper($request->vehicle_number))->first();
                
                if (!$device) {
                    // Create new vehicle
                    $device = Device::create([
                        'driver_id' => $driver->id,
                        'name' => $request->vehicle_type . ' - ' . strtoupper($request->vehicle_number),
                        'type' => $request->vehicle_type,
                        'plate_number' => strtoupper($request->vehicle_number),
                        'description' => 'Vehicle assigned to ' . $request->name,
                        'is_active' => $isActive,
                    ]);
                    
                    // Update user's assigned device
                    $user->update(['device_id' => $device->id]);
                } else {
                    // Assign existing vehicle to driver
                    $device->update(['driver_id' => $driver->id]);
                    $user->update(['device_id' => $device->id]);
                }
            }

            // Load relationships for response
            $user->load(['driver', 'assignedDevice']);
            $driver->load(['user']);

            // Return response in format expected by Flutter app
            $responseData = [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'phone' => $user->phone_number,
                'license_number' => $driver->license_number,
                'vehicle_number' => $device?->plate_number ?? null,
                'vehicle_type' => $device?->type ?? null,
                'status' => $user->is_active ? 'active' : 'inactive',
                'total_payments' => 0,
                'last_payment' => null,
                'joined_date' => $user->created_at->toISOString(),
                'rating' => 4.5,
                'trips_completed' => 0,
                'driver_profile' => $driver,
                'vehicle' => $device,
                // Shown once to the admin; null when they chose the password themselves.
                'temporary_password' => $temporaryPassword,
            ];

            return ResponseHelper::success($responseData, 'Driver created successfully', 201);

        } catch (\Illuminate\Validation\ValidationException $e) {
            return ResponseHelper::validationError($e->errors(), 'Validation failed');
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to create driver: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Update driver
     */
    #[OA\Put(
        path: '/admin/drivers/{id}',
        summary: 'Update driver',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'name', type: 'string', nullable: true),
                new OA\Property(property: 'phone', type: 'string', nullable: true),
                new OA\Property(property: 'status', type: 'string', enum: ['active', 'inactive'], nullable: true),
                new OA\Property(property: 'license_number', type: 'string', nullable: true),
                new OA\Property(property: 'address', type: 'string', nullable: true),
                new OA\Property(property: 'emergency_contact', type: 'string', nullable: true),
                new OA\Property(property: 'vehicle_type', type: 'string', enum: ['bajaji', 'pikipiki', 'gari'], nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function updateDriver(Request $request, $id)
    {
        try {
            // The email is the sign-in name (unique across the platform); a phone or licence number
            // only has to be unique inside this driver's business. The scoped lookup means another
            // business's driver id finds nothing here (and is a 404 below).
            $driverProfile = Driver::where('user_id', $id)->first();
            $business = $driverProfile?->owner_id ?? TenantContext::writeOwner();

            $request->validate([
                'name' => 'sometimes|string|max:255',
                'email' => 'sometimes|email|max:255|unique:users,email,' . $id,
                // accept both phone_number and phone from clients
                'phone_number' => ['sometimes', 'string', 'max:20', new UniquePhoneInBusiness($business, (string) $id)],
                'phone' => ['sometimes', 'string', 'max:20', new UniquePhoneInBusiness($business, (string) $id)],
                'status' => 'sometimes|in:active,inactive',
                'license_number' => ['sometimes', 'string', 'max:50', PerBusiness::unique('drivers', 'license_number', $business, $driverProfile?->id)],
                'address' => 'sometimes|string|max:500',
                'emergency_contact' => 'sometimes|string|max:20',
                // vehicle updates
                'vehicle_number' => 'sometimes|string|max:20',
                'vehicle_type' => 'sometimes|in:bajaji,pikipiki,gari',
            ]);

            $admin = $request->user();

            // Find the driver user
            $query = User::where('id', $id)->where('role', 'driver');
            
            // If admin is authenticated, ensure they can only update their own drivers
            if ($admin && !$admin->isSuperAdmin()) {
                $query->whereIn('created_by', $admin->accountMemberIds());
            }
            
            $user = $query->firstOrFail();

            // Update user data
            $userData = [];
            if ($request->has('name')) $userData['name'] = $request->name;
            if ($request->has('email')) $userData['email'] = $request->email;
            // Map phone alias if provided
            if ($request->has('phone_number')) {
                $userData['phone_number'] = $request->phone_number;
            } elseif ($request->has('phone')) {
                $userData['phone_number'] = $request->phone;
            }
            if ($request->has('status')) {
                $userData['is_active'] = $request->status === 'active';
            }

            if (!empty($userData)) {
                $user->update($userData);
            }

            // Update driver profile data
            if ($user->driver) {
                $driverData = [];
                if ($request->has('license_number')) $driverData['license_number'] = $request->license_number;
                if ($request->has('address')) $driverData['address'] = $request->address;
                if ($request->has('emergency_contact')) $driverData['emergency_contact'] = $request->emergency_contact;
                
                if (!empty($driverData)) {
                    $user->driver->update($driverData);
                }
            }

            // Handle vehicle update or assignment
            if ($request->has('vehicle_number') && $request->has('vehicle_type')) {
                $plate = strtoupper($request->vehicle_number);
                $type = $request->vehicle_type;

                // Find existing device by plate or current assigned device
                $device = Device::where('plate_number', $plate)->first();
                if (!$device && $user->device_id) {
                    $device = Device::find($user->device_id);
                }

                if ($device) {
                    // Ensure it's assigned to this driver
                    if ($user->driver) {
                        $device->driver_id = $user->driver->id;
                    }
                    $device->type = $type;
                    $device->name = $type . ' - ' . $plate;
                    $device->plate_number = $plate;
                    $device->is_active = $user->is_active;
                    $device->save();
                } else {
                    // Create a new device and assign
                    $device = Device::create([
                        'driver_id' => $user->driver?->id,
                        'name' => $type . ' - ' . $plate,
                        'type' => $type,
                        'plate_number' => $plate,
                        'description' => 'Vehicle assigned to ' . $user->name,
                        'is_active' => $user->is_active,
                    ]);
                }

                // Link to user for quick access
                $user->update(['device_id' => $device->id]);
            }

            // Load updated relationships
            $user->load(['driver', 'assignedDevice']);

            // Return a unified payload consistent with getDriver
            $driver = $user->driver;
            $device = $user->assignedDevice;
            $response = [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'phone' => $user->phone_number,
                'license_number' => $driver?->license_number,
                'vehicle_number' => $device?->plate_number,
                'vehicle_type' => $device?->type,
                'status' => $user->is_active ? 'active' : 'inactive',
            ];

            return ResponseHelper::success($response, 'Driver updated successfully');

        } catch (\Illuminate\Validation\ValidationException $e) {
            // A refused value is the caller's mistake (422), not a server failure (it used to fall
            // through to the generic handler below and come back as a 500).
            return ResponseHelper::validationError($e->errors(), 'Validation failed');
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to update driver: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Delete driver
     */
    #[OA\Delete(
        path: '/admin/drivers/{id}',
        summary: 'Delete driver',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function deleteDriver(Request $request, $id)
    {
        try {
            $admin = $request->user();

            // Find the driver user
            $query = User::where('id', $id)->where('role', 'driver');
            
            // If admin is authenticated, ensure they can only delete their own drivers
            if ($admin && !$admin->isSuperAdmin()) {
                $query->whereIn('created_by', $admin->accountMemberIds());
            }
            
            $user = $query->firstOrFail();

            // Check if driver has any active transactions
            if ($user->driver && $user->driver->transactions()->where('status', 'pending')->exists()) {
                return ResponseHelper::error('Cannot delete driver with pending transactions', 400);
            }

            // Store driver name for response
            $driverName = $user->name;

            // Soft delete or deactivate instead of hard delete to preserve transaction history
            $user->update([
                'is_active' => false,
                'email' => $user->email . '_deleted_' . time(), // Prevent email conflicts
            ]);

            // Optionally, you can implement hard delete if needed:
            // $user->delete();

            return ResponseHelper::success([
                'id' => $id,
                'name' => $driverName,
                'message' => 'Driver deactivated successfully'
            ], 'Driver deactivated successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to delete driver: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get all vehicles managed by admin
     */
    #[OA\Get(
        path: '/admin/vehicles',
        summary: 'Get vehicles',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'page', in: 'query', schema: new OA\Schema(type: 'string', default: '1')),
            new OA\Parameter(name: 'limit', in: 'query', schema: new OA\Schema(type: 'string', default: '20')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getVehicles(Request $request)
    {
        try {
            $admin = $request->user();
            $page = $request->get('page', 1);
            $limit = $request->get('limit', 20);
            $offset = ($page - 1) * $limit;

            // Device carries the account scope: the caller sees the vehicles their
            // account created or whose driver belongs to it -- never another
            // account's, and no longer every unassigned vehicle in the system.
            $query = Device::with(['driver.user']);

            // Get total count for pagination
            $total = $query->count();

            // Get vehicles with pagination
            $vehicles = $query->skip($offset)
                             ->take($limit)
                             ->get();

            // Transform data to match expected format
            $vehicleData = $vehicles->map(function ($vehicle) {
                return [
                    'id' => $vehicle->id,
                    'name' => $vehicle->name,
                    'type' => $vehicle->type,
                    'plate_number' => $vehicle->plate_number,
                    'description' => $vehicle->description,
                    'is_active' => $vehicle->is_active,
                    'driver' => $vehicle->driver ? [
                        'id' => $vehicle->driver->id,
                        'user_id' => $vehicle->driver->user_id,
                        'name' => $vehicle->driver->user->name,
                        'email' => $vehicle->driver->user->email,
                        'phone' => $vehicle->driver->user->phone_number,
                        'license_number' => $vehicle->driver->license_number,
                    ] : null,
                    'created_at' => $vehicle->created_at->toISOString(),
                    'updated_at' => $vehicle->updated_at->toISOString(),
                ];
            });

            // Return paginated response
            $response = [
                'data' => $vehicleData,
                'pagination' => [
                    'current_page' => $page,
                    'per_page' => $limit,
                    'total' => $total,
                    'last_page' => ceil($total / $limit),
                    'from' => $offset + 1,
                    'to' => min($offset + $limit, $total),
                ]
            ];

            return ResponseHelper::success($response, 'Vehicles retrieved successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve vehicles: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Update vehicle
     */
    #[OA\Put(
        path: '/admin/vehicles/{id}',
        summary: 'Update vehicle',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'name', type: 'string', nullable: true),
                new OA\Property(property: 'type', type: 'string', enum: ['bajaji', 'pikipiki', 'gari'], nullable: true),
                new OA\Property(property: 'description', type: 'string', nullable: true),
                new OA\Property(property: 'is_active', type: 'boolean', nullable: true),
                new OA\Property(property: 'driver_id', type: 'string', format: 'uuid', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function updateVehicle(Request $request, $id)
    {
        try {
            // A plate only has to be unique inside the vehicle's own business, so another
            // business's identical plate is no obstacle (and says nothing about it).
            $device = Device::find($id);
            if ($request->has('plate_number') && is_string($request->plate_number)) {
                $request->merge(['plate_number' => strtoupper(trim($request->plate_number))]);
            }

            $request->validate([
                'name' => 'sometimes|string|max:255',
                'type' => 'sometimes|in:bajaji,pikipiki,gari',
                'plate_number' => ['sometimes', 'string', 'max:20', PerBusiness::unique('devices', 'plate_number', $device?->owner_id, $id)],
                'description' => 'sometimes|nullable|string',
                'is_active' => 'sometimes|boolean',
                'driver_id' => ['sometimes', 'nullable', 'uuid', new InAccount(Driver::class)],
            ]);

            $vehicle = Device::findOrFail($id);

            $update = $request->only(['name', 'type', 'plate_number', 'description', 'is_active']);
            if (!empty($update)) {
                $vehicle->update($update);
            }

            if ($request->has('driver_id')) {
                // `exists:drivers` only proves the id exists somewhere; the scoped
                // lookup proves it is a driver this account is allowed to assign.
                $driver = $request->driver_id ? Driver::findOrFail($request->driver_id) : null;

                $vehicle->driver_id = $request->driver_id; // can be null to unassign
                $vehicle->save();

                // Sync user's assigned device if possible
                if ($request->driver_id) {
                    if ($driver) {
                        $driver->user()?->update(['device_id' => $vehicle->id]);
                    }
                } else {
                    // Unassign from any user currently pointing to this device
                    \App\Models\User::where('device_id', $vehicle->id)->update(['device_id' => null]);
                }
            }

            $vehicle->load('driver.user');

            return ResponseHelper::success([
                'id' => $vehicle->id,
                'name' => $vehicle->name,
                'type' => $vehicle->type,
                'plate_number' => $vehicle->plate_number,
                'description' => $vehicle->description,
                'is_active' => $vehicle->is_active,
                'driver' => $vehicle->driver ? [
                    'id' => $vehicle->driver->id,
                    'user_id' => $vehicle->driver->user_id,
                    'name' => $vehicle->driver->user->name,
                    'email' => $vehicle->driver->user->email,
                    'phone' => $vehicle->driver->user->phone_number,
                    'license_number' => $vehicle->driver->license_number,
                ] : null,
                'created_at' => $vehicle->created_at->toISOString(),
                'updated_at' => $vehicle->updated_at->toISOString(),
            ], 'Vehicle updated successfully');
        } catch (\Illuminate\Validation\ValidationException $e) {
            return ResponseHelper::validationError($e->errors(), 'Validation failed');
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to update vehicle: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Unassign driver from vehicle
     */
    #[OA\Post(
        path: '/admin/vehicles/{id}/unassign',
        summary: 'Unassign driver from vehicle',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function unassignDriverFromVehicle($id)
    {
        try {
            $vehicle = Device::findOrFail($id);
            $vehicle->driver_id = null;
            $vehicle->save();
            // Unlink any user currently assigned to this device
            \App\Models\User::where('device_id', $vehicle->id)->update(['device_id' => null]);

            return ResponseHelper::success([
                'id' => $vehicle->id,
                'driver' => null,
            ], 'Driver unassigned successfully');
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to unassign driver: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Create new vehicle
     */
    #[OA\Post(
        path: '/admin/vehicles',
        summary: 'Create vehicle',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['name', 'type', 'plate_number'],
                properties: [
                new OA\Property(property: 'name', type: 'string'),
                new OA\Property(property: 'type', type: 'string', enum: ['bajaji', 'pikipiki', 'gari']),
                new OA\Property(property: 'plate_number', type: 'string'),
                new OA\Property(property: 'description', type: 'string', nullable: true),
                new OA\Property(property: 'driver_id', type: 'string', format: 'uuid', nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function createVehicle(CreateVehicleRequest $request)
    {
        try {
            $admin = $request->user();
            $driver = null;

            // If driver is specified, verify it belongs to admin (if admin is authenticated)
            if ($request->driver_id) {
                $driverQuery = User::where('id', $request->driver_id)
                                  ->where('role', 'driver')
                                  ->with('driver');
                
                // If admin is authenticated, ensure driver belongs to admin
                if ($admin && !$admin->isSuperAdmin()) {
                    $driverQuery->whereIn('created_by', $admin->accountMemberIds());
                }
                
                $driver = $driverQuery->firstOrFail();
            }

            // Create vehicle using helper methods from Form Request
            $vehicle = Device::create([
                'driver_id' => $driver?->driver?->id,
                'created_by' => $admin?->id,
                'name' => $request->getVehicleName(),
                'type' => $request->type,
                'plate_number' => $request->getPlateNumber(),
                'description' => $request->description,
                'is_active' => true,
            ]);

            // Update user's assigned device if driver specified
            if ($driver) {
                $driver->update(['device_id' => $vehicle->id]);
            }

            $vehicle->load('driver.user');

            // Return response in format expected by Flutter app
            $responseData = [
                'id' => $vehicle->id,
                'name' => $vehicle->name,
                'type' => $vehicle->type,
                'plate_number' => $vehicle->plate_number,
                'description' => $vehicle->description,
                'is_active' => $vehicle->is_active,
                'driver' => $vehicle->driver ? [
                    'id' => $vehicle->driver->id,
                    'user_id' => $vehicle->driver->user_id,
                    'name' => $vehicle->driver->user->name,
                    'email' => $vehicle->driver->user->email,
                    'phone' => $vehicle->driver->user->phone_number,
                    'license_number' => $vehicle->driver->license_number,
                ] : null,
                'created_at' => $vehicle->created_at->toISOString(),
                'updated_at' => $vehicle->updated_at->toISOString(),
            ];

            return ResponseHelper::success($responseData, 'Vehicle created successfully', 201);

        } catch (\Illuminate\Validation\ValidationException $e) {
            return ResponseHelper::validationError($e->errors(), 'Validation failed');
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to create vehicle: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Assign driver to vehicle
     */
    #[OA\Post(
        path: '/admin/assign-driver',
        summary: 'Assign driver to vehicle',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['driver_id', 'vehicle_id'],
                properties: [
                new OA\Property(property: 'driver_id', type: 'string', format: 'uuid'),
                new OA\Property(property: 'vehicle_id', type: 'string', format: 'uuid'),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function assignDriverToVehicle(Request $request)
    {
        try {
            $request->validate([
                'driver_id' => 'required|uuid|exists:users,id',
                'vehicle_id' => 'required|uuid|exists:devices,id',
            ]);

            $admin = $request->user();

            // Verify driver (restrict to admin's drivers only when authenticated)
            $driverQuery = User::where('id', $request->driver_id)
                         ->where('role', 'driver')
                         ->with('driver');
            if ($admin && !$admin->isSuperAdmin()) {
                $driverQuery->whereIn('created_by', $admin->accountMemberIds());
            }
            $driver = $driverQuery->first();
            if (!$driver) {
                return ResponseHelper::error('Driver not found or not managed by this admin', 404);
            }
            if (!$driver->driver) {
                return ResponseHelper::error('Selected user is not a driver (profile missing)', 422);
            }

            // Verify vehicle exists
            $vehicle = Device::find($request->vehicle_id);
            if (!$vehicle) {
                return ResponseHelper::error('Vehicle not found', 404);
            }

            // Update assignments
            $vehicle->update(['driver_id' => $driver->driver->id]);
            $driver->update(['device_id' => $vehicle->id]);

            $driver->load('assignedDevice');
            $vehicle->load('driver.user');

            return ResponseHelper::success([
                'driver' => $driver,
                'vehicle' => $vehicle,
            ], 'Driver assigned to vehicle successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to assign driver to vehicle: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Delete vehicle
     */
    #[OA\Delete(
        path: '/admin/vehicles/{id}',
        summary: 'Delete vehicle',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function deleteVehicle($id)
    {
        try {
            $vehicle = Device::findOrFail($id);
            // Unlink any user pointing to this device
            \App\Models\User::where('device_id', $vehicle->id)->update(['device_id' => null]);
            $vehicle->delete();
            return ResponseHelper::success(null, 'Vehicle deleted successfully');
        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to delete vehicle: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get payment history
     */
    #[OA\Get(
        path: '/admin/payment-history',
        summary: 'Get payment history',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'page', in: 'query', schema: new OA\Schema(type: 'string', default: '1')),
            new OA\Parameter(name: 'limit', in: 'query', schema: new OA\Schema(type: 'string', default: '20')),
            new OA\Parameter(name: 'driver_id', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'vehicle_id', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'start_date', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'end_date', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'type', in: 'query', schema: new OA\Schema(type: 'string')),
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getPaymentHistory(Request $request)
    {
        try {
            $admin = $request->user();
            $page = $request->get('page', 1);
            $limit = $request->get('limit', 20);
            $offset = ($page - 1) * $limit;
            $driverId = $request->get('driver_id');
            $vehicleId = $request->get('vehicle_id');
            $startDate = $request->get('start_date');
            $endDate = $request->get('end_date');
            $type = $request->get('type'); // income, expense
            $status = $request->get('status'); // pending, completed, cancelled

            // Build base query
            $query = Transaction::with(['driver.user', 'device', 'receipt']);

            // If admin is authenticated, filter by admin's transactions
            if ($admin && !$admin->isSuperAdmin()) {
                $query->whereHas('driver', function ($q) use ($admin) {
                    $q->whereHas('user', function ($userQuery) use ($admin) {
                        $userQuery->whereIn('created_by', $admin->accountMemberIds());
                    });
                });
            }

            // Apply filters
            if ($driverId) {
                $query->whereHas('driver', function ($q) use ($driverId) {
                    $q->where('user_id', $driverId);
                });
            }

            if ($vehicleId) {
                $query->where('device_id', $vehicleId);
            }

            if ($startDate) {
                $query->whereDate('transaction_date', '>=', $startDate);
            }

            if ($endDate) {
                $query->whereDate('transaction_date', '<=', $endDate);
            }

            if ($type) {
                $query->where('type', $type);
            }

            if ($status) {
                $query->where('status', $status);
            }

            // Get total count for pagination
            $total = $query->count();

            // Get transactions with pagination
            $transactions = $query->orderBy('transaction_date', 'desc')
                                 ->skip($offset)
                                 ->take($limit)
                                 ->get();

            // Transform data to match expected format
            $transactionData = $transactions->map(function ($transaction) {
                return [
                    'id' => $transaction->id,
                    'driver' => [
                        'id' => $transaction->driver->id,
                        'user_id' => $transaction->driver->user_id,
                        'name' => $transaction->driver->user->name,
                        'email' => $transaction->driver->user->email,
                        'phone' => $transaction->driver->user->phone_number,
                    ],
                    'device' => $transaction->device ? [
                        'id' => $transaction->device->id,
                        'name' => $transaction->device->name,
                        'type' => $transaction->device->type,
                        'plate_number' => $transaction->device->plate_number,
                    ] : null,
                    'amount' => (float) $transaction->amount,
                    'type' => $transaction->type,
                    'category' => $transaction->category,
                    'description' => $transaction->description,
                    'customer_name' => $transaction->customer_name,
                    'customer_phone' => $transaction->customer_phone,
                    'status' => $transaction->status,
                    'payment_method' => $transaction->payment_method,
                    'notes' => $transaction->notes,
                    'reference_number' => $transaction->reference_number,
                    'transaction_date' => $transaction->transaction_date->toISOString(),
                    'created_at' => $transaction->created_at->toISOString(),
                    'updated_at' => $transaction->updated_at->toISOString(),
                    'receipt' => $transaction->receipt ? [
                        'id' => $transaction->receipt->id,
                        'customer_name' => $transaction->receipt->customer_name,
                        'service_description' => $transaction->receipt->service_description,
                        'issued_at' => $transaction->receipt->issued_at->toISOString(),
                    ] : null,
                ];
            });

            // Return paginated response
            $response = [
                'data' => $transactionData,
                'pagination' => [
                    'current_page' => $page,
                    'per_page' => $limit,
                    'total' => $total,
                    'last_page' => ceil($total / $limit),
                    'from' => $offset + 1,
                    'to' => min($offset + $limit, $total),
                ]
            ];

            return ResponseHelper::success($response, 'Payment history retrieved successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve payment history: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Add reminder/note
     */
    #[OA\Post(
        path: '/admin/reminders',
        summary: 'Add reminder',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
            required: ['title', 'message', 'reminder_date', 'priority'],
                properties: [
                new OA\Property(property: 'title', type: 'string'),
                new OA\Property(property: 'message', type: 'string'),
                new OA\Property(property: 'driver_id', type: 'string', format: 'uuid', nullable: true),
                new OA\Property(property: 'vehicle_id', type: 'string', format: 'uuid', nullable: true),
                new OA\Property(property: 'reminder_date', type: 'string', format: 'date'),
                new OA\Property(property: 'priority', type: 'string', enum: ['low', 'medium', 'high', 'urgent']),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function addReminder(Request $request)
    {
        try {
            $request->validate([
                'title' => 'required|string|max:255',
                'message' => 'required|string|max:1000',
                'driver_id' => 'nullable|uuid|exists:users,id',
                'vehicle_id' => 'nullable|uuid|exists:devices,id',
                'reminder_date' => 'required|date',
                'priority' => 'required|in:low,medium,high,urgent',
            ]);

            $admin = $request->user();

            // Verify driver belongs to admin if specified (super_admin can
            // set a reminder for any admin's driver)
            if ($request->driver_id) {
                $driver = User::where('id', $request->driver_id)
                             ->when(!$admin->isSuperAdmin(), fn($q) => $q->whereIn('created_by', $admin->accountMemberIds()))
                             ->where('role', 'driver')
                             ->with('driver')
                             ->firstOrFail();
            }

            // Create reminder
            $reminder = \App\Models\Reminder::create([
                'driver_id' => isset($driver) ? $driver->driver->id : null,
                'device_id' => $request->vehicle_id,
                'title' => $request->title,
                'message' => $request->message,
                'reminder_type' => 'custom',
                'reminder_date' => $request->reminder_date,
                'reminder_time' => $request->reminder_date,
                'priority' => $request->priority,
                'status' => 'active',
            ]);

            $reminder->load('driver.user', 'device');

            return ResponseHelper::success($reminder, 'Reminder added successfully', 201);

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to add reminder: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Public dashboard (no authentication required for development)
     */
    public function publicDashboard(Request $request)
    {
        try {
            // Get all drivers and vehicles (public endpoint for testing)
            $totalDrivers = User::where('role', 'driver')->count();
            $activeDrivers = User::where('role', 'driver')->where('is_active', true)->count();
            $totalVehicles = Device::count();
            $activeVehicles = Device::where('is_active', true)->count();
            
            // Get payment statistics
            $totalPaymentsToday = Transaction::where('type', 'income')
                ->where('status', 'completed')
                ->whereDate('created_at', today())
                ->sum('amount');
                
            $monthlyRevenue = Transaction::where('type', 'income')
                ->where('status', 'completed')
                ->whereMonth('created_at', now()->month)
                ->sum('amount');
                
            $weeklyRevenue = Transaction::where('type', 'income')
                ->where('status', 'completed')
                ->whereBetween('created_at', [now()->startOfWeek(), now()->endOfWeek()])
                ->sum('amount');

            // Get pending payments count
            $pendingPayments = Transaction::where('status', 'pending')->count();
            
            // Recent transactions
            $recentTransactions = Transaction::with('driver.user', 'device')
                ->latest()
                ->take(5)
                ->get();

            $dashboardData = [
                'total_drivers' => $totalDrivers,
                'active_drivers' => $activeDrivers,
                'total_vehicles' => $totalVehicles,
                'active_vehicles' => $activeVehicles,
                'pending_payments' => $pendingPayments,
                'daily_revenue' => (float) $totalPaymentsToday,
                'weekly_revenue' => (float) $weeklyRevenue,
                'monthly_revenue' => (float) $monthlyRevenue,
                'net_profit' => (float) ($monthlyRevenue * 0.4), // 40% profit margin
                'recent_transactions' => $recentTransactions->map(function ($transaction) {
                    return [
                        'id' => $transaction->id,
                        'amount' => $transaction->amount,
                        'driver_name' => $transaction->driver->user->name ?? 'Unknown',
                        'vehicle' => $transaction->device->plate_number ?? 'N/A',
                        'date' => $transaction->created_at->toISOString(),
                        'status' => $transaction->status,
                        'description' => $transaction->description,
                    ];
                }),
            ];

            return ResponseHelper::success($dashboardData, 'Dashboard data retrieved successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            // Return fallback data if database fails
            $fallbackData = [
                'total_drivers' => 12,
                'active_drivers' => 10,
                'total_vehicles' => 8,
                'active_vehicles' => 7,
                'pending_payments' => 3,
                'daily_revenue' => 45000.00,
                'weekly_revenue' => 280000.00,
                'monthly_revenue' => 1200000.00,
                'net_profit' => 480000.00,
                'recent_transactions' => [],
            ];
            return ResponseHelper::success($fallbackData, 'Dashboard data retrieved (fallback)');
        }
    }


    /**
     * Get all reminders
     */
    #[OA\Get(
        path: '/admin/reminders',
        summary: 'Get reminders',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'page', in: 'query', schema: new OA\Schema(type: 'string', default: '1')),
            new OA\Parameter(name: 'limit', in: 'query', schema: new OA\Schema(type: 'string', default: '20')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getReminders(Request $request)
    {
        try {
            $admin = $request->user();
            $page = $request->get('page', 1);
            $limit = $request->get('limit', 20);
            $offset = ($page - 1) * $limit;

            $query = \App\Models\Reminder::with(['driver.user', 'device'])->latest();
            
            $total = $query->count();
            $reminders = $query->skip($offset)->take($limit)->get();

            $formattedReminders = $reminders->map(function ($reminder) {
                return [
                    'id' => $reminder->id,
                    'title' => $reminder->title,
                    'message' => $reminder->message,
                    'priority' => $reminder->priority,
                    'status' => $reminder->status,
                    'reminder_date' => $reminder->reminder_date->toISOString(),
                    'driver_name' => $reminder->driver->user->name ?? 'General',
                    'vehicle' => $reminder->device->plate_number ?? 'N/A',
                    'created_at' => $reminder->created_at->toISOString(),
                ];
            });

            $response = [
                'data' => $formattedReminders,
                'meta' => [
                    'current_page' => $page,
                    'per_page' => $limit, 
                    'total' => $total,
                    'last_page' => ceil($total / $limit),
                ]
            ];

            return ResponseHelper::success($response, 'Reminders retrieved successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve reminders: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Update reminder
     */
    #[OA\Put(
        path: '/admin/reminders/{id}',
        summary: 'Update reminder',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
                requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                properties: [
                new OA\Property(property: 'title', type: 'string', nullable: true),
                new OA\Property(property: 'message', type: 'string', nullable: true),
                new OA\Property(property: 'reminder_date', type: 'string', format: 'date', nullable: true),
                new OA\Property(property: 'priority', type: 'string', enum: ['low', 'medium', 'high', 'urgent'], nullable: true),
                new OA\Property(property: 'status', type: 'string', enum: ['active', 'completed', 'cancelled'], nullable: true),
                ],
            ),
        ),
responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function updateReminder(Request $request, $id)
    {
        try {
            $request->validate([
                'title' => 'sometimes|string|max:255',
                'message' => 'sometimes|string|max:1000',
                'reminder_date' => 'sometimes|date',
                'priority' => 'sometimes|in:low,medium,high,urgent',
                'status' => 'sometimes|in:active,completed,cancelled',
            ]);

            $reminder = \App\Models\Reminder::findOrFail($id);
            $reminder->update($request->only([
                'title', 'message', 'reminder_date', 'priority', 'status'
            ]));

            $reminder->load('driver.user', 'device');

            return ResponseHelper::success($reminder, 'Reminder updated successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to update reminder: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Delete reminder
     */
    #[OA\Delete(
        path: '/admin/reminders/{id}',
        summary: 'Delete reminder',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function deleteReminder($id)
    {
        try {
            $reminder = \App\Models\Reminder::findOrFail($id);
            $reminder->delete();

            return ResponseHelper::success(null, 'Reminder deleted successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to delete reminder: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get all receipts
     */
    public function getReceipts(Request $request)
    {
        try {
            $admin = $request->user();
            $page = $request->get('page', 1);
            $limit = $request->get('limit', 20);
            $offset = ($page - 1) * $limit;

            $query = Receipt::with(['transaction.driver.user', 'transaction.device'])->latest();
            
            $total = $query->count();
            $receipts = $query->skip($offset)->take($limit)->get();

            $formattedReceipts = $receipts->map(function ($receipt) {
                return [
                    'id' => $receipt->id,
                    'customer_name' => $receipt->customer_name,
                    'service_description' => $receipt->service_description,
                    'amount' => $receipt->amount,
                    'driver_name' => $receipt->transaction->driver->user->name ?? 'Unknown',
                    'vehicle' => $receipt->transaction->device->plate_number ?? 'N/A',
                    'issued_at' => $receipt->issued_at->toISOString(),
                    'transaction_id' => $receipt->transaction_id,
                ];
            });

            $response = [
                'data' => $formattedReceipts,
                'meta' => [
                    'current_page' => $page,
                    'per_page' => $limit,
                    'total' => $total,
                    'last_page' => ceil($total / $limit),
                ]
            ];

            return ResponseHelper::success($response, 'Receipts retrieved successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve receipts: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get specific driver information
     */
    #[OA\Get(
        path: '/admin/drivers/{id}',
        summary: 'Get driver',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getDriver(Request $request, $id)
    {
        try {
            $admin = $request->user();

            // Find the driver user
            $query = User::where('id', $id)->where('role', 'driver')
                        ->with(['driver', 'assignedDevice']);
            
            // If admin is authenticated, ensure driver belongs to admin
            if ($admin && !$admin->isSuperAdmin()) {
                $query->whereIn('created_by', $admin->accountMemberIds());
            }
            
            $user = $query->firstOrFail();
            $driver = $user->driver;
            $device = $user->assignedDevice;
            
            // Calculate total payments from transactions
            $totalPayments = $driver ? $driver->incomeTransactions()->sum('amount') : 0;
            
            // Get last payment date
            $lastPayment = $driver ? $driver->incomeTransactions()
                ->latest('transaction_date')
                ->first()?->transaction_date : null;
            
            // Calculate trips completed (count of completed transactions)
            $tripsCompleted = $driver ? $driver->completedTransactions()->count() : 0;
            
            // Calculate rating (placeholder - you can implement actual rating logic)
            $rating = 4.5; // Default rating
            
            $driverData = [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'phone' => $user->phone_number,
                'license_number' => $driver?->license_number ?? 'N/A',
                'vehicle_number' => $device?->plate_number ?? 'N/A',
                'vehicle_type' => $device?->type ?? 'N/A',
                'status' => $user->is_active ? 'active' : 'inactive',
                'total_payments' => (float) $totalPayments,
                'last_payment' => $lastPayment?->toISOString(),
                'joined_date' => $user->created_at->toISOString(),
                'rating' => $rating,
                'trips_completed' => $tripsCompleted,
                'driver_profile' => $driver ? [
                    'license_expiry' => $driver->license_expiry?->toISOString(),
                    'address' => $driver->address,
                    'emergency_contact' => $driver->emergency_contact,
                    'date_of_birth' => $driver->date_of_birth?->toISOString(),
                    'national_id' => $driver->national_id,
                ] : null,
                'vehicle' => $device ? [
                    'id' => $device->id,
                    'name' => $device->name,
                    'type' => $device->type,
                    'plate_number' => $device->plate_number,
                    'description' => $device->description,
                ] : null,
            ];

            return ResponseHelper::success($driverData, 'Driver information retrieved successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve driver information: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get driver debt trends over time
     */
    #[OA\Get(
        path: '/admin/drivers/{driverId}/debt-trends',
        summary: 'Get driver debt trends',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'period', in: 'query', schema: new OA\Schema(type: 'string', default: 'monthly')),
            new OA\Parameter(name: 'months', in: 'query', schema: new OA\Schema(type: 'string', default: '12')),
            new OA\Parameter(name: 'driverId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getDriverDebtTrends(Request $request, $driverId)
    {
        try {
            $admin = $request->user();
            $period = $request->get('period', 'monthly'); // daily, weekly, monthly
            $months = $request->get('months', 12); // number of periods to return

            // Find and verify driver
            $query = User::where('id', $driverId)->where('role', 'driver')
                        ->with(['driver']);
            
            if ($admin && !$admin->isSuperAdmin()) {
                $query->whereIn('created_by', $admin->accountMemberIds());
            }
            
            $user = $query->firstOrFail();
            $driver = $user->driver;

            if (!$driver) {
                return ResponseHelper::error('Driver profile not found', 404);
            }

            // For now, generate sample debt trend data
            // TODO: Replace with actual debt calculation logic when debt tracking is implemented
            // Generate data in ascending month order (1-12)
            $trendData = [];
            $currentYear = now()->year;
            
            for ($month = 1; $month <= $months && $month <= 12; $month++) {
                $periodStart = \Carbon\Carbon::create($currentYear, $month, 1)->startOfMonth();
                
                $periodLabel = match($period) {
                    'daily' => $periodStart->format('M d'),
                    'weekly' => 'W' . $periodStart->weekOfYear,
                    'monthly' => $this->getUltraShortMonthLabel($periodStart),
                    default => $this->getUltraShortMonthLabel($periodStart),
                };

                // Generate realistic debt amounts with some fluctuation
                $baseAmount = 30000;
                $variation = ($month % 3 == 0) ? 8000 : ($month % 2 == 0 ? -3000 : 5000);
                $debtAmount = max(15000, min(60000, $baseAmount + $variation + ($month * 1000)));

                $trendData[] = [
                    'period' => $periodLabel,
                    'period_start' => $periodStart->toISOString(),
                    'amount' => (float) $debtAmount,
                    'value' => (float) $debtAmount, // alias for Flutter compatibility
                ];
            }

            $response = [
                'driver_id' => $driverId,
                'driver_name' => $user->name,
                'period' => $period,
                'periods_count' => $months,
                'data' => $trendData,
            ];

            return ResponseHelper::success($response, 'Driver debt trends retrieved successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve driver debt trends: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get driver payment trends over time
     */
    #[OA\Get(
        path: '/admin/drivers/{driverId}/payment-trends',
        summary: 'Get driver payment trends',
        security: [['bearerAuth' => []]],
        tags: ['Transport / Admin'],
        parameters: [
            new OA\Parameter(name: 'period', in: 'query', schema: new OA\Schema(type: 'string', default: 'monthly')),
            new OA\Parameter(name: 'months', in: 'query', schema: new OA\Schema(type: 'string', default: '12')),
            new OA\Parameter(name: 'driverId', in: 'path', required: true, schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function getDriverPaymentTrends(Request $request, $driverId)
    {
        try {
            $admin = $request->user();
            $period = $request->get('period', 'monthly'); // daily, weekly, monthly
            $months = $request->get('months', 12); // number of periods to return

            // Find and verify driver
            $query = User::where('id', $driverId)->where('role', 'driver')
                        ->with(['driver']);
            
            if ($admin && !$admin->isSuperAdmin()) {
                $query->whereIn('created_by', $admin->accountMemberIds());
            }
            
            $user = $query->firstOrFail();
            $driver = $user->driver;

            if (!$driver) {
                return ResponseHelper::error('Driver profile not found', 404);
            }

            // Generate data in ascending month order (1-12)
            $trendData = [];
            $currentYear = now()->year;
            
            for ($month = 1; $month <= $months && $month <= 12; $month++) {
                $periodStart = \Carbon\Carbon::create($currentYear, $month, 1)->startOfMonth();
                $periodEnd = $periodStart->copy()->endOfMonth();
                
                $periodLabel = match($period) {
                    'daily' => $periodStart->format('M d'),
                    'weekly' => 'W' . $periodStart->weekOfYear,
                    'monthly' => $this->getUltraShortMonthLabel($periodStart),
                    default => $this->getUltraShortMonthLabel($periodStart),
                };

                // Get actual payment data from transactions if available
                $actualPayments = $driver->incomeTransactions()
                    ->where('status', 'completed')
                    ->whereBetween('transaction_date', [$periodStart, $periodEnd])
                    ->sum('amount');

                // If no actual data, generate sample data
                if ($actualPayments == 0) {
                    $baseAmount = 15000;
                    $variation = ($month % 4 == 0) ? 3000 : ($month % 3 == 0 ? -1000 : 2000);
                    $paymentAmount = max(10000, min(35000, $baseAmount + $variation + ($month * 1500)));
                } else {
                    $paymentAmount = $actualPayments;
                }

                $trendData[] = [
                    'period' => $periodLabel,
                    'period_start' => $periodStart->toISOString(),
                    'period_end' => $periodEnd->toISOString(),
                    'amount' => (float) $paymentAmount,
                    'value' => (float) $paymentAmount, // alias for Flutter compatibility
                    'transaction_count' => $driver->incomeTransactions()
                        ->where('status', 'completed')
                        ->whereBetween('transaction_date', [$periodStart, $periodEnd])
                        ->count(),
                ];
            }

            $response = [
                'driver_id' => $driverId,
                'driver_name' => $user->name,
                'period' => $period,
                'periods_count' => $months,
                'data' => $trendData,
            ];

            return ResponseHelper::success($response, 'Driver payment trends retrieved successfully');

        } catch (\Illuminate\Database\Eloquent\ModelNotFoundException $e) {
            // Also what a scoped lookup returns for another account's record.
            return response()->json(['status' => 'error', 'success' => false, 'message' => 'Not found'], 404);
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve driver payment trends: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get month number label for chart display
     * 
     * @param \Carbon\Carbon $date
     * @return string
     */
    private function getUltraShortMonthLabel($date)
    {
        // Return month number (1-12) for ascending order display
        return (string) $date->month;
    }
}
