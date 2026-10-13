import 'dart:async';
import 'dart:convert';

import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/http_client.dart' as app_http;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as base;
import 'package:shared_preferences/shared_preferences.dart';

/// Opening a screen makes several providers ask for the same thing in the same moment (the business settings,
/// the crate types, the sales officers ...). Identical GETs that are on their way together now share one trip to
/// the server, and only while it is on its way: nobody is ever handed an old answer.
class _HeldClient extends base.BaseClient {
  final List<String> requested = <String>[];
  final List<Completer<_Answer>> waiting = <Completer<_Answer>>[];

  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async {
    requested.add('${request.method} ${request.url.path} auth=${request.headers['Authorization']}');
    final Completer<_Answer> c = Completer<_Answer>();
    waiting.add(c);
    final _Answer a = await c.future;
    return base.StreamedResponse(Stream<List<int>>.value(utf8.encode(a.body)), a.status, request: request);
  }

  /// Answers everything that is waiting.
  void answerAll({int status = 200, String body = '{"data":{"n":1}}'}) {
    for (final Completer<_Answer> c in waiting) {
      if (!c.isCompleted) c.complete(_Answer(status, body));
    }
  }
}

class _Answer {
  _Answer(this.status, this.body);
  final int status;
  final String body;
}

void main() {
  late _HeldClient client;
  late base.Client previous;

  Future<void> signInAs(String token) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'auth_token': token});
  }

  setUp(() async {
    await signInAs('token-A');
    client = _HeldClient();
    previous = app_http.replaceClientForTesting(client);
  });

  tearDown(() => app_http.replaceClientForTesting(previous));

  Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('three identical GETs at once make ONE request, and all three get the answer', () async {
    final ApiService api = ApiService();

    final Future<Map<String, dynamic>> a = api.get('/inventory/settings');
    final Future<Map<String, dynamic>> b = api.get('/inventory/settings');
    final Future<Map<String, dynamic>> c = api.get('/inventory/settings');
    await flush();
    expect(client.requested, hasLength(1), reason: 'one trip to the server');
    client.answerAll();

    final List<Map<String, dynamic>> all = await Future.wait(<Future<Map<String, dynamic>>>[a, b, c]);
    expect(all.every((Map<String, dynamic> m) => (m['data'] as Map<String, dynamic>)['n'] == 1), isTrue);
  });

  test('each caller gets an answer of its own: changing one cannot change another', () async {
    final ApiService api = ApiService();

    final Future<Map<String, dynamic>> a = api.get('/inventory/settings');
    final Future<Map<String, dynamic>> b = api.get('/inventory/settings');
    await flush();
    client.answerAll();
    final Map<String, dynamic> first = await a;
    final Map<String, dynamic> second = await b;

    (first['data'] as Map<String, dynamic>)['n'] = 99;

    expect((second['data'] as Map<String, dynamic>)['n'], 1);
    expect(identical(first, second), isFalse);
  });

  test('different addresses are different requests', () async {
    final ApiService api = ApiService();

    final Future<Map<String, dynamic>> a = api.get('/inventory/settings');
    final Future<Map<String, dynamic>> b = api.get('/inventory/crate-types');
    await flush();

    expect(client.requested, hasLength(2));
    client.answerAll();
    await Future.wait(<Future<Map<String, dynamic>>>[a, b]);
  });

  test('the same address with different query values is a different request', () async {
    final ApiService api = ApiService();

    final Future<Map<String, dynamic>> a = api.get('/inventory/sales?page=1');
    final Future<Map<String, dynamic>> b = api.get('/inventory/sales?page=2');
    await flush();

    expect(client.requested, hasLength(2));
    client.answerAll();
    await Future.wait(<Future<Map<String, dynamic>>>[a, b]);
  });

  test('once answered it is forgotten: the next GET goes to the server again (never an old answer)', () async {
    final ApiService api = ApiService();

    final Future<Map<String, dynamic>> a = api.get('/inventory/settings');
    await flush();
    client.answerAll(body: '{"data":{"n":1}}');
    await a;

    final Future<Map<String, dynamic>> b = api.get('/inventory/settings');
    await flush();
    expect(client.requested, hasLength(2), reason: 'a second trip');
    client.waiting.last.complete(_Answer(200, '{"data":{"n":2}}'));
    expect(((await b)['data'] as Map<String, dynamic>)['n'], 2, reason: 'the NEW answer, not the old one');
  });

  test('a different person (another token) never shares a request', () async {
    final ApiService api = ApiService();

    final Future<Map<String, dynamic>> a = api.get('/inventory/settings');
    await flush();
    await signInAs('token-B');
    final Future<Map<String, dynamic>> b = api.get('/inventory/settings');
    await flush();

    expect(client.requested, hasLength(2));
    expect(client.requested.first, contains('Bearer token-A'));
    expect(client.requested.last, contains('Bearer token-B'));
    client.answerAll();
    await Future.wait(<Future<Map<String, dynamic>>>[a, b]);
  });

  test('when the shared request fails, every caller hears about it, and the next try starts fresh', () async {
    final ApiService api = ApiService();

    final Future<Map<String, dynamic>> a = api.get('/inventory/categories');
    final Future<Map<String, dynamic>> b = api.get('/inventory/categories');
    await flush();
    // listen before the answer comes, or the rejection is reported as unhandled
    final Future<void> heardA = expectLater(a, throwsA(isA<ApiException>()));
    final Future<void> heardB = expectLater(b, throwsA(isA<ApiException>()));
    client.answerAll(status: 500, body: '{"message":"Server Error"}');
    await heardA;
    await heardB;

    final Future<Map<String, dynamic>> again = api.get('/inventory/categories');
    await flush();
    expect(client.requested, hasLength(2), reason: 'a failed request is not remembered either');
    client.waiting.last.complete(_Answer(200, '{"data":[]}'));
    expect((await again)['data'], isEmpty);
  });

  test('getOrNull shares too, and still answers null for a failure', () async {
    final ApiService api = ApiService();

    final Future<Map<String, dynamic>?> a = api.getOrNull('/inventory/suppliers');
    final Future<Map<String, dynamic>?> b = api.getOrNull('/inventory/suppliers');
    await flush();
    expect(client.requested, hasLength(1));
    client.answerAll(status: 500, body: '{"message":"Server Error"}');

    expect(await a, isNull);
    expect(await b, isNull);
  });

  test('POSTs are never shared: two saves are two saves', () async {
    final ApiService api = ApiService();

    final Future<Map<String, dynamic>> a = api.post('/inventory/customers', <String, dynamic>{'name': 'A'});
    final Future<Map<String, dynamic>> b = api.post('/inventory/customers', <String, dynamic>{'name': 'A'});
    await flush();

    expect(client.requested, hasLength(2));
    client.answerAll(status: 201, body: '{"data":{"id":1}}');
    await Future.wait(<Future<Map<String, dynamic>>>[a, b]);
  });
}
