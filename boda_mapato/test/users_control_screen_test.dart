import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/screens/admin/users_control_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The super admin's users control: the list with its numbers and filters, and every action on a person.
class _Auth extends AuthProvider {
  @override
  UserData? get user => UserData(id: 's1', name: 'Super', email: 'super@example.test', role: 'super_admin', isActive: true);
}

class _Api extends ApiService {
  final List<String> calls = <String>[];
  Map<String, dynamic>? lastBody;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, dynamic>> getUsers({int page = 1, int limit = 50, String? query, String? role, String? serviceType}) async => <String, dynamic>{
        'data': <String, dynamic>{
          'users': <Map<String, dynamic>>[
            <String, dynamic>{'id': 's1', 'name': 'Super', 'email': 'super@example.test', 'phone_number': '0700000001', 'role': 'super_admin', 'is_active': true, 'service_types': <String>[]},
            <String, dynamic>{'id': 'a1', 'name': 'Sammy', 'email': 'sammy@example.test', 'phone_number': '0700000002', 'role': 'admin', 'is_active': true, 'service_types': <String>['salon']},
            <String, dynamic>{'id': 'u1', 'name': 'Ivan', 'email': 'ivan@example.test', 'phone_number': '0700000003', 'role': 'accountant', 'is_active': true, 'service_types': <String>['salon']},
            <String, dynamic>{'id': 'u2', 'name': 'Zawadi', 'email': 'zawadi@example.test', 'phone_number': '0700000004', 'role': 'sales_officer', 'is_active': false, 'service_types': <String>['inventory']},
          ],
        },
      };

  @override
  Future<Map<String, dynamic>> updateUser(String userId, Map<String, dynamic> userData) async {
    calls.add('update:$userId');
    lastBody = userData;

    return <String, dynamic>{'success': true};
  }

  @override
  Future<Map<String, dynamic>> deleteUser(String userId) async {
    calls.add('delete:$userId');

    return <String, dynamic>{'success': true};
  }

  @override
  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    calls.add('create');
    lastBody = userData;

    return <String, dynamic>{'success': true};
  }

  @override
  Future<Map<String, dynamic>> resetUserPassword({required String userId, required String newPassword}) async {
    calls.add('password:$userId');
    lastBody = <String, dynamic>{'password': newPassword};

    return <String, dynamic>{'success': true};
  }

  @override
  Future<Map<String, dynamic>> assignUserToAdmin({required String userId, required String adminId, String? service}) async {
    calls.add('place:$userId->$adminId');

    return <String, dynamic>{'success': true};
  }
}

Future<_Api> _open(WidgetTester t) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(1800, 2400); // wide enough for the whole row of filters
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Api api = _Api();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: MaterialApp(home: UsersControlScreen(api: api)),
    ),
  );
  await t.pumpAndSettle();

  return api;
}

Finder _k(String k) => find.byKey(Key(k));

Future<void> _openActions(WidgetTester t, String id) async {
  await t.tap(_k('uc_user_$id'));
  await t.pumpAndSettle();
}

/// The confirmation message goes away after a few seconds.
Future<void> _settleMessage(WidgetTester t) => t.pump(const Duration(seconds: 6));

void main() {
  testWidgets('shows everyone with the numbers, and filters by role, status, service and search', (WidgetTester t) async {
    await _open(t);

    expect(find.descendant(of: _k('uc_stat_total'), matching: find.text('4')), findsOneWidget);
    expect(find.descendant(of: _k('uc_stat_active'), matching: find.text('3')), findsOneWidget);
    expect(_k('uc_user_a1'), findsOneWidget);

    await t.tap(_k('uc_role_owners'));
    await t.pumpAndSettle();
    expect(_k('uc_user_a1'), findsOneWidget);
    expect(_k('uc_user_u1'), findsNothing);

    await t.tap(_k('uc_role_staff'));
    await t.tap(_k('uc_status_off'));
    await t.pumpAndSettle();
    expect(_k('uc_user_u2'), findsOneWidget);
    expect(_k('uc_user_u1'), findsNothing);

    await t.tap(_k('uc_status_off'));
    await t.tap(_k('uc_svc_salon'));
    await t.pumpAndSettle();
    expect(_k('uc_user_u1'), findsOneWidget);
    expect(_k('uc_user_u2'), findsNothing);

    await t.tap(_k('uc_svc_salon'));
    await t.enterText(_k('uc_search'), 'zawadi');
    await t.pumpAndSettle();
    expect(_k('uc_user_u2'), findsOneWidget);
    expect(_k('uc_user_a1'), findsNothing);

    await t.enterText(_k('uc_search'), 'nobody-here');
    await t.pumpAndSettle();
    expect(_k('uc_empty'), findsOneWidget);
  });

  testWidgets('a person can be switched off, edited and given a new role', (WidgetTester t) async {
    final _Api api = await _open(t);

    await _openActions(t, 'u1');
    await t.tap(_k('uc_act_toggle'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'update:u1');
    expect(api.lastBody, <String, dynamic>{'is_active': false});
    await _settleMessage(t);

    await _openActions(t, 'u1');
    await t.tap(_k('uc_act_edit'));
    await t.pumpAndSettle();
    await t.enterText(_k('uc_edit_name'), 'Ivan Samwel');
    await t.tap(_k('uc_edit_save'));
    await t.pumpAndSettle();
    expect(api.lastBody!['name'], 'Ivan Samwel');
    await _settleMessage(t);

    await _openActions(t, 'u1');
    await t.tap(_k('uc_act_role'));
    await t.pumpAndSettle();
    await t.tap(_k('uc_role_manager'));
    await t.pumpAndSettle();
    await t.tap(_k('uc_role_save'));
    await t.pumpAndSettle();
    expect(api.lastBody, <String, dynamic>{'role': 'manager'});
    await _settleMessage(t);
  });

  testWidgets('making someone a Super Admin asks first', (WidgetTester t) async {
    final _Api api = await _open(t);

    await _openActions(t, 'u1');
    await t.tap(_k('uc_act_role'));
    await t.pumpAndSettle();
    await t.tap(_k('uc_role_super_admin'));
    await t.pumpAndSettle();
    await t.tap(_k('uc_role_save'));
    await t.pumpAndSettle();
    expect(_k('uc_confirm'), findsOneWidget);
    expect(api.calls, isEmpty, reason: 'nothing is sent before the person says yes');

    await t.tap(_k('uc_confirm_yes'));
    await t.pumpAndSettle();
    expect(api.lastBody, <String, dynamic>{'role': 'super_admin'});
    await _settleMessage(t);
  });

  testWidgets('delete asks first; a super admin cannot delete, switch off or demote themself', (WidgetTester t) async {
    final _Api api = await _open(t);

    await _openActions(t, 's1');
    expect(t.widget<ListTile>(_k('uc_act_delete')).enabled, isFalse);
    expect(t.widget<ListTile>(_k('uc_act_toggle')).enabled, isFalse);
    expect(t.widget<ListTile>(_k('uc_act_role')).enabled, isFalse);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    await _openActions(t, 'u2');
    await t.tap(_k('uc_act_delete'));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(_k('uc_confirm_yes'));
    await t.pumpAndSettle();
    expect(api.calls, <String>['delete:u2']);
    await _settleMessage(t);
  });

  testWidgets('reset password needs 8 characters; a staff member can be placed under an admin', (WidgetTester t) async {
    final _Api api = await _open(t);

    await _openActions(t, 'u1');
    await t.tap(_k('uc_act_password'));
    await t.pumpAndSettle();
    await t.enterText(_k('uc_pw'), 'short');
    await t.tap(_k('uc_pw_save'));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await _settleMessage(t);

    await _openActions(t, 'u1');
    await t.tap(_k('uc_act_password'));
    await t.pumpAndSettle();
    await t.enterText(_k('uc_pw'), 'LongEnough1');
    await t.tap(_k('uc_pw_save'));
    await t.pumpAndSettle();
    expect(api.calls, <String>['password:u1']);
    await _settleMessage(t);

    await _openActions(t, 'u1');
    await t.tap(_k('uc_act_place'));
    await t.pumpAndSettle();
    await t.tap(_k('uc_admin_a1'));
    await t.pumpAndSettle();
    await t.tap(_k('uc_place_save'));
    await t.pumpAndSettle();
    expect(api.calls.last, 'place:u1->a1');
    await _settleMessage(t);

    await _openActions(t, 'a1');
    expect(_k('uc_act_place'), findsNothing, reason: 'an owner is not placed under another admin');
  });

  testWidgets('adding a user checks the form and sends the services', (WidgetTester t) async {
    final _Api api = await _open(t);

    await t.tap(_k('uc_add'));
    await t.pumpAndSettle();
    await t.tap(_k('uc_new_save'));
    await t.pumpAndSettle();
    expect(_k('uc_new_error'), findsOneWidget);
    expect(api.calls, isEmpty);

    await t.enterText(_k('uc_new_name'), 'Neema Joseph');
    await t.enterText(_k('uc_new_email'), 'neema@example.test');
    await t.enterText(_k('uc_new_phone'), '0711000009');
    await t.enterText(_k('uc_new_password'), 'Secret12345');
    await t.tap(_k('uc_newsvc_salon'));
    await t.tap(_k('uc_newsvc_inventory'));
    await t.pumpAndSettle();
    await t.tap(_k('uc_new_save'));
    await t.pumpAndSettle();

    expect(api.calls, <String>['create']);
    expect(api.lastBody!['name'], 'Neema Joseph');
    expect(api.lastBody!['role'], 'manager');
    expect(api.lastBody!['service_types'], <String>['salon']);
    await _settleMessage(t);
  });
}
