import 'dart:async';

import 'package:boda_mapato/modules/inventory/models/inv_sale.dart';
import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/appointments_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The salon's diary: a day at a time, with what can be done to each appointment.
class _FakeSalon extends SalonApi {
  _FakeSalon({Map<String, List<SalonAppointment>>? days}) : days = days ?? <String, List<SalonAppointment>>{};

  final Map<String, List<SalonAppointment>> days;
  final List<String> asked = <String>[];
  final List<(int, String)> statuses = <(int, String)>[];
  final List<bool> reminders = <bool>[];
  RebookSettings settingsNow = const RebookSettings(enabled: false, weeks: 4);
  Object? failStatus;
  Object? failReminders;
  Future<List<SalonAppointment>> Function(DateTime day)? onAsk;

  static String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<List<SalonAppointment>> appointments(DateTime day) async {
    asked.add(key(day));
    if (onAsk != null) return onAsk!(day);
    return days[key(day)] ?? <SalonAppointment>[];
  }

  @override
  Future<RebookSettings> salonSettings() async => settingsNow;

  @override
  Future<RebookSettings> saveAppointmentReminders(bool on) async {
    reminders.add(on);
    if (failReminders != null) throw failReminders!;
    settingsNow = settingsNow.copyWith(appointmentReminders: on);
    return settingsNow;
  }

  @override
  Future<SalonAppointment> setAppointmentStatus(int id, String status) async {
    statuses.add((id, status));
    if (failStatus != null) throw failStatus!;
    for (final List<SalonAppointment> list in days.values) {
      final int i = list.indexWhere((SalonAppointment a) => a.id == id);
      if (i >= 0) {
        final SalonAppointment a = list[i];
        list[i] = SalonAppointment(
          id: a.id, customerId: a.customerId, clientName: a.clientName, clientPhone: a.clientPhone, staffId: a.staffId, staffName: a.staffName,
          startsAt: a.startsAt, endsAt: a.endsAt, status: status, services: a.services, total: a.total, notes: a.notes,
        );
        return list[i];
      }
    }
    throw ApiException('Appointment not found');
  }
}

class _Products extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{'data': <String, dynamic>{'inventory_type': 'retail', 'use_crates': '0', 'sale_tier': 'retail', 'prices_include_vat': '1', 'tax_percent': '0'}};
    }
    if (endpoint.startsWith('/inventory/products')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          _row(1, 'Braids', 40000, minutes: 180),
          _row(2, 'Wash', 5000, minutes: 30),
        ],
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }

  static Map<String, dynamic> _row(int id, String name, num price, {int? minutes}) => <String, dynamic>{
        'id': id, 'name': name, 'sku': 'P-$id', 'cost_price': 0, 'selling_price': price, 'unit': 'pcs', 'quantity': 0, 'min_stock': 0,
        'status': 'active', 'is_service': true, 'duration_minutes': minutes, 'units': <dynamic>[],
      };
}

SalonAppointment _appt(int id, String client, String start, String end, {String status = 'booked', String? staff, String? staffId, double total = 45000, List<AppointmentService>? services, int? customerId, String? notes, String? phone}) => SalonAppointment(
      id: id,
      customerId: customerId,
      clientName: client,
      clientPhone: phone,
      staffId: staffId,
      staffName: staff,
      startsAt: DateTime.parse(start),
      endsAt: DateTime.parse(end),
      status: status,
      services: services ?? const <AppointmentService>[AppointmentService(productId: 1, name: 'Braids', price: 40000, minutes: 180), AppointmentService(productId: 2, name: 'Wash', price: 5000, minutes: 30)],
      total: total,
      notes: notes,
    );

final DateTime _today = DateTime(2026, 10, 15);

late InventoryProvider _inv;

Future<void> _open(WidgetTester t, _FakeSalon api, {bool sw = false}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  _inv = InventoryProvider(api: _Products());
  addTearDown(_inv.dispose);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: _inv),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(411, 1400),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: Scaffold(body: AppointmentsScreen(api: api, today: _today))),
      ),
    ),
  );
  for (int i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  group('the day', () {
    testWidgets('lists the day\'s appointments with time, client, services, stylist and total, in the order given', (t) async {
      final _FakeSalon api = _FakeSalon(days: <String, List<SalonAppointment>>{
        '2026-10-15': <SalonAppointment>[
          _appt(1, 'Neema', '2026-10-15 09:00', '2026-10-15 12:30', staff: 'Asha', staffId: 'u-asha', notes: 'Bring extensions', phone: '0711000001'),
          _appt(2, 'Rehema', '2026-10-15 14:00', '2026-10-15 14:30', status: 'confirmed', total: 5000, services: const <AppointmentService>[AppointmentService(productId: 2, name: 'Wash', price: 5000, label: 'Long')]),
        ],
      });
      await _open(t, api);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('15/10/2026'), findsOneWidget);
      expect(find.text('2 appointments'), findsOneWidget);
      expect(find.text('09:00–12:30'), findsOneWidget);
      expect(find.text('Neema'), findsOneWidget);
      expect(find.text('0711000001'), findsOneWidget);
      expect(find.text('Braids, Wash'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('TSH 45,000'), findsOneWidget);
      expect(find.text('Bring extensions'), findsOneWidget);
      expect(find.text('Booked'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Wash (Long)'), findsOneWidget, reason: 'the price option it was booked with');
      expect(find.text('No stylist yet'), findsOneWidget);
      expect(t.getTopLeft(_key('appt_1')).dy, lessThan(t.getTopLeft(_key('appt_2')).dy));
    });

    testWidgets('an empty day says what to do', (t) async {
      await _open(t, _FakeSalon());

      expect(find.text('No appointments this day. Tap "Book an appointment".'), findsOneWidget);
      expect(find.text('Book an appointment'), findsOneWidget);
    });

    testWidgets('one appointment is "1 appointment"', (t) async {
      await _open(t, _FakeSalon(days: <String, List<SalonAppointment>>{'2026-10-15': <SalonAppointment>[_appt(1, 'Neema', '2026-10-15 09:00', '2026-10-15 10:00')]}));

      expect(find.text('1 appointment'), findsOneWidget);
    });

    testWidgets('the arrows ask for the day before and the day after, and "back to today" returns', (t) async {
      final _FakeSalon api = _FakeSalon(days: <String, List<SalonAppointment>>{'2026-10-16': <SalonAppointment>[_appt(7, 'Tomorrow client', '2026-10-16 09:00', '2026-10-16 10:00')]});
      await _open(t, api);

      await t.tap(_key('appt_next'));
      await _settle(t);
      expect(api.asked.last, '2026-10-16');
      expect(find.text('Tomorrow client'), findsOneWidget);
      expect(find.text('16/10/2026'), findsOneWidget);
      expect(find.text('Friday'), findsOneWidget);
      expect(_key('appt_today'), findsOneWidget);

      await t.tap(_key('appt_today'));
      await _settle(t);
      expect(api.asked.last, '2026-10-15');
      expect(find.text('Tomorrow client'), findsNothing);
      expect(_key('appt_today'), findsNothing, reason: 'already on today');

      await t.tap(_key('appt_prev'));
      await _settle(t);
      expect(api.asked.last, '2026-10-14');
    });

    testWidgets('a slow answer for a day nobody is looking at any more is thrown away', (t) async {
      final Completer<List<SalonAppointment>> slow = Completer<List<SalonAppointment>>();
      int calls = 0;
      final _FakeSalon api = _FakeSalon();
      api.onAsk = (DateTime day) {
        calls++;
        return calls == 1 ? slow.future : Future<List<SalonAppointment>>.value(<SalonAppointment>[_appt(2, 'Right day', '2026-10-16 09:00', '2026-10-16 10:00')]);
      };
      await _open(t, api);

      await t.tap(_key('appt_next'));
      await _settle(t);
      slow.complete(<SalonAppointment>[_appt(1, 'Wrong day', '2026-10-15 09:00', '2026-10-15 10:00')]);
      await _settle(t);

      expect(find.text('Right day'), findsOneWidget);
      expect(find.text('Wrong day'), findsNothing);
    });

    testWidgets('a failed load says why and can be retried', (t) async {
      final _FakeSalon api = _FakeSalon();
      int calls = 0;
      api.onAsk = (DateTime day) async {
        calls++;
        if (calls == 1) throw ApiException('Server is down');
        return <SalonAppointment>[_appt(1, 'Back again', '2026-10-15 09:00', '2026-10-15 10:00')];
      };
      await _open(t, api);

      expect(find.text('Server is down'), findsOneWidget);
      await t.tap(_key('appt_retry'));
      await _settle(t);

      expect(find.text('Back again'), findsOneWidget);
    });
  });

  group('what can be done to an appointment', () {
    Future<_FakeSalon> openWith(WidgetTester t, String status, {bool sw = false}) async {
      final _FakeSalon api = _FakeSalon(days: <String, List<SalonAppointment>>{'2026-10-15': <SalonAppointment>[_appt(1, 'Neema', '2026-10-15 09:00', '2026-10-15 10:00', status: status, staff: 'Asha', staffId: 'u-asha')]});
      await _open(t, api, sw: sw);
      await t.tap(_key('appt_1'));
      await _settle(t);
      return api;
    }

    testWidgets('a new booking can be confirmed, started, finished, changed, marked no-show or cancelled', (t) async {
      await openWith(t, 'booked');

      for (final String k in <String>['appt_confirm', 'appt_start', 'appt_sell', 'appt_edit', 'appt_noshow', 'appt_cancel']) {
        expect(_key(k), findsOneWidget, reason: k);
      }
    });

    testWidgets('a confirmed one is no longer offered "confirm"', (t) async {
      await openWith(t, 'confirmed');

      expect(_key('appt_confirm'), findsNothing);
      expect(_key('appt_start'), findsOneWidget);
    });

    testWidgets('one in progress can only be finished, changed or cancelled', (t) async {
      await openWith(t, 'in_progress');

      expect(_key('appt_sell'), findsOneWidget);
      expect(_key('appt_edit'), findsOneWidget);
      expect(_key('appt_cancel'), findsOneWidget);
      expect(_key('appt_start'), findsNothing);
      expect(_key('appt_noshow'), findsNothing);
    });

    for (final String status in <String>['done', 'cancelled', 'no_show']) {
      testWidgets('a $status appointment is final: nothing can be done to it', (t) async {
        await openWith(t, status);

        expect(find.text('This appointment is finished: it can no longer be changed.'), findsOneWidget);
        for (final String k in <String>['appt_confirm', 'appt_start', 'appt_sell', 'appt_edit', 'appt_noshow', 'appt_cancel']) {
          expect(_key(k), findsNothing, reason: k);
        }
      });
    }

    testWidgets('confirming asks the server and shows the new state', (t) async {
      final _FakeSalon api = await openWith(t, 'booked');

      await t.tap(_key('appt_confirm'));
      await _settle(t);

      expect(api.statuses, <(int, String)>[(1, 'confirmed')]);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Booked'), findsNothing);
    });

    testWidgets('cancelling and no-show send their own state', (t) async {
      final _FakeSalon api = await openWith(t, 'booked');
      await t.tap(_key('appt_cancel'));
      await _settle(t);
      expect(api.statuses.last, (1, 'cancelled'));
      expect(find.text('Cancelled'), findsOneWidget);
    });

    testWidgets('when the server refuses, its words are shown and the card stays as it was', (t) async {
      final _FakeSalon api = await openWith(t, 'booked');
      api.failStatus = ApiException('An appointment that is done cannot become cancelled.');

      await t.tap(_key('appt_cancel'));
      await _settle(t);

      expect(find.text('An appointment that is done cannot become cancelled.'), findsOneWidget);
      expect(find.text('Booked'), findsOneWidget);
      await t.pump(const Duration(seconds: 4)); // the message goes away by itself
    });

    testWidgets('the actions are in Swahili in Swahili', (t) async {
      await openWith(t, 'booked', sw: true);

      expect(find.text('Thibitisha'), findsOneWidget);
      expect(find.text('Ameanza'), findsOneWidget);
      expect(find.text('Imekamilika: weka kwenye mauzo'), findsOneWidget);
      expect(find.text('Hakuja'), findsOneWidget);
      expect(find.text('Ghairi'), findsOneWidget);
    });

    testWidgets('"done: put it in Sales" fills the cart with the services, who did them and the booked price, and marks it done', (t) async {
      final _FakeSalon api = _FakeSalon(days: <String, List<SalonAppointment>>{
        '2026-10-15': <SalonAppointment>[
          _appt(1, 'Neema', '2026-10-15 09:00', '2026-10-15 12:30', staff: 'Asha', staffId: 'u-asha', customerId: 5, services: const <AppointmentService>[
            AppointmentService(productId: 1, name: 'Braids', price: 60000, minutes: 180, label: 'Long'),
            AppointmentService(productId: 2, name: 'Wash', price: 4000, minutes: 30),
          ]),
        ],
      });
      await _open(t, api);
      await _inv.fetchProducts();
      await t.tap(_key('appt_1'));
      await _settle(t);

      await t.tap(_key('appt_sell'));
      await _settle(t);

      expect(_inv.cart.map((InvSaleItem i) => i.name).toList(), <String>['Braids (Long)', 'Wash']);
      expect(_inv.cart.map((InvSaleItem i) => i.unitPrice).toList(), <double>[60000, 4000], reason: 'the price option, and the price agreed for the wash');
      expect(_inv.cart.every((InvSaleItem i) => i.staffId == 'u-asha' && i.staffName == 'Asha'), isTrue);
      expect(_inv.selectedCustomerId, 5);
      expect(api.statuses.last, (1, 'done'));
      expect(find.text('Added to Sales. Open Sales to take the payment.'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });
  });

  group('the reminder switch', () {
    testWidgets('shows the setting and saves a change', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _open(t, api);

      expect(t.widget<Switch>(_key('appt_reminders_switch')).value, isFalse);
      await t.tap(_key('appt_reminders_switch'));
      await _settle(t);

      expect(api.reminders, <bool>[true]);
      expect(t.widget<Switch>(_key('appt_reminders_switch')).value, isTrue);
    });

    testWidgets('a refusal puts it back and says why', (t) async {
      final _FakeSalon api = _FakeSalon()..failReminders = ApiException('Not allowed');
      await _open(t, api);

      await t.tap(_key('appt_reminders_switch'));
      await _settle(t);

      expect(t.widget<Switch>(_key('appt_reminders_switch')).value, isFalse);
      expect(find.text('Not allowed'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });
  });

  testWidgets('in Swahili the page is Swahili', (t) async {
    await _open(t, _FakeSalon(days: <String, List<SalonAppointment>>{'2026-10-15': <SalonAppointment>[_appt(1, 'Neema', '2026-10-15 09:00', '2026-10-15 10:00')]}), sw: true);

    expect(find.text('Leo'), findsOneWidget);
    expect(find.text('Weka miadi'), findsOneWidget);
    expect(find.text('Miadi 1'), findsOneWidget);
    expect(find.text('Imewekwa'), findsOneWidget);
    expect(find.text('Mhudumu bado'), findsOneWidget);
    expect(find.text('Mkumbushe mteja siku moja kabla (SMS)'), findsOneWidget);
  });
}
