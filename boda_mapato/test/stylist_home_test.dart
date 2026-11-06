import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/stylist_home_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stylist's own day on one page: the diary and the queue, what they earned and their target, at work or not, and days off.
class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 's1', name: 'Asha', email: 'a@example.test', role: role, isActive: true, serviceTypes: const <String>['salon']);
}

class _Salon extends SalonApi {
  final List<String> calls = <String>[];
  bool atWork = false;
  List<DayOffRequest> requests = <DayOffRequest>[];
  List<Map<String, dynamic>> queueRows = <Map<String, dynamic>>[
    <String, dynamic>{'id': 4, 'name': 'Zawadi', 'status': 'waiting'},
  ];
  String apptStatus = 'booked';

  StylistRow row(double revenue) => StylistRow(
        staffId: 's1',
        name: 'Asha',
        services: 2,
        revenue: revenue,
        visits: 2,
        clients: 2,
        commission: revenue / 10,
        target: const StylistTarget(month: '2026-11', amount: 500000, achieved: 150000, percent: 30, expectedPercent: 40, pace: 'behind'),
      );

  @override
  Future<StylistReport> stylists({DateTime? from, DateTime? to}) async => StylistReport(from: from ?? DateTime(2026), to: to ?? DateTime(2026), stylists: <StylistRow>[row(from == to ? 30000 : 150000)], services: 2, revenue: 1, visits: 2);

  @override
  Future<List<SalonAppointment>> appointments(DateTime day) async => <SalonAppointment>[
        SalonAppointment(id: 11, clientName: 'Neema', startsAt: DateTime(2026, 11, 6, 10, 30), endsAt: DateTime(2026, 11, 6, 12), status: apptStatus, services: const <AppointmentService>[AppointmentService(productId: 1, name: 'Box Braids', price: 60000)], total: 60000),
      ];

  @override
  Future<SalonAppointment> setAppointmentStatus(int id, String status) async {
    calls.add('status:$id:$status');
    apptStatus = status;

    return (await appointments(DateTime(2026, 11, 6))).first;
  }

  @override
  Future<Map<String, dynamic>> queue() async => <String, dynamic>{'queue': queueRows};

  @override
  Future<void> setQueueStatus(int id, String status) async {
    calls.add('queue:$id:$status');
    queueRows = <Map<String, dynamic>>[<String, dynamic>{'id': id, 'name': 'Zawadi', 'status': status}];
  }

  @override
  Future<AttendanceNow> attendanceToday() async => AttendanceNow(atWork: atWork, since: atWork ? DateTime(2026, 11, 6, 8, 5) : null);

  @override
  Future<void> clockIn({String? staffId}) async {
    calls.add('clockin');
    atWork = true;
  }

  @override
  Future<void> clockOut({String? staffId}) async {
    calls.add('clockout');
    atWork = false;
  }

  @override
  Future<(bool, List<DayOffRequest>)> dayOffRequests() async => (false, requests);

  @override
  Future<void> requestDayOff(DateTime day, {String? reason}) async {
    calls.add('dayoff:${day.day}:${reason ?? ''}');
    requests = <DayOffRequest>[DayOffRequest(id: 1, staffId: 's1', offOn: day, status: 'pending', reason: reason)];
  }
}

Future<_Salon> _open(WidgetTester t, {String role = 'hair_stylist', bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Salon api = _Salon();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(411, 1800), minTextAdapt: true, builder: (_, __) => MaterialApp(home: Scaffold(body: StylistHomeScreen(api: api, today: DateTime(2026, 11, 6))))),
    ),
  );
  for (int i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }

  return api;
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets("shows the stylist's own day: what they earned (with commission), the target, the diary and the queue", (t) async {
    await _open(t);

    expect(find.text('My day, Asha'), findsOneWidget);
    expect(find.descendant(of: _key('stylist_today'), matching: find.text('TSH 30,000')), findsOneWidget);
    expect(find.descendant(of: _key('stylist_month'), matching: find.text('TSH 150,000')), findsOneWidget);
    expect(find.descendant(of: _key('stylist_today'), matching: find.text('Commission TSH 3,000')), findsOneWidget);
    expect(_key('stylist_target'), findsOneWidget);
    expect(find.text('Behind pace'), findsNothing, reason: 'the target line carries the words');
    expect(find.textContaining('Behind pace'), findsOneWidget);
    expect(find.text('10:30'), findsOneWidget);
    expect(find.text('Neema'), findsOneWidget);
    expect(find.text('Box Braids'), findsOneWidget);
    expect(find.text('Zawadi'), findsOneWidget);
  });

  testWidgets('shows nothing of the salon\'s money, profit or other people\'s pay', (t) async {
    await _open(t);

    for (final String word in <String>['Profit', 'profit', 'Payroll', 'Cashbook', 'Salaries', 'Expenses']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
  });

  testWidgets('start and finish the day, an appointment and a client from the queue, each with one tap', (t) async {
    final _Salon api = await _open(t);

    await t.tap(_key('stylist_clock_in'));
    for (int i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(api.calls, contains('clockin'));
    expect(_key('stylist_clock_out'), findsOneWidget);

    await t.tap(_key('stylist_appt_11_in_progress'));
    for (int i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(api.calls, contains('status:11:in_progress'));
    expect(_key('stylist_appt_11_done'), findsOneWidget);

    await t.tap(_key('stylist_queue_4_serving'));
    for (int i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(api.calls, contains('queue:4:serving'));
    expect(_key('stylist_queue_4_done'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('a day off is asked for with a date and a reason, and shows as waiting', (t) async {
    final _Salon api = await _open(t);

    await t.ensureVisible(_key('stylist_ask_dayoff'));
    await t.tap(_key('stylist_ask_dayoff'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await t.enterText(_key('dayoff_reason'), 'Family');
    await t.tap(_key('dayoff_send'));
    for (int i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }

    expect(api.calls.single, startsWith('dayoff:'));
    expect(api.calls.single, endsWith(':Family'));
    expect(find.text('Waiting'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('the client feedback link is not there unless the owner gave that right (off by default)', (t) async {
    await _open(t);

    expect(_key('stylist_link_attendance'), findsOneWidget);
    expect(_key('stylist_link_feedback'), findsNothing);
  });
}
