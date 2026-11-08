import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/attendance_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/device_attendance_flow.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/devices_admin_screen.dart';
import 'package:boda_mapato/modules/inventory/services/device_identity.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Attendance from one's own approved device: the phone asks to be registered, an administrator decides, and starting work goes through a
/// signed challenge (never the plain tap) when the business turned device checks on.
class _Identity implements DeviceIdentity {
  final List<String> signed = <String>[];
  PhonePlace? where = const PhonePlace(latitude: -6.8, longitude: 39.27, accuracy: 10);

  @override
  Future<DeviceFacts> facts() async => const DeviceFacts(uuid: 'phone-uuid-000000001', publicKey: 'PUBLIC', name: 'Tecno Spark', manufacturer: 'Tecno', model: 'Spark', osName: 'Android', osVersion: '13', appVersion: '1.0.0+72');

  @override
  Future<String> uuid() async => 'phone-uuid-000000001';

  @override
  Future<String> sign(String payload) async {
    signed.add(payload);
    return 'SIG($payload)';
  }

  @override
  Future<PhonePlace?> place() async => where;
}

class _Fake extends SalonApi {
  bool policyOn = true;
  String? status;
  List<Map<String, dynamic>> offices = <Map<String, dynamic>>[<String, dynamic>{'id': 3, 'name': 'Kariakoo'}];
  bool atWork = false;
  Object? refuse;
  final List<String> calls = <String>[];
  final List<String?> names = <String?>[];
  final List<int> acknowledged = <int>[];
  final List<Map<String, dynamic>> verified = <Map<String, dynamic>>[];
  final List<(int, String)> decisions = <(int, String)>[];
  List<Map<String, dynamic>> devices = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> officeSaves = <Map<String, dynamic>>[];
  final List<bool> policySaves = <bool>[];

  @override
  Future<AttendanceNow> attendanceToday() async => AttendanceNow(atWork: atWork, since: atWork ? DateTime(2026, 11, 9, 9) : null);

  @override
  Future<List<AttendancePerson>> attendance(String month) async => <AttendancePerson>[];

  @override
  Future<Map<String, dynamic>> myDevice() async => <String, dynamic>{
        'policy_on': policyOn,
        'device': status == null ? null : <String, dynamic>{'status': status, 'device_uuid': 'phone-uuid-000000001', 'name': 'Tecno Spark'},
        'offices': offices,
      };

  @override
  Future<Map<String, dynamic>> enrollDevice({required String uuid, required String publicKey, String? platform, String? name, String? manufacturer, String? model, String? osName, String? osVersion, String? appVersion}) async {
    calls.add('enroll:$uuid:$publicKey');
    status = 'pending';
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> attendanceChallenge({required String deviceUuid, required String purpose, int? officeId, String? deviceName}) async {
    calls.add('challenge:$purpose:$officeId');
    names.add(deviceName);
    if (refuse != null) throw refuse!;
    return <String, dynamic>{'challenge_id': 77, 'payload': 'P|$purpose|${officeId ?? 0}'};
  }

  Map<String, dynamic>? placeAnswer;

  @override
  Future<Map<String, dynamic>> attendanceVerify({required int challengeId, required String signature, double? latitude, double? longitude, double? accuracy, DateTime? locationAt, bool mocked = false}) async {
    verified.add(<String, dynamic>{'id': challengeId, 'sig': signature, 'lat': latitude, 'lng': longitude, 'mocked': mocked});
    atWork = !atWork;
    return <String, dynamic>{if (placeAnswer != null) 'place': placeAnswer};
  }

  final List<(String, double, double)> personPlaces = <(String, double, double)>[];
  final List<String> personCleared = <String>[];

  @override
  Future<void> setPersonPlace(int officeId, String userId, {required double latitude, required double longitude, double? accuracy, int? radiusM}) async {
    personPlaces.add((userId, latitude, longitude));
  }

  @override
  Future<void> clearPersonPlace(int officeId, String userId) async {
    personCleared.add(userId);
  }

  @override
  Future<void> clockIn({String? staffId}) async => calls.add('plain-in');

  @override
  Future<void> clockOut({String? staffId}) async => calls.add('plain-out');

  final List<String> loaded = <String>[];

  @override
  Future<Map<String, dynamic>> attendancePolicy() async {
    loaded.add('policy');
    return <String, dynamic>{'enabled': policyOn};
  }

  @override
  Future<void> saveAttendancePolicy({required bool enabled, String? timezone}) async {
    policySaves.add(enabled);
    policyOn = enabled;
  }

  @override
  Future<List<Map<String, dynamic>>> attendanceDevices() async {
    loaded.add('devices');
    return devices;
  }

  @override
  Future<void> decideDevice(int id, String decision, {String? note}) async {
    decisions.add((id, decision));
    devices = <Map<String, dynamic>>[for (final Map<String, dynamic> d in devices) d['id'] == id ? <String, dynamic>{...d, 'status': decision == 'approve' ? 'approved' : decision} : d];
  }

  List<SalonBranchInfo> branchList = <SalonBranchInfo>[];

  @override
  Future<List<SalonBranchInfo>> branches() async => branchList;

  @override
  Future<List<Map<String, dynamic>>> attendanceOffices() async => offices;

  @override
  Future<void> acknowledgeCheck(int id) async {
    acknowledged.add(id);
    checkRows = <Map<String, dynamic>>[for (final Map<String, dynamic> c in checkRows) c['flagged'] == true ? <String, dynamic>{...c, 'acknowledged': true} : c];
  }

  @override
  Future<List<Map<String, dynamic>>> attendanceChecks({String? outcome}) async {
    loaded.add('checks');
    return checkRows;
  }

  List<Map<String, dynamic>> checkRows = <Map<String, dynamic>>[
        <String, dynamic>{'id': 1, 'user_name': 'Asha', 'purpose': 'in', 'outcome': 'device_mismatch', 'at': '2026-11-09 09:00:00', 'ip': '1.2.3.4', 'office_id': 3},
        <String, dynamic>{'id': 2, 'user_name': 'Asha', 'purpose': 'in', 'outcome': 'ok', 'at': '2026-11-09 09:05:00', 'office_id': 3, 'place_status': 'away', 'distance_m': 1112.0},
  ];

  @override
  Future<void> saveAttendanceOffice({int? id, int? branchId, required String name, String? address, double? latitude, double? longitude, double? accuracy, int radiusM = 150, bool geofenceRequired = false, bool active = true}) async {
    officeSaves.add(<String, dynamic>{'id': id, 'branch': branchId, 'name': name, 'fence': geofenceRequired, 'lat': latitude});
  }

  @override
  Future<void> setOfficeStaff(int officeId, List<String> userIds) async {
    calls.add('staff:$officeId:${userIds.join(',')}');
  }
}

class _Server extends ApiService {}

class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 'u1', name: 'Someone', email: 's@example.test', role: role, isActive: true, serviceTypes: const <String>['salon']);

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

Future<void> _host(WidgetTester t, Widget screen, {String role = 'hair_stylist', bool sw = false}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final InventoryProvider inv = InventoryProvider(api: _Server());
  addTearDown(inv.dispose);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(411, 2000), minTextAdapt: true, builder: (_, __) => MaterialApp(home: Scaffold(body: screen))),
    ),
  );
  await _settle(t);
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  group('starting work from my device', () {
    testWidgets('with checks on and the device approved, Start work signs the challenge and sends the place', (t) async {
      final _Fake api = _Fake()..status = 'approved';
      final _Identity id = _Identity();
      await _host(t, AttendanceScreen(api: api, identity: id));

      expect(find.text('Approved'), findsOneWidget);
      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(api.calls, <String>['challenge:in:3']); // the only office is chosen without asking
      expect(id.signed, <String>['P|in|3']);
      expect(api.verified.single, <String, dynamic>{'id': 77, 'sig': 'SIG(P|in|3)', 'lat': -6.8, 'lng': 39.27, 'mocked': false});
      expect(api.calls.contains('plain-in'), isFalse);
      expect(_key('clock_out'), findsOneWidget);
    });

    testWidgets('finishing work needs no office', (t) async {
      final _Fake api = _Fake()
        ..status = 'approved'
        ..atWork = true;
      await _host(t, AttendanceScreen(api: api, identity: _Identity()));

      await t.tap(_key('clock_out'));
      await _settle(t);

      expect(api.calls, <String>['challenge:out:null']);
      expect(_key('clock_in'), findsOneWidget);
    });

    testWidgets('with several offices the person picks one, shown with its number', (t) async {
      final _Fake api = _Fake()
        ..status = 'approved'
        ..offices = <Map<String, dynamic>>[
          <String, dynamic>{'id': 3, 'name': 'Kariakoo'},
          <String, dynamic>{'id': 8, 'name': 'Kariakoo'},
        ];
      await _host(t, AttendanceScreen(api: api, identity: _Identity()));

      await t.tap(_key('clock_in'));
      await _settle(t);
      expect(find.text('Kariakoo · #3'), findsOneWidget);
      expect(find.text('Kariakoo · #8'), findsOneWidget);
      await t.tap(_key('office_8'));
      await _settle(t);

      expect(api.calls, <String>['challenge:in:8']);
    });

    testWidgets('a phone that is not approved starts nothing and says why', (t) async {
      final _Fake api = _Fake()..status = 'pending';
      await _host(t, AttendanceScreen(api: api, identity: _Identity()));

      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(api.calls, isEmpty);
      expect(api.verified, isEmpty);
      expect(find.text('Your device is waiting for an administrator to approve it.'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('a phone never registered can ask to be, once, and then waits', (t) async {
      final _Fake api = _Fake();
      await _host(t, AttendanceScreen(api: api, identity: _Identity()));

      expect(find.text('No phone registered'), findsOneWidget);
      await t.tap(_key('register_device'));
      await _settle(t);
      // what is collected is told first, and nothing is sent until the person agrees
      expect(_key('device_consent'), findsOneWidget);
      expect(api.calls, isEmpty);
      await t.tap(_key('consent_agree'));
      await _settle(t);

      expect(api.calls, <String>['enroll:phone-uuid-000000001:PUBLIC']);
      expect(find.text('Waiting for approval'), findsOneWidget);
      expect(_key('register_device'), findsNothing);
    });

    testWidgets('declining the agreement registers nothing and leaves the way open to agree later', (t) async {
      final _Fake api = _Fake();
      await _host(t, AttendanceScreen(api: api, identity: _Identity()));

      await t.tap(_key('register_device'));
      await _settle(t);
      expect(find.textContaining('IP'), findsWidgets);
      expect(find.textContaining('IMEI'), findsOneWidget);
      await t.tap(_key('consent_decline'));
      await _settle(t);

      expect(api.calls, isEmpty);
      expect(_key('device_consent'), findsNothing);
      expect(_key('register_device'), findsOneWidget);
    });

    testWidgets('the agreement is told in Swahili too', (t) async {
      await _host(t, AttendanceScreen(api: _Fake(), identity: _Identity()), sw: true);

      await t.tap(_key('register_device'));
      await _settle(t);

      expect(find.text('Sajili simu hii kwa mahudhurio'), findsOneWidget);
      expect(find.text('Nakubali'), findsOneWidget);
      expect(find.text('Sikubali'), findsOneWidget);
    });

    testWidgets('the phone name travels with each request, so a different phone can be told apart in the log', (t) async {
      final _Fake api = _Fake()..status = 'approved';
      await _host(t, AttendanceScreen(api: api, identity: _Identity()));

      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(api.names, <String?>['Tecno Spark']);
    });

    testWidgets('a refusal from the server is shown in its words and nothing is recorded', (t) async {
      final _Fake api = _Fake()
        ..status = 'approved'
        ..refuse = ApiException('Simu hii si ile uliyosajili. / This is not the phone you registered.');
      await _host(t, AttendanceScreen(api: api, identity: _Identity()));

      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(find.text('This is not the phone you registered.'), findsOneWidget);
      expect(api.verified, isEmpty);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('with checks off the plain tap still works and no device card shows', (t) async {
      final _Fake api = _Fake()..policyOn = false;
      await _host(t, AttendanceScreen(api: api, identity: _Identity()));

      expect(_key('my_device_card'), findsNothing);
      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(api.calls, <String>['plain-in']);
    });

    testWidgets('starting work says how far from the office you are and that you are at work', (t) async {
      final _Fake api = _Fake()
        ..status = 'approved'
        ..placeAnswer = <String, dynamic>{'status': 'at_work', 'distance_m': 35.2, 'radius_m': 150, 'reference': 'office'};
      await _host(t, AttendanceScreen(api: api, identity: _Identity()));

      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(find.text('Work started. You are at work: 35 m from the office (150 m allowed).'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('being away is told with the distance, not hidden', (t) async {
      final _Fake api = _Fake()
        ..status = 'approved'
        ..placeAnswer = <String, dynamic>{'status': 'away', 'distance_m': 1112.0, 'radius_m': 150, 'reference': 'person'};
      await _host(t, AttendanceScreen(api: api, identity: _Identity()));

      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(find.text('Work started. You are away: 1112 m from your work place (150 m allowed).'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('a fake location the phone reports is sent to the server', (t) async {
      final _Fake api = _Fake()..status = 'approved';
      final _Identity id = _Identity()..where = const PhonePlace(latitude: -6.8, longitude: 39.27, accuracy: 5, mocked: true);
      await _host(t, AttendanceScreen(api: api, identity: id));

      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(api.verified.single['mocked'], isTrue);
    });

    testWidgets('only someone with the right sees the way into devices and offices', (t) async {
      await _host(t, AttendanceScreen(api: _Fake()..status = 'approved', identity: _Identity()));
      expect(_key('open_devices_admin'), findsNothing);
    });
  });

  group('devices and offices (administrator)', () {
    Map<String, dynamic> device(int id, String status) => <String, dynamic>{'id': id, 'user_name': 'Asha', 'status': status, 'manufacturer': 'Tecno', 'model': 'Spark', 'os_name': 'Android', 'os_version': '13', 'requested_at': '2026-11-08 10:00'};

    testWidgets('a waiting phone is approved, and the list shows it approved', (t) async {
      final _Fake api = _Fake()..devices = <Map<String, dynamic>>[device(5, 'pending')];
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), staff: const <Map<String, String>>[]), role: 'admin');

      expect(find.text('Pending'), findsOneWidget);
      await t.tap(_key('device_approve_5'));
      await _settle(t);

      expect(api.decisions, <(int, String)>[(5, 'approve')]);
      expect(find.text('Approved'), findsOneWidget);
      expect(_key('device_reset_5'), findsOneWidget);
    });

    testWidgets('a replaced phone stays in the list with no actions', (t) async {
      final _Fake api = _Fake()..devices = <Map<String, dynamic>>[device(6, 'replaced')];
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), staff: const <Map<String, String>>[]), role: 'admin');

      expect(find.text('Replaced'), findsOneWidget);
      expect(_key('device_block_6'), findsNothing);
    });

    testWidgets('the switch turns device checks on or off', (t) async {
      final _Fake api = _Fake()..policyOn = false;
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), staff: const <Map<String, String>>[]), role: 'admin');

      await t.tap(_key('policy_switch'));
      await _settle(t);

      expect(api.policySaves, <bool>[true]);
    });

    testWidgets('an office is added with its place and the people who work there', (t) async {
      final _Fake api = _Fake()..offices = <Map<String, dynamic>>[<String, dynamic>{'id': 4, 'name': 'Old', 'staff_ids': <String>[]}];
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), staff: const <Map<String, String>>[<String, String>{'id': '9', 'name': 'Asha'}]), role: 'admin');

      await t.tap(_key('tab_offices'));
      await _settle(t);
      expect(find.text('Old · #4'), findsOneWidget);
      await t.tap(_key('add_office'));
      await _settle(t);
      await t.enterText(_key('office_name'), 'Mbezi');
      await t.tap(_key('office_staff_9'));
      await t.pump();
      await t.tap(_key('office_save'));
      await _settle(t);

      expect(api.officeSaves.single, <String, dynamic>{'id': null, 'branch': null, 'name': 'Mbezi', 'fence': false, 'lat': -6.8});
      expect(api.calls.single, 'staff:4:9'); // the newest office number in the fake list
    });

    testWidgets('an office can be a branch: choosing one fills its name and address and sends the branch', (t) async {
      final _Fake api = _Fake()
        ..offices = <Map<String, dynamic>>[]
        ..branchList = const <SalonBranchInfo>[SalonBranchInfo(id: 12, name: 'Kariakoo', address: 'Mtaa wa Kongo')];
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), staff: const <Map<String, String>>[]), role: 'admin');

      await t.tap(_key('tab_offices'));
      await _settle(t);
      await t.tap(_key('add_office'));
      await _settle(t);
      await t.tap(_key('office_branch'));
      await _settle(t);
      await t.tap(find.text('Kariakoo').last);
      await _settle(t);
      await t.tap(_key('office_save'));
      await _settle(t);

      expect(api.officeSaves.single['branch'], 12);
    });

    testWidgets('saving an office with no name, or a required place with no coordinates, is told in the form and sends nothing', (t) async {
      final _Fake api = _Fake()..offices = <Map<String, dynamic>>[];
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity()..where = null, staff: const <Map<String, String>>[]), role: 'admin');

      await t.tap(_key('tab_offices'));
      await _settle(t);
      await t.tap(_key('add_office'));
      await _settle(t);
      expect(find.textContaining('could not find where it is'), findsOneWidget);
      await t.tap(_key('office_save'));
      await _settle(t);
      expect(find.text('Enter the office name, or choose a branch.'), findsOneWidget);

      await t.enterText(_key('office_name'), 'Mbezi');
      await t.tap(_key('office_fence'));
      await t.pump();
      await t.tap(_key('office_save'));
      await _settle(t);
      expect(find.textContaining('Capture the place of the office'), findsOneWidget);
      expect(api.officeSaves, isEmpty);
    });

    testWidgets('a new office takes its place from the phone by itself, shows how exact it is, and the boxes cannot be typed in', (t) async {
      final _Fake api = _Fake()..offices = <Map<String, dynamic>>[];
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), staff: const <Map<String, String>>[]), role: 'admin');

      await t.tap(_key('tab_offices'));
      await _settle(t);
      await t.tap(_key('add_office'));
      await _settle(t);

      expect(find.text('-6.8000000'), findsOneWidget);
      expect(find.text('39.2700000'), findsOneWidget);
      expect(find.text('Place captured (± 10 m)'), findsOneWidget);
      expect(t.widget<TextField>(_key('office_lat')).readOnly, isTrue);

      await t.enterText(_key('office_name'), 'Mbezi');
      await t.tap(_key('office_fence'));
      await t.pump();
      await t.tap(_key('office_save'));
      await _settle(t);

      expect(api.officeSaves.single['fence'], isTrue);
      expect(api.officeSaves.single['lat'], -6.8);
    });

    testWidgets('the administrator captures the place for one person, and can take it back', (t) async {
      final _Fake api = _Fake()
        ..offices = <Map<String, dynamic>>[
          <String, dynamic>{'id': 4, 'name': 'Old', 'staff_ids': <String>['9'], 'staff_places': <String, dynamic>{}},
        ];
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), staff: const <Map<String, String>>[<String, String>{'id': '9', 'name': 'Asha'}]), role: 'admin');

      await t.tap(_key('tab_offices'));
      await _settle(t);
      await t.tap(_key('office_row_4'));
      await _settle(t);
      await t.tap(_key('person_capture_9'));
      await _settle(t);

      expect(api.personPlaces, <(String, double, double)>[('9', -6.8, 39.27)]);
      expect(find.text('Has a place of their own'), findsOneWidget);
      await t.tap(_key('person_clear_9'));
      await _settle(t);
      expect(api.personCleared, <String>['9']);
      expect(find.text('Has a place of their own'), findsNothing);
    });

    testWidgets('the log shows the distance and the verdict of each start', (t) async {
      final _Fake api = _Fake();
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), staff: const <Map<String, String>>[]), role: 'admin');

      await t.tap(_key('tab_log'));
      await _settle(t);

      expect(find.text('Away • 1112 m'), findsOneWidget);
    });

    testWidgets('each right opens only its own part: offices only means no phones, no log and no on/off switch', (t) async {
      final _Fake api = _Fake()..offices = <Map<String, dynamic>>[];
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), rights: const <String>{'inv_salon_offices'}, staff: const <Map<String, String>>[]), role: 'admin');

      expect(_key('tab_offices'), findsOneWidget);
      expect(_key('tab_devices'), findsNothing);
      expect(_key('tab_log'), findsNothing);
      expect(_key('policy_switch'), findsNothing);
      expect(api.loaded, isEmpty); // nothing the server would refuse was even asked for
    });

    testWidgets('the on/off right alone shows just the switch', (t) async {
      final _Fake api = _Fake();
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), rights: const <String>{'inv_salon_attendance_policy'}, staff: const <Map<String, String>>[]), role: 'admin');

      expect(_key('policy_switch'), findsOneWidget);
      expect(_key('tab_offices'), findsNothing);
      expect(api.loaded, <String>['policy']);
    });

    testWidgets('someone with none of the four sees nothing to open', (t) async {
      await _host(t, AttendanceScreen(api: _Fake()..status = 'approved', identity: _Identity()), role: 'hair_stylist');
      expect(_key('open_devices_admin'), findsNothing);
    });

    testWidgets('a phone that is not the registered one shows as "Not the logged-in device" with both ids, and can be marked seen', (t) async {
      final _Fake api = _Fake()
        ..checkRows = <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 9, 'user_name': 'Asha', 'purpose': 'in', 'outcome': 'device_mismatch', 'at': '2026-11-09 09:00:00', 'ip': '41.59.1.2', 'office_id': 3,
            'flagged': true, 'acknowledged': false, 'registered_device_uuid': 'registered-uuid-0001', 'presented_device_uuid': 'other-phone-uuid-0002', 'presented_device_name': 'Samsung A14',
          },
        ];
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), staff: const <Map<String, String>>[]), role: 'admin');

      await t.tap(_key('tab_log'));
      await _settle(t);

      expect(find.text('Not the logged-in device'), findsOneWidget);
      expect((t.widget(_key('check_devices_9')) as Text).data, 'Registered: register…  •  Used: other-ph… (Samsung A14)');
      await t.tap(_key('check_ack_9'));
      await _settle(t);

      expect(api.acknowledged, <int>[9]);
      expect(_key('check_ack_9'), findsNothing);
      expect(_key('check_devices_9'), findsOneWidget); // the line stays: it is a record
    });

    testWidgets('the same in Swahili', (t) async {
      final _Fake api = _Fake()
        ..checkRows = <Map<String, dynamic>>[
          <String, dynamic>{'id': 9, 'user_name': 'Asha', 'purpose': 'in', 'outcome': 'device_mismatch', 'at': '2026-11-09 09:00:00', 'flagged': true, 'registered_device_uuid': 'a', 'presented_device_uuid': 'b'},
        ];
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), staff: const <Map<String, String>>[]), role: 'admin', sw: true);

      await t.tap(_key('tab_log'));
      await _settle(t);

      expect(find.text('Si kifaa alichoingia nacho'), findsOneWidget);
      expect(find.text('Nimeona'), findsOneWidget);
      expect((t.widget(_key('check_devices_9')) as Text).data, 'Kilichosajiliwa: a  •  Kilichotumika: b');
    });

    testWidgets('the log shows what was refused', (t) async {
      final _Fake api = _Fake();
      await _host(t, DevicesAdminScreen(api: api, identity: _Identity(), staff: const <Map<String, String>>[]), role: 'admin');

      await t.tap(_key('tab_log'));
      await _settle(t);

      expect(find.text('device_mismatch'), findsOneWidget);
    });
  });

  group('what the place says, in words', () {
    test('English and Swahili, with the distance and the allowed radius', () {
      const PlaceResult near = PlaceResult(status: 'at_work', distanceM: 35.2, radiusM: 150, reference: 'office');
      expect(placeSentence(sw: false, p: near), 'You are at work: 35 m from the office (150 m allowed).');
      expect(placeSentence(sw: true, p: near), 'Uko kazini: 35 m kutoka ofisi (ruhusa 150 m).');
      expect(placeSentence(sw: true, p: const PlaceResult(status: 'away', distanceM: 900, radiusM: 100, reference: 'person')), 'Uko mbali: 900 m kutoka mahali pako pa kazi (ruhusa 100 m).');
      expect(placeSentence(sw: false, p: const PlaceResult(status: 'mocked')), 'A fake location was detected.');
      expect(placeSentence(sw: false, p: const PlaceResult(status: 'no_location')), 'Your place could not be found (is location off?).');
    });
  });

  group('the key', () {
    test('a signature is written as the DER sequence the server reads', () {
      final bytes = derSignature(BigInt.from(1), BigInt.from(0x80));

      // 30 len | 02 01 01 | 02 02 00 80 (a high first bit gets a zero in front)
      expect(bytes, <int>[0x30, 0x07, 0x02, 0x01, 0x01, 0x02, 0x02, 0x00, 0x80]);
    });
  });
}
