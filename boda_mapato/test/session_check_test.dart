import 'dart:async';
import 'dart:io';

import 'package:boda_mapato/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boda_mapato/utils/server_message.dart';

void main() {
  group('AuthService.isSessionInvalid', () {
    test('a 401 from the server means the session is over', () {
      expect(AuthService.isSessionInvalid(AuthHttpException(401, 'Unauthenticated.')),
          isTrue);
    });

    test('server errors and other statuses do not end the session', () {
      for (final int code in <int>[400, 403, 404, 422, 429, 500, 502, 503, 504]) {
        expect(AuthService.isSessionInvalid(AuthHttpException(code, 'x')), isFalse,
            reason: 'HTTP $code must not sign the user out');
      }
    });

    test('a timeout or no connection does not end the session', () {
      expect(AuthService.isSessionInvalid(TimeoutException('slow')), isFalse);
      expect(AuthService.isSessionInvalid(const SocketException('no route')), isFalse);
      expect(AuthService.isSessionInvalid(Exception('Failed to get user data: x')),
          isFalse);
    });
  });

  test('AuthHttpException prints just its message, with no "Exception:" wrapper', () {
    // It used to print "Exception: <message>", which ended up on screens. Anything that still wants the text
    // without a wrapper gets the same answer from readableErrorMessage.
    expect(AuthHttpException(401, 'Unauthenticated.').toString(), 'Unauthenticated.');
    expect(readableErrorMessage(AuthHttpException(401, 'Unauthenticated.')), 'Unauthenticated.');
  });
}
