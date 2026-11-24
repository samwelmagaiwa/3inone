<?php

namespace App\Http\Controllers\API\Groups;

use App\Models\Business;
use App\Models\User;
use App\Rules\UniquePhoneInBusiness;
use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupAudit;
use App\Support\Groups\GroupLedger;
use App\Support\Groups\GroupMembers;
use App\Support\Groups\GroupOffices;
use App\Services\SmsService;
use App\Support\TemporaryPassword;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;

/**
 * The member register: applications, approval and the life of a membership, offices, dependants and sign-in accounts. What each call
 * needs is enforced on its route (group_right:...); the rules that depend on WHO is acting (nobody changes their own office, a member
 * who left cannot hold an office) are checked here.
 */
class GroupMemberController extends Controller
{
    private const PHONE = ['regex:/^(0\d{9}|\+\d{9,15})$/'];

    private const PAGE = 50;

    private function fail(string $code, string $message, int $status = 422, array $extra = []): JsonResponse
    {
        return response()->json(['success' => false, 'code' => $code, 'message' => $message] + $extra, $status);
    }

    private function find(int $id): ?object
    {
        return DB::table('group_members')->where('id', $id)->first();
    }

    /** The register, a page at a time, with the number of members in each status (counted over the whole group). */
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'status' => ['nullable', Rule::in(GroupMembers::STATUSES)],
            'office' => ['nullable', 'string', 'max:40'],
            'q' => 'nullable|string|max:100',
            'page' => 'nullable|integer|min:1',
        ]);

        $query = DB::table('group_members as m')
            ->when($data['status'] ?? null, fn ($q, $s) => $q->where('m.status', $s))
            ->when(($data['office'] ?? null) === 'any', fn ($q) => $q->whereNotNull('m.office'))
            ->when(($data['office'] ?? null) !== null && ($data['office'] ?? null) !== 'any', fn ($q) => $q->where('m.office', $data['office']))
            ->when(trim((string) ($data['q'] ?? '')) !== '', function ($q) use ($data) {
                $term = '%' . trim((string) $data['q']) . '%';
                $q->where(fn ($w) => $w->where('m.full_name', 'like', $term)->orWhere('m.phone', 'like', $term)->orWhere('m.member_number', 'like', $term));
            });

        $total = (clone $query)->count();
        $page = (int) ($data['page'] ?? 1);
        $rows = $query->leftJoin('group_members as r', 'r.id', '=', 'm.referrer_id')
            ->orderByRaw("CASE m.status WHEN 'submitted' THEN 0 WHEN 'active' THEN 1 WHEN 'suspended' THEN 2 ELSE 3 END")
            ->orderBy('m.full_name')
            ->forPage($page, self::PAGE)
            ->get(['m.*', 'r.full_name as referrer_name']);

        $counts = DB::table('group_members')->selectRaw('status, COUNT(*) as n')->groupBy('status')->pluck('n', 'status');

        return response()->json([
            'success' => true,
            'data' => [
                'members' => $rows->map(fn ($r) => GroupMembers::payload($r))->values(),
                'counts' => collect(GroupMembers::STATUSES)->mapWithKeys(fn ($s) => [$s => (int) ($counts[$s] ?? 0)]),
            ],
            'meta' => ['pagination' => ['page' => $page, 'per_page' => self::PAGE, 'total' => $total, 'has_more' => $page * self::PAGE < $total]],
        ]);
    }

    /** One member's file: details, dependants, history of status and office, and (for whoever sees the money) what they have paid. */
    public function show(Request $request, int $id): JsonResponse
    {
        $row = DB::table('group_members as m')->leftJoin('group_members as r', 'r.id', '=', 'm.referrer_id')
            ->where('m.id', $id)->first(['m.*', 'r.full_name as referrer_name']);
        if ($row === null) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }
        $user = $request->user();

        $events = DB::table('group_member_events as e')->leftJoin('users as u', 'u.id', '=', 'e.by_user')
            ->where('e.member_id', $id)->orderByDesc('e.id')->limit(50)
            ->get(['e.kind', 'e.from_value', 'e.to_value', 'e.reason', 'e.created_at', 'u.name as by_name']);

        return response()->json(['success' => true, 'data' => [
            'member' => GroupMembers::payload($row, GroupAccess::can($user, 'view_sensitive')),
            'dependants' => DB::table('group_dependants')->where('member_id', $id)->orderBy('id')->get(['id', 'name', 'relationship', 'phone', 'date_of_birth', 'notes']),
            'events' => $events,
            'referrals' => DB::table('group_members')->where('referrer_id', $id)->orderBy('full_name')->get(['id', 'full_name', 'member_number', 'status']),
            'documents' => GroupRecordsController::documentsFor($request, $id),
            'photo_url' => \App\Support\PrivateFile::url($row->photo_path ?? null),
            'source' => $row->source ?? null,
            'balances' => GroupAccess::can($user, 'view_finance') ? GroupLedger::balances($id) : null,
            'approval_blockers' => $row->status === GroupMembers::SUBMITTED ? GroupMembers::approvalBlockers($id) : [],
        ]]);
    }

    /** @return array<string, mixed> the rules for a member's own details (shared by register and edit) */
    public function detailRules(bool $creating): array
    {
        $req = $creating ? 'required' : 'sometimes';

        return [
            'full_name' => [$req, 'string', 'min:3', 'max:150'],
            'phone' => [$req, 'string', ...self::PHONE],
            'alt_phone' => ['nullable', 'string', ...self::PHONE],
            'email' => 'nullable|email|max:150',
            'nida' => ['nullable', 'string', 'max:40', 'regex:/^[0-9A-Za-z\- ]{8,40}$/'],
            'date_of_birth' => 'nullable|date|before:today',
            'gender' => ['nullable', Rule::in(['male', 'female'])],
            'region' => 'nullable|string|max:80',
            'district' => 'nullable|string|max:80',
            'ward' => 'nullable|string|max:80',
            'street' => 'nullable|string|max:150',
            'occupation' => 'nullable|string|max:120',
            'notes' => 'nullable|string|max:2000',
            'referrer_id' => 'nullable|integer',
        ];
    }

    /** Problems with the phone, NIDA and referrer that the plain rules cannot see; null when all is well. */
    public function checkDetails(array $data, ?int $self): ?JsonResponse
    {
        $alive = fn ($q) => $q->whereNotIn('status', [GroupMembers::REJECTED, GroupMembers::EXITED, GroupMembers::DECEASED])
            ->when($self !== null, fn ($w) => $w->where('id', '!=', $self));

        if (isset($data['phone'])) {
            $nine = UniquePhoneInBusiness::lastNine($data['phone']);
            $same = DB::table('group_members')->where($alive)->get(['id', 'full_name', 'phone'])
                ->first(fn ($m) => UniquePhoneInBusiness::lastNine($m->phone) === $nine);
            if ($same !== null) {
                return $this->fail('duplicate_phone', "Namba hii tayari ni ya {$same->full_name}. / This phone already belongs to {$same->full_name}.", 422, ['errors' => ['phone' => ['duplicate']]]);
            }
        }
        if (!empty($data['nida'])) {
            $same = DB::table('group_members')->where($alive)->where('nida_hash', GroupMembers::nidaHash($data['nida']))->first(['id', 'full_name']);
            if ($same !== null) {
                return $this->fail('duplicate_nida', "NIDA hii tayari ni ya {$same->full_name}. / This NIDA number already belongs to {$same->full_name}.", 422, ['errors' => ['nida' => ['duplicate']]]);
            }
        }
        if (!empty($data['referrer_id'])) {
            if ($self !== null && (int) $data['referrer_id'] === $self) {
                return $this->fail('own_referrer', 'Mwanachama hawezi kujileta mwenyewe. / A member cannot refer themselves.');
            }
            $ok = DB::table('group_members')->where('id', (int) $data['referrer_id'])->where('status', GroupMembers::ACTIVE)->exists();
            if (!$ok) {
                return $this->fail('bad_referrer', 'Aliyemleta lazima awe mwanachama hai. / The referrer must be an active member.', 422, ['errors' => ['referrer_id' => ['inactive']]]);
            }
        }

        return null;
    }

    /** @return array<string, mixed> the columns written from validated details */
    public function columns(array $data): array
    {
        $out = [];
        foreach (['full_name', 'phone', 'alt_phone', 'email', 'date_of_birth', 'gender', 'region', 'district', 'ward', 'street', 'occupation', 'notes'] as $k) {
            if (array_key_exists($k, $data)) {
                $out[$k] = is_string($data[$k]) ? trim($data[$k]) : $data[$k];
            }
        }
        if (array_key_exists('nida', $data)) {
            $out['nida'] = GroupMembers::encryptNida($data['nida']);
            $out['nida_hash'] = GroupMembers::nidaHash($data['nida']);
        }
        if (array_key_exists('referrer_id', $data)) {
            $out['referrer_id'] = $data['referrer_id'] ?: null;
        }

        return $out;
    }

    /**
     * Register a person. An application starts SUBMITTED and waits for its payments and approval. Whoever may approve members can also
     * enter someone who was ALREADY a member before the group used the app ("existing"): they are active at once, with their old number
     * and joining date if given.
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate($this->detailRules(true) + [
            'existing' => 'nullable|boolean',
            'founding' => 'nullable|boolean',
            'member_number' => ['nullable', 'string', 'max:30', 'regex:/^[A-Za-z0-9\-\/]+$/'],
            'joined_on' => 'nullable|date|before_or_equal:today',
        ]);
        $user = $request->user();
        $existing = (bool) ($data['existing'] ?? false);
        if ($existing && !GroupAccess::can($user, 'approve_members')) {
            return $this->fail('approve_right_needed', 'Ni anayeidhinisha wanachama tu anayeweza kuweka mwanachama aliyekuwepo. / Only whoever approves members can enter an existing member.', 403);
        }
        if ($problem = $this->checkDetails($data, null)) {
            return $problem;
        }
        if ($existing && !empty($data['member_number']) && DB::table('group_members')->where('member_number', $data['member_number'])->exists()) {
            return $this->fail('number_taken', 'Namba hii ya uanachama tayari imetumika. / This member number is already taken.', 422, ['errors' => ['member_number' => ['taken']]]);
        }

        $id = DB::transaction(function () use ($data, $existing, $user) {
            $id = (int) DB::table('group_members')->insertGetId($this->columns($data) + [
                'application_ref' => GroupMembers::newApplicationRef(),
                'status' => $existing ? GroupMembers::ACTIVE : GroupMembers::SUBMITTED,
                'founding' => (bool) ($data['founding'] ?? false),
                'member_number' => $existing ? ($data['member_number'] ?? null) : null,
                'joined_on' => $existing ? ($data['joined_on'] ?? now()->toDateString()) : null,
                'approved_at' => $existing ? now() : null,
                'approved_by' => $existing ? (string) $user->id : null,
                'created_by' => (string) $user->id,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            if ($existing && empty($data['member_number'])) {
                GroupMembers::assignNumber($id);
            }
            GroupMembers::event($id, 'status', null, $existing ? GroupMembers::ACTIVE : GroupMembers::SUBMITTED, $existing ? 'existing member' : null, (string) $user->id);

            return $id;
        });

        GroupAudit::record((string) $user->id, $existing ? 'member_entered' : 'member_applied', ($existing ? 'Entered existing member ' : 'Recorded application of ') . $data['full_name'], 'member', $id);

        return $this->show($request, $id)->setStatusCode(201);
    }

    /** Change a member's own details. Their status, number and office have their own calls. */
    public function update(Request $request, int $id): JsonResponse
    {
        $row = $this->find($id);
        if ($row === null) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }
        $data = $request->validate($this->detailRules(false));
        // The referrer is a fact of the past: one who has since left stays as they were, it is only checked when it changes.
        if (array_key_exists('referrer_id', $data) && (int) ($data['referrer_id'] ?? 0) === (int) ($row->referrer_id ?? 0)) {
            unset($data['referrer_id']);
        }
        if ($problem = $this->checkDetails($data, $id)) {
            return $problem;
        }
        $columns = $this->columns($data);
        if ($columns !== []) {
            DB::table('group_members')->where('id', $id)->update($columns + ['updated_at' => now()]);
            GroupAudit::record((string) $request->user()->id, 'member_updated', 'Changed details of member #' . $id . ': ' . implode(', ', array_keys($data)), 'member', $id);
        }

        return $this->show($request, $id);
    }

    /** Approve, reject, suspend, reinstate, record an exit or a death. Every move but approve and reinstate needs a reason. */
    public function move(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'action' => ['required', Rule::in(array_keys(GroupMembers::MOVES))],
            'reason' => 'nullable|string|max:255',
        ]);
        $row = $this->find($id);
        if ($row === null) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }
        $user = $request->user();
        [$from, $to] = GroupMembers::MOVES[$data['action']];
        if (!in_array($row->status, $from, true)) {
            return $this->fail('wrong_status', 'Hatua hii haiwezekani kwa hali ya sasa ya mwanachama. / This step is not possible from the member\'s current status.', 409);
        }
        $reason = trim((string) ($data['reason'] ?? ''));
        if (!in_array($data['action'], ['approve', 'reinstate'], true) && $reason === '') {
            return $this->fail('reason_required', 'Andika sababu. / Write the reason.', 422, ['errors' => ['reason' => ['required']]]);
        }
        $me = GroupAccess::member($user);
        if ($me !== null && (int) $me['id'] === $id) {
            return $this->fail('own_membership', 'Huwezi kubadilisha hali ya uanachama wako mwenyewe. / You cannot change your own membership status.', 403);
        }
        if ($data['action'] === 'approve' && ($blockers = GroupMembers::approvalBlockers($id)) !== []) {
            return $this->fail('approval_blocked', 'Malipo ya kujiunga bado hayajathibitishwa. / The joining payments are not verified yet.', 422, ['blockers' => $blockers]);
        }

        DB::transaction(function () use ($row, $id, $to, $data, $reason, $user) {
            $set = ['status' => $to, 'status_reason' => $reason === '' ? null : $reason, 'updated_at' => now()];
            if ($data['action'] === 'approve') {
                $set += ['approved_at' => now(), 'approved_by' => (string) $user->id, 'joined_on' => now()->toDateString()];
            }
            // A member who is no longer active holds no office.
            if ($to !== GroupMembers::ACTIVE && $row->office !== null) {
                $set['office'] = null;
                GroupMembers::event($id, 'office', $row->office, null, 'membership ' . $to, (string) $user->id);
            }
            DB::table('group_members')->where('id', $id)->update($set);
            if ($data['action'] === 'approve' && $row->member_number === null) {
                GroupMembers::assignNumber($id);
            }
            GroupMembers::event($id, 'status', $row->status, $to, $reason === '' ? null : $reason, (string) $user->id);

            // Whoever left (or died) can no longer sign in; a suspended member still can, to see their own records.
            if ($row->user_id !== null && in_array($to, [GroupMembers::EXITED, GroupMembers::DECEASED, GroupMembers::REJECTED], true)) {
                $account = User::query()->withoutGlobalScopes()->find($row->user_id);
                $account?->forceFill(['is_active' => false])->save();
                $account?->tokens()->delete();
            }
            if ($row->user_id !== null && $data['action'] === 'reinstate') {
                User::query()->withoutGlobalScopes()->whereKey($row->user_id)->update(['is_active' => true]);
            }
        });

        GroupAudit::record((string) $user->id, 'member_' . $data['action'], ucfirst($data['action']) . ' ' . $row->full_name . ($reason !== '' ? ': ' . $reason : ''), 'member', $id);

        return $this->show($request, $id);
    }

    /** Give a member an office, or take it away (office null). Nobody changes their own office. */
    public function office(Request $request, int $id): JsonResponse
    {
        $data = $request->validate([
            'office' => ['nullable', Rule::in(GroupOffices::OFFICES)],
            'replace' => 'nullable|boolean',
            'reason' => 'nullable|string|max:255',
        ]);
        $row = $this->find($id);
        if ($row === null) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }
        $user = $request->user();
        $me = GroupAccess::member($user);
        if ($me !== null && (int) $me['id'] === $id) {
            return $this->fail('own_office', 'Huwezi kubadilisha cheo chako mwenyewe. / You cannot change your own office.', 403);
        }
        $office = $data['office'] ?? null;
        if ($office !== null && $row->status !== GroupMembers::ACTIVE) {
            return $this->fail('not_active', 'Ni mwanachama hai tu anayeweza kushika cheo. / Only an active member can hold an office.', 409);
        }
        if ($office === $row->office) {
            return $this->show($request, $id);
        }

        $holder = null;
        if ($office !== null && in_array($office, GroupOffices::SINGLE_HOLDER, true)) {
            $holder = DB::table('group_members')->where('office', $office)->where('id', '!=', $id)->first(['id', 'full_name']);
            if ($holder !== null && !($data['replace'] ?? false)) {
                return $this->fail('office_taken', "Cheo hiki kinashikwa na {$holder->full_name}. / This office is held by {$holder->full_name}.", 409, ['holder' => ['id' => (int) $holder->id, 'name' => $holder->full_name]]);
            }
        }

        DB::transaction(function () use ($holder, $office, $row, $id, $data, $user) {
            if ($holder !== null) {
                DB::table('group_members')->where('id', $holder->id)->update(['office' => null, 'updated_at' => now()]);
                GroupMembers::event((int) $holder->id, 'office', $office, null, 'replaced', (string) $user->id);
            }
            DB::table('group_members')->where('id', $id)->update(['office' => $office, 'updated_at' => now()]);
            GroupMembers::event($id, 'office', $row->office, $office, $data['reason'] ?? null, (string) $user->id);
        });

        GroupAudit::record((string) $user->id, 'office_changed', $row->full_name . ': ' . ($row->office ?? 'none') . ' -> ' . ($office ?? 'none'), 'member', $id);

        return $this->show($request, $id);
    }

    /** Add a dependant, or change one ([dependantId]). */
    public function saveDependant(Request $request, int $id, ?int $dependantId = null): JsonResponse
    {
        if ($this->find($id) === null) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }
        $data = $request->validate([
            'name' => 'required|string|min:2|max:150',
            'relationship' => ['required', Rule::in(GroupMembers::RELATIONSHIPS)],
            'phone' => ['nullable', 'string', ...self::PHONE],
            'date_of_birth' => 'nullable|date|before_or_equal:today',
            'notes' => 'nullable|string|max:255',
        ]);
        if ($dependantId !== null) {
            $done = DB::table('group_dependants')->where('id', $dependantId)->where('member_id', $id)->update($data + ['updated_at' => now()]);
            if ($done === 0 && !DB::table('group_dependants')->where('id', $dependantId)->where('member_id', $id)->exists()) {
                return $this->fail('not_found', 'Mtegemezi hayupo. / Dependant not found.', 404);
            }
        } else {
            DB::table('group_dependants')->insert($data + ['member_id' => $id, 'created_at' => now(), 'updated_at' => now()]);
        }
        GroupAudit::record((string) $request->user()->id, 'dependant_saved', 'Dependant ' . $data['name'] . ' (' . $data['relationship'] . ') of member #' . $id, 'member', $id);

        return $this->show($request, $id);
    }

    public function deleteDependant(Request $request, int $id, int $dependantId): JsonResponse
    {
        $dependant = DB::table('group_dependants')->where('id', $dependantId)->where('member_id', $id)->first();
        if ($dependant === null) {
            return $this->fail('not_found', 'Mtegemezi hayupo. / Dependant not found.', 404);
        }
        DB::table('group_dependants')->where('id', $dependantId)->delete();
        GroupAudit::record((string) $request->user()->id, 'dependant_removed', 'Removed dependant ' . $dependant->name . ' of member #' . $id, 'member', $id);

        return $this->show($request, $id);
    }

    /**
     * Give an active member a sign-in: they sign in with their phone number (or email) and a one-time password, which is shown here
     * once and must be changed at the first sign-in. With [reset] an existing sign-in gets a new one-time password instead.
     */
    public function signIn(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['reset' => 'nullable|boolean']);
        $row = $this->find($id);
        if ($row === null) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }
        if (!in_array($row->status, [GroupMembers::ACTIVE, GroupMembers::SUSPENDED], true)) {
            return $this->fail('not_active', 'Ni mwanachama aliyeidhinishwa tu anayepewa akaunti. / Only an approved member gets a sign-in.', 409);
        }
        $actor = $request->user();
        $password = TemporaryPassword::generate();

        if ($row->user_id !== null) {
            if (!($data['reset'] ?? false)) {
                return $this->fail('has_sign_in', 'Mwanachama huyu tayari ana akaunti. / This member already has a sign-in.', 409);
            }
            $account = User::query()->withoutGlobalScopes()->find($row->user_id);
            if ($account === null) {
                return $this->fail('not_found', 'Akaunti haipo. / Sign-in not found.', 404);
            }
            $account->forceFill(['password' => Hash::make($password), 'must_change_password' => true])->save();
            $account->tokens()->delete();
            GroupAudit::record((string) $actor->id, 'sign_in_reset', 'New one-time password for ' . $row->full_name, 'member', $id);

            return response()->json(['success' => true, 'data' => ['login' => $row->phone, 'temporary_password' => $password]]);
        }

        // The phone signs them in, so it must point at nobody else who signs in with a phone.
        $nine = UniquePhoneInBusiness::lastNine($row->phone);
        $clash = User::query()->withoutGlobalScopes()->whereNotNull('phone_number')->where('phone_number', 'like', '%' . $nine)->get(['id', 'phone_number'])
            ->first(fn ($u) => UniquePhoneInBusiness::lastNine($u->phone_number) === $nine);
        // The owner of the business is often a member too (the chairperson who set the group up): their member file is then simply
        // tied to the account they already have.
        if ($clash !== null && (string) $clash->id === (string) $actor->accountHeadId()
            && !DB::table('group_members')->where('user_id', (string) $clash->id)->exists()) {
            DB::table('group_members')->where('id', $id)->update(['user_id' => (string) $clash->id, 'updated_at' => now()]);
            GroupAudit::record((string) $actor->id, 'sign_in_linked', 'Tied ' . $row->full_name . ' to the business owner\'s own account', 'member', $id);

            return response()->json(['success' => true, 'data' => ['linked_owner' => true, 'login' => null, 'temporary_password' => null]]);
        }
        if ($clash !== null) {
            return $this->fail('phone_in_use', 'Namba hii ya simu tayari inatumika na akaunti nyingine. / This phone number is already used by another account.', 409);
        }
        $email = $row->email ?: ('m' . $row->id . '.' . substr(str_replace('-', '', (string) $actor->accountHeadId()), 0, 12) . '@members.3inone.local');
        if (User::query()->withoutGlobalScopes()->where('email', $email)->exists()) {
            return $this->fail('email_in_use', 'Barua pepe hii tayari ina akaunti. / This email already has an account.', 409);
        }

        $account = DB::transaction(function () use ($row, $email, $password, $actor, $id) {
            $account = new User([
                'name' => $row->full_name,
                'email' => $email,
                'phone_number' => $row->phone,
                'password' => Hash::make($password),
                'role' => User::GROUP_MEMBER_ROLE,
                'service_type' => 'groups',
                'created_by' => (string) $actor->accountHeadId(),
                'is_active' => $row->status === GroupMembers::ACTIVE || $row->status === GroupMembers::SUSPENDED,
            ]);
            $account->must_change_password = true;
            $account->save();
            DB::table('group_members')->where('id', $id)->update(['user_id' => (string) $account->id, 'updated_at' => now()]);

            return $account;
        });

        GroupAudit::record((string) $actor->id, 'sign_in_created', 'Gave ' . $row->full_name . ' a sign-in', 'member', $id);

        return response()->json(['success' => true, 'data' => ['login' => $row->phone, 'email' => $account->email, 'temporary_password' => $password]], 201);
    }

    /**
     * A member registers a new member. Any ACTIVE member may do it (whatever their office, or none), and so may whoever manages members.
     *
     *   - the new person is tied to the member who registered them (their referrer), so the tree of who brought whom is complete;
     *   - they start as an application, like any other: the officers still approve it once the joining payments are verified;
     *   - they get a sign-in at once, and a one-time password goes by SMS to the phone number that was entered for them. The registrar is
     *     NEVER shown it: only the person it was sent to knows it. Signing in with it forces a new password of 8 or more characters, and
     *     then a new sign-in (the app's first-login screen does that for every account with a temporary password).
     */
    public function registerFor(Request $request): JsonResponse
    {
        $user = $request->user();
        $registrar = GroupAccess::member($user);
        $isMember = $registrar !== null && $registrar['status'] === GroupMembers::ACTIVE;
        if (!$isMember && !GroupAccess::can($user, 'manage_members')) {
            return $this->fail('not_a_member', 'Ni mwanachama hai tu anayeweza kusajili mwanachama mwingine. / Only an active member can register another member.', 403);
        }

        $rules = $this->detailRules(true);
        unset($rules['referrer_id'], $rules['notes']);
        $data = $request->validate($rules);
        if ($problem = $this->checkDetails($data, null)) {
            return $problem;
        }

        // The phone signs them in, so it must point at nobody else who signs in with a phone.
        $nine = UniquePhoneInBusiness::lastNine($data['phone']);
        $clash = User::query()->withoutGlobalScopes()->whereNotNull('phone_number')->where('phone_number', 'like', '%' . $nine)->get(['id', 'phone_number'])
            ->first(fn ($u) => UniquePhoneInBusiness::lastNine($u->phone_number) === $nine);
        if ($clash !== null) {
            return $this->fail('phone_in_use', 'Namba hii ya simu tayari inatumika na akaunti nyingine. / This phone number is already used by another account.', 409);
        }
        $head = (string) $user->accountHeadId();
        $email = !empty($data['email']) ? trim($data['email']) : null;
        $signInEmail = $email ?: ('m' . substr(md5($nine . $head), 0, 10) . '.' . substr(str_replace('-', '', $head), 0, 12) . '@members.3inone.local');
        if (User::query()->withoutGlobalScopes()->where('email', $signInEmail)->exists()) {
            return $this->fail('email_in_use', 'Barua pepe hii tayari ina akaunti. / This email already has an account.', 409);
        }

        $password = TemporaryPassword::generate();
        $id = DB::transaction(function () use ($data, $user, $registrar, $isMember, $signInEmail, $password, $head) {
            $id = (int) DB::table('group_members')->insertGetId($this->columns($data) + [
                'application_ref' => GroupMembers::newApplicationRef(),
                'status' => GroupMembers::SUBMITTED,
                'founding' => false,
                'referrer_id' => $isMember ? (int) $registrar['id'] : null,
                'source' => 'member',
                'created_by' => (string) $user->id,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            GroupMembers::event($id, 'status', null, GroupMembers::SUBMITTED, $isMember ? 'registered by member #' . $registrar['id'] : null, (string) $user->id);

            $account = new User([
                'name' => $data['full_name'],
                'email' => $signInEmail,
                'phone_number' => $data['phone'],
                'password' => Hash::make($password),
                'role' => User::GROUP_MEMBER_ROLE,
                'service_type' => 'groups',
                'created_by' => $head,
                'is_active' => true,
            ]);
            $account->must_change_password = true;
            $account->save();
            DB::table('group_members')->where('id', $id)->update(['user_id' => (string) $account->id]);

            return $id;
        });

        GroupAudit::record((string) $user->id, 'member_registered_by_member', 'Registered ' . $data['full_name'] . ($isMember ? ' (brought in by member #' . $registrar['id'] . ')' : ''), 'member', $id);
        $sent = $this->sendOtp($user, (string) $data['full_name'], (string) $data['phone'], $password, $isMember ? (string) $registrar['full_name'] : (string) $user->name);

        $payload = $this->show($request, $id)->getData(true);
        $payload['data']['sms_sent'] = $sent;

        return response()->json($payload, 201);
    }

    /**
     * A new one-time password by SMS, for someone who has not yet chosen their own: the registrar (or whoever manages members) asks for it
     * again when the text never arrived. It is never shown to whoever asks. Not possible once the person has set their own password.
     */
    public function resendOtp(Request $request, int $id): JsonResponse
    {
        $row = $this->find($id);
        if ($row === null || $row->user_id === null) {
            return $this->fail('not_found', 'Mwanachama hayupo. / Member not found.', 404);
        }
        $user = $request->user();
        if ((string) ($row->created_by ?? '') !== (string) $user->id && !GroupAccess::can($user, 'manage_members')) {
            return $this->fail('not_allowed', 'Ni aliyemsajili au msimamizi wa wanachama tu. / Only whoever registered them, or whoever manages members.', 403);
        }
        $account = User::query()->withoutGlobalScopes()->find($row->user_id);
        if ($account === null || !$account->must_change_password) {
            return $this->fail('already_set', 'Mwanachama ameshaweka nenosiri lake mwenyewe. / The member has already chosen their own password.', 409);
        }
        $password = TemporaryPassword::generate();
        $account->forceFill(['password' => Hash::make($password), 'must_change_password' => true])->save();
        $account->tokens()->delete();
        GroupAudit::record((string) $user->id, 'otp_resent', 'New one-time password sent to ' . $row->full_name, 'member', $id);
        $by = GroupAccess::member($user);
        $sent = $this->sendOtp($user, (string) $row->full_name, (string) $row->phone, $password, $by !== null ? (string) $by['full_name'] : (string) $user->name);

        return response()->json(['success' => true, 'data' => ['sms_sent' => $sent]]);
    }

    /** The one-time password to the number entered for the new member, under the group's own sender name; whether the text was accepted. */
    private function sendOtp(User $actor, string $name, string $phone, string $password, string $by): bool
    {
        $business = Business::forOwnerId((string) $actor->accountHeadId());
        $group = $business?->name ?? 'Kikundi';
        $text = "{$group}: {$by} amekusajili, {$name}. Ingia kwa simu {$phone} na nenosiri la muda: {$password}. Kisha weka nenosiri lako jipya (herufi 8+). "
            . "/ {$by} registered you. Sign in with {$phone} and the temporary password {$password}, then choose your own (8+ characters).";

        return SmsService::sendFor($business, $phone, $text);
    }
}
