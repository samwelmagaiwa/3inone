import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/salon_business_profile.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthProvider {
  @override
  UserData? get user => UserData(id: 'u1', name: 'Super', email: 's@example.test', role: 'super_admin', isActive: true, serviceTypes: const <String>['salon']);
}

void main() {
  testWidgets('a super admin has no business: the page says so instead of failing', (t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage('en');
    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
          ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
        ],
        child: const MaterialApp(home: SalonBusinessProfilePage()),
      ),
    );
    await t.pump();
    expect(find.byKey(const Key('no_business_note')), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}
