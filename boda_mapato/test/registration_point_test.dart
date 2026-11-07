import 'package:boda_mapato/models/business_registration.dart';
import 'package:boda_mapato/modules/inventory/services/device_identity.dart';
import 'package:boda_mapato/screens/admin/registrations_screen.dart';
import 'package:boda_mapato/screens/auth/register_business_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_places.dart';

/// Where the business is: the applicant taps "capture my current location" at the business, and the super admin, deciding on the request,
/// sees the point and can open it on a map. (Default app language is Swahili, so these are the Swahili texts.)
Finder _key(String k) => find.byKey(ValueKey<String>(k));

Widget _host(Widget screen) => ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(800, 3200), minTextAdapt: true, builder: (_, __) => MaterialApp(home: screen)),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

Future<void> _fill(WidgetTester t) async {
  await t.pump();
  final Finder f = find.byType(TextFormField);
  await t.enterText(f.at(0), 'Asha Owner');
  await t.enterText(f.at(1), '0743519100');
  await t.enterText(f.at(2), 'asha@example.test');
  await t.enterText(f.at(3), 'secret-pass-1');
  await t.enterText(f.at(4), 'secret-pass-1');
  await t.enterText(f.at(5), 'Asha Rentals');
  await t.enterText(f.at(6), 'Dar es Salaam');
  await t.tap(_key('service_rental'));
  await t.pump();
}

class _Source implements RegistrationsDataSource {
  _Source(this.items);

  final List<BusinessRegistration> items;

  @override
  Future<RegistrationsPage> load(String status, {String? query}) async => RegistrationsPage(items: items, counts: <String, int>{'pending': items.length, 'approved': 0, 'rejected': 0});

  @override
  Future<void> approve(String id, List<String> services, {bool allowUnverified = false, String? plan, DateTime? validUntil, String? inventoryType}) async {}

  @override
  Future<void> reject(String id, String reason) async {}
}

BusinessRegistration _reg({double? lat, double? lng}) => BusinessRegistration.fromJson(<String, dynamic>{
      'id': '1',
      'status': 'pending',
      'business_name': 'Asha Rentals',
      'requested_services': <String>['rental'],
      'region': 'Dar es Salaam',
      'latitude': lat,
      'longitude': lng,
      'location_accuracy_m': lat == null ? null : 8.0,
      'map_url': lat == null ? null : 'https://www.google.com/maps?q=$lat,$lng',
      'user': <String, dynamic>{'id': 'u1', 'name': 'Asha Owner', 'email': 'asha@example.test', 'phone_number': '0743519100', 'phone_verified': true},
    });

void main() {
  group('the registration form', () {
    testWidgets('capturing the location shows the point and sends it with the request', (t) async {
      _tall(t);
      BusinessRegistrationRequest? sent;
      await t.pumpWidget(_host(RegisterBusinessScreen(
        placeSource: const NoPlaces(),
        locate: () async => const PhonePlace(latitude: -6.79234, longitude: 39.20831, accuracy: 7.4),
        onSubmit: (r) async {
          sent = r;
          return <String, dynamic>{'status': 'success'};
        },
      )));
      await _fill(t);

      await t.ensureVisible(_key('capture_business_point'));
      await t.tap(_key('capture_business_point'));
      await _settle(t);
      expect((t.widget(_key('business_point_text')) as Text).data, 'Eneo limechukuliwa: -6.79234, 39.20831 (± 7 m)');

      await t.tap(_key('registration_submit'));
      await _settle(t);
      final Map<String, dynamic> body = sent!.toJson();
      expect(body['latitude'], -6.79234);
      expect(body['longitude'], 39.20831);
      expect(body['location_accuracy'], 7.4);
    });

    testWidgets('without a capture no point is sent, and a captured one can be removed', (t) async {
      _tall(t);
      await t.pumpWidget(_host(RegisterBusinessScreen(placeSource: const NoPlaces(), locate: () async => const PhonePlace(latitude: -6.8, longitude: 39.2, accuracy: 5))));
      await t.pump();

      await t.ensureVisible(_key('capture_business_point'));
      await t.tap(_key('capture_business_point'));
      await _settle(t);
      expect(_key('business_point_text'), findsOneWidget);
      await t.tap(_key('clear_business_point'));
      await t.pump();

      expect(_key('business_point_text'), findsNothing);
      expect(const BusinessRegistrationRequest(name: 'a', businessName: 'b', email: 'e', phoneNumber: '0', password: 'p', passwordConfirmation: 'p', requestedServices: <String>['rental']).toJson().containsKey('latitude'), isFalse);
    });

    testWidgets('a phone that cannot find itself, or a weak GPS signal, is told so and nothing is kept', (t) async {
      _tall(t);
      PhonePlace? answer;
      await t.pumpWidget(_host(RegisterBusinessScreen(placeSource: const NoPlaces(), locate: () async => answer)));
      await t.pump();

      await t.ensureVisible(_key('capture_business_point'));
      await t.tap(_key('capture_business_point'));
      await _settle(t);
      expect(find.textContaining('Simu haikupata mahali'), findsOneWidget);
      expect(_key('business_point_text'), findsNothing);

      answer = const PhonePlace(latitude: -6.8, longitude: 39.2, accuracy: 350);
      await t.tap(_key('capture_business_point'));
      await _settle(t);
      expect(find.textContaining('Mawasiliano ya GPS ni hafifu (± 350 m)'), findsOneWidget);
      expect(_key('business_point_text'), findsNothing);
    });
  });

  group('the super admin deciding on the request', () {
    Future<void> open(WidgetTester t, BusinessRegistration r) async {
      _tall(t);
      await t.pumpWidget(_host(RegistrationsScreen(dataSource: _Source(<BusinessRegistration>[r]))));
      await t.pumpAndSettle();
      await t.tap(find.text(r.businessName));
      await t.pumpAndSettle();
    }

    testWidgets('sees the captured spot with its accuracy and a button that opens it on the map', (t) async {
      await open(t, _reg(lat: -6.79234, lng: 39.20831));

      expect((t.widget(_key('registration_point')) as Text).data, '-6.79234, 39.20831 (± 8 m)');
      expect(_key('open_registration_map'), findsOneWidget);
      expect(find.text('Fungua kwenye ramani'), findsOneWidget);
    });

    testWidgets('sees no map row when the applicant captured nothing', (t) async {
      await open(t, _reg());

      expect(_key('registration_point'), findsNothing);
      expect(_key('open_registration_map'), findsNothing);
    });
  });
}
