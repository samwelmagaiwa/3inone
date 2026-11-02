import 'package:boda_mapato/models/business_registration.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/screens/auth/login_screen.dart';
import 'package:boda_mapato/screens/auth/register_business_screen.dart';
import 'package:boda_mapato/services/google_login.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sign in with Google: the login page leads with the Google button (the email form is behind a link), someone Google knows but we do not
/// goes to the registration form with their name and email and no password, and a backed-out chooser does nothing.
class _GoogleAuth extends AuthProvider {
  _GoogleAuth({this.token, this.newUser});

  final String? token;
  final GoogleSignup? newUser;

  @override
  Future<GoogleResult> loginWithGoogle() async {
    if (token == null && newUser == null) return GoogleResult.cancelled;
    return GoogleResult.newUser;
  }

  @override
  GoogleSignup? get googleSignup => newUser;
}

Future<void> _open(WidgetTester t, Widget home, AuthProvider auth) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1800);
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
        child: MaterialApp(home: home),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('the login page has the email form, the Google button and the sign-up and legal links', (t) async {
    await _open(t, const LoginScreen(), AuthProvider());

    expect(find.byKey(const ValueKey<String>('login_title_signIn')), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2), reason: 'email and password only');
    expect(find.byKey(const ValueKey<String>('phone_field')), findsNothing);
    expect(find.byKey(const ValueKey<String>('login_button')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('google_signin_button')), findsOneWidget);
    expect(find.text('SIGN IN WITH GOOGLE'), findsOneWidget);
    expect(find.text('OR SIGN IN WITH'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('sign_up_link')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('legal_links')), findsOneWidget);
    expect(find.textContaining('demo', findRichText: true), findsNothing, reason: 'no demo accounts on the login page');
  });

  testWidgets('someone new goes to the registration form with their Google name and email and no password', (t) async {
    const GoogleSignup signup = GoogleSignup(email: 'neema@gmail.com', name: 'Neema Mushi', token: 'sealed');
    await _open(t, const LoginScreen(), _GoogleAuth(newUser: signup));

    await t.tap(find.byKey(const ValueKey<String>('google_signin_button')));
    for (int i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }

    expect(find.byType(RegisterBusinessScreen), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('google_signup_note')), findsOneWidget);
    expect(find.text('neema@gmail.com'), findsOneWidget);
    expect(find.text('Neema Mushi'), findsOneWidget);
    expect(find.text('Password'), findsNothing, reason: 'Google is the password');
    expect(find.text('Confirm password'), findsNothing);
    expect(find.text('Phone Number'), findsOneWidget, reason: 'the phone moved here from the login page');
  });

  testWidgets('backing out of the Google chooser changes nothing', (t) async {
    await _open(t, const LoginScreen(), _GoogleAuth());

    await t.tap(find.byKey(const ValueKey<String>('google_signin_button')));
    for (int i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RegisterBusinessScreen), findsNothing);
  });

  test('the registration sent for a Google person carries the sealed token and no password', () {
    const BusinessRegistrationRequest request = BusinessRegistrationRequest(
      name: 'Neema',
      businessName: 'Neema Shop',
      email: 'neema@gmail.com',
      phoneNumber: '0712000111',
      password: '',
      passwordConfirmation: '',
      requestedServices: <String>['inventory'],
      googleToken: 'sealed',
    );

    final Map<String, dynamic> json = request.toJson();
    expect(json['google_token'], 'sealed');
    expect(json.containsKey('password'), isFalse);
    expect(json.containsKey('password_confirmation'), isFalse);
  });

  test('a chooser that could not offer an account is explained, not silent', () async {
    await LocalizationService.instance.changeLanguage('en');
    final String msg = GoogleLogin.explain(GoogleSignInExceptionCode.canceled, 'No credentials available');
    expect(msg, contains('Add a Google account'));
    expect(msg, contains('canceled: No credentials available'), reason: 'the code stays visible for whoever is helping');

    final AuthProvider auth = AuthProvider();
    auth.googleIdTokenSource = () async => throw GoogleLoginProblem(msg);
    expect(await auth.loginWithGoogle(), GoogleResult.failed);
    expect(auth.errorMessage, contains('Add a Google account'));
  });
}
