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

/// Making another super admin from the user list: offered only to a super admin, and only after a confirmation.
class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 'u0', name: 'Me', email: 'me@example.test', role: role, isActive: true);
}

class _Api extends ApiService {
  final List<Map<String, dynamic>> created = <Map<String, dynamic>>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, dynamic>> getUsers({int page = 1, int limit = 50, String? query, String? role, String? serviceType}) async => <String, dynamic>{'data': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> getMyUsers({int page = 1, int limit = 50, String? query, String? serviceType}) async => <String, dynamic>{'data': <Map<String, dynamic>>[]};

  @override
  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    created.add(userData);

    return <String, dynamic>{'success': true};
  }
}

Future<_Api> _open(WidgetTester t, String role) async {
  SharedPreferences.setMockInitialValues(<String, Object>{'selected_service': 'transport'});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Api api = _Api();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
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
  await t.tap(find.byIcon(Icons.person_add_alt_1));
  await t.pumpAndSettle();

  return api;
}

Future<void> _openRoles(WidgetTester t) async {
  await t.tap(find.byType(DropdownButtonFormField<String>).first);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a super admin can choose Super Admin, and the account is made only after confirming', (WidgetTester t) async {
    final _Api api = await _open(t, 'super_admin');
    await t.enterText(find.byType(TextFormField).at(0), 'Second Super');
    await t.enterText(find.byType(TextFormField).at(1), 'second@example.test');
    await t.enterText(find.byType(TextFormField).at(2), '0711000002');
    await _openRoles(t);
    await t.tap(find.text('Super Admin').last);
    await t.pumpAndSettle();

    await t.tap(find.descendant(of: find.byType(Dialog), matching: find.byType(FilledButton)));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('confirm_super_admin')), findsOneWidget);
    expect(api.created, isEmpty, reason: 'nothing is sent before the person says yes');

    await t.tap(find.byKey(const Key('confirm_super_admin_yes')));
    await t.pumpAndSettle();
    expect(api.created.single['role'], 'super_admin');
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('answering No to the confirmation sends nothing', (WidgetTester t) async {
    final _Api api = await _open(t, 'super_admin');
    await t.enterText(find.byType(TextFormField).at(0), 'Second Super');
    await t.enterText(find.byType(TextFormField).at(1), 'second@example.test');
    await t.enterText(find.byType(TextFormField).at(2), '0711000002');
    await _openRoles(t);
    await t.tap(find.text('Super Admin').last);
    await t.pumpAndSettle();

    await t.tap(find.descendant(of: find.byType(Dialog), matching: find.byType(FilledButton)));
    await t.pumpAndSettle();
    await t.tap(find.text('No'));
    await t.pumpAndSettle();

    expect(api.created, isEmpty);
  });

  testWidgets('a business owner is not offered Super Admin', (WidgetTester t) async {
    await _open(t, 'admin');
    await _openRoles(t);

    expect(find.text('Super Admin'), findsNothing);
  });
}
