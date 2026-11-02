import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/screens/auth/forgot_password_sheet.dart';
import 'package:boda_mapato/screens/auth/login_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Remember me" and "Forgot Password?" on the sign-in page: the email last used is kept (or forgotten) on this phone, and the link opens the
/// reset sheet with the email already typed and puts the confirmed email back in the form afterwards.
class _Auth extends AuthProvider {
  _Auth({this.ok = true});

  final bool ok;
  final List<String> signedIn = <String>[];

  @override
  Future<bool> login({required final String email, required final String password, final String phoneNumber = ''}) async {
    signedIn.add('$email|$password');
    return ok;
  }
}

Future<void> _open(WidgetTester t, AuthProvider auth, {Map<String, Object> saved = const <String, Object>{}}) async {
  SharedPreferences.setMockInitialValues(saved);
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (BuildContext context, Widget? child) => MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ],
        child: MaterialApp(home: Builder(builder: (BuildContext c) => Scaffold(body: Center(child: ElevatedButton(key: const ValueKey<String>('go'), onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen())), child: const Text('open')))))),
      ),
    ),
  );
  await t.tap(find.byKey(const ValueKey<String>('go')));
  await _settle(t);
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

TextField _field(WidgetTester t, String key) => t.widget<TextField>(find.descendant(of: _key(key), matching: find.byType(TextField)));

Future<void> _signIn(WidgetTester t, {required String email}) async {
  await t.enterText(_key('email_field'), email);
  await t.enterText(_key('password_field'), 'secret-pass-1');
  await t.ensureVisible(_key('login_button'));
  await t.tap(_key('login_button'));
  await _settle(t);
  await t.pump(const Duration(seconds: 6)); // the banner's timer
}

void main() {
  const String remembered = 'login_remembered_email';

  group('Remember me', () {
    testWidgets('is ticked at first, and the box can be switched off and on', (t) async {
      await _open(t, _Auth());

      expect(t.widget<Checkbox>(_key('remember_me')).value, isTrue);
      await t.tap(_key('remember_me'));
      await t.pump();
      expect(t.widget<Checkbox>(_key('remember_me')).value, isFalse);
      await t.tap(_key('remember_me'));
      await t.pump();
      expect(t.widget<Checkbox>(_key('remember_me')).value, isTrue);
    });

    testWidgets('the email kept on this phone is filled in when the page opens', (t) async {
      await _open(t, _Auth(), saved: <String, Object>{remembered: 'asha@example.test'});

      expect(_field(t, 'email_field').controller!.text, 'asha@example.test');
      expect(_field(t, 'password_field').controller!.text, isEmpty, reason: 'the password is never kept');
    });

    testWidgets('a successful sign-in with the box ticked keeps the email for next time', (t) async {
      final _Auth auth = _Auth();
      await _open(t, auth);

      await _signIn(t, email: 'asha@example.test');

      expect(auth.signedIn, <String>['asha@example.test|secret-pass-1']);
      expect((await SharedPreferences.getInstance()).getString(remembered), 'asha@example.test');
    });

    testWidgets('with the box switched off the email is not kept, and one kept before is forgotten', (t) async {
      final _Auth auth = _Auth();
      await _open(t, auth, saved: <String, Object>{remembered: 'old@example.test'});

      await t.tap(_key('remember_me'));
      await t.pump();
      await _signIn(t, email: 'asha@example.test');

      expect(auth.signedIn, hasLength(1));
      expect((await SharedPreferences.getInstance()).getString(remembered), isNull);
    });

    testWidgets('a failed sign-in keeps nothing', (t) async {
      final _Auth auth = _Auth(ok: false);
      await _open(t, auth);

      await _signIn(t, email: 'asha@example.test');

      expect((await SharedPreferences.getInstance()).getString(remembered), isNull, reason: 'only a sign-in that worked is remembered');
    });

    testWidgets('what the person types is not overwritten by the kept email', (t) async {
      await _open(t, _Auth());
      await t.enterText(_key('email_field'), 'typed@example.test');
      await _settle(t);

      expect(_field(t, 'email_field').controller!.text, 'typed@example.test');
    });
  });

  group('Forgot Password?', () {
    testWidgets('opens the reset sheet with the email already typed', (t) async {
      await _open(t, _Auth());
      await t.enterText(_key('email_field'), 'asha@example.test');

      await t.ensureVisible(_key('forgot_password'));
      await t.tap(_key('forgot_password'));
      await _settle(t);

      expect(find.byType(ForgotPasswordSheet), findsOneWidget);
      final Finder sheetEmail = find.descendant(of: find.byType(ForgotPasswordSheet), matching: find.byType(TextFormField)).first;
      expect(t.widget<TextFormField>(sheetEmail).controller!.text, 'asha@example.test');
    });

    testWidgets('opens with an empty email when none was typed, and asks for the phone too', (t) async {
      await _open(t, _Auth());

      await t.ensureVisible(_key('forgot_password'));
      await t.tap(_key('forgot_password'));
      await _settle(t);

      final Finder fields = find.descendant(of: find.byType(ForgotPasswordSheet), matching: find.byType(TextFormField));
      expect(fields, findsNWidgets(2), reason: 'email and phone');
      expect(t.widget<TextFormField>(fields.first).controller!.text, isEmpty);
    });

    testWidgets('closing the sheet changes nothing on the page', (t) async {
      await _open(t, _Auth());
      await t.enterText(_key('email_field'), 'asha@example.test');
      await t.enterText(_key('password_field'), 'typed-password');
      await t.ensureVisible(_key('forgot_password'));
      await t.tap(_key('forgot_password'));
      await _settle(t);

      await t.tapAt(const Offset(200, 40)); // outside the sheet
      await _settle(t);

      expect(find.byType(ForgotPasswordSheet), findsNothing);
      expect(_field(t, 'email_field').controller!.text, 'asha@example.test');
      expect(_field(t, 'password_field').controller!.text, 'typed-password');
    });

    testWidgets('after the password is reset the confirmed email is put in the form and the old password cleared', (t) async {
      await _open(t, _Auth());
      await t.enterText(_key('email_field'), 'old@example.test');
      await t.enterText(_key('password_field'), 'wrong-password');
      await t.ensureVisible(_key('forgot_password'));
      await t.tap(_key('forgot_password'));
      await _settle(t);

      // the sheet hands back the email it confirmed when the reset is done
      Navigator.of(t.element(find.byType(ForgotPasswordSheet))).pop('asha@example.test');
      await _settle(t);

      expect(_field(t, 'email_field').controller!.text, 'asha@example.test');
      expect(_field(t, 'password_field').controller!.text, isEmpty);
    });
  });
}
