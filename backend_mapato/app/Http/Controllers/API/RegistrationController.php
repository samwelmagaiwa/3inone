<?php

namespace App\Http\Controllers\API;

use App\Helpers\ResponseHelper;
use App\Http\Controllers\Controller;
use App\Models\Business;
use App\Models\BusinessRegistration;
use App\Models\User;
use App\Services\Inventory\AuditTrail;
use App\Services\ServiceAssignment;
use App\Services\Sms\SmsCodes;
use App\Services\SmsService;
use App\Support\Pagination;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;
use OpenApi\Attributes as OA;

/**
 * Business registration: an owner registers themselves, a super admin reviews
 * the details and assigns the services, and only then can the owner sign in.
 *
 * Registering creates an INACTIVE admin login plus a pending registration, so a
 * business that has not been approved can sign in to nothing.
 */
class RegistrationController extends Controller
{
    private const SERVICES = ['inventory', 'rental', 'transport'];

    // Texts are written in both languages: nobody knows which one the person reads best, and the
    // app they used may not be in the language they speak at home.
    private const PHONE_CODE_TEXT = 'Nambari ya kuthibitisha simu / Phone verification code: :code. Dakika 10 / 10 min. Usimpe mtu / Do not share.';

    /**
     * Texts to super admins about new applications, per hour. Anyone can submit the form, so a
     * flood of fake applications must not run up the SMS bill or bury the real one; past the cap the
     * applications are still listed in the app, they just stop being texted.
     */
    private const ADMIN_TEXTS_PER_HOUR = 20;

    public function __construct(
        private readonly AuditTrail $audit,
        private readonly ServiceAssignment $assignment,
    ) {
    }

    // ------------------------------------------------------------- public

    #[OA\Post(
        path: '/auth/register',
        summary: 'Register a business',
        description: 'Public. Creates a pending registration and an inactive owner account. A super '
            . 'admin reviews it and assigns the services; the owner can sign in once approved.',
        tags: ['Auth'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'business_name', 'email', 'phone_number', 'password', 'password_confirmation', 'requested_services'],
                properties: [
                    new OA\Property(property: 'name', type: 'string'),
                    new OA\Property(property: 'business_name', type: 'string'),
                    new OA\Property(property: 'email', type: 'string', format: 'email'),
                    new OA\Property(property: 'phone_number', type: 'string', example: '0743519100'),
                    new OA\Property(property: 'password', type: 'string'),
                    new OA\Property(property: 'password_confirmation', type: 'string'),
                    new OA\Property(property: 'requested_services', type: 'array', items: new OA\Items(type: 'string', enum: ['inventory', 'rental', 'transport'])),
                    new OA\Property(property: 'region', type: 'string', nullable: true),
                    new OA\Property(property: 'district', type: 'string', nullable: true),
                    new OA\Property(property: 'address', type: 'string', nullable: true),
                    new OA\Property(property: 'id_number', type: 'string', nullable: true),
                    new OA\Property(property: 'notes', type: 'string', nullable: true),
                ],
            ),
        ),
        responses: [
            new OA\Response(response: 201, description: 'Registration received, pending approval'),
            new OA\Response(response: 422, description: 'Validation failed'),
        ],
    )]
    public function register(Request $request, SmsCodes $codes): JsonResponse
    {
        $data = $request->validate([
            'name' => 'required|string|max:255',
            'business_name' => 'required|string|max:255',
            'email' => 'required|email|max:255',
            'phone_number' => [
                'required', 'regex:/^(0\d{9}|\+\d{9,15})$/',
            ],
            'password' => ['required', 'confirmed', Password::min(8)],
            'requested_services' => 'required|array|min:1',
            'requested_services.*' => 'string|in:' . implode(',', self::SERVICES),
            // What kind of inventory business: needed only when they ask for the inventory service.
            'inventory_type' => [
                'nullable', 'string', Rule::in(Business::inventoryTypes()),
                Rule::requiredIf(fn () => in_array('inventory', (array) $request->input('requested_services', []), true)),
            ],
            'region' => 'nullable|string|max:100',
            'district' => 'nullable|string|max:100',
            'address' => 'nullable|string|max:500',
            'id_number' => 'nullable|string|max:50',
            'notes' => 'nullable|string|max:1000',
            'current_password' => 'nullable|string',
        ], [
            'phone_number.regex' => 'Namba ya simu si sahihi. Tumia namba ya ndani (mfano: 0743519100) au ya kimataifa (mfano: +255743519100).',
            'inventory_type.required' => 'Chagua aina ya biashara yako ya bidhaa (rejareja, jumla, ...). / Choose what kind of stock business you run (retail, wholesale, ...).',
            'inventory_type.in' => 'Aina ya biashara si sahihi. / That kind of business is not available.',
        ]);

        // Only meaningful when inventory is asked for.
        $inventoryType = in_array('inventory', $data['requested_services'], true) ? ($data['inventory_type'] ?? null) : null;

        $email = strtolower(trim($data['email']));

        // The email is the owner's sign-in name, so it alone identifies an existing registration.
        // The phone number is NOT an identity: businesses are separate, and two of them may give the
        // same number (an owner with two businesses, a shared office phone). Matching on it would also
        // let one applicant overwrite someone else's pending registration.
        $existingUser = User::whereRaw('LOWER(email) = ?', [$email])->first();
        $isReapplication = false;
        $existingRegistration = null;

        if ($existingUser) {
            $reg = $existingUser->registration;
            $isApproved = ($reg && $reg->status === BusinessRegistration::APPROVED)
                || $existingUser->is_active
                || $existingUser->services()->exists();

            if ($isApproved) {
                return ResponseHelper::validationError(['email' => ['This email is already registered.']]);
            }

            // Beyond this point the caller is claiming an existing, not-yet-approved registration.
            // Only the person who made it knows its password; anyone else gets the same plain
            // "already registered" a finished account would give, so these answers cannot be
            // used to find out whose registrations are pending or rejected, or to overwrite them.
            $claimedPassword = (string) ($data['current_password'] ?? $data['password']);
            if ($reg && !Hash::check($claimedPassword, (string) $existingUser->password)) {
                return ResponseHelper::validationError(['email' => ['This email is already registered.']]);
            }

            if ($reg && $reg->status === BusinessRegistration::PENDING) {
                return ResponseHelper::error(
                    'Usajili wako tayari umepokelewa na unasubiri idhini ya super admin. / Your registration is already received and is pending super admin approval.',
                    409,
                    ['code' => 'registration_pending']
                );
            }

            if ($reg && $reg->status === BusinessRegistration::REJECTED) {
                // The password was already checked above, whether one factor (email or phone)
                // matched or both: knowing someone's email and phone is not enough to take over
                // their registration.
                $isReapplication = true;
                $existingRegistration = $reg;
            } else {
                return ResponseHelper::validationError(['email' => ['This email is already registered.']]);
            }
        }

        $registration = DB::transaction(function () use ($data, $existingUser, $isReapplication, $existingRegistration, $inventoryType) {
            if ($isReapplication && $existingUser && $existingRegistration) {
                $existingUser->name = trim($data['name']);
                $existingUser->email = trim($data['email']);
                $last9 = fn (string $n): string => substr(preg_replace('/\D/', '', $n) ?? '', -9);
                if ($last9((string) $existingUser->phone_number) !== $last9((string) $data['phone_number'])) {
                    $existingUser->phone_verified = false; // a different number has not been confirmed
                }
                $existingUser->phone_number = $data['phone_number'];
                $existingUser->password = Hash::make($data['password']);
                $existingUser->role = 'admin';
                $existingUser->is_active = false;
                $existingUser->must_change_password = false;
                $existingUser->save();

                $existingRegistration->update([
                    'business_name' => trim($data['business_name']),
                    'requested_services' => array_values(array_unique($data['requested_services'])),
                    'inventory_type' => $inventoryType,
                    'region' => $data['region'] ?? null,
                    'district' => $data['district'] ?? null,
                    'address' => $data['address'] ?? null,
                    'id_number' => $data['id_number'] ?? null,
                    'notes' => $data['notes'] ?? null,
                    'status' => BusinessRegistration::PENDING,
                    'reviewed_by' => null,
                    'reviewed_at' => null,
                    'rejection_reason' => null,
                ]);

                return $existingRegistration;
            }

            $user = new User();
            $user->name = trim($data['name']);
            $user->email = trim($data['email']);
            $user->phone_number = $data['phone_number'];
            $user->password = Hash::make($data['password']);
            $user->role = 'admin';
            $user->is_active = false;
            $user->must_change_password = false;
            $user->save();

            return BusinessRegistration::create([
                'user_id' => $user->id,
                'business_name' => trim($data['business_name']),
                'requested_services' => array_values(array_unique($data['requested_services'])),
                'inventory_type' => $inventoryType,
                'region' => $data['region'] ?? null,
                'district' => $data['district'] ?? null,
                'address' => $data['address'] ?? null,
                'id_number' => $data['id_number'] ?? null,
                'notes' => $data['notes'] ?? null,
                'status' => BusinessRegistration::PENDING,
            ]);
        });

        // What they typed about the business becomes the business record (name, address, contact),
        // so the super admin reviews the same thing receipts will later carry.
        Business::syncFromRegistration($registration);

        $subject = $isReapplication
            ? 'Ombi la Usajili wa Biashara Limewasilishwa Tena / Business Registration Re-submitted'
            : 'Ombi la Usajili wa Biashara Limepokelewa / Business Registration Received';

        $msg = ($isReapplication
            ? 'Tumepokea tena ombi lako la usajili wa biashara "' . $registration->business_name . '". Utaarifiwa likikubaliwa.'
            : 'Tumepokea ombi lako la usajili wa biashara "' . $registration->business_name . '". Utaarifiwa likikubaliwa.')
            . ' / We received your business registration "' . $registration->business_name . '". You will be told when it is approved.';

        $this->notifyUser($data['phone_number'], $data['email'], $subject, $msg);

        // The people who decide are told there is something to decide.
        $this->notifySuperAdmins($registration, $isReapplication);

        // Prove the phone is theirs: a one-time code is texted, and the super admin sees
        // whether it was confirmed before deciding.
        $applicant = $registration->user;
        $phoneVerified = (bool) $applicant->phone_verified;
        $codeStatus = $phoneVerified
            ? null
            : $codes->issue($applicant, SmsCodes::PHONE_VERIFICATION, self::PHONE_CODE_TEXT);

        $returnMsg = $isReapplication
            ? 'Ombi lako limesasishwa na kuwasilishwa tena kwa super admin. / Re-application received. A super admin will review it.'
            : 'Registration received. A super admin will review it and assign your services.';

        return ResponseHelper::success([
            'registration_id' => $registration->id,
            'status' => $registration->status,
            'is_reapplication' => $isReapplication,
            'phone_verified' => $phoneVerified,
            'phone_verification_required' => !$phoneVerified,
            'code_sent' => $codeStatus === SmsCodes::SENT,
            // sent | throttled (one went out a moment ago) | unavailable (text messages are off, so
            // no code exists and the app must not ask for one) | null (the phone was already confirmed)
            'code_status' => $codeStatus,
        ], $returnMsg, 201);
    }

    #[OA\Post(
        path: '/auth/register/verify-phone',
        summary: 'Confirm the phone number of a registration with the code that was texted',
        description: 'Public. The super admin sees whether the applicant confirmed their phone before approving.',
        tags: ['Auth'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['email', 'code'],
                properties: [
                    new OA\Property(property: 'email', type: 'string', format: 'email'),
                    new OA\Property(property: 'code', type: 'string', example: '123456'),
                ],
            ),
        ),
        responses: [
            new OA\Response(response: 200, description: 'Phone confirmed'),
            new OA\Response(response: 422, description: 'Wrong or expired code'),
        ],
    )]
    public function verifyPhone(Request $request, SmsCodes $codes): JsonResponse
    {
        $data = $request->validate([
            'email' => 'required|email',
            'code' => ['required', 'digits:6'],
        ]);

        $user = User::whereRaw('LOWER(email) = ?', [strtolower(trim($data['email']))])->first();

        if (!$user || !$user->registration || !$codes->verify($user, SmsCodes::PHONE_VERIFICATION, $data['code'])) {
            return ResponseHelper::error(
                'Nambari si sahihi au imeisha muda. Omba nambari mpya. / The code is wrong or has expired. Request a new one.',
                422
            );
        }

        $user->phone_verified = true;
        $user->save();

        return ResponseHelper::success(['phone_verified' => true], 'Phone number confirmed.');
    }

    #[OA\Post(
        path: '/auth/register/resend-code',
        summary: 'Text a new phone-confirmation code for a registration',
        description: 'Public. Always answers the same way, so it cannot be used to find out who has registered.',
        tags: ['Auth'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['email'],
                properties: [new OA\Property(property: 'email', type: 'string', format: 'email')],
            ),
        ),
        responses: [
            new OA\Response(response: 200, description: 'A code was sent if the registration exists'),
            new OA\Response(response: 503, description: 'Text messages are not available'),
        ],
    )]
    public function resendCode(Request $request, SmsCodes $codes): JsonResponse
    {
        $data = $request->validate(['email' => 'required|email']);

        if (!$codes->available()) {
            return ResponseHelper::error(
                'Huduma ya ujumbe mfupi haipatikani sasa. Jaribu tena baadaye. / Text messages are not available right now. Try again later.',
                503,
                ['code' => 'sms_unavailable']
            );
        }

        $user = User::whereRaw('LOWER(email) = ?', [strtolower(trim($data['email']))])->first();
        if ($user && $user->registration && !$user->is_active && !$user->phone_verified) {
            $codes->issue($user, SmsCodes::PHONE_VERIFICATION, self::PHONE_CODE_TEXT);
        }

        return ResponseHelper::success(['code_sent' => true], 'Kama usajili upo, nambari mpya imetumwa. / If the registration exists, a new code has been sent.');
    }

    // -------------------------------------------------------- super admin

    #[OA\Get(
        path: '/admin/registrations',
        summary: 'List business registrations',
        description: 'Super admin only. Filter with ?status=pending|approved|rejected|all (default pending).',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Registrations'],
        parameters: [
            new OA\Parameter(name: 'status', in: 'query', schema: new OA\Schema(type: 'string', default: 'pending')),
            new OA\Parameter(name: 'q', in: 'query', schema: new OA\Schema(type: 'string')),
        ],
        responses: [new OA\Response(response: 200, description: 'Registrations with per-status counts')],
    )]
    public function index(Request $request): JsonResponse
    {
        $status = (string) $request->query('status', BusinessRegistration::PENDING);

        $query = BusinessRegistration::query()->with(['user.services', 'reviewer:id,name']);

        if ($status !== 'all') {
            $query->where('status', $status);
        }

        if ($search = trim((string) $request->query('q', ''))) {
            $query->where(function ($q) use ($search) {
                $q->where('business_name', 'like', "%{$search}%")
                    ->orWhereHas('user', function ($u) use ($search) {
                        $u->where('name', 'like', "%{$search}%")
                            ->orWhere('email', 'like', "%{$search}%")
                            ->orWhere('phone_number', 'like', "%{$search}%");
                    });
            });
        }

        $page = $query->latest()->paginate(Pagination::perPage($request, 20));

        $counts = BusinessRegistration::query()
            ->select('status', DB::raw('count(*) as total'))
            ->groupBy('status')
            ->pluck('total', 'status');

        return ResponseHelper::withMeta(
            $page->getCollection()->map(fn (BusinessRegistration $r) => $this->payload($r))->values(),
            [
                'counts' => [
                    'pending' => (int) ($counts[BusinessRegistration::PENDING] ?? 0),
                    'approved' => (int) ($counts[BusinessRegistration::APPROVED] ?? 0),
                    'rejected' => (int) ($counts[BusinessRegistration::REJECTED] ?? 0),
                ],
                'pagination' => [
                    'current_page' => $page->currentPage(),
                    'last_page' => $page->lastPage(),
                    'per_page' => $page->perPage(),
                    'total' => $page->total(),
                    'has_more_pages' => $page->hasMorePages(),
                ],
            ],
            'Registrations retrieved successfully'
        );
    }

    #[OA\Get(
        path: '/admin/registrations/{id}',
        summary: 'Registration details',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Registrations'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        responses: [new OA\Response(response: 200, description: 'Success')],
    )]
    public function show(string $id): JsonResponse
    {
        $registration = BusinessRegistration::with(['user.services', 'reviewer:id,name'])->findOrFail($id);

        return ResponseHelper::success($this->payload($registration));
    }

    #[OA\Post(
        path: '/admin/registrations/{id}/approve',
        summary: 'Approve a registration and assign services',
        description: 'Switches the owner\'s login on and gives them exactly the listed services. '
            . 'They can then create their own staff for those services.',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Registrations'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['service_types'],
                properties: [new OA\Property(property: 'service_types', type: 'array', items: new OA\Items(type: 'string', enum: ['inventory', 'rental', 'transport']))],
            ),
        ),
        responses: [
            new OA\Response(response: 200, description: 'Approved'),
            new OA\Response(response: 409, description: 'Already approved'),
        ],
    )]
    public function approve(Request $request, string $id): JsonResponse
    {
        $data = $request->validate([
            'service_types' => 'required|array|min:1',
            'service_types.*' => 'string|in:' . implode(',', self::SERVICES),
            // Billing: what the business starts on. Omitted, it starts a trial of
            // BILLING_TRIAL_DAYS; a super admin can set any plan and date (or none: no expiry).
            'plan' => ['nullable', 'string', Rule::in(config('billing.plans', []))],
            'valid_until' => 'nullable|date',
            // The super admin may correct the kind of inventory business the owner chose.
            'inventory_type' => ['nullable', 'string', Rule::in(Business::inventoryTypes())],
        ]);

        $registration = BusinessRegistration::with('user')->findOrFail($id);

        if ($registration->status === BusinessRegistration::APPROVED) {
            return ResponseHelper::error(
                'This registration is already approved. Change the services from the user\'s account instead.',
                409,
                ['code' => 'already_approved']
            );
        }

        $user = $registration->user;

        // Anyone can type any email into the form, so a registration whose phone number was
        // never confirmed with the texted code could belong to someone else entirely. The
        // super admin may still approve it on purpose (e.g. they phoned the applicant).
        if (!$user->phone_verified && !$request->boolean('allow_unverified')) {
            return ResponseHelper::error(
                'Mwombaji hajathibitisha namba yake ya simu. Idhinisha tu kama umemthibitisha mwenyewe. / '
                . 'The applicant has not confirmed their phone number. Approve only if you have checked them yourself.',
                422,
                ['code' => 'phone_not_verified']
            );
        }

        DB::transaction(function () use ($registration, $user, $data, $request) {
            // The business record comes first: the inventory it is given just below starts from its
            // kind (retail, wholesale, ...), so the kind has to be on it already.
            if (!empty($data['inventory_type'])) {
                $registration->update(['inventory_type' => $data['inventory_type']]);
            }
            $business = Business::syncFromRegistration($registration) ?? Business::ensureFor($user);

            // Also gives the business its own inventory settings and default crate
            // types when inventory is among the services.
            $services = $this->assignment->assign($user, $data['service_types']);

            $user->role = 'admin';
            $user->is_active = true;
            $user->save();

            // The business record starts its plan now: a trial unless the super admin chose otherwise.
            if ($business !== null) {
                $plan = $data['plan'] ?? config('billing.registration_plan', 'trial');
                $business->forceFill([
                    'plan' => $plan,
                    'valid_until' => !empty($data['valid_until'])
                        ? Carbon::parse($data['valid_until'])->endOfDay()
                        : ($plan === 'trial' ? now()->addDays(max((int) config('billing.trial_days', 30), 0))->endOfDay() : null),
                ])->save();
            }

            $registration->update([
                'status' => BusinessRegistration::APPROVED,
                'reviewed_by' => $request->user()->id,
                'reviewed_at' => now(),
                'rejection_reason' => null,
            ]);

            $this->audit->record(
                $request, 'registration', null, 'approved', null,
                ['business_name' => $registration->business_name, 'service_types' => $services, 'phone_verified' => (bool) $user->phone_verified],
                "{$request->user()->name} approved \"{$registration->business_name}\" ({$user->email}) with: " . implode(', ', $services),
            );
        });

        $this->notifyUser(
            $user->phone_number,
            $user->email,
            'Usajili wa Biashara Umekubaliwa / Business Registration Approved',
            'Hongera! Usajili wa "' . $registration->business_name . '" umekubaliwa. Ingia kwenye app kwa barua pepe ' . $user->email
            . ' na nenosiri ulilojisajilia. / Congratulations! "' . $registration->business_name . '" is approved. Sign in to the app with '
            . $user->email . ' and the password you registered with.'
        );

        return ResponseHelper::success($this->payload($registration->fresh(['user.services', 'reviewer:id,name'])), 'Registration approved');
    }

    #[OA\Post(
        path: '/admin/registrations/{id}/reject',
        summary: 'Reject a registration',
        security: [['bearerAuth' => []]],
        tags: ['Admin / Registrations'],
        parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'string'))],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(required: ['reason'], properties: [new OA\Property(property: 'reason', type: 'string')]),
        ),
        responses: [new OA\Response(response: 200, description: 'Rejected')],
    )]
    public function reject(Request $request, string $id): JsonResponse
    {
        $data = $request->validate(['reason' => 'required|string|max:500']);

        $registration = BusinessRegistration::with('user')->findOrFail($id);

        if ($registration->status === BusinessRegistration::APPROVED) {
            return ResponseHelper::error(
                'This registration is already approved. Deactivate the account instead.',
                409,
                ['code' => 'already_approved']
            );
        }

        $registration->update([
            'status' => BusinessRegistration::REJECTED,
            'reviewed_by' => $request->user()->id,
            'reviewed_at' => now(),
            'rejection_reason' => $data['reason'],
        ]);

        $this->audit->record(
            $request, 'registration', null, 'rejected', null,
            ['business_name' => $registration->business_name, 'reason' => $data['reason']],
            "{$request->user()->name} rejected \"{$registration->business_name}\" ({$registration->user->email})",
        );

        $this->notifyUser(
            $registration->user->phone_number,
            $registration->user->email,
            'Taarifa Kuhusu Usajili wa Biashara / Business Registration Status',
            'Samahani, usajili wa "' . $registration->business_name . '" haujakubaliwa. Sababu: ' . $data['reason']
            . ' / Sorry, the registration of "' . $registration->business_name . '" was not approved. Reason: ' . $data['reason']
        );

        return ResponseHelper::success($this->payload($registration->fresh(['user.services', 'reviewer:id,name'])), 'Registration rejected');
    }

    /**
     * Text every active super admin (and any number in SUPER_ADMIN_NOTIFY_PHONES) that an
     * application is waiting. Never breaks the registration: a failing provider, a missing phone
     * number or a hit cap only means this one text is not sent.
     */
    private function notifySuperAdmins(BusinessRegistration $registration, bool $isReapplication): void
    {
        try {
            $phones = $this->superAdminPhones();
            if ($phones === []) {
                Log::info('A registration is waiting but no super admin has a phone number to text.', ['registration' => $registration->id]);

                return;
            }

            if ($this->adminTextCapReached()) {
                Log::warning('Super admins were not texted about a registration: the hourly cap was reached.', ['registration' => $registration->id]);

                return;
            }

            $user = $registration->user;
            $who = Str::limit(trim($registration->business_name), 40, '...') . ' - ' . Str::limit(trim((string) $user?->name), 30, '...')
                . ', ' . $user?->phone_number;
            $services = implode(', ', (array) $registration->requested_services);
            $message = ($isReapplication ? 'Ombi la usajili limewasilishwa tena: ' : 'Ombi jipya la usajili: ') . $who
                . ($services !== '' ? " ({$services})" : '') . '. Fungua app (Usajili) kulikagua.'
                . ' / ' . ($isReapplication ? 'Registration re-submitted: ' : 'New registration: ') . $who . '. Open the app (Registrations) to review it.';

            foreach ($phones as $phone) {
                SmsService::send($phone, $message);
            }
        } catch (\Throwable $e) {
            Log::warning('Could not text the super admins about a registration: ' . $e->getMessage());
        }
    }

    /** Counts this text against the hour's cap. A cache that cannot count never stops a text. */
    private function adminTextCapReached(): bool
    {
        try {
            $key = 'registration_admin_texts:' . now()->format('YmdH');
            Cache::add($key, 0, 3600);

            return Cache::increment($key) > (int) config('sms.admin_texts_per_hour', self::ADMIN_TEXTS_PER_HOUR);
        } catch (\Throwable $e) {
            Log::warning('The registration text counter is not working: ' . $e->getMessage());

            return false;
        }
    }

    /**
     * Phone numbers to text about applications: every active super admin who has one, plus the
     * comma-separated SUPER_ADMIN_NOTIFY_PHONES (an office phone, an owner who is not a login).
     * One number is texted once however many ways it is written.
     *
     * @return array<int, string>
     */
    private function superAdminPhones(): array
    {
        return \App\Support\SuperAdminPhones::all();
    }

    /** Multi-channel notification dispatcher (SMS + Email). */
    private function notifyUser(?string $phone, ?string $email, string $subject, string $message): void
    {
        if ($phone) {
            try {
                SmsService::send($phone, $message);
            } catch (\Throwable $e) {
                Log::warning("Failed to send SMS to {$phone}: " . $e->getMessage());
            }
        }

        if ($email && filter_var($email, FILTER_VALIDATE_EMAIL)) {
            try {
                Mail::raw($message, function ($mail) use ($email, $subject) {
                    $mail->to($email)->subject($subject);
                });
            } catch (\Throwable $e) {
                Log::warning("Failed to send Email to {$email}: " . $e->getMessage());
            }
        }
    }

    /** Everything a super admin needs to decide, in one flat shape. */
    private function payload(BusinessRegistration $r): array
    {
        $user = $r->user;

        return [
            'id' => $r->id,
            'status' => $r->status,
            'business_name' => $r->business_name,
            'requested_services' => $r->requested_services ?? [],
            'inventory_type' => $r->inventory_type,
            'region' => $r->region,
            'district' => $r->district,
            'address' => $r->address,
            'id_number' => $r->id_number,
            'notes' => $r->notes,
            'submitted_at' => $r->created_at?->toISOString(),
            'reviewed_at' => $r->reviewed_at?->toISOString(),
            'reviewed_by' => $r->reviewer?->name,
            'rejection_reason' => $r->rejection_reason,
            'assigned_services' => $r->status === BusinessRegistration::APPROVED && $user
                ? $user->services->pluck('service_type')->values()->all()
                : [],
            'user' => $user ? [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'phone_number' => $user->phone_number,
                'role' => $user->role,
                'is_active' => (bool) $user->is_active,
                // Did the applicant confirm the phone number with the texted code?
                'phone_verified' => (bool) $user->phone_verified,
            ] : null,
            // The business record (name, address, TIN, plan, valid_until) the review is about.
            'business' => $user ? Business::forOwnerId($user->id)?->toApiArray() : null,
        ];
    }
}
