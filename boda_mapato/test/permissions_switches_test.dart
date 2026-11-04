import 'package:boda_mapato/screens/settings/user_permissions_management_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Access rights as switches: green and locked for what the role gives, cyan for what was added for this person, grey and off
/// for the rest; with the counts and the two quick actions, and a save that sends exactly the extras.
class _Api extends ApiService {
  final List<List<String>> saved = <List<String>>[];

  @override
  Future<Map<String, dynamic>> updateUserPermissions(String userId, List<String> permissions) async {
    saved.add(permissions);

    return <String, dynamic>{'success': true};
  }
}

Future<_Api> _open(WidgetTester t, {List<String> extra = const <String>[]}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(900, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Api api = _Api();
  await t.pumpWidget(
    MaterialApp(
      home: UserPermissionsManagementScreen(
        user: <String, dynamic>{'id': 'u-7', 'name': 'Asha', 'role': 'hair_stylist', 'permissions': extra},
        serviceType: 'salon',
        api: api,
      ),
    ),
  );
  await t.pumpAndSettle();

  return api;
}

Finder _k(String k) => find.byKey(Key(k));

Switch _switch(WidgetTester t, String id) => t.widget<Switch>(_k('perm_switch_$id'));

void main() {
  testWidgets('what the role gives is on and locked, the rest is off', (WidgetTester t) async {
    await _open(t);

    expect(_switch(t, 'inv_view_products').value, isTrue);
    expect(_switch(t, 'inv_view_products').onChanged, isNull, reason: 'locked: the role gives it');
    expect(_switch(t, 'inv_view_cash').value, isFalse);
    expect(_switch(t, 'inv_view_cash').onChanged, isNotNull);
    expect(find.text('Given by the role (locked)'), findsWidgets);
    expect(find.text('Not allowed'), findsWidgets);
  });

  testWidgets('a switch adds an extra right, shows it as extra, and the counts follow', (WidgetTester t) async {
    await _open(t);
    expect(find.descendant(of: _k('perm_count_role'), matching: find.textContaining('4')), findsOneWidget);
    expect(find.descendant(of: _k('perm_count_extra'), matching: find.textContaining('0')), findsOneWidget);

    await t.tap(_k('perm_switch_inv_view_cash'));
    await t.pumpAndSettle();

    expect(_switch(t, 'inv_view_cash').value, isTrue);
    expect(find.text('Extra for this person'), findsOneWidget);
    expect(find.descendant(of: _k('perm_count_extra'), matching: find.textContaining('1')), findsOneWidget);
  });

  testWidgets('tapping the row does the same as its switch, and a locked row does nothing', (WidgetTester t) async {
    await _open(t);

    await t.tap(find.text('Daily cash'));
    await t.pumpAndSettle();
    expect(_switch(t, 'inv_view_cash').value, isTrue);

    await t.tap(find.text('Daily cash'));
    await t.pumpAndSettle();
    expect(_switch(t, 'inv_view_cash').value, isFalse);

    await t.tap(find.text('Services & goods'));
    await t.pumpAndSettle();
    expect(_switch(t, 'inv_view_products').value, isTrue, reason: 'still given by the role');
  });

  testWidgets('Turn all on adds every missing right as an extra; Remove extras takes them all back', (WidgetTester t) async {
    final _Api api = await _open(t, extra: <String>['inv_view_cash']);

    await t.tap(_k('perm_grant_all'));
    await t.pumpAndSettle();
    expect(_switch(t, 'inv_manage_settings').value, isTrue);
    expect(find.descendant(of: _k('perm_count_off'), matching: find.textContaining('0')), findsOneWidget);
    expect(t.widget<TextButton>(_k('perm_grant_all')).onPressed, isNull, reason: 'nothing is left to turn on');

    await t.tap(_k('perm_clear_extras'));
    await t.pumpAndSettle();
    expect(_switch(t, 'inv_manage_settings').value, isFalse);
    expect(_switch(t, 'inv_view_products').value, isTrue, reason: 'what the role gives stays');

    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();
    expect(api.saved.single, isEmpty);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('save sends only the extras, never what the role already gives', (WidgetTester t) async {
    final _Api api = await _open(t);

    await t.tap(_k('perm_switch_inv_view_cash'));
    await t.tap(_k('perm_switch_inv_view_reports'));
    await t.pumpAndSettle();
    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();

    expect(api.saved.single, <String>['inv_view_cash', 'inv_view_reports']);
    await t.pump(const Duration(seconds: 4));
  });
}
