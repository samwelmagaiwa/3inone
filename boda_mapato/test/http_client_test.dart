import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:boda_mapato/services/http_client.dart' as app_http;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as base;

/// The app keeps its connections to the server open and reuses them. Every new connection costs a TCP and a TLS
/// handshake (about 0.37 s on a 160 ms link) before a single byte of the request goes out; opening the inventory
/// home sends about thirty requests.
void main() {
  late HttpServer server;
  late Uri url;
  final Set<int> ports = <int>{};
  int active = 0;
  int peak = 0;
  Duration answerAfter = Duration.zero;

  setUp(() async {
    ports.clear();
    active = 0;
    peak = 0;
    answerAfter = Duration.zero;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = Uri.parse('http://127.0.0.1:${server.port}/ping');
    server.listen((HttpRequest request) async {
      ports.add(request.connectionInfo!.remotePort);
      active++;
      if (active > peak) peak = active;
      await request.drain<void>();
      if (answerAfter > Duration.zero) await Future<void>.delayed(answerAfter);
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(<String, Object>{'ok': true}));
      await request.response.close();
      active--;
    });
  });

  tearDown(() async => server.close(force: true));

  group('the shared client', () {
    test('requests one after another travel over ONE connection', () async {
      final base.Client client = app_http.newAppClient();
      addTearDown(client.close);

      for (int i = 0; i < 8; i++) {
        expect((await client.get(url)).statusCode, 200);
      }

      expect(ports, hasLength(1), reason: 'eight requests, one handshake');
    });

    test('many requests at once share a few connections instead of one each', () async {
      final base.Client client = app_http.newAppClient();
      addTearDown(client.close);
      answerAfter = const Duration(milliseconds: 60);

      final List<base.Response> all = await Future.wait(<Future<base.Response>>[for (int i = 0; i < 30; i++) client.get(url)]);

      expect(all.every((base.Response r) => r.statusCode == 200), isTrue, reason: 'all thirty are answered');
      expect(ports.length, lessThanOrEqualTo(app_http.kMaxConnections), reason: 'not thirty handshakes');
      expect(peak, lessThanOrEqualTo(app_http.kMaxConnections), reason: 'the server never sees more than the limit at once');
    });

    test('the limit is the documented one (six, like a browser)', () {
      expect(app_http.kMaxConnections, 6);
      expect(app_http.kIdleKeepAlive, lessThan(const Duration(seconds: 60)), reason: 'shorter than the server keeps a connection');
    });

    test('the app-level functions use the shared client too', () async {
      final base.Client previous = app_http.replaceClientForTesting(app_http.newAppClient());
      addTearDown(() => app_http.replaceClientForTesting(previous));

      for (int i = 0; i < 5; i++) {
        expect((await app_http.get(url)).statusCode, 200);
      }
      expect((await app_http.post(url, body: 'x')).statusCode, 200);

      expect(ports, hasLength(1), reason: 'GETs and a POST, one connection');
    });
  });

  group('a connection the server closed in the meantime', () {
    test('a GET is asked again on a fresh connection and succeeds', () async {
      final _FlakyClient flaky = _FlakyClient(failFirstWith: const HttpException('Connection closed before full header was received'));
      final base.Client previous = app_http.replaceClientForTesting(flaky);
      addTearDown(() => app_http.replaceClientForTesting(previous));

      final base.Response r = await app_http.get(url);

      expect(r.statusCode, 200);
      expect(flaky.sent, 2, reason: 'once failed, once repeated');
    });

    test('a POST is NEVER repeated by itself: it may already have reached the server', () async {
      final _FlakyClient flaky = _FlakyClient(failFirstWith: const HttpException('Connection closed before full header was received'));
      final base.Client previous = app_http.replaceClientForTesting(flaky);
      addTearDown(() => app_http.replaceClientForTesting(previous));

      await expectLater(app_http.post(url, body: '{}'), throwsA(isA<HttpException>()));

      expect(flaky.sent, 1);
    });

    test('a refused connection (server down) is not retried either: it would only fail twice as slowly', () async {
      final _FlakyClient flaky = _FlakyClient(failFirstWith: const SocketException('Connection refused', osError: OSError('Connection refused', 111)));
      final base.Client previous = app_http.replaceClientForTesting(flaky);
      addTearDown(() => app_http.replaceClientForTesting(previous));

      await expectLater(app_http.get(url), throwsA(isA<SocketException>()));

      expect(flaky.sent, 1);
    });

    test('a different kind of failure (a bug, a timeout) is not retried', () async {
      final _FlakyClient flaky = _FlakyClient(failFirstWith: StateError('not a network problem'));
      final base.Client previous = app_http.replaceClientForTesting(flaky);
      addTearDown(() => app_http.replaceClientForTesting(previous));

      await expectLater(app_http.get(url), throwsA(isA<StateError>()));

      expect(flaky.sent, 1);
    });
  });
}

/// Fails its first request with [failFirstWith], answers every later one.
class _FlakyClient extends base.BaseClient {
  _FlakyClient({required this.failFirstWith});

  final Object failFirstWith;
  int sent = 0;

  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async {
    sent++;
    if (sent == 1) throw failFirstWith;
    return base.StreamedResponse(Stream<List<int>>.value(utf8.encode('{}')), 200, request: request);
  }
}
