import 'package:boda_mapato/modules/inventory/screens/sales/sales_by_category_screen.dart';
import 'package:boda_mapato/modules/inventory/services/money_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Sales "By category" page: the period, each category's goods and services with subtotals, the totals; profit for the owner, sales for anyone else.
class _Fake extends MoneyApi {
  _Fake({this.owner = true, this.empty = false, this.fail = false});

  final bool owner;
  final bool empty;
  final bool fail;
  final List<(String, String)> asked = <(String, String)>[];

  @override
  Future<Map<String, dynamic>> salesByCategory(String from, String to) async {
    asked.add((from, to));
    if (fail) throw Exception('No connection');
    if (empty) return <String, dynamic>{'from': from, 'to': to, 'owner_figures': owner, 'categories': <dynamic>[], 'totals': <String, dynamic>{}};
    Map<String, dynamic> part(num sales, num profit, List<Map<String, dynamic>> items) => <String, dynamic>{'qty': 1, 'sales': sales, 'cost': sales - profit, 'profit': owner ? profit : 0, 'margin_percent': null, 'items': items};
    Map<String, dynamic> item(String n, num q, num s, num p, [List<Map<String, dynamic>>? m]) => <String, dynamic>{'name': n, 'qty': q, 'sales': s, 'cost': s - p, 'profit': owner ? p : 0, if (m != null) 'materials': m};

    return <String, dynamic>{
      'from': from, 'to': to, 'owner_figures': owner,
      'categories': <Map<String, dynamic>>[
        <String, dynamic>{
          'category': 'Nywele',
          'goods': part(20000, 8000, <Map<String, dynamic>>[item('Shampoo', 4, 20000, 8000)]),
          'services': part(110000, 90000, <Map<String, dynamic>>[
            item('Knotless', 2, 110000, 90000, <Map<String, dynamic>>[<String, dynamic>{'name': 'Gel', 'qty': 2, 'cost': 20000}]),
          ]),
          'total': <String, dynamic>{'sales': 130000, 'cost': 32000, 'profit': owner ? 98000 : 0, 'margin_percent': 75},
        },
      ],
      'totals': <String, dynamic>{
        'goods': <String, dynamic>{'sales': 20000, 'profit': owner ? 8000 : 0},
        'services': <String, dynamic>{'sales': 110000, 'profit': owner ? 90000 : 0},
        'all': <String, dynamic>{'sales': 130000, 'profit': owner ? 98000 : 0},
      },
    };
  }
}

Future<void> _open(WidgetTester t, MoneyApi api, {bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(800, 3000), builder: (_, __) => MaterialApp(home: SalesByCategoryScreen(api: api, today: DateTime(2026, 11, 20)))),
    ),
  );
  await t.pump();
  await t.pump();
  await t.pump();
}

Finder _k(String k) => find.byKey(Key(k));

void main() {
  testWidgets('asks for this month so far and shows the category total, opened with subtotals and totals', (t) async {
    final _Fake api = _Fake();
    await _open(t, api);

    expect(api.asked, <(String, String)>[('2026-11-01', '2026-11-20')]);
    expect(find.text('Profit by category'), findsOneWidget);
    expect((t.widget(_k('cat_total_Nywele')) as Text).data, 'TSH 98,000');

    await t.tap(_k('cat_block_Nywele'));
    await t.pumpAndSettle();
    expect((t.widget(_k('sub_goods_Nywele')).runtimeType), isNotNull);
    expect(find.text('TSH 8,000'), findsWidgets);
    expect(find.text('TSH 90,000'), findsWidgets);
    expect(find.textContaining('Gel ×2'), findsOneWidget);
    expect(find.text('Total: all'), findsOneWidget);
    expect(find.text('TSH 98,000'), findsWidgets);
  });

  testWidgets('someone who may not see profit sees only what was sold', (t) async {
    await _open(t, _Fake(owner: false));

    expect(find.text('Sales by category'), findsWidgets);
    expect(find.text('Profit by category'), findsNothing);
    expect((t.widget(_k('cat_total_Nywele')) as Text).data, 'TSH 130,000');
  });

  testWidgets('a period with nothing sold says so', (t) async {
    await _open(t, _Fake(empty: true));
    expect(_k('cat_empty'), findsOneWidget);
  });

  testWidgets('a failed load shows the problem', (t) async {
    await _open(t, _Fake(fail: true));
    expect(_k('cat_error'), findsOneWidget);
  });

  testWidgets('in Swahili', (t) async {
    await _open(t, _Fake(), sw: true);
    expect(find.text('Faida kwa kundi'), findsOneWidget);
    await t.tap(_k('cat_block_Nywele'));
    await t.pumpAndSettle();
    expect(find.text('Jumla yote'), findsOneWidget);
    expect(find.text('Jumla ndogo ya huduma'), findsOneWidget);
  });
}
