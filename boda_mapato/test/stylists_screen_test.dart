import 'dart:async';

import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/stylists_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How each stylist did: the month's takings, services, visits and clients, best first; this month, last month or
/// the last 7 days.
class _FakeSalon extends SalonApi {
  _FakeSalon(this.answer);

  Future<StylistReport> Function(DateTime? from, DateTime? to) answer;
  final List<(DateTime?, DateTime?)> asked = <(DateTime?, DateTime?)>[];

  @override
  Future<StylistReport> stylists({DateTime? from, DateTime? to}) {
    asked.add((from, to));
    return answer(from, to);
  }
}

StylistReport _report({List<StylistRow> rows = const <StylistRow>[]}) => StylistReport(
      from: DateTime(2026, 10),
      to: DateTime(2026, 10, 15),
      stylists: rows,
      services: rows.fold(0, (int s, StylistRow r) => s + r.services),
      revenue: rows.fold(0, (double s, StylistRow r) => s + r.revenue),
      visits: rows.fold(0, (int s, StylistRow r) => s + r.visits),
    );

const StylistRow _asha = StylistRow(staffId: 'u-asha', name: 'Asha', services: 3, revenue: 50000, visits: 2, clients: 1);
const StylistRow _bahati = StylistRow(staffId: 'u-bahati', name: 'Bahati', services: 1, revenue: 40000, visits: 1, clients: 1);
const StylistRow _nobody = StylistRow(staffId: null, name: '', services: 1, revenue: 5000, visits: 1, clients: 0);

final DateTime _today = DateTime(2026, 10, 15);

Future<void> _open(WidgetTester t, _FakeSalon api, {bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(411, 900),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: Scaffold(body: StylistsScreen(api: api, today: _today))),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('shows the totals, and each stylist with what they brought in, best first', (t) async {
    await _open(t, _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha, _bahati, _nobody])));

    expect(find.text('TSH 95,000'), findsOneWidget, reason: 'the total');
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('TSH 50,000'), findsOneWidget);
    expect(find.text('Bahati'), findsOneWidget);
    expect(find.text('TSH 40,000'), findsOneWidget);
    expect(find.text('No stylist named'), findsOneWidget, reason: 'a line with nobody named is still shown, honestly');
    expect(t.getTopLeft(_key('stylist_u-asha')).dy, lessThan(t.getTopLeft(_key('stylist_u-bahati')).dy), reason: 'the best first');
    expect(t.getTopLeft(_key('stylist_u-bahati')).dy, lessThan(t.getTopLeft(_key('stylist_none')).dy));
  });

  testWidgets('shows what each stylist earned in commission, and says nothing when no service has a rate', (t) async {
    const StylistRow earns = StylistRow(staffId: 'u-asha', name: 'Asha', services: 2, revenue: 50000, visits: 2, clients: 1, commission: 15000);
    await _open(t, _FakeSalon((_, __) async => StylistReport(from: DateTime(2026, 10), to: DateTime(2026, 10, 15), stylists: <StylistRow>[earns, _bahati], services: 3, revenue: 90000, visits: 3, commission: 15000)));

    expect(find.text('TSH 15,000'), findsNWidgets(2), reason: 'the total, and Ashas card');
    expect(find.descendant(of: _key('stylist_u-asha'), matching: find.text('Commission')), findsOneWidget);
    expect(find.descendant(of: _key('stylist_u-bahati'), matching: find.text('Commission')), findsNothing);
  });

  testWidgets('no commission anywhere shows no commission line', (t) async {
    await _open(t, _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha])));

    expect(find.text('Commission'), findsNothing);
    expect(find.text("Stylists' commission"), findsNothing);
  });

  testWidgets('says services, visits and clients for each stylist', (t) async {
    await _open(t, _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha])));

    final Finder card = _key('stylist_u-asha');
    expect(find.descendant(of: card, matching: find.text('3')), findsOneWidget, reason: '3 services');
    expect(find.descendant(of: card, matching: find.text('2')), findsOneWidget, reason: '2 visits');
    expect(find.descendant(of: card, matching: find.text('1')), findsWidgets, reason: '1 client (and the rank)');
    expect(find.descendant(of: card, matching: find.text('Services')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Visits')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Clients')), findsOneWidget);
  });

  testWidgets('asks for this month first, then last month, then the last 7 days', (t) async {
    final _FakeSalon api = _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha]));
    await _open(t, api);

    expect(api.asked.last, (DateTime(2026, 10), DateTime(2026, 10, 15)), reason: 'this month: the 1st to today');

    await t.tap(find.text('Last month'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(api.asked.last, (DateTime(2026, 9), DateTime(2026, 9, 30)), reason: 'all of September');

    await t.ensureVisible(find.text('Last 7 days')); // the chips scroll sideways on a narrow phone
    await t.tap(find.text('Last 7 days'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(api.asked.last, (DateTime(2026, 10, 9), DateTime(2026, 10, 15)), reason: 'today and the 6 days before');
    expect(api.asked, hasLength(3));
  });

  testWidgets('last month in January is December of the year before', (t) async {
    final _FakeSalon api = _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha]));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    t.view.physicalSize = const Size(411, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<LocalizationService>.value(
        value: LocalizationService.instance,
        child: ScreenUtilInit(
          designSize: const Size(411, 900),
          minTextAdapt: true,
          builder: (_, __) => MaterialApp(home: Scaffold(body: StylistsScreen(api: api, today: DateTime(2027, 1, 10)))),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    await t.tap(find.text('Last month'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(api.asked.last, (DateTime(2026, 12), DateTime(2026, 12, 31)));
  });

  testWidgets('a period with no services says what to do, not just "nothing"', (t) async {
    await _open(t, _FakeSalon((_, __) async => _report()));

    expect(find.textContaining('No services recorded for this period'), findsOneWidget);
    expect(find.textContaining('Choose a stylist each time you sell a service'), findsOneWidget);
    expect(find.text('TSH 0'), findsOneWidget);
  });

  testWidgets('a failed load says why and can be retried', (t) async {
    int calls = 0;
    await _open(t, _FakeSalon((_, __) async {
      calls++;
      if (calls == 1) throw ApiException('Hakuna mtandao. / No connection.');
      return _report(rows: <StylistRow>[_asha]);
    }));

    expect(find.text('No connection.'), findsOneWidget);

    await t.tap(_key('stylists_retry'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('No connection.'), findsNothing);
  });

  testWidgets('an answer for a period nobody is looking at any more is thrown away', (t) async {
    final Completer<StylistReport> slow = Completer<StylistReport>();
    int calls = 0;
    final _FakeSalon api = _FakeSalon((_, __) {
      calls++;
      return calls == 1 ? slow.future : Future<StylistReport>.value(_report(rows: <StylistRow>[_bahati]));
    });
    await _open(t, api);

    await t.tap(find.text('Last month')); // while this month is still loading
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Bahati'), findsOneWidget);

    slow.complete(_report(rows: <StylistRow>[_asha])); // the slow, old answer arrives late
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.text('Bahati'), findsOneWidget, reason: 'last month is what is on screen');
    expect(find.text('Asha'), findsNothing, reason: 'this month\'s late answer did not overwrite it');
  });

  testWidgets('in Swahili the labels are Swahili', (t) async {
    await _open(t, _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha, _nobody])), sw: true);

    expect(find.text('Mwezi huu'), findsOneWidget);
    expect(find.text('Mwezi uliopita'), findsOneWidget);
    expect(find.text('Siku 7'), findsOneWidget);
    expect(find.text('Mapato'), findsOneWidget);
    expect(find.text('Hakutajwa mhudumu'), findsOneWidget);
    expect(find.text('Ziara'), findsWidgets);
  });
}
