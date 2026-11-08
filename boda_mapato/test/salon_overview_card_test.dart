import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/payment_references_screen.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/salon_overview_card.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The owner's dashboard at a glance: takings and profit for today, the week, the month and the year, the diary, who
/// and what earns most, how the money came in and what clients owe.
class _FakeSalon extends SalonApi {
  _FakeSalon(this.data);

  SalonOverview data;
  final List<String?> referenceAsks = <String?>[];

  @override
  Future<PaymentReferencePage> paymentReferences({final DateTime? from, final DateTime? to, final String? query, final String? channel, final int page = 1}) async {
    referenceAsks.add(channel);

    return const PaymentReferencePage(rows: <PaymentReference>[], count: 0, amount: 0, page: 1, lastPage: 1);
  }
  Object? fail;
  int calls = 0;

  @override
  Future<SalonOverview> overview() async {
    calls++;
    if (fail != null) {
      final Object e = fail!;
      fail = null;
      throw e;
    }
    return data;
  }
}

SalonOverview _overview({double monthProfit = 51000, double outstanding = 20000, List<RankedItem>? staff}) => SalonOverview(
      today: const PeriodFigures(revenue: 0, expenses: 0, netProfit: 0, clients: 0, sales: 0),
      week: const PeriodFigures(revenue: 126000, expenses: 0, netProfit: 80000, clients: 1, sales: 3),
      month: PeriodFigures(revenue: 126000, expenses: 30000, netProfit: monthProfit, clients: 4, sales: 3),
      year: const PeriodFigures(revenue: 900000, expenses: 200000, netProfit: 400000, clients: 30, sales: 40),
      collections: const <Collection>[Collection(method: 'mpesa', amount: 90000), Collection(method: 'cash', amount: 16000)],
      outstanding: outstanding,
      topServices: const <RankedItem>[RankedItem(name: 'Braids', revenue: 72000, times: 1), RankedItem(name: 'Wash', revenue: 38000, times: 2)],
      topStaff: staff ?? const <RankedItem>[RankedItem(name: 'Asha', revenue: 110000), RankedItem(name: '', revenue: 5000)],
      bookingsToday: 2,
      bookingsUpcoming: 5,
    );

class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 'u1', name: 'Someone', email: 's@example.test', role: role, isActive: true, serviceTypes: const <String>['salon']);
}

Future<void> _host(WidgetTester t, SalonApi api, {bool sw = false, String? role}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
        if (role != null) ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
      ],
      child: ScreenUtilInit(designSize: const Size(411, 1800), minTextAdapt: true, builder: (_, __) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SalonOverviewCard(api: api))))),
    ),
  );
  for (int i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('shows takings and profit for each period', (t) async {
    await _host(t, _FakeSalon(_overview()));

    expect(find.text('Business overview'), findsOneWidget);
    expect(find.descendant(of: _key('ov_today'), matching: find.text('TSH 0')), findsOneWidget);
    expect(find.descendant(of: _key('ov_week'), matching: find.text('TSH 126,000')), findsOneWidget);
    expect(find.descendant(of: _key('ov_week'), matching: find.text('Profit TSH 80,000')), findsOneWidget);
    expect(find.descendant(of: _key('ov_month'), matching: find.text('Profit TSH 51,000')), findsOneWidget);
    expect(find.descendant(of: _key('ov_year'), matching: find.text('TSH 900,000')), findsOneWidget);
  });

  testWidgets('without the profit right the periods show takings only', (t) async {
    final SalonOverview base = _overview();
    await _host(
      t,
      _FakeSalon(SalonOverview(
        today: base.today, week: base.week, month: base.month, year: base.year, collections: base.collections, outstanding: base.outstanding,
        topServices: base.topServices, topStaff: const <RankedItem>[], bookingsToday: 2, bookingsUpcoming: 5, profitHidden: true,
      )),
    );

    expect(find.descendant(of: _key('ov_week'), matching: find.text('TSH 126,000')), findsOneWidget);
    expect(find.textContaining('Profit'), findsNothing);
    expect(find.textContaining('Loss'), findsNothing);
    expect(find.text('Top 3 stylists this month'), findsNothing);
    expect(find.text('Best 3 selling services'), findsOneWidget);
  });

  testWidgets('a month at a loss says loss', (t) async {
    await _host(t, _FakeSalon(_overview(monthProfit: -4000)));

    expect(find.descendant(of: _key('ov_month'), matching: find.text('Loss TSH -4,000')), findsOneWidget);
  });

  testWidgets('the business admin dashboard leaves the bookings out and keeps the rest', (t) async {
    await _host(t, _FakeSalon(_overview()), role: 'admin');

    expect(_key('ov_bookings_today'), findsNothing);
    expect(_key('ov_bookings_upcoming'), findsNothing);
    expect(find.text('Bookings today'), findsNothing);
    expect(find.descendant(of: _key('ov_clients'), matching: find.text('4')), findsOneWidget);
    expect(find.descendant(of: _key('ov_outstanding'), matching: find.text('TSH 20,000')), findsOneWidget);
    expect(find.text('Top 3 stylists this month'), findsOneWidget);
  });

  testWidgets('everyone else still sees how many are booked today and coming up', (t) async {
    await _host(t, _FakeSalon(_overview()), role: 'accountant');

    expect(find.descendant(of: _key('ov_bookings_today'), matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: _key('ov_bookings_upcoming'), matching: find.text('5')), findsOneWidget);
  });

  testWidgets('says how many are booked today and coming up, how many clients, and what is owed', (t) async {
    await _host(t, _FakeSalon(_overview()));

    expect(find.descendant(of: _key('ov_bookings_today'), matching: find.text('2')) , findsOneWidget);
    expect(find.descendant(of: _key('ov_bookings_upcoming'), matching: find.text('5')), findsOneWidget);
    expect(find.descendant(of: _key('ov_clients'), matching: find.text('4')), findsOneWidget);
    expect(find.descendant(of: _key('ov_outstanding'), matching: find.text('TSH 20,000')), findsOneWidget);
  });

  testWidgets('says nothing about debts when there are none', (t) async {
    await _host(t, _FakeSalon(_overview(outstanding: 0)));

    expect(_key('ov_outstanding'), findsNothing);
  });

  testWidgets('ranks the stylists and the services, and names the unnamed', (t) async {
    await _host(t, _FakeSalon(_overview()));

    expect(find.descendant(of: _key('ov_staff_0'), matching: find.text('Asha')), findsOneWidget);
    expect(find.descendant(of: _key('ov_staff_0'), matching: find.text('TSH 110,000')), findsOneWidget);
    expect(find.descendant(of: _key('ov_staff_1'), matching: find.text('No stylist named')), findsOneWidget);
    expect(find.descendant(of: _key('ov_service_0'), matching: find.text('× 1')), findsOneWidget);
    expect(find.descendant(of: _key('ov_service_1'), matching: find.text('× 2')), findsOneWidget);
  });

  testWidgets('shows how the money came in', (t) async {
    await _host(t, _FakeSalon(_overview()));

    expect(find.descendant(of: _key('ov_col_mpesa'), matching: find.text('TSH 90,000')), findsOneWidget);
    expect(find.descendant(of: _key('ov_col_cash'), matching: find.text('TSH 16,000')), findsOneWidget);
  });

  testWidgets('how the money came in is for the owner: an accountant (without the cashbook right) does not see it', (t) async {
    await _host(t, _FakeSalon(_overview()), role: 'accountant');

    expect(find.text('Money received this month'), findsNothing);
    expect(_key('ov_col_mpesa'), findsNothing);
  });

  testWidgets('the owner taps a way of paying and is taken to its payments, with that way already chosen', (t) async {
    final _FakeSalon api = _FakeSalon(_overview());
    await _host(t, api, role: 'admin');

    await t.ensureVisible(_key('ov_col_mpesa'));
    await t.tap(_key('ov_col_mpesa'));
    for (int i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }

    expect(find.byType(PaymentReferencesScreen), findsOneWidget);
    expect(api.referenceAsks.last, 'mpesa');
  });

  testWidgets('a failed load says so quietly and can be retried', (t) async {
    final _FakeSalon api = _FakeSalon(_overview())..fail = ApiException('Server is down');
    await _host(t, api);
    expect(find.text('The overview could not be loaded.'), findsOneWidget);
    expect(find.text('Business overview'), findsNothing);

    await t.tap(_key('overview_retry'));
    for (int i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }

    expect(api.calls, 2);
    expect(find.text('Business overview'), findsOneWidget);
  });

  testWidgets('in Swahili the card is Swahili', (t) async {
    await _host(t, _FakeSalon(_overview()), sw: true);

    expect(find.text('Muhtasari wa biashara'), findsOneWidget);
    expect(find.descendant(of: _key('ov_bookings_today'), matching: find.text('2')), findsOneWidget);
    expect(find.text('Wahudumu 3 bora mwezi huu'), findsOneWidget);
    expect(find.text('Huduma 3 zinazouza zaidi'), findsOneWidget);
    expect(find.text('Pesa zilizopokelewa mwezi huu'), findsOneWidget);
    expect(find.descendant(of: _key('ov_outstanding'), matching: find.text('TSH 20,000')), findsOneWidget);
  });
}
