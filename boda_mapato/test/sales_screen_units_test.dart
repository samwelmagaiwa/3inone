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

/// Canned answers instead of a server: the business's settings and its products with their selling units.
class _FakeApi extends ApiService {
  _FakeApi(this.settings, this.products);

  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> products;

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) return <String, dynamic>{'data': settings};
    if (endpoint.startsWith('/inventory/products')) return <String, dynamic>{'data': products};
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

class _SellerAuth extends AuthProvider {
  @override
  UserPermissions get permissions => UserPermissions.fromRole('admin');
}

Map<String, dynamic> _price(int id, int unitId, String tier, num price) =>
    <String, dynamic>{'id': id, 'product_unit_id': unitId, 'tier': tier, 'price': price};

Map<String, dynamic> _cola() => <String, dynamic>{
      'id': 1,
      'name': 'Cola',
      'sku': 'C-1',
      'cost_price': 700,
      'selling_price': 1000,
      'unit': 'bottle',
      'quantity': 240,
      'min_stock': 0,
      'status': 'active',
      'units': <Map<String, dynamic>>[
        <String, dynamic>{'id': 10, 'name': 'bottle', 'factor': 1, 'is_base': true, 'status': 'active', 'prices': <Map<String, dynamic>>[_price(1, 10, 'retail', 1000)]},
        <String, dynamic>{
          'id': 11,
          'name': 'crate',
          'factor': 24,
          'is_base': false,
          'status': 'active',
          'prices': <Map<String, dynamic>>[_price(2, 11, 'retail', 22000), _price(3, 11, 'wholesale', 20000)],
        },
      ],
    };

const Map<String, dynamic> _shop = <String, dynamic>{
  'inventory_type': 'mixed',
  'use_crates': '0',
  'sale_tier': 'retail',
  'prices_include_vat': '1',
  'tax_percent': '0',
};

void _ignoreTestFontOverflow() {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<InventoryProvider> _pump(WidgetTester t, Map<String, dynamic> settings, {List<Map<String, dynamic>>? products}) async {
  _ignoreTestFontOverflow();
  t.view.physicalSize = const Size(1170, 3200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  final _FakeApi api = _FakeApi(settings, products ?? <Map<String, dynamic>>[_cola()]);
  final InventoryProvider inv = InventoryProvider(api: api);
  await inv.fetchCapabilities();
  await inv.fetchProducts();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: api)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _SellerAuth()),
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
InvProduct _cola0(InventoryProvider inv) => inv.products.firstWhere((InvProduct p) => p.id == 1);

void main() {
  group('the till sells in the unit the customer asks for', () {
    testWidgets('a product with a crate and a bottle shows both as chips, and the crate re-prices the line', (t) async {
      final InventoryProvider inv = await _pump(t, _shop);
      inv.addProductToCart(_cola0(inv));
      await t.pumpAndSettle();

      expect(_key('unit_chip_10'), findsOneWidget);
      expect(_key('unit_chip_11'), findsOneWidget);
      expect(inv.cart.single.unitPrice, 1000);

      await t.ensureVisible(_key('unit_chip_11'));
      await t.tap(_key('unit_chip_11'));
      await t.pumpAndSettle();

      expect(inv.cart.single.unitName, 'crate');
      expect(inv.cart.single.unitPrice, 22000);
      expect(find.textContaining('@ TZS 22000 / crate'), findsOneWidget);
    });

    testWidgets('a product with one way to be sold shows no chips', (t) async {
      final Map<String, dynamic> single = <String, dynamic>{
        ..._cola(),
        'units': <Map<String, dynamic>>[
          <String, dynamic>{'id': 10, 'name': 'bottle', 'factor': 1, 'is_base': true, 'status': 'active', 'prices': <Map<String, dynamic>>[]},
        ],
      };
      final InventoryProvider inv = await _pump(t, _shop, products: <Map<String, dynamic>>[single]);
      inv.addProductToCart(_cola0(inv));
      await t.pumpAndSettle();

      expect(inv.cart, hasLength(1));
      expect(_key('unit_chip_10'), findsNothing);
    });
  });

  group('retail and wholesale prices', () {
    testWidgets('a business on price levels sees the two chips and the wholesale one re-prices the cart', (t) async {
      final InventoryProvider inv = await _pump(t, _shop);
      inv.addProductToCart(_cola0(inv), unit: inv.unitsOf(1).firstWhere((u) => u.name == 'crate'));
      await t.pumpAndSettle();

      expect(_key('tier_retail'), findsOneWidget);
      expect(_key('tier_wholesale'), findsOneWidget);
      expect(t.widget<ChoiceChip>(_key('tier_retail')).selected, isTrue);

      await t.ensureVisible(_key('tier_wholesale'));
      await t.tap(_key('tier_wholesale'));
      await t.pumpAndSettle();

      expect(inv.cartTier, 'wholesale');
      expect(inv.cart.single.unitPrice, 20000);
      expect(t.widget<ChoiceChip>(_key('tier_wholesale')).selected, isTrue);
    });

    testWidgets('a depot prices by product and is not shown the chips', (t) async {
      final InventoryProvider inv = await _pump(t, <String, dynamic>{});
      inv.addProductToCart(_cola0(inv));
      await t.pumpAndSettle();

      expect(_key('tier_retail'), findsNothing);
      expect(_key('tier_wholesale'), findsNothing);
    });
  });

  group('VAT on the till', () {
    testWidgets('nothing is shown when no VAT applies', (t) async {
      final InventoryProvider inv = await _pump(t, _shop);
      inv.addProductToCart(_cola0(inv));
      await t.pumpAndSettle();

      expect(_key('cart_vat_row'), findsNothing);
      expect(_key('cart_vat_1:0'), findsNothing);
    });

    testWidgets('the share inside the price is shown on the line and in the totals', (t) async {
      final InventoryProvider inv = await _pump(t, <String, dynamic>{..._shop, 'tax_percent': '18'});
      inv.addProductToCart(_cola0(inv));
      await t.pumpAndSettle();

      expect(_key('cart_vat_row'), findsOneWidget);
      expect(find.textContaining('VAT (ndani ya bei)'), findsOneWidget);
      expect(find.textContaining('VAT 18%'), findsOneWidget);
      expect(find.text('TZS 153'), findsWidgets, reason: '1,000 x 18/118 rounded for display');
    });

    testWidgets('when prices exclude VAT the total includes it', (t) async {
      final InventoryProvider inv = await _pump(t, <String, dynamic>{..._shop, 'tax_percent': '18', 'prices_include_vat': '0'});
      inv.addProductToCart(_cola0(inv));
      await t.pumpAndSettle();

      expect(inv.cartTotal, 1180);
      expect(find.textContaining('VAT (ndani ya bei)'), findsNothing);
      expect(find.text('TZS 1180'), findsWidgets);
    });
  });

  group('quantities are whole numbers', () {
    testWidgets('tapping the count opens a box that takes digits only', (t) async {
      final InventoryProvider inv = await _pump(t, _shop);
      inv.addProductToCart(_cola0(inv));
      await t.pumpAndSettle();

      await t.ensureVisible(_key('cart_qty_1:0'));
      await t.tap(_key('cart_qty_1:0'));
      await t.pumpAndSettle();

      await t.enterText(_key('whole_number_field'), '2.5');
      await t.pump();
      final EditableText typed = t.widget<EditableText>(find.descendant(of: _key('whole_number_field'), matching: find.byType(EditableText)));
      expect(typed.controller.text, '25', reason: 'the dot never gets in');

      await t.enterText(_key('whole_number_field'), '12');
      await t.tap(_key('whole_number_ok'));
      await t.pumpAndSettle();

      expect(inv.cart.single.qty, 12);
      expect(inv.cart.single.qty, isA<int>());
    });

    testWidgets('typing zero leaves the count alone', (t) async {
      final InventoryProvider inv = await _pump(t, _shop);
      inv.addProductToCart(_cola0(inv));
      await t.pumpAndSettle();

      await t.ensureVisible(_key('cart_qty_1:0'));
      await t.tap(_key('cart_qty_1:0'));
      await t.pumpAndSettle();
      await t.enterText(_key('whole_number_field'), '0');
      await t.tap(_key('whole_number_ok'));
      await t.pumpAndSettle();

      expect(inv.cart.single.qty, 1);
    });
  });
}
