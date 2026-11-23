import 'package:boda_mapato/modules/groups/screens/group_more_screen.dart';
import 'package:boda_mapato/modules/groups/screens/widgets/repayment_schedule.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends GroupsApi {
  _Api(this.current);

  Map<String, dynamic> current;
  Map<String, dynamic>? saved;

  Map<String, dynamic> _reply() => <String, dynamic>{'settings': current, 'history': <dynamic>[]};

  @override
  Future<Map<String, dynamic>> settings() async => _reply();

  @override
  Future<Map<String, dynamic>> saveSettings(final Map<String, dynamic> values, {required final String reason, final String? effectiveFrom}) async {
    saved = values;
    current = <String, dynamic>{...current, ...values};
    return _reply();
  }
}

Future<void> _pump(final WidgetTester t, final Widget home, {final double width = 411, final String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(lang);
  t.view.physicalSize = Size(width, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: Size(width, 2400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: KeyedSubtree(key: UniqueKey(), child: home))),
    ),
  );
  await t.pumpAndSettle();
}

const Map<String, dynamic> _base = <String, dynamic>{
  'joining_fee': '80000', 'share_amount': '200000', 'loan_multiplier': '3', 'member_prefix': 'MEG', 'payment_instructions': '', 'shares_required_for': 'loans',
  'sms_reminders': 'off', 'sms_show_amounts': 'off', 'loan_interest_rate': '2', 'loan_interest_method': 'flat', 'loan_max_months': '12', 'loan_guarantors': '1',
  'hire_days_rule': 'both', 'loan_repayment': 'monthly', 'loan_repayment_days': '30',
};

Future<void> _openPicker(final WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('grp_rep_open')));
  await t.tap(find.byKey(const Key('grp_rep_open')));
  await t.pumpAndSettle();
}

Future<void> _choose(final WidgetTester t, final String key) async {
  await t.ensureVisible(find.byKey(Key('grp_rep_opt_$key')));
  await t.tap(find.byKey(Key('grp_rep_opt_$key')));
  await t.pumpAndSettle();
}

Future<void> _save(final WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('grp_set_save')));
  await t.tap(find.byKey(const Key('grp_set_save')));
  await t.pumpAndSettle();
  await t.enterText(find.byKey(const Key('grp_reason_field')), 'Uamuzi wa kikao cha Novemba');
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('grp_reason_yes')));
  await t.pumpAndSettle();
}

void main() {
  test('the first payment falls one period after the loan: tomorrow for a daily loan', () {
    final DateTime d = DateTime(2026, 11, 10);
    expect(repaymentFirstDue(d, 'daily', null), DateTime(2026, 11, 11));
    expect(repaymentFirstDue(d, 'weekly', null), DateTime(2026, 11, 17));
    expect(repaymentFirstDue(d, 'every_2_weeks', null), DateTime(2026, 11, 24));
    expect(repaymentFirstDue(d, 'monthly', null), DateTime(2026, 12, 10));
    expect(repaymentFirstDue(d, 'every_2_months', null), DateTime(2027, 1, 10));
    expect(repaymentFirstDue(d, 'quarterly', null), DateTime(2027, 2, 10));
    expect(repaymentFirstDue(d, 'every_6_months', null), DateTime(2027, 5, 10));
    expect(repaymentFirstDue(d, 'custom', 15), DateTime(2026, 11, 25));
    // The end of a short month is not skipped over.
    expect(repaymentFirstDue(DateTime(2026, 1, 31), 'monthly', null), DateTime(2026, 2, 28));
  });

  test('every rhythm has words in both languages', () {
    for (final String e in repaymentChoices) {
      expect(repaymentLabel(sw: false, every: e, days: 12), isNotEmpty);
      expect(repaymentLabel(sw: true, every: e, days: 12), isNotEmpty);
      expect(repaymentDetail(sw: true, every: e), isNotEmpty);
    }
    expect(repaymentLabel(sw: false, every: 'custom', days: 12), 'Every 12 days');
    expect(repaymentLabel(sw: true, every: 'quarterly'), 'Kila miezi mitatu');
  });

  testWidgets('the loan terms show the schedule as one button; it opens cards for every way of repaying, each with a worked first date', (final WidgetTester t) async {
    final _Api api = _Api(<String, dynamic>{..._base});
    await _pump(t, GroupSettingsScreen(api: api));

    expect(find.byKey(const Key('grp_rep_open')), findsOneWidget);
    expect(find.text('Every month'), findsOneWidget);
    await _openPicker(t);

    expect(find.text('How often is a loan repaid?'), findsOneWidget);
    for (final String o in repaymentChoices) {
      expect(find.byKey(Key('grp_rep_opt_$o')), findsOneWidget, reason: o);
    }
    final DateTime today = DateTime.now();
    String two(final int n) => n.toString().padLeft(2, '0');
    final DateTime tomorrow = today.add(const Duration(days: 1));
    expect(find.textContaining('first payment ${two(tomorrow.day)}/${two(tomorrow.month)}/${tomorrow.year}'), findsOneWidget, reason: 'the daily card says: first payment tomorrow');
    expect(find.textContaining('starting tomorrow after borrowing today'), findsOneWidget);
  });

  testWidgets('choosing every week updates the button and saves as a change of the group rules', (final WidgetTester t) async {
    final _Api api = _Api(<String, dynamic>{..._base});
    await _pump(t, GroupSettingsScreen(api: api));
    await _openPicker(t);
    await _choose(t, 'weekly');
    await t.tap(find.byKey(const Key('grp_rep_use')));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('grp_rep_current'))).data, 'Every week');

    await _save(t);
    expect(api.saved, <String, dynamic>{'loan_repayment': 'weekly'}, reason: 'only what changed is sent');
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('every N days asks for the number, refuses 0 and more than 365, and sends the days', (final WidgetTester t) async {
    final _Api api = _Api(<String, dynamic>{..._base});
    await _pump(t, GroupSettingsScreen(api: api));
    await _openPicker(t);
    await _choose(t, 'custom');
    expect(find.byKey(const Key('grp_rep_days')), findsOneWidget);

    await t.enterText(find.byKey(const Key('grp_rep_days')), '0');
    await t.tap(find.byKey(const Key('grp_rep_use')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_rep_problem')), findsOneWidget);
    expect(find.byKey(const Key('grp_rep_use')), findsOneWidget, reason: 'the sheet stays open');

    await t.enterText(find.byKey(const Key('grp_rep_days')), '10');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_rep_problem')), findsNothing);
    await t.tap(find.byKey(const Key('grp_rep_use')));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.byKey(const Key('grp_rep_current'))).data, 'Every 10 days');

    await _save(t);
    expect(api.saved, <String, dynamic>{'loan_repayment': 'custom', 'loan_repayment_days': '10'});
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('closing the cards without choosing changes nothing, and the page follows the language', (final WidgetTester t) async {
    final _Api api = _Api(<String, dynamic>{..._base, 'loan_repayment': 'quarterly'});
    await _pump(t, GroupSettingsScreen(api: api), lang: 'sw');
    expect(find.text('Kila miezi mitatu'), findsOneWidget);
    await _openPicker(t);
    expect(find.text('Mikopo hurejeshwa mara ngapi?'), findsOneWidget);
    await t.tapAt(const Offset(200, 40));
    await t.pumpAndSettle();
    expect(find.text('Kila miezi mitatu'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('grp_rep_current'))).data, 'Kila miezi mitatu');
  });

  testWidgets('the cards fit a narrow phone', (final WidgetTester t) async {
    final _Api api = _Api(<String, dynamic>{..._base});
    await _pump(t, GroupSettingsScreen(api: api), width: 320);
    await _openPicker(t);
    await _choose(t, 'custom');
    expect(t.takeException(), isNull);
  });
}
