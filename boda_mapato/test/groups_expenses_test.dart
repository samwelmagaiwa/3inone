import 'package:boda_mapato/modules/groups/models/group_expense_models.dart';
import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_project_models.dart';
import 'package:boda_mapato/modules/groups/screens/expenses_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _expense(final int id, {final String state = 'requested', final bool mine = false, final double amount = 100000}) => <String, dynamic>{
      'id': id,
      'reference': 'MT-00000$id',
      'purpose': 'Cement for the hall',
      'category': 'office',
      'payee': 'Hardware Ltd',
      'amount': amount,
      'amount_approved': state == 'requested' ? null : amount,
      'state': state,
      'mine': mine,
      'requested_by_name': 'Neema Mussa',
      'created_at': '2026-11-22 10:00:00',
    };

Map<String, dynamic> _me({required final List<String> rights, final Map<String, int> waiting = const <String, int>{}}) => <String, dynamic>{
      'is_owner': false,
      'rights': rights,
      'member': <String, dynamic>{'id': 1, 'full_name': 'Neema Mussa', 'phone': '0712000001', 'status': 'active', 'member_number': 'MEG-0001'},
      'balances': <String, double>{'joining_fee': 80000, 'shares': 200000, 'savings': 100000, 'contribution': 0},
      'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000},
      'waiting': waiting,
    };

class _FakeApi extends GroupsApi {
  _FakeApi(this.rows);

  final List<Map<String, dynamic>> rows;
  final List<String> calls = <String>[];

  @override
  Future<List<GroupExpense>> expenses({final String? status}) async => <GroupExpense>[
        for (final Map<String, dynamic> r in rows)
          if (status == null || r['state'] == status) GroupExpense.fromJson(r),
      ];

  @override
  Future<List<GroupProject>> projects({final String? status}) async => const <GroupProject>[];

  @override
  Future<void> requestExpense(final Map<String, dynamic> body) async => calls.add('ask:${body['payee']}:${body['amount']}:${body['category']}');

  @override
  Future<void> decideExpense(final int id, {required final bool approve, final double? amount, final String? note}) async => calls.add('decide:$id:$approve:$amount');

  @override
  Future<void> payExpense(final int id, {required final String method, final String? reference}) async => calls.add('pay:$id:$method');

  @override
  Future<void> cancelExpense(final int id) async => calls.add('cancel:$id');
}

Future<void> _pump(final WidgetTester t, final _FakeApi api, final GroupMe me) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 1400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: Scaffold(body: ExpensesScreen(me: me, api: api, onChanged: () async {})))),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the treasurer approves another person\'s request after a Yes, and pays an approved one', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(<Map<String, dynamic>>[_expense(1), _expense(2, state: 'approved')]);
    await _pump(t, api, GroupMe.fromJson(_me(rights: <String>['view_expenses', 'approve_expenses', 'record_payouts'], waiting: <String, int>{'expenses_to_approve': 1})));

    expect(find.byKey(const Key('grp_expense_1')), findsOneWidget);
    expect(find.byKey(const Key('grp_expense_2')), findsNothing, reason: 'it opens on what waits for a decision');
    await t.tap(find.byKey(const Key('grp_expense_1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_act_approve')), findsOneWidget);
    expect(find.byKey(const Key('grp_act_pay')), findsNothing);
    await t.tap(find.byKey(const Key('grp_act_approve')));
    await t.pumpAndSettle();
    await t.tap(find.byType(TextButton).last); // the amount card: its confirm button
    await t.pumpAndSettle();
    expect(api.calls, isEmpty, reason: 'nothing is sent before the Yes');
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['decide:1:true:100000.0']);
    await t.pump(const Duration(seconds: 6));

    await t.ensureVisible(find.byKey(const Key('grp_expense_filter_approved')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_expense_filter_approved')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_expense_2')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_act_pay')), findsOneWidget);
    expect(find.byKey(const Key('grp_act_approve')), findsNothing);
  });

  testWidgets('nobody decides or pays their own request; they may only withdraw it', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(<Map<String, dynamic>>[_expense(1, mine: true), _expense(2, state: 'approved', mine: true)]);
    await _pump(t, api, GroupMe.fromJson(_me(rights: <String>['view_expenses', 'approve_expenses', 'record_payouts', 'request_expenses'])));

    await t.tap(find.byKey(const Key('grp_expense_1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_act_approve')), findsNothing);
    expect(find.byKey(const Key('grp_act_reject')), findsNothing);
    expect(find.byKey(const Key('grp_act_cancel')), findsOneWidget);
    await t.tapAt(const Offset(10, 10)); // close the sheet
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_expense_2')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_act_pay')), findsNothing);
  });

  testWidgets('an official asks for money to be spent, after a Yes; an ordinary member has no button for it', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(<Map<String, dynamic>>[]);
    await _pump(t, api, GroupMe.fromJson(_me(rights: <String>['request_expenses'])));

    await t.tap(find.byKey(const Key('grp_expense_ask')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_expense_purpose')), 'Chairs for the meeting');
    await t.enterText(find.byKey(const Key('grp_expense_payee')), 'Rental Co');
    await t.enterText(find.byKey(const Key('grp_expense_amount')), '45000');
    await t.tap(find.byKey(const Key('grp_expense_send')));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['ask:Rental Co:45000.0:office']);
    await t.pump(const Duration(seconds: 6));

    await _pump(t, api, GroupMe.fromJson(_me(rights: <String>[])));
    expect(find.byKey(const Key('grp_expense_ask')), findsNothing);
  });
}
