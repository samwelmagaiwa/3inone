import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/models/inv_sale.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/price_option_picker.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/staff_picker.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A service that comes at several prices (short, medium or long hair) asks which one when it is sold, and the sale
/// line carries that price and name; a service can say who may do it, and then only those people are offered for it.
class _Server extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{'data': <String, dynamic>{'inventory_type': 'retail', 'use_crates': '0', 'sale_tier': 'retail', 'prices_include_vat': '1', 'tax_percent': '0'}};
    }
    if (endpoint.startsWith('/inventory/salon/staff')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'u-asha', 'name': 'Asha', 'role': 'sales_officer'},
          <String, dynamic>{'id': 'u-bahati', 'name': 'Bahati', 'role': 'manager'},
        ],
      };
    }
    if (endpoint.startsWith('/inventory/products')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          _row(1, 'Braids', 40000, options: <Map<String, dynamic>>[<String, dynamic>{'label': 'Short', 'price': 30000}, <String, dynamic>{'label': 'Long', 'price': 60000}]),
          _row(2, 'Wash', 5000),
          _row(3, 'Bridal makeup', 150000, staff: <String>['u-bahati']),
        ],
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }

  static Map<String, dynamic> _row(int id, String name, num price, {List<Map<String, dynamic>>? options, List<String>? staff}) => <String, dynamic>{
        'id': id, 'name': name, 'sku': 'P-$id', 'cost_price': 0, 'selling_price': price, 'unit': 'pcs', 'quantity': 0, 'min_stock': 0,
        'status': 'active', 'is_service': true, 'units': <dynamic>[],
        'price_options': options ?? <dynamic>[], 'staff_ids': staff ?? <dynamic>[],
      };
}

InvProduct _p(InventoryProvider inv, int id) => inv.products.firstWhere((InvProduct p) => p.id == id);

Future<InventoryProvider> _load() async {
  final InventoryProvider inv = InventoryProvider(api: _Server());
  addTearDown(inv.dispose);
  await inv.fetchCapabilities();
  await inv.fetchProducts();
  await inv.fetchSalonStaff();
  return inv;
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _host(WidgetTester t, InventoryProvider inv, Widget Function(BuildContext) button) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(411, 1200),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: Scaffold(body: Builder(builder: (BuildContext c) => Center(child: button(c))))),
      ),
    ),
  );
}

void main() {
  test('what the server says about a service is read: its people and its other prices', () async {
    final InventoryProvider inv = await _load();

    expect(_p(inv, 1).priceOptions.map((PriceOption o) => (o.label, o.price)).toList(), <(String, double)>[('Short', 30000), ('Long', 60000)]);
    expect(_p(inv, 1).staffIds, isEmpty);
    expect(_p(inv, 3).staffIds, <String>['u-bahati']);
    expect(_p(inv, 2).priceOptions, isEmpty);
  });

  group('the cart', () {
    test('a service added with an option carries its price and name, and is a line of its own', () async {
      final InventoryProvider inv = await _load();
      final InvProduct braids = _p(inv, 1);

      inv.addProductToCart(braids, option: braids.priceOptions.last);
      inv.addProductToCart(braids, option: braids.priceOptions.first);
      inv.addProductToCart(braids); // the usual price

      expect(inv.cart.map((InvSaleItem i) => (i.name, i.unitPrice, i.optionLabel)).toList(), <(String, double, String?)>[
        ('Braids (Long)', 60000, 'Long'),
        ('Braids (Short)', 30000, 'Short'),
        ('Braids', 40000, null),
      ]);
      expect(inv.cart.every((InvSaleItem i) => i.productId == 1), isTrue);
    });

    test('the same option twice is one line with two of it', () async {
      final InventoryProvider inv = await _load();
      final InvProduct braids = _p(inv, 1);

      inv.addProductToCart(braids, option: braids.priceOptions.last);
      inv.addProductToCart(braids, option: braids.priceOptions.last);

      expect(inv.cart, hasLength(1));
      expect(inv.cart.single.qty, 2);
    });
  });

  group('asking which price', () {
    testWidgets('a service with other prices asks, and the choice goes in the cart', (t) async {
      final InventoryProvider inv = await _load();
      await _host(t, inv, (BuildContext c) => TextButton(key: const ValueKey<String>('add'), onPressed: () => addToCartAskingPrice(c, inv, _p(inv, 1)), child: const Text('add')));

      await t.tap(find.byKey(const ValueKey<String>('add')));
      await _settle(t);
      expect(find.text('Usual price'), findsOneWidget);
      expect(find.text('Short'), findsOneWidget);
      expect(find.text('Long'), findsOneWidget);
      expect(find.text('TSH 60,000'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey<String>('price_option_Long')));
      await _settle(t);

      expect(inv.cart.single.name, 'Braids (Long)');
      expect(inv.cart.single.unitPrice, 60000);
    });

    testWidgets('the usual price is one of the choices', (t) async {
      final InventoryProvider inv = await _load();
      await _host(t, inv, (BuildContext c) => TextButton(key: const ValueKey<String>('add'), onPressed: () => addToCartAskingPrice(c, inv, _p(inv, 1)), child: const Text('add')));

      await t.tap(find.byKey(const ValueKey<String>('add')));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey<String>('price_usual')));
      await _settle(t);

      expect(inv.cart.single.name, 'Braids');
      expect(inv.cart.single.unitPrice, 40000);
    });

    testWidgets('closing the sheet without choosing leaves the cart alone', (t) async {
      final InventoryProvider inv = await _load();
      bool? added;
      await _host(t, inv, (BuildContext c) => TextButton(key: const ValueKey<String>('add'), onPressed: () async => added = await addToCartAskingPrice(c, inv, _p(inv, 1)), child: const Text('add')));

      await t.tap(find.byKey(const ValueKey<String>('add')));
      await _settle(t);
      await t.tapAt(const Offset(200, 30));
      await _settle(t);

      expect(added, isFalse);
      expect(inv.cart, isEmpty);
    });

    testWidgets('a service with one price goes straight in, without asking', (t) async {
      final InventoryProvider inv = await _load();
      bool? added;
      await _host(t, inv, (BuildContext c) => TextButton(key: const ValueKey<String>('add'), onPressed: () async => added = await addToCartAskingPrice(c, inv, _p(inv, 2)), child: const Text('add')));

      await t.tap(find.byKey(const ValueKey<String>('add')));
      await _settle(t);

      expect(added, isTrue);
      expect(find.text('Usual price'), findsNothing);
      expect(inv.cart.single.name, 'Wash');
    });
  });

  group('who may do the service', () {
    Future<void> openFor(WidgetTester t, InventoryProvider inv, InvSaleItem line) async {
      await _host(t, inv, (BuildContext c) => TextButton(key: const ValueKey<String>('pick'), onPressed: () => pickStylist(c, line), child: const Text('pick')));
      await t.tap(find.byKey(const ValueKey<String>('pick')));
      await _settle(t);
    }

    testWidgets('a service that names nobody offers everyone', (t) async {
      final InventoryProvider inv = await _load();
      await openFor(t, inv, InvSaleItem(productId: 2, name: 'Wash', qty: 1, unitPrice: 5000, unitCostSnapshot: 0, isService: true));

      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Bahati'), findsOneWidget);
    });

    testWidgets('a service that names someone offers only them, and "nobody" is still there', (t) async {
      final InventoryProvider inv = await _load();
      await openFor(t, inv, InvSaleItem(productId: 3, name: 'Bridal makeup', qty: 1, unitPrice: 150000, unitCostSnapshot: 0, isService: true));

      expect(find.text('Asha'), findsNothing);
      expect(find.text('Bahati'), findsOneWidget);
      expect(find.text('Nobody (do not name a stylist)'), findsOneWidget);
    });
  });
}
