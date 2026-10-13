import 'dart:convert';

import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/providers/debts_provider.dart';
import 'package:boda_mapato/providers/maintenance_provider.dart';
import 'package:boda_mapato/providers/rental_provider.dart';
import 'package:boda_mapato/screens/maintenance/maintenance_list_screen.dart';
import 'package:boda_mapato/screens/maintenance/vendors_list_screen.dart';
import 'package:boda_mapato/screens/rental/helpdesk_screen.dart';
import 'package:boda_mapato/screens/rental/rental_arrears_screen.dart';
import 'package:boda_mapato/screens/rental/rental_dashboard_screen.dart';
import 'package:boda_mapato/screens/rental/rental_payments_screen.dart';
import 'package:boda_mapato/screens/rental/rental_properties_screen.dart';
import 'package:boda_mapato/screens/rental/rental_receipts_screen.dart';
import 'package:boda_mapato/screens/rental/rental_tenants_screen.dart';
import 'package:boda_mapato/screens/settings/backup_screen.dart';
import 'package:boda_mapato/screens/settings/help_screen.dart';
import 'package:boda_mapato/screens/settings/permissions_management_screen.dart';
import 'package:boda_mapato/screens/settings/security_screen.dart';
import 'package:boda_mapato/screens/settings/settings_screen.dart';
import 'package:boda_mapato/screens/settings/user_management_screen.dart';
import 'package:boda_mapato/services/http_client.dart' as app_http;
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as base;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Rental, maintenance and settings screens read in ONE language: the one chosen in the app. Each is opened
/// in English and in Swahili (with the server answering "nothing yet"), every piece of text is read, and a word of
/// the other language fails the test. Same idea as transport_language_test.dart.

class _EmptyServer extends base.BaseClient {
  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'status': 'success',
      'success': true,
      'data': <String, dynamic>{'data': <dynamic>[], 'items': <dynamic>[]},
    };
    return base.StreamedResponse(Stream<List<int>>.value(utf8.encode(jsonEncode(body))), 200,
        request: request, headers: <String, String>{'content-type': 'application/json'});
  }
}

// Words only Swahili / only English uses. A text in the wrong language has one of them.
const Set<String> _swahili = <String>{
  'hakuna', 'bado', 'ongeza', 'hariri', 'futa', 'tafuta', 'ripoti', 'malipo', 'mpangaji', 'wapangaji', 'nyumba',
  'mali', 'mkataba', 'mikataba', 'kodi', 'deni', 'madeni', 'risiti', 'hifadhi', 'ghairi', 'chagua', 'tarehe',
  'kiasi', 'hali', 'jina', 'simu', 'matengenezo', 'fundi', 'mafundi', 'maombi', 'ombi', 'mipangilio', 'msaada',
  'watumiaji', 'mtumiaji', 'ruhusa', 'nywila', 'usalama', 'akaunti', 'mwenye', 'wazi', 'imekalia', 'vyumba',
  'karibu', 'wote', 'zote', 'yote', 'jumla', 'mapato', 'matumizi', 'ankara', 'bili', 'rudi', 'sawa',
};
const Set<String> _english = <String>{
  'no', 'yet', 'add', 'edit', 'delete', 'search', 'report', 'reports', 'payment', 'payments', 'tenant', 'tenants',
  'house', 'houses', 'property', 'properties', 'agreement', 'agreements', 'rent', 'debt', 'debts', 'receipt',
  'receipts', 'save', 'cancel', 'select', 'date', 'amount', 'status', 'name', 'phone', 'maintenance',
  'technician', 'technicians', 'requests', 'request', 'settings', 'help', 'users', 'user', 'permissions',
  'password', 'security', 'account', 'landlord', 'vacant', 'occupied', 'units', 'welcome', 'all', 'total',
  'income', 'expenses', 'bills', 'bill', 'back', 'ok',
};

Set<String> _wordsOf(String text) => RegExp(r'[a-z]+').allMatches(text.toLowerCase()).map((RegExpMatch m) => m.group(0)!).toSet();

List<String> _allTexts() {
  final List<String> texts = <String>[];
  for (final Element e in find.byType(Text).evaluate()) {
    final Text t = e.widget as Text;
    final String? s = t.data ?? t.textSpan?.toPlainText();
    if (s != null && s.trim().isNotEmpty) texts.add(s);
  }
  for (final Element e in find.byType(TextField).evaluate()) {
    final InputDecoration? d = (e.widget as TextField).decoration;
    for (final String? s in <String?>[d?.labelText, d?.hintText, d?.helperText]) {
      if (s != null && s.trim().isNotEmpty) texts.add(s);
    }
  }
  return texts;
}

void main() {
  late base.Client previous;
  late String before;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{'auth_token': 'token'});
    previous = app_http.replaceClientForTesting(_EmptyServer());
    before = LocalizationService.instance.currentLanguage;
  });

  tearDown(() async {
    app_http.replaceClientForTesting(previous);
    await LocalizationService.instance.changeLanguage(before);
  });

  // The check above could pass just because a screen draws nothing. So count the screens whose texts do contain
  // words of the language they are shown in: most of them must.
  final Map<String, int> readsInOwnLanguage = <String, int>{'en': 0, 'sw': 0};
  tearDownAll(() {
    expect(readsInOwnLanguage['sw'], greaterThanOrEqualTo(10), reason: 'Swahili texts were not found on the screens');
    expect(readsInOwnLanguage['en'], greaterThanOrEqualTo(10), reason: 'English texts were not found on the screens');
  });

  final Map<String, Widget Function()> screens = <String, Widget Function()>{
    'Rental dashboard': () => const RentalDashboardScreen(),
    'Rental properties': () => const RentalPropertiesScreen(),
    'Rental tenants': () => const RentalTenantsScreen(),
    'Rental payments': () => const RentalPaymentsScreen(),
    'Rental arrears': () => const RentalArrearsScreen(),
    'Rental receipts': () => const RentalReceiptsScreen(),
    'Helpdesk': () => const HelpdeskScreen(),
    'Maintenance list': () => const MaintenanceListScreen(),
    'Vendors list': () => const VendorsListScreen(),
    'Settings': () => const SettingsScreen(),
    'Help': () => const HelpScreen(),
    'Security': () => const SecurityScreen(),
    'Backup': () => const BackupScreen(),
    'User management': () => const UserManagementScreen(),
    'Permissions': () => const PermissionsScreen(),
  };

  for (final String language in <String>['en', 'sw']) {
    for (final MapEntry<String, Widget Function()> screen in screens.entries) {
      testWidgets('${screen.key} reads in one language only ($language)', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await LocalizationService.instance.changeLanguage(language);

        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (BuildContext context, Widget? child) => MultiProvider(
              providers: <ChangeNotifierProvider<ChangeNotifier>>[
                ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
                ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
                ChangeNotifierProvider<RentalProvider>(create: (_) => RentalProvider()),
                ChangeNotifierProvider<MaintenanceProvider>(create: (_) => MaintenanceProvider()),
                ChangeNotifierProvider<DebtsProvider>(create: (_) => DebtsProvider()),
              ],
              child: MaterialApp(home: screen.value()),
            ),
          ),
        );
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }

        final List<String> texts = _allTexts();
        expect(texts.length, greaterThanOrEqualTo(2), reason: 'the screen was not drawn');
        final Set<String> own = language == 'en' ? _english : _swahili;
        if (texts.any((String t) => _wordsOf(t).any(own.contains))) {
          readsInOwnLanguage[language] = readsInOwnLanguage[language]! + 1;
        }
        final Set<String> wrong = language == 'en' ? _swahili : _english;
        final List<String> offenders = <String>[
          for (final String t in texts)
            if (_wordsOf(t).any(wrong.contains)) t,
        ];
        expect(offenders, isEmpty, reason: 'texts in the wrong language ($language):\n${offenders.join('\n')}');
      });
    }
  }
}
