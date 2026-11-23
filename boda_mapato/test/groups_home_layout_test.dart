import 'dart:async';

import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_records_models.dart';
import 'package:boda_mapato/modules/groups/screens/group_dashboard_screen.dart';
import 'package:boda_mapato/modules/groups/screens/group_overview_dashboard.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/glow_list_card.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends GroupsApi {
  _FakeApi({this.withMoney = true, this.desk, this.failing = false});

  final bool withMoney;
  final Map<String, dynamic>? desk;

  /// The group's figures cannot be loaded.
  final bool failing;

  @override
  Future<List<GroupTransaction>> myTransactions() async => const <GroupTransaction>[];

  @override
  Future<GroupDashboardData> dashboard({final String? month}) async {
    if (failing) throw Exception('offline');
    return _dashboard(month);
  }

  GroupDashboardData _dashboard(final String? month) => GroupDashboardData.fromJson(<String, dynamic>{
        'month': month,
        'members': <String, dynamic>{'active': 24, 'applications': 3, 'suspended': 1, 'joined_in_month': 2},
        'desk': desk,
        'money': !withMoney ? null : <String, dynamic>{
          'cash_on_record': 1250000,
          'month_in': 400000,
          'month_out': 90000,
          'savings': 800000,
          'shares': 240000,
          'contributions': <String, dynamic>{'expected': 200000, 'collected': 150000, 'overdue_amount': 30000, 'overdue_members': 3},
          'loans': <String, dynamic>{'principal': 500000, 'interest': 50000, 'arrears': 20000, 'running': 4, 'overdue': 1},
          'pending_count': 2,
          'year': <String, dynamic>{'welfare_paid': 60000, 'dividends': 0, 'hire_income': 45000, 'expenses': 90000},
          'trend': <dynamic>[
            for (int i = 1; i <= 12; i++) <String, dynamic>{'month': '2026-${i.toString().padLeft(2, '0')}', 'in': i * 10000, 'out': i * 2000},
          ],
          'mix': <dynamic>[],
        },
      });
}

GroupMe _me(final List<String> rights, final Map<String, int> waiting) => GroupMe.fromJson(<String, dynamic>{
      'rights': rights,
      'member': <String, dynamic>{'id': 1, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active', 'office': 'mweka_hazina', 'member_number': 'MEG-0001'},
      'group': <String, dynamic>{'name': 'MEG'},
      'balances': <String, double>{'joining_fee': 80000, 'shares': 200000, 'savings': 100000, 'contribution': 0},
      'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000},
      'waiting': waiting,
    });

Future<void> _pump(final WidgetTester t, final GroupMe me, {final double width = 411, final _FakeApi? api}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = Size(width, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(411, 3000),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: Scaffold(body: GroupDashboardScreen(me: me, api: api ?? _FakeApi(), onChanged: () async {}, onOpen: (_) {}))),
      ),
    ),
  );
  await t.pumpAndSettle();
}

double _top(final WidgetTester t, final Finder f) => t.getTopLeft(f).dy;

void main() {
  const List<String> rights = <String>['view_members', 'view_finance', 'record_payments', 'verify_payments', 'view_loans'];

  testWidgets('the figures of the group come first, then who the person is and what waits, then the trend, then their own money', (final WidgetTester t) async {
    await _pump(t, _me(rights, <String, int>{'payments_to_verify': 3, 'loans_to_recommend': 0, 'applications': 2}));

    final double who = _top(t, find.byKey(const Key('grp_me_name')));
    final double waiting = _top(t, find.byKey(const Key('grp_waiting_open')));
    final double account = _top(t, find.byKey(const Key('grp_my_account')));
    expect(find.byKey(const Key('grp_qa_payment')), findsNothing, reason: 'the shortcut buttons are gone');
    final double headline = _top(t, find.byKey(const Key('grp_overview_joined')));
    final double chart = _top(t, find.byKey(const Key('grp_overview_chart')));
    expect(<double>[account, headline, who, waiting, chart], orderedEquals(<double>[account, headline, who, waiting, chart]..sort()), reason: 'the account, headline, who I am, the buttons (waiting first), then the trend');
    // What waits is not listed on Home any more: a button with the count leads to it.
    expect(find.byKey(const Key('grp_wait_payments')), findsNothing);
    expect(find.text('5'), findsWidgets, reason: 'the total on the button: 3 payments and 2 applications');
    await t.ensureVisible(find.byKey(const Key('grp_waiting_open')));
    await t.tap(find.byKey(const Key('grp_waiting_open')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_wait_payments')), findsOneWidget);
    expect(find.byKey(const Key('grp_wait_applications')), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byType(GlowSections), findsOneWidget, reason: 'who I am, the buttons, the trend and the news are ONE joined card');
    // Every part of the dashboard, the top ones too, is a titled part of that one card.
    for (final String title in <String>['Account', 'The group at a glance', 'Members and money']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(find.byKey(const Key('grp_overview_chart')), findsOneWidget);
  });

  testWidgets('every member has the account at the top, whatever the office: treasurer, secretary, chair, and a member with none', (final WidgetTester t) async {
    for (final (String office, List<String> r) in <(String, List<String>)>[
      ('mweka_hazina', rights),
      ('katibu', <String>['view_members']),
      ('mwenyekiti', <String>['view_members', 'view_finance', 'manage_payment_methods']),
      ('', <String>[]),
    ]) {
      final GroupMe me = GroupMe.fromJson(<String, dynamic>{
        'rights': r,
        'member': <String, dynamic>{'id': 1, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active', 'office': office.isEmpty ? null : office, 'member_number': 'MEG-0001'},
        'group': <String, dynamic>{'name': 'MEG'},
        'balances': <String, double>{'joining_fee': 80000, 'shares': 200000, 'savings': 100000, 'contribution': 0},
        'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000},
        'waiting': <String, int>{},
      });
      await _pump(t, me);
      expect(find.byKey(const Key('grp_my_account')), findsOneWidget, reason: 'office: $office');
      expect(find.text('No. MEG-0001'), findsOneWidget, reason: 'office: $office');
      expect(find.text('TSh ••••••'), findsOneWidget, reason: 'office: $office');
      expect(find.byKey(const Key('grp_my_account_none')), findsNothing);
      // It is the first part on the screen.
      expect(_top(t, find.byKey(const Key('grp_my_account'))), lessThan(_top(t, find.byKey(const Key('grp_my_glance')))), reason: 'office: $office');
    }
  });

  testWidgets('someone who runs the group without being registered as a member is told there is no account for them, instead of an empty place', (final WidgetTester t) async {
    final GroupMe me = GroupMe.fromJson(<String, dynamic>{'rights': rights, 'group': <String, dynamic>{'name': 'MEG'}, 'waiting': <String, int>{}});
    await _pump(t, me);
    expect(find.byKey(const Key('grp_my_account_none')), findsOneWidget);
    expect(find.byKey(const Key('grp_my_account')), findsNothing);
  });

  testWidgets('when the group figures cannot be loaded the account still comes first', (final WidgetTester t) async {
    await _pump(t, _me(rights, <String, int>{}), api: _FakeApi(failing: true));
    expect(find.byKey(const Key('grp_my_account')), findsOneWidget);
    expect(find.text('No. MEG-0001'), findsOneWidget);
    expect(find.byKey(const Key('grp_my_glance')), findsOneWidget);
  });

  testWidgets('a count of zero is not shown, and when nothing waits the screen says so', (final WidgetTester t) async {
    await _pump(t, _me(rights, <String, int>{'payments_to_verify': 0, 'loans_to_recommend': 0}));

    await t.ensureVisible(find.byKey(const Key('grp_waiting_open')));
    await t.tap(find.byKey(const Key('grp_waiting_open')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_wait_payments')), findsNothing);
    expect(find.text('Nothing is waiting for you. You are all caught up.'), findsOneWidget);
  });

  testWidgets('many things waiting: one button on Home carrying the total, and every line on its own screen', (final WidgetTester t) async {
    await _pump(t, _me(rights, <String, int>{'payments_to_verify': 3, 'applications': 2, 'members_overdue': 4, 'hires_to_decide': 1, 'dividends_to_approve': 1, 'meetings_to_record': 1, 'expenses_to_approve': 2}));

    expect(find.text('14'), findsWidgets, reason: 'the total on the button');
    expect(find.byKey(const Key('grp_wait_applications')), findsNothing, reason: 'nothing is listed on Home');
    await t.ensureVisible(find.byKey(const Key('grp_waiting_open')));
    await t.tap(find.byKey(const Key('grp_waiting_open')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_wait_applications')), findsOneWidget);
    expect(find.byKey(const Key('grp_wait_overdue')), findsOneWidget);
    expect(find.byKey(const Key('grp_wait_more')), findsNothing, reason: 'no Show all: the screen has room for all of them');
  });

  testWidgets('a narrow phone shows the same layout without anything overflowing', (final WidgetTester t) async {
    await _pump(t, _me(rights, <String, int>{'payments_to_verify': 3}), width: 320);

    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('grp_overview_joined')), findsOneWidget);
    expect(find.byType(GroupOverviewDashboard), findsOneWidget);
  });

  testWidgets('the projects office sees the projects and the loan pipeline without any money', (final WidgetTester t) async {
    await _pump(
      t,
      _me(<String>['view_members', 'view_loans', 'recommend_loans', 'view_projects', 'recommend_projects', 'request_expenses'], <String, int>{}),
      api: _FakeApi(withMoney: false, desk: <String, dynamic>{
        'projects': <String, dynamic>{'proposed': 2, 'active': 1, 'completed': 3, 'budget': 5000000, 'spent': 1200000, 'committed': 300000},
        'loans': <String, dynamic>{'under_review': 4, 'recommended': 1, 'approved': 0, 'active': 6},
      }),
    );

    expect(find.byKey(const Key('grp_desk_proposed')), findsOneWidget);
    expect(find.byKey(const Key('grp_desk_spent')), findsOneWidget);
    expect(find.byKey(const Key('grp_desk_loan_review')), findsOneWidget);
    expect(find.byKey(const Key('grp_overview_joined')), findsNothing, reason: 'no money for this office');
    expect(find.byKey(const Key('grp_desk_to_record')), findsNothing, reason: 'meetings are not theirs');
    expect(find.byKey(const Key('grp_qa_projects')), findsNothing);
    expect(find.byKey(const Key('grp_qa_expenses')), findsNothing);
  });

  testWidgets('the secretary sees the meetings and records, not the money', (final WidgetTester t) async {
    await _pump(
      t,
      _me(<String>['view_members', 'manage_members', 'record_meetings', 'post_announcements'], <String, int>{}),
      api: _FakeApi(withMoney: false, desk: <String, dynamic>{
        'meetings': <String, dynamic>{'to_record': 1, 'minutes_open': 2, 'open_actions': 5, 'overdue_actions': 1},
      }),
    );

    expect(find.byKey(const Key('grp_desk_to_record')), findsOneWidget);
    expect(find.byKey(const Key('grp_desk_late')), findsOneWidget);
    expect(find.byKey(const Key('grp_desk_proposed')), findsNothing);
    expect(find.byKey(const Key('grp_overview_joined')), findsNothing);
  });

  testWidgets('an ordinary member has a dashboard of their own: savings, shares, what is owed, what waits', (final WidgetTester t) async {
    await _pump(t, _me(<String>[], <String, int>{}));

    expect(find.byKey(const Key('grp_my_glance')), findsOneWidget);
    expect(find.byType(GlowSections), findsOneWidget, reason: 'an ordinary member has ONE joined card too');
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('My standing'), findsOneWidget);
    expect(find.byKey(const Key('grp_my_account')), findsOneWidget);
    expect(find.byKey(const Key('grp_my_account_number')), findsOneWidget);
    expect(find.text('No. MEG-0001'), findsOneWidget, reason: 'the account number sits beside the amount');
    expect(find.text('TSh ••••••'), findsOneWidget, reason: 'the balance is hidden until the eye is tapped');
    expect(find.text('TSH 300,000'), findsNothing);
    await t.tap(find.byKey(const Key('grp_my_account_eye')));
    await t.pump();
    expect(find.text('TSH 300,000'), findsOneWidget, reason: 'savings and shares held for them');
    await t.tap(find.byKey(const Key('grp_my_account_eye')));
    await t.pump();
    expect(find.text('TSH 300,000'), findsNothing, reason: 'hidden again on the next tap');
    expect(find.text('TSh ••••••'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_my_account_eye')));
    await t.pump();
    expect(find.byKey(const Key('grp_my_savings')), findsOneWidget);
    expect(find.byKey(const Key('grp_my_shares')), findsOneWidget);
    expect(find.byKey(const Key('grp_my_owed')), findsOneWidget);
    expect(find.byKey(const Key('grp_my_pending')), findsOneWidget);
    expect(find.byKey(const Key('grp_overview')), findsNothing, reason: 'no officers figures for a member');
    expect(find.text('100K'), findsOneWidget, reason: 'their savings');
  });

  testWidgets('while the officers figures load there is only a spinner: the page appears once, in its final order', (final WidgetTester t) async {
    final Completer<void> gate = Completer<void>();
    final _FakeApi api = _SlowApi(gate.future);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage('en');
    t.view.physicalSize = const Size(411, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<LocalizationService>.value(
        value: LocalizationService.instance,
        child: ScreenUtilInit(
          designSize: const Size(411, 3000),
          minTextAdapt: true,
          builder: (_, __) => MaterialApp(home: Scaffold(body: GroupDashboardScreen(me: _me(rights, <String, int>{'payments_to_verify': 1}), api: api, onChanged: () async {}, onOpen: (_) {}))),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('grp_me_name')), findsNothing, reason: 'no personal cards before the figures');
    expect(find.text('Waiting for you'), findsNothing);

    gate.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_me_name')), findsOneWidget);
    expect(find.byKey(const Key('grp_overview_joined')), findsOneWidget);
  });
}

class _SlowApi extends _FakeApi {
  _SlowApi(this._gate);

  final Future<void> _gate;

  @override
  Future<GroupDashboardData> dashboard({final String? month}) async {
    await _gate;

    return super.dashboard(month: month);
  }
}
