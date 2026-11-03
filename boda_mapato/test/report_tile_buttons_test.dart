import 'package:boda_mapato/modules/inventory/models/inv_depot_models.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/reports/reports_screen.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The reports page: each report is a raised button with an arrow that says "open", and pressing it opens that report.
class _Api extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.contains('/reports') && !endpoint.contains('/reports/')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'key': 'daily_sales', 'title': 'Daily Sales'},
          <String, dynamic>{'key': 'sales_detail', 'title': 'Sales Detail'},
          <String, dynamic>{'key': 'stock_valuation', 'title': 'Stock Valuation'},
        ],
      };
    }

    return <String, dynamic>{'data': <dynamic>[]};
  }
}

void main() {
  testWidgets('every report is a button with an arrow, in rows of two divided by the glowing lines', (t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage('en');
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final DepotProvider depot = DepotProvider(api: _Api());
    await depot.fetchReports();
    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
          ChangeNotifierProvider<DepotProvider>.value(value: depot),
          ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ],
        child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => const MaterialApp(home: Scaffold(body: ReportsScreen()))),
      ),
    );
    await t.pump();
    await t.pump();

    for (final String k in <String>['daily_sales', 'sales_detail', 'stock_valuation']) {
      expect(find.byKey(ValueKey<String>('report_tile_$k')), findsOneWidget, reason: '$k is a button');
    }
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNWidgets(3), reason: 'each has its "open" arrow');
    expect(find.byKey(const ValueKey<String>('report_divider_1')), findsOneWidget, reason: 'three reports: two rows, one line between them');
    expect(find.byKey(const ValueKey<String>('report_divider_2')), findsNothing);
  });
}
