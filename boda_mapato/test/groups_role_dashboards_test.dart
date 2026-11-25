import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_records_models.dart';
import 'package:boda_mapato/modules/groups/models/group_voting_models.dart';
import 'package:boda_mapato/modules/groups/screens/group_dashboard_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/glow_list_card.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends GroupsApi {
  @override
  Future<List<GroupTransaction>> myTransactions() async => const <GroupTransaction>[];

  @override
  Future<(List<GroupNotice>, int)> notifications() async => (<GroupNotice>[], 0);

  @override
  Future<GroupDashboardData> dashboard({final String? month}) async => GroupDashboardData.fromJson(<String, dynamic>{
        'month': month,
        'members': <String, dynamic>{'active': 24, 'applications': 3, 'suspended': 1, 'joined_in_month': 2},
        'money': null,
      });
}

GroupMe _leader() => GroupMe.fromJson(<String, dynamic>{
      'rights': <String>['view_members', 'view_finance', 'record_payments', 'verify_payments', 'view_loans'],
      'member': <String, dynamic>{'id': 1, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active', 'office': 'mweka_hazina', 'member_number': 'MEG-0001'},
      'group': <String, dynamic>{'name': 'MEG'},
      'balances': <String, double>{'savings': 100000, 'shares': 200000},
      'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000},
      'waiting': <String, int>{'payments_to_verify': 3, 'applications': 2, 'votes_to_cast': 1},
    });

GroupMe _plain() => GroupMe.fromJson(<String, dynamic>{
      'rights': <String>[],
      'member': <String, dynamic>{'id': 2, 'full_name': 'Juma Ali', 'phone': '0713000002', 'status': 'active', 'member_number': 'MEG-0002'},
      'group': <String, dynamic>{'name': 'MEG'},
      'balances': <String, double>{'savings': 50000, 'shares': 100000},
      'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000},
      'waiting': <String, int>{'votes_to_cast': 1},
    });

Future<void> _pump(final WidgetTester t, final GroupMe me, final double width) async {
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
        builder: (_, __) => MaterialApp(home: Scaffold(body: GroupDashboardScreen(me: me, api: _Api(), onChanged: () async {}, onOpen: (_) {}))),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void _expectMemberDashboard(final String who) {
  expect(find.byType(GlowSections), findsOneWidget, reason: '$who: ONE joined card');
  for (final String k in <String>['grp_my_account', 'grp_my_glance', 'grp_pay_open', 'grp_my_money', 'grp_my_loans', 'grp_waiting_open']) {
    expect(find.byKey(Key(k)), findsOneWidget, reason: '$who has $k');
  }
  // The thin dividing lines between the rows of tiles (the same design as the shop's dashboard).
  for (final String k in <String>['grp_menu_div_1', 'grp_menu_div_2', 'grp_my_glance_div_1']) {
    expect(find.byKey(ValueKey<String>(k)), findsOneWidget, reason: '$who has the divider $k');
  }
  for (final String k in <String>['grp_overview', 'grp_overview_joined', 'grp_overview_chart', 'grp_desk_loan_review', 'grp_wait_payments', 'grp_wait_applications']) {
    expect(find.byKey(Key(k)), findsNothing, reason: '$who must not see $k');
  }
}

void main() {
  for (final double width in <double>[411, 360]) {
    testWidgets('a plain member at $width px: the clean joined dashboard with dividers, only their own account, nothing of the leaders', (final WidgetTester t) async {
      await _pump(t, _plain(), width);
      _expectMemberDashboard('member');
      expect(find.text('Juma Ali'), findsOneWidget);
      expect(tester(t), isNull, reason: 'no layout exception');
    });

    testWidgets('a leader in ME at $width px has the same dashboard as that member, with their own account and no office parts', (final WidgetTester t) async {
      await _pump(t, _leader().asMember(), width);
      _expectMemberDashboard('leader in ME');
      expect(find.byKey(const Key('grp_my_account_number')), findsOneWidget);
      expect(find.textContaining('mweka_hazina'), findsNothing);
      expect(find.textContaining('Treasurer'), findsNothing);
      // Only the member's own wait (votes) is behind the button: not the leaders' payments to verify or applications.
      await t.tap(find.byKey(const Key('grp_waiting_open')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('grp_wait_votes')), findsOneWidget);
      expect(find.byKey(const Key('grp_wait_payments')), findsNothing);
      expect(find.byKey(const Key('grp_wait_applications')), findsNothing);
    });

    testWidgets('the same leader outside ME at $width px has the leaders\' dashboard too, over the same member parts', (final WidgetTester t) async {
      await _pump(t, _leader(), width);
      expect(find.byKey(const Key('grp_overview')), findsOneWidget, reason: 'the leaders dashboard');
      expect(find.byKey(const Key('grp_my_account')), findsOneWidget);
      expect(find.byKey(const Key('grp_my_glance')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('grp_menu_div_1')), findsOneWidget);
    });
  }
}

Object? tester(final WidgetTester t) => t.takeException();
