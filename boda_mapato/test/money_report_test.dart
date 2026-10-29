import 'package:boda_mapato/modules/inventory/screens/money/month_summary_card.dart';
import 'package:boda_mapato/modules/inventory/screens/money/monthly_report_screen.dart';
import 'package:boda_mapato/modules/inventory/services/money_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The monthly report: the headline (better, the same or below last month, in percent), the profit target and its verdict, the
/// figures with how each moved, where the business stands, spending, and advice (by AI or by rules). Plus the dashboard card.
Map<String, dynamic> _cmp(num now, num before, String dir, num? pct, {bool good = true}) => <String, dynamic>{'now': now, 'before': before, 'change': now - before, 'percent': pct, 'direction': dir, 'good': good};

/// "2026-10" -> "2026-09", "2026-01" -> "2025-12".
String _before(String month) {
  final List<String> p = month.split('-');
  final DateTime d = DateTime(int.parse(p[0]), int.parse(p[1]) - 1);

  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

class _FakeMoney extends MoneyApi {
  _FakeMoney({this.dir = 'up', this.target, this.position = true, this.answer, this.failReport = false, this.current = true});

  final String dir;
  final Map<String, dynamic>? target;
  final bool position;
  final Map<String, dynamic>? answer;
  final bool failReport;
  final bool current;
  final List<String?> asked = <String?>[];
  final List<(String, double)> targets = <(String, double)>[];
  final List<bool> adviceRefresh = <bool>[];

  @override
  Future<Map<String, dynamic>> monthlyReport([String? month]) async {
    asked.add(month);
    if (failReport) throw Exception('No connection');
    final int pct = dir == 'up' ? 50 : (dir == 'down' ? -30 : 0);

    return <String, dynamic>{
      'month': month ?? '2026-11', 'is_current': current, 'is_future': false, 'days_elapsed': 20, 'days_in_month': 30,
      'figures': <String, dynamic>{
        'sales': 300000, 'sales_count': 12, 'cost_of_goods': 150000, 'gross_profit': 150000, 'margin_percent': 50.0, 'expenses': 30000,
        'expenses_by_category': <Map<String, dynamic>>[<String, dynamic>{'category': 'rent', 'total': 20000}, <String, dynamic>{'category': 'transport', 'total': 10000}],
        'personal_spending': 7000, 'write_offs': 0, 'net_profit': 120000,
      },
      'previous': <String, dynamic>{'month': _before(month ?? '2026-11'), 'like_for_like': current, 'figures': <String, dynamic>{}},
      'compare': <String, dynamic>{
        'sales': _cmp(300000, 200000, 'up', 50),
        'gross_profit': _cmp(150000, 100000, 'up', 50),
        'expenses': _cmp(30000, 20000, 'up', 50, good: false),
        'net_profit': _cmp(120000, 80000, dir, pct),
      },
      'overall': <String, dynamic>{'direction': dir, 'percent': pct, 'based_on': 'profit'},
      'position': position ? <String, dynamic>{'stock_value': 900000, 'receivable': 150000, 'payable': 50000, 'capital': 1000000} : null,
      'capital_change': position ? <String, dynamic>{'now': 1000000, 'before': 800000, 'change': 200000, 'percent': 25.0, 'direction': 'up'} : null,
      'target': target,
      'top_products': <Map<String, dynamic>>[<String, dynamic>{'name': 'Soda', 'qty': 40, 'sales': 100000, 'profit': 40000}],
      'top_customers': <Map<String, dynamic>>[<String, dynamic>{'name': 'Mama Neema', 'purchases': 3, 'spent': 90000}],
      'slow_stock': <Map<String, dynamic>>[<String, dynamic>{'name': 'Dusty Dye', 'quantity': 50, 'value': 100000}],
      'debtors': <Map<String, dynamic>>[<String, dynamic>{'name': 'Baba Juma', 'owed': 90000, 'days': 200}],
      'creditors': <dynamic>[],
    };
  }

  @override
  Future<Map<String, dynamic>?> setTarget(String month, double t) async {
    targets.add((month, t));
    return null;
  }

  @override
  Future<Map<String, dynamic>> advice(String month, String lang, {bool refresh = false}) async {
    adviceRefresh.add(refresh);
    return answer ?? <String, dynamic>{'items': <dynamic>[], 'source': 'rules', 'ai_available': false, 'refreshes_left': 5};
  }
}

Future<void> _open(WidgetTester t, MoneyApi api, {bool sw = false, String? month}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 6000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: MaterialApp(home: MonthlyReportScreen(api: api, month: month ?? '2026-11', today: DateTime(2026, 11, 20))),
    ),
  );
  await t.pump();
  await t.pump();
  await t.pump();
}

Finder _k(String k) => find.byKey(Key(k));

Map<String, dynamic> _ai() => <String, dynamic>{
      'source': 'ai', 'ai_available': true, 'refreshes_left': 4,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'level': 'warning', 'title': 'Collect from Baba Juma', 'detail': 'Baba Juma owes TSh 90,000.'},
        <String, dynamic>{'level': 'good', 'title': 'Soda is carrying you', 'detail': 'Soda earned TSh 40,000.'},
        <String, dynamic>{'level': 'tip', 'title': 'Discount Dusty Dye', 'detail': 'It has not sold in 30 days.'},
      ],
    };

void main() {
  group('the headline', () {
    testWidgets('better than last month says so, with the percent and the two profits', (t) async {
      await _open(t, _FakeMoney());

      expect(find.text('Better than October 2026 50%'), findsOneWidget);
      expect(_k('headline_up'), findsOneWidget);
      expect(find.textContaining('Profit: TSH 120,000 against TSH 80,000 (same days of October 2026)'), findsOneWidget);
      expect(find.text('The month is still in progress.'), findsOneWidget);
    });

    testWidgets('below last month says so', (t) async {
      await _open(t, _FakeMoney(dir: 'down'));

      expect(find.text('Below October 2026 30%'), findsOneWidget);
      expect(_k('headline_down'), findsOneWidget);
    });

    testWidgets('level with last month says it stayed put, and a finished month is not "in progress"', (t) async {
      await _open(t, _FakeMoney(dir: 'same', current: false), month: '2026-10');

      expect(find.text('The same as September 2026'), findsOneWidget);
      expect(find.text('The month is still in progress.'), findsNothing);
    });

    testWidgets('in Swahili', (t) async {
      await _open(t, _FakeMoney(), sw: true);

      expect(find.text('Umefanya vizuri kuliko Oktoba 2026 50%'), findsOneWidget);
      expect(find.text('Novemba 2026'), findsOneWidget);
      expect(find.text('Hesabu za mwezi'), findsOneWidget);
    });
  });

  testWidgets('the figures, each with a chip for how it moved; more spending is red', (t) async {
    await _open(t, _FakeMoney());

    expect(find.descendant(of: _k('fig_sales'), matching: find.text('TSH 300,000')), findsOneWidget);
    expect(find.descendant(of: _k('fig_net'), matching: find.text('TSH 120,000')), findsOneWidget);
    expect(find.descendant(of: _k('fig_gross'), matching: find.text('Margin 50.0%')), findsOneWidget);
    final Icon up = t.widget<Icon>(find.descendant(of: _k('fig_expenses'), matching: find.byType(Icon)));
    expect(up.icon, Icons.arrow_upward_rounded);
    expect(up.color, const Color(0xFFFF9B9B), reason: 'spending that grew is bad news, in the red that can be read on the dark card');
    final Icon sales = t.widget<Icon>(find.descendant(of: _k('fig_sales'), matching: find.byType(Icon)));
    expect(sales.color, const Color(0xFF10B981));
  });

  testWidgets('says in plain words how the net profit and the capital are worked out', (t) async {
    await _open(t, _FakeMoney());

    expect(find.byKey(const Key('hint_net'), skipOffstage: false), findsOneWidget);
    expect(find.text('Net profit = Sales − Cost of goods − Business expenses. Personal spending is not taken off the profit.', skipOffstage: false), findsOneWidget);
    expect(find.text('Capital = Stock on hand + Owed to me − I owe.', skipOffstage: false), findsOneWidget);
  });

  testWidgets('where the business stands, with the change in capital; debts open the debts page', (t) async {
    await _open(t, _FakeMoney());

    expect(find.descendant(of: _k('pos_stock'), matching: find.text('TSH 900,000')), findsOneWidget);
    expect(find.descendant(of: _k('pos_receivable'), matching: find.text('TSH 150,000')), findsOneWidget);
    expect(find.descendant(of: _k('pos_payable'), matching: find.text('TSH 50,000')), findsOneWidget);
    expect(find.descendant(of: _k('pos_capital'), matching: find.text('TSH 1,000,000')), findsOneWidget);
    expect(find.text('Capital grew TSH 200,000 (25.0%) since last month'), findsOneWidget);
  });

  testWidgets('a month nobody recorded says balances start from the first time the report is opened', (t) async {
    await _open(t, _FakeMoney(position: false));

    expect(_k('no_position'), findsOneWidget);
    expect(_k('pos_capital'), findsNothing);
  });

  testWidgets('spending lists business categories and keeps personal spending apart, labelled as not in the profit', (t) async {
    await _open(t, _FakeMoney());

    expect(find.descendant(of: _k('spend_rent'), matching: find.text('TSH 20,000')), findsOneWidget);
    expect(_k('spend_transport'), findsOneWidget);
    expect(find.descendant(of: _k('spend_personal'), matching: find.text('TSH 7,000')), findsOneWidget);
    expect(find.text('Personal spending (not taken off the profit)'), findsOneWidget);
  });

  testWidgets('the products, customers, sleeping stock and debtors are named', (t) async {
    await _open(t, _FakeMoney());

    expect(_k('top_Soda'), findsOneWidget);
    expect(_k('cust_Mama Neema'), findsOneWidget);
    expect(_k('slow_Dusty Dye'), findsOneWidget);
    expect(_k('debtor_Baba Juma'), findsOneWidget);
  });

  group('the profit target', () {
    testWidgets('none yet: offered, and setting one sends the month and amount', (t) async {
      final _FakeMoney api = _FakeMoney();
      await _open(t, api);

      await t.tap(_k('target_set'));
      await t.pumpAndSettle();
      await t.enterText(_k('target_amount'), '2,000,000');
      await t.tap(_k('target_save'));
      await t.pumpAndSettle();

      expect(api.targets.single, ('2026-11', 2000000.0));
    });

    testWidgets('behind says so, with what is left and what it should be by today', (t) async {
      await _open(t, _FakeMoney(target: <String, dynamic>{'profit_target': 300000, 'profit': 120000, 'progress_percent': 40.0, 'left': 180000, 'over_by': 0, 'expected_by_today': 200000, 'days_left': 10, 'status': 'behind'}));

      expect(t.widget<Text>(_k('target_status')).data, 'Behind target');
      expect(t.widget<Text>(_k('target_numbers')).data, 'TSH 120K / TSH 300K');
      expect(find.textContaining('To go: TSH 180,000  ·  days 10  ·  By today you should have TSH 200,000'), findsOneWidget);
    });

    testWidgets('reached says so, and by how much it was passed', (t) async {
      await _open(t, _FakeMoney(target: <String, dynamic>{'profit_target': 100000, 'profit': 120000, 'progress_percent': 120.0, 'left': 0, 'over_by': 20000, 'expected_by_today': 70000, 'days_left': 10, 'status': 'reached'}));

      expect(t.widget<Text>(_k('target_status')).data, 'Target reached');
      expect(find.text('You are over the target by TSH 20,000.'), findsOneWidget);
    });

    testWidgets('a finished month that missed it says how short it fell, and offers no new target', (t) async {
      await _open(t, _FakeMoney(current: false, target: <String, dynamic>{'profit_target': 500000, 'profit': 120000, 'progress_percent': 24.0, 'left': 380000, 'over_by': 0, 'expected_by_today': 500000, 'days_left': 0, 'status': 'missed'}), month: '2026-10');

      expect(t.widget<Text>(_k('target_status')).data, 'Target missed');
      expect(find.text('You were short by TSH 380,000.'), findsOneWidget);
    });

    testWidgets('a finished month without a target shows no target card at all', (t) async {
      await _open(t, _FakeMoney(current: false), month: '2026-10');

      expect(_k('target_set'), findsNothing);
    });
  });

  group('where to improve', () {
    testWidgets('AI advice is marked AI, each item has its colour, and a fresh one can be asked for', (t) async {
      final _FakeMoney api = _FakeMoney(answer: _ai());
      await _open(t, api);

      expect(find.text('Where to improve'), findsOneWidget);
      expect(t.widget<Text>(_k('advice_source')).data, 'AI');
      expect(find.text('Collect from Baba Juma'), findsOneWidget);
      expect(find.text('Soda earned TSh 40,000.'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);

      await t.tap(_k('advice_refresh'));
      await t.pump();
      await t.pump();
      expect(api.adviceRefresh, <bool>[false, true]);
    });

    testWidgets('rule-based advice says "Rules", and says the AI was down when it was switched on but did not answer', (t) async {
      await _open(t, _FakeMoney(answer: <String, dynamic>{'items': <Map<String, dynamic>>[<String, dynamic>{'level': 'tip', 'title': 'Set a profit target', 'detail': 'x'}], 'source': 'rules', 'ai_available': true, 'refreshes_left': 5}));

      expect(t.widget<Text>(_k('advice_source')).data, 'Rules');
      expect(_k('advice_ai_down'), findsOneWidget);
    });

    testWidgets('no refresh is offered when none is left', (t) async {
      await _open(t, _FakeMoney(answer: <String, dynamic>{...(_ai()), 'refreshes_left': 0}));

      expect(t.widget<IconButton>(_k('advice_refresh')).onPressed, isNull);
    });
  });

  group('moving between months', () {
    testWidgets('the arrows load the month before, and the next one is limited to the month after this one', (t) async {
      final _FakeMoney api = _FakeMoney();
      await _open(t, api);

      await t.tap(_k('month_prev'));
      await t.pump();
      await t.pump();
      expect(find.text('October 2026'), findsOneWidget);
      expect(api.asked.last, '2026-10');
      await t.tap(_k('month_next'));
      await t.pump();
      await t.pump();
      expect(api.asked.last, '2026-11');
      expect(t.widget<IconButton>(_k('month_next')).onPressed, isNotNull, reason: 'the next month can be opened to set a target for it');
    });

    testWidgets('the month after the next one cannot be opened', (t) async {
      await _open(t, _FakeMoney(), month: '2026-12');

      expect(t.widget<IconButton>(_k('month_next')).onPressed, isNull);
    });

    testWidgets('across a year end', (t) async {
      final _FakeMoney api = _FakeMoney();
      await _open(t, api, month: '2026-01');

      await t.tap(_k('month_prev'));
      await t.pump();
      await t.pump();
      expect(api.asked.last, '2025-12');
      expect(find.text('December 2025'), findsOneWidget);
    });
  });

  testWidgets('a failed load says why instead of showing numbers', (t) async {
    await _open(t, _FakeMoney(failReport: true));

    expect(find.textContaining('No connection'), findsOneWidget);
    expect(_k('fig_net'), findsNothing);
  });

  group('the card on the dashboard', () {
    Future<void> card(WidgetTester t, MoneyApi api, {bool sw = false}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
      addTearDown(() => LocalizationService.instance.changeLanguage('en'));
      await t.pumpWidget(
        ChangeNotifierProvider<LocalizationService>.value(
          value: LocalizationService.instance,
          child: MaterialApp(home: Scaffold(body: MonthSummaryCard(api: api))),
        ),
      );
      await t.pump();
      await t.pump();
    }

    testWidgets('shows the profit, the trend against last month and the target bar', (t) async {
      await card(t, _FakeMoney(target: <String, dynamic>{'profit_target': 300000, 'profit': 120000, 'progress_percent': 40.0, 'left': 180000, 'over_by': 0, 'expected_by_today': 200000, 'days_left': 10, 'status': 'behind'}));

      expect(t.widget<Text>(_k('month_profit')).data, 'TSH 120,000');
      expect(t.widget<Text>(_k('month_trend')).data, '+50%');
      expect(find.text('Profit this month · ahead of last month'), findsOneWidget);
      expect(find.text('Target TSH 300K  ·  40%  ·  behind'), findsOneWidget);
    });

    testWidgets('down shows a minus; in Swahili it is Swahili', (t) async {
      await card(t, _FakeMoney(dir: 'down'), sw: true);

      expect(t.widget<Text>(_k('month_trend')).data, '-30%');
      expect(find.text('Faida ya mwezi huu · nyuma ya mwezi uliopita'), findsOneWidget);
    });

    testWidgets('a tap opens the whole report', (t) async {
      await card(t, _FakeMoney());

      await t.tap(_k('month_summary'));
      await t.pumpAndSettle();

      expect(find.text('Monthly report'), findsOneWidget);
    });

    testWidgets('when the numbers cannot be loaded the card is simply not there', (t) async {
      await card(t, _FakeMoney(failReport: true));

      expect(_k('month_summary'), findsNothing);
    });
  });

  test('month names and short money', () {
    expect(monthName('2026-03', sw: true), 'Machi 2026');
    expect(monthName('2026-12', sw: false), 'December 2026');
    expect(shortMoney(1250000), 'TSH 1.25M');
    expect(shortMoney(45000), 'TSH 45K');
    expect(shortMoney(9500), 'TSH 9,500');
    expect(shortMoney(-2000000), '-TSH 2M');
  });
}
