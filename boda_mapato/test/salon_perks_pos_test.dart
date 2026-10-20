import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/salon_perks_card.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Perks at the till: a voucher, loyalty points and a package take money off (or make a line free) and ride along on the
/// sale; the discount sent is the typed one plus those, and the shop never sees any of it.
class _Api extends ApiService {
  final List<Map<String, dynamic>> sales = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    if (endpoint == '/inventory/sales') sales.add(data);
    return <String, dynamic>{'data': <String, dynamic>{'id': 1, 'number': 'S-1'}};
  }

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async => <String, dynamic>{'data': <dynamic>[]};
}

class _FakeSalon extends SalonApi {
  double voucherOff = 4000;
  Object? voucherFails;
  final List<double> asked = <double>[];
  Map<String, dynamic> loyalty = <String, dynamic>{'on': true, 'balance': 30, 'value': 100};
  List<Map<String, dynamic>> packages = <Map<String, dynamic>>[
    <String, dynamic>{'id': 9, 'name': '5 braids', 'service_product_id': 1, 'sessions_left': 2, 'usable': true},
  ];

  @override
  Future<double> voucherDiscount(String code, double subtotal) async {
    asked.add(subtotal);
    if (voucherFails != null) throw voucherFails!;
    return voucherOff;
  }

  @override
  Future<Map<String, dynamic>> clientLoyalty(int customerId) async => loyalty;

  @override
  Future<List<Map<String, dynamic>>> clientPackages(int customerId) async => packages;
}

InvProduct _braids() => InvProduct(id: 1, name: 'Braids', sku: 'B-1', category: '', costPrice: 0, sellingPrice: 40000, unit: 'pcs', quantity: 0, minStock: 0, status: 'active', barcode: '', createdBy: 1, isService: true);

InventoryProvider _inv({bool salon = true}) {
  final InventoryProvider inv = InventoryProvider(api: _Api());
  addTearDown(inv.dispose);
  addTearDown(() => ApiService.activeService = null);
  inv.setSalonMode(salon);
  inv.addProductToCart(_braids());

  return inv;
}

Future<void> _pump(WidgetTester t, InventoryProvider inv, _FakeSalon api) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(800, 2400), builder: (_, __) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SalonPerksCard(api: api))))),
    ),
  );
  await t.pump();
}

void main() {
  group('the cart', () {
    test('a voucher and points reduce the total together and never below nothing', () {
      final InventoryProvider inv = _inv();
      inv.setCartDiscount(1000);
      inv.setVoucher('welcome', 4000);
      inv.setRedeemPoints(10, 100);
      expect(inv.voucherCode, 'WELCOME');
      expect(inv.pointsOff, 1000);
      expect(inv.totalDiscount, 6000);
      expect(inv.cartTotal, 34000);

      inv.setRedeemPoints(100000, 100);
      expect(inv.totalDiscount, 40000, reason: 'never more than the sale');
      expect(inv.cartTotal, 0);
    });

    test('the shop ignores all of it', () {
      final InventoryProvider inv = _inv(salon: false);
      inv.setVoucher('X', 4000);
      inv.setRedeemPoints(10, 100);
      expect(inv.totalDiscount, 0);
      expect(inv.cartTotal, 40000);
    });

    test('a package makes the line free and can be undone; changing client drops points and packages', () {
      final InventoryProvider inv = _inv();
      final line = inv.cart.first;
      inv.setLinePackage(line, 9);
      expect(inv.cartTotal, 0);
      expect(line.packageId, 9);
      inv.setLinePackage(line, null);
      expect(inv.cartTotal, 40000);

      inv.setLinePackage(line, 9);
      inv.setRedeemPoints(5, 100);
      inv.setVoucher('KEEP', 1000);
      inv.setCustomer(5);
      expect(line.packageId, isNull);
      expect(inv.cartTotal, 39000, reason: 'back to its price, voucher kept, points gone');
      expect(inv.pointsUsed, 0);
    });

    test('the sale carries the voucher, points, package and a discount reason', () async {
      final _Api api = _Api();
      final InventoryProvider inv = InventoryProvider(api: api);
      addTearDown(inv.dispose);
      addTearDown(() => ApiService.activeService = null);
      inv.setSalonMode(true);
      inv.addProductToCart(_braids());
      inv.addProductToCart(_braids());
      inv.setVoucher('welcome', 4000);
      inv.setRedeemPoints(10, 100);
      await inv.checkout(createdBy: 1);

      final Map<String, dynamic> sent = api.sales.single;
      expect(sent['discount'], 5000);
      expect(sent['voucher_code'], 'WELCOME');
      expect(sent['redeem_points'], 10);
      expect(sent['discount_reason'], 'Voucher WELCOME + Loyalty points');
      expect(inv.voucherCode, '', reason: 'cleared after the sale');
    });
  });

  group('the till card', () {
    testWidgets('a voucher is checked with the server, shown, and removed', (t) async {
      final InventoryProvider inv = _inv();
      final _FakeSalon api = _FakeSalon();
      await _pump(t, inv, api);
      await t.enterText(find.byKey(const Key('salon_voucher')), 'welcome');
      await t.tap(find.byKey(const Key('salon_voucher_apply')));
      await t.pump();
      await t.pump();
      expect(api.asked.first, 40000);
      expect(find.text('WELCOME: -TSH 4,000'), findsOneWidget);
      expect(inv.cartTotal, 36000);

      await t.tap(find.byKey(const Key('salon_voucher_clear')));
      await t.pump();
      expect(inv.cartTotal, 40000);
      expect(find.byKey(const Key('salon_voucher')), findsOneWidget);
    });

    testWidgets('a refused voucher says why and takes nothing off', (t) async {
      final InventoryProvider inv = _inv();
      final _FakeSalon api = _FakeSalon()..voucherFails = Exception('Kuponi hii imeisha muda.');
      await _pump(t, inv, api);
      await t.enterText(find.byKey(const Key('salon_voucher')), 'old');
      await t.tap(find.byKey(const Key('salon_voucher_apply')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('imeisha muda'), findsOneWidget);
      expect(inv.cartTotal, 40000);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('after a client is chosen their points and packages appear; points cannot exceed the balance', (t) async {
      final InventoryProvider inv = _inv();
      final _FakeSalon api = _FakeSalon();
      await _pump(t, inv, api);
      expect(find.byKey(const Key('salon_points')), findsNothing);
      inv.setCustomer(5);
      await t.pump();
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('salon_points_balance')), findsOneWidget);

      await t.enterText(find.byKey(const Key('salon_points')), '500');
      await t.tap(find.byKey(const Key('salon_points_apply')));
      await t.pump();
      expect(inv.pointsUsed, 30);
      expect(find.text('-TSH 3,000'), findsOneWidget);

      await t.tap(find.byKey(const Key('salon_pkg_1')));
      await t.pump();
      expect(inv.cart.first.packageId, 9);
      expect(inv.cartSubtotal, 0);
    });

    testWidgets('a line with more visits than the package has left is refused', (t) async {
      final InventoryProvider inv = _inv();
      inv.addProductToCart(_braids());
      inv.addProductToCart(_braids());
      final _FakeSalon api = _FakeSalon();
      await _pump(t, inv, api);
      inv.setCustomer(5);
      await t.pump();
      await t.pump();
      await t.pump();
      await t.tap(find.byKey(const Key('salon_pkg_1')));
      await t.pump(const Duration(milliseconds: 300));
      expect(inv.cart.first.packageId, isNull);
      expect(find.textContaining('enough visits'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });
  });
}
