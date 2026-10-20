import 'dart:convert';

import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/http_client.dart' as app_http;
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as base;
import 'package:shared_preferences/shared_preferences.dart';

/// A sale for more than is in stock is refused by the server (422 `insufficient_stock`). The seller has to READ why:
/// "Kili Water: 200 in stock, 300 asked for". The server also sends the same facts as data, in `errors.items`, and
/// the app used to take the first thing under `errors` as the message: a sale refusal read like a dump of the data
/// ("{product_id: 7, product_name: Kili Water, ...}"). These tests use the exact answer the live server gives.

const String _sentence = 'Stock haitoshi kwa Kili Water: zilizopo 200, unazouza 300. / Not enough stock for Kili Water: 200 available, 300 requested.';

/// What `SalesController::store` answers when the cart asks for more than the shelf holds.
final String _stockRefusal = jsonEncode(<String, dynamic>{
  'message': _sentence,
  'code': 'insufficient_stock',
  'errors': <String, dynamic>{
    'items': <Map<String, dynamic>>[
      <String, dynamic>{'product_id': 7, 'product_name': 'Kili Water', 'available': 200, 'requested': 300},
    ],
  },
});

class _Server extends base.BaseClient {
  _Server(this.status, this.body);
  final int status;
  final String body;
  final List<String> posted = <String>[];

  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async {
    if (request.method == 'POST') posted.add(request.url.path);

    return base.StreamedResponse(Stream<List<int>>.value(utf8.encode(body)), status,
        request: request, headers: <String, String>{'content-type': 'application/json'});
  }
}

InvProduct _water() => InvProduct(
      id: 7,
      name: 'Kili Water',
      sku: 'WATER',
      category: 'Drinks',
      costPrice: 700,
      sellingPrice: 1000,
      unit: 'bottle',
      quantity: 200,
      minStock: 10,
      status: 'active',
      barcode: '',
      createdBy: 1,
    );

void main() {
  late base.Client previous;
  late String before;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{'auth_token': 'tok-1', 'language': 'en'});
    before = LocalizationService.instance.currentLanguage;
    await LocalizationService.instance.changeLanguage('en');
  });

  tearDown(() async {
    app_http.replaceClientForTesting(previous);
    await LocalizationService.instance.changeLanguage(before);
  });

  Future<(bool, String)> checkoutWith(final _Server server, {final int qty = 300}) async {
    previous = app_http.replaceClientForTesting(server);
    final InventoryProvider inv = InventoryProvider(api: ApiService());
    addTearDown(inv.dispose);
    inv.addProductToCart(_water());
    inv.setCartQty(inv.cart.first, qty);

    return inv.checkout(createdBy: 1);
  }

  test('the refusal is a sentence the seller can read, not a dump of the data behind it', () async {
    final _Server server = _Server(422, _stockRefusal);

    final (bool ok, String message) = await checkoutWith(server);

    expect(server.posted, <String>['/api/inventory/sales'], reason: 'the sale was really sent');
    expect(ok, isFalse);
    expect(message, contains('Kili Water'));
    expect(message, contains('200'));
    expect(message, contains('300'));
    expect(message, isNot(contains('product_id')), reason: 'no Dart map text on the screen');
    expect(message, isNot(contains('{')));
  });

  test('in English only the English half is shown, in Swahili only the Swahili half', () async {
    final (bool _, String english) = await checkoutWith(_Server(422, _stockRefusal));
    expect(english, 'Not enough stock for Kili Water: 200 available, 300 requested.');

    await LocalizationService.instance.changeLanguage('sw');
    final (bool _, String swahili) = await checkoutWith(_Server(422, _stockRefusal));
    expect(swahili, 'Stock haitoshi kwa Kili Water: zilizopo 200, unazouza 300.');
  });

  test('a refused sale keeps the cart, so the seller only has to lower the quantity', () async {
    previous = app_http.replaceClientForTesting(_Server(422, _stockRefusal));
    final InventoryProvider inv = InventoryProvider(api: ApiService());
    addTearDown(inv.dispose);
    inv.addProductToCart(_water());
    inv.setCartQty(inv.cart.first, 300);

    final (bool ok, String _) = await inv.checkout(createdBy: 1);

    expect(ok, isFalse);
    expect(inv.cart, hasLength(1));
    expect(inv.cart.first.qty, 300);
  });

  test('an ordinary field error still reads as the first field message', () async {
    final String body = jsonEncode(<String, dynamic>{
      'message': 'The given data was invalid.',
      'errors': <String, dynamic>{
        'payment_status': <String>['The payment status field is required.'],
      },
    });

    final (bool ok, String message) = await checkoutWith(_Server(422, body), qty: 2);

    expect(ok, isFalse);
    expect(message, 'The payment status field is required.');
  });

  test('a server error with no message at all falls back to the plain "checkout failed" key', () async {
    final (bool ok, String message) = await checkoutWith(_Server(500, '{}'), qty: 2);

    expect(ok, isFalse);
    expect(message.trim().isNotEmpty, isTrue);
  });
}
