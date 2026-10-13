import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as base;
import 'package:http/io_client.dart';

// The app's HTTP calls. It is `package:http` with the same function names, so a file switches by changing one
// import (`import 'http_client.dart' as http;`); the types it uses (Response, MultipartRequest ...) are re-exported.
export 'package:http/http.dart' show ClientException, MultipartFile, MultipartRequest, Response, StreamedResponse;

// WHY: the plain top-level `http.get` / `http.post` open a brand-new connection for every call and close it again.
// Over the internet every new connection costs a TCP handshake and a TLS handshake before the first byte of the
// request can be sent: about 0.37 s on a 160 ms link, against 0.17 s for a request on a connection that is
// already open. The inventory home sends about thirty requests when it opens, so that was most of the waiting.
// One shared client keeps connections open and reuses them.

/// How many connections the app keeps to the server at once. Requests beyond this wait for a free one instead of
/// each starting a handshake of its own (browsers do the same, with six).
const int kMaxConnections = 6;

/// How long an unused connection is kept open. The server's own limit (nginx: 60-75 s) is longer, so the app is the
/// one to close it, never the other way round.
const Duration kIdleKeepAlive = Duration(seconds: 45);

/// A client set up the way the app uses it. Public so tests can build one against a local server.
base.Client newAppClient({int maxConnections = kMaxConnections, Duration idle = kIdleKeepAlive}) {
  final HttpClient inner = HttpClient()
    ..idleTimeout = idle
    ..maxConnectionsPerHost = maxConnections
    ..connectionTimeout = const Duration(seconds: 20);
  return IOClient(inner);
}

base.Client _client = newAppClient();

/// Swap the client (tests): a fake, or one pointed at a local server. Returns the previous one.
base.Client replaceClientForTesting(base.Client client) {
  final base.Client previous = _client;
  _client = client;
  return previous;
}

/// A connection that was open but that the server closed meanwhile fails the NEXT request on it with one of these.
/// The connection is thrown away, so asking again opens a fresh one. Only for requests that are safe to repeat.
bool _isStaleConnection(Object e) => e is HttpException || (e is SocketException && !(e.osError?.message.contains('refused') ?? false)) || e is base.ClientException;

Future<T> _once<T>(Future<T> Function() send) async {
  try {
    return await send();
  } on Object catch (e) {
    if (!_isStaleConnection(e)) rethrow;
    return send();
  }
}

Future<base.Response> get(Uri url, {Map<String, String>? headers}) => _once(() => _client.get(url, headers: headers));

Future<base.Response> head(Uri url, {Map<String, String>? headers}) => _once(() => _client.head(url, headers: headers));

// A POST / PUT / PATCH / DELETE may already have reached the server when the connection failed, so these are never
// repeated on their own.
Future<base.Response> post(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _client.post(url, headers: headers, body: body, encoding: encoding);

Future<base.Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _client.put(url, headers: headers, body: body, encoding: encoding);

Future<base.Response> patch(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _client.patch(url, headers: headers, body: body, encoding: encoding);

Future<base.Response> delete(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
    _client.delete(url, headers: headers, body: body, encoding: encoding);
