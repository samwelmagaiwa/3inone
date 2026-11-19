import 'package:boda_mapato/screens/settings/notifications_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the server's /business/sms-switch.
class _Api extends ApiService {
  _Api({this.canChange = true, this.enabled = true, this.hasBusiness = true});

  final bool canChange;
  bool enabled;
  final bool hasBusiness;
  final List<Map<String, dynamic>> puts = <Map<String, dynamic>>[];

  Map<String, dynamic> get _data => <String, dynamic>{
        'enabled': enabled,
        'paused_at': enabled ? null : '2026-11-19T10:00:00+00:00',
        'paused_by': enabled ? null : 'Julius',
        'can_change': canChange,
        'confirm_word': 'ZIMA',
      };

  @override
  Future<Map<String, dynamic>?> getOrNull(final String endpoint, {final bool requireAuth = true}) async =>
      hasBusiness && endpoint == '/business/sms-switch' ? <String, dynamic>{'data': _data} : null;

  @override
  Future<Map<String, dynamic>> put(final String endpoint, final Map<String, dynamic> data) async {
    puts.add(data);
    enabled = data['enabled'] == true;
    return <String, dynamic>{'data': _data};
  }
}

Future<void> _open(final WidgetTester t, final _Api api, {final String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(lang);
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ScreenUtilInit(
    designSize: const Size(411, 1400),
    minTextAdapt: true,
    builder: (_, __) => MaterialApp(home: NotificationsScreen(api: api)),
  ));
  await t.pumpAndSettle();
}

Switch _switch(final WidgetTester t) =>
    t.widget<Switch>(find.descendant(of: find.byKey(const ValueKey<String>('sms_master_switch')), matching: find.byType(Switch)));

void main() {
  testWidgets('the SMS switch sits right below Payment Alerts', (t) async {
    await _open(t, _Api());

    expect(find.text('SMS (text messages)'), findsOneWidget);
    final double payment = t.getRect(find.text('Payment Alerts')).top;
    final double sms = t.getRect(find.text('SMS (text messages)')).top;
    final double debt = t.getRect(find.text('Debt Reminders')).top;
    expect(sms, greaterThan(payment));
    expect(sms, lessThan(debt));
  });

  testWidgets('switching off needs the word ZIMA and the password before the button works', (t) async {
    final _Api api = _Api();
    await _open(t, api);

    await t.tap(find.descendant(of: find.byKey(const ValueKey<String>('sms_master_switch')), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    expect(find.text('Switch off all SMS?'), findsOneWidget);

    FilledButton button() => t.widget<FilledButton>(find.byKey(const ValueKey<String>('sms_master_confirm')));
    expect(button().onPressed, isNull);

    await t.enterText(find.byKey(const ValueKey<String>('sms_master_password')), 'secret1');
    await t.pump();
    expect(button().onPressed, isNull, reason: 'the word is still missing');

    await t.enterText(find.byKey(const ValueKey<String>('sms_master_word')), 'zim');
    await t.pump();
    expect(button().onPressed, isNull, reason: 'the word must be typed exactly');

    await t.enterText(find.byKey(const ValueKey<String>('sms_master_word')), 'zima');
    await t.pump();
    expect(button().onPressed, isNotNull);

    await t.tap(find.byKey(const ValueKey<String>('sms_master_confirm')));
    await t.pumpAndSettle();

    expect(api.puts.single, <String, dynamic>{'enabled': false, 'password': 'secret1', 'confirm': 'zima'});
    expect(_switch(t).value, isFalse);
    expect(find.textContaining('OFF: no text leaves this business'), findsOneWidget);
  });

  testWidgets('cancelling changes nothing', (t) async {
    final _Api api = _Api();
    await _open(t, api);

    await t.tap(find.descendant(of: find.byKey(const ValueKey<String>('sms_master_switch')), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(api.puts, isEmpty);
    expect(_switch(t).value, isTrue);
  });

  testWidgets('staff see the switch but cannot move it', (t) async {
    await _open(t, _Api(canChange: false, enabled: false));

    expect(_switch(t).onChanged, isNull);
    expect(find.textContaining('Only the business owner can change this'), findsOneWidget);
    expect(find.textContaining('Switched off by Julius'), findsOneWidget);
  });

  testWidgets('an account with no business (a super admin) has no SMS switch', (t) async {
    await _open(t, _Api(hasBusiness: false));

    expect(find.byKey(const ValueKey<String>('sms_master_switch')), findsNothing);
  });

  testWidgets('in Swahili the switch and its dialog are Swahili', (t) async {
    await _open(t, _Api(), lang: 'sw');

    expect(find.text('SMS (ujumbe mfupi)'), findsOneWidget);
    await t.tap(find.descendant(of: find.byKey(const ValueKey<String>('sms_master_switch')), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    expect(find.text('Zima SMS zote?'), findsOneWidget);
    expect(find.text('Andika ZIMA kuthibitisha'), findsOneWidget);
  });
}
