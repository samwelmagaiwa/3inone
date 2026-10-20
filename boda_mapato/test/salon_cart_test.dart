import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/models/inv_sale.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A salon sells services (no stock) next to goods, and says WHO served each service. These tests use canned
/// server answers: what the app reads for a service, what its cart does with one, and what it sends at checkout.
class _FakeApi extends ApiService {
  _FakeApi({this.staff = const <Map<String, dynamic>>[]});

  final List<Map<String, dynamic>> staff;
  final List<(String, Map<String, dynamic>)> posts = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{
        'data': <String, dynamic>{'inventory_type': 'retail', 'use_crates': '0', 'sale_tier': 'retail', 'prices_include_vat': '1', 'tax_percent': '0'},
      };
    }
    if (endpoint.startsWith('/inventory/products')) return <String, dynamic>{'data': _products};
    if (endpoint.startsWith('/inventory/salon/staff')) return <String, dynamic>{'data': staff};
    return <String, dynamic>{'data': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    posts.add((endpoint, data));
    return <String, dynamic>{'data': <String, dynamic>{'id': 1}};
  }
}

Map<String, dynamic> _row(int id, String name, num price, {num cost = 0, int quantity = 0, Object? isService, int? minutes, int? rebook}) => <String, dynamic>{
      'id': id,
      'name': name,
      'sku': 'P-$id',
      'cost_price': cost,
      'selling_price': price,
      'unit': 'pcs',
      'quantity': quantity,
      'min_stock': 0,
      'status': 'active',
      if (isService != null) 'is_service': isService,
      if (minutes != null) 'duration_minutes': minutes,
      if (rebook != null) 'rebook_after_weeks': rebook,
      'units': <dynamic>[],
    };

final List<Map<String, dynamic>> _products = <Map<String, dynamic>>[
  _row(1, 'Braids', 40000, isService: true, minutes: 180, rebook: 6),
  _row(2, 'Wash', 5000, isService: 1, minutes: 30),
  _row(3, 'Shampoo', 8000, cost: 3000, quantity: 20),
  _row(4, 'Oil', 6000, cost: 2000, quantity: 10, isService: false),
  _row(5, 'Conditioner', 7000, cost: 2500, quantity: 5, isService: '1'),
];

Future<InventoryProvider> _load({List<Map<String, dynamic>> staff = const <Map<String, dynamic>>[]}) async {
  final _FakeApi api = _FakeApi(staff: staff);
  final InventoryProvider inv = InventoryProvider(api: api);
  addTearDown(inv.dispose);
  await inv.fetchCapabilities();
  await inv.fetchProducts();

  return inv;
}

InvProduct _p(InventoryProvider inv, int id) => inv.products.firstWhere((InvProduct p) => p.id == id);

void main() {
  group('what the app reads for a service', () {
    test('a service says it is one, how long it takes and when to bring the client back', () async {
      final InventoryProvider inv = await _load();

      final InvProduct braids = _p(inv, 1);
      expect(braids.isService, isTrue);
      expect(braids.durationMinutes, 180);
      expect(braids.rebookAfterWeeks, 6);
      expect(_p(inv, 2).rebookAfterWeeks, isNull, reason: 'none given: the salon\'s own number applies');
    });

    test('the server may say it as true, 1 or "1"; anything else, or nothing, is goods', () async {
      final InventoryProvider inv = await _load();

      expect(_p(inv, 2).isService, isTrue, reason: '1');
      expect(_p(inv, 5).isService, isTrue, reason: '"1"');
      expect(_p(inv, 3).isService, isFalse, reason: 'not said at all');
      expect(_p(inv, 4).isService, isFalse, reason: 'false');
    });
  });

  group('the cart', () {
    test('a service carries no cost of goods and is marked as a service; goods keep their cost', () async {
      final InventoryProvider inv = await _load();

      inv.addProductToCart(_p(inv, 1));
      inv.addProductToCart(_p(inv, 3));

      final InvSaleItem braids = inv.cart.firstWhere((InvSaleItem i) => i.productId == 1);
      final InvSaleItem shampoo = inv.cart.firstWhere((InvSaleItem i) => i.productId == 3);
      expect(braids.isService, isTrue);
      expect(braids.unitCostSnapshot, 0);
      expect(braids.profit, 40000, reason: 'a service is all profit');
      expect(shampoo.isService, isFalse);
      expect(shampoo.unitCostSnapshot, 3000);
    });

    test('the stylist picked for one service is offered again for the next service, never for goods', () async {
      final InventoryProvider inv = await _load();
      inv.addProductToCart(_p(inv, 1));
      inv.setCartStaff(inv.cart.first, 'u-asha', 'Asha');

      inv.addProductToCart(_p(inv, 2)); // another service
      inv.addProductToCart(_p(inv, 3)); // goods

      expect(inv.cart.firstWhere((InvSaleItem i) => i.productId == 2).staffId, 'u-asha');
      expect(inv.cart.firstWhere((InvSaleItem i) => i.productId == 2).staffName, 'Asha');
      expect(inv.cart.firstWhere((InvSaleItem i) => i.productId == 3).staffId, isNull, reason: 'shampoo is not served by anyone');
    });

    test('changing the stylist on one line changes it for that line only, and becomes the next offer', () async {
      final InventoryProvider inv = await _load();
      inv.addProductToCart(_p(inv, 1));
      inv.addProductToCart(_p(inv, 2));
      final InvSaleItem first = inv.cart[0];
      final InvSaleItem second = inv.cart[1];

      inv.setCartStaff(first, 'u-asha', 'Asha');
      inv.setCartStaff(second, 'u-bahati', 'Bahati');

      expect(first.staffName, 'Asha');
      expect(second.staffName, 'Bahati');
    });

    test('"nobody" clears the line and the offer', () async {
      final InventoryProvider inv = await _load();
      inv.addProductToCart(_p(inv, 1));
      inv.setCartStaff(inv.cart.first, 'u-asha', 'Asha');
      inv.setCartStaff(inv.cart.first, null, null);

      inv.addProductToCart(_p(inv, 2));

      expect(inv.cart.first.staffId, isNull);
      expect(inv.cart[1].staffId, isNull, reason: 'nobody is offered again');
    });

    test('a new client starts with nobody picked: emptying the cart forgets who served', () async {
      final InventoryProvider inv = await _load();
      inv.addProductToCart(_p(inv, 1));
      inv.setCartStaff(inv.cart.first, 'u-asha', 'Asha');

      inv.clearCart();
      inv.addProductToCart(_p(inv, 2));

      expect(inv.cart.single.staffId, isNull);
    });

    test('adding the same service again is one line with two, still served by the same person', () async {
      final InventoryProvider inv = await _load();
      inv.addProductToCart(_p(inv, 2));
      inv.setCartStaff(inv.cart.first, 'u-asha', 'Asha');

      inv.addProductToCart(_p(inv, 2));

      expect(inv.cart, hasLength(1));
      expect(inv.cart.single.qty, 2);
      expect(inv.cart.single.staffId, 'u-asha');
    });
  });

  group('checkout', () {
    test('sends who served each service line, and nothing for goods or lines nobody was named for', () async {
      final _FakeApi api = _FakeApi();
      final InventoryProvider inv = InventoryProvider(api: api);
      addTearDown(inv.dispose);
      await inv.fetchProducts();
      inv.addProductToCart(_p(inv, 1));
      inv.setCartStaff(inv.cart.first, 'u-asha', 'Asha');
      inv.addProductToCart(_p(inv, 3));
      inv.addProductToCart(_p(inv, 5)); // a service, but the stylist chosen is offered, so name nobody here
      inv.setCartStaff(inv.cart.firstWhere((InvSaleItem i) => i.productId == 5), null, null);

      final (bool ok, String _) = await inv.checkout(createdBy: 1);

      expect(ok, isTrue);
      final Map<String, dynamic> body = api.posts.single.$2;
      expect(api.posts.single.$1, '/inventory/sales');
      final List<Map<String, dynamic>> items = (body['items'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(items.firstWhere((Map<String, dynamic> i) => i['product_id'] == 1)['staff_id'], 'u-asha');
      expect(items.firstWhere((Map<String, dynamic> i) => i['product_id'] == 3).containsKey('staff_id'), isFalse);
      expect(items.firstWhere((Map<String, dynamic> i) => i['product_id'] == 5).containsKey('staff_id'), isFalse);
      expect(items.firstWhere((Map<String, dynamic> i) => i['product_id'] == 1)['unit_cost_snapshot'], 0, reason: 'a service carries no cost of goods');
    });

    test('after a sale the next client starts with nobody picked', () async {
      final InventoryProvider inv = await _load();
      inv.addProductToCart(_p(inv, 1));
      inv.setCartStaff(inv.cart.first, 'u-asha', 'Asha');
      await inv.checkout(createdBy: 1);

      inv.addProductToCart(_p(inv, 2));

      expect(inv.cart.single.staffId, isNull);
    });
  });

  group('who can serve', () {
    test('the salon\'s people are read from the server', () async {
      final InventoryProvider inv = await _load(staff: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'u-1', 'name': 'Asha', 'role': 'admin'},
        <String, dynamic>{'id': 'u-2', 'name': 'Bahati', 'role': 'sales_officer'},
      ]);

      await inv.fetchSalonStaff();

      expect(inv.salonStaff.map((Map<String, String> s) => s['name']).toList(), <String>['Asha', 'Bahati']);
      expect(inv.salonStaff.first['id'], 'u-1');
    });

    test('a failed read keeps what was there', () async {
      final InventoryProvider inv = await _load(staff: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'u-1', 'name': 'Asha', 'role': 'admin'},
      ]);
      await inv.fetchSalonStaff();

      final InventoryProvider other = InventoryProvider(api: _Failing());
      addTearDown(other.dispose);
      await other.fetchSalonStaff();

      expect(inv.salonStaff, hasLength(1));
      expect(other.salonStaff, isEmpty);
    });
  });

  group('salon mode', () {
    test('is off until the salon\'s home says so, and tells listeners when it changes', () async {
      final InventoryProvider inv = await _load();
      int told = 0;
      inv.addListener(() => told++);

      expect(inv.salonMode, isFalse);
      inv.setSalonMode(true);
      inv.setSalonMode(true); // no change: nobody is told twice
      expect(inv.salonMode, isTrue);
      expect(told, 1);
      inv.setSalonMode(false);
      expect(inv.salonMode, isFalse);
      expect(told, 2);
    });
  });
}

class _Failing extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async => throw ApiException('offline');
}
