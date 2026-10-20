import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/client_history_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A client's page: visits, spending, favourite service, when they are due back, notes, and the choice not to be
/// texted.
class _FakeSalon extends SalonApi {
  _FakeSalon(this.history);

  ClientHistory history;
  Object? saveFails;
  final List<({int id, String? notes, bool? optOut})> saves = <({int id, String? notes, bool? optOut})>[];

  @override
  Future<ClientHistory> clientHistory(int customerId) async => history;

  @override
  Future<void> saveClient(int customerId, {String? notes, bool? smsOptOut, String? birthday, Map<String, String>? preferences}) async {
    saves.add((id: customerId, notes: notes, optOut: smsOptOut));
    if (birthday != null || preferences != null) profileSaves.add(<String, dynamic>{'birthday': birthday, 'preferences': preferences});
    if (saveFails != null) throw saveFails!;
  }

  final List<Map<String, dynamic>> profileSaves = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> packages = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> clientPackages(int customerId) async => packages;

  @override
  Future<List<Map<String, dynamic>>> clientPhotos(int customerId) async => <Map<String, dynamic>>[];
}

ClientHistory _neema({String? notes, bool optOut = false, NextVisit? next, bool visited = true}) => ClientHistory(
      id: 7,
      name: 'Neema Juma',
      phone: '0711000001',
      notes: notes,
      smsOptOut: optOut,
      visitCount: visited ? 3 : 0,
      totalSpent: visited ? 133000 : 0,
      lastVisitOn: visited ? DateTime(2026, 9, 20) : null,
      favouriteService: visited ? 'Braids' : null,
      nextVisit: next,
      visits: visited
          ? <ClientVisit>[
              ClientVisit(
                saleId: 11,
                number: 'S-20260920-0011',
                date: DateTime(2026, 9, 20),
                total: 45000,
                paid: 45000,
                paymentStatus: 'paid',
                items: const <ClientVisitItem>[
                  ClientVisitItem(name: 'Braids', isService: true, staffName: 'Asha', qty: 1, total: 40000),
                  ClientVisitItem(name: 'Wash', isService: true, staffName: null, qty: 1, total: 5000),
                ],
              ),
              ClientVisit(
                saleId: 12,
                number: 'S-20261002-0012',
                date: DateTime(2026, 10, 2),
                total: 16000,
                paid: 16000,
                paymentStatus: 'paid',
                items: const <ClientVisitItem>[ClientVisitItem(name: 'Shampoo', isService: false, staffName: null, qty: 2, total: 16000)],
              ),
            ]
          : <ClientVisit>[],
    );

final NextVisit _due = NextVisit(visitOn: DateTime(2026, 9, 20), dueOn: DateTime(2026, 11), ruleWeeks: 6, service: 'Braids');

Future<void> _open(WidgetTester t, _FakeSalon api, {bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(411, 900),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: ClientHistoryScreen(customerId: 7, name: 'Neema', api: api)),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('shows who the client is, how often they come, what they spend and like', (t) async {
    await _open(t, _FakeSalon(_neema(next: _due)));

    expect(find.text('Neema Juma'), findsNWidgets(2), reason: 'the title (the loaded name) and the client card');
    expect(find.text('0711000001'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'visits');
    expect(find.text('TSH 133,000'), findsOneWidget);
    expect(find.text('20/09/2026'), findsWidgets, reason: 'last visit');
    expect(find.text('Braids'), findsWidgets, reason: 'favourite service');
  });

  testWidgets('says when the client is due back, and why: the wait and the service', (t) async {
    await _open(t, _FakeSalon(_neema(next: _due)));

    expect(find.text('Due back 01/11/2026 (6 weeks after Braids)'), findsOneWidget);
  });

  testWidgets('in Swahili the sentence is Swahili: "wiki 6"', (t) async {
    await _open(t, _FakeSalon(_neema(next: _due)), sw: true);

    expect(find.text('Anatakiwa kurudi 01/11/2026 (wiki 6 baada ya Braids)'), findsOneWidget);
    expect(find.text('Ziara'), findsOneWidget);
    expect(find.text('Jumla aliyotumia'), findsOneWidget);
  });

  testWidgets('in Swahili one week is "wiki moja", not "wiki 1"', (t) async {
    await _open(
      t,
      _FakeSalon(_neema(next: NextVisit(visitOn: DateTime(2026, 9, 20), dueOn: DateTime(2026, 9, 27), ruleWeeks: 1, service: 'Wash'))),
      sw: true,
    );

    expect(find.text('Anatakiwa kurudi 27/09/2026 (wiki moja baada ya Wash)'), findsOneWidget);
  });

  testWidgets('lists the past visits with the stylist next to each service', (t) async {
    await _open(t, _FakeSalon(_neema(next: _due)));

    expect(find.text('20/09/2026 • S-20260920-0011'), findsOneWidget);
    expect(find.text('Braids — Asha'), findsOneWidget, reason: 'who did it');
    expect(find.text('Wash'), findsOneWidget, reason: 'no stylist named: just the service');
    expect(find.text('2 × Shampoo'), findsOneWidget, reason: 'goods show how many, and nobody served them');
    expect(find.text('TSH 45,000'), findsOneWidget);
  });

  testWidgets('a client who never had a service has dashes and no "due back" line', (t) async {
    await _open(t, _FakeSalon(_neema(visited: false)));

    expect(_key('client_next_visit'), findsNothing);
    expect(find.text('Nothing bought yet.'), findsOneWidget);
    expect(find.text('0'), findsOneWidget, reason: 'no visits');
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('the notes are shown, and saving sends them trimmed', (t) async {
    final _FakeSalon api = _FakeSalon(_neema(notes: 'Allergic to ammonia dye'));
    await _open(t, api);
    expect(find.widgetWithText(TextFormField, 'Allergic to ammonia dye'), findsOneWidget);

    await t.enterText(find.byType(TextFormField), '  Prefers Saturdays \n');
    await t.tap(_key('client_save_notes'));
    await _settle(t);

    expect(api.saves.single, (id: 7, notes: 'Prefers Saturdays', optOut: null));
    expect(find.text('Saved'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('a failed save says why', (t) async {
    final _FakeSalon api = _FakeSalon(_neema())..saveFails = ApiException('Imeshindikana. / It could not be saved.');
    await _open(t, api);

    await t.tap(_key('client_save_notes'));
    await _settle(t);

    expect(find.text('It could not be saved.'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('"do not text me" is saved at once and the switch follows', (t) async {
    final _FakeSalon api = _FakeSalon(_neema());
    await _open(t, api);
    expect(t.widget<Switch>(_key('client_sms_opt_out')).value, isFalse);

    await t.tap(_key('client_sms_opt_out'));
    await _settle(t);

    expect(api.saves.single, (id: 7, notes: null, optOut: true));
    expect(t.widget<Switch>(_key('client_sms_opt_out')).value, isTrue);
  });

  testWidgets('if the choice cannot be saved the switch stays as it was and the reason is shown', (t) async {
    final _FakeSalon api = _FakeSalon(_neema(optOut: true))..saveFails = ApiException('Kikao kimeisha. / Your session ended.');
    await _open(t, api);

    await t.tap(_key('client_sms_opt_out'));
    await _settle(t);

    expect(t.widget<Switch>(_key('client_sms_opt_out')).value, isTrue, reason: 'still opted out: nothing was saved');
    expect(find.text('Your session ended.'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('the salon extras: new or returning, points, birthday and preferences are saved together', (t) async {
    final ClientHistory h = ClientHistory(
      id: 7,
      name: 'Neema Juma',
      phone: '0711000001',
      notes: null,
      smsOptOut: false,
      visitCount: 3,
      totalSpent: 1000,
      lastVisitOn: null,
      favouriteService: null,
      nextVisit: null,
      visits: const <ClientVisit>[],
      birthday: '1995-03-21',
      preferences: const <String, String>{'hairstyle': 'Bob', 'allergies': 'Ammonia'},
      isReturning: true,
      loyaltyPoints: 42,
    );
    final _FakeSalon api = _FakeSalon(h)..packages = <Map<String, dynamic>>[<String, dynamic>{'id': 1, 'name': '5 braids', 'service_name': 'Braids', 'sessions_left': 3, 'sessions_total': 5, 'usable': true}];
    await _open(t, api);
    await t.pump();
    expect(find.text('Returning client'), findsOneWidget);
    expect(find.text('Points: 42'), findsOneWidget);
    expect(find.text('3/5'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1995-03-21'), findsOneWidget);

    await t.scrollUntilVisible(find.byKey(const Key('client_birthday')), 200, scrollable: find.byType(Scrollable).first);
    await t.enterText(find.byKey(const Key('client_birthday')), 'March');
    await t.tap(find.byKey(const Key('client_profile_save')));
    await _settle(t);
    expect(api.profileSaves, isEmpty, reason: 'a bad date is not sent');
    expect(find.textContaining('year-month-day'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));

    await t.enterText(find.byKey(const Key('client_birthday')), '1996-01-02');
    await t.enterText(find.byKey(const Key('client_pref_colour')), 'Honey blonde');
    await t.tap(find.byKey(const Key('client_profile_save')));
    await _settle(t);
    expect(api.profileSaves.single['birthday'], '1996-01-02');
    expect((api.profileSaves.single['preferences'] as Map<String, String>)['colour'], 'Honey blonde');
    expect((api.profileSaves.single['preferences'] as Map<String, String>)['hairstyle'], 'Bob');
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('a page that cannot load says why and can be tried again', (t) async {
    final _Flaky api = _Flaky(_neema());
    await _open(t, api);
    expect(find.text('No connection.'), findsOneWidget);

    await t.tap(_key('client_retry'));
    await _settle(t);

    expect(find.text('Neema Juma'), findsNWidgets(2));
  });
}

class _Flaky extends _FakeSalon {
  _Flaky(super.history);

  bool failed = false;

  @override
  Future<ClientHistory> clientHistory(int customerId) async {
    if (!failed) {
      failed = true;
      throw ApiException('Hakuna mtandao. / No connection.');
    }
    return super.clientHistory(customerId);
  }
}
