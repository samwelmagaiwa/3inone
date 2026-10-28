import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/salon_overview_card.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/services_report_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The dashboard shows the best three stylists and the best three services; when there are more, a More button opens the page with
/// everything, and the services page names the clients each service was done for.
class _FakeSalon extends SalonApi {
  _FakeSalon(this.overviewData);

  final SalonOverview overviewData;
  final List<(DateTime?, DateTime?)> askedServices = <(DateTime?, DateTime?)>[];
  int stylistCalls = 0;

  @override
  Future<SalonOverview> overview() async => overviewData;

  @override
  Future<StylistReport> stylists({DateTime? from, DateTime? to}) async {
    stylistCalls++;
    return StylistReport(from: DateTime(2026, 10), to: DateTime(2026, 10, 15), stylists: const <StylistRow>[StylistRow(staffId: 'a', name: 'Asha', services: 3, revenue: 50000, visits: 2, clients: 1)], services: 3, revenue: 50000, visits: 2);
  }

  @override
  Future<ServiceReport> serviceSales({DateTime? from, DateTime? to}) async {
    askedServices.add((from, to));
    return ServiceReport(from: DateTime(2026, 10), to: DateTime(2026, 10, 15), times: 3, revenue: 120000, services: <ServiceRow>[
      ServiceRow(productId: 1, name: 'Braids', times: 2, revenue: 80000, clients: 2, sales: <ServiceSaleLine>[
        ServiceSaleLine(saleId: 1, number: 'S-1', date: DateTime(2026, 10, 5, 10, 30), client: 'Neema Joseph', stylist: 'Asha', qty: 1, net: 40000),
        ServiceSaleLine(saleId: 2, number: 'S-2', date: DateTime(2026, 10, 6, 9, 0), client: 'Rehema Ally', stylist: 'Bahati', qty: 1, net: 40000),
      ]),
      ServiceRow(productId: 2, name: 'Wash', times: 1, revenue: 40000, clients: 0, sales: <ServiceSaleLine>[
        ServiceSaleLine(saleId: 3, number: 'S-3', date: DateTime(2026, 10, 6, 11, 0), qty: 1, net: 40000),
      ]),
    ]);
  }
}

SalonOverview _overview(int staff, int services) => SalonOverview(
      today: const PeriodFigures(revenue: 0, expenses: 0, netProfit: 0, clients: 0, sales: 0),
      week: const PeriodFigures(revenue: 0, expenses: 0, netProfit: 0, clients: 0, sales: 0),
      month: const PeriodFigures(revenue: 100000, expenses: 0, netProfit: 50000, clients: 4, sales: 3),
      year: const PeriodFigures(revenue: 100000, expenses: 0, netProfit: 50000, clients: 4, sales: 3),
      collections: const <Collection>[],
      outstanding: 0,
      topServices: <RankedItem>[for (int i = 0; i < services; i++) RankedItem(name: 'Service $i', revenue: 100000.0 - i * 1000, times: 1)],
      topStaff: <RankedItem>[for (int i = 0; i < staff; i++) RankedItem(name: 'Stylist $i', revenue: 100000.0 - i * 1000)],
      bookingsToday: 0,
      bookingsUpcoming: 0,
    );

Future<void> _host(WidgetTester t, Widget child, {bool sw = false, bool scroll = true}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 2400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: scroll ? Scaffold(body: SingleChildScrollView(child: child)) : child)),
    ),
  );
  for (int i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('only the best three stylists and services show, with a More button for each when there are more', (t) async {
    await _host(t, SalonOverviewCard(api: _FakeSalon(_overview(5, 5))));

    for (final String k in <String>['ov_staff_0', 'ov_staff_1', 'ov_staff_2', 'ov_service_0', 'ov_service_1', 'ov_service_2']) {
      expect(_key(k), findsOneWidget, reason: k);
    }
    for (final String k in <String>['ov_staff_3', 'ov_staff_4', 'ov_service_3', 'ov_service_4']) {
      expect(_key(k), findsNothing, reason: k);
    }
    expect(_key('ov_staff_more'), findsOneWidget);
    expect(_key('ov_service_more'), findsOneWidget);
    expect(find.text('Top 3 stylists this month'), findsOneWidget);
  });

  testWidgets('with three or fewer there is nothing more to show, so no More button', (t) async {
    await _host(t, SalonOverviewCard(api: _FakeSalon(_overview(3, 2))));

    expect(_key('ov_staff_2'), findsOneWidget);
    expect(_key('ov_staff_more'), findsNothing);
    expect(_key('ov_service_more'), findsNothing);
  });

  testWidgets('More under the stylists opens the full stylists page', (t) async {
    final _FakeSalon api = _FakeSalon(_overview(5, 5));
    await _host(t, SalonOverviewCard(api: api));

    await t.tap(_key('ov_staff_more'));
    for (int i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }

    expect(api.stylistCalls, 1);
    expect(find.text('Asha'), findsWidgets);
  });

  testWidgets('More under the services opens the page with every service, and a tap names the clients', (t) async {
    final _FakeSalon api = _FakeSalon(_overview(5, 5));
    await _host(t, SalonOverviewCard(api: api));

    await t.tap(_key('ov_service_more'));
    for (int i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }

    expect(api.askedServices, hasLength(1));
    expect(find.text('Braids'), findsOneWidget);
    expect(find.text('Wash'), findsOneWidget);
    expect(find.text('Neema Joseph'), findsNothing, reason: 'closed until tapped');

    await t.tap(_key('service_1'));
    await t.pump();
    expect(find.text('Neema Joseph'), findsOneWidget);
    expect(find.text('Rehema Ally'), findsOneWidget);
    expect(find.textContaining('Asha'), findsWidgets, reason: 'and who did it');
  });

  testWidgets('a service done for a walk-in with no name still lists it', (t) async {
    await _host(t, ServicesReportScreen(api: _FakeSalon(_overview(1, 1)), today: DateTime(2026, 10, 15)), scroll: false);
    await t.pump(const Duration(milliseconds: 300));

    await t.tap(_key('service_2'));
    await t.pump();
    expect(find.text('Walk-in client'), findsOneWidget);
  });

  testWidgets('the services page asks for this month first and again for the period chosen', (t) async {
    final _FakeSalon api = _FakeSalon(_overview(1, 1));
    await _host(t, ServicesReportScreen(api: api, today: DateTime(2026, 10, 15)), scroll: false);
    await t.pump(const Duration(milliseconds: 300));

    expect(api.askedServices.single, (DateTime(2026, 10), DateTime(2026, 10, 15)));
    await t.tap(find.text('Last month'));
    await t.pump(const Duration(milliseconds: 300));
    expect(api.askedServices.last, (DateTime(2026, 9), DateTime(2026, 9, 30)));
    expect(find.text('Revenue'), findsOneWidget);
  });
}
