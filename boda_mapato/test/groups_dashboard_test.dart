import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_records_models.dart';
import 'package:boda_mapato/modules/groups/screens/group_overview_dashboard.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends GroupsApi {
  _FakeApi({required this.withMoney});

  final bool withMoney;
  final List<String?> months = <String?>[];

  @override
  Future<GroupDashboardData> dashboard({final String? month}) async {
    months.add(month);
    return GroupDashboardData.fromJson(<String, dynamic>{
      'month': month,
      'members': <String, dynamic>{'active': 24, 'applications': 3, 'suspended': 1, 'joined_in_month': 2},
      'next_meeting': null,
      'money': !withMoney
          ? null
          : <String, dynamic>{
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
              'mix': <dynamic>[
                <String, dynamic>{'category': 'savings', 'in': 300000, 'out': 0},
                <String, dynamic>{'category': 'expense', 'in': 0, 'out': 90000},
              ],
            },
    });
  }
}

GroupMe _me(final List<String> rights) => GroupMe.fromJson(<String, dynamic>{
      'rights': rights,
      'member': <String, dynamic>{'id': 1, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active'},
      'group': <String, dynamic>{'name': 'MEG'},
    });

Future<List<String>> _pump(final WidgetTester t, final GroupsApi api, final GroupMe me) async {
  final List<String> opened = <String>[];
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 2200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(411, 2200),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: GroupOverviewDashboard(api: api, me: me, onOpen: opened.add)))),
      ),
    ),
  );
  await t.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('the treasurer sees the cash, the collection ring, the tiles and the chart, and each leads to its section', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(withMoney: true);
    final List<String> opened = await _pump(t, api, _me(<String>['view_members', 'view_finance', 'record_payments', 'view_loans']));

    expect(find.text('TSH 1,250,000'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget, reason: '150,000 of 200,000');
    expect(find.text('24'), findsOneWidget);
    expect(find.text('800K'), findsOneWidget);
    expect(find.text('550K'), findsOneWidget, reason: 'principal and interest still owed');
    expect(find.text('50K'), findsOneWidget, reason: 'overdue contributions and loan arrears');
    expect(find.text('2 waiting'), findsOneWidget);
    expect(find.byKey(const Key('grp_overview_chart')), findsOneWidget);

    // The bars show the month by kind; the line comes back.
    await t.tap(find.byKey(const ValueKey<String>('grp_chart_bars')));
    await t.pumpAndSettle();
    expect(find.text('Savings'), findsWidgets);
    await t.tap(find.byKey(const ValueKey<String>('grp_chart_line')));
    await t.pumpAndSettle();

    // The row of shortcut buttons is gone: the account takes its place (see the layout test).
    for (final String k in <String>['payment', 'loans', 'member', 'contribution', 'meeting', 'voting', 'projects', 'expenses']) {
      expect(find.byKey(Key('grp_qa_$k')), findsNothing, reason: k);
    }

    await t.tap(find.byKey(const Key('grp_overview_ring')));
    await t.tap(find.byKey(const Key('grp_overview_loans')));
    expect(opened, <String>['contributions', 'loans']);
    expect(api.months.single, matches(RegExp(r'^\d{4}-\d{2}$')));
  });

  testWidgets('the secretary sees the membership, never the money', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(withMoney: false);
    await _pump(t, api, _me(<String>['view_members', 'manage_members']));

    expect(find.text('24'), findsOneWidget);
    expect(find.text('Joined this month'), findsOneWidget);
    expect(find.byKey(const Key('grp_overview_balance')), findsNothing);
    expect(find.byKey(const Key('grp_overview_ring')), findsNothing);
    expect(find.byKey(const Key('grp_overview_chart')), findsNothing);
    expect(find.byKey(const Key('grp_qa_member')), findsNothing);
  });
}
