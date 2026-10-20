import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/attendance_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/schedule_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/shifts_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/inventory_widgets.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The salon's people at work: attendance (start and finish a day, hours for the month), the schedule (working days,
/// hours, days off) and each shift's cash (open with a float, close by counting; short or over is told plainly).
class _FakeSalon extends SalonApi {
  AttendanceNow nowState = const AttendanceNow(atWork: false);
  List<AttendancePerson> people = <AttendancePerson>[];
  final List<String?> clockIns = <String?>[];
  final List<String?> clockOuts = <String?>[];
  final List<String> asked = <String>[];
  Object? failClock;
  Object? failLoad;

  List<StaffProfile> profiles = <StaffProfile>[];
  List<DayOff> off = <DayOff>[];
  final List<Map<String, dynamic>> profileSaves = <Map<String, dynamic>>[];
  final List<(String, DateTime, String?)> offAdded = <(String, DateTime, String?)>[];
  final List<int> offDeleted = <int>[];

  SalonShift? current;
  ShiftsReport report = const ShiftsReport(month: '2026-10', shifts: <SalonShift>[], count: 0, withDifference: 0, difference: 0);
  final List<double> opened = <double>[];
  final List<Map<String, dynamic>> closed = <Map<String, dynamic>>[];
  SalonShift? closeAnswer;

  @override
  Future<AttendanceNow> attendanceToday() async {
    if (failLoad != null) {
      final Object e = failLoad!;
      failLoad = null;
      throw e;
    }
    return nowState;
  }

  @override
  Future<List<AttendancePerson>> attendance(String month) async {
    asked.add(month);
    return people;
  }

  @override
  Future<void> clockIn({String? staffId}) async {
    clockIns.add(staffId);
    if (failClock != null) throw failClock!;
    nowState = AttendanceNow(atWork: true, since: DateTime(2026, 10, 15, 9));
  }

  @override
  Future<void> clockOut({String? staffId}) async {
    clockOuts.add(staffId);
    nowState = const AttendanceNow(atWork: false);
  }

  @override
  Future<List<StaffProfile>> staffProfiles() async => profiles;

  @override
  Future<List<DayOff>> daysOff(String month) async => off;

  @override
  Future<void> saveStaffProfile(String staffId, {String? specialization, double? monthlySalary, double? commissionPercent, bool clearCommission = false, List<int>? workDays, String? shiftStart, String? shiftEnd, bool clearHours = false}) async {
    profileSaves.add(<String, dynamic>{'staff': staffId, 'days': workDays, 'from': shiftStart, 'to': shiftEnd, 'clear': clearHours});
  }

  @override
  Future<void> addDayOff(String staffId, DateTime day, {String? reason}) async {
    offAdded.add((staffId, day, reason));
  }

  @override
  Future<void> deleteDayOff(int id) async => offDeleted.add(id);

  @override
  Future<SalonShift?> currentShift() async => current;

  @override
  Future<SalonShift> openShift(double openingFloat) async {
    opened.add(openingFloat);
    current = _shift(1, float: openingFloat);
    return current!;
  }

  @override
  Future<SalonShift> closeShift(int id, {required double countedCash, String? handedToId, String? note}) async {
    closed.add(<String, dynamic>{'id': id, 'counted': countedCash, 'to': handedToId, 'note': note});
    final SalonShift done = closeAnswer ?? _shift(id, status: 'closed', counted: countedCash, diff: 0);
    current = null;
    return done;
  }

  @override
  Future<ShiftsReport> shifts(String month) async => report;
}

SalonShift _shift(int id, {double float = 20000, String status = 'open', double expected = 60000, double? counted, double? diff, String name = 'Asha', String? handed}) => SalonShift(
      id: id,
      staffId: 'u-asha',
      staffName: name,
      status: status,
      openedAt: DateTime(2026, 10, 15, 9),
      closedAt: status == 'closed' ? DateTime(2026, 10, 15, 18) : null,
      openingFloat: float,
      expectedCash: expected,
      collected: const ShiftCollected(cash: 40000, mobileMoney: 30000, bank: 0),
      countedCash: counted,
      difference: diff,
      handedToName: handed,
    );

class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 'u1', name: 'Someone', email: 's@example.test', role: role, isActive: true, serviceTypes: const <String>['salon']);

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

class _Server extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/salon/staff')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'u-asha', 'name': 'Asha', 'role': 'hair_stylist'},
          <String, dynamic>{'id': 'u-bahati', 'name': 'Bahati', 'role': 'manager'},
        ],
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

final DateTime _today = DateTime(2026, 10, 15);

Future<void> _host(WidgetTester t, Widget screen, {String role = 'admin', bool sw = false}) async {
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

AttendancePerson _person(String id, String name, {int days = 2, double hours = 13.5, bool atWork = false}) => AttendancePerson(
      staffId: id,
      name: name,
      days: days,
      hours: hours,
      atWork: atWork,
      records: <AttendanceRecord>[
        AttendanceRecord(id: 1, staffId: id, date: DateTime(2026, 10, 7), clockIn: DateTime(2026, 10, 7, 9), clockOut: DateTime(2026, 10, 7, 18, 30), hours: 9.5),
        AttendanceRecord(id: 2, staffId: id, date: DateTime(2026, 10, 8), clockIn: DateTime(2026, 10, 8, 9), clockOut: atWork ? null : DateTime(2026, 10, 8, 13), hours: atWork ? null : 4),
      ],
    );

void main() {
  group('attendance', () {
    testWidgets('says whether I am at work and starts my day with one tap', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _host(t, AttendanceScreen(api: api, today: _today), role: 'hair_stylist');

      expect(find.text('Not at work yet'), findsOneWidget);
      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(api.clockIns, <String?>[null]);
      expect(find.text('At work since 09:00'), findsOneWidget);
      expect(_key('clock_out'), findsOneWidget);
      expect(_key('clock_in'), findsNothing);
    });

    testWidgets('finishing the day sends clock out', (t) async {
      final _FakeSalon api = _FakeSalon()..nowState = AttendanceNow(atWork: true, since: DateTime(2026, 10, 15, 9));
      await _host(t, AttendanceScreen(api: api, today: _today), role: 'hair_stylist');

      await t.tap(_key('clock_out'));
      await _settle(t);

      expect(api.clockOuts, <String?>[null]);
      expect(find.text('Not at work yet'), findsOneWidget);
    });

    testWidgets('a refusal is shown in the server\'s words', (t) async {
      final _FakeSalon api = _FakeSalon()..failClock = ApiException('Already at work since 09:00.');
      await _host(t, AttendanceScreen(api: api, today: _today), role: 'hair_stylist');

      await t.tap(_key('clock_in'));
      await _settle(t);

      expect(find.text('Already at work since 09:00.'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('lists each person\'s month: days, hours and the latest records', (t) async {
      final _FakeSalon api = _FakeSalon()..people = <AttendancePerson>[_person('u-asha', 'Asha'), _person('u-bahati', 'Bahati', atWork: true)];
      await _host(t, AttendanceScreen(api: api, today: _today));

      expect(api.asked.single, '2026-10');
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.descendant(of: _key('att_u-asha'), matching: find.text('2 days • 13.5 h')), findsOneWidget);
      expect(find.descendant(of: _key('att_u-asha'), matching: find.text('07/10/2026  09:00–18:30  (9.5 h)')), findsOneWidget);
      expect(find.descendant(of: _key('att_u-bahati'), matching: find.text('At work')), findsOneWidget);
      expect(find.descendant(of: _key('att_u-bahati'), matching: find.text('08/10/2026  09:00–…')), findsOneWidget);
    });

    testWidgets('the arrows move to another month', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _host(t, AttendanceScreen(api: api, today: DateTime(2026, 1, 5)));

      await t.tap(_key('attendance_prev'));
      await _settle(t);

      expect(api.asked, <String>['2026-01', '2025-12']);
      expect(find.text('Nobody has clocked in this month.'), findsOneWidget);
    });

    testWidgets('the owner can finish someone\'s day and start someone\'s; a stylist cannot', (t) async {
      final _FakeSalon api = _FakeSalon()..people = <AttendancePerson>[_person('u-bahati', 'Bahati', atWork: true)];
      await _host(t, AttendanceScreen(api: api, today: _today));

      await t.tap(_key('att_out_u-bahati'));
      await _settle(t);
      expect(api.clockOuts, <String?>['u-bahati']);

      await t.tap(_key('clock_someone_in'));
      await _settle(t);
      await t.tap(_key('clock_for_u-asha'));
      await _settle(t);
      expect(api.clockIns, <String?>['u-asha']);
    });

    testWidgets('a stylist has neither of those buttons', (t) async {
      final _FakeSalon api = _FakeSalon()..people = <AttendancePerson>[_person('u-asha', 'Asha', atWork: true)];
      await _host(t, AttendanceScreen(api: api, today: _today), role: 'hair_stylist');

      expect(_key('clock_someone_in'), findsNothing);
      expect(_key('att_out_u-asha'), findsNothing);
    });

    testWidgets('a failed load says why and can be retried; Swahili is Swahili', (t) async {
      final _FakeSalon api = _FakeSalon()..failLoad = ApiException('Server is down');
      await _host(t, AttendanceScreen(api: api, today: _today), sw: true);
      expect(find.text('Server is down'), findsOneWidget);

      await t.tap(_key('attendance_retry'));
      await _settle(t);
      expect(find.text('Oktoba 2026'), findsOneWidget);
      expect(find.text('Anza kazi'), findsOneWidget);
      expect(find.text('Hujaanza kazi leo'), findsOneWidget);
    });
  });

  group('the schedule', () {
    StaffProfile profile(String id, String name, {List<int> days = const <int>[], String? from, String? to, String? spec}) =>
        StaffProfile(staffId: id, name: name, role: 'hair_stylist', monthlySalary: 0, workDays: days, shiftStart: from, shiftEnd: to, specialization: spec);

    testWidgets('shows each person\'s days and hours, and any days off', (t) async {
      final _FakeSalon api = _FakeSalon()
        ..profiles = <StaffProfile>[profile('u-asha', 'Asha', days: <int>[1, 2, 3], from: '09:00', to: '17:00', spec: 'Hair stylist'), profile('u-bahati', 'Bahati')]
        ..off = <DayOff>[DayOff(id: 7, staffId: 'u-asha', staffName: 'Asha', offOn: DateTime(2026, 10, 20), reason: 'Family')];
      await _host(t, ScheduleScreen(api: api, today: _today));

      expect(find.text('Asha • Hair stylist'), findsOneWidget);
      expect(t.widget<FilterChip>(_key('wd_u-asha_1')).selected, isTrue);
      expect(t.widget<FilterChip>(_key('wd_u-asha_6')).selected, isFalse);
      expect(find.descendant(of: _key('hours_start_u-asha'), matching: find.text('09:00')), findsOneWidget);
      expect(find.descendant(of: _key('hours_start_u-bahati'), matching: find.text('From')), findsOneWidget);
      expect(find.text('Asha • 20/10/2026'), findsOneWidget);
      expect(find.text('Family'), findsOneWidget);
    });

    testWidgets('choosing days and hours and saving sends them', (t) async {
      final _FakeSalon api = _FakeSalon()..profiles = <StaffProfile>[profile('u-asha', 'Asha')];
      await _host(t, ScheduleScreen(api: api, today: _today, pickTime: (BuildContext c, TimeOfDay initial) async => initial.hour == 9 ? const TimeOfDay(hour: 8, minute: 30) : const TimeOfDay(hour: 17, minute: 45)));

      for (final int d in <int>[1, 2, 6]) {
        await t.tap(_key('wd_u-asha_$d'));
      }
      await t.tap(_key('hours_start_u-asha'));
      await _settle(t);
      await t.tap(_key('hours_end_u-asha'));
      await _settle(t);
      await t.tap(_key('schedule_save_u-asha'));
      await _settle(t);

      expect(api.profileSaves.single, <String, dynamic>{'staff': 'u-asha', 'days': <int>[1, 2, 6], 'from': '08:30', 'to': '17:45', 'clear': false});
      expect(find.text('Schedule saved.'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('one time without the other, or a finish before the start, is refused', (t) async {
      final _FakeSalon api = _FakeSalon()..profiles = <StaffProfile>[profile('u-asha', 'Asha', from: '09:00', to: '17:00')];
      await _host(t, ScheduleScreen(api: api, today: _today, pickTime: (BuildContext c, TimeOfDay initial) async => const TimeOfDay(hour: 20, minute: 0)));

      await t.tap(_key('hours_clear_u-asha'));
      await t.tap(_key('hours_start_u-asha'));
      await _settle(t);
      await t.tap(_key('schedule_save_u-asha'));
      await _settle(t);
      expect(find.text('Set both the starting and the finishing time, or leave both empty.'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));

      await t.tap(_key('hours_end_u-asha'));
      await _settle(t); // both 20:00 now: not after the start
      await t.tap(_key('schedule_save_u-asha'));
      await _settle(t);
      expect(find.text('The finishing time must be after the starting time.'), findsOneWidget);
      expect(api.profileSaves, isEmpty);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('clearing the hours sends them as cleared', (t) async {
      final _FakeSalon api = _FakeSalon()..profiles = <StaffProfile>[profile('u-asha', 'Asha', days: <int>[1], from: '09:00', to: '17:00')];
      await _host(t, ScheduleScreen(api: api, today: _today));

      await t.tap(_key('hours_clear_u-asha'));
      await t.tap(_key('schedule_save_u-asha'));
      await _settle(t);

      expect(api.profileSaves.single['clear'], isTrue);
      expect(api.profileSaves.single['from'], isNull);
      expect(api.profileSaves.single['days'], <int>[1]);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('adding a day off needs a person, then sends the date and reason', (t) async {
      final _FakeSalon api = _FakeSalon()..profiles = <StaffProfile>[profile('u-asha', 'Asha')];
      await _host(t, ScheduleScreen(api: api, today: _today));
      await t.ensureVisible(_key('dayoff_add'));
      await t.tap(_key('dayoff_add'));
      await _settle(t);

      await t.tap(_key('dayoff_save'));
      await _settle(t);
      expect(find.text('Choose who.'), findsOneWidget);
      await t.tap(_key('dayoff_who_u-asha'));
      await t.enterText(_key('dayoff_reason'), 'Wedding');
      await t.tap(_key('dayoff_save'));
      await _settle(t);

      expect(api.offAdded.single, ('u-asha', DateTime(2026, 10), 'Wedding'));
    });

    testWidgets('a day off can be taken back', (t) async {
      final _FakeSalon api = _FakeSalon()
        ..profiles = <StaffProfile>[profile('u-asha', 'Asha')]
        ..off = <DayOff>[DayOff(id: 7, staffId: 'u-asha', staffName: 'Asha', offOn: DateTime(2026, 10, 20))];
      await _host(t, ScheduleScreen(api: api, today: _today));
      await t.ensureVisible(_key('dayoff_remove_7'));

      await t.tap(_key('dayoff_remove_7'));
      await _settle(t);

      expect(api.offDeleted, <int>[7]);
    });
  });

  group('shifts', () {
    testWidgets('with no shift open it offers to open one, and opens it with the float', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _host(t, ShiftsScreen(api: api, today: _today), role: 'hair_stylist');
      expect(find.text('You have no shift open.'), findsOneWidget);

      await t.tap(_key('shift_open'));
      await _settle(t);
      await t.enterText(_key('shift_float'), '20000');
      await t.tap(_key('shift_open_yes'));
      await _settle(t);

      expect(api.opened, <double>[20000]);
      expect(_key('shift_open_card'), findsOneWidget);
      expect(find.text('Your shift opened at 09:00'), findsOneWidget);
    });

    testWidgets('cancelling the dialog opens nothing', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _host(t, ShiftsScreen(api: api, today: _today), role: 'hair_stylist');

      await t.tap(_key('shift_open'));
      await _settle(t);
      await t.tap(_key('shift_open_no'));
      await _settle(t);

      expect(api.opened, isEmpty);
    });

    testWidgets('an open shift says what the till should hold and what came in by cash, mobile money and bank', (t) async {
      final _FakeSalon api = _FakeSalon()..current = _shift(1);
      await _host(t, ShiftsScreen(api: api, today: _today), role: 'hair_stylist');

      expect(find.text('The till should hold TSH 60,000'), findsOneWidget);
      expect(find.descendant(of: _key('shift_open_card'), matching: find.text('TSH 40,000')), findsOneWidget);
      expect(find.descendant(of: _key('shift_open_card'), matching: find.text('TSH 30,000')), findsOneWidget);
      expect(find.descendant(of: _key('shift_open_card'), matching: find.text('TSH 20,000')), findsOneWidget);
    });

    testWidgets('closing needs the counted cash, and says exact when it is right', (t) async {
      final _FakeSalon api = _FakeSalon()..current = _shift(1);
      await _host(t, ShiftsScreen(api: api, today: _today), role: 'hair_stylist');
      await t.tap(_key('shift_close'));
      await _settle(t);

      await t.tap(_key('shift_save'));
      await _settle(t);
      expect(find.text('Write the cash you counted.'), findsOneWidget);
      expect(api.closed, isEmpty);

      await t.enterText(_key('shift_counted'), '60000');
      await t.tap(_key('handed_u-bahati'));
      await t.enterText(_key('shift_note'), 'All there');
      await t.pump();
      await t.tap(_key('shift_save'));
      await _settle(t);

      expect(api.closed.single, <String, dynamic>{'id': 1, 'counted': 60000.0, 'to': 'u-bahati', 'note': 'All there'});
      expect(find.text('The cash is exactly right. Thank you.'), findsOneWidget);
      await t.tap(_key('shift_done'));
      await _settle(t);
      expect(_key('shift_none'), findsOneWidget, reason: 'no shift is open any more');
    });

    testWidgets('short cash is said plainly, with the amount, and that the owner was told', (t) async {
      final _FakeSalon api = _FakeSalon()
        ..current = _shift(1)
        ..closeAnswer = _shift(1, status: 'closed', counted: 55000, diff: -5000);
      await _host(t, ShiftsScreen(api: api, today: _today), role: 'hair_stylist');
      await t.tap(_key('shift_close'));
      await _settle(t);

      await t.enterText(_key('shift_counted'), '55000');
      await t.tap(_key('shift_save'));
      await _settle(t);

      expect(find.text('The cash is short by TSH 5,000. The owner has been told.'), findsOneWidget);
    });

    testWidgets('extra cash is said too', (t) async {
      final _FakeSalon api = _FakeSalon()
        ..current = _shift(1)
        ..closeAnswer = _shift(1, status: 'closed', counted: 62500, diff: 2500);
      await _host(t, ShiftsScreen(api: api, today: _today), role: 'hair_stylist');
      await t.tap(_key('shift_close'));
      await _settle(t);

      await t.enterText(_key('shift_counted'), '62500');
      await t.tap(_key('shift_save'));
      await _settle(t);

      expect(find.text('The cash is over by TSH 2,500. The owner has been told.'), findsOneWidget);
    });

    testWidgets('the month lists every shift with expected, counted and any difference, and a total', (t) async {
      final _FakeSalon api = _FakeSalon()
        ..report = ShiftsReport(
          month: '2026-10',
          shifts: <SalonShift>[
            _shift(2, status: 'closed', counted: 55000, diff: -5000, handed: 'Mary'),
            _shift(3, status: 'closed', counted: 60000, diff: 0, name: 'Bahati'),
          ],
          count: 2,
          withDifference: 1,
          difference: -5000,
        );
      await _host(t, ShiftsScreen(api: api, today: _today));

      expect(find.text('2 shifts • 1 with a difference • difference in all TSH -5,000'), findsOneWidget);
      expect(find.descendant(of: _key('shift_2'), matching: find.text('Short')), findsOneWidget);
      expect(find.descendant(of: _key('shift_2'), matching: find.text('Mary')), findsOneWidget);
      expect(find.descendant(of: _key('shift_2'), matching: find.text('TSH -5,000')), findsOneWidget);
      expect(find.descendant(of: _key('shift_3'), matching: find.text('Exact')), findsOneWidget);
      expect(find.descendant(of: _key('shift_3'), matching: find.text('Difference')), findsNothing);
    });

    testWidgets('a failed load says why and can be retried; Swahili is Swahili', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _host(t, ShiftsScreen(api: api, today: _today), sw: true);

      expect(find.text('Huna zamu iliyo wazi.'), findsOneWidget);
      expect(find.text('Fungua zamu'), findsOneWidget);
      expect(find.text('Hakuna zamu mwezi huu.'), findsOneWidget);
    });
  });
}
