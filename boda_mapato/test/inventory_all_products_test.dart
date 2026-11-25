import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A server that pages like the real one: the newest first, `per_page` to a page (100 at most, 20 when not asked), with `meta.last_page`.
class _PagedApi extends ApiService {
  _PagedApi({required this.products, this.customers = 0, this.failOnPage});

  final int products;
  final int customers;

  /// The page (of the products) that fails, to see what a weak connection leaves.
  final int? failOnPage;
  final List<String> asked = <String>[];

  Map<String, dynamic> _page(final String endpoint, final int total, final Map<String, dynamic> Function(int id) row) {
    final Uri u = Uri.parse(endpoint);
    final int page = int.tryParse(u.queryParameters['page'] ?? '1') ?? 1;
    final int per = (int.tryParse(u.queryParameters['per_page'] ?? '') ?? 20).clamp(1, 100);
    final int last = total == 0 ? 1 : (total / per).ceil();
    // ids total .. 1, the newest first
    final List<Map<String, dynamic>> data = <Map<String, dynamic>>[
      for (int i = (page - 1) * per; i < page * per && i < total; i++) row(total - i),
    ];
    return <String, dynamic>{'data': data, 'meta': <String, dynamic>{'current_page': page, 'last_page': last, 'per_page': per, 'total': total}};
  }

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    asked.add(endpoint);
    if (endpoint.startsWith('/inventory/products')) {
      if (failOnPage != null && endpoint.contains('page=$failOnPage&')) return null;
      return _page(endpoint, products, (int id) => <String, dynamic>{
            'id': id, 'name': id == 35 ? 'medium tembo' : 'Product $id', 'sku': 'SKU-$id', 'cost_price': 100, 'selling_price': 150, 'quantity': 5, 'min_stock': 1, 'status': 'active',
          });
    }
    if (endpoint.startsWith('/inventory/customers')) {
      return _page(endpoint, customers, (int id) => <String, dynamic>{'id': id, 'name': 'Customer $id', 'phone': '07130000$id'});
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

InvProduct _p(final int id, final String name) => InvProduct(id: id, name: name, sku: 'S$id', category: '', costPrice: 1, sellingPrice: 2, unit: 'pcs', quantity: 1, minStock: 1, status: 'active', barcode: '', createdBy: 0);

void main() {
  test('products and services are listed A to Z by name, capitals and stray spaces ignored, the same name older first', () {
    final List<InvProduct> sorted = InventoryProvider.alphabetical(<InvProduct>[
      _p(5, 'kucha'), _p(2, 'Bangili'), _p(7, '  Cheni'), _p(3, 'bangili'), _p(9, 'Zeze'), _p(1, 'afro wig'), _p(8, 'Rasta'), _p(6, '027 sunflower'),
    ]);
    expect(sorted.map((InvProduct p) => p.name.trim()).toList(), <String>['027 sunflower', 'afro wig', 'Bangili', 'bangili', 'Cheni', 'kucha', 'Rasta', 'Zeze']);
    expect(sorted[2].id, 2, reason: 'the same name: the older (smaller id) first');
    expect(sorted[3].id, 3);
  });

  test('after the pages are read the whole list is alphabetical, even when the server gave it newest first (an older server)', () async {
    final InventoryProvider inv = InventoryProvider(api: _PagedApi(products: 250));
    await inv.fetchProducts();
    final List<String> names = inv.products.map((p) => p.name.toLowerCase()).toList();
    final List<String> sorted = List<String>.of(names)..sort();
    expect(names, sorted);
    expect(inv.products.length, 250);
    inv.dispose();
  });

  test('a shop with more than a page of products has ALL of them in the app, the old ones too (the slow sellers saved long ago)', () async {
    final _PagedApi api = _PagedApi(products: 250);
    final InventoryProvider inv = InventoryProvider(api: api);
    await inv.fetchProducts();

    expect(inv.products.length, 250, reason: 'three pages of 100, 100 and 50 are all read');
    expect(inv.products.any((p) => p.name == 'medium tembo'), isTrue, reason: 'the product saved long ago is not left out');
    expect(inv.products.first.name, 'medium tembo', reason: 'A to Z: the name that comes first in the alphabet is first, whatever its age');
    expect(inv.products.map((p) => p.id).toSet().length, 250, reason: 'none twice');
    final List<String> asked = api.asked.where((String e) => e.startsWith('/inventory/products')).toList();
    expect(asked.length, 3);
    expect(asked.every((String e) => e.contains('per_page=100')), isTrue);
    inv.dispose();
  });

  test('the customer who failed to appear at the till is there too: every page of customers is read', () async {
    final _PagedApi api = _PagedApi(products: 0, customers: 130);
    final InventoryProvider inv = InventoryProvider(api: api);
    await inv.fetchCustomers();
    expect(inv.customers.length, 130);
    expect(inv.customers.last.id, 1, reason: 'the oldest customer is on the list');
    inv.dispose();
  });

  test('a small shop still takes one request, and an empty shop has an empty list', () async {
    final _PagedApi api = _PagedApi(products: 12);
    final InventoryProvider inv = InventoryProvider(api: api);
    await inv.fetchProducts();
    expect(inv.products.length, 12);
    expect(api.asked.where((String e) => e.startsWith('/inventory/products')).length, 1);

    final InventoryProvider empty = InventoryProvider(api: _PagedApi(products: 0));
    await empty.fetchProducts();
    expect(empty.products, isEmpty);
    inv.dispose();
    empty.dispose();
  });

  test('when a later page cannot be read (a weak connection) what was read stays, instead of an empty or half-replaced list', () async {
    final InventoryProvider inv = InventoryProvider(api: _PagedApi(products: 250, failOnPage: 3));
    await inv.fetchProducts();
    expect(inv.products.length, 200, reason: 'pages 1 and 2 were read');
    inv.dispose();
  });

  test('a newer read has the last word: an older slow one never overwrites it', () async {
    final InventoryProvider inv = InventoryProvider(api: _PagedApi(products: 250));
    final Future<void> first = inv.fetchProducts();
    final Future<void> second = inv.fetchProducts();
    await Future.wait(<Future<void>>[first, second]);
    expect(inv.products.length, 250);
    expect(inv.products.map((p) => p.id).toSet().length, 250, reason: 'no product twice from two reads running together');
    inv.dispose();
  });
}
