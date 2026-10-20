<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Http\Requests\LoginRequest;
use App\Http\Requests\RegisterDriverRequest;
use App\Models\Business;
use App\Models\User;
use App\Models\Driver;
use App\Models\Device;
use App\Helpers\ResponseHelper;
use App\Services\Sms\SmsCodes;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Password;
use Illuminate\Validation\ValidationException;
use Illuminate\Support\Str;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;
use OpenApi\Attributes as OA;

#[OA\Tag(name: 'Auth', description: 'Login, session, and account endpoints shared by every service.')]
class AuthController extends Controller
{

    /**
     * Login with credentials (direct authentication)
     */
    #[OA\Post(
        path: '/auth/login',
        summary: 'Log in and receive a bearer token',
        description: 'Validates email + password + phone number together (phone must match the '
            . 'number on file). Returns the user profile, effective permissions, and a Sanctum '
            . 'token to use as `Authorization: Bearer <token>` on every subsequent request.',
        tags: ['Auth'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['email', 'password', 'phone_number'],
                properties: [
                    new OA\Property(property: 'email', type: 'string', format: 'email', example: 'admin@gmail.com'),
                    new OA\Property(property: 'password', type: 'string', format: 'password', example: '12345678'),
                    new OA\Property(property: 'phone_number', type: 'string', example: '+255743519104'),
                ],
            ),
        ),
        responses: [
            new OA\Response(
                response: 200,
                description: 'Login successful',
                content: new OA\JsonContent(properties: [
                    new OA\Property(property: 'status', type: 'string', example: 'success'),
                    new OA\Property(property: 'message', type: 'string', example: 'Login successful'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'user', ref: '#/components/schemas/User'),
                        new OA\Property(property: 'token', type: 'string', example: '104|S8eZuEzqFiyKbmo7WxTc...'),
                        new OA\Property(property: 'role', type: 'string', example: 'admin'),
                        new OA\Property(property: 'dashboard_route', type: 'string', example: '/admin/dashboard'),
                    ], type: 'object'),
                ], type: 'object'),
            ),
            new OA\Response(
                response: 401,
                description: 'Invalid credentials',
                content: new OA\JsonContent(ref: '#/components/schemas/ErrorResponse'),
            ),
            new OA\Response(
                response: 422,
                description: 'Validation failed (missing/malformed field)',
                content: new OA\JsonContent(ref: '#/components/schemas/ValidationErrorResponse'),
            ),
        ],
    )]
    public function login(Request $request)
    {
        // Log login attempt start
        Log::info('Login attempt started', [
            'email' => $request->email,
            'ip_address' => $request->ip(),
            'user_agent' => $request->userAgent(),
            'timestamp' => now()->toISOString(),
        ]);

        try {
            $request->validate(
                [
                    'email' => 'required|email',
                    'password' => 'required|string',
                    'phone_number' => ['required', 'regex:/^(0\d{9}|\+\d{9,15})$/'],
                ],
                [
                    'phone_number.required' => 'Namba ya simu inahitajika',
                    'phone_number.regex' => 'Namba ya simu si sahihi. Tumia namba ya ndani (mfano: 0743519100) au ya kimataifa (mfano: +255743519100).',
                ]
            );

            // Find user by email
            $user = User::where('email', $request->email)->first();

            if (!$user) {
                Log::warning('Login failed - User not found', [
                    'email' => $request->email,
                    'ip_address' => $request->ip(),
                    'user_agent' => $request->userAgent(),
                    'reason' => 'user_not_found',
                    'timestamp' => now()->toISOString(),
                ]);
                return ResponseHelper::error('Invalid credentials', 401);
            }

            // Verify password
            if (!Hash::check($request->password, $user->password)) {
                Log::warning('Login failed - Invalid password', [
                    'user_id' => $user->id,
                    'email' => $request->email,
                    'ip_address' => $request->ip(),
                    'user_agent' => $request->userAgent(),
                    'reason' => 'invalid_password',
                    'timestamp' => now()->toISOString(),
                ]);
                return ResponseHelper::error('Invalid credentials', 401);
            }

            // A business that registered itself cannot sign in until a super admin
            // approves it. Say so plainly rather than "account is inactive" -- the
            // password was correct, so this is not an enumeration risk.
            if (!$user->is_active) {
                $registration = $user->registration;
                if ($registration && $registration->status === \App\Models\BusinessRegistration::PENDING) {
                    return ResponseHelper::error(
                        'Usajili wako unasubiri idhini ya super admin. Utaweza kuingia baada ya kukubaliwa. / '
                        . 'Your registration is awaiting super admin approval. You can sign in once it is approved.',
                        403,
                        ['code' => 'registration_pending']
                    );
                }
                if ($registration && $registration->status === \App\Models\BusinessRegistration::REJECTED) {
                    return ResponseHelper::error(
                        'Usajili wako haukukubaliwa. Sababu: ' . ($registration->rejection_reason ?: '-') . ' / '
                        . 'Your registration was not approved. Reason: ' . ($registration->rejection_reason ?: '-'),
                        403,
                        ['code' => 'registration_rejected']
                    );
                }
            }

            // Check if user is active
            if (!$user->is_active) {
                Log::warning('Login failed - Account inactive', [
                    'user_id' => $user->id,
                    'email' => $request->email,
                    'ip_address' => $request->ip(),
                    'user_agent' => $request->userAgent(),
                    'reason' => 'account_inactive',
                    'timestamp' => now()->toISOString(),
                ]);
                return ResponseHelper::error('Account is inactive', 403);
            }

            // Everyone working for a business whose owner has been deactivated is shut out with
            // them. Nothing is deleted: re-activating the owner opens it all again.
            if (!$user->accountIsActive()) {
                Log::warning('Login failed - Business suspended', [
                    'user_id' => $user->id,
                    'email' => $request->email,
                    'ip_address' => $request->ip(),
                    'reason' => 'business_suspended',
                ]);
                return ResponseHelper::error(
                    'Biashara yako imesimamishwa. Wasiliana na msimamizi wako. / Your business has been suspended. Contact your administrator.',
                    403,
                    ['code' => 'business_suspended']
                );
            }

            // A business that has not paid (past its grace period, with billing enforced) cannot
            // sign in. Its drivers and tenants are its customers and are not held to this.
            if (!$user->seesAllAccounts() && !$user->isPortalUser()) {
                $business = Business::forUser($user);
                if ($business !== null && $business->blocksAccess()) {
                    return ResponseHelper::error(
                        'Usajili wa biashara yako umeisha. Wasiliana na msimamizi ili kuuhuisha. / '
                        . 'Your business subscription has expired. Contact your administrator to renew it.',
                        402,
                        ['code' => 'subscription_expired', 'plan' => $business->plan, 'valid_until' => $business->valid_until?->toIso8601String()]
                    );
                }
            }

            // Verify phone number matches (comparing last 9 digits for maximum compatibility)
            if (!$this->phoneMatches($user, $request->phone_number)) {
                Log::warning('Login failed - Phone number mismatch', [
                    'user_id' => $user->id,
                    'email' => $request->email,
                    'provided_phone' => $request->phone_number,
                    'registered_phone' => $user->phone_number,
                    'ip_address' => $request->ip(),
                    'user_agent' => $request->userAgent(),
                    'reason' => 'phone_mismatch',
                    'timestamp' => now()->toISOString(),
                ]);
                return ResponseHelper::error('Phone number does not match our records', 400);
            }

            // Update last login
            $user->updateLastLogin();

            // Record login activity
            try {
                \App\Models\LoginActivity::create([
                    'user_id' => $user->id,
                    'ip_address' => $request->ip(),
                    'user_agent' => $request->userAgent(),
                    'login_at' => now(),
                    'success' => true,
                ]);
            } catch (\Exception $e) {
                Log::warning('Failed to record login activity', [
                    'user_id' => $user->id,
                    'error' => $e->getMessage(),
                ]);
            }

            // Other devices stay signed in. (Only if a cap was configured are sessions beyond it dropped.)
            $tokensRevoked = $this->makeRoomForNewSession($user);

            $token = $user->createToken('auth_token')->plainTextToken;

            // Load relationships based on role
            $userData = $this->getUserDataWithRelations($user);

            // Log successful login
            Log::info('Login successful', [
                'user_id' => $user->id,
                'email' => $user->email,
                'name' => $user->name,
                'role' => $user->role,
                'phone_number' => $user->phone_number,
                'ip_address' => $request->ip(),
                'user_agent' => $request->userAgent(),
                'tokens_revoked' => $tokensRevoked,
                'dashboard_route' => $this->getDashboardRoute($user->role),
                'last_login_at' => $user->last_login_at,
                'timestamp' => now()->toISOString(),
            ]);

            // Build UI badges and gating flags
            $badges = [];
            if (method_exists($user, 'isSuperAdmin') && $user->isSuperAdmin()) {
                $badges[] = 'Super Admin';
            }

            $can = [
                'manage_all' => method_exists($user, 'isSuperAdmin') ? $user->isSuperAdmin() : false,
                'create_users' => method_exists($user, 'canCreateUsers') ? $user->canCreateUsers() : false,
                'manage_drivers' => method_exists($user, 'canManageDrivers') ? $user->canManageDrivers() : false,
            ];

            return ResponseHelper::success([
                'user' => $userData,
                'token' => $token,
                'role' => $user->role,
                'role_display' => $user->role_display ?? $user->role,
                'badges' => $badges,
                'can' => $can,
                'dashboard_route' => $this->getDashboardRoute($user->role),
            ], 'Login successful');

        } catch (ValidationException $e) {
            Log::error('Login failed - Validation error', [
                'email' => $request->email,
                'ip_address' => $request->ip(),
                'user_agent' => $request->userAgent(),
                'validation_errors' => $e->errors(),
                'reason' => 'validation_failed',
                'timestamp' => now()->toISOString(),
            ]);
            return ResponseHelper::error('Validation failed', 422, $e->errors());
        } catch (\Exception $e) {
            Log::error('Login failed - System error', [
                'email' => $request->email,
                'ip_address' => $request->ip(),
                'user_agent' => $request->userAgent(),
                'error_message' => $e->getMessage(),
                'error_file' => $e->getFile(),
                'error_line' => $e->getLine(),
                'reason' => 'system_error',
                'timestamp' => now()->toISOString(),
            ]);
            return ResponseHelper::error('Login failed: ' . $e->getMessage(), 500);
        }
    }



    /**
     * Create driver account (Admin only)
     */
    public function createDriver(RegisterDriverRequest $request)
    {
        try {
            $admin = $request->user();

            // Check if user can create drivers
            if (!$admin->canManageDrivers()) {
                return ResponseHelper::error('Insufficient permissions', 403);
            }

            // Create user account
            $user = User::create([
                'name' => $request->name,
                'email' => $request->email,
                'password' => Hash::make($request->password),
                'phone_number' => $request->phone_number,
                'role' => 'driver',
                'created_by' => $admin->id,
                'device_id' => $request->device_id,
                'is_active' => true,
            ]);

            // Create driver profile
            $driver = Driver::create([
                'user_id' => $user->id,
                'license_number' => $request->license_number,
                'license_expiry' => $request->license_expiry,
                'address' => $request->address,
                'emergency_contact' => $request->emergency_contact,
                'national_id' => $request->national_id,
                'is_active' => true,
            ]);

            // Update device assignment if provided
            if ($request->device_id) {
                Device::where('id', $request->device_id)->update(['driver_id' => $driver->id]);
            }

            // Bind driver to transport service so they only see that module on login
            $user->services()->delete();
            $user->services()->create(['service_type' => 'transport']);

            $user->load('driver', 'assignedDevice', 'services');

            return ResponseHelper::success([
                'user' => $user,
                'driver' => $driver,
            ], 'Driver created successfully', 201);

        } catch (\Exception $e) {
            return ResponseHelper::error('Driver creation failed: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Step 1 of password recovery. Whoever asks must know the account's email AND the
     * phone number on it; a one-time code is then TEXTED to that phone. Nothing that proves
     * identity is ever returned in the response: the code reaches only whoever really holds
     * the phone.
     *
     * The answer is identical whether or not the details matched, so this cannot be used to
     * find out which emails or numbers are registered. Rate-limited on the route.
     */
    #[OA\Post(
        path: '/auth/forgot-password',
        summary: 'Forgot password: text a one-time code to the registered phone',
        tags: ['Auth'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['email', 'phone_number'],
                properties: [
                    new OA\Property(property: 'email', type: 'string', format: 'email'),
                    new OA\Property(property: 'phone_number', type: 'string'),
                ],
            ),
        ),
        responses: [
            new OA\Response(response: 200, description: 'A code was sent if the details are correct'),
            new OA\Response(response: 503, description: 'Text messages are not available'),
        ],
    )]
    public function forgotPassword(Request $request, SmsCodes $codes)
    {
        try {
            $request->validate(
                [
                    'email' => 'required|email',
                    'phone_number' => ['required', 'regex:/^(0\d{9}|\+\d{9,15})$/'],
                ],
                [
                    'phone_number.required' => 'Namba ya simu inahitajika',
                    'phone_number.regex' => 'Namba ya simu si sahihi. Tumia namba ya ndani (mfano: 0743519100) au ya kimataifa (mfano: +255743519100).',
                ]
            );
        } catch (ValidationException $e) {
            return ResponseHelper::error('Validation failed', 422, $e->errors());
        }

        // If no code can be texted at all, say so for everybody: that tells an outsider nothing
        // about any account, and it stops a reset from "succeeding" with a code nobody receives.
        if (!$codes->available()) {
            Log::error('Password reset unavailable: no SMS provider is switched on.');

            return ResponseHelper::error(
                'Huduma ya ujumbe mfupi haipatikani sasa. Wasiliana na msimamizi wako akubadilishie nywila. / '
                . 'Text messages are not available right now. Ask your administrator to reset your password.',
                503,
                ['code' => 'sms_unavailable']
            );
        }

        $user = User::where('email', $request->email)->first();

        if ($user && $user->is_active && $user->accountIsActive() && $this->phoneMatches($user, $request->phone_number)) {
            $result = $codes->issue(
                $user,
                SmsCodes::PASSWORD_RESET,
                'Nambari ya kubadili nywila / Password reset code: :code. Dakika 10 / 10 min. Usimpe mtu / Do not share.'
            );
            Log::info('Password reset code requested', ['user_id' => $user->id, 'result' => $result, 'ip_address' => $request->ip()]);
        } else {
            Log::warning('Password reset requested with details that do not match an active account', [
                'email' => $request->email,
                'ip_address' => $request->ip(),
            ]);
        }

        return ResponseHelper::success(
            ['code_sent' => true, 'expires_in_minutes' => 10],
            'Kama taarifa ni sahihi, nambari ya kuthibitisha imetumwa kwa simu yako. / '
            . 'If the details are correct, a verification code has been sent to your phone.'
        );
    }

    /**
     * Step 2: the code texted in step 1 plus the new password. Five wrong tries, or ten
     * minutes, and the code is dead; a right one is used up. Every device is signed out.
     */
    #[OA\Post(
        path: '/auth/reset-password',
        summary: 'Reset password with the code that was texted',
        tags: ['Auth'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['email', 'code', 'password', 'password_confirmation'],
                properties: [
                    new OA\Property(property: 'email', type: 'string', format: 'email'),
                    new OA\Property(property: 'code', type: 'string', example: '123456'),
                    new OA\Property(property: 'password', type: 'string'),
                    new OA\Property(property: 'password_confirmation', type: 'string'),
                ],
            ),
        ),
        responses: [new OA\Response(response: 200, description: 'Password changed')],
    )]
    public function resetPassword(Request $request, SmsCodes $codes)
    {
        try {
            $request->validate([
                'email' => 'required|email',
                'code' => ['required', 'digits:6'],
                'password' => 'required|string|min:8|confirmed',
            ]);
        } catch (ValidationException $e) {
            return ResponseHelper::error('Validation failed', 422, $e->errors());
        }

        $generic = 'Nambari si sahihi au imeisha muda. Omba nambari mpya. / The code is wrong or has expired. Request a new one.';

        $user = User::where('email', $request->email)->first();

        if (
            !$user
            || !$user->is_active
            || !$user->accountIsActive()
            || !$codes->verify($user, SmsCodes::PASSWORD_RESET, (string) $request->code)
        ) {
            Log::warning('Password reset failed: bad email or code', ['email' => $request->email, 'ip_address' => $request->ip()]);

            return ResponseHelper::error($generic, 422);
        }

        // They chose this one themselves, so it is no longer a temporary password.
        $user->forceFill(['password' => Hash::make($request->password), 'must_change_password' => false])->save();

        // Force every device to sign in again with the new password.
        $user->tokens()->delete();

        Log::info('Password reset completed', ['user_id' => $user->id, 'ip_address' => $request->ip()]);

        return ResponseHelper::success(null, 'Password reset successfully');
    }


    /**
     * Same last-9-digit comparison used everywhere a login-time phone check
     * happens, so login() and forgotPassword() can never silently drift
     * apart on what counts as a match.
     */
    private function phoneMatches(User $user, string $providedPhone): bool
    {
        $normalize = fn (string $number): string => preg_replace('/[^0-9]/', '', $number);

        return substr($normalize($user->phone_number ?? ''), -9)
            === substr($normalize($providedPhone), -9);
    }

    /**
     * Logout user
     */
    #[OA\Post(
        path: '/auth/logout',
        summary: 'Log out and revoke the current token',
        security: [['bearerAuth' => []]],
        tags: ['Auth'],
        responses: [
            new OA\Response(response: 200, description: 'Logged out successfully'),
            new OA\Response(response: 401, description: 'Unauthenticated', content: new OA\JsonContent(ref: '#/components/schemas/ErrorResponse')),
        ],
    )]
    public function logout(Request $request)
    {
        try {
            $user = $request->user();
            
            // Log logout attempt
            Log::info('Logout attempt', [
                'user_id' => $user->id,
                'email' => $user->email,
                'name' => $user->name,
                'role' => $user->role,
                'ip_address' => $request->ip(),
                'user_agent' => $request->userAgent(),
                'timestamp' => now()->toISOString(),
            ]);
            
            $request->user()->currentAccessToken()->delete();

            // Record logout time on latest login activity
            try {
                $last = \App\Models\LoginActivity::where('user_id', $user->id)
                    ->orderByDesc('login_at')
                    ->first();
                if ($last && !$last->logout_at) {
                    $last->logout_at = now();
                    $last->save();
                }
            } catch (\Exception $e) {
                Log::warning('Failed to record logout activity', [
                    'user_id' => $user->id,
                    'error' => $e->getMessage(),
                ]);
            }

            // Log successful logout
            Log::info('Logout successful', [
                'user_id' => $user->id,
                'email' => $user->email,
                'ip_address' => $request->ip(),
                'timestamp' => now()->toISOString(),
            ]);

            return ResponseHelper::success(null, 'Logged out successfully');
        } catch (\Exception $e) {
            Log::error('Logout failed', [
                'user_id' => $request->user()?->id,
                'email' => $request->user()?->email,
                'ip_address' => $request->ip(),
                'error_message' => $e->getMessage(),
                'timestamp' => now()->toISOString(),
            ]);
            return ResponseHelper::error('Logout failed: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get authenticated user
     */
    #[OA\Get(
        path: '/auth/user',
        summary: "Get the logged-in user's current profile",
        description: 'Always fetches fresh from the database (with role/service backfill applied), '
            . 'so call this after login instead of trusting a stale cached profile.',
        security: [['bearerAuth' => []]],
        tags: ['Auth'],
        responses: [
            new OA\Response(
                response: 200,
                description: 'Current user data',
                content: new OA\JsonContent(properties: [
                    new OA\Property(property: 'user', ref: '#/components/schemas/User'),
                    new OA\Property(property: 'role', type: 'string'),
                    new OA\Property(property: 'dashboard_route', type: 'string'),
                ], type: 'object'),
            ),
            new OA\Response(response: 401, description: 'Unauthenticated', content: new OA\JsonContent(ref: '#/components/schemas/ErrorResponse')),
        ],
    )]
    #[OA\Get(
        path: '/common/profile',
        summary: "Get the logged-in user's current profile",
        description: 'Always fetches fresh from the database (with role/service backfill applied), '
            . 'so call this after login instead of trusting a stale cached profile.',
        security: [['bearerAuth' => []]],
        tags: ['Auth'],
        responses: [
            new OA\Response(
                response: 200,
                description: 'Current user data',
                content: new OA\JsonContent(properties: [
                    new OA\Property(property: 'user', ref: '#/components/schemas/User'),
                    new OA\Property(property: 'role', type: 'string'),
                    new OA\Property(property: 'dashboard_route', type: 'string'),
                ], type: 'object'),
            ),
            new OA\Response(response: 401, description: 'Unauthenticated', content: new OA\JsonContent(ref: '#/components/schemas/ErrorResponse')),
        ],
    )]
    public function user(Request $request)
    {
        try {
            $user = $request->user();
            $userData = $this->getUserDataWithRelations($user);

            // Build UI badges and gating flags
            $badges = [];
            if (method_exists($user, 'isSuperAdmin') && $user->isSuperAdmin()) {
                $badges[] = 'Super Admin';
            }

            $can = [
                'manage_all' => method_exists($user, 'isSuperAdmin') ? $user->isSuperAdmin() : false,
                'create_users' => method_exists($user, 'canCreateUsers') ? $user->canCreateUsers() : false,
                'manage_drivers' => method_exists($user, 'canManageDrivers') ? $user->canManageDrivers() : false,
            ];

            return ResponseHelper::success([
                'user' => $userData,
                'role' => $user->role,
                'role_display' => $user->role_display ?? $user->role,
                'badges' => $badges,
                'can' => $can,
                'dashboard_route' => $this->getDashboardRoute($user->role),
            ], 'User data retrieved successfully');

        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve user data: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Upload or update user avatar/profile photo
     */
    #[OA\Post(
        path: '/auth/profile/avatar',
        summary: 'Upload avatar',
        security: [['bearerAuth' => []]],
        tags: ['Auth'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\MediaType(
                mediaType: 'multipart/form-data',
                schema: new OA\Schema(properties: [
                    new OA\Property(property: 'avatar', type: 'string', format: 'binary', description: 'Also accepted as `photo` or `image`'),
                ]),
            ),
        ),
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    #[OA\Post(
        path: '/auth/profile/photo',
        summary: 'Upload avatar',
        security: [['bearerAuth' => []]],
        tags: ['Auth'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\MediaType(
                mediaType: 'multipart/form-data',
                schema: new OA\Schema(properties: [
                    new OA\Property(property: 'avatar', type: 'string', format: 'binary', description: 'Also accepted as `photo` or `image`'),
                ]),
            ),
        ),
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    #[OA\Post(
        path: '/auth/profile/image',
        summary: 'Upload avatar',
        security: [['bearerAuth' => []]],
        tags: ['Auth'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\MediaType(
                mediaType: 'multipart/form-data',
                schema: new OA\Schema(properties: [
                    new OA\Property(property: 'avatar', type: 'string', format: 'binary', description: 'Also accepted as `photo` or `image`'),
                ]),
            ),
        ),
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function uploadAvatar(Request $request)
    {
        try {
            $user = $request->user();

            // Accept any of these field names from clients
            $file = $request->file('avatar') ?? $request->file('photo') ?? $request->file('image');
            if (!$file) {
                return ResponseHelper::error('No image file provided', 422);
            }

            // Basic validation: ensure upload is valid and size is reasonable (~2MB)
            if (!$file->isValid()) {
                return ResponseHelper::error('Invalid image upload', 422);
            }
            if (($file->getSize() ?? 0) > 2 * 1024 * 1024) {
                return ResponseHelper::error('Image too large (max 2MB)', 422);
            }

            $ext = strtolower($file->getClientOriginalExtension() ?: 'jpg');
            if (!in_array($ext, ['jpg','jpeg','png','webp'])) {
                $ext = 'jpg';
            }

            // Remove previous avatar if exists
            if (!empty($user->avatar_url)) {
                $oldPath = str_replace('/storage/', '', $user->avatar_url);
                if ($oldPath) {
                    Storage::disk('public')->delete($oldPath);
                }
            }

            // Store new avatar on public disk
            $path = $file->storeAs('avatars', $user->id.'_'.Str::random(16).'.'.$ext, 'public'); // random, not the time: the name cannot be guessed
            $publicUrl = '/storage/'.$path;

            // Persist path on user (requires nullable column `avatar_url`)
            if (Schema::hasColumn('users', 'avatar_url')) {
                $user->avatar_url = $publicUrl;
                $user->save();
            }

            $fresh = $this->getUserDataWithRelations($user->fresh());
            // Ensure avatar_url is present in response even if column is missing
            $fresh->setAttribute('avatar_url', $publicUrl);

            return ResponseHelper::success([
                'user' => $fresh,
            ], 'Avatar updated successfully');
        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to upload avatar: '.$e->getMessage(), 500);
        }
    }

    /**
     * Clear dead token rows and, if the account is already at its session cap,
     * revoke its OLDEST live sessions so the login about to happen leaves at most
     * `sanctum.max_sessions` of them.
     *
     * A "live session" is a normal token. Rows retired by /auth/refresh (they carry
     * a short grace expiry) and tokens past the configured lifetime are not
     * sessions, so they neither count toward the cap nor get to push a real one out.
     *
     * @return int how many live sessions were revoked to make room (normally 0)
     */
    private function makeRoomForNewSession(User $user): int
    {
        $lifetime = (int) config('sanctum.expiration');

        $user->tokens()
            ->where(function ($dead) use ($lifetime) {
                $dead->where('expires_at', '<=', now());
                if ($lifetime > 0) {
                    $dead->orWhere('created_at', '<=', now()->subMinutes($lifetime));
                }
            })
            ->delete();

        // No cap unless one was configured: signing in somewhere new never signs anyone out.
        $max = (int) config('sanctum.max_sessions', 0);
        if ($max <= 0) {
            return 0;
        }

        $live = $user->tokens()->whereNull('expires_at')->orderBy('id')->pluck('id');

        $excess = $live->count() - ($max - 1);   // leave room for the new one
        if ($excess <= 0) {
            return 0;
        }

        $user->tokens()->whereIn('id', $live->take($excess)->all())->delete();

        return $excess;
    }

    /**
     * Refresh token
     */
    #[OA\Post(
        path: '/auth/refresh',
        summary: 'Refresh',
        security: [['bearerAuth' => []]],
        tags: ['Auth'],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function refresh(Request $request)
    {
        try {
            $user = $request->user();

            // Retire the current token after a grace period instead of deleting it: if
            // the response is lost on a flaky mobile connection the app still holds the
            // old token, which must keep working long enough to retry -- even if the phone
            // is offline for days. Only THIS device's token is touched; the user's other
            // devices are unaffected.
            $request->user()->currentAccessToken()->forceFill([
                'expires_at' => now()->addMinutes((int) config('sanctum.refresh_grace_minutes', 60 * 24 * 7)),
            ])->save();

            $token = $user->createToken('auth_token')->plainTextToken;

            return ResponseHelper::success([
                'token' => $token,
            ], 'Token refreshed successfully');

        } catch (\Exception $e) {
            return ResponseHelper::error('Token refresh failed: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Get user data with appropriate relations based on role.
     * Always appends effective_permissions so the client has the fully
     * resolved list (role defaults ∪ explicit grants) without a second call.
     */
    private function getUserDataWithRelations(User $user): User
    {
        $user->load('services');

        // The client reads service access from the serialized `services`
        // relation, so a role's implicit access (super_admin -> all three,
        // sales_officer/driver/landlord/etc -> their one default -- see
        // User::allowedServiceTypes()) has to be materialized into real
        // user_services rows for it to show up in the response at all.
        // This used to only run for super_admin, so every other role with
        // zero explicit bindings got an empty `services` array and the
        // client's "no access to any service" screen -- same bug already
        // fixed for super_admin here, just missed for everyone else.
        $implied = $user->full_access
            ? ['inventory', 'rental', 'transport', 'salon']
            : $user->allowedServiceTypes();
        $existingTypes = $user->services->pluck('service_type')->all();
        $missing = array_diff($implied, $existingTypes);
        if (!empty($missing)) {
            foreach ($missing as $serviceType) {
                \App\Models\UserService::firstOrCreate([
                    'user_id'      => $user->id,
                    'service_type' => $serviceType,
                ]);
            }
            $user->load('services'); // reload with the newly added rows
        }

        // What the app lists is what the API will actually serve: the services the
        // user was given AND the account head above them still has. A staff member
        // whose business lost a service must not be shown it just to get a 403.
        $effective = $user->effectiveServiceTypes();
        $user->setRelation('services', $user->services->filter(
            fn ($s) => in_array($s->service_type, $effective, true)
        )->values());

        switch ($user->role) {
            case 'driver':
                $user->load('driver', 'assignedDevice');
                break;
            case 'landlord':
                $user->load('ownedProperties');
                break;
            case 'tenant':
                $user->load('tenantProfile', 'rentalAgreements.house.property');
                break;
        }

        // Append resolved permission set as a virtual attribute so the app
        // knows the full effective access without calling a separate endpoint.
        $user->setAttribute('effective_permissions', $user->effectiveInventoryPermissions());

        // The business this person works for (name, address, TIN, logo) and its plan, so the app
        // can show whose business it is and warn before the paid-until date. Null for a super admin.
        $user->setAttribute('business', Business::forUser($user)?->toApiArray());

        return $user;
    }

    /**
     * Return the authenticated user's service bindings.
     *
     * Lightweight alternative to /user when the app only needs to know which
     * services the user can access (e.g. on the service selection screen).
     * Uses User::allowedServiceTypes(): explicit user_services bindings if
     * any exist, else the role-implied default (super_admin -> all three,
     * sales_officer/manager/operator -> inventory, driver -> transport,
     * landlord/caretaker/tenant/vendor -> rental, admin -> none until a
     * super_admin explicitly binds them) -- mirrors the Flutter client's
     * own servicesForRole() fallback exactly, so this endpoint can't tell a
     * user "no access" when the client would have shown them a service.
     */
    #[OA\Get(
        path: '/auth/user/services',
        summary: 'List services this user may pick from',
        description: 'Returns explicit `user_services` bindings if any exist, else the role-implied '
            . 'default. Drives the "Select Service" screen -- an empty list with `is_unbound: true` '
            . 'means the user genuinely has no access anywhere yet.',
        security: [['bearerAuth' => []]],
        tags: ['Auth'],
        responses: [
            new OA\Response(
                response: 200,
                description: 'Services available to this user',
                content: new OA\JsonContent(properties: [
                    new OA\Property(property: 'services', type: 'array', items: new OA\Items(type: 'string', enum: ['inventory', 'rental', 'transport'])),
                    new OA\Property(property: 'is_unbound', type: 'boolean'),
                    new OA\Property(property: 'role', type: 'string'),
                ], type: 'object'),
            ),
        ],
    )]
    public function myServices(Request $request): \Illuminate\Http\JsonResponse
    {
        $user = $request->user();

        if (!$user) {
            return response()->json(['message' => 'Unauthenticated.'], 401);
        }

        $allowed = $user->full_access
            ? ['inventory', 'rental', 'transport', 'salon']
            : $user->effectiveServiceTypes();

        return response()->json([
            'services'    => $allowed,
            'is_unbound'  => empty($allowed),
            'role'        => $user->role,
            // Hint to the client: if is_unbound is true, display the
            // "no service access" screen and offer a logout button.
            'message'     => empty($allowed)
                ? 'No services assigned. Contact your administrator.'
                : null,
        ]);
    }

    /**
     * Get dashboard route based on user role
     */
    private function getDashboardRoute(string $role): string
    {
        switch ($role) {
            case 'super_admin':
                return '/super-admin/dashboard';
            case 'admin':
                return '/admin/dashboard';
            case 'landlord':
                return '/landlord/dashboard';
            case 'tenant':
                return '/tenant/dashboard';
            case 'driver':
                return '/driver/dashboard';
            default:
                return '/dashboard';
        }
    }

    /**
     * Get all drivers (Admin only)
     */
    public function getDrivers(Request $request)
    {
        try {
            $admin = $request->user();

            if (!$admin->canManageDrivers()) {
                return ResponseHelper::error('Insufficient permissions', 403);
            }

            $drivers = User::drivers()
                          ->with('driver', 'assignedDevice')
                          ->paginate(15);

            return ResponseHelper::success($drivers, 'Drivers retrieved successfully');

        } catch (\Exception $e) {
            return ResponseHelper::error('Failed to retrieve drivers: ' . $e->getMessage(), 500);
        }
    }

    /**
     * Assign device to driver (Admin only)
     */
    public function assignDevice(Request $request)
    {
        try {
            $request->validate([
                'driver_id' => 'required|uuid|exists:users,id',
                'device_id' => 'required|uuid|exists:devices,id',
            ]);

            $admin = $request->user();

            if (!$admin->canManageDrivers()) {
                return ResponseHelper::error('Insufficient permissions', 403);
            }

            $driver = User::drivers()->findOrFail($request->driver_id);
            $device = Device::findOrFail($request->device_id);

            // Update user's assigned device
            $driver->update(['device_id' => $request->device_id]);

            // Update device's driver
            $device->update(['driver_id' => $driver->driver->id]);

            return ResponseHelper::success([
                'driver' => $driver->load('assignedDevice'),
                'device' => $device,
            ], 'Device assigned successfully');

        } catch (\Exception $e) {
            return ResponseHelper::error('Device assignment failed: ' . $e->getMessage(), 500);
        }
    }
}