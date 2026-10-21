import 'package:boda_mapato/modules/inventory/screens/salon/salon_reports_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSalon extends SalonApi {
  final List<(DateTime, DateTime)> asked = <(DateTime, DateTime)>[];
  Object? fail;
  bool noBranches = false;

  @override
  Future<Map<String, dynamic>> salonReports(DateTime from, DateTime to) async {
    asked.add((from, to));
    if (fail != null) throw fail!;

    return <String, dynamic>{
      'summary': <String, dynamic>{'revenue': 110000, 'service_revenue': 110000, 'goods_revenue': 0, 'discounts': 0, 'expenses': 20000, 'commissions': 8000, 'net_profit': 82000, 'sales': 4, 'clients': 2},
      'by_service': <Map<String, dynamic>>[<String, dynamic>{'name': 'Braids', 'times': 2, 'revenue': 80000}],
      'by_stylist': <Map<String, dynamic>>[<String, dynamic>{'name': 'Asha', 'services': 2, 'clients': 2, 'revenue': 80000}],
      'by_method': <Map<String, dynamic>>[<String, dynamic>{'method': 'mpesa', 'amount': 40000}, <String, dynamic>{'method': 'cash', 'amount': 60000}],
      'by_branch': noBranches ? <dynamic>[] : <Map<String, dynamic>>[<String, dynamic>{'name': 'Kariakoo', 'sales': 3, 'revenue': 80000}],
      'expenses_by_category': <Map<String, dynamic>>[<String, dynamic>{'category': 'rent', 'total': 20000}],
      'diary': <String, dynamic>{'booked': 10, 'done': 6, 'no_show': 1, 'cancelled': 1, 'still_open': 2, 'online': 3, 'no_show_rate': 12.5, 'deposits_kept': 5000},
      'clients': <String, dynamic>{
        'active': 2, 'new': 1, 'returning': 1, 'stopped_coming': 7, 'stopped_after_weeks': 8, 'birthdays_this_month': 2,
        'top_spenders': <Map<String, dynamic>>[<String, dynamic>{'name': 'Neema', 'visits': 3, 'spent': 55000}],
      },
      'owed': <String, dynamic>{'total': 10000, 'count': 1, 'list': <Map<String, dynamic>>[<String, dynamic>{'client': 'Rehema', 'due': 10000, 'days': 5}]},
      'stock': <String, dynamic>{'items': 4, 'at_cost': 12000, 'at_price': 32000, 'low': 1},
    };
  }
}

Future<void> _pump(WidgetTester t, _FakeSalon api, {bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: MaterialApp(home: Scaffold(body: SalonReportsScreen(api: api, today: DateTime(2026, 11, 18)))),
    ),
  );
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('every section of the reports is there with its figures', (t) async {
    final _FakeSalon api = _FakeSalon();
    await _pump(t, api);
    expect(api.asked.single, (DateTime(2026, 11), DateTime(2026, 11, 18)));
    for (final String id in <String>['summary', 'service', 'stylist', 'method', 'branch', 'expenses', 'diary', 'clients', 'owed', 'stock']) {
      expect(find.byKey(Key('sr_section_$id')), findsOneWidget, reason: id);
    }
    expect(find.descendant(of: find.byKey(const Key('sr_revenue')), matching: find.text('TSH 110,000')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('sr_profit')), matching: find.text('TSH 82,000')), findsOneWidget);
    expect(find.text('Braids  ×2'), findsOneWidget);
    expect(find.text('Asha  (2 · 2 clients)'), findsOneWidget);
    expect(find.text('M-Pesa'), findsOneWidget);
    expect(find.text('Kariakoo  (3 sales)'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('sr_noshow')), matching: find.text('1 (12.5%)')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('sr_stopped')), matching: find.text('7')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('sr_owed')), matching: find.text('TSH 10,000')), findsOneWidget);
    expect(find.text('Rehema  ·  5 days'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('sr_cost')), matching: find.text('TSH 12,000')), findsOneWidget);
    expect(find.text('Neema  (3)'), findsOneWidget);
  });

  testWidgets('the period chips ask for today, this week, this month and this year', (t) async {
    final _FakeSalon api = _FakeSalon();
    await _pump(t, api);
    for (final String k in <String>['today', 'week', 'year', 'month']) {
      await t.tap(find.byKey(Key('sr_$k')));
      await t.pump();
      await t.pump();
    }
    expect(api.asked.skip(1).toList(), <(DateTime, DateTime)>[
      (DateTime(2026, 11, 18), DateTime(2026, 11, 18)),
      (DateTime(2026, 11, 16), DateTime(2026, 11, 18)),
      (DateTime(2026, 1, 1), DateTime(2026, 11, 18)),
      (DateTime(2026, 11), DateTime(2026, 11, 18)),
    ]);
  });

  testWidgets('without branches there is no branch section', (t) async {
    await _pump(t, _FakeSalon()..noBranches = true);
    expect(find.byKey(const Key('sr_section_branch')), findsNothing);
  });

  testWidgets('a refusal shows the server words and the page is Swahili when asked', (t) async {
    await _pump(t, _FakeSalon()..fail = Exception('Ni mmiliki au mhasibu tu.'));
    expect(find.textContaining('Ni mmiliki au mhasibu tu.'), findsOneWidget);
  });

  testWidgets('in Swahili the sections are Swahili', (t) async {
    await _pump(t, _FakeSalon(), sw: true);
    expect(find.text('Mapato kwa huduma'), findsOneWidget);
    expect(find.text('Madeni ya wateja'), findsOneWidget);
    expect(find.text('Hawajaja wiki 8+'), findsOneWidget);
  });
}
