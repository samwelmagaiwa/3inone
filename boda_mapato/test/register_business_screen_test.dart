import 'package:boda_mapato/models/business_registration.dart';
import 'package:boda_mapato/screens/auth/register_business_screen.dart';
import 'package:boda_mapato/services/auth_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// Default app language is Swahili, so these are the Swahili texts.
const String _required = 'Sehemu hii inahitajika';
const String _pickService = 'Chagua angalau huduma moja';
const String _badPhone =
    'Namba ya simu si sahihi (mfano 0743519100 au +255743519100)';

final Finder _submit = find.byKey(const ValueKey<String>('registration_submit'));

Widget _host(RegisterBusinessScreen screen) =>
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(800, 3200),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: screen),
      ),
    );

/// A tall surface so the whole (scrolling) form is built and tappable.
void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

/// The starfield background animates forever, so pumpAndSettle can never settle
/// on this screen; let the (instant) fake request finish and rebuild instead.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

Future<void> _fill(
  WidgetTester t, {
  String phone = '0743519100',
  String confirm = 'secret-pass-1',
  bool pickService = true,
}) async {
  final Finder f = find.byType(TextFormField);
  await t.enterText(f.at(0), 'Asha Owner'); // your name
  await t.enterText(f.at(1), 'asha@example.test');
  await t.enterText(f.at(2), phone);
  await t.enterText(f.at(3), 'secret-pass-1');
  await t.enterText(f.at(4), confirm);
  await t.enterText(f.at(5), 'Asha Rentals'); // business name
  await t.enterText(f.at(6), 'Dar es Salaam'); // region
  if (pickService) {
    await t.tap(find.byKey(const ValueKey<String>('service_transport')));
    await t.tap(find.byKey(const ValueKey<String>('service_rental')));
  }
  await t.pump();
}

void main() {
  testWidgets('an empty form is not sent and says what is missing', (t) async {
    _tall(t);
    int calls = 0;
    await t.pumpWidget(_host(RegisterBusinessScreen(
      onSubmit: (_) async => <String, dynamic>{'n': calls++},
    )));

    await t.tap(_submit);
    await t.pump();

    expect(find.text(_required), findsWidgets);
    expect(find.text(_pickService), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('a bad phone number or mismatched password is not sent',
      (t) async {
    _tall(t);
    int calls = 0;
    await t.pumpWidget(_host(RegisterBusinessScreen(
      onSubmit: (_) async => <String, dynamic>{'n': calls++},
    )));

    await _fill(t, phone: '12345', confirm: 'different');
    await t.tap(_submit);
    await t.pump();

    expect(find.text(_badPhone), findsOneWidget);
    expect(find.text(LocalizationService.instance.translate('passwords_do_not_match')),
        findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('a valid form sends exactly what was entered, then shows the waiting screen',
      (t) async {
    _tall(t);
    BusinessRegistrationRequest? sent;
    await t.pumpWidget(_host(RegisterBusinessScreen(
      onSubmit: (r) async {
        sent = r;
        return <String, dynamic>{'status': 'success'};
      },
    )));

    await _fill(t);
    await t.tap(_submit);
    await _settle(t);

    final Map<String, dynamic> body = sent!.toJson();
    expect(body['name'], 'Asha Owner');
    expect(body['business_name'], 'Asha Rentals');
    expect(body['email'], 'asha@example.test');
    expect(body['phone_number'], '0743519100');
    expect(body['password'], 'secret-pass-1');
    expect(body['password_confirmation'], 'secret-pass-1');
    // Always in the app's fixed order, whatever order they were tapped in.
    expect(body['requested_services'], <String>['rental', 'transport']);
    expect(body['region'], 'Dar es Salaam');
    // Empty optional fields are left out rather than sent blank.
    expect(body.containsKey('district'), isFalse);
    expect(body.containsKey('notes'), isFalse);
    // The form does not ask for an ID number (NIDA), so none is sent.
    expect(body.containsKey('id_number'), isFalse);

    expect(find.byKey(const ValueKey<String>('registration_done_title')), findsOneWidget);
    expect(find.textContaining('Asha Rentals'), findsOneWidget);
  });

  testWidgets('the form does not ask for an ID number (NIDA)', (t) async {
    _tall(t);
    await t.pumpWidget(_host(const RegisterBusinessScreen()));

    expect(find.textContaining('NIDA'), findsNothing);
    expect(find.textContaining('kitambulisho'), findsNothing);
    expect(find.byIcon(Icons.badge_outlined), findsNothing);
    // The optional location and notes fields are still there.
    expect(find.text('Mkoa'), findsOneWidget);
    expect(find.text('Maelezo ya ziada'), findsOneWidget);
  });

  testWidgets('a server rejection is shown and the input is kept', (t) async {
    _tall(t);
    await t.pumpWidget(_host(RegisterBusinessScreen(
      onSubmit: (_) async =>
          throw AuthHttpException(422, 'The email has already been taken.'),
    )));

    await _fill(t);
    await t.tap(_submit);
    await _settle(t);

    expect(find.byKey(const ValueKey<String>('registration_error')), findsOneWidget);
    expect(find.text('The email has already been taken.'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('registration_done_title')), findsNothing);
    expect(find.text('asha@example.test'), findsOneWidget, reason: 'what they typed is still there');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('no connection gives a plain message, not an exception dump',
      (t) async {
    _tall(t);
    await t.pumpWidget(_host(RegisterBusinessScreen(
      onSubmit: (_) async => throw Exception('SocketException: Failed host lookup'),
    )));

    await _fill(t);
    await t.tap(_submit);
    await _settle(t);

    expect(find.textContaining('Imeshindikana kuwasiliana na seva'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
  });

  testWidgets('prefilled initialEmail and initialPhone populate the form fields',
      (t) async {
    _tall(t);
    await t.pumpWidget(_host(const RegisterBusinessScreen(
      initialEmail: 'rejected_owner@example.test',
      initialPhone: '0788112233',
    )));

    expect(find.text('rejected_owner@example.test'), findsOneWidget);
    expect(find.text('0788112233'), findsOneWidget);
  });

  group('the kind of stock business', () {
    final Finder typeField = find.byKey(const ValueKey<String>('inventory_type_field'));

    testWidgets('is not asked for until inventory is chosen, and then shows a placeholder', (t) async {
      _tall(t);
      await t.pumpWidget(_host(const RegisterBusinessScreen()));

      expect(typeField, findsNothing);
      await t.tap(find.byKey(const ValueKey<String>('service_inventory')));
      await t.pump();

      expect(typeField, findsOneWidget);
      expect(find.text('Jumla, Rejareja, au ...'), findsOneWidget, reason: 'the placeholder names the choices');

      // Taking inventory off again takes the question away.
      await t.tap(find.byKey(const ValueKey<String>('service_inventory')));
      await t.pump();
      expect(typeField, findsNothing);
    });

    testWidgets('must be chosen before a registration with inventory is sent', (t) async {
      _tall(t);
      int calls = 0;
      await t.pumpWidget(_host(RegisterBusinessScreen(
        onSubmit: (_) async => <String, dynamic>{'n': calls++},
      )));

      await _fill(t, pickService: false);
      await t.tap(find.byKey(const ValueKey<String>('service_inventory')));
      await t.pump();
      await t.tap(_submit);
      await t.pump();

      expect(calls, 0);
      expect(find.byKey(const ValueKey<String>('inventory_type_error')), findsOneWidget);
    });

    testWidgets('is sent with the registration once chosen', (t) async {
      _tall(t);
      BusinessRegistrationRequest? sent;
      await t.pumpWidget(_host(RegisterBusinessScreen(
        onSubmit: (r) async {
          sent = r;
          return <String, dynamic>{'status': 'success'};
        },
      )));

      await _fill(t, pickService: false);
      await t.tap(find.byKey(const ValueKey<String>('service_inventory')));
      await t.pump();
      await t.tap(typeField);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Jumla (Wholesale)').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey<String>('inventory_type_hint')), findsOneWidget);
      await t.tap(_submit);
      await _settle(t);

      expect(sent!.toJson()['inventory_type'], 'wholesale');
      expect(sent!.toJson()['requested_services'], <String>['inventory']);
    });

    testWidgets('is left out when inventory is not one of the services', (t) async {
      _tall(t);
      BusinessRegistrationRequest? sent;
      await t.pumpWidget(_host(RegisterBusinessScreen(
        onSubmit: (r) async {
          sent = r;
          return <String, dynamic>{'status': 'success'};
        },
      )));

      await _fill(t);
      await t.tap(_submit);
      await _settle(t);

      expect(sent!.toJson().containsKey('inventory_type'), isFalse);
    });
  });
}
