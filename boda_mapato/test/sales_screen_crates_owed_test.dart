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

/// Canned answers instead of a server. Remembers every save the app attempts.
class _FakeApi extends ApiService {
  final List<String> posts = <String>[];

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data,
      {bool requireAuth = true}) async {
    posts.add(endpoint);
    return <String, dynamic>{
      'data': <String, dynamic>{'id': 1, 'number': 'S-TEST-1'}
    };
  }

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint,
      {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/customers')) {
      return <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'id': 2, 'name': 'mama anna', 'phone': '0783510498'},
          <String, dynamic>{'id': 5, 'name': 'Baba John', 'phone': '0711000111'},
        ],
      };
    }
    if (endpoint.startsWith('/inventory/crate-balances')) {
      return <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{
            'customer_id': 2, 'customer_name': 'mama anna',
            'crate_type_id': 1, 'crate_type_name': 'Crate',
            'held': 10, 'deposit_at_risk': 20000,
          },
        ],
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

/// A signed-in user who may sell and manage customers.
class _SellerAuth extends AuthProvider {
  @override
  UserPermissions get permissions => UserPermissions.fromRole('admin');
}

late _FakeApi _api;

/// Flutter's test font draws every letter as a wide square, so rows that fit on a phone
/// "overflow" here. Those warnings say nothing about the real app, so they are ignored;
/// every other error still fails the test.
void _ignoreTestFontOverflow() {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<InventoryProvider> _pump(WidgetTester t) async {
  _ignoreTestFontOverflow();
  _api = _FakeApi();
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  final InventoryProvider inv = InventoryProvider(api: _api);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(
            create: (_) => DepotProvider(api: _FakeApi())),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _SellerAuth()),
        ChangeNotifierProvider<LocalizationService>.value(
            value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) =>
            const MaterialApp(home: Scaffold(body: SalesScreen())),
      ),
    ),
  );
  await t.pumpAndSettle();
  await inv.fetchCustomers();
  await t.pumpAndSettle();
  return inv;
}

void main() {
  const String note = 'Makreti anayodaiwa: 10 × Crate (dhamana TZS 20000)';

  testWidgets('picking a customer who holds crates shows the note', (t) async {
    final InventoryProvider inv = await _pump(t);

    inv.setPaymentMode('debt');
    inv.setCustomer(2); // mama anna
    await t.pumpAndSettle();

    expect(find.text(note), findsOneWidget);
  });

  testWidgets('picking a customer who holds none shows no note', (t) async {
    final InventoryProvider inv = await _pump(t);

    inv.setPaymentMode('debt');
    inv.setCustomer(5); // Baba John
    await t.pumpAndSettle();

    expect(find.text(note), findsNothing);
  });

  testWidgets('in a salon the same customer shows no crate note: a salon has no crates', (t) async {
    final InventoryProvider inv = await _pump(t);

    inv.setSalonMode(true);
    inv.setPaymentMode('debt');
    inv.setCustomer(2);
    await t.pumpAndSettle();

    expect(find.text(note), findsNothing);
    expect(find.text('Ongeza huduma au bidhaa'), findsOneWidget);
  });

  testWidgets('a cash sale has no customer picked, so no note', (t) async {
    final InventoryProvider inv = await _pump(t);

    inv.setPaymentMode('cash');
    inv.setCustomer(2);
    await t.pumpAndSettle();

    expect(find.text(note), findsNothing);
  });

  group('checkout asks for confirmation first', () {
    final InvProduct pepsi = InvProduct(
      id: 7, name: 'Pepsi 300ml', sku: 'COC-PEP-PCS', category: 'Soda',
      costPrice: 9000, sellingPrice: 11200, unit: 'crate', quantity: 100,
      minStock: 5, status: 'active', barcode: '', createdBy: 1,
    );

    Future<InventoryProvider> readyToCheckout(WidgetTester t) async {
      final InventoryProvider inv = await _pump(t);
      inv.addProductToCart(pepsi);
      inv.addProductToCart(pepsi);
      await t.pumpAndSettle();
      return inv;
    }

    Future<void> tapCheckout(WidgetTester t) async {
      final Finder button =
          find.widgetWithIcon(ElevatedButton, Icons.payments_outlined);
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pumpAndSettle();
    }

    testWidgets('the card shows the amount, and No sends nothing', (t) async {
      await readyToCheckout(t);
      await tapCheckout(t);

      expect(find.text('Thibitisha mauzo'), findsOneWidget);
      expect(find.text('TZS 22400'), findsWidgets); // 2 x 11200
      expect(_api.posts, isEmpty);

      await t.tap(find.byKey(const ValueKey<String>('sale_confirm_no')));
      await t.pumpAndSettle();

      expect(find.text('Thibitisha mauzo'), findsNothing);
      expect(_api.posts, isEmpty, reason: 'No must not record a sale');
    });

    testWidgets('Yes records the sale', (t) async {
      await readyToCheckout(t);
      await tapCheckout(t);

      await t.tap(find.byKey(const ValueKey<String>('sale_confirm_yes')));
      await t.pumpAndSettle();

      expect(_api.posts, contains('/inventory/sales'));

      // Let the success banner's auto-dismiss timer run out before the test ends.
      await t.pump(const Duration(seconds: 10));
      await t.pumpAndSettle();
    });

    testWidgets('owing crates without choosing a type is stopped before the card',
        (t) async {
      await readyToCheckout(t);
      await t.tap(find.byType(Switch)); // the customer did NOT bring crates
      await t.pumpAndSettle();
      await tapCheckout(t);

      expect(find.text('Thibitisha mauzo'), findsNothing);
      expect(_api.posts, isEmpty);

      // Let the warning banner's auto-dismiss timer run out before the test ends.
      await t.pump(const Duration(seconds: 10));
      await t.pumpAndSettle();
    });
  });
}
