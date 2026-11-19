import 'package:boda_mapato/constants/theme_constants.dart';
import 'package:boda_mapato/screens/settings/notifications_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the server's /business/sms-switch.
class _Api extends ApiService {
  _Api({this.canChange = true, this.enabled = true, this.hasBusiness = true, this.byPlatform = false});

  final bool canChange;
  final bool byPlatform;
  final List<String> putUrls = <String>[];

  /// What the super admin's list shows: two businesses, both sending.
  final List<Map<String, dynamic>> businesses = <Map<String, dynamic>>[
    <String, dynamic>{'id': 'b1', 'name': 'masai mitumba bora', 'owner': <String, dynamic>{'name': 'Julius', 'email': 'owner1@example.test'}, 'sms_sender': <String, dynamic>{'paused': false}},
    <String, dynamic>{'id': 'b2', 'name': 'DUKA LA MAMA ASHA', 'owner': <String, dynamic>{'name': 'Asha', 'email': 'owner2@example.test'}, 'sms_sender': <String, dynamic>{'paused': false}},
  ];
  bool enabled;
  final bool hasBusiness;
  final List<Map<String, dynamic>> puts = <Map<String, dynamic>>[];

  Map<String, dynamic> get _data => <String, dynamic>{
        'enabled': enabled,
        'paused_at': enabled ? null : '2026-11-19T10:00:00+00:00',
        'paused_by': enabled ? null : 'Julius',
        'can_change': canChange,
        'paused_by_platform': !enabled && byPlatform,
        'confirm_word': 'ZIMA',
      };

  @override
  Future<Map<String, dynamic>> get(final String endpoint, {final bool requireAuth = true, final Map<String, dynamic>? queryParams}) async =>
      <String, dynamic>{'data': endpoint == '/admin/businesses' ? businesses : <dynamic>[]};

  @override
  Future<Map<String, dynamic>?> getOrNull(final String endpoint, {final bool requireAuth = true}) async =>
      hasBusiness && endpoint == '/business/sms-switch' ? <String, dynamic>{'data': _data} : null;

  @override
  Future<Map<String, dynamic>> put(final String endpoint, final Map<String, dynamic> data) async {
    puts.add(data);
    putUrls.add(endpoint);
    if (endpoint.startsWith('/admin/businesses/')) {
      final bool on = data['enabled'] == true;
      return <String, dynamic>{'data': <String, dynamic>{'enabled': on, 'paused_at': on ? null : '2026-11-19T10:00:00+00:00', 'paused_by_platform': !on}};
    }
    enabled = data['enabled'] == true;
    return <String, dynamic>{'data': _data};
  }
}

Future<void> _open(final WidgetTester t, final _Api api, {final String lang = 'en', final bool superAdmin = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(lang);
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ScreenUtilInit(
    designSize: const Size(411, 1400),
    minTextAdapt: true,
    builder: (_, __) => MaterialApp(home: NotificationsScreen(api: api, superAdmin: superAdmin)),
  ));
  await t.pumpAndSettle();
}

/// The app's own banner: green, at the TOP of the screen, not a SnackBar at the bottom.
void _expectGreenBannerAtTop(final WidgetTester t, final String message) {
  final Finder text = find.text(message);
  expect(text, findsOneWidget);
  expect(find.byType(SnackBar), findsNothing);
  expect(t.getRect(text).top, lessThan(120), reason: 'the banner sits at the top');
  final Container box = t.widget<Container>(find.ancestor(of: text, matching: find.byType(Container)).first);
  expect((box.decoration! as BoxDecoration).color, ThemeConstants.successGreen);
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

    // Readable on the dark dialog: not a light-filled box with white text in it.
    for (final String key in <String>['sms_master_word', 'sms_master_password']) {
      final TextField field = t.widget<TextField>(find.byKey(ValueKey<String>(key)));
      expect(field.style?.color, Colors.white);
      expect(field.decoration?.fillColor?.a, lessThan(0.2), reason: '$key must not be filled white');
      expect(field.decoration?.labelText, isNotEmpty);
    }

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
    _expectGreenBannerAtTop(t, 'SMS are off');
    await t.pump(const Duration(seconds: 4)); // the banner goes away by itself
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

  testWidgets('an owner whose texts the platform switched off is told so and cannot switch them on', (t) async {
    await _open(t, _Api(canChange: false, enabled: false, byPlatform: true));

    expect(_switch(t).onChanged, isNull);
    expect(find.textContaining('Switched off by the platform administrator'), findsOneWidget);
    expect(find.textContaining('Only the business owner'), findsNothing);
  });

  testWidgets('the super admin picks one business and switches ITS texts off; the others stay on', (t) async {
    final _Api api = _Api(hasBusiness: false);
    await _open(t, api, superAdmin: true);

    // Right below Payment Alerts, a row that opens the list of businesses (no switch of their own: they own no business).
    expect(find.byKey(const ValueKey<String>('sms_master_switch')), findsNothing);
    final double payment = t.getRect(find.text('Payment Alerts')).top;
    final double row = t.getRect(find.text('SMS of a business')).top;
    expect(row, greaterThan(payment));
    expect(row, lessThan(t.getRect(find.text('Debt Reminders')).top));

    await t.tap(find.text('SMS of a business'));
    await t.pumpAndSettle();
    expect(find.text('SMS per business'), findsOneWidget);
    expect(find.text('masai mitumba bora'), findsOneWidget);
    expect(find.text('DUKA LA MAMA ASHA'), findsOneWidget);

    Switch rowSwitch(final String id) =>
        t.widget<Switch>(find.descendant(of: find.byKey(ValueKey<String>('sms_admin_business_$id')), matching: find.byType(Switch)));

    await t.tap(find.descendant(of: find.byKey(const ValueKey<String>('sms_admin_business_b1')), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    expect(find.text('Switch off all SMS?'), findsOneWidget);
    expect(find.textContaining('Nothing masai mitumba bora sends will go out'), findsOneWidget);

    FilledButton button() => t.widget<FilledButton>(find.byKey(const ValueKey<String>('sms_master_confirm')));
    await t.enterText(find.byKey(const ValueKey<String>('sms_master_password')), 'adminpass');
    await t.pump();
    expect(button().onPressed, isNull, reason: 'the word ZIMA is still missing');
    await t.enterText(find.byKey(const ValueKey<String>('sms_master_word')), 'ZIMA');
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('sms_master_confirm')));
    await t.pumpAndSettle();

    expect(api.putUrls.single, '/admin/businesses/b1/sms-switch');
    expect(api.puts.single, <String, dynamic>{'enabled': false, 'password': 'adminpass', 'confirm': 'ZIMA'});
    expect(rowSwitch('b1').value, isFalse);
    expect(find.textContaining('SMS OFF (by the platform)'), findsOneWidget, reason: 'only masai mitumba bora is off');
    expect(rowSwitch('b2').value, isTrue, reason: 'every other business keeps sending');
    _expectGreenBannerAtTop(t, 'masai mitumba bora: SMS are off');
    await t.pump(const Duration(seconds: 4));
  });
}
