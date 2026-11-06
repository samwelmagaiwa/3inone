import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/dashboard/inventory_dashboard_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/top_items_chart.dart';
import 'package:boda_mapato/modules/inventory/services/money_api.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Under the months of the dashboard's chart two small buttons choose the graph: sales day by day (the line) or what earned most this
/// month (coloured bars with a trend line).
class _Auth extends AuthProvider {
  @override
  UserData? get user => UserData(id: '1', name: 'Owner', email: 'o@example.test', role: 'admin', isActive: true, permissions: const <String>['inv_view_products', 'inv_view_reports', 'inv_create_sales']);
}

class _Inv extends InventoryProvider {
  @override
  Future<void> fetchKpis() async {}
}

class _Money extends MoneyApi {
  _Money({this.fail = false});

  final bool fail;
  final List<String?> asked = <String?>[];

  @override
  Future<Map<String, dynamic>> monthlyReport([final String? month]) async {
    asked.add(month);
    if (fail) throw Exception('no');

    return <String, dynamic>{
      'owner_figures': true,
      'top_products': <Map<String, dynamic>>[
        <String, dynamic>{'name': 'Box Braids', 'qty': 2, 'sales': 120000, 'profit': 100000},
        <String, dynamic>{'name': 'Senegalese Twist', 'qty': 1, 'sales': 70000, 'profit': 60000},
      ],
    };
  }
}

Future<void> _open(WidgetTester t, MoneyApi money) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  addTearDown(() {
    ApiService.activeBranch = null;
    ApiService.activeBranchName = null;
    ApiService.activeService = null;
  });
  t.view.physicalSize = const Size(411, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Inv inv = _Inv()..setSalonMode(true);
  await t.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider()),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(390, 844), minTextAdapt: true, builder: (_, __) => MaterialApp(home: Scaffold(body: InventoryDashboardScreen(moneyApi: money)))),
    ),
  );
  await t.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('the buttons beside the months switch between the sales line and the bars of what earned most', (t) async {
    final _Money money = _Money();
    await _open(t, money);

    expect(find.byKey(const ValueKey<String>('graph_toggle')), findsOneWidget);
    expect(find.byType(TopItemsChart), findsNothing, reason: 'the line is shown first');

    await t.ensureVisible(find.byKey(const ValueKey<String>('graph_bars')));
    await t.tap(find.byKey(const ValueKey<String>('graph_bars')));
    await t.pump(const Duration(milliseconds: 900));
    expect(find.byType(TopItemsChart), findsOneWidget);
    expect(find.text('Profit (TSH)'), findsOneWidget);
    expect(find.text('Trend line'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey<String>('graph_line')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(TopItemsChart), findsNothing);
    expect(money.asked.first, matches(RegExp(r'^\d{4}-\d{2}$')), reason: 'the report of a month');
  });

  testWidgets('without the monthly report (a person who may not read it) the choice of graph is not offered', (t) async {
    await _open(t, _Money(fail: true));

    expect(find.byKey(const ValueKey<String>('graph_toggle')), findsNothing);
  });
}
