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
import 'package:shared_preferences/shared_preferences.dart';

/// A salon's sale: a discount that says why, and how the client paid (cash, M-Pesa, Mixx by Yas, Airtel Money,
/// HaloPesa, bank). The shop's sale is untouched: no discount, a full payment is cash.
class _FakeApi extends ApiService {
  final List<Map<String, dynamic>> sales = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    if (endpoint == '/inventory/sales') sales.add(data);
    return <String, dynamic>{'data': <String, dynamic>{'id': 1, 'number': 'S-TEST-1'}};
  }

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async => <String, dynamic>{'data': <dynamic>[]};
}

class _Seller extends AuthProvider {
  @override
  UserPermissions get permissions => UserPermissions.fromRole('admin');
}

late _FakeApi _api;

InvProduct _braids() => InvProduct(id: 1, name: 'Braids', sku: 'B-1', category: '', costPrice: 0, sellingPrice: 40000, unit: 'pcs', quantity: 0, minStock: 0, status: 'active', barcode: '', createdBy: 1, isService: true);

Future<InventoryProvider> _pump(WidgetTester t, {required bool salon, bool sw = false}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  _api = _FakeApi();
  t.view.physicalSize = const Size(1170, 3400);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  final InventoryProvider inv = InventoryProvider(api: _api);
  inv.setSalonMode(salon);
  addTearDown(() => ApiService.activeService = null);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: _api)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Seller()),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => const MaterialApp(home: Scaffold(body: SalesScreen())),
      ),
    ),
  );
  await t.pumpAndSettle();
  inv.addProductToCart(_braids());
  await t.pumpAndSettle();
  return inv;
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<void> _checkout(WidgetTester t) async {
  final Finder button = find.widgetWithIcon(ElevatedButton, Icons.payments_outlined);
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
}

Future<void> _confirmYes(WidgetTester t) async {
  await t.tap(_key('sale_confirm_yes'));
  await t.pumpAndSettle();
  await t.pump(const Duration(seconds: 10));
  await t.pumpAndSettle();
}

void main() {
  group('the cart', () {
    test('only a salon can give a discount; it never goes below nothing or above the sale', () {
      final InventoryProvider inv = InventoryProvider(api: _FakeApi());
      addTearDown(inv.dispose);
      addTearDown(() => ApiService.activeService = null);
      inv.addProductToCart(_braids());

      inv.setCartDiscount(5000);
      expect(inv.cartDiscount, 0, reason: 'the shop has no discount');
      expect(inv.cartTotal, 40000);

      inv.setSalonMode(true);
      expect(inv.cartDiscount, 5000);
      expect(inv.cartTotal, 35000);
      inv.setCartDiscount(99999);
      expect(inv.cartDiscount, 40000, reason: 'never more than the sale');
      expect(inv.cartTotal, 0);
      inv.setCartDiscount(-5);
      expect(inv.cartDiscount, 0);
    });

    test('emptying the cart takes the discount and its reason away', () {
      final InventoryProvider inv = InventoryProvider(api: _FakeApi());
      addTearDown(inv.dispose);
      addTearDown(() => ApiService.activeService = null);
      inv.setSalonMode(true);
      inv.addProductToCart(_braids());
      inv.setCartDiscount(5000);
      inv.setDiscountReason('Regular client');

      inv.clearCart();

      expect(inv.cartDiscount, 0);
      expect(inv.discountReason, '');
    });
  });

  group('the salon\'s sale screen', () {
    testWidgets('has the discount and "paid by" card, and a shop does not', (t) async {
      await _pump(t, salon: true);
      expect(_key('salon_money_card'), findsOneWidget);
      expect(find.text('Paid by'), findsOneWidget);
      for (final String c in <String>['cash', 'mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer']) {
        expect(_key('channel_$c'), findsOneWidget, reason: c);
      }
      expect(find.text('Mixx by Yas'), findsOneWidget);
    });

    testWidgets('a shop\'s sale screen is as it was: no discount card, no channels', (t) async {
      await _pump(t, salon: false);

      expect(_key('salon_money_card'), findsNothing);
      expect(find.text('Paid by'), findsNothing);
    });

    testWidgets('a discount asks why, shows on the total, and a sale without the reason is not sent', (t) async {
      final InventoryProvider inv = await _pump(t, salon: true);
      expect(_key('salon_discount_reason'), findsNothing, reason: 'no discount, nothing to explain');

      await t.enterText(_key('salon_discount'), '4000');
      await t.pumpAndSettle();
      expect(_key('salon_discount_reason'), findsOneWidget);
      expect(find.text('- TZS 4000'), findsOneWidget);
      expect(inv.cartTotal, 36000);

      await _checkout(t);
      expect(find.text('Write the reason for the discount.'), findsOneWidget);
      expect(_api.sales, isEmpty);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('with the reason and M-Pesa chosen, the sale carries both', (t) async {
      await _pump(t, salon: true);
      await t.enterText(_key('salon_discount'), '4000');
      await t.pumpAndSettle();
      await t.enterText(_key('salon_discount_reason'), 'Regular client');
      await t.tap(_key('channel_mpesa'));
      await t.pumpAndSettle();

      await _checkout(t);
      await _confirmYes(t);

      final Map<String, dynamic> sale = _api.sales.single;
      expect(sale['discount'], 4000);
      expect(sale['discount_reason'], 'Regular client');
      expect(sale['total'], 36000);
      expect((sale['payments'] as List<dynamic>).single, containsPair('method', 'mpesa'));
      expect((sale['payments'] as List<dynamic>).single, containsPair('amount', 36000));
    });

    testWidgets('with no discount and no choice the client paid cash, as before', (t) async {
      await _pump(t, salon: true);

      await _checkout(t);
      await _confirmYes(t);

      final Map<String, dynamic> sale = _api.sales.single;
      expect(sale['discount'], 0);
      expect(sale.containsKey('discount_reason'), isFalse);
      expect((sale['payments'] as List<dynamic>).single, containsPair('method', 'cash'));
    });

    testWidgets('a part payment names its channel too', (t) async {
      final InventoryProvider inv = await _pump(t, salon: true);
      inv.setPaymentMode('partial');
      inv.setPaidAmount(10000);
      await t.pumpAndSettle();
      await t.ensureVisible(_key('channel_halopesa'));
      await t.tap(_key('channel_halopesa'));
      await t.pumpAndSettle();

      expect(inv.partialPaymentMethod, 'halopesa');
      expect(find.byType(DropdownButtonFormField<String>), findsNothing, reason: 'the chips replace the shop\'s list');
    });

    testWidgets('a shop sale still says cash, whatever a salon chose before', (t) async {
      final InventoryProvider inv = await _pump(t, salon: true);
      inv.setCashChannel('mpesa');
      inv.setSalonMode(false);
      await t.pumpAndSettle();

      await _checkout(t);
      await _confirmYes(t);

      expect((_api.sales.single['payments'] as List<dynamic>).single, containsPair('method', 'cash'));
    });

    testWidgets('in Swahili the card is Swahili', (t) async {
      await _pump(t, salon: true, sw: true);

      expect(find.text('Punguzo'), findsOneWidget);
      expect(find.text('Amelipa kwa'), findsOneWidget);
      expect(find.text('Taslimu'), findsOneWidget);
      expect(find.text('Benki'), findsOneWidget);
    });
  });
}
