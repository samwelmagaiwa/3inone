import 'dart:async';
import 'dart:convert';

import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/http_client.dart' as app_http;
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as base;
import 'package:shared_preferences/shared_preferences.dart';

/// What the app does when the business it works for is held back for an unpaid plan, and when it is opened again.

/// The server, scripted by the test: [held] says whether the business is held back right now.
class _Server extends base.BaseClient {
  bool held = false;
  int subscriptionCalls = 0;
  final List<String> paths = <String>[];

  Map<String, dynamic> get _billing => <String, dynamic>{
        'plan': 'basic',
        'valid_until': '2026-09-01T00:00:00+03:00',
        'days_left': held ? -43 : 20,
        'is_expired': held,
        'enforced': true,
        'blocked': held,
      };

  Map<String, dynamic> get _user => <String, dynamic>{
        'id': 'u-1',
        'name': 'Asha Owner',
        'email': 'asha@example.test',
        'role': 'admin',
        'is_active': true,
        'business': <String, dynamic>{'id': 'b-1', 'name': 'Asha Rentals', 'billing': _billing},
      };

  base.StreamedResponse _json(base.BaseRequest request, int status, Map<String, dynamic> body) =>
      base.StreamedResponse(Stream<List<int>>.value(utf8.encode(jsonEncode(body))), status,
          request: request, headers: <String, String>{'content-type': 'application/json'});

  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async {
    final String path = request.url.path;
    paths.add(path);
    if (path.endsWith('/auth/login')) {
      return _json(request, 200, <String, dynamic>{'status': 'success', 'data': <String, dynamic>{'token': 'tok-1'}});
    }
    if (path.endsWith('/auth/user')) {
      return _json(request, 200, <String, dynamic>{'status': 'success', 'data': <String, dynamic>{'user': _user}});
    }
    if (path.endsWith('/business/subscription')) {
      subscriptionCalls++;
      return _json(request, 200, <String, dynamic>{
        'status': 'success',
        'data': <String, dynamic>{
          'status': held ? 'expired' : 'active',
          'plan': 'basic',
          'business_name': 'Asha Rentals',
          'is_owner': true,
          'valid_until': '2026-09-01T00:00:00+03:00',
          'days_left': held ? -43 : 20,
          'enforced': true,
          'blocked': held,
        },
      });
    }
    if (path.endsWith('/auth/logout') || path.endsWith('/health')) {
      return _json(request, 200, <String, dynamic>{'status': 'ok'});
    }
    if (held) {
      return _json(request, 402, <String, dynamic>{
        'status': 'error',
        'message': 'Usajili wa biashara yako umeisha. Wasiliana na msimamizi ili kuuhuisha. / '
            'Your business subscription has expired. Contact your administrator to renew it.',
        'errors': <String, dynamic>{'code': 'subscription_expired', 'plan': 'basic'},
      });
    }
    return _json(request, 200, <String, dynamic>{'status': 'success', 'data': <dynamic>[]});
  }
}

Future<void> _until(bool Function() done) async {
  for (int i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late _Server server;
  late base.Client previous;
  late AuthProvider auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    server = _Server();
    previous = app_http.replaceClientForTesting(server);
    await LocalizationService.instance.changeLanguage('en');
    auth = AuthProvider();
  });

  tearDown(() async {
    auth.dispose();
    app_http.replaceClientForTesting(previous);
    await LocalizationService.instance.changeLanguage('sw');
  });

  Future<void> signIn() async {
    final bool ok = await auth.login(email: 'asha@example.test', password: 'secret-pass-1', phoneNumber: '0743519100');
    expect(ok, isTrue);
  }

  test('signing in with an open business shows no cover', () async {
    await signIn();
    expect(auth.subscriptionBlocked, isFalse);
    expect(auth.subscriptionReopened, 0);
  });

  test('signing in with a business that is held back puts the cover up at once, then fetches the details', () async {
    server.held = true;
    await signIn();

    expect(auth.isAuthenticated, isTrue, reason: 'a late payment never signs anybody out');
    expect(auth.subscriptionBlocked, isTrue);

    await _until(() => auth.subscription != null);
    expect(auth.subscription!.blocked, isTrue);
    expect(auth.subscription!.status, 'expired');
    expect(auth.subscription!.businessName, 'Asha Rentals');
  });

  test('a 402 from any call puts the cover up, keeps the person signed in and says why in plain words', () async {
    await signIn();
    expect(auth.subscriptionBlocked, isFalse);

    server.held = true;
    await expectLater(
      ApiService().getBusinesses(),
      throwsA(isA<ApiException>().having((ApiException e) => e.toString(), 'message', allOf(contains('Your business subscription has expired'), isNot(contains('Usajili')), isNot(contains('Exception'))))),
    );
    await _until(() => auth.subscription != null);

    expect(auth.subscriptionBlocked, isTrue);
    expect(auth.isAuthenticated, isTrue, reason: 'not signed out');
    expect(auth.subscription!.blocked, isTrue);
  });

  test('a 402 for something other than an ended subscription does not put the cover up', () async {
    await signIn();
    server.held = false;
    final _Server other = _OtherPaymentRequired();
    app_http.replaceClientForTesting(other);

    await expectLater(ApiService().getBusinesses(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(auth.subscriptionBlocked, isFalse);
  });

  test('once a payment is recorded the next check opens the business and counts the reopening', () async {
    server.held = true;
    await signIn();
    await _until(() => auth.subscription != null);
    expect(auth.subscriptionBlocked, isTrue);
    expect(auth.subscriptionReopened, 0, reason: 'a business that was never open has not been reopened');

    // still unpaid: nothing changes
    await auth.recheckSubscription();
    expect(auth.subscriptionBlocked, isTrue);
    expect(auth.subscriptionReopened, 0);

    // the super admin records a payment
    server.held = false;
    await auth.recheckSubscription();

    expect(auth.subscriptionBlocked, isFalse);
    expect(auth.subscription!.status, 'active');
    expect(auth.subscriptionReopened, 1, reason: 'the app reloads its data when this changes');

    // checking again, still open, is not another reopening
    await auth.recheckSubscription();
    expect(auth.subscriptionReopened, 1);
  });

  test('the periodic refresh of the account also opens the business', () async {
    server.held = true;
    await signIn();
    expect(auth.subscriptionBlocked, isTrue);

    server.held = false;
    await auth.refreshUser();

    expect(auth.subscriptionBlocked, isFalse);
    expect(auth.subscriptionReopened, 1);
  });

  test('a failed check (no connection) changes nothing', () async {
    server.held = true;
    await signIn();
    await _until(() => auth.subscription != null);

    app_http.replaceClientForTesting(_Offline());
    await auth.recheckSubscription();

    expect(auth.subscriptionBlocked, isTrue, reason: 'no news is not good news');
    expect(auth.subscriptionReopened, 0);
  });

  test('signing out takes the cover away with the session', () async {
    server.held = true;
    await signIn();
    await _until(() => auth.subscription != null);

    await auth.logout();

    expect(auth.subscriptionBlocked, isFalse);
    expect(auth.subscription, isNull);
  });
}

/// A payment-required answer that is not about the subscription (no code).
class _OtherPaymentRequired extends _Server {
  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async => _json(request, 402, <String, dynamic>{
        'status': 'error',
        'message': 'Payment required for this feature.',
      });
}

class _Offline extends base.BaseClient {
  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async => throw TimeoutException('no signal');
}
