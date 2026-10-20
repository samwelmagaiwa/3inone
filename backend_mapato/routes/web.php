<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Web\AdminDashboardController;

// Status page: what a person sees when they open the server's address in a browser. It shows only what is
// safe to show (that the API is running, its version, the time) and needs nothing from the database, so it
// still answers when the database is down: no session is started for it. /api/health is the check for programs.
Route::get('/', function () {
    return response()
        ->view('status', [
            'version' => config('app.api_version'),
            'time' => now()->utc()->format('Y-m-d H:i:s'),
            'year' => now()->utc()->year,
        ])
        ->header('Cache-Control', 'no-store')
        ->header('X-Robots-Tag', 'noindex, nofollow');
})->withoutMiddleware([
    \Illuminate\Session\Middleware\StartSession::class,
    \Illuminate\View\Middleware\ShareErrorsFromSession::class,
    \Illuminate\Foundation\Http\Middleware\ValidateCsrfToken::class,
]);

// The page a client opens from the text a salon sends after a visit: rate it, leave a comment or a complaint. It needs
// no sign-in and no session; the secret is in the link.
Route::get('/f/{token}', [\App\Http\Controllers\API\Inventory\SalonFeedbackController::class, 'page'])
    ->middleware('throttle:60,1')
    ->withoutMiddleware([
        \Illuminate\Session\Middleware\StartSession::class,
        \Illuminate\View\Middleware\ShareErrorsFromSession::class,
        \Illuminate\Foundation\Http\Middleware\ValidateCsrfToken::class,
    ]);

// Admin Dashboard Routes
Route::prefix('admin')->middleware(['auth:sanctum', 'role:admin'])->group(function () {
    Route::get('/dashboard', [AdminDashboardController::class, 'index'])->name('admin.dashboard');
    Route::get('/dashboard/data', [AdminDashboardController::class, 'getData'])->name('admin.dashboard.data');
    Route::get('/dashboard/revenue-chart', [AdminDashboardController::class, 'getRevenueChart'])->name('admin.dashboard.revenue-chart');
});

// Fallback route for admin (redirect to dashboard)
Route::get('/admin', function () {
    return redirect()->route('admin.dashboard');
})->middleware(['auth:sanctum', 'role:admin']);
