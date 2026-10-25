import 'package:boda_mapato/modules/inventory/models/inv_sale.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/goods_used_sheet.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/price_option_picker.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A salon service put in the cart opens the list of goods: it starts from what the service usually uses, the person
/// changes it for this visit, and the sale carries exactly that. Goods and services are linked through the sale line.
class _Server extends ApiService {
  static bool noGoods = false;

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{'data': <String, dynamic>{'inventory_type': 'retail', 'use_crates': '0', 'sale_tier': 'retail', 'prices_include_vat': '1', 'tax_percent': '0'}};
    }
    if (endpoint.startsWith('/inventory/products')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          _row(1, 'Braids', 40000, service: true),
          if (!noGoods) _row(2, 'Shampoo', 8000, cost: 3000),
          if (!noGoods) _row(3, 'Dye', 12000, cost: 5000),
        ],
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }

  static Map<String, dynamic> _row(int id, String name, num price, {bool service = false, num cost = 0}) => <String, dynamic>{
        'id': id, 'name': name, 'sku': 'P-$id', 'cost_price': cost, 'selling_price': price, 'unit': 'pcs', 'quantity': 20, 'min_stock': 0,
        'status': 'active', 'is_service': service, 'units': <dynamic>[], 'price_options': <dynamic>[], 'staff_ids': <dynamic>[],
      };
}

class _Salon extends SalonApi {
  @override
  Future<List<Map<String, dynamic>>> usualGoods(int serviceId) async => <Map<String, dynamic>>[
        <String, dynamic>{'product_id': 2, 'name': 'Shampoo', 'quantity': 2},
      ];
}

Future<InventoryProvider> _open(WidgetTester t) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  addTearDown(() => ApiService.activeService = null);
  addTearDown(() => _Server.noGoods = false);
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final InventoryProvider inv = InventoryProvider(api: _Server())..setSalonMode(true);
  addTearDown(inv.dispose);
  await inv.fetchCapabilities();
  await inv.fetchProducts();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext c) => TextButton(
                key: const ValueKey<String>('add'),
                onPressed: () => addToCartAskingPrice(c, inv, inv.products.firstWhere((p) => p.id == 1), api: _Salon()),
                child: const Text('add'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const ValueKey<String>('add')));
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }

  return inv;
}

Finder _k(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('adding a service opens the goods, starting from the usual ones, with their cost', (t) async {
    final InventoryProvider inv = await _open(t);

    expect(inv.cart.single.name, 'Braids');
    expect(find.text('Goods used: Braids'), findsOneWidget);
    expect(find.descendant(of: _k('good_2'), matching: find.text('2')), findsOneWidget, reason: 'shampoo x2 is the usual');
    expect(_k('good_3'), findsNothing, reason: 'dye is not used until it is selected');
    expect(find.descendant(of: _k('goods_cost'), matching: find.textContaining('TSH 6,000')), findsNothing);
    expect(find.text('Cost of the goods: TSH 6,000'), findsOneWidget);
  });

  testWidgets('what is chosen goes onto the line and into the sale', (t) async {
    final InventoryProvider inv = await _open(t);

    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Dye').last);
    await t.pumpAndSettle();
    await t.tap(_k('good_plus_3'));
    await t.tap(_k('good_minus_2'));
    await t.pump();
    expect(find.text('Cost of the goods: TSH 13,000'), findsOneWidget, reason: '2 dye at 5,000 + 1 shampoo at 3,000');
    await t.tap(_k('goods_save'));
    for (int i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }

    final InvSaleItem line = inv.cart.single;
    expect(<String>[for (final InvUsedGood g in line.usedGoods!) '${g.name}x${g.qty}'], <String>['Shampoox1', 'Dyex2']);
    expect(usedGoodsSummary(line.usedGoods, sw: false), 'Goods: Shampoo ×1, Dye ×2');
  });

  testWidgets('choosing nothing is allowed: no goods were used', (t) async {
    final InventoryProvider inv = await _open(t);

    await t.tap(_k('good_minus_2'));
    await t.tap(_k('good_minus_2'));
    await t.tap(_k('goods_save'));
    for (int i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }

    expect(inv.cart.single.usedGoods, isEmpty);
    expect(usedGoodsSummary(inv.cart.single.usedGoods, sw: true), 'Bidhaa: hakuna');
  });

  testWidgets('with no goods at all the sheet offers to add some', (t) async {
    _Server.noGoods = true;
    await _open(t);

    expect(find.text('No goods yet.'), findsOneWidget);
    expect(_k('goods_add_first'), findsOneWidget);
  });

  test('a line nobody picked for says "the usual"', () {
    expect(usedGoodsSummary(null, sw: false), 'Goods: the usual');
  });
}
