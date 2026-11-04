import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/screens/settings/user_permissions_management_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What one person may open, as switches the owner turns on and off: the role starts the list, every switch can be turned off (taking
/// back what the role gave) or on (adding to it), and "Back to the role" puts it all as the role has it.
Map<String, dynamic> _m(String key, String group, String en, String sw, {required bool fromRole, required bool on}) => <String, dynamic>{
      'key': key, 'group': group, 'en': en, 'sw': sw, 'from_role': fromRole, 'on': on, 'added': on && !fromRole, 'taken_back': !on && fromRole,
    };

/// An accountant, as the server describes one: the books on, the rest off.
List<Map<String, dynamic>> _accountant() => <Map<String, dynamic>>[
      _m('inv_view_products', 'goods', 'See services and goods', 'Kuona huduma na bidhaa', fromRole: true, on: true),
      _m('inv_create_products', 'goods', 'Add new services and goods', 'Kuongeza huduma na bidhaa mpya', fromRole: true, on: true),
      _m('inv_manage_products', 'goods', 'Change and delete services and goods, prices', 'Kubadilisha na kufuta', fromRole: false, on: false),
      _m('inv_create_sales', 'selling', 'Sell (the till)', 'Kuuza (kaunta)', fromRole: true, on: true),
      _m('inv_salon_walkins', 'selling', 'Walk-ins queue', 'Wanaosubiri', fromRole: false, on: false),
      _m('inv_salon_money', 'money', 'Money pages: profit and loss, cashbook', 'Kurasa za fedha', fromRole: true, on: true),
      _m('inv_salon_equipment', 'people', 'Equipment', 'Vifaa', fromRole: false, on: false),
    ];

class _Api extends ApiService {
  _Api({this.modules, this.failLoad = false});

  final List<Map<String, dynamic>>? modules;
  final bool failLoad;
  final List<List<String>> saved = <List<String>>[];
  int loads = 0;

  @override
  Future<Map<String, dynamic>> getUserAccess(String userId) async {
    loads++;
    if (failLoad && loads == 1) throw ApiException('offline');

    return <String, dynamic>{'success': true, 'data': <String, dynamic>{'modules': modules ?? _accountant()}};
  }

  @override
  Future<Map<String, dynamic>> saveUserAccess(String userId, List<String> on) async {
    saved.add(on);

    return <String, dynamic>{'success': true};
  }
}

Future<_Api> _open(WidgetTester t, {bool sw = false, _Api? api}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(900, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Api fake = api ?? _Api();
  await t.pumpWidget(
    MaterialApp(
      home: UserPermissionsManagementScreen(
        user: <String, dynamic>{'id': 'u-7', 'name': 'Ivan Samwel', 'role': 'accountant', 'permissions': <String>[]},
        serviceType: 'salon',
        api: fake,
      ),
    ),
  );
  await t.pumpAndSettle();

  return fake;
}

Finder _k(String k) => find.byKey(Key(k));

Switch _switch(WidgetTester t, String key) => t.widget<Switch>(_k('access_switch_$key'));

String _state(WidgetTester t, String key) => t.widget<Text>(_k('access_state_$key')).data!;

void main() {
  group('the switches', () {
    testWidgets('the role starts the list: what it gives is on, the rest off, and the person and the groups are named', (t) async {
      await _open(t);

      expect(find.text('Ivan Samwel'), findsOneWidget);
      expect(t.widget<Text>(_k('access_role')).data, 'ACCOUNTANT');
      for (final String g in <String>['goods', 'selling', 'money', 'people']) {
        expect(_k('access_group_$g'), findsOneWidget, reason: g);
      }
      expect(_k('access_group_reports'), findsNothing, reason: 'a group with no switch is not shown');
      expect(_switch(t, 'inv_create_products').value, isTrue);
      expect(_switch(t, 'inv_salon_equipment').value, isFalse);
      expect(_state(t, 'inv_create_products'), 'Given by the role');
      expect(_state(t, 'inv_salon_equipment'), 'Not allowed');
    });

    testWidgets('a switch the role gave can be turned off: it says it is taken back', (t) async {
      await _open(t);

      await t.tap(_k('access_switch_inv_create_products'));
      await t.pumpAndSettle();

      expect(_switch(t, 'inv_create_products').value, isFalse);
      expect(_switch(t, 'inv_create_products').onChanged, isNotNull, reason: 'nothing is locked');
      expect(_state(t, 'inv_create_products'), 'Taken back for this person');
    });

    testWidgets('a switch that is off can be turned on: it says it is added', (t) async {
      await _open(t);

      await t.tap(_k('access_switch_inv_salon_equipment'));
      await t.pumpAndSettle();

      expect(_switch(t, 'inv_salon_equipment').value, isTrue);
      expect(_state(t, 'inv_salon_equipment'), 'Added for this person');
    });

    testWidgets('tapping the row does the same as its switch', (t) async {
      await _open(t);

      await t.tap(_k('access_row_inv_salon_walkins'));
      await t.pumpAndSettle();
      expect(_switch(t, 'inv_salon_walkins').value, isTrue);

      await t.tap(_k('access_row_inv_salon_walkins'));
      await t.pumpAndSettle();
      expect(_switch(t, 'inv_salon_walkins').value, isFalse);
    });

    testWidgets('the counts follow: from the role, added, off', (t) async {
      await _open(t);
      expect(find.descendant(of: _k('access_count_role'), matching: find.textContaining('4')), findsOneWidget);
      expect(find.descendant(of: _k('access_count_extra'), matching: find.textContaining('0')), findsOneWidget);
      expect(find.descendant(of: _k('access_count_off'), matching: find.textContaining('3')), findsOneWidget);

      await t.tap(_k('access_switch_inv_salon_equipment'));
      await t.tap(_k('access_switch_inv_salon_money'));
      await t.pumpAndSettle();

      expect(find.descendant(of: _k('access_count_role'), matching: find.textContaining('3')), findsOneWidget);
      expect(find.descendant(of: _k('access_count_extra'), matching: find.textContaining('1')), findsOneWidget);
      expect(find.descendant(of: _k('access_count_off'), matching: find.textContaining('3')), findsOneWidget);
    });
  });

  group('saving', () {
    testWidgets('Save waits until something is changed, then sends exactly the switches left on', (t) async {
      final _Api api = await _open(t);
      expect(t.widget<TextButton>(_k('access_save')).onPressed, isNull);

      await t.tap(_k('access_switch_inv_create_products'));
      await t.tap(_k('access_switch_inv_salon_equipment'));
      await t.pumpAndSettle();
      expect(t.widget<TextButton>(_k('access_save')).onPressed, isNotNull);

      await t.tap(_k('access_save'));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 6)); // the "saved" message goes away

      expect(api.saved, hasLength(1));
      expect(api.saved.single, unorderedEquals(<String>['inv_view_products', 'inv_create_sales', 'inv_salon_money', 'inv_salon_equipment']));
      expect(api.saved.single, isNot(contains('inv_create_products')), reason: 'taken back');
    });

    testWidgets('turning a switch off and on again changes nothing, so there is nothing to save', (t) async {
      await _open(t);

      await t.tap(_k('access_switch_inv_create_products'));
      await t.pumpAndSettle();
      await t.tap(_k('access_switch_inv_create_products'));
      await t.pumpAndSettle();

      expect(t.widget<TextButton>(_k('access_save')).onPressed, isNull);
    });

    testWidgets('Back to the role puts every switch as the role has it', (t) async {
      await _open(t);
      await t.tap(_k('access_switch_inv_create_products'));
      await t.tap(_k('access_switch_inv_salon_equipment'));
      await t.pumpAndSettle();

      await t.tap(_k('access_back_to_role'));
      await t.pumpAndSettle();

      expect(_switch(t, 'inv_create_products').value, isTrue);
      expect(_switch(t, 'inv_salon_equipment').value, isFalse);
      expect(t.widget<TextButton>(_k('access_back_to_role')).onPressed, isNull, reason: 'already as the role has it');
    });

    testWidgets('Turn all on switches every section on', (t) async {
      await _open(t);

      await t.tap(_k('access_all_on'));
      await t.pumpAndSettle();

      for (final String key in <String>['inv_manage_products', 'inv_salon_walkins', 'inv_salon_equipment']) {
        expect(_switch(t, key).value, isTrue, reason: key);
      }
    });
  });

  group('words and failures', () {
    testWidgets('in Swahili the names and the states are Swahili', (t) async {
      await _open(t, sw: true);

      expect(find.text('Kuongeza huduma na bidhaa mpya'), findsOneWidget);
      expect(find.text('Vifaa'), findsOneWidget);
      expect(_state(t, 'inv_create_products'), 'Imetolewa na wadhifa');
      expect(_state(t, 'inv_salon_equipment'), 'Hairuhusiwi');
      expect(find.text('HIFADHI'), findsOneWidget);
    });

    testWidgets('when the list cannot be had it says so and Retry asks again', (t) async {
      final _Api api = _Api(failLoad: true);
      await _open(t, api: api);

      expect(_k('access_error'), findsOneWidget);
      expect(_k('access_switch_inv_create_products'), findsNothing);

      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();

      expect(_k('access_error'), findsNothing);
      expect(_k('access_switch_inv_create_products'), findsOneWidget);
    });
  });

  group('the rights as the server worked them out', () {
    UserData person(Map<String, dynamic> extra) => UserData.fromJson(<String, dynamic>{'id': 'u-7', 'name': 'Ivan', 'email': 'i@e.test', 'role': 'accountant', 'is_active': true, ...extra});

    test('a right the owner took back is not given again by the role defaults', () {
      final UserData ivan = person(<String, dynamic>{
        'effective_permissions': <String>['inv_view_products', 'inv_create_sales', 'inv_salon_money'],
      });

      expect(ivan.access.has('inv_create_sales'), isTrue);
      expect(ivan.access.has('inv_create_products'), isFalse, reason: 'the accountant role gives it, the owner took it back');
      expect(ivan.hasPermission('inv_create_products'), isFalse);
      expect(ivan.access.has('inv_view_reports'), isFalse);
    });

    test('everything taken back is a real answer, not "nothing was sent"', () {
      final UserData ivan = person(<String, dynamic>{'effective_permissions': <String>[]});

      expect(ivan.permissionsResolved, isTrue);
      expect(ivan.access.has('inv_view_products'), isFalse);
    });

    test('an older server that sends no resolved list still gets the role defaults and the explicit grants', () {
      final UserData ivan = person(<String, dynamic>{'permissions': <String>['inv_salon_equipment']});

      expect(ivan.permissionsResolved, isFalse);
      expect(ivan.access.has('inv_create_sales'), isTrue, reason: 'the role');
      expect(ivan.access.has('inv_salon_equipment'), isTrue, reason: 'the grant');
      expect(ivan.access.has('inv_salon_feedback'), isFalse);
    });

    test('the cached login (a map) is read the same way', () {
      final UserPermissions p = <String, dynamic>{'role': 'accountant', 'effective_permissions': <String>['inv_view_products']}.permissions;

      expect(p.has('inv_view_products'), isTrue);
      expect(p.has('inv_create_sales'), isFalse);
    });

    test('the accountant starts with the books and without the front desk, equipment and goods by branch', () {
      final UserPermissions p = UserPermissions.fromRole('accountant');

      for (final String key in <String>['inv_create_products', 'inv_salon_money', 'inv_salon_team', 'inv_salon_insights', 'inv_salon_appointments', 'inv_salon_stylists']) {
        expect(p.has(key), isTrue, reason: key);
      }
      for (final String key in <String>['inv_salon_equipment', 'inv_salon_branch_stock', 'inv_salon_feedback', 'inv_salon_walkins', 'inv_salon_rebook']) {
        expect(p.has(key), isFalse, reason: key);
      }
    });
  });
}
