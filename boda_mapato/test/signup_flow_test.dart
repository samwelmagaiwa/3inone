import 'package:boda_mapato/models/business_registration.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/screens/auth/login_screen.dart';
import 'package:boda_mapato/screens/auth/register_business_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signing up by email on the login page: the sign-up fields fold out on the same page, a text code confirms the phone, then the person
/// signs in with email and password only and is asked for the business details (no phone, no password again).
Future<void> _open(WidgetTester t, Widget home, {AuthProvider? auth}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
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
          ChangeNotifierProvider<AuthProvider>.value(value: auth ?? AuthProvider()),
        ],
        child: MaterialApp(home: home),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('"Sign up" folds the phone and confirm-password fields out on the same page, and "Sign in" folds them away', (t) async {
    await _open(t, const LoginScreen());
    expect(_key('phone_field'), findsNothing);
    expect(_key('confirm_field'), findsNothing);

    await t.tap(_key('sign_up_link'));
    await _settle(t);
    expect(_key('phone_field'), findsOneWidget);
    expect(_key('confirm_field'), findsOneWidget);
    expect(_key('email_field'), findsOneWidget, reason: 'the same page, the same fields');
    expect(find.text('SIGN UP'), findsOneWidget, reason: 'the button changes with the page');

    await t.ensureVisible(_key('sign_in_link'));
    await t.tap(_key('sign_in_link'));
    await _settle(t);
    expect(_key('phone_field'), findsNothing);
    expect(_key('confirm_field'), findsNothing);
    expect(find.text('SIGN IN'), findsOneWidget);
  });

  testWidgets('the landing page can open the page already on "Sign up"', (t) async {
    await _open(t, const LoginScreen(startInSignup: true));
    expect(_key('phone_field'), findsOneWidget);
  });

  testWidgets('a wrong phone number or different passwords stop the sign-up before anything is sent', (t) async {
    int sent = 0;
    await _open(
      t,
      LoginScreen(
        startInSignup: true,
        onSignup: ({required String email, required String phone, required String password, required String confirm}) async {
          sent++;
          return <String, dynamic>{};
        },
      ),
    );

    await t.enterText(_key('email_field'), 'asha@example.test');
    await t.enterText(_key('phone_field'), '12345');
    await t.enterText(_key('password_field'), 'secret-pass-1');
    await t.enterText(_key('confirm_field'), 'something-else');
    await t.tap(_key('login_button'));
    await _settle(t);

    expect(sent, 0);
    expect(find.textContaining('Invalid phone number'), findsOneWidget);
    expect(find.textContaining('do not match'), findsOneWidget);
  });

  testWidgets('signing up asks for the code that was texted, then returns to sign-in with email and password only', (t) async {
    final List<String> verified = <String>[];
    String? sentTo;
    await _open(
      t,
      LoginScreen(
        startInSignup: true,
        onSignup: ({required String email, required String phone, required String password, required String confirm}) async {
          sentTo = phone;
          return <String, dynamic>{
            'data': <String, dynamic>{'phone_verification_required': true, 'code_status': 'sent'},
          };
        },
        onVerifyCode: (String email, String code) async => verified.add('$email:$code'),
        onResendCode: (String email) async {},
      ),
    );

    await t.enterText(_key('email_field'), 'asha@example.test');
    await t.enterText(_key('phone_field'), '0743519100');
    await t.enterText(_key('password_field'), 'secret-pass-1');
    await t.enterText(_key('confirm_field'), 'secret-pass-1');
    await t.tap(_key('login_button'));
    await _settle(t);

    expect(sentTo, '0743519100');
    expect(_key('otp_field'), findsOneWidget, reason: 'the code step opens');
    expect(find.textContaining('0743519100'), findsWidgets, reason: 'it says where the code went');
    expect(_key('email_field'), findsNothing);

    // a code that is not 6 digits is refused on the spot
    await t.enterText(_key('otp_field'), '123');
    await t.tap(_key('confirm_code_button'));
    await _settle(t);
    expect(verified, isEmpty);
    expect(_key('login_error'), findsOneWidget);

    await t.enterText(_key('otp_field'), '123456');
    await t.tap(_key('confirm_code_button'));
    await _settle(t);

    expect(verified, <String>['asha@example.test:123456']);
    expect(_key('email_field'), findsOneWidget, reason: 'back to signing in');
    expect(_key('phone_field'), findsNothing, reason: 'email and password only from now on');
    expect(find.textContaining('phone number is confirmed'), findsOneWidget);
    expect((t.widget(_key('password_field')) as TextFormField).controller!.text, isEmpty, reason: 'they type the password to sign in');
    expect((t.widget(_key('email_field')) as TextFormField).controller!.text, 'asha@example.test', reason: 'the email is kept');
  });

  testWidgets('"send the code again" says a new one went', (t) async {
    int resent = 0;
    await _open(
      t,
      LoginScreen(
        startInSignup: true,
        onSignup: ({required String email, required String phone, required String password, required String confirm}) async =>
            <String, dynamic>{'data': <String, dynamic>{'phone_verification_required': true, 'code_status': 'sent'}},
        onResendCode: (String email) async => resent++,
      ),
    );
    await t.enterText(_key('email_field'), 'asha@example.test');
    await t.enterText(_key('phone_field'), '0743519100');
    await t.enterText(_key('password_field'), 'secret-pass-1');
    await t.enterText(_key('confirm_field'), 'secret-pass-1');
    await t.tap(_key('login_button'));
    await _settle(t);

    await t.tap(_key('resend_code_button'));
    await _settle(t);

    expect(resent, 1);
    expect(find.textContaining('new code was sent'), findsOneWidget);
  });

  testWidgets('when texts are switched off the person is told, not left waiting for a code', (t) async {
    await _open(
      t,
      LoginScreen(
        startInSignup: true,
        onSignup: ({required String email, required String phone, required String password, required String confirm}) async =>
            <String, dynamic>{'data': <String, dynamic>{'code_status': 'unavailable'}},
      ),
    );
    await t.enterText(_key('email_field'), 'asha@example.test');
    await t.enterText(_key('phone_field'), '0743519100');
    await t.enterText(_key('password_field'), 'secret-pass-1');
    await t.enterText(_key('confirm_field'), 'secret-pass-1');
    await t.tap(_key('login_button'));
    await _settle(t);

    expect(_key('otp_field'), findsNothing);
    expect(find.textContaining('not available right now'), findsOneWidget);
  });

  // ---------------------------------------------------------------- the business details afterwards

  testWidgets('after signing up the business form has no email, phone or password fields', (t) async {
    Map<String, dynamic>? sent;
    await _open(
      t,
      RegisterBusinessScreen(
        applicant: const ApplicantCredentials(email: 'asha@example.test', password: 'secret-pass-1'),
        onSubmit: (BusinessRegistrationRequest r) async {
          sent = r.toJson();
          return <String, dynamic>{'data': <String, dynamic>{'phone_verified': true}};
        },
        onLoadPlans: () async => throw Exception('offline'),
      ),
    );

    expect(find.byKey(const ValueKey<String>('applicant_note')), findsOneWidget);
    expect(find.text('Phone Number'), findsNothing);
    expect(find.text('Password'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Your full name'), findsOneWidget);
    expect(find.text('Business name'), findsOneWidget);
  });

  test('the details of someone who signed up first carry their password as proof, no phone and no new password', () {
    const BusinessRegistrationRequest request = BusinessRegistrationRequest(
      name: 'Asha Owner',
      businessName: 'Asha Shop',
      email: 'asha@example.test',
      phoneNumber: '',
      password: '',
      passwordConfirmation: '',
      requestedServices: <String>['inventory'],
      currentPassword: 'secret-pass-1',
    );

    final Map<String, dynamic> json = request.toJson();
    expect(json['current_password'], 'secret-pass-1');
    expect(json.containsKey('phone_number'), isFalse);
    expect(json.containsKey('password'), isFalse);
    expect(json.containsKey('password_confirmation'), isFalse);
  });

  testWidgets('with Google the business form still asks for the phone number', (t) async {
    await _open(
      t,
      RegisterBusinessScreen(
        googleSignup: const GoogleSignup(email: 'neema@gmail.com', name: 'Neema Mushi', token: 'sealed'),
        onLoadPlans: () async => throw Exception('offline'),
      ),
    );

    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('Password'), findsNothing);
  });
}
