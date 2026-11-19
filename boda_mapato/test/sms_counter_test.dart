import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/sms_sender.dart';
import 'package:boda_mapato/models/sms_usage.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/notifications_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/inventory_home.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/screens/admin/sms_senders_screen.dart';
import 'package:boda_mapato/screens/settings/notifications_screen.dart';
import 'package:boda_mapato/screens/settings/sms_counters_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The SMS counter: the super admin's list and detail (texts of the last 3 days), the limit on SMS Sender Names, and the owner's badge
/// in the ⋮ menu (owners only).
class _Api extends ApiService {
  final List<String> gets = <String>[];

  @override
  Future<Map<String, dynamic>> get(final String endpoint, {final bool requireAuth = true, final Map<String, dynamic>? queryParams}) async {
    gets.add(endpoint);
    if (endpoint == '/admin/sms-usage') {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'b1', 'name': 'masai mitumba bora', 'owner': <String, dynamic>{'name': 'Julius', 'email': 'owner1@example.test'}, 'usage': <String, dynamic>{'used': 20, 'limit': 1000, 'remaining': 980}},
          <String, dynamic>{'id': 'b2', 'name': 'DUKA LA MAMA ASHA', 'owner': <String, dynamic>{'name': 'Asha'}, 'usage': <String, dynamic>{'used': 5000, 'limit': 5000, 'remaining': 0, 'blocked': true}},
        ],
      };
    }
    if (endpoint == '/admin/sms-usage/b1') {
      return <String, dynamic>{
        'data': <String, dynamic>{
          'id': 'b1',
          'name': 'masai mitumba bora',
          'usage': <String, dynamic>{'used': 20, 'limit': 1000, 'remaining': 980, 'week_messages': 12, 'week_parts': 20},
          'log_days': 3,
          'recent': <Map<String, dynamic>>[
            <String, dynamic>{'id': 7, 'to': '0743519104', 'message': 'Habari Happy, unadaiwa TSh 100,000', 'parts': 1, 'sent_at': '2026-11-19T10:00:00+03:00'},
          ],
        },
      };
    }
    if (endpoint == '/business/sms-usage') {
      return <String, dynamic>{'data': <String, dynamic>{'business_name': 'masai mitumba bora', 'used': 200, 'limit': 5000, 'remaining': 4800}};
    }
    throw ApiException('offline');
  }

  @override
  Future<Map<String, dynamic>?> getOrNull(final String endpoint, {final bool requireAuth = true}) async => null;
}

Future<void> _pump(final WidgetTester t, final Widget home) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ScreenUtilInit(designSize: const Size(411, 1400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: home)));
  await t.pumpAndSettle();
}

class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 'o1', name: 'Owner', email: 'o@example.test', role: role, isActive: true, serviceTypes: const <String>['inventory']);

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

class _Senders implements SmsSendersDataSource {
  @override
  Future<SmsSenderPage> load({final String status = 'all', final String? query, final int page = 1, final int perPage = 50}) async => SmsSenderPage(
        items: <SmsSenderEntry>[
          SmsSenderEntry.fromJson(<String, dynamic>{
            'id': 'b1',
            'name': 'masai mitumba bora',
            'owner': <String, dynamic>{'name': 'Julius', 'phone_number': '0711000001'},
            'sms_sender': <String, dynamic>{'status': 'none', 'usage': <String, dynamic>{'used': 20, 'limit': 1000, 'remaining': 980}},
          }),
        ],
      );

  @override
  Future<SmsSenderEntry> save(final String businessId, final SmsSenderEdit edit) => throw UnimplementedError();

  @override
  Future<SmsSenderTestResult> test(final String businessId, {final String? phone, final String? senderId, final String? apiKey, final String? apiSecret}) =>
      throw UnimplementedError();
}

Future<void> _openHome(final WidgetTester t, final String role) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (final FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Api server = _Api();
  final InventoryProvider inv = InventoryProvider(api: server);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider(api: server)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(411, 900), minTextAdapt: true, builder: (_, __) => const MaterialApp(home: InventoryHome(salon: false))),
    ),
  );
  for (int i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUp(() => InventoryHome.smsUsageReader = () async => <String, dynamic>{'data': <String, dynamic>{'used': 20, 'limit': 1000, 'remaining': 980}});

  testWidgets('the counter card says used of limit, what is left and when texts stopped', (t) async {
    await _pump(t, const Scaffold(body: SmsUsageCard(usage: SmsUsage(used: 1000, limit: 1000, remaining: 0, blocked: true))));

    expect(find.text('1000/1000'), findsOneWidget);
    expect(find.text('0 left'), findsOneWidget);
    expect(find.textContaining('Limit reached'), findsOneWidget);
  });

  testWidgets('the super admin opens Users SMS counter, picks a business and sees its counter and recent texts', (t) async {
    final _Api api = _Api();
    await _pump(t, NotificationsScreen(api: api, superAdmin: true));

    final double row = t.getRect(find.text('Users SMS counter')).top;
    expect(row, greaterThan(t.getRect(find.text('Payment Alerts')).top));
    await t.tap(find.text('Users SMS counter'));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('sms_counter_badge_b1')), findsOneWidget);
    expect(find.text('20/1000'), findsOneWidget);
    expect(find.text('5000/5000'), findsOneWidget);

    await t.tap(find.text('masai mitumba bora'));
    await t.pumpAndSettle();
    expect(find.text('20/1000'), findsOneWidget);
    expect(find.text('980 left'), findsOneWidget);
    expect(find.text('This week: 12 texts (20 SMS)'), findsOneWidget);
    expect(find.text('Texts of the last 3 days'), findsOneWidget);
    expect(find.text('To 0743519104'), findsOneWidget);
    expect(find.text('Habari Happy, unadaiwa TSh 100,000'), findsOneWidget);
  });

  testWidgets('the super admin sets the SMS limit on SMS Sender Names', (t) async {
    final List<(String, int?, bool)> saved = <(String, int?, bool)>[];
    await _pump(
      t,
      SmsSendersScreen(
        dataSource: _Senders(),
        saveLimit: (final String id, final int? limit, final bool reset) async {
          saved.add((id, limit, reset));
          return SmsUsage(used: reset ? 0 : 20, limit: limit, remaining: (limit ?? 0) - (reset ? 0 : 20));
        },
      ),
    );

    expect(find.text('SMS counter: 20/1000'), findsOneWidget);
    await t.tap(find.text('masai mitumba bora'));
    await t.pumpAndSettle();

    await t.scrollUntilVisible(find.byKey(const ValueKey<String>('sms_limit_save')), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('20 of 1000 SMS used · 980 left'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey<String>('sms_limit_field')), '5000');
    await t.tap(find.byKey(const ValueKey<String>('sms_limit_reset')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey<String>('sms_limit_save')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    expect(saved.single, ('b1', 5000, true));
    expect(find.text('0 of 5000 SMS used · 5000 left'), findsOneWidget);
    await t.pump(const Duration(seconds: 4)); // the green banner goes away
  });

  testWidgets('the owner sees the SMS counter in the ⋮ menu, before Notifications', (t) async {
    await _openHome(t, 'admin');
    await t.tap(find.byKey(const Key('header_more_menu')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('menu_sms_counter')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('menu_sms_counter_badge')), matching: find.text('20/1000')), findsOneWidget);
    expect(t.getRect(find.byKey(const Key('menu_sms_counter'))).top, lessThan(t.getRect(find.byKey(const Key('menu_notifications'))).top));
  });

  testWidgets('staff do not see the SMS counter in the ⋮ menu', (t) async {
    await _openHome(t, 'sales_officer');
    await t.tap(find.byKey(const Key('header_more_menu')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('menu_sms_counter')), findsNothing);
    expect(find.byKey(const Key('menu_notifications')), findsOneWidget);
  });

  testWidgets('the owner opens their counter', (t) async {
    await _pump(t, OwnerSmsUsageScreen(api: _Api()));

    expect(find.text('masai mitumba bora'), findsOneWidget);
    expect(find.text('200/5000'), findsOneWidget);
    expect(find.text('4800 left'), findsOneWidget);
  });
}
