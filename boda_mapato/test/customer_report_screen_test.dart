import 'package:boda_mapato/modules/inventory/screens/credit/customer_report_screen.dart';
import 'package:boda_mapato/modules/inventory/services/customer_report_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A customer's report: what they bought, paid, the profit they brought (only for those who may see profit) and what they owe now,
/// for any period, grouped by day, week or month.
class _FakeReport extends CustomerReportApi {
  _FakeReport({this.profit = true});

  final bool profit;
  final List<(DateTime, DateTime, String)> asked = <(DateTime, DateTime, String)>[];

  @override
  Future<Map<String, dynamic>> report(final int customerId, {required final DateTime from, required final DateTime to, required final String group}) async {
    asked.add((from, to, group));

    return <String, dynamic>{
      'customer': <String, dynamic>{'id': customerId, 'name': 'Mama Neema Joseph', 'phone': '0711000001', 'address': 'Kariakoo', 'credit_limit': 500000},
      'profit_visible': profit,
      'totals': <String, dynamic>{'purchases': 3, 'sales': 6000000, 'paid': 5000000, 'cost': profit ? 4000000 : null, 'profit': profit ? 2000000 : null, 'margin_percent': profit ? 33.3 : null},
      'debt': <String, dynamic>{'owes_now': 1090000, 'from_sales': 1000000, 'from_before_app': 90000},
      'lifetime': <String, dynamic>{'purchases': 9, 'sales': 12000000, 'profit': profit ? 4000000 : null, 'first_purchase': '2026-01-05 09:00', 'last_purchase': '2026-11-20 09:00'},
      'by_period': <Map<String, dynamic>>[
        <String, dynamic>{'period': '2026-11-02', 'purchases': 2, 'sales': 4000000, 'paid': 4000000, 'profit': profit ? 1500000 : null},
        <String, dynamic>{'period': '2026-11-16', 'purchases': 1, 'sales': 2000000, 'paid': 1000000, 'profit': profit ? 500000 : null},
      ],
      'top_products': <Map<String, dynamic>>[<String, dynamic>{'name': 'Soda', 'qty': 40, 'sales': 4000000, 'profit': profit ? 1600000 : null}],
      'recent_sales': <Map<String, dynamic>>[<String, dynamic>{'id': 7, 'number': 'S-0007', 'at': '2026-11-20 09:00', 'total': 2000000, 'paid': 1000000, 'status': 'partial'}],
    };
  }
}

Future<void> _open(WidgetTester t, _FakeReport api, {bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: MaterialApp(home: CustomerReportScreen(customerId: 1, name: 'Mama Neema Joseph', api: api, today: DateTime(2026, 11, 25))),
    ),
  );
  await t.pump();
  await t.pump();
}

Finder _k(String k) => find.byKey(Key(k));

void main() {
  testWidgets('starts on this month, grouped by week, and shows what was bought, paid, the profit and what is owed with commas', (WidgetTester t) async {
    final _FakeReport api = _FakeReport();
    await _open(t, api);

    expect(api.asked.single, (DateTime(2026, 11, 1), DateTime(2026, 11, 25), 'week'));
    expect(t.widget<Text>(find.descendant(of: _k('cr_sales'), matching: find.text('TSh 6,000,000'))).data, 'TSh 6,000,000');
    expect(find.descendant(of: _k('cr_paid'), matching: find.text('TSh 5,000,000')), findsOneWidget);
    expect(find.descendant(of: _k('cr_profit'), matching: find.text('TSh 2,000,000')), findsOneWidget);
    expect(find.descendant(of: _k('cr_owes'), matching: find.text('TSh 1,090,000')), findsOneWidget);
    expect(find.textContaining('incl. TSh 90,000 from before the app'), findsOneWidget);
    expect(_k('period_row_2026-11-02'), findsOneWidget);
    expect(find.text('Soda'), findsOneWidget);
    expect(find.text('S-0007'), findsOneWidget);
    expect(find.descendant(of: _k('cr_life'), matching: find.text('TSh 12,000,000')), findsOneWidget);
  });

  testWidgets('a person who may not see profit gets no profit anywhere', (WidgetTester t) async {
    await _open(t, _FakeReport(profit: false));

    expect(_k('cr_profit'), findsNothing);
    expect(find.textContaining('profit'), findsNothing);
    expect(find.descendant(of: _k('cr_owes'), matching: find.text('TSh 1,090,000')), findsOneWidget);
  });

  testWidgets('choosing a year asks for the year grouped by month, and the grouping can be changed', (WidgetTester t) async {
    final _FakeReport api = _FakeReport();
    await _open(t, api);

    await t.tap(_k('period_year'));
    await t.pump();
    await t.pump();
    expect(api.asked.last, (DateTime(2026, 1, 1), DateTime(2026, 11, 25), 'month'));

    await t.tap(_k('group_week'));
    await t.pump();
    await t.pump();
    expect(api.asked.last.$3, 'week');
    expect(api.asked.last.$1, DateTime(2026, 1, 1));
  });

  testWidgets('a week is shown day by day', (WidgetTester t) async {
    final _FakeReport api = _FakeReport();
    await _open(t, api);

    await t.tap(_k('period_week'));
    await t.pump();
    await t.pump();

    expect(api.asked.last, (DateTime(2026, 11, 23), DateTime(2026, 11, 25), 'day'), reason: 'Monday 23 Nov to today');
  });

  testWidgets('Swahili wording', (WidgetTester t) async {
    await _open(t, _FakeReport(), sw: true);

    expect(find.text('Alichonunua'), findsOneWidget);
    expect(find.text('Deni analodaiwa sasa'), findsOneWidget);
    expect(find.text('Mwezi huu'), findsOneWidget);
  });
}
