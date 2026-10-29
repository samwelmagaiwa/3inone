import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/hubs/sales_hub_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/payment_references_screen.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Sales menu button opens the sales hub: Sales | References | Returns & parked. The owner (anyone who may see reports) gets the
/// References tab, between Sales and Returns & parked; a sales officer does not.
class _FakeApi extends ApiService {
  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async => <String, dynamic>{'data': <String, dynamic>{}};

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async => <String, dynamic>{'data': <dynamic>[], 'meta': <String, dynamic>{'current_page': 1, 'last_page': 1}};

  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async => <String, dynamic>{'data': <dynamic>[], 'summary': <String, dynamic>{'count': 0, 'amount': 0}, 'meta': <String, dynamic>{'current_page': 1, 'last_page': 1}};
}

class _Who extends AuthProvider {
  _Who(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 'u1', name: 'Someone', email: 'u@example.test', role: role, isActive: true);

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

Future<void> _pump(WidgetTester t, String role, {bool sw = false}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final _FakeApi api = _FakeApi();
  final InventoryProvider inv = InventoryProvider(api: api);
  inv.setSalonMode(true);
  addTearDown(() => ApiService.activeService = null);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: api)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Who(role)),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => const MaterialApp(home: Scaffold(body: SalesHubScreen()))),
    ),
  );
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('the owner sees Sales, then References, then Returns & parked', (t) async {
    await _pump(t, 'admin');

    final double sales = t.getTopLeft(find.text('Sales').first).dx;
    final double references = t.getTopLeft(find.text('References')).dx;
    final double returns = t.getTopLeft(find.text('Returns & parked')).dx;
    expect(references, greaterThan(sales));
    expect(returns, greaterThan(references));
  });

  testWidgets('a tap on References opens the list of reference numbers', (t) async {
    await _pump(t, 'admin');

    await t.tap(find.text('References'));
    for (int i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }

    expect(find.byType(PaymentReferencesScreen), findsOneWidget);
  });

  testWidgets('the tab speaks Swahili', (t) async {
    await _pump(t, 'admin', sw: true);
    expect(find.text('Miamala'), findsOneWidget);
  });

  testWidgets('a sales officer, who may not see reports, has no References tab', (t) async {
    await _pump(t, 'sales_officer');

    expect(find.text('References'), findsNothing);
    expect(find.text('Returns & parked'), findsOneWidget);
  });
}
