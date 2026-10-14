import 'dart:io';
import 'dart:typed_data';

import 'package:boda_mapato/constants/styles.dart';
import 'package:boda_mapato/constants/theme_constants.dart';
import 'package:boda_mapato/models/business.dart';
import 'package:boda_mapato/models/business_registration.dart';
import 'package:boda_mapato/models/plan_prices.dart';
import 'package:boda_mapato/models/sms_sender.dart';
import 'package:boda_mapato/models/subscription.dart';
import 'package:boda_mapato/screens/admin/businesses_screen.dart';
import 'package:boda_mapato/screens/admin/plan_prices_screen.dart';
import 'package:boda_mapato/screens/admin/registrations_screen.dart';
import 'package:boda_mapato/screens/admin/sms_senders_screen.dart';
import 'package:boda_mapato/screens/settings/business_profile_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app theme gives EVERY text field a white fill (AppStyles.inputDecorationTheme, made for the light forms). On a
/// dark popup a field that does not say otherwise is drawn as a white box and the white text typed into it cannot be
/// read. These tests open the popups under that very theme and look at what is really drawn, and the popups must be in
/// the app's own colour, not a colour of their own.

/// The app's theme, as main.dart builds it where it matters here: a dark scheme, the dialog colour, and the white fields.
Widget _app(Widget home) => ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(800, 2400),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: ThemeConstants.primaryBlue,
            dialogTheme: const DialogThemeData(backgroundColor: ThemeConstants.primaryBlue, surfaceTintColor: Colors.transparent),
            useMaterial3: true,
          ),
          builder: (BuildContext context, Widget? child) => Theme(
            data: Theme.of(context).copyWith(inputDecorationTheme: AppStyles.inputDecorationTheme(context)),
            child: child!,
          ),
          home: home,
        ),
      ),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

/// Every text field on screen, as drawn: none may have a light, solid fill.
void _noWhiteBoxes(WidgetTester t, String where) {
  final List<InputDecorator> fields = t.widgetList<InputDecorator>(find.byType(InputDecorator)).toList();
  expect(fields, isNotEmpty, reason: '$where: there are no fields to look at');
  for (final InputDecorator d in fields) {
    final InputDecoration deco = d.decoration;
    if (deco.filled != true) continue;
    final Color fill = deco.fillColor ?? Colors.transparent;
    final bool lightAndSolid = fill.a > 0.5 && fill.computeLuminance() > 0.5;
    expect(lightAndSolid, isFalse, reason: '$where: a text field is drawn as a white box (fill $fill, label ${deco.labelText ?? deco.hintText})');
  }
}

/// The colour of the popup in front.
Color? _dialogColor(WidgetTester t) {
  final Finder dialog = find.byType(AlertDialog);
  if (dialog.evaluate().isNotEmpty) return t.widget<AlertDialog>(dialog.last).backgroundColor ?? ThemeConstants.primaryBlue;
  final Finder plain = find.byType(Dialog);
  return plain.evaluate().isEmpty ? null : t.widget<Dialog>(plain.last).backgroundColor;
}

Business _biz({String plan = 'standard'}) => Business(
      id: 'b-1',
      ownerId: 'u-1',
      name: 'Mama Duka',
      billing: BusinessBilling(plan: plan),
      services: const <String>['rental', 'inventory'],
      owner: const BusinessOwner(id: 'u-1', name: 'Asha Owner', email: 'a@b.c', phoneNumber: '0743519100', isActive: true),
    );

class _ProfileSource implements BusinessProfileDataSource {
  Business business = _biz();

  @override
  Future<Business> load() async => business;

  @override
  Future<Business> save({required String name, required String address, required String tin, required String phone, required String email, String? inventoryType}) async => business;

  @override
  Future<Business> uploadLogo(Uint8List bytes, String filename) async => business;

  @override
  Future<Business> removeLogo() async => business;

  @override
  Future<Business> requestSmsSender({required String senderId, String? displayName}) async => business;

  @override
  Future<Business> withdrawSmsSender() async => business;
}

class _RegistrationsSource implements RegistrationsDataSource {
  @override
  Future<RegistrationsPage> load(String status, {String? query}) async => RegistrationsPage(
        items: <BusinessRegistration>[
          BusinessRegistration.fromJson(<String, dynamic>{
            'id': '1', 'status': 'pending', 'business_name': 'Asha Rentals', 'requested_services': <String>['rental'],
            'user': <String, dynamic>{'name': 'Asha', 'email': 'a@b.c', 'phone_number': '0743519100', 'phone_verified': true},
          }),
        ],
        counts: const <String, int>{'pending': 1},
      );

  @override
  Future<void> approve(String id, List<String> services, {bool allowUnverified = false, String? plan, DateTime? validUntil, String? inventoryType}) async {}

  @override
  Future<void> reject(String id, String reason) async {}
}

class _BusinessesSource implements BusinessesDataSource {
  @override
  Future<BusinessesPage> load(String status, {String? query}) async => BusinessesPage(items: <Business>[_biz()], total: 1);

  @override
  Future<void> updateBilling(String id, {String? plan, DateTime? validUntil, bool clearValidUntil = false}) async {}

  @override
  Future<List<SubscriptionPayment>> payments(String id) async => <SubscriptionPayment>[];

  @override
  Future<PlanCatalog> planCatalog() async => PlanCatalog.fallback;

  @override
  Future<SubscriptionInfo> recordPayment(String id,
          {required double amount, String? method, String? reference, String? plan, int months = 1, DateTime? validUntil, String? note}) async =>
      const SubscriptionInfo(status: 'active', plan: 'standard');
}

class _SendersSource implements SmsSendersDataSource {
  @override
  Future<SmsSenderPage> load({String status = 'all', String? query, int page = 1, int perPage = 50}) async => SmsSenderPage(
        items: const <SmsSenderEntry>[SmsSenderEntry(id: 'b-1', name: 'Mama Duka', sender: SmsSenderInfo())],
        counts: const <String, int>{'total': 1, 'none': 1},
      );

  @override
  Future<SmsSenderEntry> save(String businessId, SmsSenderEdit edit) async => const SmsSenderEntry(id: 'b-1', name: 'Mama Duka', sender: SmsSenderInfo());

  @override
  Future<SmsSenderTestResult> test(String businessId, {String? phone, String? senderId, String? apiKey, String? apiSecret}) async => const SmsSenderTestResult(outcome: 'accepted');
}

class _PricesSource implements PlanPricesDataSource {
  @override
  Future<PlanCatalog> load() async => PlanCatalog.fallback;

  @override
  Future<PlanCatalog> save(Map<String, Map<int, double?>> changes) async => PlanCatalog.fallback;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => LocalizationService.instance.changeLanguage('sw'));

  group('a text field on a dark popup is never a white box', () {
    testWidgets('Business profile: "Ask for a sender name" (the one in the screenshot)', (t) async {
      _tall(t);
      await t.pumpWidget(_app(BusinessProfileScreen(canEdit: true, dataSource: _ProfileSource())));
      await t.pumpAndSettle();

      await t.ensureVisible(_key('request_sender'));
      await t.tap(_key('request_sender'));
      await t.pumpAndSettle();

      expect(_key('request_sender_id_field'), findsOneWidget);
      _noWhiteBoxes(t, 'ask for a sender name');
      expect(_dialogColor(t), ThemeConstants.primaryBlue, reason: 'in the app colour');

      // what is typed can be read: white text on a dark field
      await t.enterText(_key('request_sender_id_field'), 'MAMAASHA');
      await t.pump();
      expect(t.widget<TextField>(_key('request_sender_id_field')).style!.color, Colors.white);
      _noWhiteBoxes(t, 'ask for a sender name, typing');
    });

    testWidgets('Registrations: "Reject registration"', (t) async {
      _tall(t);
      await t.pumpWidget(_app(RegistrationsScreen(dataSource: _RegistrationsSource())));
      await t.pumpAndSettle();
      await t.tap(find.text('Asha Rentals'));
      await t.pumpAndSettle();

      await t.ensureVisible(_key('reject_button'));
      await t.tap(_key('reject_button'));
      await t.pumpAndSettle();

      expect(_key('reject_reason'), findsOneWidget);
      _noWhiteBoxes(t, 'reject registration');
      expect(_dialogColor(t), isNot(const Color(0xFF001D3D)));
      expect(t.widget<TextField>(_key('reject_reason')).style!.color, Colors.white);
    });

    testWidgets('Businesses & Plans: "Record payment" and its confirmation', (t) async {
      _tall(t);
      await t.pumpWidget(_app(BusinessesScreen(dataSource: _BusinessesSource())));
      await t.pumpAndSettle();
      await t.tap(find.text('Mama Duka'));
      await t.pumpAndSettle();
      await t.tap(_key('record_payment'));
      await t.pumpAndSettle();

      _noWhiteBoxes(t, 'record payment');
      expect(_dialogColor(t), ThemeConstants.primaryBlue);

      await t.enterText(_key('payment_amount'), '50000');
      await t.tap(_key('payment_submit'));
      await t.pumpAndSettle();
      expect(_key('confirm_payment'), findsOneWidget);
      expect(_dialogColor(t), ThemeConstants.primaryBlue, reason: 'the question is in the app colour too');
    });

    testWidgets('SMS Sender Names: the sheet for one business', (t) async {
      _tall(t);
      await t.pumpWidget(_app(SmsSendersScreen(dataSource: _SendersSource())));
      await t.pumpAndSettle();
      await t.tap(find.text('Mama Duka'));
      await t.pumpAndSettle();

      expect(_key('sender_id_field'), findsOneWidget);
      _noWhiteBoxes(t, 'sms sender sheet');
      expect(
        find.ancestor(of: _key('sender_id_field'), matching: find.byWidgetPredicate((Widget w) => w is Material && w.color == ThemeConstants.primaryBlue)),
        findsOneWidget,
        reason: 'the sheet is in the app colour',
      );
    });

    testWidgets('Plans & Prices: the price fields', (t) async {
      _tall(t);
      await t.pumpWidget(_app(PlanPricesScreen(dataSource: _PricesSource())));
      await t.pumpAndSettle();

      expect(_key('price_basic_1'), findsOneWidget);
      _noWhiteBoxes(t, 'plans and prices');
    });
  });

  group('the app colour', () {
    // Popups used a navy of their own (0xFF001D3D) while the rest of the app is the teal of ThemeConstants.primaryBlue.
    test('no screen or widget paints a popup in a colour of its own', () {
      final List<String> offenders = <String>[];
      for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String src = f.readAsStringSync();
        for (final String off in <String>['0xFF001D3D', '0xFF00305F']) {
          if (src.contains(off)) offenders.add('${f.path}: $off');
        }
      }
      expect(offenders, isEmpty, reason: 'use ThemeConstants.primaryBlue (or bgBottom for a menu): $offenders');
    });

    test('the dark field helper is not the theme\'s white', () {
      final InputDecoration d = ThemeConstants.darkField('Name');
      expect(d.filled, isTrue);
      expect(d.fillColor!.a, lessThan(0.3));
      expect(d.fillColor!.computeLuminance(), greaterThan(0.9), reason: 'a faint white veil over the surface, not a white box');
      expect(d.labelText, 'Name');
      expect(ThemeConstants.darkField('Name', error: 'Bad').errorText, 'Bad');
    });
  });
}
