import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_records_models.dart';
import 'package:boda_mapato/modules/groups/screens/group_dashboard_screen.dart';
import 'package:boda_mapato/modules/groups/screens/group_overview_dashboard.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends GroupsApi {
  _FakeApi({this.withMoney = true, this.desk});

  final bool withMoney;
  final Map<String, dynamic>? desk;

  @override
  Future<List<GroupTransaction>> myTransactions() async => const <GroupTransaction>[];

  @override
  Future<GroupDashboardData> dashboard({final String? month}) async => GroupDashboardData.fromJson(<String, dynamic>{
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
    final double waiting = _top(t, find.text('Waiting for you'));
    final double actions = _top(t, find.byKey(const Key('grp_qa_payment')));
    final double headline = _top(t, find.byKey(const Key('grp_overview_joined')));
    final double chart = _top(t, find.byKey(const Key('grp_overview_chart')));
    final double mine = _top(t, find.text('My payments'));
    expect(<double>[actions, headline, who, waiting, chart, mine], orderedEquals(<double>[actions, headline, who, waiting, chart, mine]..sort()), reason: 'actions, headline, who I am, waiting, then the trend, then my money');
    expect(find.byKey(const Key('grp_wait_payments')), findsOneWidget);
    expect(find.byKey(const Key('grp_wait_applications')), findsOneWidget);
    expect(find.byKey(const Key('grp_overview_chart')), findsOneWidget);
  });

  testWidgets('a count of zero is not shown, and when nothing waits the card says so', (final WidgetTester t) async {
    await _pump(t, _me(rights, <String, int>{'payments_to_verify': 0, 'loans_to_recommend': 0}));

    expect(find.byKey(const Key('grp_wait_payments')), findsNothing);
    expect(find.text('Nothing is waiting for you. You are all caught up.'), findsOneWidget);
  });

  testWidgets('more than five things waiting: five first, the rest after Show all', (final WidgetTester t) async {
    await _pump(t, _me(rights, <String, int>{'payments_to_verify': 3, 'applications': 2, 'members_overdue': 4, 'hires_to_decide': 1, 'dividends_to_approve': 1, 'meetings_to_record': 1, 'expenses_to_approve': 2}));

    expect(find.byKey(const Key('grp_wait_more')), findsOneWidget);
    expect(find.byKey(const Key('grp_wait_applications')), findsNothing, reason: 'the last line waits for Show all');
    await t.ensureVisible(find.byKey(const Key('grp_wait_more')));
    await t.tap(find.byKey(const Key('grp_wait_more')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_wait_applications')), findsOneWidget);
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
    expect(find.byKey(const Key('grp_qa_projects')), findsOneWidget);
    expect(find.byKey(const Key('grp_qa_expenses')), findsOneWidget);
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
    expect(find.byKey(const Key('grp_my_account')), findsOneWidget);
    expect(find.text('My account · MEG-0001'), findsOneWidget);
    expect(find.text('TSH 300,000'), findsOneWidget, reason: 'savings and shares held for them');
    expect(find.byKey(const Key('grp_my_savings')), findsOneWidget);
    expect(find.byKey(const Key('grp_my_shares')), findsOneWidget);
    expect(find.byKey(const Key('grp_my_owed')), findsOneWidget);
    expect(find.byKey(const Key('grp_my_pending')), findsOneWidget);
    expect(find.byKey(const Key('grp_overview')), findsNothing, reason: 'no officers figures for a member');
    expect(find.text('100K'), findsOneWidget, reason: 'their savings');
  });
}
