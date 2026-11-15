import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/sales/sales_screen.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// While a sale is being booked the owner of the shop or depot sees what it earns, before submitting: and nobody else does.
class _Api extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{'data': <String, dynamic>{'inventory_type': 'retail', 'use_crates': '0', 'sale_tier': 'retail', 'prices_include_vat': '1', 'tax_percent': '0'}};
    }
    if (endpoint.startsWith('/inventory/products')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'name': 'Cola', 'sku': 'C-1', 'cost_price': 700, 'selling_price': 1000, 'unit': 'bottle', 'quantity': 240, 'min_stock': 0, 'status': 'active'},
        ],
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

class _As extends AuthProvider {
  _As(this.role);

  final String role;

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);

  @override
  UserData? get user => UserData(id: '1', name: 'Test', email: 't@example.com', role: role, isActive: true);
}

Future<InventoryProvider> _pump(WidgetTester t, String role) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
  t.view.physicalSize = const Size(1170, 3200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  final _Api api = _Api();
  final InventoryProvider inv = InventoryProvider(api: api);
  await inv.fetchCapabilities();
  await inv.fetchProducts();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: api)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _As(role)),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => const MaterialApp(home: Scaffold(body: SalesScreen())),
      ),
    ),
  );
  await t.pumpAndSettle();
  return inv;
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));
String _shown(WidgetTester t, String k) => t.widget<Text>(_key(k)).data ?? '';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the owner sees the profit of the sale while booking it, and it follows the lines', (t) async {
    final InventoryProvider inv = await _pump(t, 'admin');
    final InvProduct cola = inv.products.single;

    expect(_key('cart_profit_row'), findsNothing, reason: 'nothing in the cart yet');

    inv.addProductToCart(cola);
    inv.addProductToCart(cola);
    await t.pumpAndSettle();

    // 2 bottles: sold 2,000, cost 1,400
    expect(_key('cart_profit_header'), findsOneWidget);
    expect(_shown(t, 'cart_profit_header'), contains('TZS 600'));
    expect(_key('cart_profit_row'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('cart_profit_value')), findsOneWidget);
    expect(_shown(t, 'cart_profit_value'), 'TZS 600');

    inv.addProductToCart(cola);
    await t.pumpAndSettle();
    expect(_shown(t, 'cart_profit_value'), 'TZS 900');
    expect(_shown(t, 'cart_profit_header'), contains('TZS 900'));
  });

  for (final String role in <String>['sales_officer', 'accountant', 'cashier', 'super_admin']) {
    testWidgets('$role never sees the profit', (t) async {
      final InventoryProvider inv = await _pump(t, role);
      inv.addProductToCart(inv.products.single);
      await t.pumpAndSettle();

      expect(_key('cart_profit_header'), findsNothing);
      expect(_key('cart_profit_row'), findsNothing);
    });
  }
}
