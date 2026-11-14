import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the app sends, and can refuse like the server does.
class _Api extends ApiService {
  final List<MapEntry<String, Map<String, dynamic>>> posts = <MapEntry<String, Map<String, dynamic>>>[];
  bool refuse = false;

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/products')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'name': 'Cola', 'sku': 'C', 'cost_price': 700, 'selling_price': 1000, 'unit': 'bottle', 'quantity': 100, 'min_stock': 0, 'status': 'active'},
        ],
      };
    }
    if (endpoint.startsWith('/inventory/kpis') || endpoint.startsWith('/inventory/sales/summary')) return <String, dynamic>{'data': <String, dynamic>{'today': <String, dynamic>{}}};
    return <String, dynamic>{'data': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    if (refuse) throw ApiException('Punguzo haliwezi kuzidi jumla ya mauzo. / The discount cannot be more than the sale total.');
    posts.add(MapEntry<String, Map<String, dynamic>>(endpoint, data));
    return <String, dynamic>{'data': <String, dynamic>{}};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a discount after the sale goes to the sale with its reason, and a refund names how it is given back', () async {
    final _Api api = _Api();
    final InventoryProvider inv = InventoryProvider(api: api);

    final String? error = await inv.discountSale(42, amount: 2000, reason: '  Goods did not satisfy  ', refundMethod: 'mpesa');

    expect(error, isNull);
    expect(api.posts.single.key, '/inventory/sales/42/discount');
    expect(api.posts.single.value, <String, dynamic>{'amount': 2000.0, 'reason': 'Goods did not satisfy', 'refund_method': 'mpesa'});
  });

  test('no refund method is sent when nothing is given back', () async {
    final _Api api = _Api();
    final InventoryProvider inv = InventoryProvider(api: api);

    await inv.discountSale(7, amount: 500, reason: 'Short on weight');

    expect(api.posts.single.value.containsKey('refund_method'), isFalse);
  });

  test('the server refusing comes back as its words, not as a crash', () async {
    final _Api api = _Api()..refuse = true;
    final InventoryProvider inv = InventoryProvider(api: api);

    final String? error = await inv.discountSale(42, amount: 999999, reason: 'too much');

    expect(error, isNotNull);
    expect(error, isNotEmpty);
  });

  test('the profit of the sale being booked is what the lines earn less the discount', () async {
    final InventoryProvider inv = InventoryProvider(api: _Api());
    await inv.fetchProducts();
    final InvProduct cola = inv.products.single;

    inv.addProductToCart(cola);
    inv.addProductToCart(cola);

    // 2 bottles: sold 2,000, cost 1,400
    expect(inv.cartProfit, 600);
    expect(inv.cartProfitAfterDiscount, 600, reason: 'no discount taken off yet');
  });
}
