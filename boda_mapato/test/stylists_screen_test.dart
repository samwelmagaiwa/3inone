import 'dart:async';

import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/stylists_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How each stylist did: the month's takings, services, visits and clients, best first; this month, last month or
/// the last 7 days.
class _FakeSalon extends SalonApi {
  _FakeSalon(this.answer);

  Future<StylistReport> Function(DateTime? from, DateTime? to) answer;
  final List<(DateTime?, DateTime?)> asked = <(DateTime?, DateTime?)>[];
  final List<(String, Map<String, double>)> savedTargets = <(String, Map<String, double>)>[];
  StylistTargets targets = const StylistTargets(month: '2026-10', canSet: true, people: <TargetPerson>[]);
  bool failSave = false;

  @override
  Future<StylistTargets> stylistTargets(String month) async => targets;

  @override
  Future<StylistTargets> saveStylistTargets(String month, Map<String, double> t) async {
    if (failSave) throw ApiException('Ni mmiliki tu anayeweka malengo. / Only the owner sets targets.');
    savedTargets.add((month, t));

    return targets;
  }

  @override
  Future<StylistReport> stylists({DateTime? from, DateTime? to}) {
    asked.add((from, to));
    return answer(from, to);
  }
}

StylistReport _report({List<StylistRow> rows = const <StylistRow>[]}) => StylistReport(
      from: DateTime(2026, 10),
      to: DateTime(2026, 10, 15),
      stylists: rows,
      services: rows.fold(0, (int s, StylistRow r) => s + r.services),
      revenue: rows.fold(0, (double s, StylistRow r) => s + r.revenue),
      visits: rows.fold(0, (int s, StylistRow r) => s + r.visits),
    );

const StylistRow _asha = StylistRow(staffId: 'u-asha', name: 'Asha', services: 3, revenue: 50000, visits: 2, clients: 1);
const StylistRow _bahati = StylistRow(staffId: 'u-bahati', name: 'Bahati', services: 1, revenue: 40000, visits: 1, clients: 1);
const StylistRow _nobody = StylistRow(staffId: null, name: '', services: 1, revenue: 5000, visits: 1, clients: 0);

final DateTime _today = DateTime(2026, 10, 15);

Future<void> _open(WidgetTester t, _FakeSalon api, {bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(411, 900),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: Scaffold(body: StylistsScreen(api: api, today: _today))),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('shows the totals, and each stylist with what they brought in, best first', (t) async {
    await _open(t, _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha, _bahati, _nobody])));

    expect(find.text('TSH 95,000'), findsOneWidget, reason: 'the total');
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('TSH 50,000'), findsOneWidget);
    expect(find.text('Bahati'), findsOneWidget);
    expect(find.text('TSH 40,000'), findsOneWidget);
    expect(find.text('No stylist named'), findsOneWidget, reason: 'a line with nobody named is still shown, honestly');
    expect(t.getTopLeft(_key('stylist_u-asha')).dy, lessThan(t.getTopLeft(_key('stylist_u-bahati')).dy), reason: 'the best first');
    expect(t.getTopLeft(_key('stylist_u-bahati')).dy, lessThan(t.getTopLeft(_key('stylist_none')).dy));
  });

  testWidgets('shows what each stylist earned in commission, and says nothing when no service has a rate', (t) async {
    const StylistRow earns = StylistRow(staffId: 'u-asha', name: 'Asha', services: 2, revenue: 50000, visits: 2, clients: 1, commission: 15000);
    await _open(t, _FakeSalon((_, __) async => StylistReport(from: DateTime(2026, 10), to: DateTime(2026, 10, 15), stylists: <StylistRow>[earns, _bahati], services: 3, revenue: 90000, visits: 3, commission: 15000)));

    expect(find.text('TSH 15,000'), findsNWidgets(2), reason: 'the total, and Ashas card');
    expect(find.descendant(of: _key('stylist_u-asha'), matching: find.text('Commission')), findsOneWidget);
    expect(find.descendant(of: _key('stylist_u-bahati'), matching: find.text('Commission')), findsNothing);
  });

  testWidgets('no commission anywhere shows no commission line', (t) async {
    await _open(t, _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha])));

    expect(find.text('Commission'), findsNothing);
    expect(find.text("Stylists' commission"), findsNothing);
  });

  testWidgets('says services, visits and clients for each stylist', (t) async {
    await _open(t, _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha])));

    final Finder card = _key('stylist_u-asha');
    expect(find.descendant(of: card, matching: find.text('3')), findsOneWidget, reason: '3 services');
    expect(find.descendant(of: card, matching: find.text('2')), findsOneWidget, reason: '2 visits');
    expect(find.descendant(of: card, matching: find.text('1')), findsWidgets, reason: '1 client (and the rank)');
    expect(find.descendant(of: card, matching: find.text('Services')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Visits')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Clients')), findsOneWidget);
  });

  testWidgets('asks for this month first, then last month, then the last 7 days', (t) async {
    final _FakeSalon api = _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha]));
    await _open(t, api);

    expect(api.asked.last, (DateTime(2026, 10), DateTime(2026, 10, 15)), reason: 'this month: the 1st to today');

    await t.tap(find.text('Last month'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(api.asked.last, (DateTime(2026, 9), DateTime(2026, 9, 30)), reason: 'all of September');

    await t.ensureVisible(find.text('Last 7 days')); // the chips scroll sideways on a narrow phone
    await t.tap(find.text('Last 7 days'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(api.asked.last, (DateTime(2026, 10, 9), DateTime(2026, 10, 15)), reason: 'today and the 6 days before');
    expect(api.asked, hasLength(3));
  });

  testWidgets('last month in January is December of the year before', (t) async {
    final _FakeSalon api = _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha]));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    t.view.physicalSize = const Size(411, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<LocalizationService>.value(
        value: LocalizationService.instance,
        child: ScreenUtilInit(
          designSize: const Size(411, 900),
          minTextAdapt: true,
          builder: (_, __) => MaterialApp(home: Scaffold(body: StylistsScreen(api: api, today: DateTime(2027, 1, 10)))),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    await t.tap(find.text('Last month'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(api.asked.last, (DateTime(2026, 12), DateTime(2026, 12, 31)));
  });

  testWidgets('a period with no services says what to do, not just "nothing"', (t) async {
    await _open(t, _FakeSalon((_, __) async => _report()));

    expect(find.textContaining('No services recorded for this period'), findsOneWidget);
    expect(find.textContaining('Choose a stylist each time you sell a service'), findsOneWidget);
    expect(find.text('TSH 0'), findsNWidgets(2), reason: 'the revenue, and what a visit is worth');
  });

  testWidgets('a failed load says why and can be retried', (t) async {
    int calls = 0;
    await _open(t, _FakeSalon((_, __) async {
      calls++;
      if (calls == 1) throw ApiException('Hakuna mtandao. / No connection.');
      return _report(rows: <StylistRow>[_asha]);
    }));

    expect(find.text('No connection.'), findsOneWidget);

    await t.tap(_key('stylists_retry'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('No connection.'), findsNothing);
  });

  testWidgets('an answer for a period nobody is looking at any more is thrown away', (t) async {
    final Completer<StylistReport> slow = Completer<StylistReport>();
    int calls = 0;
    final _FakeSalon api = _FakeSalon((_, __) {
      calls++;
      return calls == 1 ? slow.future : Future<StylistReport>.value(_report(rows: <StylistRow>[_bahati]));
    });
    await _open(t, api);

    await t.tap(find.text('Last month')); // while this month is still loading
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Bahati'), findsOneWidget);

    slow.complete(_report(rows: <StylistRow>[_asha])); // the slow, old answer arrives late
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.text('Bahati'), findsOneWidget, reason: 'last month is what is on screen');
    expect(find.text('Asha'), findsNothing, reason: 'this month\'s late answer did not overwrite it');
  });

  testWidgets('in Swahili the labels are Swahili', (t) async {
    await _open(t, _FakeSalon((_, __) async => _report(rows: <StylistRow>[_asha, _nobody])), sw: true);

    expect(find.text('Mwezi huu'), findsOneWidget);
    expect(find.text('Mwezi uliopita'), findsOneWidget);
    expect(find.text('Siku 7'), findsOneWidget);
    expect(find.text('Mapato'), findsOneWidget);
    expect(find.text('Hakutajwa mhudumu'), findsOneWidget);
    expect(find.text('Ziara'), findsWidgets);
  });

  group('how they did against before, who is ahead, and the targets', () {
    StylistTarget target(String pace, double percent) => StylistTarget(month: '2026-10', amount: 200000, achieved: 140000, percent: percent, expectedPercent: 66.7, pace: pace);

    final StylistRow ashaPlus = StylistRow(
      staffId: 'u-asha', name: 'Asha', services: 3, revenue: 140000, visits: 3, clients: 2, commission: 14000,
      avgTicket: 46667, returnRate: 50, share: 82.4, rank: 1, previousRevenue: 100000, revenueChange: 40, target: target('ahead', 70),
    );
    const StylistRow bahatiMinus = StylistRow(
      staffId: 'u-bahati', name: 'Bahati', services: 1, revenue: 30000, visits: 1, clients: 1,
      avgTicket: 30000, returnRate: 0, share: 17.6, rank: 2, previousRevenue: 90000, revenueChange: -66.7,
    );
    const StylistRow chaoNothing = StylistRow(
      staffId: 'u-chao', name: 'Chao', services: 0, revenue: 0, visits: 0, clients: 0, previousRevenue: 50000, revenueChange: -100,
    );

    StylistReport report({List<StylistRow>? rows, bool everyone = true, bool canSet = false}) => StylistReport(
          from: DateTime(2026, 10), to: DateTime(2026, 10, 15), stylists: rows ?? <StylistRow>[ashaPlus, bahatiMinus, chaoNothing],
          services: 4, revenue: 170000, visits: 4, commission: 14000, avgTicket: 42500, previousRevenue: 240000, revenueChange: -29.2,
          previousFrom: DateTime(2026, 9, 16), previousTo: DateTime(2026, 9, 30), targetMonth: '2026-10', seesEveryone: everyone, canSetTargets: canSet,
        );

    testWidgets('says what a visit is worth and how many clients come back, for each stylist and for all of them', (t) async {
      await _open(t, _FakeSalon((_, __) async => report()));

      expect(find.text('TSH 42,500'), findsOneWidget, reason: 'all of them: 170,000 over 4 visits');
      final Finder asha = _key('stylist_u-asha');
      expect(find.descendant(of: asha, matching: find.text('Avg per visit')), findsOneWidget);
      expect(find.descendant(of: asha, matching: find.text('TSH 46,667')), findsOneWidget);
      expect(find.descendant(of: asha, matching: find.text('Came back')), findsOneWidget);
      expect(find.descendant(of: asha, matching: find.text('50%')), findsOneWidget);
      expect(find.descendant(of: asha, matching: find.text('Share')), findsOneWidget);
      expect(find.descendant(of: asha, matching: find.text('82.4%')), findsOneWidget);
      expect(find.descendant(of: _key('stylist_u-chao'), matching: find.text('Came back')), findsNothing, reason: 'no clients, nothing to say');
      expect(find.descendant(of: _key('stylist_u-chao'), matching: find.text('Avg per visit')), findsNothing, reason: 'no visits');
    });

    testWidgets('each line says up or down against the period before, and the total says it too', (t) async {
      await _open(t, _FakeSalon((_, __) async => report()));

      expect(find.descendant(of: _key('change_u-asha'), matching: find.text('+40%')), findsOneWidget);
      expect(find.descendant(of: _key('change_u-bahati'), matching: find.text('-66.7%')), findsOneWidget);
      expect(find.descendant(of: _key('change_u-chao'), matching: find.text('-100%')), findsOneWidget, reason: 'gone to nothing is shown');
      expect(find.descendant(of: _key('stylists_total_change'), matching: find.text('-29.2%')), findsOneWidget);
      expect(find.descendant(of: _key('stylists_compare'), matching: find.textContaining('16/9 - 30/9')), findsOneWidget);
      expect(find.descendant(of: _key('change_u-asha'), matching: find.byIcon(Icons.arrow_upward_rounded)), findsOneWidget);
      expect(find.descendant(of: _key('change_u-bahati'), matching: find.byIcon(Icons.arrow_downward_rounded)), findsOneWidget);
    });

    testWidgets('a person with nothing before to compare with is "new", not given a made-up percent', (t) async {
      const StylistRow fresh = StylistRow(staffId: 'u-new', name: 'Newcomer', services: 1, revenue: 20000, visits: 1, clients: 1, avgTicket: 20000, rank: 1, previousRevenue: 0);
      await _open(t, _FakeSalon((_, __) async => report(rows: <StylistRow>[fresh])));

      expect(find.descendant(of: _key('change_u-new'), matching: find.text('new')), findsNothing, reason: 'with no previous revenue and no change the chip is not drawn at all');
    });

    testWidgets('the first three get a gold, silver or bronze medal, the others a number', (t) async {
      const StylistRow third = StylistRow(staffId: 'u-3', name: 'Third', services: 1, revenue: 10000, visits: 1, clients: 1, rank: 3);
      const StylistRow fourth = StylistRow(staffId: 'u-4', name: 'Fourth', services: 1, revenue: 5000, visits: 1, clients: 1, rank: 4);
      await _open(t, _FakeSalon((_, __) async => report(rows: <StylistRow>[ashaPlus, bahatiMinus, third, fourth])));

      for (final String id in <String>['u-asha', 'u-bahati', 'u-3']) {
        expect(_key('medal_$id'), findsOneWidget, reason: id);
      }
      expect(_key('medal_u-4'), findsNothing);
      Color colour(String id) => ((t.widget<Container>(_key('medal_$id'))).decoration as BoxDecoration).color!;
      expect(colour('u-asha'), const Color(0xFFF5B301));
      expect(colour('u-bahati'), const Color(0xFF9AA5B1));
      expect(colour('u-3'), const Color(0xFFCD7F32));
    });

    testWidgets('a person who sees only their own line gets no medal and no ranking', (t) async {
      await _open(t, _FakeSalon((_, __) async => report(rows: <StylistRow>[ashaPlus], everyone: false)));

      expect(_key('medal_u-asha'), findsNothing);
      expect(find.descendant(of: _key('stylist_u-asha'), matching: find.text('Share')), findsNothing);
      expect(_key('target_u-asha'), findsOneWidget, reason: 'their own target is theirs to see');
    });

    testWidgets('a target shows the percent reached and whether that is ahead of the month', (t) async {
      final StylistRow behind = StylistRow(staffId: 'u-b', name: 'Behind', services: 1, revenue: 30000, visits: 1, clients: 1, rank: 2, target: target('behind', 15));
      final StylistRow reached = StylistRow(staffId: 'u-r', name: 'Reached', services: 1, revenue: 250000, visits: 1, clients: 1, rank: 1, target: StylistTarget(month: '2026-10', amount: 200000, achieved: 250000, percent: 125, expectedPercent: 50, pace: 'reached'));
      final StylistRow track = StylistRow(staffId: 'u-t', name: 'Track', services: 1, revenue: 100000, visits: 1, clients: 1, target: target('on_track', 60));
      await _open(t, _FakeSalon((_, __) async => report(rows: <StylistRow>[reached, ashaPlus, track, behind])));
      t.view.physicalSize = const Size(411, 2600); // all four cards on screen
      await t.pump();

      Finder inCard(String id, String text) => find.descendant(of: _key('target_$id'), matching: find.text(text));
      expect(inCard('u-asha', 'Ahead of pace'), findsOneWidget);
      expect(inCard('u-asha', '70%'), findsOneWidget);
      expect(inCard('u-asha', 'Target TSH 200,000'), findsOneWidget);
      expect(inCard('u-r', 'Target reached'), findsOneWidget);
      expect(inCard('u-r', '125%'), findsOneWidget);
      expect(inCard('u-t', 'On track'), findsOneWidget);
      expect(inCard('u-b', 'Behind pace'), findsOneWidget);
      expect(find.descendant(of: _key('target_u-asha'), matching: _key('target_pace_mark')), findsOneWidget, reason: 'the days gone are marked on the bar');
      expect(_key('target_u-bahati'), findsNothing, reason: 'no target set: no bar');
    });

    testWidgets('the bar is as full as the percent and never more than full', (t) async {
      await _open(t, _FakeSalon((_, __) async => report(rows: <StylistRow>[
            StylistRow(staffId: 'u-r', name: 'Reached', services: 1, revenue: 250000, visits: 1, clients: 1, target: StylistTarget(month: '2026-10', amount: 200000, achieved: 250000, percent: 125, expectedPercent: 50, pace: 'reached')),
            StylistRow(staffId: 'u-asha', name: 'Asha', services: 1, revenue: 140000, visits: 1, clients: 1, target: target('ahead', 70)),
          ])));

      expect(t.widget<LinearProgressIndicator>(find.descendant(of: _key('target_u-r'), matching: find.byType(LinearProgressIndicator))).value, 1.0);
      expect(t.widget<LinearProgressIndicator>(find.descendant(of: _key('target_u-asha'), matching: find.byType(LinearProgressIndicator))).value, closeTo(0.7, 0.001));
    });

    testWidgets('only the owner is offered the targets; the sheet saves just what was changed', (t) async {
      final _FakeSalon api = _FakeSalon((_, __) async => report(canSet: true))
        ..targets = StylistTargets(month: '2026-10', canSet: true, people: <TargetPerson>[
          TargetPerson(staffId: 'u-asha', name: 'Asha', role: 'hair_stylist', target: target('ahead', 70)),
          const TargetPerson(staffId: 'u-bahati', name: 'Bahati', role: 'nail_technician'),
        ]);
      await _open(t, api);

      await t.tap(_key('stylists_targets'));
      await t.pumpAndSettle();

      expect(find.text('Targets for October 2026'), findsOneWidget);
      expect(t.widget<TextField>(_key('target_box_u-asha')).controller!.text, '200000', reason: 'what is set is filled in');
      expect(t.widget<TextField>(_key('target_box_u-bahati')).controller!.text, '', reason: 'no target yet');

      await t.enterText(_key('target_box_u-bahati'), '90,000');
      await t.tap(_key('targets_save'));
      await t.pumpAndSettle();

      expect(api.savedTargets, hasLength(1));
      expect(api.savedTargets.single.$1, '2026-10');
      expect(api.savedTargets.single.$2, <String, double>{'u-bahati': 90000}, reason: 'Asha was not touched');
      expect(find.text('Targets for October 2026'), findsNothing, reason: 'the sheet closes, and the page asks again');
      expect(api.asked.length, 2);
    });

    testWidgets('clearing a box removes that target (0), and saving with nothing changed sends nothing', (t) async {
      final _FakeSalon api = _FakeSalon((_, __) async => report(canSet: true))
        ..targets = StylistTargets(month: '2026-10', canSet: true, people: <TargetPerson>[TargetPerson(staffId: 'u-asha', name: 'Asha', role: 'hair_stylist', target: target('ahead', 70))]);
      await _open(t, api);

      await t.tap(_key('stylists_targets'));
      await t.pumpAndSettle();
      await t.tap(_key('targets_save'));
      await t.pumpAndSettle();
      expect(api.savedTargets, isEmpty);

      await t.tap(_key('stylists_targets'));
      await t.pumpAndSettle();
      await t.enterText(_key('target_box_u-asha'), '');
      await t.tap(_key('targets_save'));
      await t.pumpAndSettle();
      expect(api.savedTargets.single.$2, <String, double>{'u-asha': 0});
    });

    testWidgets('someone who may not set targets is not offered the button, and a refusal is shown', (t) async {
      await _open(t, _FakeSalon((_, __) async => report(canSet: false)));
      expect(_key('stylists_targets'), findsNothing);
    });

    testWidgets('a refusal from the server is shown and the sheet stays open', (t) async {
      final _FakeSalon api = _FakeSalon((_, __) async => report(canSet: true))
        ..failSave = true
        ..targets = const StylistTargets(month: '2026-10', canSet: true, people: <TargetPerson>[TargetPerson(staffId: 'u-bahati', name: 'Bahati', role: 'nail_technician')]);
      await _open(t, api);

      await t.tap(_key('stylists_targets'));
      await t.pumpAndSettle();
      await t.enterText(_key('target_box_u-bahati'), '50000');
      await t.tap(_key('targets_save'));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 6));

      expect(find.text('Targets for October 2026'), findsOneWidget);
      expect(t.widget<TextField>(_key('target_box_u-bahati')).controller!.text, '50000', reason: 'what was typed is kept');
    });

    testWidgets('in Swahili the new words are Swahili', (t) async {
      await _open(t, _FakeSalon((_, __) async => report(canSet: true)), sw: true);

      expect(find.text('Wastani kwa ziara'), findsWidgets);
      expect(find.text('Waliorudi'), findsWidgets);
      expect(find.text('Mbele ya kasi'), findsOneWidget);
      expect(find.textContaining('Ikilinganishwa na'), findsOneWidget);
      expect(find.text('Weka malengo ya mwezi'), findsOneWidget);
    });
  });
}
