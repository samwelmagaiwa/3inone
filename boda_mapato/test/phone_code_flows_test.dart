import 'package:boda_mapato/screens/auth/forgot_password_sheet.dart';
import 'package:boda_mapato/screens/auth/register_business_screen.dart';
import 'package:boda_mapato/screens/settings/backup_screen.dart';
import 'package:boda_mapato/services/auth_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The default app language is Swahili, so these are the Swahili texts.
const String _badCode = 'Weka nambari ya tarakimu 6';
const String _codeSent = 'Nambari imetumwa';

Widget _scaled(Widget child) => ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(800, 3200),
        minTextAdapt: true,
        builder: (_, __) => child,
      ),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

/// The register screen's starfield animates forever, so pumpAndSettle can never settle there.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  // ------------------------------------------- registering: confirm the phone

  group('registration: confirming the phone with the texted code', () {
    Future<void> fillAndSubmit(WidgetTester t) async {
      final Finder f = find.byType(TextFormField);
      await t.enterText(f.at(0), 'Asha Owner');
      await t.enterText(f.at(1), 'asha@example.test');
      await t.enterText(f.at(2), '0743519100');
      await t.enterText(f.at(3), 'secret-pass-1');
      await t.enterText(f.at(4), 'secret-pass-1');
      await t.enterText(f.at(5), 'Asha Rentals');
      await t.tap(find.byKey(const ValueKey<String>('service_rental')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey<String>('registration_submit')));
      await _settle(t);
    }

    Future<List<String>> pumpScreen(
      WidgetTester t, {
      required Map<String, dynamic> serverAnswer,
      Future<void> Function(String email, String code)? verify,
      Future<void> Function(String email)? resend,
    }) async {
      _tall(t);
      final List<String> calls = <String>[];
      await t.pumpWidget(_scaled(MaterialApp(
        home: RegisterBusinessScreen(
          onSubmit: (_) async => <String, dynamic>{'data': serverAnswer},
          onVerifyPhone: (String e, String c) async {
            calls.add('verify $e $c');
            await verify?.call(e, c);
          },
          onResendCode: (String e) async {
            calls.add('resend $e');
            await resend?.call(e);
          },
        ),
      )));
      await fillAndSubmit(t);

      return calls;
    }

    final Finder card = find.byKey(const ValueKey<String>('phone_code_card'));
    final Finder confirmed = find.byKey(const ValueKey<String>('phone_confirmed'));

    testWidgets('asks for the code that was texted, right after the application is sent', (t) async {
      await pumpScreen(t, serverAnswer: <String, dynamic>{'phone_verification_required': true, 'phone_verified': false});

      expect(find.byKey(const ValueKey<String>('registration_done_title')), findsOneWidget, reason: 'the application itself is in');
      expect(card, findsOneWidget);
      expect(find.textContaining('0743519100'), findsWidgets, reason: 'it says which number the code went to');
      expect(confirmed, findsNothing);
    });

    testWidgets('asks nothing when the phone does not need confirming', (t) async {
      await pumpScreen(t, serverAnswer: <String, dynamic>{'phone_verification_required': false, 'phone_verified': true});

      expect(card, findsNothing);
      expect(confirmed, findsOneWidget);
    });

    testWidgets('a code that is not 6 digits is not sent', (t) async {
      final List<String> calls = await pumpScreen(t, serverAnswer: <String, dynamic>{'phone_verification_required': true});

      await t.enterText(find.byKey(const ValueKey<String>('phone_code_field')), '123');
      await t.tap(find.byKey(const ValueKey<String>('registration_confirm_phone')));
      await _settle(t);

      expect(find.text(_badCode), findsOneWidget);
      expect(calls, isEmpty);
    });

    testWidgets('the right code confirms the phone and the card goes away', (t) async {
      final List<String> calls = await pumpScreen(t, serverAnswer: <String, dynamic>{'phone_verification_required': true});

      await t.enterText(find.byKey(const ValueKey<String>('phone_code_field')), '481516');
      await t.tap(find.byKey(const ValueKey<String>('registration_confirm_phone')));
      await _settle(t);

      expect(calls, <String>['verify asha@example.test 481516']);
      expect(card, findsNothing);
      expect(confirmed, findsOneWidget);
    });

    testWidgets("the server's reason for refusing a code is shown and the card stays", (t) async {
      await pumpScreen(
        t,
        serverAnswer: <String, dynamic>{'phone_verification_required': true},
        verify: (_, __) async => throw AuthHttpException(422, 'Nambari si sahihi au imeisha muda.'),
      );

      await t.enterText(find.byKey(const ValueKey<String>('phone_code_field')), '000000');
      await t.tap(find.byKey(const ValueKey<String>('registration_confirm_phone')));
      await _settle(t);

      expect(find.byKey(const ValueKey<String>('phone_code_error')), findsOneWidget);
      expect(find.textContaining('imeisha muda'), findsOneWidget);
      expect(card, findsOneWidget);
      expect(confirmed, findsNothing);
    });

    testWidgets('a new code can be asked for', (t) async {
      final List<String> calls = await pumpScreen(t, serverAnswer: <String, dynamic>{'phone_verification_required': true});

      await t.tap(find.byKey(const ValueKey<String>('registration_resend_code')));
      await _settle(t);

      expect(calls, <String>['resend asha@example.test']);
      expect(find.text(_codeSent), findsOneWidget);
      expect(card, findsOneWidget);
    });
  });

  // ------------------------------------------------------ forgot password

  group('forgot password: a code is texted, nothing is handed back', () {
    final Finder button = find.byType(ElevatedButton);

    Future<List<String>> pumpSheet(
      WidgetTester t, {
      Future<void> Function(String email, String phone)? request,
      Future<void> Function(String email, String code, String password)? reset,
    }) async {
      _tall(t);
      final List<String> calls = <String>[];
      await t.pumpWidget(_scaled(MaterialApp(
        home: Scaffold(
          body: ForgotPasswordSheet(
            onRequestCode: (String e, String p) async {
              calls.add('code $e $p');
              await request?.call(e, p);
            },
            onReset: (String e, String c, String pw) async {
              calls.add('reset $e $c $pw');
              await reset?.call(e, c, pw);
            },
          ),
        ),
      )));

      return calls;
    }

    Future<void> askForCode(WidgetTester t) async {
      await t.enterText(find.byType(TextFormField).at(0), 'asha@example.test');
      await t.enterText(find.byType(TextFormField).at(1), '0743519100');
      await t.tap(button);
      await t.pumpAndSettle();
    }

    testWidgets('step 1 asks for a code to be texted, then waits for it', (t) async {
      final List<String> calls = await pumpSheet(t);

      await askForCode(t);

      expect(calls, <String>['code asha@example.test 0743519100']);
      // Step 2 is showing: the code field is there, the email field is not.
      expect(find.text(LocalizationService.instance.translate('verification_code')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('reset_resend')), findsOneWidget);
    });

    testWidgets('a refused request stays on step 1 and shows why', (t) async {
      await pumpSheet(t, request: (_, __) async => throw AuthHttpException(503, 'Huduma ya ujumbe mfupi haipatikani sasa.'));

      await askForCode(t);

      expect(find.textContaining('haipatikani sasa'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('reset_resend')), findsNothing, reason: 'never moved on to step 2');
    });

    testWidgets('step 2 needs a 6-digit code and matching passwords before anything is sent', (t) async {
      final List<String> calls = await pumpSheet(t);
      await askForCode(t);

      // Bad code.
      await t.enterText(find.byType(TextFormField).at(0), '12');
      await t.enterText(find.byType(TextFormField).at(1), 'brand-new-pass-1');
      await t.enterText(find.byType(TextFormField).at(2), 'brand-new-pass-1');
      await t.tap(button);
      await t.pumpAndSettle();
      expect(find.text(_badCode), findsOneWidget);

      // Good code, passwords that differ.
      await t.enterText(find.byType(TextFormField).at(0), '481516');
      await t.enterText(find.byType(TextFormField).at(2), 'something-else-9');
      await t.tap(button);
      await t.pumpAndSettle();

      expect(calls.where((c) => c.startsWith('reset')), isEmpty);
    });

    testWidgets('the right code and a new password finish the reset', (t) async {
      final List<String> calls = await pumpSheet(t);
      await askForCode(t);

      await t.enterText(find.byType(TextFormField).at(0), '481516');
      await t.enterText(find.byType(TextFormField).at(1), 'brand-new-pass-1');
      await t.enterText(find.byType(TextFormField).at(2), 'brand-new-pass-1');
      await t.tap(button);
      await t.pumpAndSettle();

      expect(calls.last, 'reset asha@example.test 481516 brand-new-pass-1');
      expect(find.text(LocalizationService.instance.translate('password_reset_successfully')), findsOneWidget);
    });

    testWidgets('a wrong code shows the server\'s message and keeps the form', (t) async {
      await pumpSheet(t, reset: (_, __, ___) async => throw AuthHttpException(422, 'Nambari si sahihi au imeisha muda.'));
      await askForCode(t);

      await t.enterText(find.byType(TextFormField).at(0), '000000');
      await t.enterText(find.byType(TextFormField).at(1), 'brand-new-pass-1');
      await t.enterText(find.byType(TextFormField).at(2), 'brand-new-pass-1');
      await t.tap(button);
      await t.pumpAndSettle();

      expect(find.textContaining('imeisha muda'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('reset_resend')), findsOneWidget, reason: 'still on step 2');
    });

    testWidgets('a new code can be asked for from step 2', (t) async {
      final List<String> calls = await pumpSheet(t);
      await askForCode(t);

      await t.tap(find.byKey(const ValueKey<String>('reset_resend')));
      await t.pumpAndSettle();

      expect(calls.where((c) => c.startsWith('code')), hasLength(2));
      expect(find.byKey(const ValueKey<String>('reset_notice')), findsOneWidget);
    });
  });

  // ------------------------------------------------- restore needs typing

  group('restore: a tap is not enough', () {
    Future<bool?> openDialog(WidgetTester t) async {
      bool? answer;
      await t.pumpWidget(_scaled(MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                answer = await showDialog<bool>(
                  context: context,
                  builder: (_) => const TypeToConfirmDialog(word: 'RESTORE'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      return answer;
    }

    final Finder field = find.byKey(const ValueKey<String>('restore_confirm_field'));
    final Finder confirm = find.byKey(const ValueKey<String>('restore_confirm_button'));

    testWidgets('the button stays dead until the word is typed exactly', (t) async {
      await openDialog(t);
      bool enabled() => t.widget<TextButton>(confirm).onPressed != null;

      expect(enabled(), isFalse);
      await t.enterText(field, 'restor');
      await t.pump();
      expect(enabled(), isFalse);
      await t.enterText(field, 'yes');
      await t.pump();
      expect(enabled(), isFalse);

      await t.enterText(field, 'RESTORE');
      await t.pump();
      expect(enabled(), isTrue);
    });

    testWidgets('typing the word and confirming answers yes; cancelling answers no', (t) async {
      bool? answer;
      Future<void> run(Future<void> Function() act) async {
        await t.pumpWidget(_scaled(MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  answer = await showDialog<bool>(context: context, builder: (_) => const TypeToConfirmDialog(word: 'RESTORE'));
                },
                child: const Text('open'),
              ),
            ),
          ),
        )));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        await act();
        await t.pumpAndSettle();
      }

      await run(() async {
        await t.enterText(field, 'RESTORE');
        await t.pump();
        await t.tap(confirm);
      });
      expect(answer, isTrue);

      await run(() async {
        await t.tap(find.text(LocalizationService.instance.translate('cancel')));
      });
      expect(answer, isFalse);
    });
  });
}
