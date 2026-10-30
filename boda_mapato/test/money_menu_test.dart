import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/screens/money/money_menu_screen.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Money & debts": one place with a sentence for each choice (customers & credit, debts, the monthly report), shown by what the
/// person may see.
class _Who extends AuthProvider {
  _Who(this.role, [this.grants = const <String>[]]);

  final String role;
  final List<String> grants;

  @override
  UserData? get user => UserData(id: 'u1', name: 'Someone', email: 'u@example.test', role: role, isActive: true);

  @override
  UserPermissions get permissions => grants.isEmpty ? UserPermissions.fromRole(role) : UserPermissions.fromList(grants);
}

Future<void> _pump(WidgetTester t, AuthProvider who, {bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<AuthProvider>.value(value: who),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => const MaterialApp(home: Scaffold(body: MoneyMenuScreen()))),
    ),
  );
  await t.pump();
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('the owner sees the three choices, in order, each with a sentence', (t) async {
    await _pump(t, _Who('admin'));

    expect(_key('money_credit'), findsOneWidget);
    expect(_key('money_debts'), findsOneWidget);
    expect(_key('money_monthly'), findsOneWidget);
    expect(t.getTopLeft(_key('money_credit')).dy, lessThan(t.getTopLeft(_key('money_debts')).dy));
    expect(t.getTopLeft(_key('money_debts')).dy, lessThan(t.getTopLeft(_key('money_monthly')).dy));
    expect(find.text('Customers & credit'), findsOneWidget);
    expect(find.textContaining('a report for each customer'), findsOneWidget);
    expect(find.textContaining('even from before the app'), findsOneWidget);
    expect(find.textContaining('where to improve'), findsOneWidget);
    expect(_key('money_trash'), findsOneWidget, reason: 'the owner also has the Trash, last');
    expect(t.getTopLeft(_key('money_monthly')).dy, lessThan(t.getTopLeft(_key('money_trash')).dy));
  });

  testWidgets('a tap on Monthly report opens it', (t) async {
    await _pump(t, _Who('admin'));

    await t.tap(_key('money_monthly'));
    for (int i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Monthly report'), findsWidgets);
    expect(_key('money_monthly'), findsNothing, reason: 'the menu is behind the report now');
  });

  testWidgets('Swahili', (t) async {
    await _pump(t, _Who('admin'), sw: true);

    expect(find.text('Wateja na mikopo'), findsOneWidget);
    expect(find.text('Madeni'), findsOneWidget);
    expect(find.text('Ripoti ya mwezi'), findsOneWidget);
  });

  testWidgets('someone who may see no credit and no reports gets no choice', (t) async {
    await _pump(t, _Who('sales_officer', <String>['inv_create_sales']));

    expect(_key('money_credit'), findsNothing);
    expect(_key('money_debts'), findsNothing);
    expect(_key('money_monthly'), findsNothing);
  });

  testWidgets('someone who may see only reports gets only the monthly report', (t) async {
    await _pump(t, _Who('sales_officer', <String>['inv_view_reports']));

    expect(_key('money_monthly'), findsOneWidget);
    expect(_key('money_debts'), findsNothing);
    expect(_key('money_trash'), findsNothing, reason: 'the Trash is for the owner and the admins');
  });
}
