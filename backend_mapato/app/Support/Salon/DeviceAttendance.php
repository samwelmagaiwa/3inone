<?php

namespace App\Support\Salon;

use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

/**
 * Starting and finishing work from one's own approved device.
 *
 * Each person may have ONE approved device. The app on it makes a key pair (ECDSA P-256) and keeps the private key; the server keeps the public
 * key. To start work the app asks for a short-lived, single-use challenge for an office, signs it, and sends the signature (with the place, when
 * the office wants it). The server checks the person, the device, its approval, the office, the signature and the place, and only then writes the
 * attendance, at the SERVER's time. Whatever fails is written to a log with a plain reason, and no attendance is written.
 *
 * What is NOT trusted: the phone's clock, the device name, the IP address and the browser's fingerprint (they are only recorded), and a GPS
 * position alone (it can be faked: it is one more check, not proof). On a phone the private key lives in the app's secure storage; in a browser it
 * is a non-exportable key in the browser's own store, which is weaker (see docs/ATTENDANCE_DEVICES.md).
 */
final class DeviceAttendance
{
    public const POLICY_KEY = 'attendance_device_policy';

    public const TIMEZONE_KEY = 'attendance_timezone';

    public const CHALLENGE_SECONDS = 90;

    // ------------------------------------------------------------------ the policy

    /** Off until the owner turns it on: a business that has not enrolled its phones is not locked out. */
    public static function policyOn(): bool
    {
        return DB::table('inventory_settings')->where('key', self::POLICY_KEY)->value('value') === '1';
    }

    public static function setPolicy(bool $on, ?string $timezone = null): void
    {
        DB::table('inventory_settings')->updateOrInsert(['key' => self::POLICY_KEY], ['value' => $on ? '1' : '0', 'updated_at' => now()]);
        if ($timezone !== null && $timezone !== '') {
            DB::table('inventory_settings')->updateOrInsert(['key' => self::TIMEZONE_KEY], ['value' => $timezone, 'updated_at' => now()]);
        }
    }

    public static function timezone(): string
    {
        $tz = (string) DB::table('inventory_settings')->where('key', self::TIMEZONE_KEY)->value('value');

        return in_array($tz, \DateTimeZone::listIdentifiers(), true) ? $tz : AppointmentPlanner::TIMEZONE;
    }

    /** The server's own time, in the business's timezone: the only attendance time there is. */
    public static function now(): Carbon
    {
        return Carbon::now(self::timezone());
    }

    // ------------------------------------------------------------------ the device

    /** The person's current device: the newest that has not been replaced (it may be pending, approved, rejected or blocked). */
    public static function current(string $userId): ?object
    {
        return DB::table('inventory_attendance_devices')->where('user_id', $userId)->where('status', '!=', 'replaced')->orderByDesc('id')->first();
    }

    /**
     * Ask for a device to be registered. The key is checked (it must be a P-256 public key). A person with a pending, approved or blocked device
     * cannot register another: an administrator resets it first.
     *
     * @param  array<string, mixed>  $data
     */
    public static function enroll(User $user, array $data, ?string $ip, ?string $agent): object
    {
        $pem = self::normalizeKey((string) $data['public_key']);
        $have = self::current((string) $user->id);
        if ($have !== null && $have->status !== 'rejected') {
            throw ValidationException::withMessages(['device' => ['Una kifaa kilichosajiliwa au kinachosubiri idhini. Msimamizi akikiondoa unaweza kusajili kipya. / You already have a registered or waiting device. An administrator must reset it before you can register another.']]);
        }
        $taken = DB::table('inventory_attendance_devices')->where('device_uuid', $data['device_uuid'])->where('user_id', '!=', (string) $user->id)->where('status', '!=', 'replaced')->exists();
        if ($taken) {
            throw ValidationException::withMessages(['device_uuid' => ['Kifaa hiki kimesajiliwa kwa mtu mwingine. / This device is registered to someone else.']]);
        }
        $id = DB::table('inventory_attendance_devices')->insertGetId([
            'user_id' => (string) $user->id,
            'device_uuid' => (string) $data['device_uuid'],
            'public_key' => $pem,
            'key_algorithm' => 'ES256',
            'platform' => (string) ($data['platform'] ?? 'android'),
            'name' => self::clip($data['name'] ?? null, 120),
            'manufacturer' => self::clip($data['manufacturer'] ?? null, 80),
            'model' => self::clip($data['model'] ?? null, 120),
            'os_name' => self::clip($data['os_name'] ?? null, 40),
            'os_version' => self::clip($data['os_version'] ?? null, 40),
            'app_version' => self::clip($data['app_version'] ?? null, 30),
            'user_agent' => self::clip($agent, 255),
            'ip' => $ip,
            'status' => 'pending',
            'last_seen_at' => now(),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return DB::table('inventory_attendance_devices')->find($id);
    }

    /** An administrator's decision on a device. Nothing is deleted: a replaced device keeps its row and its history. */
    public static function decide(object $device, string $decision, ?string $note, string $by): void
    {
        $status = match ($decision) {
            'approve' => 'approved',
            'reject' => 'rejected',
            'block' => 'blocked',
            'reset' => 'replaced',
        };
        DB::transaction(function () use ($device, $status, $note, $by) {
            if ($status === 'approved') {
                // one approved device per person: any other is put away (replaced), never deleted
                DB::table('inventory_attendance_devices')->where('user_id', $device->user_id)->where('id', '!=', $device->id)->whereIn('status', ['approved', 'pending'])->update(['status' => 'replaced', 'updated_at' => now()]);
            }
            DB::table('inventory_attendance_devices')->where('id', $device->id)->update(['status' => $status, 'decision_note' => self::clip($note, 200), 'decided_by' => $by, 'decided_at' => now(), 'updated_at' => now()]);
        });
    }

    // ------------------------------------------------------------------ offices

    /** The active offices a person is assigned to. */
    public static function officesFor(string $userId): array
    {
        return DB::table('inventory_attendance_offices as o')
            ->join('inventory_attendance_office_staff as s', 's.office_id', '=', 'o.id')
            ->where('s.user_id', $userId)->where('o.active', true)
            ->orderBy('o.name')->get(['o.*'])
            ->map(fn ($o) => self::presentOffice($o))->all();
    }

    /** @return array<string, mixed> */
    public static function presentOffice(object $o): array
    {
        // An office that IS a branch takes the branch's name and address (so a rename there shows here); the office keeps only the
        // attendance rules (the place to check, the radius, who works there).
        $branch = ($o->branch_id ?? null) === null ? null : DB::table('inventory_branches')->find($o->branch_id);
        $place = $branch === null ? null : trim((string) ($branch->address ?: implode(', ', array_filter([$branch->street ?? null, $branch->ward ?? null, $branch->district ?? null, $branch->region ?? null]))));

        return [
            'id' => (int) $o->id,
            'branch_id' => $branch === null ? null : (int) $branch->id,
            'name' => $branch?->name ?? $o->name,
            'address' => $branch === null ? $o->address : ($place !== '' ? $place : $o->address),
            'latitude' => $o->latitude === null ? null : (float) $o->latitude,
            'longitude' => $o->longitude === null ? null : (float) $o->longitude,
            'radius_m' => (int) $o->radius_m,
            'geofence_required' => (bool) $o->geofence_required,
            'active' => (bool) $o->active,
        ];
    }

    private static function authorizedOffice(string $userId, ?int $officeId): ?object
    {
        if ($officeId === null) {
            return null;
        }
        $office = DB::table('inventory_attendance_offices')->where('id', $officeId)->where('active', true)->first();
        if ($office === null || !DB::table('inventory_attendance_office_staff')->where('office_id', $officeId)->where('user_id', $userId)->exists()) {
            return null;
        }

        return $office;
    }

    // ------------------------------------------------------------------ a challenge to sign

    /**
     * Ready the device for starting (or finishing) work. Every refusal is logged with its reason.
     *
     * @return array<string, mixed>
     */
    public static function challenge(User $user, ?int $officeId, string $deviceUuid, string $purpose, ?string $ip, ?string $agent): array
    {
        $uid = (string) $user->id;
        $device = self::current($uid);
        $office = null;
        try {
            if ($device === null) {
                throw new DeviceDenied('device_not_registered', 'Hujasajili kifaa. / No device is registered for you yet.');
            }
            if (!hash_equals((string) $device->device_uuid, $deviceUuid)) {
                throw new DeviceDenied('device_mismatch', 'Hiki si kifaa ulichosajili. / This is not the device you registered.');
            }
            self::requireApproved($device);

            $open = DB::table('inventory_attendance')->where('staff_id', $uid)->whereNull('clock_out')->orderByDesc('id')->first();
            if ($purpose === 'out') {
                if ($open === null) {
                    throw new DeviceDenied('no_active_session', 'Hujaanza kazi bado. / You have not started work.');
                }
                $officeId = $open->office_id === null ? null : (int) $open->office_id;
            } else {
                if ($open !== null) {
                    throw new DeviceDenied('already_clocked_in', 'Tayari umeanza kazi. / You are already at work.');
                }
                $office = self::authorizedOffice($uid, $officeId);
                if ($office === null) {
                    throw new DeviceDenied('office_not_authorized', 'Huna ruhusa ya ofisi hii, au haitumiki. / You are not assigned to this office, or it is not active.');
                }
            }
        } catch (DeviceDenied $d) {
            self::log($user, $device, $officeId, $purpose, $d->outcome, $d->getMessage(), $ip, $agent);
            throw $d;
        }

        $nonce = Str::random(40);
        $id = DB::table('inventory_attendance_challenges')->insertGetId([
            'user_id' => $uid, 'device_id' => $device->id, 'office_id' => $officeId, 'purpose' => $purpose, 'nonce' => $nonce,
            'expires_at' => now()->addSeconds(self::CHALLENGE_SECONDS), 'created_at' => now(), 'updated_at' => now(),
        ]);
        DB::table('inventory_attendance_devices')->where('id', $device->id)->update(['last_seen_at' => now(), 'ip' => $ip, 'user_agent' => self::clip($agent, 255)]);

        return [
            'challenge_id' => (int) $id,
            'nonce' => $nonce,
            'expires_in' => self::CHALLENGE_SECONDS,
            // What the device signs, byte for byte: the server builds the same text from its own records.
            'payload' => self::payload($id, $nonce, $uid, $officeId, (string) $device->device_uuid, $purpose),
            'office' => $office === null ? null : self::presentOffice($office),
        ];
    }

    public static function payload(int $challengeId, string $nonce, string $userId, ?int $officeId, string $deviceUuid, string $purpose): string
    {
        return implode('|', ['3INONE-ATT', 'v1', $challengeId, $nonce, $userId, $officeId ?? 0, $deviceUuid, $purpose]);
    }

    // ------------------------------------------------------------------ checking the answer and writing the attendance

    /**
     * @param  array{challenge_id: int, signature: string, latitude?: ?float, longitude?: ?float, accuracy?: ?float, location_at?: ?string}  $answer
     * @return array{attendance: object, purpose: string}
     */
    public static function verify(User $user, array $answer, ?string $ip, ?string $agent): array
    {
        $uid = (string) $user->id;
        $challenge = DB::table('inventory_attendance_challenges')->where('id', $answer['challenge_id'])->where('user_id', $uid)->first();
        $device = $challenge === null ? self::current($uid) : DB::table('inventory_attendance_devices')->find($challenge->device_id);
        $purpose = $challenge->purpose ?? 'in';
        $officeId = $challenge?->office_id === null ? null : (int) $challenge->office_id;
        $where = ['lat' => $answer['latitude'] ?? null, 'lng' => $answer['longitude'] ?? null, 'acc' => $answer['accuracy'] ?? null, 'at' => $answer['location_at'] ?? null, 'mocked' => !empty($answer['mocked'])];
        $verdict = null;

        try {
            if ($challenge === null) {
                throw new DeviceDenied('challenge_expired', 'Ombi hili halijulikani. Jaribu tena. / That request is not known. Try again.');
            }
            // Single use, decided atomically: whoever burns it first has it; a second answer finds it used.
            $burned = DB::table('inventory_attendance_challenges')->where('id', $challenge->id)->whereNull('used_at')->update(['used_at' => now(), 'updated_at' => now()]);
            if ($burned === 0 || Carbon::parse($challenge->expires_at)->isPast()) {
                throw new DeviceDenied('challenge_expired', 'Muda wa ombi umeisha au limeshatumika. Jaribu tena. / The request has expired or was already used. Try again.');
            }
            // The device must still be the person's current, approved one (it may have been reset or blocked since the challenge was made).
            $current = self::current($uid);
            if ($current === null || $device === null || (int) $current->id !== (int) $device->id) {
                throw new DeviceDenied('device_mismatch', 'Kifaa hiki kimebadilishwa. / This device was replaced.');
            }
            self::requireApproved($current);
            if (!self::signatureValid((string) $current->public_key, self::payload((int) $challenge->id, (string) $challenge->nonce, $uid, $officeId, (string) $current->device_uuid, $purpose), (string) $answer['signature'])) {
                throw new DeviceDenied('signature_invalid', 'Uthibitisho wa kifaa umeshindwa. / The device could not be verified.');
            }
            $office = $purpose === 'in' ? self::authorizedOffice($uid, $officeId) : ($officeId === null ? null : DB::table('inventory_attendance_offices')->find($officeId));
            if ($purpose === 'in' && $office === null) {
                throw new DeviceDenied('office_not_authorized', 'Huna ruhusa ya ofisi hii. / You are not assigned to this office.');
            }
            // Where the person is, measured from the reference place the administrator captured (theirs if they have one, else the office's).
            // Recorded every time, for starting and for finishing; it only BLOCKS a start at an office that requires its place.
            $placeOffice = $office;
            if ($purpose === 'out' && $placeOffice === null) {
                $openNow = DB::table('inventory_attendance')->where('staff_id', $uid)->whereNull('clock_out')->orderByDesc('id')->first();
                $placeOffice = $openNow?->office_id === null ? null : DB::table('inventory_attendance_offices')->find($openNow->office_id);
            }
            $link = $placeOffice === null ? null : DB::table('inventory_attendance_office_staff')->where('office_id', $placeOffice->id)->where('user_id', $uid)->first();
            $verdict = self::placeVerdict($placeOffice, $link, $where);
            $where += ['dist' => $verdict['distance_m'], 'status' => $verdict['status'], 'ref' => $verdict['reference']];
            if ($purpose === 'in' && $office !== null) {
                self::enforcePlace($office, $verdict);
            }

            $attendance = DB::transaction(function () use ($uid, $user, $purpose, $officeId, $current, $ip, $where) {
                $open = DB::table('inventory_attendance')->where('staff_id', $uid)->whereNull('clock_out')->orderByDesc('id')->lockForUpdate()->first();
                $now = self::now();
                if ($purpose === 'out') {
                    if ($open === null) {
                        throw new DeviceDenied('no_active_session', 'Hujaanza kazi bado. / You have not started work.');
                    }
                    DB::table('inventory_attendance')->where('id', $open->id)->update(['clock_out' => $now->format('Y-m-d H:i:s'), 'updated_at' => now()]);

                    return DB::table('inventory_attendance')->find($open->id);
                }
                if ($open !== null) {
                    throw new DeviceDenied('already_clocked_in', 'Tayari umeanza kazi. / You are already at work.');
                }
                $id = DB::table('inventory_attendance')->insertGetId([
                    'staff_id' => $uid,
                    'staff_name' => $user->name,
                    'work_date' => $now->toDateString(),
                    'clock_in' => $now->format('Y-m-d H:i:s'),
                    'office_id' => $officeId,
                    'device_id' => $current->id,
                    'source' => 'verified',
                    'ip' => $ip,
                    'latitude' => $where['lat'],
                    'longitude' => $where['lng'],
                    'accuracy_m' => $where['acc'],
                    'distance_m' => $where['dist'] ?? null,
                    'place_status' => $where['status'] ?? null,
                    'place_reference' => $where['ref'] ?? null,
                    'mocked' => (bool) $where['mocked'],
                    'created_by' => $uid,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                return DB::table('inventory_attendance')->find($id);
            });
        } catch (DeviceDenied $d) {
            self::log($user, $device, $officeId, $purpose, $d->outcome, $d->getMessage(), $ip, $agent, $where);
            throw $d;
        }
        self::log($user, $device, $officeId, $purpose, 'ok', $purpose === 'in' ? 'Started work' : 'Finished work', $ip, $agent, $where);

        return ['attendance' => $attendance, 'purpose' => $purpose, 'place' => $verdict];
    }

    private static function requireApproved(object $device): void
    {
        $status = (string) $device->status;
        if ($status === 'approved') {
            return;
        }
        $words = [
            'pending' => 'Kifaa chako kinasubiri idhini ya msimamizi. / Your device is waiting for an administrator\'s approval.',
            'rejected' => 'Usajili wa kifaa chako ulikataliwa. / Your device registration was rejected.',
            'blocked' => 'Kifaa chako kimezuiwa. / Your device has been blocked.',
        ];
        throw new DeviceDenied($status, $words[$status] ?? 'Kifaa hakiruhusiwi. / The device is not allowed.');
    }

    /** The most inaccurate a GPS fix may be (metres) and still count as proof of being somewhere; and how old a fix may be (seconds). */
    public const MAX_ACCURACY_M = 100;
    public const MAX_FIX_AGE_S = 180;

    /**
     * Is this person really at work? The distance from the reference place (the person's own captured place, else the office's) to where the
     * phone says it is, weighed against the radius, the fix's accuracy and age, and whether the phone says the location is faked. A place is
     * strong evidence but never proof; the verdict is kept on every attempt, and only an office that REQUIRES it blocks on it.
     *
     * status: at_work · away · no_location · no_reference · stale · weak_signal · mocked
     *
     * @param  array{lat?: ?float, lng?: ?float, acc?: ?float, at?: ?string, mocked?: bool}  $where
     * @return array{status: string, distance_m: ?float, radius_m: ?int, reference: ?string, accuracy_m: ?float}
     */
    public static function placeVerdict(?object $office, ?object $link, array $where): array
    {
        $lat = $lng = $radius = null;
        $source = null;
        if ($link !== null && $link->latitude !== null && $link->longitude !== null) {
            [$lat, $lng, $radius, $source] = [(float) $link->latitude, (float) $link->longitude, (int) ($link->radius_m ?: ($office->radius_m ?? 150)), 'person'];
        } elseif ($office !== null && $office->latitude !== null && $office->longitude !== null) {
            [$lat, $lng, $radius, $source] = [(float) $office->latitude, (float) $office->longitude, (int) $office->radius_m, 'office'];
        }
        $has = ($where['lat'] ?? null) !== null && ($where['lng'] ?? null) !== null;
        $acc = isset($where['acc']) ? (float) $where['acc'] : null;
        $distance = $source !== null && $has ? round(self::metres($lat, $lng, (float) $where['lat'], (float) $where['lng']), 1) : null;

        $age = null;
        if ($has && !empty($where['at'])) {
            try {
                $age = abs(Carbon::now('UTC')->diffInSeconds(Carbon::parse($where['at'])->utc()));
            } catch (\Throwable) {
                $age = null;
            }
        }

        if ($source === null) {
            $status = 'no_reference';
        } elseif (!$has) {
            $status = 'no_location';
        } elseif (!empty($where['mocked'])) {
            $status = 'mocked';
        } elseif ($age !== null && $age > self::MAX_FIX_AGE_S) {
            $status = 'stale';
        } elseif ($acc !== null && $acc > self::MAX_ACCURACY_M) {
            $status = 'weak_signal';
        } elseif ($distance <= $radius || ($acc !== null && $distance - $acc <= $radius)) {
            // inside the circle, or inside it once the GPS's own uncertainty is allowed for
            $status = 'at_work';
        } else {
            $status = 'away';
        }

        return ['status' => $status, 'distance_m' => $distance, 'radius_m' => $radius, 'reference' => $source, 'accuracy_m' => $acc];
    }

    /** Only an office that requires its place blocks a start; for every other office the verdict is just kept. */
    private static function enforcePlace(object $office, array $verdict): void
    {
        if (!(bool) $office->geofence_required || $verdict['status'] === 'at_work' || $verdict['status'] === 'no_reference') {
            return;
        }
        $m = $verdict['distance_m'] === null ? '' : (int) round($verdict['distance_m']);
        $words = [
            'no_location' => 'Ofisi hii inahitaji eneo lako. Washa location. / This office needs your location. Turn location on.',
            'mocked' => 'Eneo la bandia limegunduliwa. Zima programu ya eneo bandia. / A fake location was detected. Turn the mock-location app off.',
            'stale' => 'Eneo ulilotuma ni la zamani. Jaribu tena. / The location sent is old. Try again.',
            'weak_signal' => 'Mawasiliano ya GPS ni hafifu (± ' . (int) round((float) $verdict['accuracy_m']) . ' m). Nenda eneo wazi ujaribu tena. / The GPS signal is weak (± ' . (int) round((float) $verdict['accuracy_m']) . ' m). Move to open space and try again.',
            'away' => "Uko mbali na ofisi ({$m} m, ruhusa ni {$verdict['radius_m']} m). / You are away from the office ({$m} m; {$verdict['radius_m']} m allowed).",
        ];
        throw new DeviceDenied('location_out_of_range', $words[$verdict['status']] ?? $words['away']);
    }

    public static function metres(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $r = 6371000.0;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        return 2 * $r * asin(min(1.0, sqrt($a)));
    }

    // ------------------------------------------------------------------ the key and the signature

    /** Accept a public key as PEM or as base64 DER (SubjectPublicKeyInfo); it must be an EC P-256 key. Returns it as PEM. */
    public static function normalizeKey(string $input): string
    {
        $input = trim($input);
        if (!str_contains($input, 'BEGIN PUBLIC KEY')) {
            $der = base64_decode(strtr($input, '-_', '+/'), true);
            if ($der === false || $der === '') {
                throw ValidationException::withMessages(['public_key' => ['Ufunguo si sahihi. / The key is not valid.']]);
            }
            $input = "-----BEGIN PUBLIC KEY-----\n" . chunk_split(base64_encode($der), 64, "\n") . "-----END PUBLIC KEY-----\n";
        }
        $key = @openssl_pkey_get_public($input);
        $details = $key === false ? null : openssl_pkey_get_details($key);
        if ($details === null || ($details['type'] ?? null) !== OPENSSL_KEYTYPE_EC || ($details['ec']['curve_name'] ?? '') !== 'prime256v1') {
            throw ValidationException::withMessages(['public_key' => ['Ufunguo lazima uwe wa aina ya ECDSA P-256. / The key must be an ECDSA P-256 public key.']]);
        }

        return $input;
    }

    /** Verify an ES256 signature, as DER (OpenSSL, Android) or as the raw 64 bytes r||s (browsers' Web Crypto, many libraries). */
    public static function signatureValid(string $pem, string $payload, string $signatureBase64): bool
    {
        $sig = base64_decode(strtr($signatureBase64, '-_', '+/'), true);
        if ($sig === false || $sig === '') {
            return false;
        }
        if (strlen($sig) === 64) {
            $sig = self::rawToDer($sig);
        }

        return openssl_verify($payload, $sig, $pem, OPENSSL_ALGO_SHA256) === 1;
    }

    /** r||s (32 bytes each) into the DER sequence OpenSSL expects. */
    public static function rawToDer(string $raw): string
    {
        $int = function (string $bytes): string {
            $bytes = ltrim($bytes, "\x00");
            if ($bytes === '' || ord($bytes[0]) > 0x7F) {
                $bytes = "\x00" . $bytes;
            }

            return "\x02" . chr(strlen($bytes)) . $bytes;
        };
        $body = $int(substr($raw, 0, 32)) . $int(substr($raw, 32, 32));

        return "\x30" . chr(strlen($body)) . $body;
    }

    // ------------------------------------------------------------------ the log

    /** @param  array{lat?: ?float, lng?: ?float, acc?: ?float, at?: ?string}  $where */
    public static function log(User $user, ?object $device, ?int $officeId, string $purpose, string $outcome, ?string $detail, ?string $ip, ?string $agent, array $where = []): void
    {
        DB::table('inventory_attendance_checks')->insert([
            'user_id' => (string) $user->id,
            'device_id' => $device?->id,
            'office_id' => $officeId,
            'purpose' => $purpose,
            'outcome' => $outcome,
            'detail' => self::clip($detail, 255),
            'ip' => $ip,
            'user_agent' => self::clip($agent, 255),
            'latitude' => $where['lat'] ?? null,
            'longitude' => $where['lng'] ?? null,
            'accuracy_m' => $where['acc'] ?? null,
            'distance_m' => $where['dist'] ?? null,
            'place_status' => $where['status'] ?? null,
            'place_reference' => $where['ref'] ?? null,
            'mocked' => !empty($where['mocked']),
            'location_at' => isset($where['at']) && $where['at'] ? Carbon::parse($where['at'])->utc()->format('Y-m-d H:i:s') : null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    private static function clip(mixed $v, int $n): ?string
    {
        $v = $v === null ? null : trim((string) $v);

        return $v === null || $v === '' ? null : mb_substr($v, 0, $n);
    }
}
