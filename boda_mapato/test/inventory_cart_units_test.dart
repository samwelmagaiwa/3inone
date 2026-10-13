import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/models/inv_product_unit.dart';
import 'package:boda_mapato/modules/inventory/models/inv_sale.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

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

Map<String, dynamic> _price(int id, int unitId, String tier, num price, {int? customerId}) => <String, dynamic>{
      'id': id,
      'product_unit_id': unitId,
      'tier': tier,
      'price': price,
      if (customerId != null) 'customer_id': customerId,
    };

Map<String, dynamic> _unit(int id, String name, int factor, {bool base = false, String status = 'active', List<Map<String, dynamic>> prices = const <Map<String, dynamic>>[]}) =>
    <String, dynamic>{'id': id, 'name': name, 'factor': factor, 'is_base': base, 'status': status, 'prices': prices};

/// Cola: 1,000 a bottle, a crate of 24 at 22,000 retail / 20,000 wholesale, and a switched-off "tray".
Map<String, dynamic> _cola({Object? tax}) => <String, dynamic>{
      'id': 1,
      'name': 'Cola',
      'sku': 'C-1',
      'cost_price': 700,
      'selling_price': 1000,
      'unit': 'bottle',
      'quantity': 240,
      'min_stock': 0,
      'status': 'active',
      'tax_percent': tax,
      'units': <Map<String, dynamic>>[
        _unit(10, 'bottle', 1, base: true, prices: <Map<String, dynamic>>[_price(1, 10, 'retail', 1000)]),
        _unit(11, 'crate', 24, prices: <Map<String, dynamic>>[
          _price(2, 11, 'retail', 22000),
          _price(3, 11, 'wholesale', 20000),
          _price(4, 11, 'special', 19000, customerId: 5),
        ]),
        _unit(12, 'tray', 6, status: 'inactive', prices: <Map<String, dynamic>>[_price(5, 12, 'retail', 5500)]),
      ],
    };

/// Sugar, kept in grams (2.2 a gram) and sold by the kilogram at 2,200.
Map<String, dynamic> _sugar() => <String, dynamic>{
      'id': 2,
      'name': 'Sugar',
      'sku': 'S-1',
      'cost_price': 1.5,
      'selling_price': 2.2,
      'unit': 'g',
      'quantity': 50000,
      'min_stock': 0,
      'status': 'active',
      'measure': 'weight',
      'units': <Map<String, dynamic>>[
        _unit(20, 'g', 1, base: true),
        _unit(21, 'kg', 1000, prices: <Map<String, dynamic>>[_price(6, 21, 'retail', 2200), _price(7, 21, 'wholesale', 2000)]),
      ],
    };

const Map<String, dynamic> _retailSettings = <String, dynamic>{
  'inventory_type': 'retail',
  'use_crates': '0',
  'sale_tier': 'retail',
  'prices_include_vat': '1',
  'tax_percent': '0',
};

Future<InventoryProvider> _load(Map<String, dynamic> settings, List<Map<String, dynamic>> products) async {
  final InventoryProvider inv = InventoryProvider(api: _FakeApi(settings, products));
  await inv.fetchCapabilities();
  await inv.fetchProducts();
  return inv;
}

InvProduct _product(InventoryProvider inv, int id) => inv.products.firstWhere((InvProduct p) => p.id == id);
InvProductUnit _unitOf(InventoryProvider inv, int productId, String name) =>
    inv.unitsOf(productId).firstWhere((InvProductUnit u) => u.name == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a depot sells the way it always has', () {
    test('a bottle is the product\'s own price and a crate is its own line', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{}, <Map<String, dynamic>>[_cola()]);
      final InvProduct cola = _product(inv, 1);

      inv.addProductToCart(cola);
      inv.addProductToCart(cola, unit: _unitOf(inv, 1, 'crate'));

      expect(inv.cart, hasLength(2), reason: '1 bottle and 1 crate are two lines');
      expect(inv.cart[0].unitPrice, 1000);
      expect(inv.cart[0].unitName, isNull);
      expect(inv.cart[1].unitPrice, 22000);
      expect(inv.cart[1].unitName, 'crate');
      expect(inv.cart[1].baseQty, 24, reason: 'a crate takes 24 bottles out of stock');
      expect(inv.cartSubtotal, 23000);
      expect(inv.cartTotal, 23000);
      expect(inv.cartTax, 0);
    });

    test('adding the same product and unit again raises the count', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{}, <Map<String, dynamic>>[_cola()]);
      final InvProduct cola = _product(inv, 1);

      inv.addProductToCart(cola);
      inv.addProductToCart(cola);
      inv.addProductToCart(cola, unit: _unitOf(inv, 1, 'crate'));
      inv.addProductToCart(cola, unit: _unitOf(inv, 1, 'crate'));

      expect(inv.cart, hasLength(2));
      expect(inv.cart[0].qty, 2);
      expect(inv.cart[1].qty, 2);
      expect(inv.cart[1].baseQty, 48);
    });

    test('a depot is not on price levels, so its tier stays retail', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{}, <Map<String, dynamic>>[_cola()]);
      expect(inv.capabilities.isDepot, isTrue);
      expect(inv.capabilities.usesPriceLevels, isFalse);
      expect(inv.cartTier, 'retail');
    });

    test('moving a line to another unit re-prices it and merges with a line already in that unit', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{}, <Map<String, dynamic>>[_cola()]);
      final InvProduct cola = _product(inv, 1);
      final InvProductUnit crate = _unitOf(inv, 1, 'crate');

      inv.addProductToCart(cola);
      inv.addProductToCart(cola, unit: crate);
      inv.changeCartUnit(inv.cart[0], crate);

      expect(inv.cart, hasLength(1), reason: 'both are crates now');
      expect(inv.cart.single.qty, 2);
      expect(inv.cart.single.unitPrice, 22000);
    });

    test('a count can never drop below one, and a price never below zero', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{}, <Map<String, dynamic>>[_cola()]);
      inv.addProductToCart(_product(inv, 1));
      inv.setCartQty(inv.cart.single, 0);
      expect(inv.cart.single.qty, 1);
      inv.setCartQty(inv.cart.single, -4);
      expect(inv.cart.single.qty, 1);
      inv.setCartUnitPrice(inv.cart.single, -50);
      expect(inv.cart.single.unitPrice, 0);
    });

    test('switched-off units are not offered', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{}, <Map<String, dynamic>>[_cola()]);
      expect(inv.activeUnitsOf(1).map((InvProductUnit u) => u.name), <String>['bottle', 'crate']);
      expect(inv.hasChoiceOfUnits(1), isTrue);
    });

    test('clearing the cart empties it and forgets a chosen price level', () async {
      final InventoryProvider inv = await _load(_retailSettings, <Map<String, dynamic>>[_cola()]);
      inv.addProductToCart(_product(inv, 1));
      inv.setCartTier('wholesale');
      expect(inv.cartTier, 'wholesale');
      inv.clearCart();
      expect(inv.cart, isEmpty);
      expect(inv.cartTier, 'retail');
    });
  });

  group('price levels', () {
    test('a retail shop rings up the retail price', () async {
      final InventoryProvider inv = await _load(_retailSettings, <Map<String, dynamic>>[_cola()]);
      inv.addProductToCart(_product(inv, 1), unit: _unitOf(inv, 1, 'crate'));
      expect(inv.cart.single.unitPrice, 22000);
    });

    test('a wholesaler rings up the wholesale price, and falls back to retail where there is none', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{..._retailSettings, 'inventory_type': 'wholesale', 'sale_tier': 'wholesale'}, <Map<String, dynamic>>[_cola()]);
      expect(inv.cartTier, 'wholesale');
      inv.addProductToCart(_product(inv, 1), unit: _unitOf(inv, 1, 'crate'));
      inv.addProductToCart(_product(inv, 1));
      expect(inv.cart[0].unitPrice, 20000);
      expect(inv.cart[1].unitPrice, 1000, reason: 'the bottle has only a retail price');
    });

    test('the cashier can switch the whole cart between levels and every line is priced again', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{..._retailSettings, 'inventory_type': 'mixed'}, <Map<String, dynamic>>[_cola()]);
      inv.addProductToCart(_product(inv, 1), unit: _unitOf(inv, 1, 'crate'));
      expect(inv.cart.single.unitPrice, 22000);

      inv.setCartTier('wholesale');
      expect(inv.cart.single.unitPrice, 20000);

      inv.setCartTier('retail');
      expect(inv.cart.single.unitPrice, 22000);
    });

    test('a price typed by hand is replaced when the level is switched', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{..._retailSettings, 'inventory_type': 'mixed'}, <Map<String, dynamic>>[_cola()]);
      inv.addProductToCart(_product(inv, 1), unit: _unitOf(inv, 1, 'crate'));
      inv.setCartUnitPrice(inv.cart.single, 21000);
      expect(inv.cart.single.unitPrice, 21000);
      inv.setCartTier('wholesale');
      expect(inv.cart.single.unitPrice, 20000);
    });

    test('a customer\'s special price beats both levels', () async {
      final InventoryProvider inv = await _load(_retailSettings, <Map<String, dynamic>>[_cola()]);
      final InvProduct cola = _product(inv, 1);
      final InvProductUnit crate = _unitOf(inv, 1, 'crate');

      expect(inv.unitPriceFor(cola, crate, customerId: 5), 19000);
      expect(inv.unitPriceFor(cola, crate, customerId: 6), 22000, reason: 'another customer pays the level\'s price');
      expect(inv.unitPriceFor(cola, crate, tier: 'wholesale'), 20000);
    });

    test('a unit with no price yet is the base price times what it holds', () async {
      final InventoryProvider inv = await _load(_retailSettings, <Map<String, dynamic>>[
        <String, dynamic>{
          ..._cola(),
          'units': <Map<String, dynamic>>[_unit(10, 'bottle', 1, base: true), _unit(13, 'dozen', 12)],
        },
      ]);
      expect(inv.unitPriceFor(_product(inv, 1), _unitOf(inv, 1, 'dozen')), 12000);
    });
  });

  group('VAT', () {
    test('with no rate anywhere there is no VAT', () async {
      final InventoryProvider inv = await _load(_retailSettings, <Map<String, dynamic>>[_cola()]);
      inv.addProductToCart(_product(inv, 1));
      expect(inv.cartTax, 0);
      expect(inv.cart.single.taxPercent, 0);
    });

    test('the business default applies to a product with no rate of its own; prices include it', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{..._retailSettings, 'tax_percent': '18'}, <Map<String, dynamic>>[_cola()]);
      inv.addProductToCart(_product(inv, 1));

      expect(inv.cart.single.taxPercent, 18);
      expect(inv.cartTax, 152.54, reason: '1,000 x 18/118');
      expect(inv.cartTotal, 1000, reason: 'the price already contains the VAT');
    });

    test('a product\'s own rate beats the default, and 0 is exempt', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{..._retailSettings, 'tax_percent': '18'}, <Map<String, dynamic>>[
        _cola(tax: 0),
        <String, dynamic>{..._sugar(), 'tax_percent': 16},
      ]);
      inv.addProductToCart(_product(inv, 1));
      expect(inv.cartTax, 0, reason: 'cola is exempt');

      inv.addProductToCart(_product(inv, 2));
      expect(inv.cart.last.taxPercent, 16);
      expect(inv.cartTax, closeTo(2200 * 16 / 116, 0.01));
    });

    test('when prices exclude VAT it is added on top of the total', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{..._retailSettings, 'tax_percent': '18', 'prices_include_vat': '0'}, <Map<String, dynamic>>[_cola()]);
      inv.addProductToCart(_product(inv, 1));

      expect(inv.cartTax, 180);
      expect(inv.cartSubtotal, 1000);
      expect(inv.cartTotal, 1180);
    });

    test('VAT follows the count and the unit', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{..._retailSettings, 'tax_percent': '18', 'prices_include_vat': '0'}, <Map<String, dynamic>>[_cola()]);
      inv.addProductToCart(_product(inv, 1), unit: _unitOf(inv, 1, 'crate'));
      inv.setCartQty(inv.cart.single, 3);
      expect(inv.cartSubtotal, 66000);
      expect(inv.cartTax, 11880);
      expect(inv.cartTotal, 77880);

      inv.setCartTier('wholesale');
      expect(inv.cartSubtotal, 60000);
      expect(inv.cartTax, 10800);
    });

    test('line tax is rounded to whole cents', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{..._retailSettings, 'tax_percent': '18'}, <Map<String, dynamic>>[_cola()]);
      inv.addProductToCart(_product(inv, 1));
      final double tax = inv.cart.single.taxAmount;
      expect((tax * 100).roundToDouble(), tax * 100);
    });
  });

  group('goods by weight', () {
    test('start on the kilogram, at its price', () async {
      final InventoryProvider inv = await _load(_retailSettings, <Map<String, dynamic>>[_sugar()]);
      inv.addProductToCart(_product(inv, 2));

      final InvSaleItem line = inv.cart.single;
      expect(line.unitName, 'kg');
      expect(line.unitPrice, 2200);
      expect(line.baseQty, 1000, reason: '1 kg takes 1,000 g out of stock');
      expect(line.qty, isA<int>());
    });

    test('can be sold in grams instead, priced per gram', () async {
      final InventoryProvider inv = await _load(_retailSettings, <Map<String, dynamic>>[_sugar()]);
      inv.addProductToCart(_product(inv, 2));
      inv.changeCartUnit(inv.cart.single, _unitOf(inv, 2, 'g'));
      inv.setCartQty(inv.cart.single, 250);

      final InvSaleItem line = inv.cart.single;
      expect(line.unitName, isNull, reason: 'the base unit is the product\'s own');
      expect(line.unitPrice, 2.2);
      expect(line.baseQty, 250);
      expect(line.total, closeTo(550, 0.001));
    });

    test('a kilogram and 250 g of the same sugar are two lines', () async {
      final InventoryProvider inv = await _load(_retailSettings, <Map<String, dynamic>>[_sugar()]);
      final InvProduct sugar = _product(inv, 2);
      inv.addProductToCart(sugar);
      inv.addProductToCart(sugar, unit: _unitOf(inv, 2, 'g'));
      inv.setCartQty(inv.cart.last, 250);

      expect(inv.cart, hasLength(2));
      expect(inv.cart.fold<int>(0, (int s, InvSaleItem i) => s + i.baseQty), 1250);
    });

    test('the wholesale level prices the kilogram at wholesale', () async {
      final InventoryProvider inv = await _load(<String, dynamic>{..._retailSettings, 'inventory_type': 'mixed'}, <Map<String, dynamic>>[_sugar()]);
      inv.addProductToCart(_product(inv, 2));
      inv.setCartTier('wholesale');
      expect(inv.cart.single.unitPrice, 2000);
    });
  });

  group('sale items', () {
    test('the key tells a product apart by unit', () {
      final InvSaleItem a = InvSaleItem(productId: 1, name: 'x', qty: 1, unitPrice: 1, unitCostSnapshot: 1);
      final InvSaleItem b = InvSaleItem(productId: 1, name: 'x', qty: 1, unitPrice: 1, unitCostSnapshot: 1, unitId: 11, unitFactor: 24);
      expect(a.key, '1:0');
      expect(b.key, '1:11');
    });

    test('total is per selling unit but profit is worked out in base units', () {
      final InvSaleItem crate = InvSaleItem(productId: 1, name: 'Cola', qty: 2, unitPrice: 22000, unitCostSnapshot: 700, unitId: 11, unitFactor: 24);
      expect(crate.total, 44000);
      expect(crate.baseQty, 48);
      expect(crate.profit, 44000 - 700 * 48);
    });

    test('a factor below one is treated as one', () {
      final InvSaleItem odd = InvSaleItem(productId: 1, name: 'x', qty: 3, unitPrice: 10, unitCostSnapshot: 4, unitFactor: 0);
      expect(odd.baseQty, 3);
    });
  });
}
