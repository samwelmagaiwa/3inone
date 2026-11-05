import 'package:boda_mapato/models/business.dart';
import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/screens/settings/settings_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(
        id: 'u1',
        name: 'ivan samwel',
        email: 'ivan@example.test',
        role: role,
        isActive: true,
        serviceTypes: const <String>['salon'],
        business: const Business(id: 'b1', name: "MARY'S BEAUTY", billing: BusinessBilling(plan: 'basic')),
      );
}

Future<void> _open(WidgetTester t, String role) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(411, 1800), minTextAdapt: true, builder: (_, __) => const MaterialApp(home: SettingsScreen())),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets("the business's details and its subscription are the owner's: an accountant does not see them", (t) async {
    await _open(t, 'accountant');

    expect(find.text("MARY'S BEAUTY"), findsNothing);
    expect(find.text('My Subscription'), findsNothing);
    expect(find.text('Business'), findsNothing);
  });

  testWidgets('the owner sees the business and its subscription', (t) async {
    await _open(t, 'admin');

    expect(find.text("MARY'S BEAUTY"), findsOneWidget);
    expect(find.text('My Subscription'), findsOneWidget);
  });

  testWidgets('the profile card takes the full width, so the person sits in the middle of it', (t) async {
    await _open(t, 'accountant');

    final Rect name = t.getRect(find.text('ivan samwel'));
    final double screen = t.view.physicalSize.width / t.view.devicePixelRatio;
    expect((name.center.dx - screen / 2).abs(), lessThan(8), reason: 'the name is centred on the screen');
  });
}
