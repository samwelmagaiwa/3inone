import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/stylist_detail_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/stylists_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The services behind one stylist's total, and the tap that opens them from the Stylists page.
class _FakeSalon extends SalonApi {
  _FakeSalon({this.page, this.report});

  StylistPage? page;
  StylistReport? report;
  Object? fail;
  final List<(String?, DateTime?, DateTime?)> asked = <(String?, DateTime?, DateTime?)>[];

  @override
  Future<StylistPage> stylistPage(String? staffId, {DateTime? from, DateTime? to}) async {
    asked.add((staffId, from, to));
    if (fail != null) {
      final Object e = fail!;
      fail = null;
      throw e;
    }
    return page!;
  }

  @override
  Future<StylistReport> stylists({DateTime? from, DateTime? to}) async => report!;
}

StylistLine _line({String number = 'S-1', String? client = 'Neema', String service = 'Braids', int qty = 1, double value = 80000, double discount = 8000, double net = 72000, double commission = 8000, String? reason = 'Loyal client', String status = 'paid', List<String> methods = const <String>['mpesa']}) => StylistLine(
      saleId: 1,
      number: number,
      date: DateTime(2026, 10, 5, 10, 30),
      client: client,
      service: service,
      qty: qty,
      value: value,
      discount: discount,
      net: net,
      commission: commission,
      discountReason: reason,
      paymentStatus: status,
      methods: methods,
    );

StylistPage _page({List<StylistLine>? lines, double discount = 8000}) => StylistPage(
      from: DateTime(2026, 10),
      to: DateTime(2026, 10, 15),
      name: 'Asha',
      lines: lines ?? <StylistLine>[_line()],
      services: 1,
      value: 80000,
      discount: discount,
      net: 72000,
      commission: 8000,
    );

Future<void> _host(WidgetTester t, Widget home, {bool sw = false}) async {
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
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 1400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: home)),
    ),
  );
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('shows net revenue, commission and the number of services, then every line', (t) async {
    await _host(t, StylistDetailScreen(title: 'Asha', staffId: 'u-asha', from: DateTime(2026, 10), to: DateTime(2026, 10, 15), api: _FakeSalon(page: _page())));

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('01/10/2026 – 15/10/2026'), findsOneWidget);
    expect(find.text('Net revenue'), findsOneWidget);
    expect(find.text('TSH 72,000'), findsWidgets);
    expect(find.text('TSH 8,000'), findsOneWidget, reason: 'the commission tile');
    expect(find.text('Worth TSH 80,000 – discount TSH 8,000'), findsOneWidget);

    final Finder line = _key('stylist_line_0');
    expect(find.descendant(of: line, matching: find.text('Braids')), findsOneWidget);
    expect(find.descendant(of: line, matching: find.text('Neema')), findsOneWidget);
    expect(find.descendant(of: line, matching: find.text('TSH 80,000 − TSH 8,000')), findsOneWidget);
    expect(find.descendant(of: line, matching: find.text('TSH 72,000')), findsOneWidget);
    expect(find.descendant(of: line, matching: find.text('Discount: Loyal client')), findsOneWidget);
    expect(find.descendant(of: line, matching: find.text('M-Pesa')), findsOneWidget);
    expect(find.descendant(of: line, matching: find.text('Paid')), findsOneWidget);
    expect(find.descendant(of: line, matching: find.text('Commission TSH 8,000')), findsOneWidget);
    expect(find.descendant(of: line, matching: find.text('05/10/2026 10:30 • S-1')), findsOneWidget);
  });

  testWidgets('asks the server for that stylist and that period', (t) async {
    final _FakeSalon api = _FakeSalon(page: _page());
    await _host(t, StylistDetailScreen(title: 'Asha', staffId: 'u-asha', from: DateTime(2026, 10), to: DateTime(2026, 10, 15), api: api));

    expect(api.asked.single, ('u-asha', DateTime(2026, 10), DateTime(2026, 10, 15)));
  });

  testWidgets('a line with no discount shows just its value; a walk-in and an owing sale say so', (t) async {
    await _host(
      t,
      StylistDetailScreen(
        title: 'Asha',
        staffId: 'u-asha',
        from: DateTime(2026, 10),
        to: DateTime(2026, 10, 15),
        api: _FakeSalon(page: _page(discount: 0, lines: <StylistLine>[_line(client: null, discount: 0, net: 80000, reason: null, status: 'debt', methods: const <String>[], qty: 2, service: 'Wash')])),
      ),
    );

    expect(find.text('Wash × 2'), findsOneWidget);
    expect(find.text('Walk-in client'), findsOneWidget);
    expect(find.text('Owing'), findsOneWidget);
    expect(find.textContaining('Discount:'), findsNothing);
    expect(_key('stylist_page_discount'), findsNothing);
    expect(find.text('TSH 80,000'), findsWidgets);
  });

  testWidgets('every way of paying is named the way people say it', (t) async {
    await _host(
      t,
      StylistDetailScreen(
        title: 'Asha',
        staffId: 'u-asha',
        from: DateTime(2026, 10),
        to: DateTime(2026, 10, 15),
        api: _FakeSalon(page: _page(lines: <StylistLine>[_line(methods: const <String>['cash', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer'])])),
      ),
    );

    for (final String m in <String>['Cash', 'Mixx by Yas', 'Airtel Money', 'HaloPesa', 'Bank']) {
      expect(find.text(m), findsOneWidget, reason: m);
    }
  });

  testWidgets('a period with no services says so', (t) async {
    await _host(t, StylistDetailScreen(title: 'Asha', staffId: 'u-asha', from: DateTime(2026, 10), to: DateTime(2026, 10, 15), api: _FakeSalon(page: _page(lines: <StylistLine>[], discount: 0))));

    expect(find.text('No services in this period.'), findsOneWidget);
  });

  testWidgets('a failed load says why and can be retried', (t) async {
    final _FakeSalon api = _FakeSalon(page: _page())..fail = ApiException('Server is down');
    await _host(t, StylistDetailScreen(title: 'Asha', staffId: 'u-asha', from: DateTime(2026, 10), to: DateTime(2026, 10, 15), api: api));

    expect(find.text('Server is down'), findsOneWidget);
    await t.tap(_key('stylist_page_retry'));
    for (int i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Net revenue'), findsOneWidget);
  });

  testWidgets('in Swahili the page is Swahili', (t) async {
    await _host(t, StylistDetailScreen(title: 'Asha', staffId: 'u-asha', from: DateTime(2026, 10), to: DateTime(2026, 10, 15), api: _FakeSalon(page: _page())), sw: true);

    expect(find.text('Mapato halisi'), findsOneWidget);
    expect(find.text('Kamisheni'), findsOneWidget);
    expect(find.text('Imelipwa'), findsOneWidget);
    expect(find.text('Punguzo: Loyal client'), findsOneWidget);
    expect(find.text('Thamani TSH 80,000 – punguzo TSH 8,000'), findsOneWidget);
  });

  group('from the Stylists page', () {
    StylistReport report() => StylistReport(
          from: DateTime(2026, 10),
          to: DateTime(2026, 10, 15),
          stylists: const <StylistRow>[
            StylistRow(staffId: 'u-asha', name: 'Asha', services: 1, revenue: 72000, visits: 1, clients: 1, commission: 8000, discount: 8000),
            StylistRow(staffId: null, name: '', services: 1, revenue: 5000, visits: 1, clients: 0),
          ],
          services: 2,
          revenue: 77000,
          visits: 2,
        );

    testWidgets('tapping a stylist opens the services behind her total, for the period the report covers', (t) async {
      final _FakeSalon api = _FakeSalon(page: _page(), report: report());
      await _host(t, Scaffold(body: StylistsScreen(api: api, today: DateTime(2026, 10, 15))));
      expect(find.text('Discount'), findsOneWidget, reason: 'her card says how much discount came off her services');

      await t.tap(_key('stylist_u-asha'));
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }

      expect(find.text('Net revenue'), findsOneWidget);
      expect(api.asked.single, ('u-asha', DateTime(2026, 10), DateTime(2026, 10, 15)));
    });

    testWidgets('"nobody named" opens its own page', (t) async {
      final _FakeSalon api = _FakeSalon(page: _page(), report: report());
      await _host(t, Scaffold(body: StylistsScreen(api: api, today: DateTime(2026, 10, 15))));

      await t.tap(_key('stylist_none'));
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }

      expect(api.asked.single.$1, isNull);
      expect(find.text('No stylist named'), findsWidgets);
    });
  });
}
