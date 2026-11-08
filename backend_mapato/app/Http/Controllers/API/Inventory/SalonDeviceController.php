<?php

namespace App\Http\Controllers\API\Inventory;

use App\Models\User;
use App\Services\Inventory\InventoryNotifier;
use App\Support\Salon\DeviceAttendance;
use App\Support\Salon\DeviceDenied;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use OpenApi\Attributes as OA;

/**
 * Attendance from one's own approved device: the person's device, the challenge to sign, the signed answer; and for the administrator the
 * devices to approve, the offices and who works at each, the policy switch and the log of every check. See {@see DeviceAttendance}.
 */
#[OA\Tag(name: 'Inventory / Salon', description: 'Device-verified attendance')]
class SalonDeviceController extends Controller
{
    private function denied(DeviceDenied $d): JsonResponse
    {
        // Never "success": the status code says why, in words the person can act on.
        return response()->json(['message' => $d->getMessage(), 'code' => $d->outcome], 403);
    }

    /** The business admin controls the staff: no phone to register, no work to start (the staff's starts are what the owner reads). */
    private function refuseAdmin(Request $request): ?JsonResponse
    {
        return $request->user()->isBusinessAdmin() ? response()->json([
            'message' => 'Msimamizi wa biashara hasajili simu wala kuanza kazi: wafanyakazi ndio wanaofanya hivyo. / The business admin does not register a phone or start work: the staff do.',
            'code' => 'admin_does_not_start_work',
        ], 403) : null;
    }

    /** @return array<string, mixed> */
    private function present(?object $d): ?array
    {
        return $d === null ? null : [
            'id' => (int) $d->id,
            'user_id' => $d->user_id,
            'status' => $d->status,
            'platform' => $d->platform,
            'name' => $d->name,
            'manufacturer' => $d->manufacturer,
            'model' => $d->model,
            'os_name' => $d->os_name,
            'os_version' => $d->os_version,
            'app_version' => $d->app_version,
            'device_uuid' => $d->device_uuid,
            'ip' => $d->ip,
            'user_agent' => $d->user_agent,
            'note' => $d->decision_note,
            'consent_at' => ($d->consent_at ?? null) ? Carbon::parse($d->consent_at)->format('Y-m-d H:i') : null,
            'requested_at' => Carbon::parse($d->created_at)->format('Y-m-d H:i'),
            'decided_at' => $d->decided_at ? Carbon::parse($d->decided_at)->format('Y-m-d H:i') : null,
            'last_seen_at' => $d->last_seen_at ? Carbon::parse($d->last_seen_at)->format('Y-m-d H:i') : null,
        ];
    }

    // ------------------------------------------------------------------ the person's own

    #[OA\Get(path: '/inventory/salon/attendance/device', summary: 'My device, its status and the offices I may clock in at', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function mine(Request $request): JsonResponse
    {
        $uid = (string) $request->user()->id;

        return response()->json(['data' => [
            'policy_on' => DeviceAttendance::policyOn(),
            'timezone' => DeviceAttendance::timezone(),
            'device' => $this->present(DeviceAttendance::current($uid)),
            'offices' => DeviceAttendance::officesFor($uid),
        ]]);
    }

    #[OA\Post(path: '/inventory/salon/attendance/device/enroll', summary: 'Ask for this device to be registered', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Waiting for approval')])]
    public function enroll(Request $request): JsonResponse
    {
        if ($refused = $this->refuseAdmin($request)) {
            return $refused;
        }
        $data = $request->validate([
            'device_uuid' => 'required|string|min:16|max:64|regex:/^[A-Za-z0-9\-_]+$/',
            'public_key' => 'required|string|max:2000',
            'platform' => ['nullable', Rule::in(['android', 'ios', 'web'])],
            'name' => 'nullable|string|max:120',
            'manufacturer' => 'nullable|string|max:80',
            'model' => 'nullable|string|max:120',
            'os_name' => 'nullable|string|max:40',
            'os_version' => 'nullable|string|max:40',
            'app_version' => 'nullable|string|max:30',
            // the person agreed, in the app, to what is collected: no agreement, no registration
            'consent' => 'accepted',
        ], [
            'consent.accepted' => 'Kubali kwanza taarifa zitakazokusanywa ili kusajili kifaa. Kama huoni swali la ridhaa, sasisha app. / Agree to what is collected before registering a device. If you are not asked, update the app.',
        ]);
        $me = $request->user();
        $device = DeviceAttendance::enroll($me, $data, $request->ip(), $request->userAgent());
        app(InventoryNotifier::class)->notifyByPermission(
            ['inv_salon_devices'],
            'salon_device_request',
            'Kifaa kipya kinasubiri idhini / A device is waiting for approval',
            "{$me->name}: " . ($device->name ?: $device->model ?: $device->platform),
            ['device_id' => (int) $device->id],
            excludeUserId: (string) $me->id,
        );

        return response()->json(['message' => 'Waiting for approval', 'data' => $this->present($device)], 201);
    }

    #[OA\Post(path: '/inventory/salon/attendance/challenge', summary: 'A short-lived, single-use challenge for this device to sign', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success'), new OA\Response(response: 403, description: 'Refused, with a status code')])]
    public function challenge(Request $request): JsonResponse
    {
        if ($refused = $this->refuseAdmin($request)) {
            return $refused;
        }
        $data = $request->validate([
            'device_uuid' => 'required|string|max:64',
            'office_id' => 'nullable|integer',
            'purpose' => ['nullable', Rule::in(['in', 'out'])],
            'device_name' => 'nullable|string|max:120',
        ]);
        try {
            $out = DeviceAttendance::challenge($request->user(), isset($data['office_id']) ? (int) $data['office_id'] : null, $data['device_uuid'], $data['purpose'] ?? 'in', $request->ip(), $request->userAgent(), $data['device_name'] ?? null);
        } catch (DeviceDenied $d) {
            return $this->denied($d);
        }

        return response()->json(['data' => $out]);
    }

    #[OA\Post(path: '/inventory/salon/attendance/verify', summary: 'The signed challenge: starts or finishes work when every check passes', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Done'), new OA\Response(response: 403, description: 'Refused, with a status code')])]
    public function verify(Request $request): JsonResponse
    {
        $data = $request->validate([
            'challenge_id' => 'required|integer',
            'signature' => 'required|string|max:400',
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'accuracy' => 'nullable|numeric|min:0|max:100000',
            'location_at' => 'nullable|date',
            'mocked' => 'nullable|boolean',
        ]);
        try {
            $done = DeviceAttendance::verify($request->user(), $data, $request->ip(), $request->userAgent());
        } catch (DeviceDenied $d) {
            return $this->denied($d);
        }
        $a = $done['attendance'];

        return response()->json(['message' => $done['purpose'] === 'in' ? 'Clocked in' : 'Clocked out', 'data' => [
            'purpose' => $done['purpose'],
            'id' => (int) $a->id,
            // The server's own time: the phone's clock is never used.
            'clock_in' => Carbon::parse($a->clock_in)->format('Y-m-d H:i'),
            'clock_out' => $a->clock_out ? Carbon::parse($a->clock_out)->format('Y-m-d H:i') : null,
            'office_id' => $a->office_id === null ? null : (int) $a->office_id,
            // How far from the reference place the phone was, and whether that counts as being at work.
            'place' => $done['place'],
        ]], $done['purpose'] === 'in' ? 201 : 200);
    }

    // ------------------------------------------------------------------ the administrator

    #[OA\Get(path: '/inventory/salon/attendance/admin/devices', summary: 'Devices to approve, and the ones already decided', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function devices(Request $request): JsonResponse
    {
        $data = $request->validate(['status' => ['nullable', Rule::in(['pending', 'approved', 'rejected', 'blocked', 'replaced'])]]);
        $list = DB::table('inventory_attendance_devices')
            ->when(!empty($data['status']), fn ($q) => $q->where('status', $data['status']))
            ->orderByRaw("CASE WHEN status = 'pending' THEN 0 ELSE 1 END")->orderByDesc('id')->limit(200)->get();
        $names = User::query()->whereIn('id', $list->pluck('user_id')->unique()->values())->pluck('name', 'id');
        $rows = $list->map(fn ($d) => $this->present($d) + ['user_name' => $names[$d->user_id] ?? '']);

        return response()->json(['data' => $rows->values()]);
    }

    #[OA\Post(path: '/inventory/salon/attendance/admin/devices/{id}/decision', summary: 'Approve, reject, block or reset (replace) a device', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function decide(Request $request, int $id): JsonResponse
    {
        $data = $request->validate(['decision' => ['required', Rule::in(['approve', 'reject', 'block', 'reset'])], 'note' => 'nullable|string|max:200']);
        $device = DB::table('inventory_attendance_devices')->find($id);
        abort_if($device === null, 404, 'Not found');
        abort_if($device->status === 'replaced', 422, 'Kifaa hiki kimeshabadilishwa. / This device was already replaced.');
        abort_if($data['decision'] === 'approve' && !in_array($device->status, ['pending', 'blocked'], true), 422, 'Kifaa hiki hakiko kwenye hali ya kuidhinishwa. / This device is not waiting for approval.');
        DeviceAttendance::decide($device, $data['decision'], $data['note'] ?? null, (string) $request->user()->id);

        return response()->json(['message' => 'Saved', 'data' => $this->present(DB::table('inventory_attendance_devices')->find($id))]);
    }

    #[OA\Get(path: '/inventory/salon/attendance/admin/checks', summary: 'The log of every attendance check, good and bad', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function checks(Request $request): JsonResponse
    {
        $data = $request->validate(['user_id' => 'nullable|string|max:64', 'outcome' => 'nullable|string|max:30', 'flagged' => 'nullable|boolean']);
        $list = DB::table('inventory_attendance_checks')
            ->when(!empty($data['flagged']), fn ($q) => $q->where('flagged', true))
            ->when(!empty($data['user_id']), fn ($q) => $q->where('user_id', $data['user_id']))
            ->when(!empty($data['outcome']), fn ($q) => $q->where('outcome', $data['outcome']))
            ->orderByDesc('id')->limit(200)->get();
        $names = User::query()->whereIn('id', $list->pluck('user_id')->filter()->unique()->values())->pluck('name', 'id');
        $rows = $list->map(fn ($c) => [
                'id' => (int) $c->id,
                'user_id' => $c->user_id,
                'user_name' => $names[$c->user_id] ?? '',
                'device_id' => $c->device_id === null ? null : (int) $c->device_id,
                'office_id' => $c->office_id === null ? null : (int) $c->office_id,
                'purpose' => $c->purpose,
                'outcome' => $c->outcome,
                'detail' => $c->detail,
                'ip' => $c->ip,
                'latitude' => $c->latitude === null ? null : (float) $c->latitude,
                'longitude' => $c->longitude === null ? null : (float) $c->longitude,
                'accuracy_m' => $c->accuracy_m === null ? null : (float) $c->accuracy_m,
                'distance_m' => $c->distance_m === null ? null : (float) $c->distance_m,
                'place_status' => $c->place_status,
                'place_reference' => $c->place_reference,
                'mocked' => (bool) $c->mocked,
                // the audit trail: which attendance it made, the device registered to the person against the one that was used
                'attendance_id' => $c->attendance_id === null ? null : (int) $c->attendance_id,
                'registered_device_uuid' => $c->registered_device_uuid,
                'presented_device_uuid' => $c->presented_device_uuid,
                'presented_device_name' => $c->presented_device_name,
                'flagged' => (bool) $c->flagged,
                'status' => $c->flagged ? 'not_logged_in_device' : ($c->outcome === 'ok' ? 'verified' : 'refused'),
                'acknowledged' => $c->acknowledged_at !== null,
                'at' => Carbon::parse($c->created_at)->setTimezone(DeviceAttendance::timezone())->format('Y-m-d H:i:s'),
            ]);

        return response()->json(['data' => $rows->values(), 'meta' => ['flagged_open' => DB::table('inventory_attendance_checks')->where('flagged', true)->whereNull('acknowledged_at')->count()]]);
    }

    #[OA\Post(path: '/inventory/salon/attendance/admin/checks/{id}/acknowledge', summary: 'Mark a "not the logged-in device" case as seen', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function acknowledge(Request $request, int $id): JsonResponse
    {
        $check = DB::table('inventory_attendance_checks')->find($id);
        abort_if($check === null, 404, 'Not found');
        // seen for the person's whole spell, not only this line: the same case is not asked about twice
        DB::table('inventory_attendance_checks')->where('user_id', $check->user_id)->where('flagged', true)->whereNull('acknowledged_at')
            ->update(['acknowledged_at' => now(), 'acknowledged_by' => (string) $request->user()->id, 'updated_at' => now()]);

        return response()->json(['message' => 'Saved']);
    }

    #[OA\Get(path: '/inventory/salon/attendance/admin/offices', summary: 'Offices, with who works at each', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function offices(): JsonResponse
    {
        $staff = DB::table('inventory_attendance_office_staff')->get()->groupBy('office_id');
        $rows = DB::table('inventory_attendance_offices')->orderBy('name')->get()->map(fn ($o) => DeviceAttendance::presentOffice($o) + [
            'staff_ids' => ($staff[$o->id] ?? collect())->pluck('user_id')->values()->all(),
            // people who have a place of their own captured (it wins over the office's)
            'staff_places' => ($staff[$o->id] ?? collect())->filter(fn ($r) => $r->latitude !== null)->mapWithKeys(fn ($r) => [(string) $r->user_id => ['latitude' => (float) $r->latitude, 'longitude' => (float) $r->longitude, 'radius_m' => $r->radius_m === null ? null : (int) $r->radius_m, 'captured_at' => $r->captured_at]])->all(),
        ]);

        return response()->json(['data' => $rows->values()]);
    }

    #[OA\Post(path: '/inventory/salon/attendance/admin/offices', summary: 'Add an office', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 201, description: 'Created')])]
    public function storeOffice(Request $request): JsonResponse
    {
        $data = $this->officeFields($request);
        $id = DB::table('inventory_attendance_offices')->insertGetId($data + ['created_at' => now(), 'updated_at' => now()]);

        return response()->json(['message' => 'Saved', 'data' => DeviceAttendance::presentOffice(DB::table('inventory_attendance_offices')->find($id))], 201);
    }

    #[OA\Put(path: '/inventory/salon/attendance/admin/offices/{id}', summary: 'Change an office, or switch it off', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function updateOffice(Request $request, int $id): JsonResponse
    {
        abort_if(DB::table('inventory_attendance_offices')->where('id', $id)->doesntExist(), 404, 'Not found');
        DB::table('inventory_attendance_offices')->where('id', $id)->update($this->officeFields($request, true) + ['updated_at' => now()]);

        return response()->json(['message' => 'Saved', 'data' => DeviceAttendance::presentOffice(DB::table('inventory_attendance_offices')->find($id))]);
    }

    #[OA\Put(path: '/inventory/salon/attendance/admin/offices/{id}/staff', summary: 'Who may clock in at an office', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], parameters: [new OA\Parameter(name: 'id', in: 'path', required: true, schema: new OA\Schema(type: 'integer'))], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function setOfficeStaff(Request $request, int $id): JsonResponse
    {
        abort_if(DB::table('inventory_attendance_offices')->where('id', $id)->doesntExist(), 404, 'Not found');
        $data = $request->validate(['user_ids' => 'present|array|max:200', 'user_ids.*' => 'string|max:64']);
        // only people of this business (the users table is shared by every business)
        $members = \App\Support\Tenancy\TenantContext::viewer()?->accountMemberIds() ?? [];
        // the business admin is never an office's staff: they control the staff, they do not start work
        $mine = User::query()->whereIn('id', $data['user_ids'])->whereIn('id', $members)->get(['id', 'role'])->reject(fn (User $u) => $u->isBusinessAdmin())->pluck('id')->map(fn ($u) => (string) $u)->values()->all();
        DB::transaction(function () use ($id, $mine) {
            DB::table('inventory_attendance_office_staff')->where('office_id', $id)->whereNotIn('user_id', $mine)->delete();
            foreach ($mine as $uid) {
                if (DB::table('inventory_attendance_office_staff')->where('office_id', $id)->where('user_id', $uid)->doesntExist()) {
                    DB::table('inventory_attendance_office_staff')->insert(['office_id' => $id, 'user_id' => $uid, 'created_at' => now(), 'updated_at' => now()]);
                }
            }
        });

        return response()->json(['message' => 'Saved', 'data' => ['staff_ids' => $mine]]);
    }

    #[OA\Put(path: '/inventory/salon/attendance/admin/offices/{id}/staff/{userId}/place', summary: 'Capture the place one person is measured from (wins over the office\'s)', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function setPersonPlace(Request $request, int $id, string $userId): JsonResponse
    {
        $data = $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
            'accuracy' => 'nullable|numeric|min:0|max:100000',
            'radius_m' => 'nullable|integer|min:20|max:5000',
        ]);
        abort_if(($data['accuracy'] ?? 0) > DeviceAttendance::MAX_ACCURACY_M, 422, 'Mawasiliano ya GPS ni hafifu (± ' . (int) round($data['accuracy']) . ' m). Nenda eneo wazi uchukue tena. / The GPS signal is weak (± ' . (int) round($data['accuracy']) . ' m). Move to open space and capture again.');
        $link = DB::table('inventory_attendance_office_staff')->where('office_id', $id)->where('user_id', $userId);
        abort_if(!$link->exists(), 404, 'Mtu huyu hajapangiwa ofisi hii. / This person is not assigned to this office.');
        $link->update([
            'latitude' => $data['latitude'], 'longitude' => $data['longitude'], 'radius_m' => $data['radius_m'] ?? null,
            'captured_at' => now(), 'captured_by' => (string) $request->user()->id, 'capture_accuracy_m' => $data['accuracy'] ?? null, 'updated_at' => now(),
        ]);

        return response()->json(['message' => 'Saved', 'data' => ['user_id' => $userId, 'latitude' => (float) $data['latitude'], 'longitude' => (float) $data['longitude'], 'radius_m' => $data['radius_m'] ?? null]]);
    }

    #[OA\Delete(path: '/inventory/salon/attendance/admin/offices/{id}/staff/{userId}/place', summary: 'Go back to measuring one person from the office\'s place', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function clearPersonPlace(int $id, string $userId): JsonResponse
    {
        DB::table('inventory_attendance_office_staff')->where('office_id', $id)->where('user_id', $userId)
            ->update(['latitude' => null, 'longitude' => null, 'radius_m' => null, 'captured_at' => null, 'captured_by' => null, 'capture_accuracy_m' => null, 'updated_at' => now()]);

        return response()->json(['message' => 'Saved']);
    }

    #[OA\Get(path: '/inventory/salon/attendance/admin/policy', summary: 'Is device-verified attendance on?', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function policy(): JsonResponse
    {
        return response()->json(['data' => ['enabled' => DeviceAttendance::policyOn(), 'timezone' => DeviceAttendance::timezone()]]);
    }

    #[OA\Put(path: '/inventory/salon/attendance/admin/policy', summary: 'Turn device-verified attendance on or off', security: [['bearerAuth' => []]], tags: ['Inventory / Salon'], responses: [new OA\Response(response: 200, description: 'Success')])]
    public function savePolicy(Request $request): JsonResponse
    {
        $data = $request->validate(['enabled' => 'required|boolean', 'timezone' => ['nullable', 'string', Rule::in(\DateTimeZone::listIdentifiers())]]);
        DeviceAttendance::setPolicy((bool) $data['enabled'], $data['timezone'] ?? null);

        return response()->json(['message' => 'Saved', 'data' => ['enabled' => DeviceAttendance::policyOn(), 'timezone' => DeviceAttendance::timezone()]]);
    }

    /** @return array<string, mixed> */
    private function officeFields(Request $request, bool $partial = false): array
    {
        $required = $partial ? 'sometimes' : 'required';
        $data = $request->validate([
            'branch_id' => 'nullable|integer',
            'name' => ($partial ? 'sometimes' : 'required_without:branch_id') . '|nullable|string|min:2|max:120',
            'address' => 'nullable|string|max:200',
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'radius_m' => 'nullable|integer|min:20|max:5000',
            'accuracy' => 'nullable|numeric|min:0|max:100000',
            'geofence_required' => 'sometimes|boolean',
            'active' => 'sometimes|boolean',
        ]);
        if (($data['geofence_required'] ?? false) && (!array_key_exists('latitude', $data) || $data['latitude'] === null || !array_key_exists('longitude', $data) || $data['longitude'] === null)) {
            abort(422, 'Weka latitudo na longitudo ili kuhitaji eneo. / Give the office a latitude and longitude to require location.');
        }

        if (isset($data['accuracy']) && $data['accuracy'] > DeviceAttendance::MAX_ACCURACY_M) {
            abort(422, 'Mawasiliano ya GPS ni hafifu (± ' . (int) round($data['accuracy']) . ' m). Nenda eneo wazi uchukue tena. / The GPS signal is weak (± ' . (int) round($data['accuracy']) . ' m). Move to open space and capture again.');
        }
        if (isset($data['latitude'], $data['longitude'])) {
            $data['captured_at'] = now();
            $data['captured_by'] = (string) $request->user()->id;
            $data['capture_accuracy_m'] = $data['accuracy'] ?? null;
        }
        unset($data['accuracy']);
        if (!empty($data['branch_id'])) {
            $branch = DB::table('inventory_branches')->find($data['branch_id']);
            abort_if($branch === null, 422, 'Tawi hili halipo. / That branch does not exist.');
            $taken = DB::table('inventory_attendance_offices')->where('branch_id', $branch->id)->when($request->route('id'), fn ($q, $id) => $q->where('id', '!=', (int) $id))->exists();
            abort_if($taken, 422, 'Tawi hili tayari lina ofisi. / This branch already has an office.');
            $data['name'] = $branch->name;
        }
        abort_if(!$partial && empty($data['name']), 422, 'Weka jina la ofisi au chagua tawi. / Give the office a name or choose a branch.');

        return array_filter($data, fn ($v, $k) => $v !== null || in_array($k, ['address', 'latitude', 'longitude', 'branch_id', 'capture_accuracy_m'], true), ARRAY_FILTER_USE_BOTH);
    }
}
