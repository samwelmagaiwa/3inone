import 'dart:typed_data';

import 'package:boda_mapato/modules/inventory/screens/salon/export_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/offers_screens.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/salon_settings_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSalon extends SalonApi {
  Map<String, dynamic> settings = <String, dynamic>{
    'rebook_enabled': false,
    'appointment_reminders': false,
    'daily_summary': false,
    'feedback_sms': false,
    'birthday_offer': false,
    'birthday_text': '',
    'cancel_hours': 24,
    'online_booking': false,
    'booking_slug': 'glow',
    'booking_url': 'https://x.test/book/glow',
  };
  Map<String, dynamic> loyalty = <String, dynamic>{'on': false, 'per': 1000, 'value': 50, 'referral': 5};
  final List<Map<String, dynamic>> settingSaves = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> loyaltySaves = <Map<String, dynamic>>[];
  Object? failSave;

  List<Map<String, dynamic>> voucherRows = <Map<String, dynamic>>[
    <String, dynamic>{'id': 1, 'code': 'WELCOME', 'kind': 'percent', 'value': 10, 'used_count': 2, 'max_uses': 5, 'active': true, 'usable': true},
  ];
  final List<Map<String, dynamic>> voucherSaves = <Map<String, dynamic>>[];
  final List<(String, String)> sent = <(String, String)>[];
  final List<String> exports = <String>[];

  @override
  Future<Map<String, dynamic>> salonSettingsMap() async => settings;

  @override
  Future<Map<String, dynamic>> saveSalonSettingsMap(Map<String, dynamic> body) async {
    if (failSave != null) throw failSave!;
    settingSaves.add(body);
    settings = <String, dynamic>{...settings, ...body};
    return settings;
  }

  @override
  Future<Map<String, dynamic>> loyaltySettings() async => loyalty;

  @override
  Future<Map<String, dynamic>> saveLoyaltySettings(Map<String, dynamic> body) async {
    loyaltySaves.add(body);
    loyalty = <String, dynamic>{...loyalty, ...body};
    return loyalty;
  }

  @override
  Future<List<Map<String, dynamic>>> vouchers() async => voucherRows;

  @override
  Future<void> saveVoucher(Map<String, dynamic> body, {int? id}) async => voucherSaves.add(<String, dynamic>{...body, 'id': id});

  @override
  Future<Map<String, dynamic>> campaigns() async => <String, dynamic>{
        'segments': <Map<String, dynamic>>[
          <String, dynamic>{'segment': 'all', 'members': 10, 'reachable': 8},
          <String, dynamic>{'segment': 'new', 'members': 3, 'reachable': 2},
        ],
        'campaigns': <Map<String, dynamic>>[],
      };

  @override
  Future<void> sendCampaign({required String segment, required String message, String? name}) async => sent.add((segment, message));

  @override
  Future<Uint8List> exportReport(String type, {required String format, required bool sw, required DateTime from, required DateTime to}) async {
    exports.add('$type|$format|${from.toIso8601String().substring(0, 10)}|${to.toIso8601String().substring(0, 10)}');
    return Uint8List.fromList(<int>[1, 2, 3]);
  }
}

Future<void> _pump(WidgetTester t, Widget screen) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance, child: MaterialApp(home: Scaffold(body: screen))));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('a switch saves at once and says so', (WidgetTester t) async {
    final _FakeSalon api = _FakeSalon();
    await _pump(t, SalonSettingsScreen(api: api));
    await t.tap(find.byKey(const Key('set_feedback')));
    await t.pump();
    expect(api.settingSaves.single, <String, dynamic>{'feedback_sms': true});
    expect(find.text('https://x.test/book/glow'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('text fields save with their button, loyalty goes to its own endpoint', (WidgetTester t) async {
    final _FakeSalon api = _FakeSalon();
    await _pump(t, SalonSettingsScreen(api: api));
    await t.enterText(find.byKey(const Key('set_cancel')), '12');
    await t.tap(find.byKey(const Key('set_cancel_save')));
    await t.pump();
    expect(api.settingSaves.last, <String, dynamic>{'cancel_hours': 12});

    await t.enterText(find.byKey(const Key('set_slug')), 'Glow-Salon');
    await t.tap(find.byKey(const Key('set_slug_save')));
    await t.pump();
    expect(api.settingSaves.last, <String, dynamic>{'booking_slug': 'glow-salon'});

    await t.tap(find.byKey(const Key('set_loyalty')));
    await t.pump();
    expect(api.loyaltySaves.single, <String, dynamic>{'on': true});
    await t.enterText(find.byKey(const Key('set_per')), '2000');
    await t.ensureVisible(find.byKey(const Key('set_loyalty_save')));
    await t.tap(find.byKey(const Key('set_loyalty_save')));
    await t.pump();
    expect(api.loyaltySaves.last['per'], 2000);
    expect(api.settingSaves.any((Map<String, dynamic> m) => m.containsKey('per')), isFalse);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('a refused save shows the server words', (WidgetTester t) async {
    final _FakeSalon api = _FakeSalon()..failSave = Exception('Weka anwani kwanza');
    await _pump(t, SalonSettingsScreen(api: api));
    await t.tap(find.byKey(const Key('set_online')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Weka anwani kwanza'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('vouchers are checked before saving and switched off with the switch', (WidgetTester t) async {
    final _FakeSalon api = _FakeSalon();
    await _pump(t, VouchersScreen(api: api));
    expect(find.textContaining('WELCOME'), findsOneWidget);

    await t.tap(find.byKey(const Key('voucher_switch_1')));
    await t.pump();
    expect(api.voucherSaves.single, <String, dynamic>{'active': false, 'id': 1});

    await t.tap(find.byKey(const Key('voucher_add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('voucher_code')), 'ab');
    await t.tap(find.byKey(const Key('voucher_save')));
    await t.pump();
    expect(find.textContaining('at least 3'), findsOneWidget);
    await t.enterText(find.byKey(const Key('voucher_code')), 'summer');
    await t.enterText(find.byKey(const Key('voucher_value')), '150');
    await t.tap(find.byKey(const Key('voucher_save')));
    await t.pump();
    expect(find.textContaining('more than 100'), findsOneWidget);
    await t.enterText(find.byKey(const Key('voucher_value')), '15');
    await t.tap(find.byKey(const Key('voucher_save')));
    await t.pumpAndSettle();
    expect(api.voucherSaves.last, <String, dynamic>{'code': 'SUMMER', 'kind': 'percent', 'value': 15.0, 'id': null});
  });

  testWidgets('a message goes to the chosen group and shows how many can be texted', (WidgetTester t) async {
    final _FakeSalon api = _FakeSalon();
    await _pump(t, CampaignsScreen(api: api));
    expect(find.text('Can be texted: 8'), findsOneWidget);
    await t.tap(find.byKey(const Key('seg_new')));
    await t.pump();
    expect(find.text('Can be texted: 2'), findsOneWidget);
    await t.enterText(find.byKey(const Key('camp_message')), 'Hi');
    await t.tap(find.byKey(const Key('camp_send')));
    await t.pump();
    expect(api.sent, isEmpty);
    await t.pump(const Duration(seconds: 4));
    await t.enterText(find.byKey(const Key('camp_message')), 'Karibu tena, 10% punguzo wiki hii');
    await t.tap(find.byKey(const Key('camp_send')));
    await t.pump();
    expect(api.sent.single, ('new', 'Karibu tena, 10% punguzo wiki hii'));
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('a report is asked for by type, format and period and handed over as a file', (WidgetTester t) async {
    final _FakeSalon api = _FakeSalon();
    final List<(Uint8List, String)> saved = <(Uint8List, String)>[];
    await _pump(t, ExportScreen(api: api, today: DateTime(2026, 11, 15), saver: (Uint8List b, String n) async => saved.add((b, n))));
    await t.tap(find.byKey(const Key('exp_type_tax')));
    await t.tap(find.text('CSV'));
    await t.tap(find.byKey(const Key('exp_last')));
    await t.pump();
    await t.tap(find.byKey(const Key('exp_go')));
    await t.pump();
    expect(api.exports.single, 'tax|csv|2026-10-01|2026-10-31');
    expect(saved.single.$2, 'salon_tax_2026-10-31.csv');
    expect(saved.single.$1, hasLength(3));
  });
}
