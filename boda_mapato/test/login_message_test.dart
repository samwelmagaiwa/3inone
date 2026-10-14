import 'dart:async';
import 'dart:convert';

import 'package:boda_mapato/constants/theme_constants.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/screens/auth/login_screen.dart';
import 'package:boda_mapato/services/http_client.dart' as app_http;
import 'package:boda_mapato/services/localization_service.dart';
import 'package:boda_mapato/utils/server_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as base;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A person who cannot sign in must be told WHY in plain words, in the language they chose: not
/// "Exception: Login failed: Exception: <both languages>".

const String _pendingSw = 'Usajili wako unasubiri idhini ya super admin. Utaweza kuingia baada ya kukubaliwa.';
const String _pendingEn = 'Your registration is awaiting super admin approval. You can sign in once it is approved.';

class _Server extends base.BaseClient {
  _Server(this.loginStatus, this.loginBody);
  final int loginStatus;
  final Map<String, dynamic> loginBody;

  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async {
    if (request.url.path.endsWith('/auth/login')) {
      return base.StreamedResponse(Stream<List<int>>.value(utf8.encode(jsonEncode(loginBody))), loginStatus,
          request: request, headers: <String, String>{'content-type': 'application/json'});
    }
    // the health check (and anything else) is fine
    return base.StreamedResponse(Stream<List<int>>.value(utf8.encode('{"status":"ok"}')), 200,
        request: request, headers: <String, String>{'content-type': 'application/json'});
  }
}

Map<String, dynamic> _pendingAnswer() => <String, dynamic>{
      'status': 'error',
      'message': '$_pendingSw / $_pendingEn',
      'errors': <String, dynamic>{'code': 'registration_pending'},
    };

void main() {
  late String before;
  late base.Client previous;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    previous = app_http.replaceClientForTesting(_Server(403, _pendingAnswer()));
    before = LocalizationService.instance.currentLanguage;
  });

  tearDown(() async {
    app_http.replaceClientForTesting(previous);
    await LocalizationService.instance.changeLanguage(before);
  });

  group('readableServerMessage', () {
    test('takes the Exception wrappers off', () {
      expect(readableServerMessage('Exception: Login failed: Exception: Wrong password'), 'Wrong password');
      expect(readableServerMessage('Exception: Wrong password'), 'Wrong password');
      expect(readableServerMessage('Wrong password'), 'Wrong password');
    });

    test('keeps only the half in the chosen language', () async {
      const String raw = 'Exception: Login failed: Exception: $_pendingSw / $_pendingEn';
      await LocalizationService.instance.changeLanguage('en');
      expect(readableServerMessage(raw), _pendingEn);
      await LocalizationService.instance.changeLanguage('sw');
      expect(readableServerMessage(raw), _pendingSw);
    });

    test('leaves a message alone when the slash is part of the text', () async {
      await LocalizationService.instance.changeLanguage('en');
      expect(readableServerMessage('Credit / Debt'), 'Credit / Debt');
      expect(readableServerMessage('a / b / c and some more words'), 'a / b / c and some more words');
    });

    test('a request that never reached the server reads as a plain sentence', () async {
      await LocalizationService.instance.changeLanguage('en');
      final String message = readableErrorMessage(TimeoutException('x', const Duration(seconds: 30)));
      expect(message, contains('Could not reach the server'));
      expect(message.toLowerCase(), isNot(contains('exception')));
    });
  });

  group('every banner and message that carries an error', () {
    test('a plain text with a slash is not cut in two', () async {
      await LocalizationService.instance.changeLanguage('en');
      expect(readableServerMessage('Paid / Total balance for the day'), 'Paid / Total balance for the day');
    });

    test('an error handed to a translation reads as plain words', () async {
      await LocalizationService.instance.changeLanguage('en');
      final String text = LocalizationService.instance.translateWith('failed_get_user_data', <Object?>[Exception('Token has expired')]);
      expect(text, 'Could not get your account details: Token has expired');
      expect(text, isNot(contains('Exception')));

      await LocalizationService.instance.changeLanguage('sw');
      expect(
        LocalizationService.instance.translateWith('failed_get_user_data', <Object?>[Exception('$_pendingSw / $_pendingEn')]),
        'Imeshindikana kupata taarifa za akaunti yako: $_pendingSw',
      );
    });

    testWidgets('the banner shows the clean message in the chosen language', (WidgetTester tester) async {
      await LocalizationService.instance.changeLanguage('en');
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (BuildContext context) {
        captured = context;
        return const SizedBox();
      }))));

      ThemeConstants.showErrorSnackBar(captured, 'Exception: Login failed: Exception: $_pendingSw / $_pendingEn');
      await tester.pump();

      expect(find.text(_pendingEn), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('Usajili'), findsNothing);
      await tester.pump(const Duration(seconds: 4)); // the banner removes itself
    });
  });

  group('signing in while the registration is not approved', () {
    for (final String language in <String>['en', 'sw']) {
      test('the provider keeps the code and a clean message ($language)', () async {
        await LocalizationService.instance.changeLanguage(language);
        final AuthProvider auth = AuthProvider();

        final bool ok = await auth.login(email: 'owner@example.test', password: 'secret-pass-1', phoneNumber: '0743519100');

        expect(ok, isFalse);
        expect(auth.lastErrorCode, 'registration_pending', reason: 'the screen shows the right dialog for this code');
        expect(auth.errorMessage, language == 'en' ? _pendingEn : _pendingSw);
        expect(auth.errorMessage, isNot(contains('Exception')));
        expect(auth.errorMessage, isNot(contains('Login failed')));
        expect(auth.errorMessage, isNot(contains(' / ')), reason: 'one language only');
      });
    }

    testWidgets('the sign-in screen opens the "pending approval" dialog with the message in the chosen language', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await LocalizationService.instance.changeLanguage('en');

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (BuildContext context, Widget? child) => MultiProvider(
            providers: <ChangeNotifierProvider<ChangeNotifier>>[
              ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
              ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
            ],
            child: const MaterialApp(home: LoginScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final Finder fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'owner@example.test');
      await tester.enterText(fields.at(1), '0743519100');
      await tester.enterText(fields.at(2), 'secret-pass-1');
      await tester.pump();
      await tester.tap(find.byWidgetPredicate((Widget w) => w is Text && (w.data ?? '').toUpperCase() == 'SIGN IN').first);
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(AlertDialog), findsOneWidget, reason: 'the pending-approval dialog');
      final Text message = tester.widget<Text>(find.byKey(const ValueKey<String>('registration_pending_message')));
      expect(message.data, _pendingEn);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('Login failed'), findsNothing);
      expect(find.text('Registration Pending Approval'), findsOneWidget);
    });
  });
}
