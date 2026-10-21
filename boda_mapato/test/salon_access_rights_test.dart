import 'package:boda_mapato/screens/settings/user_permissions_management_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The salon's access rights are set on the same screen as the other services': what the role already gives (locked), what
/// the owner adds for one person, and what is left out.
class _Api extends ApiService {
  final List<(String, List<String>)> saved = <(String, List<String>)>[];

  @override
  Future<Map<String, dynamic>> updateUserPermissions(String userId, List<String> permissions) async {
    saved.add((userId, permissions));
    return <String, dynamic>{'success': true};
  }
}

Future<_Api> _open(WidgetTester t, {String role = 'hair_stylist', List<String> extra = const <String>[], bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Api api = _Api();
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext ctx) => Scaffold(
          body: TextButton(
            key: const Key('open'),
            onPressed: () => Navigator.push<void>(
              ctx,
              MaterialPageRoute<void>(
                builder: (_) => UserPermissionsManagementScreen(
                  user: <String, dynamic>{'id': 'u-7', 'name': 'Asha', 'role': role, 'permissions': extra},
                  serviceType: 'salon',
                  api: api,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();

  return api;
}

void main() {
  testWidgets('a salon person gets the salon rights list, not an empty page', (t) async {
    await _open(t);
    expect(find.text('Sales, appointments and walk-ins'), findsOneWidget);
    expect(find.text('Daily cash'), findsOneWidget);
    expect(find.text('Reports, money, profit and insights'), findsOneWidget);
    expect(find.text('Settings, branches and business profile'), findsOneWidget);
    expect(find.text('SALON'), findsOneWidget, reason: 'the service pill');
  });

  testWidgets('the rights are in Swahili too', (t) async {
    await _open(t, sw: true);
    expect(find.text('Mauzo, miadi na wanaosubiri'), findsOneWidget);
    expect(find.text('Pesa za kila siku (kasha)'), findsOneWidget);
  });

  testWidgets('what the role gives is locked and cannot be taken away here', (t) async {
    await _open(t, role: 'accountant');
    // the accountant's role gives sales, returns, clients\' credit, daily cash, expenses, reports, reminders and products
    expect(find.byIcon(Icons.lock), findsNWidgets(9));
    await t.tap(find.text('Daily cash'));
    await t.pump();
    expect(find.byIcon(Icons.lock), findsNWidgets(9), reason: 'still locked');
  });

  testWidgets('an extra right is added with a tap and saved for that person', (t) async {
    final _Api api = await _open(t);
    expect(find.byIcon(Icons.lock), findsNWidgets(4), reason: 'a stylist: services, sales, reminders, damaged goods');
    await t.tap(find.text('Daily cash'));
    await t.pump();
    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();
    expect(api.saved.single.$1, 'u-7');
    expect(api.saved.single.$2, <String>['inv_view_cash']);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('an extra right already given shows as given and can be taken back', (t) async {
    final _Api api = await _open(t, extra: <String>['inv_view_cash']);
    await t.tap(find.text('Daily cash'));
    await t.pump();
    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();
    expect(api.saved.single.$2, isEmpty);
    await t.pump(const Duration(seconds: 4));
  });
}
