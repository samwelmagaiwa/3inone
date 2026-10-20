import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/rebook_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Come back" reminders: the owner switches them on, sets the usual wait in weeks, and sees who is due now and
/// whether they were texted.
class _FakeSalon extends SalonApi {
  _FakeSalon({required this.settings, this.clients = const <RebookClient>[]});

  RebookSettings settings;
  List<RebookClient> clients;
  Object? saveFails;
  final List<({bool? enabled, int? weeks})> saves = <({bool? enabled, int? weeks})>[];
  int loads = 0;

  @override
  Future<RebookOverview> rebookOverview() async {
    loads++;
    return RebookOverview(settings: settings, clients: clients);
  }

  @override
  Future<RebookSettings> saveRebookSettings({bool? enabled, int? weeks}) async {
    saves.add((enabled: enabled, weeks: weeks));
    if (saveFails != null) throw saveFails!;
    settings = settings.copyWith(enabled: enabled, weeks: weeks);
    return settings;
  }
}

RebookClient _client(
  int id,
  String name, {
  String service = 'Braids',
  int weeksWaited = 4,
  bool sent = false,
  bool canText = true,
  String? skip,
  String phone = '0711000001',
}) =>
    RebookClient(
      customerId: id,
      name: name,
      phone: phone,
      visitOn: DateTime(2026, 9),
      dueOn: DateTime(2026, 9, 29),
      weeksWaited: weeksWaited,
      ruleWeeks: 4,
      service: service,
      sent: sent,
      canText: canText,
      skipReason: skip,
    );

Future<void> _open(WidgetTester t, _FakeSalon api, {bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 1200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(411, 900),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: Scaffold(body: RebookScreen(api: api))),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(milliseconds: 100));
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('shows the switch, the usual wait and who is due now', (t) async {
    await _open(t, _FakeSalon(settings: const RebookSettings(enabled: true, weeks: 4), clients: <RebookClient>[_client(1, 'Anna Mushi'), _client(2, 'Beth', service: 'Haircut')]));

    expect(t.widget<Switch>(_key('rebook_switch')).value, isTrue);
    expect(find.text('4 weeks'), findsOneWidget);
    expect(find.text('Due to come back now (2)'), findsOneWidget);
    expect(find.text('Anna Mushi'), findsOneWidget);
    expect(find.textContaining('Haircut • 01/09/2026'), findsOneWidget);
    expect(find.text('Switched off: no text is sent.'), findsNothing);
  });

  testWidgets('each client says whether the text went, will go, or cannot go and why', (t) async {
    await _open(
      t,
      _FakeSalon(
        settings: const RebookSettings(enabled: true, weeks: 4),
        clients: <RebookClient>[
          _client(1, 'Sent One', sent: true),
          _client(2, 'Pending One'),
          _client(3, 'No Phone', canText: false, skip: 'no_phone', phone: ''),
          _client(4, 'Opted Out', canText: false, skip: 'opted_out'),
        ],
      ),
    );

    Finder badge(int id, String text) => find.descendant(of: _key('rebook_client_$id'), matching: find.text(text));
    expect(badge(1, 'Texted'), findsOneWidget);
    expect(badge(2, 'Will be texted'), findsOneWidget);
    expect(badge(3, 'No phone number'), findsOneWidget);
    expect(badge(4, 'Opted out'), findsOneWidget);
  });

  testWidgets('the weeks since the visit agree with the number: one week, 4 weeks', (t) async {
    await _open(
      t,
      _FakeSalon(settings: const RebookSettings(enabled: true, weeks: 1), clients: <RebookClient>[_client(1, 'One', weeksWaited: 1), _client(2, 'Six', weeksWaited: 6)]),
    );

    expect(find.textContaining('One week ago'), findsOneWidget);
    expect(find.textContaining('6 weeks ago'), findsOneWidget);
  });

  testWidgets('in Swahili: "Wiki moja iliyopita" and "Wiki 6 zilizopita"', (t) async {
    await _open(
      t,
      _FakeSalon(settings: const RebookSettings(enabled: true, weeks: 1), clients: <RebookClient>[_client(1, 'One', weeksWaited: 1), _client(2, 'Six', weeksWaited: 6)]),
      sw: true,
    );

    expect(find.textContaining('Wiki moja iliyopita'), findsOneWidget);
    expect(find.textContaining('Wiki 6 zilizopita'), findsOneWidget);
    expect(find.text('wiki moja'), findsOneWidget, reason: 'the usual wait is one week');
    expect(find.text('Vikumbusho vya kurudi'), findsOneWidget);
    expect(find.text('Wanaotakiwa kurudi sasa (2)'), findsOneWidget);
    expect(find.text('Atatumiwa'), findsNWidgets(2));
  });

  testWidgets('nobody due says so', (t) async {
    await _open(t, _FakeSalon(settings: const RebookSettings(enabled: true, weeks: 4)));

    expect(find.text('Due to come back now (0)'), findsOneWidget);
    expect(find.text('No client is due to come back today.'), findsOneWidget);
  });

  testWidgets('switched off: no text is sent, and the list still shows who would be due', (t) async {
    await _open(t, _FakeSalon(settings: const RebookSettings(enabled: false, weeks: 4), clients: <RebookClient>[_client(1, 'Anna')]));

    expect(t.widget<Switch>(_key('rebook_switch')).value, isFalse);
    expect(find.text('Switched off: no text is sent.'), findsOneWidget);
    expect(find.descendant(of: _key('rebook_client_1'), matching: find.text('Off')), findsOneWidget);
  });

  testWidgets('switching it on is saved, and the list is read again', (t) async {
    final _FakeSalon api = _FakeSalon(settings: const RebookSettings(enabled: false, weeks: 4), clients: <RebookClient>[_client(1, 'Anna')]);
    await _open(t, api);

    await t.tap(_key('rebook_switch'));
    await _settle(t);

    expect(api.saves, <({bool? enabled, int? weeks})>[(enabled: true, weeks: null)]);
    expect(t.widget<Switch>(_key('rebook_switch')).value, isTrue);
    expect(find.text('Switched off: no text is sent.'), findsNothing);
    expect(api.loads, greaterThanOrEqualTo(2), reason: 'who is due depends on it');
    expect(find.descendant(of: _key('rebook_client_1'), matching: find.text('Will be texted')), findsOneWidget);
  });

  testWidgets('the usual wait goes up and down a week at a time, saved each time', (t) async {
    final _FakeSalon api = _FakeSalon(settings: const RebookSettings(enabled: true, weeks: 4));
    await _open(t, api);

    await t.tap(_key('rebook_weeks_plus'));
    await _settle(t);
    expect(find.text('5 weeks'), findsOneWidget);

    await t.tap(_key('rebook_weeks_minus'));
    await _settle(t);
    await t.tap(_key('rebook_weeks_minus'));
    await _settle(t);

    expect(find.text('3 weeks'), findsOneWidget);
    expect(api.saves.map((s) => s.weeks).toList(), <int?>[5, 4, 3]);
  });

  testWidgets('the wait cannot go below one week or above the most the server allows', (t) async {
    final _FakeSalon low = _FakeSalon(settings: const RebookSettings(enabled: true, weeks: 1));
    await _open(t, low);
    expect(t.widget<IconButton>(_key('rebook_weeks_minus')).onPressed, isNull, reason: 'one week is the least');
    expect(find.text('one week'), findsOneWidget);
  });

  testWidgets('the top of the range disables "more"', (t) async {
    await _open(t, _FakeSalon(settings: const RebookSettings(enabled: true, weeks: 52)));

    expect(t.widget<IconButton>(_key('rebook_weeks_plus')).onPressed, isNull);
  });

  testWidgets('if the server says no, the screen goes back to what it was and says why', (t) async {
    final _FakeSalon api = _FakeSalon(settings: const RebookSettings(enabled: false, weeks: 4))..saveFails = ApiException('Kikao kimeisha. / Your session ended.');
    await _open(t, api);

    await t.tap(_key('rebook_switch'));
    await _settle(t);

    expect(t.widget<Switch>(_key('rebook_switch')).value, isFalse, reason: 'it is still off: nothing was saved');
    expect(find.text('Your session ended.'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('a failed load says why and can be retried', (t) async {
    final _Flaky api = _Flaky();
    await _open(t, api);
    expect(find.text('No connection.'), findsOneWidget);

    await t.tap(_key('rebook_retry'));
    await _settle(t);

    expect(find.text('Due to come back now (0)'), findsOneWidget);
  });
}

class _Flaky extends _FakeSalon {
  _Flaky() : super(settings: const RebookSettings(enabled: true, weeks: 4));

  bool failed = false;

  @override
  Future<RebookOverview> rebookOverview() async {
    if (!failed) {
      failed = true;
      throw ApiException('Hakuna mtandao. / No connection.');
    }
    return super.rebookOverview();
  }
}
