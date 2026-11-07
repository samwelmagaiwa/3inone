import '../../services/device_identity.dart';
import '../../services/salon_api.dart';

/// What the server said about this person's phone and where they may start work (GET attendance/device).
class MyDevice {
  const MyDevice({required this.policyOn, this.status, this.deviceUuid, this.name, this.note, this.offices = const <AttendanceOffice>[]});

  factory MyDevice.fromJson(final Map<String, dynamic> j) {
    final dynamic d = j['device'];
    final Map<String, dynamic>? device = d is Map ? Map<String, dynamic>.from(d) : null;

    return MyDevice(
      policyOn: j['policy_on'] == true,
      status: device?['status']?.toString(),
      deviceUuid: device?['device_uuid']?.toString(),
      name: (device?['name'] ?? device?['model'])?.toString(),
      note: device?['note']?.toString(),
      offices: <AttendanceOffice>[
        if (j['offices'] is List)
          for (final dynamic o in j['offices'] as List)
            if (o is Map) AttendanceOffice.fromJson(Map<String, dynamic>.from(o)),
      ],
    );
  }

  /// Device checks are on for this business.
  final bool policyOn;

  /// pending / approved / rejected / blocked, or null when no phone was ever registered.
  final String? status;
  final String? deviceUuid;
  final String? name;
  final String? note;
  final List<AttendanceOffice> offices;

  bool get approved => status == 'approved';
}

/// An office with its own number, so two offices with the same name are never mistaken for each other.
class AttendanceOffice {
  const AttendanceOffice({required this.id, required this.name, this.branchId, this.address, this.geofenceRequired = false, this.active = true, this.latitude, this.longitude, this.radiusM = 150, this.staffIds = const <String>[], this.staffPlaceIds = const <String>{}});

  factory AttendanceOffice.fromJson(final Map<String, dynamic> j) => AttendanceOffice(
        id: (j['id'] as num).toInt(),
        branchId: (j['branch_id'] as num?)?.toInt(),
        name: j['name']?.toString() ?? '',
        address: j['address']?.toString(),
        geofenceRequired: j['geofence_required'] == true,
        active: j['active'] != false,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        radiusM: (j['radius_m'] as num?)?.toInt() ?? 150,
        staffIds: <String>[if (j['staff_ids'] is List) for (final dynamic s in j['staff_ids'] as List) s.toString()],
        staffPlaceIds: <String>{if (j['staff_places'] is Map) ...(j['staff_places'] as Map).keys.map((dynamic k) => k.toString())},
      );

  final int id;

  /// The branch this office is (its name and address come from there), or null for an office of its own.
  final int? branchId;
  final String name;
  final String? address;
  final bool geofenceRequired;
  final bool active;
  final double? latitude;
  final double? longitude;
  final int radiusM;
  final List<String> staffIds;

  /// People who have a place of their own captured (it wins over the office's).
  final Set<String> staffPlaceIds;

  /// "Kariakoo · #3": the name always travels with the number.
  String get label => '$name · #$id';
}

/// Start or finish work from this phone: ask the server for a challenge, sign it with the key that never leaves the phone, add where
/// the phone is, and send it back. The server decides; a refusal comes back as its own sentence (an ApiException) and nothing is recorded.
class DeviceAttendanceFlow {
  DeviceAttendanceFlow({required this.api, required this.identity});

  final SalonApi api;
  final DeviceIdentity identity;

  Future<MyDevice> mine() async => MyDevice.fromJson(await api.myDevice());

  /// Register this phone (it waits for an administrator).
  Future<void> enroll() async {
    final DeviceFacts f = await identity.facts();
    await api.enrollDevice(uuid: f.uuid, publicKey: f.publicKey, platform: f.platform, name: f.name, manufacturer: f.manufacturer, model: f.model, osName: f.osName, osVersion: f.osVersion, appVersion: f.appVersion);
  }

  /// [purpose] 'in' needs the office; 'out' does not. Returns what the server measured: how far the phone was from the place it is checked against.
  Future<PlaceResult?> run({required final String purpose, final int? officeId}) async {
    final String uuid = await identity.uuid();
    final Map<String, dynamic> c = await api.attendanceChallenge(deviceUuid: uuid, purpose: purpose, officeId: officeId);
    final String signature = await identity.sign(c['payload']?.toString() ?? '');
    final PhonePlace? where = await identity.place();
    final Map<String, dynamic> done = await api.attendanceVerify(
      challengeId: (c['challenge_id'] as num).toInt(),
      signature: signature,
      latitude: where?.latitude,
      longitude: where?.longitude,
      accuracy: where?.accuracy,
      locationAt: where?.at,
      mocked: where?.mocked ?? false,
    );
    final dynamic place = done['place'];

    return place is Map ? PlaceResult.fromJson(Map<String, dynamic>.from(place)) : null;
  }
}

/// How far the person was from the place they are checked against, and whether that counts as being at work.
class PlaceResult {
  const PlaceResult({required this.status, this.distanceM, this.radiusM, this.reference});

  factory PlaceResult.fromJson(final Map<String, dynamic> j) => PlaceResult(
        status: j['status']?.toString() ?? 'no_reference',
        distanceM: (j['distance_m'] as num?)?.toDouble(),
        radiusM: (j['radius_m'] as num?)?.toInt(),
        reference: j['reference']?.toString(),
      );

  /// at_work · away · no_location · no_reference · stale · weak_signal · mocked
  final String status;
  final double? distanceM;
  final int? radiusM;
  final String? reference;

  bool get atWork => status == 'at_work';
}

/// In plain words: "You are at work: 35 m from the office (150 m allowed)" or why the place could not be confirmed.
String placeSentence({required final bool sw, required final PlaceResult p}) {
  final String m = p.distanceM == null ? '' : '${p.distanceM!.round()} m';
  final String of = p.reference == 'person' ? (sw ? 'mahali pako pa kazi' : 'your work place') : (sw ? 'ofisi' : 'the office');
  final String allowed = p.radiusM == null ? '' : (sw ? ' (ruhusa ${p.radiusM} m)' : ' (${p.radiusM} m allowed)');
  switch (p.status) {
    case 'at_work':
      return sw ? 'Uko kazini: $m kutoka $of$allowed.' : 'You are at work: $m from $of$allowed.';
    case 'away':
      return sw ? 'Uko mbali: $m kutoka $of$allowed.' : 'You are away: $m from $of$allowed.';
    case 'no_location':
      return sw ? 'Mahali hapakupatikana (location imezimwa?).' : 'Your place could not be found (is location off?).';
    case 'stale':
      return sw ? 'Eneo lililotumwa ni la zamani.' : 'The location sent was old.';
    case 'weak_signal':
      return sw ? 'Mawasiliano ya GPS ni hafifu, mahali hapakuthibitishwa.' : 'The GPS signal is weak, so the place is not confirmed.';
    case 'mocked':
      return sw ? 'Eneo bandia limegunduliwa.' : 'A fake location was detected.';
    default:
      return sw ? 'Hakuna mahali pa kulinganisha bado.' : 'There is no place to compare with yet.';
  }
}
