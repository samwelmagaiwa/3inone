import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/screens/settings/user_management_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The super admin's "Place under an admin" action in the user list.
class _Super extends AuthProvider {
  @override
  UserData? get user => UserData(id: 's1', name: 'Super', email: 's@example.test', role: 'super_admin', isActive: true);
}

class _Api extends ApiService {
  final List<(String, String, String?)> placed = <(String, String, String?)>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, dynamic>> getUsers({int page = 1, int limit = 50, String? query, String? role, String? serviceType}) async => <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a1', 'name': 'Sammy', 'email': 'sammy@example.test', 'role': 'admin', 'is_active': true},
          <String, dynamic>{'id': 'u1', 'name': 'Ivan', 'email': 'ivan@example.test', 'role': 'accountant', 'is_active': true},
          <String, dynamic>{'id': 'd1', 'name': 'Dino', 'email': 'dino@example.test', 'role': 'driver', 'is_active': true},
        ],
      };

  @override
  Future<Map<String, dynamic>> assignUserToAdmin({required String userId, required String adminId, String? service}) async {
    placed.add((userId, adminId, service));

    return <String, dynamic>{'success': true, 'message': 'Amewekwa. / Placed.'};
  }
}

Future<_Api> _open(WidgetTester t) async {
  SharedPreferences.setMockInitialValues(<String, Object>{'selected_service': 'salon'});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Api api = _Api();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Super()),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(411, 900),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: UserManagementScreen(api: api)),
      ),
    ),
  );
  await t.pumpAndSettle();

  return api;
}

void main() {
  testWidgets('a super admin places a staff member under an admin, optionally in one service', (WidgetTester t) async {
    final _Api api = await _open(t);

    await t.tap(find.text('Ivan'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('assign_admin_action')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('admin_a1')), findsOneWidget, reason: 'only business admins are offered');
    expect(find.byKey(const Key('admin_u1')), findsNothing);
    expect(t.widget<TextButton>(find.byKey(const Key('assign_admin_confirm'))).onPressed, isNull, reason: 'an admin must be chosen first');

    await t.tap(find.byKey(const Key('admin_a1')));
    await t.tap(find.byKey(const Key('service_salon')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('assign_admin_confirm')));
    await t.pumpAndSettle();

    expect(api.placed, <(String, String, String?)>[('u1', 'a1', 'salon')]);
    await t.pump(const Duration(seconds: 6)); // the confirmation message goes away
  });

  testWidgets('an outside party such as a driver is not offered the action', (WidgetTester t) async {
    await _open(t);

    await t.tap(find.text('Dino'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('assign_admin_action')), findsNothing);
  });
}
