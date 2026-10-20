import 'dart:convert';

import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/http_client.dart' as app_http;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as base;
import 'package:shared_preferences/shared_preferences.dart';

/// The server keeps a salon's sales, clients and goods apart from the shop's, going by a header the app sends only
/// from the salon's screens. This pins down exactly when it is sent.
class _Recorder extends base.BaseClient {
  final List<Map<String, String>> headers = <Map<String, String>>[];

  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async {
    headers.add(request.headers);
    return base.StreamedResponse(Stream<List<int>>.value(utf8.encode('{"data":[]}')), 200,
        request: request, headers: <String, String>{'content-type': 'application/json'});
  }
}

void main() {
  late _Recorder client;
  late base.Client previous;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{'auth_token': 'tok-1'});
    ApiService.activeService = null;
    client = _Recorder();
    previous = app_http.replaceClientForTesting(client);
  });

  tearDown(() {
    ApiService.activeService = null;
    app_http.replaceClientForTesting(previous);
  });

  test('a request from the shop says nothing about a service', () async {
    await ApiService().get('/inventory/products');

    expect(client.headers.single.containsKey('X-Service'), isFalse);
  });

  test('once the salon is open every request says it is the salon\'s', () async {
    final InventoryProvider inv = InventoryProvider(api: ApiService());
    addTearDown(inv.dispose);

    inv.setSalonMode(true);
    await ApiService().get('/inventory/products');
    await ApiService().post('/inventory/customers', <String, dynamic>{'name': 'Neema', 'phone': '0711'});

    expect(client.headers, hasLength(2));
    expect(client.headers.every((Map<String, String> h) => h['X-Service'] == 'salon'), isTrue);
  });

  test('opening the shop again stops sending it', () async {
    final InventoryProvider inv = InventoryProvider(api: ApiService());
    addTearDown(inv.dispose);
    inv.setSalonMode(true);
    inv.setSalonMode(false);

    await ApiService().get('/inventory/products');

    expect(client.headers.single.containsKey('X-Service'), isFalse);
  });

  test('the header follows the mode from one request to the next', () async {
    final InventoryProvider inv = InventoryProvider(api: ApiService());
    addTearDown(inv.dispose);

    await ApiService().get('/inventory/products');
    inv.setSalonMode(true);
    await ApiService().get('/inventory/products');
    inv.setSalonMode(false);
    await ApiService().get('/inventory/products');

    expect(client.headers.map((Map<String, String> h) => h['X-Service']).toList(), <String?>[null, 'salon', null]);
  });
}
