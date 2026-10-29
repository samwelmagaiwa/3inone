<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\API\AuthController;
use App\Http\Controllers\API\RegistrationController;
use App\Http\Controllers\API\BusinessController;
use App\Http\Controllers\API\BusinessSubscriptionController;
use App\Http\Controllers\API\SmsSenderController;
use App\Http\Controllers\API\PlanPriceController;
use App\Http\Controllers\API\LocationController;
use App\Http\Controllers\API\Transport\AdminController;
use App\Http\Controllers\API\Transport\AdminReportController;
use App\Http\Controllers\API\Transport\DriverViewController;
use App\Http\Controllers\API\Transport\DeviceController;
use App\Http\Controllers\API\Transport\DriverController;
use App\Http\Controllers\API\Transport\PaymentController;
use App\Http\Controllers\API\Transport\TransactionController;
use App\Http\Controllers\API\Transport\ReceiptController;
use App\Http\Controllers\API\Transport\ReportController;
use App\Http\Controllers\API\Transport\TestController;
use App\Http\Controllers\API\Transport\TestReportController;
use App\Http\Controllers\API\Transport\PaymentReceiptController;
use App\Http\Controllers\API\Transport\CommunicationController;
use App\Http\Controllers\API\Transport\DriverAgreementController;
use App\Http\Controllers\API\Transport\DashboardController;
use App\Http\Controllers\API\Inventory\ProductController as InventoryProductController;
use App\Http\Controllers\API\Inventory\CategoryController as InventoryCategoryController;
use App\Http\Controllers\API\Inventory\BrandController as InventoryBrandController;
use App\Http\Controllers\API\Inventory\ProductUnitController as InventoryProductUnitController;
use App\Http\Controllers\API\Inventory\BatchController as InventoryBatchController;
use App\Http\Controllers\API\Inventory\StockCountController as InventoryStockCountController;
use App\Http\Controllers\API\Inventory\WriteOffController as InventoryWriteOffController;
use App\Http\Controllers\API\Inventory\PurchasingController as InventoryPurchasingController;
use App\Http\Controllers\API\Inventory\CreditController as InventoryCreditController;
use App\Http\Controllers\API\Inventory\CashController as InventoryCashController;
use App\Http\Controllers\API\Inventory\CrateController as InventoryCrateController;
use App\Http\Controllers\API\Inventory\PosController as InventoryPosController;
use App\Http\Controllers\API\Inventory\DispatchController as InventoryDispatchController;
use App\Http\Controllers\API\Inventory\NotificationController as InventoryNotificationController;
use App\Http\Controllers\API\Inventory\BarcodeController as InventoryBarcodeController;
use App\Http\Controllers\API\Inventory\ReportController as InventoryReportController;
use App\Http\Controllers\API\Inventory\AlertController as InventoryAlertController;
use App\Http\Controllers\API\Inventory\CustomerController as InventoryCustomerController;
use App\Http\Controllers\API\Inventory\AppointmentController;
use App\Http\Controllers\API\Inventory\SalonBooksController;
use App\Http\Controllers\API\Inventory\SalonBranchController;
use App\Http\Controllers\API\Inventory\SalonBranchStockController;
use App\Http\Controllers\API\Inventory\SalonQueueController;
use App\Http\Controllers\API\Inventory\SalonReportsController;
use App\Http\Controllers\API\Inventory\SalonSetupController;
use App\Http\Controllers\API\Inventory\SalonClientController;
use App\Http\Controllers\API\Inventory\BusinessMoneyController;
use App\Http\Controllers\API\Inventory\SalonController;
use App\Http\Controllers\API\Inventory\SalonEquipmentController;
use App\Http\Controllers\API\Inventory\SalonExportController;
use App\Http\Controllers\API\Inventory\SalonFeedbackController;
use App\Http\Controllers\API\Inventory\SalonPublicBookingController;
use App\Http\Controllers\API\Inventory\SalonMoneyController;
use App\Http\Controllers\API\Inventory\SalonPerksController;
use App\Http\Controllers\API\Inventory\SalonStaffController;
use App\Http\Controllers\API\Inventory\AssistantController;
use App\Http\Controllers\API\Inventory\SalesController as InventorySalesController;
use App\Http\Controllers\API\Inventory\StockMovementController as InventoryStockMovementController;
use App\Http\Controllers\API\Inventory\ReminderController as InventoryReminderController;
use App\Http\Controllers\API\Inventory\ExpenseController as InventoryExpenseController;
use App\Http\Controllers\API\Rental\PropertyController;
use App\Http\Controllers\API\Rental\BlockController;
use App\Http\Controllers\API\Rental\HouseController;
use App\Http\Controllers\API\Rental\TenantController;
use App\Http\Controllers\API\Rental\BillingController;
use App\Http\Controllers\API\Rental\CaretakerController;
use App\Http\Controllers\API\Rental\AgreementController;
use App\Http\Controllers\API\Rental\MaintenanceController;


/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
|
| Here is where you can register API routes for your application. These
| routes are loaded by the RouteServiceProvider and all of them will
| be assigned to the "api" middleware group. Make something great!
|
*/

// Location endpoints
Route::prefix('locations')->group(function () {
    Route::get('regions', [LocationController::class, 'getRegions']);
    Route::get('districts', [LocationController::class, 'getDistricts']);
    Route::get('wards', [LocationController::class, 'getWards']);
    Route::get('streets', [LocationController::class, 'getStreets']);
    Route::get('places', [LocationController::class, 'getPlaces']);
});

// Public routes (no authentication required)
Route::prefix('auth')->group(function () {
    // Brute-force guard: keyed by email + IP so one office NAT can't lock out everyone.
    Route::post('login', [AuthController::class, 'login'])->middleware('throttle:login');
    // Rate-limited: both steps are unauthenticated and check identity by
    // email/phone, so without a limit they'd be a brute-force target.
    // A business owner registers themselves; a super admin then reviews and assigns
    // services. Public, so it is rate-limited per IP.
    Route::post('register', [RegistrationController::class, 'register'])->middleware('throttle:10,10');
    // The applicant proves the phone number is theirs with the code texted at registration.
    Route::post('register/verify-phone', [RegistrationController::class, 'verifyPhone'])->middleware('throttle:10,10');
    Route::post('register/resend-code', [RegistrationController::class, 'resendCode'])->middleware('throttle:5,10');
    Route::post('forgot-password', [AuthController::class, 'forgotPassword'])->middleware('throttle:5,1');
    Route::post('reset-password', [AuthController::class, 'resetPassword'])->middleware('throttle:5,1');
});

// Public house listings (no authentication required)
Route::get('public/houses', [HouseController::class, 'publicListing']);

// The plans, how many services each covers and what they cost: the registration form shows it before sign-in.
Route::get('plans', [PlanPriceController::class, 'publicIndex'])->middleware('throttle:60,1');

// Payment Receipt routes - PROTECTED
// Transport receipts across all drivers: admin-level only (or the payments grant).
Route::middleware(['auth:sanctum', 'role:admin', 'service:transport'])->prefix('payment-receipts')->group(function () {
    Route::get('pending', [PaymentReceiptController::class, 'getPendingReceipts']);
    Route::post('generate', [PaymentReceiptController::class, 'generateReceipt']);
    Route::get('{receiptId}/preview', [PaymentReceiptController::class, 'getReceiptPreview']);
    Route::post('send', [PaymentReceiptController::class, 'sendReceipt']);
    Route::get('', [PaymentReceiptController::class, 'getReceipts']);
    Route::get('{receiptId}', [PaymentReceiptController::class, 'getReceiptPreview']);
});

// ACCOUNT MANAGEMENT -- staff of the caller's own business. Not tied to one service:
// an owner may create staff for whichever services they were given (the controller
// checks that), so these are deliberately outside the service: gates below.
// A client's answer to "how was your visit": opened from a link in a text, so nobody is signed in. The secret is the
// token in the link (one use, a few days); every call is throttled.
// (Each limit has its own name: without one, every limit on the same address counts the same requests.)
Route::prefix('public/salon')->middleware('throttle:120,1,public-salon')->group(function () {
    Route::get('feedback/{token}', [SalonFeedbackController::class, 'show']);
    Route::post('feedback/{token}', [SalonFeedbackController::class, 'answer']);
    // A client booking for themselves from the salon's own page.
    Route::get('book/{slug}', [SalonPublicBookingController::class, 'catalog']);
    Route::get('book/{slug}/slots', [SalonPublicBookingController::class, 'slots']);
    Route::post('book/{slug}', [SalonPublicBookingController::class, 'book'])->middleware('throttle:10,1,salon-book');
});

Route::middleware(['auth:sanctum', 'role:admin'])->prefix('admin')->group(function () {
    // Users management
    Route::prefix('users')->group(function () {
        Route::get('mine', [\App\Http\Controllers\API\UserManagementController::class, 'myUsers']);
        Route::get('by-service', [\App\Http\Controllers\API\UserManagementController::class, 'usersByService']);
        Route::get('', [\App\Http\Controllers\API\UserManagementController::class, 'myUsers']); // fallback with created_by=me assumption
        Route::post('', [\App\Http\Controllers\API\UserManagementController::class, 'store']);
        Route::put('{id}', [\App\Http\Controllers\API\UserManagementController::class, 'update']);
        Route::put('{id}/services', [\App\Http\Controllers\API\UserManagementController::class, 'bindServices']); // super_admin only
        Route::put('{id}/assign-admin', [\App\Http\Controllers\API\UserManagementController::class, 'assignToAdmin']); // super_admin only
        Route::delete('{id}', [\App\Http\Controllers\API\UserManagementController::class, 'destroy']);
        Route::post('{id}/reset-password', [\App\Http\Controllers\API\UserManagementController::class, 'resetPassword']);
    });
});

// BUSINESS REGISTRATIONS -- super admin only. A business owner registers themselves
// (POST /auth/register); the super admin reviews the details here and assigns services.
Route::middleware(['auth:sanctum', 'role:super_admin'])->prefix('admin/registrations')->group(function () {
    Route::get('', [RegistrationController::class, 'index']);
    Route::get('{id}', [RegistrationController::class, 'show']);
    Route::post('{id}/approve', [RegistrationController::class, 'approve']);
    Route::post('{id}/reject', [RegistrationController::class, 'reject']);
});

// BUSINESSES -- super admin only: every business with its owner, services and plan, and the one
// place a plan / valid_until is changed (an owner can never change their own billing).
Route::middleware(['auth:sanctum', 'role:super_admin'])->prefix('admin/businesses')->group(function () {
    Route::get('', [BusinessController::class, 'adminIndex']);
    Route::get('{id}', [BusinessController::class, 'adminShow']);
    Route::put('{id}', [BusinessController::class, 'adminUpdate']);
    // A payment moves the paid-until date on and opens a held-back business again at once.
    Route::get('{id}/payments', [BusinessSubscriptionController::class, 'adminIndex']);
    Route::post('{id}/payments', [BusinessSubscriptionController::class, 'adminStore']);
});

// PLAN PRICES -- super admin only: what each plan costs for 1, 3, 6 and 12 months. The registration form shows
// them as soon as they are saved.
Route::middleware(['auth:sanctum', 'role:super_admin'])->prefix('admin/plan-prices')->group(function () {
    Route::get('', [PlanPriceController::class, 'adminIndex']);
    Route::put('', [PlanPriceController::class, 'adminUpdate']);
});

// SMS SENDER NAMES -- super admin only: which registered sender name each business's texts go out under.
// A name works only once the super admin has registered it with the SMS provider and marked it approved.
Route::middleware(['auth:sanctum', 'role:super_admin'])->prefix('admin/sms-senders')->group(function () {
    Route::get('', [SmsSenderController::class, 'index']);
    Route::put('{id}', [SmsSenderController::class, 'update']);
    // One real text under the name: costs a message, so it is limited.
    Route::post('{id}/test', [SmsSenderController::class, 'test'])->middleware('throttle:10,1');
});

// PROTECTED ADMIN ROUTES -- the Transport service
Route::middleware(['auth:sanctum', 'role:admin', 'service:transport'])->prefix('admin')->group(function () {
    // Dashboard
    Route::get('dashboard', [AdminController::class, 'dashboard']);
    Route::get('dashboard-data', [DashboardController::class, 'index']);
    Route::get('dashboard-stats', [DashboardController::class, 'getStats']);

    // Individual Dashboard Card Endpoints
    // Branches of the transport business (yards, garages): vehicles and drivers belong to one, and every figure can be looked at per branch.
    Route::prefix('branches')->group(function () {
        Route::get('', [\App\Http\Controllers\API\BusinessBranchController::class, 'index'])->defaults('service', 'transport');
        Route::post('', [\App\Http\Controllers\API\BusinessBranchController::class, 'store'])->defaults('service', 'transport');
        Route::put('{id}', [\App\Http\Controllers\API\BusinessBranchController::class, 'update'])->defaults('service', 'transport')->whereNumber('id');
        Route::delete('{id}', [\App\Http\Controllers\API\BusinessBranchController::class, 'destroy'])->defaults('service', 'transport')->whereNumber('id');
    });

    Route::prefix('dashboard')->group(function () {
        Route::get('active-drivers-count', [DashboardController::class, 'getActiveDriversCount']);
        Route::get('active-devices-count', [DashboardController::class, 'getActiveDevicesCount']);
        Route::get('unpaid-debts-count', [DashboardController::class, 'getUnpaidDebtsCount']);
        Route::get('generated-receipts-count', [DashboardController::class, 'getGeneratedReceiptsCount']);
        Route::get('pending-receipts-count', [DashboardController::class, 'getPendingReceiptsCountApi']);
        Route::get('daily-revenue', [DashboardController::class, 'getDailyRevenueApi']);
        Route::get('weekly-revenue', [DashboardController::class, 'getWeeklyRevenueApi']);
        Route::get('monthly-revenue', [DashboardController::class, 'getMonthlyRevenueApi']);
    });

    // Drivers
    Route::get('drivers', [AdminController::class, 'getDrivers']);
    Route::get('drivers/{id}', [AdminController::class, 'getDriver']);
    Route::post('drivers', [AdminController::class, 'createDriver']);
    Route::put('drivers/{id}', [AdminController::class, 'updateDriver']);
    Route::delete('drivers/{id}', [AdminController::class, 'deleteDriver']);
    Route::get('drivers/{driverId}/debt-trends', [AdminController::class, 'getDriverDebtTrends']);
    Route::get('drivers/{driverId}/payment-trends', [AdminController::class, 'getDriverPaymentTrends']);
    Route::get('drivers/{driverId}/prediction', [\App\Http\Controllers\API\Transport\PredictionController::class, 'getDriverPrediction']);
    Route::get('drivers/{driverId}/history-pdf', [\App\Http\Controllers\API\Transport\DriverReportController::class, 'driverHistoryPdf']);

    // Vehicles
    Route::get('vehicles', [AdminController::class, 'getVehicles']);
    Route::post('vehicles', [AdminController::class, 'createVehicle']);
    Route::put('vehicles/{id}', [AdminController::class, 'updateVehicle']);
    Route::delete('vehicles/{id}', [AdminController::class, 'deleteVehicle']);
    Route::post('vehicles/{id}/unassign', [AdminController::class, 'unassignDriverFromVehicle']);
    Route::post('assign-driver', [AdminController::class, 'assignDriverToVehicle']);

    // Payments (use PaymentController under admin/payments)
    Route::prefix('payments')->group(function () {
        Route::get('drivers-with-debts', [PaymentController::class, 'getDriversWithDebts']);
        Route::get('driver-debt-summary/{driverId}', [PaymentController::class, 'getDriverDebtSummary']);
        Route::get('driver-debts/{driverId}', [PaymentController::class, 'getDriverDebtRecords']);
        Route::post('record', [PaymentController::class, 'recordPayment']);
        Route::get('history', [PaymentController::class, 'getPaymentHistory']);
        Route::put('{paymentId}', [PaymentController::class, 'updatePayment']);
        Route::delete('{paymentId}', [PaymentController::class, 'deletePayment']);
        Route::get('summary', [PaymentController::class, 'getPaymentSummary']);
        Route::put('mark-debt-paid/{debtId}', [PaymentController::class, 'markDebtAsPaid']);
        Route::post('new', [PaymentController::class, 'storeNewPayment']);
        Route::get('new-payments-map', [PaymentController::class, 'getNewPaymentsMap']);
    });

    // Debts
    Route::prefix('debts')->group(function () {
        Route::get('drivers', [\App\Http\Controllers\API\Transport\DebtsController::class, 'listDrivers']);
        Route::get('driver/{driverId}/records', [\App\Http\Controllers\API\Transport\DebtsController::class, 'listDriverRecords']);
        Route::post('bulk-create', [\App\Http\Controllers\API\Transport\DebtsController::class, 'bulkCreate']);
        Route::put('records/{id}', [\App\Http\Controllers\API\Transport\DebtsController::class, 'updateRecord']);
        Route::delete('records/{id}', [\App\Http\Controllers\API\Transport\DebtsController::class, 'deleteRecord']);
    });

    // Driver agreements
    Route::prefix('driver-agreements')->group(function () {
        Route::get('', [DriverAgreementController::class, 'index']);
        Route::post('', [DriverAgreementController::class, 'store']);
        Route::get('{id}', [DriverAgreementController::class, 'show']);
        Route::put('{id}', [DriverAgreementController::class, 'update']);
        Route::delete('{id}', [DriverAgreementController::class, 'destroy']);
        Route::get('driver/{driverId}', [DriverAgreementController::class, 'getByDriver']);
        Route::post('calculate-preview', [DriverAgreementController::class, 'calculatePreview']);
    });

    // Reminders
    Route::prefix('reminders')->group(function () {
        Route::get('', [AdminController::class, 'getReminders']);
        Route::post('', [AdminController::class, 'addReminder']);
        Route::put('{id}', [AdminController::class, 'updateReminder']);
        Route::delete('{id}', [AdminController::class, 'deleteReminder']);
    });

    // Receipts Management (admin view)
    //
    // `{receiptId}` is a number. Without that, "stats" and "search" (declared further down) were taken for a receipt id
    // by the `{receiptId}` route above them, and answered 500 because the controller wants an int.
    Route::prefix('receipts')->group(function () {
        Route::get('pending', [PaymentReceiptController::class, 'getPendingReceipts']);
        Route::post('generate', [PaymentReceiptController::class, 'generateReceipt']);
        Route::get('{receiptId}/preview', [PaymentReceiptController::class, 'getReceiptPreview'])->whereNumber('receiptId');
        Route::post('send', [PaymentReceiptController::class, 'sendReceipt']);
        Route::get('', [PaymentReceiptController::class, 'getReceipts']);
        Route::get('{receiptId}', [PaymentReceiptController::class, 'getReceiptPreview'])->whereNumber('receiptId');
        Route::put('{receiptId}/status', [PaymentReceiptController::class, 'updateReceiptStatus'])->whereNumber('receiptId');
        Route::put('{receiptId}/cancel', [PaymentReceiptController::class, 'cancelReceipt'])->whereNumber('receiptId');
        Route::delete('{receiptId}', [PaymentReceiptController::class, 'deleteReceipt'])->whereNumber('receiptId');
        Route::get('stats', [PaymentReceiptController::class, 'getReceiptStats']);
        Route::post('export', [PaymentReceiptController::class, 'exportReceipts']);
        Route::post('bulk-generate', [PaymentReceiptController::class, 'generateBulkReceipts']);
        Route::get('search', [PaymentReceiptController::class, 'searchReceipts']);
    });

    // Reports
    Route::prefix('reports')->group(function () {
        Route::get('dashboard', [AdminReportController::class, 'getDashboardReport']);
        Route::get('revenue', [AdminReportController::class, 'getRevenueReport']);
        Route::get('expenses', [AdminReportController::class, 'getExpenseReport']);
        Route::get('profit-loss', [AdminReportController::class, 'getProfitLossReport']);
        Route::get('device-performance', [AdminReportController::class, 'getDevicePerformanceReport']);
        Route::post('export-pdf', [AdminReportController::class, 'exportToPdf']);
    });

    // Analytics
    Route::prefix('analytics')->group(function () {
        Route::get('overview', [AdminReportController::class, 'getAnalyticsOverview']);
        Route::get('top-performers', [AdminReportController::class, 'getTopPerformers']);
        Route::get('live', [AdminReportController::class, 'getLiveAnalytics']);
        Route::get('trends', [AdminReportController::class, 'getRevenueReport']);
    });
});

// Public file proxy for web images (CORS-enabled)
Route::get('files/public/{path}', [\App\Http\Controllers\API\MediaController::class, 'publicFile'])->where('path', '.*');

// Private uploads (lease documents, tenant and repair photos, reports): only through a signed,
// expiring link that the API gives to people allowed to see the record. Signed on the path alone
// ("relative") so it still validates behind the proxy that turns https into http.
Route::get('files/private/{path}', [\App\Http\Controllers\API\MediaController::class, 'privateFile'])
    ->where('path', '.*')
    ->middleware(['signed:relative', 'throttle:240,1'])
    ->name('files.private');

// Protected routes (authentication required)
Route::middleware(['auth:sanctum'])->group(function () {
    // The AI assistant: one for every service. Whoever is signed in may ask; what it can read is decided per person, tool by tool,
    // by the same rights the matching screens use (see App\Support\Ai\AssistantTools).
    Route::middleware('throttle:15,1,assistant')->group(function () {
        Route::get('assistant',  [AssistantController::class, 'status']);
        Route::post('assistant', [AssistantController::class, 'ask']);
    });


    // The signed-in user's own business: anyone who works for it reads it; only its owner edits
    // the profile and logo. Billing (plan / valid_until) is read here, changed only by a super admin.
    Route::prefix('business')->group(function () {
        Route::get('', [BusinessController::class, 'show']);
        // What it paid, when it started and when it ends. Stays reachable when the business is held back.
        Route::get('subscription', [BusinessSubscriptionController::class, 'show']);
        Route::put('', [BusinessController::class, 'update']);
        // The owner asks for the name customers' phones should show; it then waits for the super admin.
        Route::post('sms-sender', [SmsSenderController::class, 'request']);
        Route::delete('sms-sender', [SmsSenderController::class, 'withdraw']);
        Route::post('logo', [BusinessController::class, 'uploadLogo']);
        Route::delete('logo', [BusinessController::class, 'removeLogo']);
    });

    // Auth routes
    Route::prefix('auth')->group(function () {
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('user', [AuthController::class, 'user']);
        Route::get('user/services', [AuthController::class, 'myServices']);
        Route::post('refresh', [AuthController::class, 'refresh']);
        // Profile avatar upload (multipart)
        Route::post('profile/avatar', [AuthController::class, 'uploadAvatar']);
        Route::post('profile/photo', [AuthController::class, 'uploadAvatar']);
        Route::post('profile/image', [AuthController::class, 'uploadAvatar']);
        // Security
        Route::post('change-password', [\App\Http\Controllers\API\SecurityController::class, 'changePassword']);
        Route::get('security', [\App\Http\Controllers\API\SecurityController::class, 'getSecuritySettings']);
        Route::post('two-factor', [\App\Http\Controllers\API\SecurityController::class, 'setTwoFactor']);
        Route::get('login-history', [\App\Http\Controllers\API\SecurityController::class, 'getLoginHistory']);
        Route::delete('login-history', [\App\Http\Controllers\API\SecurityController::class, 'clearLoginHistory']);

        // Backup / Restore — super_admin only
        Route::prefix('admin')->group(function () {
            Route::get('backup', [\App\Http\Controllers\API\BackupController::class, 'status']);
            Route::post('backup', [\App\Http\Controllers\API\BackupController::class, 'create']);
            Route::post('restore', [\App\Http\Controllers\API\BackupController::class, 'restore']);
        });
    });

    // =========================================================================
    // INVENTORY — granular permission gates via inv_perm middleware.
    // Every route checks User::hasInventoryPermission() which resolves:
    //   1. super_admin / admin / full_access       → always allowed
    //   2. Explicit per-user grant (users.permissions JSON column)
    //   3. Role-default permission set (User::$INV_ROLE_DEFAULTS)
    // Admin can extend any individual's access via UserManagement → Permissions.
    // =========================================================================

    // ── Products & Catalog (inv_view_products / inv_manage_products) ──────────
    Route::middleware('inv_perm:inv_view_products')->group(function () {
        Route::get('inventory/products',          [InventoryProductController::class, 'index']);
        Route::get('products',                    [InventoryProductController::class, 'index']);
        Route::get('inventory/categories',        [InventoryCategoryController::class, 'index']);
        Route::get('inventory/categories/{id}',   [InventoryCategoryController::class, 'show']);
        Route::get('categories',                  [InventoryCategoryController::class, 'index']);
        Route::get('inventory/brands',            [InventoryBrandController::class, 'index']);
        Route::get('inventory/brands/{id}',       [InventoryBrandController::class, 'show']);
        Route::get('inventory/alerts',            [InventoryAlertController::class, 'index']);
        Route::post('inventory/alerts/{id}/acknowledge', [InventoryAlertController::class, 'acknowledge']);
    });

    // Creating a product accepts either full catalogue management OR the narrower
    // create-only grant (sales_officer); edit/delete stay manage-only below.
    Route::middleware('inv_perm:inv_manage_products,inv_create_products')->group(function () {
        Route::post('inventory/products',        [InventoryProductController::class, 'store']);
    });

    Route::middleware('inv_perm:inv_manage_products')->group(function () {
        Route::put('inventory/products/{id}',    [InventoryProductController::class, 'update']);
        // More sizes / colours for an existing product (each a stock item of its own).
        Route::post('inventory/products/{id}/variants', [InventoryProductController::class, 'addVariants']);
        Route::delete('inventory/products/{id}', [InventoryProductController::class, 'destroy']);
        Route::post('inventory/categories',        [InventoryCategoryController::class, 'store']);
        Route::put('inventory/categories/{id}',    [InventoryCategoryController::class, 'update']);
        Route::delete('inventory/categories/{id}', [InventoryCategoryController::class, 'destroy']);
        Route::post('inventory/brands',        [InventoryBrandController::class, 'store']);
        Route::put('inventory/brands/{id}',    [InventoryBrandController::class, 'update']);
        Route::delete('inventory/brands/{id}', [InventoryBrandController::class, 'destroy']);
        Route::put('inventory/customers/{id}',     [InventoryCustomerController::class, 'update']);
        Route::delete('inventory/customers/{id}',  [InventoryCustomerController::class, 'destroy']);
    });

    // Listing and adding customers is part of SELLING (pick or create the buyer
    // at the POS, sell on credit), so it must work for anyone who can create
    // sales -- not only those who manage the catalogue. Editing/deleting a
    // customer stays inv_manage_products (above).
    Route::middleware('inv_perm:inv_manage_products,inv_create_sales,inv_view_credit')->group(function () {
        Route::get('inventory/customers',          [InventoryCustomerController::class, 'index']);
        Route::get('customers',                    [InventoryCustomerController::class, 'index']);
    });
    Route::middleware('inv_perm:inv_manage_products,inv_create_sales')->group(function () {
        Route::post('inventory/customers',         [InventoryCustomerController::class, 'store']);
    });

    // ── The owner's money tools: debts from before the app, the monthly report with its target, and advice.
    Route::middleware('inv_perm:inv_view_credit,inv_manage_products')->group(function () {
        Route::get('inventory/opening-debts',                    [BusinessMoneyController::class, 'debts']);
        Route::post('inventory/opening-debts',                   [BusinessMoneyController::class, 'addDebt']);
        Route::post('inventory/opening-debts/{id}/payments',     [BusinessMoneyController::class, 'payDebt']);
        Route::get('inventory/opening-debts/{id}/payments',      [BusinessMoneyController::class, 'debtPayments']);
        Route::delete('inventory/opening-debts/{id}',            [BusinessMoneyController::class, 'deleteDebt']);
    });
    Route::middleware('inv_perm:inv_view_reports')->group(function () {
        Route::get('inventory/monthly-report',                  [BusinessMoneyController::class, 'report']);
        Route::get('inventory/advice',                           [BusinessMoneyController::class, 'advice']);
        Route::get('inventory/payment-references',               [BusinessMoneyController::class, 'paymentReferences']);
    });
    Route::middleware('inv_perm:inv_manage_settings')->group(function () {
        Route::put('inventory/monthly-target',                   [BusinessMoneyController::class, 'setTarget']);
    });

    // ── Salon: stylists, client history, "come back" reminders (see SalonController). It runs on the sales
    // engine, so these use the same permissions: whoever may sell may look a client up and note them down.
    Route::middleware('inv_perm:inv_manage_products,inv_create_sales,inv_view_credit')->group(function () {
        Route::get('inventory/salon/staff',                [SalonController::class, 'staff']);
        Route::get('inventory/salon/services/{id}/usual-goods', [SalonSetupController::class, 'usualGoods']);
        Route::get('inventory/salon/settings',             [SalonController::class, 'settings']);
        Route::get('inventory/salon/clients/overview',     [SalonClientController::class, 'overview']);
        Route::get('inventory/salon/clients/{id}/history', [SalonController::class, 'clientHistory']);
        Route::get('inventory/salon/clients/{id}/photos',  [SalonClientController::class, 'photos']);
        Route::get('inventory/salon/clients/{id}/loyalty', [SalonPerksController::class, 'loyalty']);
        Route::get('inventory/salon/clients/{id}/packages', [SalonPerksController::class, 'packages']);
        Route::get('inventory/salon/loyalty/settings',     [SalonPerksController::class, 'loyaltySettings']);
        Route::get('inventory/salon/vouchers/check',       [SalonPerksController::class, 'checkVoucher']);
        Route::get('inventory/salon/vouchers',             [SalonPerksController::class, 'vouchers']);
        Route::post('inventory/salon/vouchers',            [SalonPerksController::class, 'storeVoucher']);
        Route::match(['put', 'patch'], 'inventory/salon/vouchers/{id}', [SalonPerksController::class, 'updateVoucher']);
        Route::delete('inventory/salon/vouchers/{id}',     [SalonPerksController::class, 'destroyVoucher']);
        Route::put('inventory/salon/loyalty/settings',     [SalonPerksController::class, 'saveLoyaltySettings']);
        Route::post('inventory/salon/clients/{id}/loyalty/adjust', [SalonPerksController::class, 'adjustLoyalty']);
        Route::post('inventory/salon/clients/{id}/photos', [SalonClientController::class, 'storePhoto']);
        Route::delete('inventory/salon/photos/{id}',       [SalonClientController::class, 'destroyPhoto']);
        Route::get('inventory/salon/campaigns',            [SalonClientController::class, 'campaigns']);
        // Equipment and its upkeep (the owner, managers and the stock manager: checked in the controller).
        // The owner's books and the walk-in queue, ready-made categories and the goods a service uses up.
        // Branches and the goods held in each work for a shop or depot too (the same controllers, without "salon" in the address).
        Route::get('inventory/branch-stock',               [SalonBranchStockController::class, 'index']);
        Route::post('inventory/branch-stock/transfer',     [SalonBranchStockController::class, 'transfer']);
        Route::put('inventory/branch-stock/level',         [SalonBranchStockController::class, 'level']);
        Route::get('inventory/branch-stock/transfers',     [SalonBranchStockController::class, 'transfers']);
        Route::get('inventory/salon/branch-stock',         [SalonBranchStockController::class, 'index']);
        Route::post('inventory/salon/branch-stock/transfer', [SalonBranchStockController::class, 'transfer']);
        Route::put('inventory/salon/branch-stock/level',   [SalonBranchStockController::class, 'level']);
        Route::get('inventory/salon/branch-stock/transfers', [SalonBranchStockController::class, 'transfers']);
        Route::get('inventory/salon/reports',              [SalonReportsController::class, 'index']);
        Route::get('inventory/salon/cashbook',             [SalonBooksController::class, 'cashbook']);
        Route::post('inventory/salon/cashbook/moves',      [SalonBooksController::class, 'storeMove']);
        Route::delete('inventory/salon/cashbook/moves/{id}', [SalonBooksController::class, 'destroyMove']);
        Route::post('inventory/salon/cashbook/counts',     [SalonBooksController::class, 'storeCount']);
        Route::get('inventory/salon/analytics',            [SalonBooksController::class, 'analytics']);
        Route::get('inventory/salon/queue',                [SalonQueueController::class, 'index']);
        Route::post('inventory/salon/queue',               [SalonQueueController::class, 'store']);
        Route::post('inventory/salon/queue/{id}/status',   [SalonQueueController::class, 'status']);
        Route::post('inventory/salon/category-presets',    [SalonSetupController::class, 'presets']);
        Route::get('inventory/salon/services/{id}/materials', [SalonSetupController::class, 'materials']);
        Route::put('inventory/salon/services/{id}/materials', [SalonSetupController::class, 'saveMaterials']);
        Route::get('inventory/salon/materials-usage',      [SalonSetupController::class, 'usage']);
        // Branches: everyone sees the list; the owner and managers change it (checked in the controller).
        Route::get('inventory/branches',                   [SalonBranchController::class, 'index']);
        Route::post('inventory/branches',                  [SalonBranchController::class, 'store']);
        Route::match(['put', 'patch'], 'inventory/branches/{id}', [SalonBranchController::class, 'update']);
        Route::delete('inventory/branches/{id}',           [SalonBranchController::class, 'destroy']);
        Route::get('inventory/branch-team',                [\App\Http\Controllers\API\Inventory\BranchTeamController::class, 'index']);
        Route::put('inventory/branch-team/{staffId}',      [\App\Http\Controllers\API\Inventory\BranchTeamController::class, 'assign']);
        Route::get('inventory/branch-sales',               [\App\Http\Controllers\API\Inventory\BranchTeamController::class, 'sales']);
        Route::get('inventory/salon/branches',             [SalonBranchController::class, 'index']);
        Route::post('inventory/salon/branches',            [SalonBranchController::class, 'store']);
        Route::match(['put', 'patch'], 'inventory/salon/branches/{id}', [SalonBranchController::class, 'update']);
        Route::delete('inventory/salon/branches/{id}',     [SalonBranchController::class, 'destroy']);
        Route::get('inventory/salon/equipment',            [SalonEquipmentController::class, 'index']);
        Route::post('inventory/salon/equipment',           [SalonEquipmentController::class, 'store']);
        Route::match(['put', 'patch'], 'inventory/salon/equipment/{id}', [SalonEquipmentController::class, 'update']);
        Route::delete('inventory/salon/equipment/{id}',    [SalonEquipmentController::class, 'destroy']);
        Route::get('inventory/salon/equipment/{id}/logs',  [SalonEquipmentController::class, 'logs']);
        Route::post('inventory/salon/equipment/{id}/logs', [SalonEquipmentController::class, 'addLog']);
        // Reports as a PDF or a CSV (the owner, managers and accountants: checked in the controller).
        Route::get('inventory/salon/export/{type}',        [SalonExportController::class, 'export']);
        Route::get('inventory/salon/feedback',             [SalonFeedbackController::class, 'index']);
        Route::post('inventory/salon/feedback',            [SalonFeedbackController::class, 'store']);
        Route::post('inventory/salon/feedback/{id}/resolve', [SalonFeedbackController::class, 'resolve']);
        Route::post('inventory/salon/campaigns',           [SalonClientController::class, 'sendCampaign']);
        Route::get('inventory/salon/rebook/due',           [SalonController::class, 'rebookDue']);
        // The diary: whoever may sell may look at it and book.
        Route::get('inventory/salon/appointments',         [AppointmentController::class, 'index']);
        Route::post('inventory/salon/appointments',        [AppointmentController::class, 'store']);
        Route::match(['put', 'patch'], 'inventory/salon/appointments/{id}', [AppointmentController::class, 'update']);
        Route::post('inventory/salon/appointments/{id}/status', [AppointmentController::class, 'status']);
        // People at work: attendance, days off and the cash of each shift. A person sees only their own; the owner
        // and managers see everyone's (checked in the controller).
        Route::get('inventory/salon/days-off',             [SalonStaffController::class, 'daysOff']);
        Route::post('inventory/salon/days-off',            [SalonStaffController::class, 'storeDayOff']);
        Route::delete('inventory/salon/days-off/{id}',     [SalonStaffController::class, 'destroyDayOff']);
        Route::get('inventory/salon/attendance',           [SalonStaffController::class, 'attendance']);
        Route::get('inventory/salon/attendance/today',     [SalonStaffController::class, 'attendanceToday']);
        Route::post('inventory/salon/attendance/clock-in', [SalonStaffController::class, 'clockIn']);
        Route::post('inventory/salon/attendance/clock-out', [SalonStaffController::class, 'clockOut']);
        Route::get('inventory/salon/shifts',               [SalonStaffController::class, 'shifts']);
        Route::get('inventory/salon/shifts/current',       [SalonStaffController::class, 'currentShift']);
        Route::post('inventory/salon/shifts/open',         [SalonStaffController::class, 'openShift']);
        Route::post('inventory/salon/shifts/{id}/close',   [SalonStaffController::class, 'closeShift']);
    });
    Route::middleware('inv_perm:inv_manage_products,inv_create_sales')->group(function () {
        // PUT as well as PATCH: the app's HTTP client has PUT, and this changes only the two fields it is given.
        Route::match(['put', 'patch'], 'inventory/salon/clients/{id}', [SalonController::class, 'updateClient']);
    });
    // Results per stylist: the owner and managers see everyone, a stylist only their own line.
    Route::middleware('inv_perm:inv_view_reports,inv_create_sales')->group(function () {
        Route::get('inventory/salon/stylists',             [SalonController::class, 'stylists']);
        Route::get('inventory/salon/stylists/{staffId}/transactions', [SalonController::class, 'stylistTransactions']);
        Route::get('inventory/salon/services',             [SalonController::class, 'serviceSales']);
        // Profit and loss, the dashboard figures and payroll: the owner and managers only (checked in the controller too).
        Route::get('inventory/salon/profit-loss',          [SalonMoneyController::class, 'profitLoss']);
        Route::get('inventory/salon/overview',             [SalonMoneyController::class, 'overview']);
        Route::get('inventory/salon/staff-profiles',       [SalonMoneyController::class, 'profiles']);
        Route::get('inventory/salon/payroll',              [SalonMoneyController::class, 'payroll']);
        Route::get('inventory/salon/payouts',              [SalonMoneyController::class, 'payouts']);
    });
    Route::middleware('inv_perm:inv_manage_settings')->group(function () {
        Route::put('inventory/salon/settings',             [SalonController::class, 'updateSettings']);
        Route::match(['put', 'patch'], 'inventory/salon/staff-profiles/{staffId}', [SalonMoneyController::class, 'saveProfile']);
        Route::post('inventory/salon/payouts',             [SalonMoneyController::class, 'storePayout']);
        Route::delete('inventory/salon/payouts/{id}',      [SalonMoneyController::class, 'destroyPayout']);
    });

    // ── Product units & pricing ───────────────────────────────────────────────
    Route::middleware('inv_perm:inv_view_products')->group(function () {
        Route::get('inventory/products/{productId}/units', [InventoryProductUnitController::class, 'index']);
        Route::get('inventory/products/{product}/units',   [InventoryProductUnitController::class, 'index']);
        Route::get('inventory/products/{productId}/units/{unitId}/price-history', [InventoryProductUnitController::class, 'priceHistory']);
        Route::get('inventory/products/{product}/units/{unit}/price-history',     [InventoryProductUnitController::class, 'priceHistory']);
    });
    Route::middleware('inv_perm:inv_manage_products')->group(function () {
        Route::post('inventory/products/{productId}/units',              [InventoryProductUnitController::class, 'store']);
        Route::put('inventory/products/{productId}/units/{unitId}',      [InventoryProductUnitController::class, 'update']);
        Route::delete('inventory/products/{productId}/units/{unitId}',   [InventoryProductUnitController::class, 'destroy']);
        Route::post('inventory/products/{productId}/units/{unitId}/price',[InventoryProductUnitController::class, 'setPrice']);
        Route::post('inventory/products/{product}/units',                [InventoryProductUnitController::class, 'store']);
        Route::put('inventory/products/{product}/units/{unit}',          [InventoryProductUnitController::class, 'update']);
        Route::delete('inventory/products/{product}/units/{unit}',       [InventoryProductUnitController::class, 'destroy']);
        Route::post('inventory/products/{product}/units/{unit}/price',   [InventoryProductUnitController::class, 'setPrice']);
    });

    // ── Stock management (inv_manage_stock) ───────────────────────────────────
    Route::middleware('inv_perm:inv_manage_stock')->group(function () {
        Route::get('inventory/stock-movements',   [InventoryStockMovementController::class, 'index']);
        Route::get('stock-movements',             [InventoryStockMovementController::class, 'index']);
        Route::post('inventory/stock-movements',  [InventoryStockMovementController::class, 'store']);
        Route::post('stock-movements',            [InventoryStockMovementController::class, 'store']);
        Route::get('inventory/batches',           [InventoryBatchController::class, 'index']);
        Route::post('inventory/batches',          [InventoryBatchController::class, 'store']);
        Route::put('inventory/batches/{id}',      [InventoryBatchController::class, 'update']);
        Route::get('inventory/expiry-summary',    [InventoryBatchController::class, 'expirySummary']);
        Route::get('inventory/stock-counts',              [InventoryStockCountController::class, 'index']);
        Route::post('inventory/stock-counts',             [InventoryStockCountController::class, 'store']);
        Route::get('inventory/stock-counts/{id}',         [InventoryStockCountController::class, 'show']);
        Route::post('inventory/stock-counts/{id}/lines',  [InventoryStockCountController::class, 'saveLine']);
        Route::delete('inventory/stock-counts/{id}/lines/{line}', [InventoryStockCountController::class, 'deleteLine']);
        Route::post('inventory/stock-counts/{id}/post',   [InventoryStockCountController::class, 'post']);
        Route::post('inventory/stock-counts/{id}/cancel', [InventoryStockCountController::class, 'cancel']);
        Route::post('inventory/write-offs/{id}/decide', [InventoryWriteOffController::class, 'decide']);
        // Barcodes: generate needs manage_stock; resolve/labels only need view_products (above)
        Route::post('inventory/barcodes',        [InventoryBarcodeController::class, 'generate']);
    });
    // Reporting damage doesn't need full stock-management rights -- a narrower
    // inv_report_damage permission (e.g. sales_officer) can submit/view
    // write-offs alongside inv_manage_stock holders, but approving them
    // (above) stays exclusive to inv_manage_stock so nobody can self-approve
    // their own damage report.
    Route::middleware('inv_perm:inv_manage_stock,inv_report_damage')->group(function () {
        Route::get('inventory/write-offs',  [InventoryWriteOffController::class, 'index']);
        Route::post('inventory/write-offs', [InventoryWriteOffController::class, 'store']);
    });
    Route::middleware('inv_perm:inv_view_products')->group(function () {
        Route::get('inventory/barcodes/resolve', [InventoryBarcodeController::class, 'resolve']);
        Route::post('inventory/barcodes/labels', [InventoryBarcodeController::class, 'labels']);
    });

    // ── Sales (inv_create_sales / inv_manage_sales) ───────────────────────────
    Route::middleware('inv_perm:inv_create_sales')->group(function () {
        Route::get('inventory/kpis',                    [InventorySalesController::class, 'kpis']);
        Route::get('inventory/sales/monthly-chart',     [InventorySalesController::class, 'monthlyChart']);
        Route::get('inventory/sales/summary',           [InventorySalesController::class, 'summary']);
        Route::get('inventory/sales-officers',          [InventorySalesController::class, 'officers']);
        Route::get('inventory/sales',          [InventorySalesController::class, 'index']);
        Route::get('sales',                    [InventorySalesController::class, 'index']);
        Route::get('inventory/sales/{id}',     [InventorySalesController::class, 'show']);
        Route::get('sales/{id}',               [InventorySalesController::class, 'show']);
        Route::post('inventory/sales',         [InventorySalesController::class, 'store']);
        Route::post('sales',                   [InventorySalesController::class, 'store']);
        Route::post('inventory/sales/{id}/payments', [InventorySalesController::class, 'recordPayment']);
        Route::get('inventory/parked-sales',           [InventoryPosController::class, 'parkedSales']);
        Route::post('inventory/parked-sales',          [InventoryPosController::class, 'parkSale']);
        Route::post('inventory/parked-sales/{id}/resume',  [InventoryPosController::class, 'resumeParkedSale']);
        Route::delete('inventory/parked-sales/{id}',       [InventoryPosController::class, 'discardParkedSale']);
        Route::get('inventory/returns',        [InventoryPosController::class, 'returns']);
        Route::post('inventory/returns',       [InventoryPosController::class, 'storeReturn']);
        Route::get('inventory/discount-check', [InventoryPosController::class, 'checkDiscount']);
    });
    Route::middleware('inv_perm:inv_manage_sales')->group(function () {
        Route::post('inventory/sales/{id}/cancel',      [InventorySalesController::class, 'cancel']);
        Route::post('inventory/returns/{id}/decide',    [InventoryPosController::class, 'decideReturn']);
        Route::get('inventory/dispatches',              [InventoryDispatchController::class, 'index']);
        Route::get('inventory/dispatches/{id}',         [InventoryDispatchController::class, 'show']);
        Route::post('inventory/dispatches',             [InventoryDispatchController::class, 'store']);
        Route::post('inventory/dispatches/{id}/reconcile', [InventoryDispatchController::class, 'reconcile']);
    });

    // ── Reminders (inv_view_reminders) ────────────────────────────────────────
    Route::middleware('inv_perm:inv_view_reminders')->group(function () {
        Route::get('inventory/reminders',              [InventoryReminderController::class, 'index']);
        Route::put('inventory/reminders/{id}/done',    [InventoryReminderController::class, 'markDone']);
        Route::put('inventory/reminders/{id}/snooze',  [InventoryReminderController::class, 'snooze']);
    });

    // ── Purchasing / Supply chain (inv_view_purchasing) ───────────────────────
    Route::middleware('inv_perm:inv_view_purchasing')->group(function () {
        Route::get('inventory/suppliers',            [InventoryPurchasingController::class, 'suppliers']);
        Route::post('inventory/suppliers',           [InventoryPurchasingController::class, 'storeSupplier']);
        Route::put('inventory/suppliers/{id}',       [InventoryPurchasingController::class, 'updateSupplier']);
        Route::delete('inventory/suppliers/{id}',    [InventoryPurchasingController::class, 'destroySupplier']);
        Route::get('inventory/purchase-orders',     [InventoryPurchasingController::class, 'purchaseOrders']);
        Route::get('inventory/purchase-orders/{id}',[InventoryPurchasingController::class, 'showPurchaseOrder']);
        Route::post('inventory/purchase-orders',               [InventoryPurchasingController::class, 'storePurchaseOrder']);
        Route::post('inventory/purchase-orders/{id}/status',   [InventoryPurchasingController::class, 'setPurchaseOrderStatus']);
        Route::get('inventory/goods-receipts',      [InventoryPurchasingController::class, 'goodsReceipts']);
        Route::post('inventory/goods-receipts',     [InventoryPurchasingController::class, 'receiveGoods']);
        Route::get('inventory/supplier-invoices',   [InventoryPurchasingController::class, 'supplierInvoices']);
        Route::post('inventory/supplier-payments',  [InventoryPurchasingController::class, 'paySupplier']);
    });

    // ── Credit / Customers (inv_view_credit) ──────────────────────────────────
    Route::middleware('inv_perm:inv_view_credit')->group(function () {
        Route::get('inventory/credit/customers',            [InventoryCreditController::class, 'customers']);
        Route::put('inventory/credit/customers/{id}',       [InventoryCreditController::class, 'updateCredit']);
        Route::get('inventory/credit/customers/{id}/check', [InventoryCreditController::class, 'creditCheck']);
        Route::get('inventory/credit/customers/{id}/statement', [InventoryCreditController::class, 'statement']);
        Route::get('inventory/credit/customers/{id}/report', [InventoryCreditController::class, 'report']);
        Route::get('inventory/credit/debtors-ageing',       [InventoryCreditController::class, 'debtorsAgeing']);
    });

    // ── Daily Cash (inv_view_cash) ────────────────────────────────────────────
    Route::middleware('inv_perm:inv_view_cash')->group(function () {
        Route::post('inventory/payments',                    [InventoryCashController::class, 'receivePayment']);
        Route::get('inventory/cash-sessions',                [InventoryCashController::class, 'sessions']);
        Route::post('inventory/cash-sessions',               [InventoryCashController::class, 'openSession']);
        Route::get('inventory/cash-sessions/{id}',           [InventoryCashController::class, 'sessionSummary']);
        Route::post('inventory/cash-sessions/{id}/expenses', [InventoryCashController::class, 'addExpense']);
        Route::post('inventory/cash-sessions/{id}/close',    [InventoryCashController::class, 'closeSession']);
    });

    // ── Crates & Empties (inv_view_crates) ────────────────────────────────────
    Route::middleware('inv_perm:inv_view_crates')->group(function () {
        Route::get('inventory/crate-types',       [InventoryCrateController::class, 'types']);
        Route::get('inventory/crate-movements',   [InventoryCrateController::class, 'movements']);
        Route::post('inventory/crate-movements',  [InventoryCrateController::class, 'move']);
        Route::get('inventory/crate-balances',    [InventoryCrateController::class, 'customerBalances']);
        Route::get('inventory/crate-position',    [InventoryCrateController::class, 'depotPosition']);
    });

    // Crate types and the security deposit charged per crate are depot configuration,
    // so changing them needs the settings permission, not just access to crates.
    Route::middleware('inv_perm:inv_manage_settings')->group(function () {
        Route::post('inventory/crate-types',        [InventoryCrateController::class, 'storeType']);
        Route::put('inventory/crate-types/{id}',    [InventoryCrateController::class, 'updateType']);
        Route::delete('inventory/crate-types/{id}', [InventoryCrateController::class, 'destroyType']);
    });

    // ── Reports (inv_view_reports) ────────────────────────────────────────────
    Route::middleware('inv_perm:inv_view_reports')->group(function () {
        Route::get('inventory/reports',      [InventoryReportController::class, 'index']);
        Route::get('inventory/reports/{key}',[InventoryReportController::class, 'show']);
        Route::get('inventory/audit-log',    [InventoryAlertController::class, 'auditLog']);
    });

    // ── Expenses (inv_view_expenses / inv_manage_expenses) ────────────────────
    Route::middleware('inv_perm:inv_view_expenses')->group(function () {
        Route::get('inventory/expenses/summary',    [InventoryExpenseController::class, 'summary']);
        Route::get('inventory/expenses/categories', [InventoryExpenseController::class, 'categories']);
        Route::get('inventory/expenses',            [InventoryExpenseController::class, 'index']);
    });
    Route::middleware('inv_perm:inv_manage_expenses')->group(function () {
        Route::post('inventory/expenses',       [InventoryExpenseController::class, 'store']);
        Route::put('inventory/expenses/{id}',   [InventoryExpenseController::class, 'update']);
        Route::post('inventory/expenses/{id}/approval', [InventoryExpenseController::class, 'approval']);
        Route::post('inventory/expenses/{id}/receipt',  [InventoryExpenseController::class, 'receipt']);
        Route::delete('inventory/expenses/{id}',[InventoryExpenseController::class, 'destroy']);
    });

    // ── Depot Settings (inv_manage_settings) ──────────────────────────────────
    // Reading is needed to SELL (shop name/address/tax on the receipt, the
    // max-discount and tax limits at the POS), so anyone who can create sales
    // may read it. Only inv_manage_settings may change it.
    Route::middleware('inv_perm:inv_manage_settings,inv_create_sales')->group(function () {
        Route::get('inventory/settings',  [InventoryAlertController::class, 'settings']);
    });
    Route::middleware('inv_perm:inv_manage_settings')->group(function () {
        Route::put('inventory/settings',  [InventoryAlertController::class, 'updateSettings']);
    });

    // ── Approval notifications (any authenticated user, own inbox only) ──────
    // (The Salon service uses the same inbox: its alerts about cash, spending and bookings arrive here.)
    Route::middleware('service:inventory,salon')->group(function () {
        Route::get('inventory/notifications',               [InventoryNotificationController::class, 'index']);
        Route::post('inventory/notifications/{id}/read',    [InventoryNotificationController::class, 'markRead']);
        Route::post('inventory/notifications/read-all',     [InventoryNotificationController::class, 'markAllRead']);
    });

    // Admin routes (Vehicle Owner/Admin only)
    Route::middleware(['role:admin', 'service:transport'])->group(function () {
        Route::prefix('admin')->group(function () {
            // Dashboard
            Route::get('dashboard', [AdminController::class, 'dashboard']);

            // Vehicle management
            Route::get('vehicles', [AdminController::class, 'getVehicles']);
            Route::post('vehicles', [AdminController::class, 'createVehicle']);
            Route::post('assign-driver', [AdminController::class, 'assignDriverToVehicle']);

            // Payment management
            Route::post('record-payment', [AdminController::class, 'recordPayment']);
            Route::get('payment-history', [AdminController::class, 'getPaymentHistory']);

            // Receipt management
            Route::post('generate-receipt', [AdminController::class, 'generateReceipt']);

            // Reminders/Notes
            Route::post('reminders', [AdminController::class, 'addReminder']);

            // Reports (admin view) - DISABLED - Using temporary routes instead
            // Route::prefix('reports')->group(function () {
            //     Route::get('dashboard', [ReportController::class, 'dashboard']);
            //     Route::get('revenue', [ReportController::class, 'revenue']);
            //     Route::get('expenses', [ReportController::class, 'expenses']);
            //     Route::get('profit-loss', [ReportController::class, 'profitLoss']);
            //     Route::get('device-performance', [ReportController::class, 'devicePerformance']);
            //     Route::post('export-pdf', [ReportController::class, 'exportPdf']);
            // });
        });
    });

    // Driver routes (Read-only view for drivers)
    Route::middleware(['role:driver', 'service:transport'])->group(function () {
        Route::prefix('driver')->group(function () {
            // Driver dashboard (read-only)
            Route::get('dashboard', [DriverViewController::class, 'dashboard']);
            Route::get('profile', [DriverViewController::class, 'getProfile']);

            // Payments summary (driver-authorized)
            Route::get('payments/summary', [DriverViewController::class, 'getPaymentsSummary']);

            // Payments list and history
            Route::get('payments', [DriverViewController::class, 'getPayments']);
            Route::get('payment-history', [DriverViewController::class, 'getPaymentHistory']);

            // Debts for driver
            Route::get('debts/records', [DriverViewController::class, 'getDebtRecords']);

            // View receipts
            Route::get('receipts', [DriverViewController::class, 'getReceipts']);

            // Submit payment request (for admin approval)
            Route::post('submit-payment-request', [DriverViewController::class, 'submitPaymentRequest']);

            // View reminders from admin
            Route::get('reminders', [DriverViewController::class, 'getReminders']);
        });
    });

    // Rental Service Module
    Route::prefix('rental')->middleware('service:rental')->group(function () {
        // Landlord & Admin routes
        Route::middleware(['role:admin,landlord'])->group(function () {
            // Branches of the rental business (offices, areas): properties belong to one, and everything on them follows.
            Route::prefix('branches')->group(function () {
                Route::get('', [\App\Http\Controllers\API\BusinessBranchController::class, 'index'])->defaults('service', 'rental');
                Route::post('', [\App\Http\Controllers\API\BusinessBranchController::class, 'store'])->defaults('service', 'rental');
                Route::put('{id}', [\App\Http\Controllers\API\BusinessBranchController::class, 'update'])->defaults('service', 'rental')->whereNumber('id');
                Route::delete('{id}', [\App\Http\Controllers\API\BusinessBranchController::class, 'destroy'])->defaults('service', 'rental')->whereNumber('id');
            });

            // Properties
            Route::prefix('properties')->group(function () {
                Route::get('', [PropertyController::class, 'index']);
                Route::get('stats', [PropertyController::class, 'stats']);
                Route::get('trashed', [PropertyController::class, 'trashed']);
                Route::post('', [PropertyController::class, 'store']);
                Route::get('{id}', [PropertyController::class, 'show']);
                Route::put('{id}', [PropertyController::class, 'update']);
                Route::delete('{id}', [PropertyController::class, 'destroy']);
                Route::post('{id}/restore', [PropertyController::class, 'restore']);
                Route::post('{id}/houses', [PropertyController::class, 'addHouse']);
                Route::get('{id}/houses', [HouseController::class, 'getByProperty']);
            });

            // Blocks
            Route::prefix('blocks')->group(function () {
                Route::get('{propertyId}', [BlockController::class, 'index']);
                Route::post('{propertyId}', [BlockController::class, 'store']);
                Route::get('block/{id}', [BlockController::class, 'show']);
                Route::put('block/{id}', [BlockController::class, 'update']);
                Route::delete('block/{id}', [BlockController::class, 'destroy']);
            });

            // Houses
            Route::prefix('houses')->group(function () {
                Route::get('', [HouseController::class, 'index']);
                Route::post('', [HouseController::class, 'store']);
                Route::get('{id}', [HouseController::class, 'show']);
                Route::put('{id}', [HouseController::class, 'update']);
                Route::delete('{id}', [HouseController::class, 'destroy']);
            });

            // Tenants
            Route::prefix('tenants')->group(function () {
                Route::get('', [TenantController::class, 'index']);
                Route::get('system', [TenantController::class, 'availableSystemTenants']);
                Route::get('{id}', [TenantController::class, 'show']);
                Route::post('onboard', [TenantController::class, 'onboard']);
                Route::put('{id}/status', [TenantController::class, 'updateStatus']);
                Route::delete('{id}', [TenantController::class, 'terminate']);
            });

            // Payments
            Route::prefix('payments')->group(function () {
                Route::get('', [BillingController::class, 'getPayments']);
                Route::post('record', [BillingController::class, 'recordPayment']);
            });

            // Receipts
            Route::prefix('receipts')->group(function () {
                Route::get('', [BillingController::class, 'getReceipts']);
                Route::get('{id}', [BillingController::class, 'getReceipt']);
                Route::post('{id}/dispatch', [BillingController::class, 'dispatchReceipt']);
            });

            // Reports
            Route::get('dashboard', [BillingController::class, 'getDashboard']);
            Route::get('reports/arrears', [BillingController::class, 'getArrears']);
            Route::get('reports/revenue', [BillingController::class, 'getRevenue']);
            Route::get('reports/occupancy', [BillingController::class, 'getOccupancy']);
            Route::get('reports/houses', [HouseController::class, 'index']);

            // Caretakers
            Route::prefix('caretakers')->group(function () {
                Route::get('', [CaretakerController::class, 'index']);
                Route::post('', [CaretakerController::class, 'store']);
                Route::put('{id}', [CaretakerController::class, 'update']);
                Route::delete('{id}', [CaretakerController::class, 'destroy']);
                Route::post('{id}/assign', [CaretakerController::class, 'assignProperties']);
            });

            // Lease Agreements
            Route::prefix('agreements')->group(function () {
                Route::get('', [AgreementController::class, 'index']);
                Route::get('expiring', [AgreementController::class, 'getExpiring']);
                Route::post('', [AgreementController::class, 'store']);
                Route::get('{id}', [AgreementController::class, 'show']);
                Route::post('{id}/renew', [AgreementController::class, 'renew']);
                Route::post('{id}/terminate', [AgreementController::class, 'terminate']);
                Route::post('{id}/documents', [AgreementController::class, 'uploadDocument']);
            });
        });

        // Shared Maintenance Routes (Landlords, Tenants, Caretakers, Vendors)
        Route::middleware(['role:admin,landlord,caretaker,tenant,vendor'])->prefix('maintenance')->group(function () {
            // View/Create Requests & Vendors
            Route::get('requests', [MaintenanceController::class, 'index']);
            Route::post('requests', [MaintenanceController::class, 'store']);
            Route::get('requests/{id}', [MaintenanceController::class, 'show']);
            Route::get('vendors', [MaintenanceController::class, 'getVendors']);

            // Vendors and management can update status
            Route::put('requests/{id}/status', [MaintenanceController::class, 'updateStatus'])->middleware('role:admin,landlord,vendor');

            // Marketplace and Roster functionality (Landlords only)
            Route::middleware(['role:admin,landlord,caretaker'])->group(function () {
                Route::get('marketplace/vendors', [MaintenanceController::class, 'getMarketplaceVendors']);
                Route::post('vendors/{id}/save', [MaintenanceController::class, 'saveToRoster']);
                Route::post('vendors/{id}/remove', [MaintenanceController::class, 'removeFromRoster']);
            });

            // Strictly restricted management routes
            Route::middleware(['role:admin,landlord'])->group(function () {
                Route::post('requests/{id}/assign', [MaintenanceController::class, 'assign']);

                Route::post('vendors', [MaintenanceController::class, 'storeVendor']);

                Route::get('preventive', [MaintenanceController::class, 'getPreventive']);
                Route::post('preventive', [MaintenanceController::class, 'storePreventive']);
            });
        });

        // Tenant self-service routes (admins/landlords can preview empty views safely)
        Route::middleware(['role:tenant,admin,landlord'])->group(function () {
            Route::get('tenant/bills', [TenantController::class, 'myBills']);
            Route::get('tenant/payments', [TenantController::class, 'myPayments']);
            Route::get('tenant/receipts', [TenantController::class, 'myReceipts']);
        });

        // Common routes (Landlord, Caretaker, Tenant)
        Route::middleware(['role:admin,landlord,caretaker,tenant'])->group(function () {
            Route::get('billing/bills', [BillingController::class, 'getBills']);
        });
    });


    // Common routes (all authenticated users)
    Route::prefix('common')->group(function () {
        // Basic user info
        Route::get('profile', [AuthController::class, 'user']);
    });
});

// Health check route
Route::get('health', function () {
    // No PHP or framework version here: this is public, and it is nobody's business what the server runs.
    return response()->json([
        'status' => 'success',
        'message' => '3 in One API is running',
        'timestamp' => now()->toISOString(),
        'version' => config('app.api_version'),
        'server_time' => date('Y-m-d H:i:s'),
    ]);
});

// Removed testing and debug routes for production

// Fallback route for undefined API endpoints
Route::fallback(function () {
    return response()->json([
        'status' => 'error',
        'message' => 'API endpoint not found',
        'requested_url' => request()->fullUrl(),
        'available_endpoints' => [
            'GET /api/health',
            'GET /api/test',
            'GET /api/debug',
            'POST /api/auth/login',
            'POST /api/auth/forgot-password',
            'POST /api/auth/reset-password',
        ],
    ], 404);
});