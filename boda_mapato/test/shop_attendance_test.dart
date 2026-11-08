import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/notifications_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/inventory_home.dart';
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

/// Start work from one's own approved phone in a SHOP or DEPOT: every person on the staff has "Attendance" in the menu, and the
/// owner's and managers' set-up (phones, offices and places, the log, the switch) is there for whoever holds each of the four rights.
class _Identity implements DeviceIdentity {
  final List<String> signed = <String>[];

  @override
  Future<DeviceFacts> facts() async => const DeviceFacts(uuid: 'shop-phone-uuid-0001', publicKey: 'PUBLIC', name: 'Tecno Spark', manufacturer: 'Tecno', model: 'Spark', osName: 'Android', osVersion: '13', appVersion: '1.0.0+73');

  @override
  Future<String> uuid() async => 'shop-phone-uuid-0001';

  @override
  Future<String> sign(String payload) async {
    signed.add(payload);

    return 'SIG($payload)';
  }

  @override
  Future<PhonePlace?> place() async => const PhonePlace(latitude: -6.8, longitude: 39.27, accuracy: 10);
}

class _Fake extends SalonApi {
  bool policyOn = false;
  String? status;
  bool atWork = false;
  final List<String> calls = <String>[];
  final List<String> loaded = <String>[];

  @override
  Future<AttendanceNow> attendanceToday() async => AttendanceNow(atWork: atWork, since: atWork ? DateTime(2026, 11, 9, 9) : null);

  @override
  Future<List<AttendancePerson>> attendance(String month) async => <AttendancePerson>[];

  @override
  Future<Map<String, dynamic>> myDevice() async => <String, dynamic>{
        'policy_on': policyOn,
        'device': status == null ? null : <String, dynamic>{'status': status, 'device_uuid': 'shop-phone-uuid-0001', 'name': 'Tecno Spark'},
        'offices': <Map<String, dynamic>>[
          <String, dynamic>{'id': 4, 'name': 'Dukani'},
        ],
      };

  @override
  Future<Map<String, dynamic>> enrollDevice({required String uuid, required String publicKey, String? platform, String? name, String? manufacturer, String? model, String? osName, String? osVersion, String? appVersion}) async {
    calls.add('enroll:$uuid');
    status = 'pending';

    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> attendanceChallenge({required String deviceUuid, required String purpose, int? officeId, String? deviceName}) async {
    calls.add('challenge:$purpose:$officeId');

    return <String, dynamic>{'challenge_id': 5, 'payload': 'P|$purpose|${officeId ?? 0}'};
  }

  @override
  Future<Map<String, dynamic>> attendanceVerify({required int challengeId, required String signature, double? latitude, double? longitude, double? accuracy, DateTime? locationAt, bool mocked = false}) async {
    calls.add('verify:$challengeId');
    atWork = !atWork;

    return <String, dynamic>{
      'place': <String, dynamic>{'status': 'at_work', 'distance_m': 20.0, 'radius_m': 150, 'reference': 'office'},
    };
  }

  @override
  Future<void> clockIn({String? staffId}) async {
    calls.add('plain-in');
    atWork = true;
  }

  @override
  Future<void> clockOut({String? staffId}) async => calls.add('plain-out');

  @override
  Future<Map<String, dynamic>> attendancePolicy() async {
    loaded.add('policy');

    return <String, dynamic>{'enabled': policyOn};
  }

  @override
  Future<List<Map<String, dynamic>>> attendanceDevices() async {
    loaded.add('devices');

    return <Map<String, dynamic>>[];
  }

  @override
  Future<List<Map<String, dynamic>>> attendanceOffices() async {
    loaded.add('offices');

    return <Map<String, dynamic>>[];
  }

  @override
  Future<List<Map<String, dynamic>>> attendanceChecks({String? outcome}) async {
    loaded.add('checks');

    return <Map<String, dynamic>>[];
  }

  @override
  Future<List<SalonBranchInfo>> branches() async => <SalonBranchInfo>[];
}

class _Server extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{
        'data': <String, dynamic>{'inventory_type': 'retail', 'use_crates': '0', 'sale_tier': 'retail', 'depot_name': 'Duka'},
      };
    }

    return null;
  }

  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async => throw ApiException('offline');
}

/// A shop worker of [role]; [rights], when given, is the list the server worked out for them (the owner's additions and take-backs included).
class _Auth extends AuthProvider {
  _Auth(this.role, [this.rights]);

  final String role;
  final List<String>? rights;

  @override
  UserData? get user => UserData(
        id: 'u1',
        name: 'Juma',
        email: 'j@example.test',
        role: role,
        isActive: true,
        serviceTypes: const <String>['inventory'],
        permissions: rights,
        permissionsResolved: rights != null,
      );

  @override
  UserPermissions get permissions => rights != null ? UserPermissions.fromEffective(userRole: role, permissions: rights!) : UserPermissions.fromRole(role);
}

Future<void> _host(WidgetTester t, Widget screen, {required AuthProvider auth, bool sw = false}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Server server = _Server();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>(create: (_) => InventoryProvider(api: server)),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider(api: server)),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(411, 1400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: screen)),
    ),
  );
  await _settle(t);
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  group('the shop menu', () {
    for (final String role in <String>['admin', 'manager', 'sales_officer', 'operator', 'accountant', 'viewer']) {
      testWidgets('a $role has Attendance among the sections', (t) async {
        await _host(t, const InventoryHome(), auth: _Auth(role));
        await t.tap(find.descendant(of: find.byType(InventoryFooter), matching: find.byIcon(Icons.grid_view_rounded)));
        await _settle(t);

        expect(find.text('Attendance'), findsOneWidget);
      });
    }

    testWidgets('and it is told in Swahili too', (t) async {
      await _host(t, const InventoryHome(), auth: _Auth('sales_officer'), sw: true);
      await t.tap(find.descendant(of: find.byType(InventoryFooter), matching: find.byIcon(Icons.grid_view_rounded)));
      await _settle(t);

      expect(find.text('Mahudhurio'), findsOneWidget);
    });
  });

  group('starting work in a shop', () {
    testWidgets('with the switch off the cashier starts and finishes the plain way, and sees no admin button', (t) async {
      final _Fake api = _Fake();
      await _host(t, ShopAttendancePage(api: api, identity: _Identity()), auth: _Auth('sales_officer'));

      expect(_key('open_devices_admin'), findsNothing);
      expect(_key('clock_someone_in'), findsNothing);
      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(api.calls, <String>['plain-in']);
      expect(_key('clock_out'), findsOneWidget);
    });

    testWidgets('with the switch on and the phone approved, even a viewer starts work with the phone\'s signature and is told the distance', (t) async {
      final _Fake api = _Fake()
        ..policyOn = true
        ..status = 'approved';
      final _Identity id = _Identity();
      await _host(t, ShopAttendancePage(api: api, identity: id), auth: _Auth('viewer'));

      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(api.calls, <String>['challenge:in:4', 'verify:5']); // the only office is chosen without asking
      expect(id.signed, <String>['P|in|4']);
      expect(find.textContaining('You are at work: 20 m from the office (150 m allowed)'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('a phone is registered only after the agreement, in a shop too', (t) async {
      final _Fake api = _Fake()..policyOn = true;
      await _host(t, ShopAttendancePage(api: api, identity: _Identity()), auth: _Auth('operator'));

      await t.tap(_key('register_device'));
      await _settle(t);
      expect(_key('device_consent'), findsOneWidget);
      expect(api.calls, isEmpty);
      await t.tap(_key('consent_decline'));
      await _settle(t);
      expect(api.calls, isEmpty);

      await t.tap(_key('register_device'));
      await _settle(t);
      await t.tap(_key('consent_agree'));
      await _settle(t);

      expect(api.calls, <String>['enroll:shop-phone-uuid-0001']);
      expect(find.text('Waiting for approval'), findsOneWidget);
    });
  });

  group('the business admin controls the staff and does not start work', () {
    testWidgets('the owner has no Start work and no phone card, only the note and what the staff did', (t) async {
      final _Fake api = _Fake()
        ..policyOn = true
        ..status = 'approved';
      await _host(t, ShopAttendancePage(api: api, identity: _Identity()), auth: _Auth('admin'));

      expect(_key('clock_in'), findsNothing);
      expect(_key('clock_out'), findsNothing);
      expect(_key('attendance_status'), findsNothing);
      expect(_key('register_device'), findsNothing);
      expect(_key('owner_attendance_note'), findsOneWidget);
      expect(find.text('Start work'), findsNothing);
      // the month and the way into phones and offices stay
      expect(_key('attendance_month'), findsOneWidget);
      expect(_key('open_devices_admin'), findsOneWidget);
    });

    testWidgets('and says so in Swahili', (t) async {
      await _host(t, ShopAttendancePage(api: _Fake(), identity: _Identity()), auth: _Auth('admin'), sw: true);

      expect(find.textContaining('Wafanyakazi wanaanza kazi wenyewe'), findsOneWidget);
      expect(find.text('Anza kazi'), findsNothing);
    });

    testWidgets('a staff member, a manager included, still has Start work', (t) async {
      for (final String role in <String>['sales_officer', 'manager']) {
        await _host(t, ShopAttendancePage(api: _Fake(), identity: _Identity()), auth: _Auth(role));
        expect(_key('clock_in'), findsOneWidget, reason: role);
        expect(_key('owner_attendance_note'), findsNothing, reason: role);
      }
    });
  });

  group('the owner\'s and managers\' set-up in a shop', () {
    testWidgets('the owner gets the button and all four parts, and no way to start someone else\'s day', (t) async {
      final _Fake api = _Fake();
      await _host(t, ShopAttendancePage(api: api, identity: _Identity()), auth: _Auth('admin'));

      expect(_key('clock_someone_in'), findsNothing);
      await t.tap(_key('open_devices_admin'));
      await _settle(t);

      for (final String k in <String>['tab_devices', 'tab_offices', 'tab_log', 'policy_switch']) {
        expect(_key(k), findsOneWidget, reason: k);
      }
      expect(api.loaded.toSet(), <String>{'policy', 'devices', 'offices', 'checks'});
    });

    testWidgets('a cashier the owner gave only the phones right sees only the phones, and the app asks the server for nothing else', (t) async {
      final _Fake api = _Fake();
      await _host(
        t,
        ShopAttendancePage(api: api, identity: _Identity()),
        auth: _Auth('sales_officer', const <String>['inv_view_products', 'inv_create_sales', 'inv_salon_devices']),
      );

      await t.tap(_key('open_devices_admin'));
      await _settle(t);

      expect(_key('tab_devices'), findsOneWidget);
      expect(_key('tab_offices'), findsNothing);
      expect(_key('tab_log'), findsNothing);
      expect(_key('policy_switch'), findsNothing);
      expect(api.loaded, <String>['devices']);
    });

    testWidgets('a manager has none of the four until the owner turns them on', (t) async {
      final _Fake api = _Fake();
      await _host(t, ShopAttendancePage(api: api, identity: _Identity()), auth: _Auth('manager'));

      expect(_key('open_devices_admin'), findsNothing);
      expect(api.loaded, isEmpty);
    });

    testWidgets('a manager the owner took the log from keeps the rest', (t) async {
      final _Fake api = _Fake();
      await _host(
        t,
        ShopAttendancePage(api: api, identity: _Identity()),
        auth: _Auth('manager', const <String>['inv_view_reports', 'inv_salon_devices', 'inv_salon_offices', 'inv_salon_attendance_policy']),
      );

      await t.tap(_key('open_devices_admin'));
      await _settle(t);

      expect(_key('tab_log'), findsNothing);
      expect(_key('tab_devices'), findsOneWidget);
      expect(_key('tab_offices'), findsOneWidget);
    });
  });
}
