import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/appointment_form_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Booking and changing an appointment: what is asked, what is offered (only services, only the people who can do
/// all of them), what is sent, and what happens when the stylist is already booked.
class _Saved {
  _Saved({this.id, this.customerId, required this.name, this.phone, this.staffId, required this.startsAt, required this.services, this.notes, required this.force});

  final int? id;
  final int? customerId;
  final String name;
  final String? phone;
  final String? staffId;
  final DateTime startsAt;
  final List<AppointmentService> services;
  final String? notes;
  final bool force;
}

class _FakeSalon extends SalonApi {
  final List<_Saved> saved = <_Saved>[];
  final List<Object> failures = <Object>[];
  final List<(double?, String?)> deposits = <(double?, String?)>[];

  @override
  Future<SalonAppointment> saveAppointment({
    int? id,
    int? customerId,
    required String clientName,
    String? clientPhone,
    String? staffId,
    required DateTime startsAt,
    required List<AppointmentService> services,
    String? notes,
    double? depositAmount,
    String? depositMethod,
    bool force = false,
  }) async {
    deposits.add((depositAmount, depositMethod));
    saved.add(_Saved(id: id, customerId: customerId, name: clientName, phone: clientPhone, staffId: staffId, startsAt: startsAt, services: services, notes: notes, force: force));
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return SalonAppointment(id: id ?? 1, clientName: clientName, startsAt: startsAt, endsAt: startsAt.add(const Duration(hours: 1)), status: 'booked', services: services, total: 0);
  }
}

class _Server extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{'data': <String, dynamic>{'inventory_type': 'retail', 'use_crates': '0', 'sale_tier': 'retail', 'prices_include_vat': '1', 'tax_percent': '0'}};
    }
    if (endpoint.startsWith('/inventory/salon/staff')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'u-asha', 'name': 'Asha', 'role': 'sales_officer'},
          <String, dynamic>{'id': 'u-bahati', 'name': 'Bahati', 'role': 'manager'},
        ],
      };
    }
    if (endpoint.startsWith('/inventory/customers')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 5, 'name': 'Rehema Juma', 'phone': '0711000002'},
          <String, dynamic>{'id': 6, 'name': 'Neema Ali', 'phone': '0722000003'},
        ],
      };
    }
    if (endpoint.startsWith('/inventory/products')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          _row(1, 'Braids', 40000, minutes: 180, options: <Map<String, dynamic>>[<String, dynamic>{'label': 'Short', 'price': 30000}, <String, dynamic>{'label': 'Long', 'price': 60000}]),
          _row(2, 'Wash', 5000, minutes: 30),
          _row(3, 'Bridal makeup', 150000, minutes: 120, staff: <String>['u-bahati']),
          _row(4, 'Shampoo', 8000, service: false),
          _row(5, 'Retired service', 1000, status: 'inactive'),
        ],
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }

  static Map<String, dynamic> _row(int id, String name, num price, {int? minutes, List<Map<String, dynamic>>? options, List<String>? staff, bool service = true, String status = 'active'}) => <String, dynamic>{
        'id': id, 'name': name, 'sku': 'P-$id', 'cost_price': 0, 'selling_price': price, 'unit': 'pcs', 'quantity': service ? 0 : 10, 'min_stock': 0,
        'status': status, 'is_service': service, 'duration_minutes': minutes, 'units': <dynamic>[],
        'price_options': options ?? <dynamic>[], 'staff_ids': staff ?? <dynamic>[],
      };
}

final DateTime _day = DateTime(2026, 10, 15);

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

class _Result {
  bool? popped;
}

Future<_Result> _open(WidgetTester t, _FakeSalon api, {SalonAppointment? appointment, bool sw = false}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final InventoryProvider inv = InventoryProvider(api: _Server());
  addTearDown(inv.dispose);
  final _Result result = _Result();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(411, 1800),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (BuildContext ctx) => Scaffold(
              body: TextButton(
                key: const ValueKey<String>('open_form'),
                onPressed: () async => result.popped = await Navigator.push<bool>(ctx, MaterialPageRoute<bool>(builder: (_) => AppointmentFormScreen(api: api, appointment: appointment, day: _day))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(_key('open_form'));
  await _settle(t);
  await t.pump(const Duration(seconds: 1));
  return result;
}

Future<void> _addService(WidgetTester t, String id) async {
  await t.tap(_key('appt_add_service'));
  await _settle(t);
  await t.tap(_key('appt_service_$id'));
  await _settle(t);
}

Future<void> _save(WidgetTester t) async {
  await t.ensureVisible(_key('appt_save'));
  await t.tap(_key('appt_save'));
  await _settle(t);
}

void main() {
  group('asking', () {
    testWidgets('a new appointment starts on the day the diary showed, at nine, with nothing chosen', (t) async {
      await _open(t, _FakeSalon());

      expect(find.text('New appointment'), findsOneWidget);
      expect(find.text('15/10/2026'), findsOneWidget);
      expect(find.text('09:00'), findsWidgets);
      expect(find.text('No service yet.'), findsOneWidget);
      expect(find.text('60 min'), findsNothing, reason: 'no summary time without a service: an hour is assumed, shown below');
    });

    testWidgets('only active services are offered: no goods, no retired service', (t) async {
      await _open(t, _FakeSalon());
      await t.tap(_key('appt_add_service'));
      await _settle(t);

      expect(find.text('Braids'), findsOneWidget);
      expect(find.text('Wash'), findsOneWidget);
      expect(find.text('Bridal makeup'), findsOneWidget);
      expect(find.text('Shampoo'), findsNothing);
      expect(find.text('Retired service'), findsNothing);
      expect(find.text('TSH 40,000 • 180 min'), findsOneWidget);
    });

    testWidgets('choosing services adds them up: their time and their price', (t) async {
      await _open(t, _FakeSalon());
      await _addService(t, '2');
      // Braids has price options: choose Long
      await t.tap(_key('appt_add_service'));
      await _settle(t);
      await t.tap(_key('appt_service_1'));
      await _settle(t);
      expect(find.text('Short'), findsOneWidget);
      await t.tap(_key('appt_option_Long'));
      await _settle(t);

      expect(find.text('Wash'), findsOneWidget);
      expect(find.text('Braids (Long)'), findsOneWidget);
      expect(find.text('TSH 65,000'), findsWidgets);
      expect(find.text('09:00–12:30 • 210 min'), findsOneWidget);
    });

    testWidgets('closing the price sheet without choosing adds nothing', (t) async {
      await _open(t, _FakeSalon());
      await t.tap(_key('appt_add_service'));
      await _settle(t);
      await t.tap(_key('appt_service_1'));
      await _settle(t);
      await t.tapAt(const Offset(200, 40)); // outside the sheet
      await _settle(t);

      expect(find.text('No service yet.'), findsOneWidget);
    });

    testWidgets('a service can be taken off again', (t) async {
      await _open(t, _FakeSalon());
      await _addService(t, '2');
      await t.tap(_key('appt_remove_0'));
      await t.pump();

      expect(find.text('No service yet.'), findsOneWidget);
    });

    testWidgets('only the people who can do every chosen service are offered', (t) async {
      await _open(t, _FakeSalon());
      expect(_key('appt_staff_u-asha'), findsOneWidget);
      expect(_key('appt_staff_u-bahati'), findsOneWidget);

      await _addService(t, '3'); // bridal makeup: Bahati only

      expect(_key('appt_staff_u-asha'), findsNothing);
      expect(_key('appt_staff_u-bahati'), findsOneWidget);
      expect(_key('appt_staff_note'), findsOneWidget);
    });

    testWidgets('a stylist chosen earlier who cannot do a service added later is let go', (t) async {
      await _open(t, _FakeSalon());
      await t.tap(_key('appt_staff_u-asha'));
      await t.pump();
      expect(t.widget<ChoiceChip>(_key('appt_staff_u-asha')).selected, isTrue);

      await _addService(t, '3');

      expect(t.widget<ChoiceChip>(_key('appt_staff_none')).selected, isTrue, reason: 'back to "not yet"');
    });
  });

  group('saving', () {
    testWidgets('without a name, or without a service, nothing is sent and it says so', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _open(t, api);

      await _save(t);
      expect(find.text('Write the name of the client.'), findsOneWidget);

      await t.enterText(_key('appt_name'), 'Neema');
      await _save(t);
      expect(find.text('Choose at least one service.'), findsOneWidget);
      expect(api.saved, isEmpty);
    });

    testWidgets('sends who, when, what, with whom and the notes, and closes saying it saved', (t) async {
      final _FakeSalon api = _FakeSalon();
      final _Result result = await _open(t, api);
      await t.enterText(_key('appt_name'), 'Neema Juma');
      await t.enterText(_key('appt_phone'), '0711 000001');
      await t.enterText(_key('appt_notes'), 'Bring extensions');
      await _addService(t, '2');
      await t.tap(_key('appt_staff_u-asha'));
      await t.pump();

      await _save(t);
      await t.pump(const Duration(seconds: 4));

      final _Saved s = api.saved.single;
      expect(s.id, isNull);
      expect(s.name, 'Neema Juma');
      expect(s.phone, '0711 000001');
      expect(s.staffId, 'u-asha');
      expect(s.startsAt, DateTime(2026, 10, 15, 9));
      expect(s.services.single.productId, 2);
      expect(s.services.single.price, 5000);
      expect(s.notes, 'Bring extensions');
      expect(s.force, isFalse);
      expect(result.popped, isTrue);
    });

    testWidgets('picking an existing client fills in their name and phone and sends their id', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _open(t, api);
      await t.tap(_key('appt_pick_client'));
      await _settle(t);
      await t.enterText(_key('appt_client_search'), 'rehema');
      await t.pump();
      expect(find.text('Neema Ali'), findsNothing);
      await t.tap(_key('appt_client_5'));
      await _settle(t);
      await _addService(t, '2');

      await _save(t);
      await t.pump(const Duration(seconds: 4));

      expect(api.saved.single.customerId, 5);
      expect(api.saved.single.name, 'Rehema Juma');
      expect(api.saved.single.phone, '0711000002');
    });

    testWidgets('a stylist who is already booked: the server\'s words are shown, and "book anyway" sends it again with force', (t) async {
      final _FakeSalon api = _FakeSalon()..failures.add(ApiException('Asha is already booked 09:00-10:00 (First).'));
      final _Result result = await _open(t, api);
      await t.enterText(_key('appt_name'), 'Neema');
      await _addService(t, '2');
      await t.tap(_key('appt_staff_u-asha'));
      await t.pump();

      await _save(t);

      expect(find.text('Stylist is booked'), findsOneWidget);
      expect(find.text('Asha is already booked 09:00-10:00 (First).'), findsWidgets);
      await t.tap(_key('appt_clash_force'));
      await _settle(t);
      await t.pump(const Duration(seconds: 4));

      expect(api.saved.map((_Saved s) => s.force).toList(), <bool>[false, true]);
      expect(result.popped, isTrue);
    });

    testWidgets('a stylist who is off that day, or does not work then, can also be booked anyway', (t) async {
      for (final String message in <String>['Asha is off on 13/10/2026.', 'Asha works 09:00-17:00.', 'Asha does not work on Saturdays (10/10/2026).']) {
        final _FakeSalon api = _FakeSalon()..failures.add(ApiException(message));
        final _Result result = await _open(t, api);
        await t.enterText(_key('appt_name'), 'Neema');
        await _addService(t, '2');
        await _save(t);

        expect(find.text('Stylist is booked'), findsOneWidget, reason: message);
        await t.tap(_key('appt_clash_force'));
        await _settle(t);
        await t.pump(const Duration(seconds: 4));

        expect(api.saved.map((_Saved x) => x.force).toList(), <bool>[false, true], reason: message);
        expect(result.popped, isTrue);
      }
    });

    testWidgets('"change the time" leaves the form open and sends nothing more', (t) async {
      final _FakeSalon api = _FakeSalon()..failures.add(ApiException('Asha is already booked 09:00-10:00 (First).'));
      final _Result result = await _open(t, api);
      await t.enterText(_key('appt_name'), 'Neema');
      await _addService(t, '2');
      await _save(t);

      await t.tap(_key('appt_clash_cancel'));
      await _settle(t);

      expect(api.saved, hasLength(1));
      expect(result.popped, isNull);
      expect(find.text('New appointment'), findsOneWidget);
    });

    testWidgets('any other refusal is shown on the form, and nothing closes', (t) async {
      final _FakeSalon api = _FakeSalon()..failures.add(ApiException('That person cannot be booked.'));
      final _Result result = await _open(t, api);
      await t.enterText(_key('appt_name'), 'Neema');
      await _addService(t, '2');

      await _save(t);

      expect(find.text('That person cannot be booked.'), findsOneWidget);
      expect(find.text('Stylist is booked'), findsNothing);
      expect(result.popped, isNull);
    });
  });

  group('changing one', () {
    SalonAppointment existing() => SalonAppointment(
          id: 9,
          customerId: 5,
          clientName: 'Rehema Juma',
          clientPhone: '0711000002',
          staffId: 'u-asha',
          staffName: 'Asha',
          startsAt: DateTime(2026, 10, 20, 14, 30),
          endsAt: DateTime(2026, 10, 20, 15),
          status: 'booked',
          services: const <AppointmentService>[AppointmentService(productId: 2, name: 'Wash', price: 5000, minutes: 30)],
          total: 5000,
          notes: 'Allergic to dye',
        );

    testWidgets('comes back filled in', (t) async {
      await _open(t, _FakeSalon(), appointment: existing());

      expect(find.text('Change appointment'), findsOneWidget);
      expect(find.text('Rehema Juma'), findsOneWidget);
      expect(find.text('0711000002'), findsOneWidget);
      expect(find.text('Allergic to dye'), findsOneWidget);
      expect(find.text('20/10/2026'), findsOneWidget);
      expect(find.text('14:30'), findsWidgets);
      expect(find.text('Wash'), findsOneWidget);
      expect(t.widget<ChoiceChip>(_key('appt_staff_u-asha')).selected, isTrue);
    });

    testWidgets('saving sends the same appointment again with its id', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _open(t, api, appointment: existing());
      await t.enterText(_key('appt_notes'), 'Allergic to dye, wants a wash first');

      await _save(t);
      await t.pump(const Duration(seconds: 4));

      final _Saved s = api.saved.single;
      expect(s.id, 9);
      expect(s.customerId, 5);
      expect(s.startsAt, DateTime(2026, 10, 20, 14, 30));
      expect(s.staffId, 'u-asha');
      expect(s.notes, 'Allergic to dye, wants a wash first');
    });
  });

  group('deposits', () {
    SalonAppointment withDeposit(String status) => SalonAppointment(
          id: 9,
          clientName: 'Rehema Juma',
          startsAt: DateTime(2026, 10, 20, 14, 30),
          endsAt: DateTime(2026, 10, 20, 15),
          status: 'booked',
          services: const <AppointmentService>[AppointmentService(productId: 2, name: 'Wash', price: 5000, minutes: 30)],
          total: 5000,
          depositAmount: 3000,
          depositMethod: 'mpesa',
          depositStatus: status,
        );

    testWidgets('a deposit is sent with the way it was paid, and the ways only show once there is a deposit', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _open(t, api, appointment: withDeposit('none'));
      expect(find.byKey(const ValueKey<String>('appt_deposit_mpesa')), findsOneWidget);
      await t.enterText(_key('appt_deposit'), '');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('appt_deposit_mpesa')), findsNothing);
      await t.enterText(_key('appt_deposit'), '5000');
      await t.pump();
      await t.ensureVisible(_key('appt_deposit_airtel_money'));
      await t.tap(_key('appt_deposit_airtel_money'));
      await t.pump();

      await _save(t);
      await t.pump(const Duration(seconds: 4));
      expect(api.deposits.single, (5000.0, 'airtel_money'));
    });

    testWidgets('a deposit already settled is shown, not editable, and not sent again', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _open(t, api, appointment: withDeposit('applied'));
      expect(find.byKey(const ValueKey<String>('appt_deposit_settled')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('appt_deposit')), findsNothing);

      await _save(t);
      await t.pump(const Duration(seconds: 4));
      expect(api.deposits.single.$1, isNull);
    });
  });

  testWidgets('in Swahili the form is Swahili', (t) async {
    await _open(t, _FakeSalon(), sw: true);

    expect(find.text('Miadi mpya'), findsOneWidget);
    expect(find.text('Mteja'), findsOneWidget);
    expect(find.text('Lini'), findsOneWidget);
    expect(find.text('Bado hakuna huduma.'), findsOneWidget);
    expect(find.text('Hifadhi miadi'), findsOneWidget);
  });
}
