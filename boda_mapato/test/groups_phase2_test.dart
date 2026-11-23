import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/groups_home.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _obligation(final int id, {final int memberId = 1, final String name = 'Neema Mussa', final String state = 'overdue', final double remaining = 10000}) =>
    <String, dynamic>{
      'id': id,
      'member_id': memberId,
      'member_name': name,
      'member_number': 'MEG-000$memberId',
      'type_name': 'JAMII',
      'period': '2026-11',
      'amount_due': 10000,
      'paid': 10000 - remaining,
      'remaining': remaining,
      'due_date': '2026-11-05',
      'state': state,
      'days_overdue': state == 'overdue' ? 5 : 0,
    };

class _FakeApi extends GroupsApi {
  _FakeApi(this.meJson);

  final Map<String, dynamic> meJson;
  final List<String> calls = <String>[];

  @override
  Future<GroupMe> me() async => GroupMe.fromJson(meJson);

  @override
  Future<List<GroupTransaction>> myTransactions() async => const <GroupTransaction>[];

  @override
  Future<GroupTransaction> payMine(final Map<String, dynamic> payment) async {
    calls.add('pay:${payment['category']}:${payment['obligation_id']}:${payment['amount']}');
    return GroupTransaction.fromJson(<String, dynamic>{'id': 1, 'category': payment['category'], 'amount': payment['amount'], 'status': 'pending'});
  }

  @override
  Future<GroupTransaction> recordPayment(final Map<String, dynamic> payment) async {
    calls.add('record:${payment['category']}:${payment['direction'] ?? 'in'}:${payment['amount']}:${payment['payee'] ?? ''}');
    return GroupTransaction.fromJson(<String, dynamic>{'id': 2, 'category': payment['category'], 'amount': payment['amount'], 'status': 'pending'});
  }

  @override
  Future<GroupPromise> makePromise(final Map<String, dynamic> body, {final int? memberId}) async {
    calls.add('promise:${memberId ?? 'me'}:${body['obligation_id']}:${body['amount']}');
    return GroupPromise.fromJson(<String, dynamic>{'id': 3, 'member_id': memberId ?? 1, 'amount': body['amount'], 'promised_on': body['promised_on'], 'state': 'due'});
  }

  @override
  Future<List<GroupContributionType>> contributionTypes() async => <GroupContributionType>[
        GroupContributionType.fromJson(<String, dynamic>{'id': 7, 'name': 'JAMII', 'amount': 10000, 'frequency': 'monthly', 'due_day': 5}),
      ];

  @override
  Future<int> raiseContribution(final int typeId, {final String? month, final String? dueDate, final String? label}) async {
    calls.add('raise:$typeId:$month');
    return 22;
  }

  @override
  Future<GroupObligationPage> obligations({final String state = 'owing', final int? typeId, final int? memberId, final String? query, final int page = 1}) async =>
      GroupObligationPage.fromJson(<String, dynamic>{
        'data': <String, dynamic>{
          'obligations': <Map<String, dynamic>>[_obligation(41, memberId: 5, name: 'Asha Juma')],
        },
      });

  @override
  Future<void> exempt(final int obligationId, final String reason) async => calls.add('exempt:$obligationId:$reason');

  @override
  Future<List<GroupPromise>> promises({final int? memberId}) async => const <GroupPromise>[];

  @override
  Future<GroupStatementData?> statement({final int? memberId, final String? from, final String? to}) async => GroupStatementData.fromJson(<String, dynamic>{
        'balances': <String, dynamic>{'joining_fee': 80000, 'shares': 200000, 'savings': 30000, 'contribution': 0},
        'owing': <dynamic>[_obligation(41, memberId: 5, name: 'Asha Juma')],
      });

  @override
  Future<GroupMemberPage> members({final String? status, final String? office, final String? query, final int page = 1}) async =>
      GroupMemberPage.fromJson(<String, dynamic>{
        'data': <String, dynamic>{
          'members': <Map<String, dynamic>>[
            <String, dynamic>{'id': 5, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active', 'member_number': 'MEG-0005'},
          ],
        },
      });

  @override
  Future<GroupTransactionPage> transactions({final String? status, final String? category, final int? memberId, final String? query, final int page = 1}) async =>
      GroupTransactionPage.fromJson(<String, dynamic>{'data': <String, dynamic>{'transactions': <dynamic>[]}});

  @override
  Future<Map<String, dynamic>> moneySummary({final String? month}) async => <String, dynamic>{
        'verified': <String, dynamic>{'joining_fee': 160000, 'shares': 0, 'savings': 30000, 'contribution': 10000, 'expense': -15000},
        'cash_on_record': 185000,
        'pending_count': 0,
        'pending_amount': 0,
        'month': '2026-11',
        'contributions': <String, dynamic>{'expected': 60000, 'collected': 10000, 'overdue_amount': 50000, 'overdue_members': 5, 'overdue_count': 5},
        'expenses_in_month': 15000,
      };
}

Map<String, dynamic> _me({final List<String> rights = const <String>[], final String? office, final List<dynamic> owing = const <dynamic>[]}) => <String, dynamic>{
      'is_owner': false,
      'rights': rights,
      'member': <String, dynamic>{'id': 1, 'full_name': 'Neema Mussa', 'phone': '0712000001', 'status': 'active', 'office': office, 'member_number': 'MEG-0001'},
      'balances': <String, double>{'joining_fee': 80000, 'shares': 200000, 'savings': 30000, 'contribution': 0},
      'pending': 0,
      'owing': owing,
      'promises': <dynamic>[],
      'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000, 'shares_required_for': 'loans', 'payment_instructions': ''},
      'waiting': <String, int>{},
    };

const List<String> _treasurer = <String>['view_members', 'view_sensitive', 'view_finance', 'record_payments', 'verify_payments', 'reverse_payments', 'manage_contributions', 'record_payouts'];
const List<String> _chair = <String>['view_members', 'manage_members', 'approve_members', 'view_finance', 'manage_offices', 'manage_settings', 'manage_contributions', 'grant_exemptions'];

Future<void> _pump(final WidgetTester t, final Widget home) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1300);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 1300), minTextAdapt: true, builder: (_, __) => MaterialApp(home: home)),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _banner(final WidgetTester t) async {
  await t.pump(const Duration(seconds: 6));
  await t.pumpAndSettle();
}

Future<void> _yes(final WidgetTester t) async {
  expect(find.byKey(const Key('grp_confirm')), findsOneWidget);
  await t.tap(find.byKey(const Key('grp_confirm_yes')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a member sees what they owe and pays that very contribution', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(owing: <dynamic>[_obligation(31)]));
    await _pump(t, GroupsHome(api: api));

    // What they owe is on the Malipo yangu screen, behind a button that carries the number owed.
    await t.ensureVisible(find.byKey(const Key('grp_my_money')));
    await t.tap(find.byKey(const Key('grp_my_money')));
    await t.pumpAndSettle();
    expect(find.text('What I owe'), findsOneWidget);
    expect(find.byKey(const Key('grp_obl_31')), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_obl_31')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_pay_obligation')), findsOneWidget);
    expect(find.text('Still due: TSH 10,000'), findsOneWidget);

    await t.tap(find.byKey(const Key('grp_pay_method')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cash').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('grp_pay_send')));
    await t.tap(find.byKey(const Key('grp_pay_send')));
    await t.pumpAndSettle();
    await _yes(t);
    expect(api.calls, <String>['pay:contribution:31:10000.0']);
    await _banner(t);
  });

  testWidgets('a member promises to pay; the card says a promise does not lower the debt', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(owing: <dynamic>[_obligation(31)]));
    await _pump(t, GroupsHome(api: api));

    await t.ensureVisible(find.byKey(const Key('grp_my_money')));
    await t.tap(find.byKey(const Key('grp_my_money')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('grp_promise_open')));
    await t.tap(find.byKey(const Key('grp_promise_open')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_promise_amount')), '5000');
    await t.tap(find.byKey(const Key('grp_promise_save')));
    await t.pumpAndSettle();
    expect(find.textContaining('A promise does not lower the debt'), findsOneWidget);
    await _yes(t);
    expect(api.calls, <String>['promise:me:null:5000.0']);
    await _banner(t);
  });

  testWidgets('the treasurer calls the month, and records a withdrawal never past the savings', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(rights: _treasurer, office: 'mweka_hazina'));
    await _pump(t, GroupsHome(api: api));

    expect(find.byKey(const Key('grp_footer_contributions')), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_footer_contributions')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_type_7')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_act_raise')));
    await t.pumpAndSettle();
    final String month = '${DateTime.now().year.toString().padLeft(4, '0')}-${DateTime.now().month.toString().padLeft(2, '0')}';
    expect(find.text(month), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_raise_next')));
    await t.pumpAndSettle();
    await _yes(t);
    expect(api.calls, <String>['raise:7:$month']);
    await _banner(t);

    // The treasurer has no udhuru to give.
    await t.tap(find.byKey(const Key('grp_obl_41')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_act_exempt')), findsNothing);
    expect(find.byKey(const Key('grp_act_pay')), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_act_pay')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_pay_cat_withdrawal')), findsNothing, reason: 'from a contribution line the savings are not known');
    await t.tapAt(const Offset(200, 50));
    await t.pumpAndSettle();

    // From Payments: choose the member, their savings are read, the withdrawal can never pass them.
    await t.tap(find.byKey(const Key('grp_footer_payments')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_payment_record')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_act_payment')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_pick_5')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_pay_cat_withdrawal')));
    await t.pumpAndSettle();
    expect(find.text('Savings there are: TSH 30,000'), findsOneWidget);
    await t.enterText(find.byKey(const Key('grp_pay_amount')), '40000');
    await t.ensureVisible(find.byKey(const Key('grp_pay_send')));
    await t.tap(find.byKey(const Key('grp_pay_send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_pay_error')), findsOneWidget);
    expect(api.calls.length, 1, reason: 'nothing past the savings is sent');

    await t.enterText(find.byKey(const Key('grp_pay_amount')), '20000');
    await t.ensureVisible(find.byKey(const Key('grp_pay_send')));
    await t.tap(find.byKey(const Key('grp_pay_send')));
    await t.pumpAndSettle();
    await _yes(t);
    expect(api.calls.last, 'record:savings:out:20000.0:');
    await _banner(t);
  });

  testWidgets('the chair excuses a member only with a written reason', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(rights: _chair, office: 'mwenyekiti'));
    await _pump(t, GroupsHome(api: api));
    await t.tap(find.byKey(const Key('grp_footer_contributions')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('grp_obl_41')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_act_exempt')));
    await t.pumpAndSettle();
    expect(t.widget<TextButton>(find.byKey(const Key('grp_reason_yes'))).onPressed, isNull);
    await t.enterText(find.byKey(const Key('grp_reason_field')), 'Hospital');
    await t.pump();
    await t.tap(find.byKey(const Key('grp_reason_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['exempt:41:Hospital']);
    await _banner(t);
  });

  testWidgets('a group expense names who was paid; the summary shows cash, the month and what is overdue', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(rights: _treasurer, office: 'mweka_hazina'));
    await _pump(t, GroupsHome(api: api));
    await t.tap(find.byKey(const Key('grp_footer_payments')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('grp_cash_stat')), findsOneWidget);
    expect(find.text('TSH 185,000'), findsOneWidget);
    expect(find.text('TSH 10,000 / TSH 60,000'), findsOneWidget);

    await t.tap(find.byKey(const Key('grp_payment_record')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_act_expense')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_exp_amount')), '15000');
    await t.tap(find.byKey(const Key('grp_exp_send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_exp_error')), findsOneWidget, reason: 'who was paid');
    await t.enterText(find.byKey(const Key('grp_exp_payee')), 'Ukumbi');
    await t.tap(find.byKey(const Key('grp_exp_send')));
    await t.pumpAndSettle();
    await _yes(t);
    expect(api.calls, <String>['record:expense:in:15000.0:Ukumbi']);
    await _banner(t);
  });
}
