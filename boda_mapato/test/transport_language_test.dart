import 'dart:convert';

import 'package:boda_mapato/providers/debts_provider.dart';
import 'package:boda_mapato/screens/admin/communications_screen.dart';
import 'package:boda_mapato/screens/admin/debts_management_screen.dart';
import 'package:boda_mapato/screens/admin/drivers_management_screen.dart';
import 'package:boda_mapato/screens/admin/payments_management_screen.dart';
import 'package:boda_mapato/screens/admin/record_payment_screen.dart';
import 'package:boda_mapato/screens/payments/payments_screen.dart';
import 'package:boda_mapato/screens/reminders/reminders_screen.dart';
import 'package:boda_mapato/screens/reports/report_screen.dart';
import 'package:boda_mapato/screens/admin/vehicles_management_screen.dart';
import 'package:boda_mapato/services/http_client.dart' as app_http;
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as base;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Transport screen must speak ONE language: the one chosen in the app. These open the screens the way a
/// person does, once in English and once in Swahili, read every piece of text on them, and fail if a word of
/// the other language is there.

class _Server extends base.BaseClient {
  @override
  Future<base.StreamedResponse> send(base.BaseRequest request) async {
    final String path = request.url.path;
    final String now = DateTime(2026, 1, 5).toIso8601String();
    Object body;
    if (path.endsWith('/admin/drivers')) {
      body = <String, dynamic>{
        'status': 'success',
        'data': <String, dynamic>{
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': '1',
              'name': 'Juma Said',
              'email': 'juma@example.com',
              'phone': '0712345678',
              'license_number': 'LIC001',
              'vehicle_number': 'T123ABC',
              'vehicle_type': 'pikipiki',
              'status': 'active',
              'total_payments': 120000,
              'created_at': now,
            },
          ],
        },
      };
    } else if (path.endsWith('/admin/vehicles')) {
      body = <String, dynamic>{
        'status': 'success',
        'data': <String, dynamic>{
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'v1',
              'name': 'Boda One',
              'type': 'pikipiki',
              'plate_number': 'T123ABC',
              'is_active': true,
              'driver': <String, dynamic>{'id': '1', 'name': 'Juma Said', 'email': 'juma@example.com', 'phone': '0712345678'},
              'created_at': now,
              'updated_at': now,
            },
          ],
        },
      };
    } else if (path.endsWith('/admin/communications')) {
      body = <String, dynamic>{'status': 'success', 'data': <dynamic>[]};
    } else {
      body = <String, dynamic>{
        'status': 'success',
        'data': <String, dynamic>{'data': <dynamic>[], 'drivers': <dynamic>[], 'debt_records': <dynamic>[]},
      };
    }
    return base.StreamedResponse(Stream<List<int>>.value(utf8.encode(jsonEncode(body))), 200,
        request: request, headers: <String, String>{'content-type': 'application/json'});
  }
}

// Words that are Swahili and not English, and the other way round. A text in the wrong language has one of them.
const Set<String> _swahili = <String>{
  'madereva', 'dereva', 'magari', 'gari', 'chombo', 'vyombo', 'malipo', 'tafuta', 'ongeza', 'hariri', 'futa', 'washa',
  'zima', 'hakuna', 'bado', 'jina', 'simu', 'leseni', 'hali', 'hai', 'hahai', 'wote', 'ghairi', 'hifadhi', 'tarehe',
  'kiasi', 'ripoti', 'deni', 'safari', 'kiwango', 'makubaliano', 'sajili', 'simamia', 'ingiza', 'hamisha', 'tafadhali',
  'inapakia', 'jumla', 'maelezo', 'aina', 'namba', 'yamepewa', 'matumizi', 'ondoa', 'weka', 'chagua', 'ona', 'historia',
  'utabiri', 'rekodi', 'kamilisha', 'barua', 'pepe', 'bajaji', 'pikipiki',
};
const Set<String> _english = <String>{
  'drivers', 'driver', 'vehicles', 'vehicle', 'payments', 'payment', 'search', 'add', 'edit', 'delete', 'activate',
  'deactivate', 'none', 'name', 'phone', 'license', 'status', 'active', 'inactive', 'cancel', 'save', 'date', 'amount',
  'report', 'debt', 'trips', 'rating', 'agreement', 'register', 'manage', 'enter', 'export', 'import', 'please', 'loading',
  'total', 'description', 'type', 'number', 'assigned', 'unassigned', 'remove', 'assign', 'select', 'view', 'history',
  'prediction', 'record', 'complete', 'motorcycle',
};

Set<String> _wordsOf(String text) => RegExp(r'[a-z]+').allMatches(text.toLowerCase()).map((RegExpMatch m) => m.group(0)!).toSet();

/// Every text on the screen right now: Text widgets and the labels/hints of text fields.
List<String> _allTexts(WidgetTester tester) {
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
  for (final Element e in find.byType(Tooltip).evaluate()) {
    final String? s = (e.widget as Tooltip).message;
    if (s != null && s.trim().isNotEmpty) texts.add(s);
  }
  return texts;
}

void expectOnly(WidgetTester tester, String language) {
  final Set<String> wrong = language == 'en' ? _swahili : _english;
  final List<String> offenders = <String>[
    for (final String t in _allTexts(tester))
      if (_wordsOf(t).any(wrong.contains)) t,
  ];
  expect(offenders, isEmpty, reason: 'texts in the wrong language ($language):\n${offenders.join('\n')}');
}

Future<void> openScreen(WidgetTester tester, Widget screen, String language) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await LocalizationService.instance.changeLanguage(language);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (BuildContext context, Widget? child) => ChangeNotifierProvider<LocalizationService>.value(
        value: LocalizationService.instance,
        child: ChangeNotifierProvider<DebtsProvider>(
          create: (_) => DebtsProvider(),
          child: MaterialApp(home: screen),
        ),
      ),
    ),
  );
  // the screen asks the server for its data; let the answers arrive
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late base.Client previous;
  late String before;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{'auth_token': 'token'});
    previous = app_http.replaceClientForTesting(_Server());
    before = LocalizationService.instance.currentLanguage;
  });

  tearDown(() async {
    app_http.replaceClientForTesting(previous);
    await LocalizationService.instance.changeLanguage(before);
  });

  for (final String language in <String>['en', 'sw']) {
    testWidgets('Drivers Management reads in one language only ($language)', (WidgetTester tester) async {
      await openScreen(tester, const DriversManagementScreen(), language);
      // the driver from the server is on the screen, and so is the vehicle type in the chosen language
      expect(find.text('Juma Said'), findsWidgets);
      expect(
        find.textContaining(language == 'en' ? 'Motorcycle' : 'Pikipiki', findRichText: true),
        findsWidgets,
      );
      expect(_allTexts(tester).length, greaterThan(10), reason: 'the screen was not drawn');
      expectOnly(tester, language);

      // the Add Driver form
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Dialog), findsOneWidget);
      expectOnly(tester, language);
      await tester.tap(find.byType(TextButton).first);
      await tester.pump(const Duration(milliseconds: 400));

      // the actions menu on the driver's card
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PopupMenuItem<String>), findsWidgets);
      expectOnly(tester, language);
    });

    testWidgets('Vehicles Management reads in one language only ($language)', (WidgetTester tester) async {
      await openScreen(tester, const VehiclesManagementScreen(), language);
      expect(find.text('Boda One'), findsWidgets);
      expect(_allTexts(tester).length, greaterThan(10), reason: 'the screen was not drawn');
      expectOnly(tester, language);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Dialog), findsOneWidget);
      expectOnly(tester, language);
    });
  }

  // The other Transport screens: opened and read in both languages.
  final Map<String, Widget Function()> others = <String, Widget Function()>{
    'Payments Management': () => const PaymentsManagementScreen(),
    'Record Payment': () => const RecordPaymentScreen(),
    'Reports': () => const ReportScreen(),
    'Reminders': () => const RemindersScreen(),
    'Communications': () => const CommunicationsScreen(),
    'Debts': () => const DebtsManagementScreen(),
    'Payments': () => const PaymentsScreen(),
  };
  for (final String language in <String>['en', 'sw']) {
    for (final MapEntry<String, Widget Function()> screen in others.entries) {
      testWidgets('${screen.key} reads in one language only ($language)', (WidgetTester tester) async {
        await openScreen(tester, screen.value(), language);
        expect(_allTexts(tester).length, greaterThanOrEqualTo(3), reason: 'the screen was not drawn');
        expectOnly(tester, language);
      });
    }
  }
}
