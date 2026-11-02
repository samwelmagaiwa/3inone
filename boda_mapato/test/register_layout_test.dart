import 'package:boda_mapato/models/business_registration.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/screens/auth/register_business_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_places.dart';

/// The registration form puts short fields side by side (name and phone, password and confirm, region and district, ward and street),
/// keeps the long ones full width, and sends where the business is as chosen from the imported locations or typed.
Future<void> _open(WidgetTester t, Widget screen, {double width = 800}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = Size(width, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: Size(width, 3200),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: screen),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));
Finder _fields() => find.byType(TextFormField);

/// The starfield behind the form animates forever, so pumpAndSettle can never settle on this screen: pump a little instead.
Future<void> _later(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pick(WidgetTester t, int level, String name) async {
  await t.tap(_key('place_select_$level'));
  await _later(t);
  await t.tap(find.text(name));
  await _later(t);
}

Future<void> _fillPeople(WidgetTester t) async {
  await t.enterText(_fields().at(0), 'Asha Owner');
  await t.enterText(_fields().at(1), '0743519100');
  await t.enterText(_fields().at(2), 'asha@example.test');
  await t.enterText(_fields().at(3), 'secret-pass-1');
  await t.enterText(_fields().at(4), 'secret-pass-1');
  await t.enterText(_fields().at(5), 'Asha Rentals');
  await t.tap(_key('service_rental'));
  await t.pump();
}

void main() {
  testWidgets('short fields sit in two columns and long ones take the whole width', (t) async {
    await _open(t, RegisterBusinessScreen(placeSource: FakePlaces()));

    final Offset name = t.getTopLeft(_fields().at(0));
    final Offset phone = t.getTopLeft(_fields().at(1));
    final Offset email = t.getTopLeft(_fields().at(2));
    final Offset password = t.getTopLeft(_fields().at(3));
    final Offset confirm = t.getTopLeft(_fields().at(4));

    expect(phone.dy, name.dy, reason: 'name and phone share a row');
    expect(phone.dx, greaterThan(name.dx));
    expect(email.dy, greaterThan(name.dy), reason: 'the email has a row of its own');
    expect(confirm.dy, password.dy, reason: 'password and confirm share a row');
    expect(password.dy, greaterThan(email.dy));

    final double half = t.getSize(_fields().at(0)).width;
    final double full = t.getSize(_fields().at(2)).width;
    expect(full, greaterThan(half * 1.8), reason: 'the email is as wide as both columns');

    final Offset region = t.getTopLeft(_key('place_select_0'));
    final Offset district = t.getTopLeft(_key('place_select_1'));
    final Offset ward = t.getTopLeft(_key('place_select_2'));
    final Offset street = t.getTopLeft(_key('place_select_3'));
    expect(district.dy, region.dy, reason: 'region and district share a row');
    expect(street.dy, ward.dy, reason: 'ward and street share a row');
    expect(ward.dy, greaterThan(region.dy));
    expect(district.dx, greaterThan(region.dx));
  });

  testWidgets('on a very narrow screen the pairs stack instead of being squeezed', (t) async {
    await _open(t, RegisterBusinessScreen(placeSource: FakePlaces()), width: 280);

    expect(t.getTopLeft(_fields().at(1)).dy, greaterThan(t.getTopLeft(_fields().at(0)).dy), reason: 'the phone is under the name');
    expect(t.getTopLeft(_key('place_select_1')).dy, greaterThan(t.getTopLeft(_key('place_select_0')).dy), reason: 'the district is under the region');
  });

  testWidgets('the region, district, ward and street chosen from the lists are what is sent', (t) async {
    BusinessRegistrationRequest? sent;
    await _open(
      t,
      RegisterBusinessScreen(
        placeSource: FakePlaces(),
        onLoadPlans: () async => throw Exception('offline'),
        onSubmit: (BusinessRegistrationRequest r) async {
          sent = r;
          return <String, dynamic>{'data': <String, dynamic>{'phone_verified': true}};
        },
      ),
    );
    await _fillPeople(t);
    await _pick(t, 0, 'Dar es Salaam');
    await _pick(t, 1, 'Kinondoni');
    await _pick(t, 2, 'Mikocheni');
    await _pick(t, 3, 'Mikocheni B');

    await t.ensureVisible(_key('registration_submit'));
    await t.tap(_key('registration_submit'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    final Map<String, dynamic> body = sent!.toJson();
    expect(<Object?>[body['region'], body['district'], body['ward'], body['street']], <Object?>['Dar es Salaam', 'Kinondoni', 'Mikocheni', 'Mikocheni B']);
  });

  testWidgets('places typed by hand (no list has them) are sent just the same, and the form is not blocked', (t) async {
    BusinessRegistrationRequest? sent;
    await _open(
      t,
      RegisterBusinessScreen(
        placeSource: const NoPlaces(),
        onLoadPlans: () async => throw Exception('offline'),
        onSubmit: (BusinessRegistrationRequest r) async {
          sent = r;
          return <String, dynamic>{'data': <String, dynamic>{'phone_verified': true}};
        },
      ),
    );
    await _fillPeople(t);
    await t.enterText(_key('place_text_0'), 'Kigoma');
    await t.pump();
    await t.enterText(_key('place_text_1'), 'Kigoma Ujiji');
    await t.pump();
    await t.enterText(_key('place_text_2'), 'Mwanga Kaskazini');
    await t.pump();
    await t.enterText(_key('place_text_3'), 'Katubuka');
    await t.pump();

    await t.ensureVisible(_key('registration_submit'));
    await t.tap(_key('registration_submit'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    final Map<String, dynamic> body = sent!.toJson();
    expect(<Object?>[body['region'], body['district'], body['ward'], body['street']], <Object?>['Kigoma', 'Kigoma Ujiji', 'Mwanga Kaskazini', 'Katubuka']);
  });

  testWidgets('no place at all is fine: the parts are left out of the request', (t) async {
    BusinessRegistrationRequest? sent;
    await _open(
      t,
      RegisterBusinessScreen(
        placeSource: FakePlaces(),
        onLoadPlans: () async => throw Exception('offline'),
        onSubmit: (BusinessRegistrationRequest r) async {
          sent = r;
          return <String, dynamic>{'data': <String, dynamic>{'phone_verified': true}};
        },
      ),
    );
    await _fillPeople(t);

    await t.ensureVisible(_key('registration_submit'));
    await t.tap(_key('registration_submit'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    final Map<String, dynamic> body = sent!.toJson();
    for (final String k in <String>['region', 'district', 'ward', 'street']) {
      expect(body.containsKey(k), isFalse, reason: k);
    }
  });

  testWidgets('someone who signed up first gives only their name, and still says where the business is', (t) async {
    await _open(
      t,
      RegisterBusinessScreen(
        placeSource: FakePlaces(),
        applicant: const ApplicantCredentials(email: 'asha@example.test', password: 'secret-pass-1'),
        onLoadPlans: () async => throw Exception('offline'),
      ),
    );

    expect(_fields().at(0), findsOneWidget);
    expect(find.text('Phone Number'), findsNothing);
    expect(_key('place_select_0'), findsOneWidget);
    expect(_key('place_select_3'), findsOneWidget);
  });

  test('the super admin reads the whole place, from the address down to the region', () {
    final BusinessRegistration r = BusinessRegistration.fromJson(<String, dynamic>{
      'id': 1,
      'status': 'pending',
      'business_name': 'Asha Shop',
      'requested_services': <String>['rental'],
      'region': 'Dar es Salaam',
      'district': 'Kinondoni',
      'ward': 'Mikocheni',
      'street': 'Mikocheni B',
      'address': 'Plot 12',
    });

    expect(r.ward, 'Mikocheni');
    expect(r.street, 'Mikocheni B');
    expect(r.location, 'Plot 12, Mikocheni B, Mikocheni, Kinondoni, Dar es Salaam');
  });
}
