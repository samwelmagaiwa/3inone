import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/appointments_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/salon_access.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:boda_mapato/utils/role_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The salon's roles in the app: what each is allowed (the same table as the server), that each means the salon, who
/// sees the money, and that a stylist works the diary but does not write it.
const List<String> _salonRoles = <String>['hair_stylist', 'nail_technician', 'lash_makeup_artist', 'accountant'];
const List<String> _removedRoles = <String>['receptionist', 'cashier', 'stock_manager'];

UserData _user(String role) => UserData(id: 'u1', name: 'Someone', email: 's@example.test', role: role, isActive: true, serviceTypes: const <String>['salon']);

class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => _user(role);

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

class _FakeSalon extends SalonApi {
  _FakeSalon(this.items);

  final List<SalonAppointment> items;

  @override
  Future<List<SalonAppointment>> appointments(DateTime day) async => items;

  RebookSettings settingsNow = const RebookSettings(enabled: false, weeks: 4);
  final List<bool> summaries = <bool>[];

  @override
  Future<RebookSettings> salonSettings() async => settingsNow;

  @override
  Future<RebookSettings> saveDailySummary(bool on) async {
    summaries.add(on);
    settingsNow = settingsNow.copyWith(dailySummary: on);
    return settingsNow;
  }
}

class _Server extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async => <String, dynamic>{'data': <dynamic>[]};
}

void main() {
  group('what each role may do', () {
    const Map<String, Map<String, bool>> table = <String, Map<String, bool>>{
      'hair_stylist': <String, bool>{'inv_create_sales': true, 'inv_report_damage': true, 'inv_view_reports': false, 'inv_view_expenses': false, 'inv_view_cash': false, 'inv_manage_settings': false, 'inv_manage_stock': false},
      'nail_technician': <String, bool>{'inv_create_sales': true, 'inv_report_damage': true, 'inv_view_reports': false, 'inv_manage_products': false},
      'lash_makeup_artist': <String, bool>{'inv_create_sales': true, 'inv_report_damage': true, 'inv_view_reports': false, 'inv_manage_products': false},
      'accountant': <String, bool>{'inv_create_sales': true, 'inv_manage_sales': true, 'inv_view_cash': true, 'inv_view_credit': true, 'inv_view_reports': true, 'inv_view_expenses': true, 'inv_manage_expenses': true, 'inv_manage_stock': false, 'inv_manage_products': false, 'inv_manage_settings': false},
    };

    for (final MapEntry<String, Map<String, bool>> e in table.entries) {
      test('${e.key} has exactly the permissions the server gives it', () {
        final UserPermissions p = UserPermissions.fromRole(e.key);
        for (final MapEntry<String, bool> perm in e.value.entries) {
          expect(p.has(perm.key), perm.value, reason: '${e.key} / ${perm.key}');
        }
      });
    }
  });

  test('the roles that were folded away carry no rights and mean no service', () {
    for (final String role in _removedRoles) {
      expect(UserPermissions.fromRole(role).all, isEmpty, reason: role);
      expect(servicesForRole(role), isEmpty, reason: role);
    }
  });

  test('every salon role means the salon service, and no other', () {
    for (final String role in _salonRoles) {
      expect(servicesForRole(role), <String>['salon'], reason: role);
      expect(servicesForRole(role.toUpperCase()), <String>['salon'], reason: '$role in capitals');
    }
    expect(servicesForRole('sales_officer'), <String>['inventory'], reason: 'the shop\'s roles did not change');
    expect(servicesForRole('driver'), <String>['transport']);
  });

  test('every salon role has a name in both languages', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    for (final String lang in <String>['en', 'sw']) {
      await LocalizationService.instance.changeLanguage(lang);
      for (final String role in _salonRoles) {
        final String name = LocalizationService.instance.translate(role);
        expect(name, isNot(role), reason: '$role in $lang');
        expect(name.trim(), isNotEmpty);
      }
    }
    await LocalizationService.instance.changeLanguage('en');
    expect(LocalizationService.instance.translate('accountant'), 'Accountant');
    await LocalizationService.instance.changeLanguage('sw');
    expect(LocalizationService.instance.translate('accountant'), 'Mhasibu');
    await LocalizationService.instance.changeLanguage('en');
  });

  group('who sees the money', () {
    test('it follows the rights, not the role name: a stylist given "reports" sees it, and loses it when it is taken back', () {
      UserData stylist(List<String>? extra) => UserData(id: 'u1', name: 'Asha', email: 'a@example.test', role: 'hair_stylist', isActive: true, serviceTypes: const <String>['salon'], permissions: extra);
      expect(canSeeSalonMoney(stylist(null)), isFalse);
      expect(canSeeSalonMoney(stylist(<String>['inv_view_cash'])), isFalse, reason: 'another right is not this one');
      expect(canSeeSalonMoney(stylist(<String>['inv_view_reports'])), isTrue);
      expect(canSeeSalonMoney(stylist(<String>[])), isFalse);
    });

    test('the accountant by default, and an accountant with no extras still sees it', () {
      expect(canSeeSalonMoney(_user('accountant')), isTrue);
    });

    test('whoever holds the reports right: the owner, the accountant, the shop\'s manager and the super admin; nobody else', () {
      for (final String role in <String>['admin', 'administrator', 'manager', 'accountant', 'super_admin']) {
        expect(canSeeSalonMoney(_user(role)), isTrue, reason: role);
      }
      for (final String role in <String>['hair_stylist', 'nail_technician', 'lash_makeup_artist', 'sales_officer', 'viewer']) {
        expect(canSeeSalonMoney(_user(role)), isFalse, reason: role);
      }
      expect(canSeeSalonMoney(null), isFalse);
    });

    test('a stylist is one of the three who do the work themselves', () {
      for (final String role in <String>['hair_stylist', 'nail_technician', 'lash_makeup_artist']) {
        expect(isStylistRole(_user(role)), isTrue, reason: role);
      }
      for (final String role in <String>['admin', 'manager', 'accountant']) {
        expect(isStylistRole(_user(role)), isFalse, reason: role);
      }
      expect(isStylistRole(null), isFalse);
    });
  });

  group('the diary', () {
    final SalonAppointment mine = SalonAppointment(
      id: 1,
      clientName: 'Neema',
      startsAt: DateTime(2026, 10, 15, 9),
      endsAt: DateTime(2026, 10, 15, 10),
      status: 'booked',
      services: const <AppointmentService>[AppointmentService(productId: 1, name: 'Wash', price: 5000)],
      total: 5000,
      staffId: 'u1',
      staffName: 'Asha',
    );

    late _FakeSalon api;

    Future<void> open(WidgetTester t, String role) async {
      api = _FakeSalon(<SalonAppointment>[mine]);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalizationService.instance.changeLanguage('en');
      t.view.physicalSize = const Size(411, 1400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final InventoryProvider inv = InventoryProvider(api: _Server());
      addTearDown(inv.dispose);
      await t.pumpWidget(
        MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<InventoryProvider>.value(value: inv),
            ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
            ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
          ],
          child: ScreenUtilInit(
            designSize: const Size(411, 1400),
            minTextAdapt: true,
            builder: (_, __) => MaterialApp(home: Scaffold(body: AppointmentsScreen(api: api, today: DateTime(2026, 10, 15)))),
          ),
        ),
      );
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    }

    testWidgets('the accountant can book, move and cancel', (t) async {
      await open(t, 'accountant');

      expect(find.byKey(const ValueKey<String>('appt_add')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('appt_1')));
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      for (final String k in <String>['appt_edit', 'appt_cancel', 'appt_noshow', 'appt_sell']) {
        expect(find.byKey(ValueKey<String>(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('the owner can switch on the evening summary text; stylists do not even see it', (t) async {
      await open(t, 'admin');
      expect(t.widget<Switch>(find.byKey(const ValueKey<String>('daily_summary_switch'))).value, isFalse);

      await t.tap(find.byKey(const ValueKey<String>('daily_summary_switch')));
      for (int i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(api.summaries, <bool>[true]);
      expect(t.widget<Switch>(find.byKey(const ValueKey<String>('daily_summary_switch'))).value, isTrue);
    });

    for (final String role in <String>['hair_stylist', 'nail_technician']) {
      testWidgets('$role does not see the evening summary switch', (t) async {
        await open(t, role);

        expect(find.byKey(const ValueKey<String>('daily_summary_card')), findsNothing);
        expect(find.byKey(const ValueKey<String>('appt_reminders_card')), findsOneWidget, reason: 'the client reminder is not money');
      });
    }

    testWidgets('a stylist sees the diary but has no "book" button and may only start or finish', (t) async {
      await open(t, 'hair_stylist');

      expect(find.byKey(const ValueKey<String>('appt_add')), findsNothing);
      expect(find.text('Neema'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('appt_1')));
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(find.byKey(const ValueKey<String>('appt_start')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('appt_sell')), findsOneWidget);
      for (final String k in <String>['appt_edit', 'appt_cancel', 'appt_noshow']) {
        expect(find.byKey(ValueKey<String>(k)), findsNothing, reason: k);
      }
    });
  });
}
