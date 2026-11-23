import 'package:boda_mapato/modules/groups/models/group_loan_models.dart';
import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/groups_home.dart';
import 'package:boda_mapato/modules/groups/screens/loan_detail_screen.dart';
import 'package:boda_mapato/modules/groups/screens/my_loans_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _loan({final int id = 9, final int memberId = 5, final String status = 'under_review', final double? approved}) => <String, dynamic>{
      'id': id,
      'reference': 'LN-ABC123',
      'member_id': memberId,
      'member_name': 'Asha Juma',
      'amount_requested': 240000,
      'amount_approved': approved,
      'purpose': 'Mtaji wa duka',
      'term_months': 6,
      'interest_rate': 2,
      'interest_method': 'flat',
      'ceiling': 300000,
      'status': status,
      'state': status,
      'guarantors': <dynamic>[
        <String, dynamic>{'id': 1, 'member_id': 6, 'name': 'Juma Ali', 'status': 'accepted'},
      ],
      'preview': <String, dynamic>{
        'instalments': <dynamic>[
          <String, dynamic>{'number': 1, 'due_date': '2026-12-10', 'principal_due': 40000, 'interest_due': 4800},
        ],
        'total_interest': 28800,
        'total': 268800,
      },
    };

class _FakeApi extends GroupsApi {
  _FakeApi(this.meJson, {this.eligibility, this.loanJson});

  final Map<String, dynamic> meJson;
  final Map<String, dynamic>? eligibility;
  final Map<String, dynamic>? loanJson;
  final List<String> calls = <String>[];

  @override
  Future<GroupMe> me() async => GroupMe.fromJson(meJson);

  @override
  Future<List<GroupTransaction>> myTransactions() async => const <GroupTransaction>[];

  @override
  Future<GroupLoanEligibility?> myEligibility() async => eligibility == null ? null : GroupLoanEligibility.fromJson(eligibility!);

  @override
  Future<(List<GroupLoan>, List<GroupGuarantee>)> myLoans() async => (
        const <GroupLoan>[],
        <GroupGuarantee>[
          GroupGuarantee.fromJson(<String, dynamic>{
            'id': 77, 'status': 'pending', 'loan_id': 9, 'reference': 'LN-ABC123', 'amount_requested': 240000, 'purpose': 'Mtaji wa duka',
            'borrower': 'Asha Juma', 'loan_status': 'awaiting_guarantors', 'term_months': 6,
          }),
        ],
      );

  @override
  Future<GroupLoan> applyLoan(final Map<String, dynamic> body) async {
    calls.add('apply:${body['amount']}:${body['term_months']}:${body['guarantor_ids']}');
    return GroupLoan.fromJson(_loan(status: 'awaiting_guarantors'));
  }

  @override
  Future<GroupLoan> respondGuarantee(final int guaranteeId, {required final bool accept, final String? note}) async {
    calls.add('guarantee:$guaranteeId:$accept');
    return GroupLoan.fromJson(_loan());
  }

  @override
  Future<GroupMemberPage> members({final String? status, final String? office, final String? query, final int page = 1}) async =>
      GroupMemberPage.fromJson(<String, dynamic>{
        'data': <String, dynamic>{
          'members': <Map<String, dynamic>>[<String, dynamic>{'id': 6, 'full_name': 'Juma Ali', 'phone': '0713000002', 'status': 'active', 'member_number': 'MEG-0006'}],
        },
      });

  @override
  Future<GroupLoan> loan(final int id) async => GroupLoan.fromJson(loanJson ?? _loan());

  @override
  Future<GroupLoan> recommendLoan(final int id, {required final double amount, required final String note}) async {
    calls.add('recommend:$id:$amount:$note');
    return GroupLoan.fromJson(_loan(status: 'recommended', approved: amount));
  }

  @override
  Future<GroupLoan> disburseLoan(final int id, {required final String method, final String? reference}) async {
    calls.add('disburse:$id:$method');
    return GroupLoan.fromJson(_loan(status: 'approved', approved: 200000));
  }

  @override
  Future<List<GroupBenefitRequest>> benefits({final String? status}) async => <GroupBenefitRequest>[
        GroupBenefitRequest.fromJson(<String, dynamic>{
          'id': 31, 'reference': 'MS-1', 'member_id': 5, 'member_name': 'Asha Juma', 'type_id': 2, 'type_name': 'Msiba',
          'beneficiary': 'Mama Asha', 'relationship': 'parent', 'event_date': '2026-11-08', 'state': 'submitted',
        }),
      ];

  @override
  Future<List<GroupBenefitType>> benefitTypes() async => <GroupBenefitType>[GroupBenefitType.fromJson(<String, dynamic>{'id': 2, 'name': 'Msiba', 'amount': 100000})];

  @override
  Future<void> decideBenefit(final int id, {required final bool approve, final double? amount, final String? note}) async => calls.add('decide:$id:$approve:$amount');
}

Map<String, dynamic> _me({final List<String> rights = const <String>[], final String? office, final int memberId = 1, final Map<String, int> waiting = const <String, int>{}}) => <String, dynamic>{
      'is_owner': false,
      'rights': rights,
      'member': <String, dynamic>{'id': memberId, 'full_name': 'Neema Mussa', 'phone': '0712000001', 'status': 'active', 'office': office, 'member_number': 'MEG-0001'},
      'balances': <String, double>{'joining_fee': 80000, 'shares': 200000, 'savings': 100000, 'contribution': 0},
      'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000},
      'waiting': waiting,
    };

Map<String, dynamic> _eligibility({final bool termsSet = true}) => <String, dynamic>{
      'savings': 100000,
      'multiplier': 3,
      'other_loans': 0,
      'ceiling': 300000,
      'shares_paid': 200000,
      'shares_needed': 200000,
      'eligible': termsSet,
      'reasons': termsSet ? <String>[] : <String>['terms_not_set'],
      'terms': <String, dynamic>{'rate': termsSet ? 2 : null, 'method': termsSet ? 'flat' : null, 'max_months': 12, 'guarantors': 1},
    };

Future<void> _pump(final WidgetTester t, final Widget home) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 1400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: home)),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _banner(final WidgetTester t) async {
  await t.pump(const Duration(seconds: 6));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the member sees how the ceiling is reached, and cannot apply before the group sets its terms', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(), eligibility: _eligibility(termsSet: false));
    await _pump(t, MyLoansScreen(api: api, me: GroupMe.fromJson(_me())));

    expect(find.text('TSH 100,000'), findsWidgets);
    expect(find.text('× 3'), findsOneWidget);
    expect(find.text('TSH 300,000'), findsOneWidget);
    expect(find.byKey(const Key('grp_reason_terms_not_set')), findsOneWidget);
    expect(find.byKey(const Key('grp_loan_apply_open')), findsNothing);
  });

  testWidgets('applying: never past the ceiling, guarantors chosen, Yes before it is sent', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(), eligibility: _eligibility());
    await _pump(t, MyLoansScreen(api: api, me: GroupMe.fromJson(_me())));

    await t.tap(find.byKey(const Key('grp_loan_apply_open')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_apply_amount')), '350000');
    await t.enterText(find.byKey(const Key('grp_apply_purpose')), 'Mtaji wa duka');
    await t.ensureVisible(find.byKey(const Key('grp_apply_send')));
    await t.tap(find.byKey(const Key('grp_apply_send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_apply_error')), findsOneWidget, reason: 'over the ceiling');

    await t.enterText(find.byKey(const Key('grp_apply_amount')), '240000');
    await t.ensureVisible(find.byKey(const Key('grp_apply_send')));
    await t.tap(find.byKey(const Key('grp_apply_send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_apply_error')), findsOneWidget, reason: 'a guarantor is needed');

    await t.ensureVisible(find.byKey(const Key('grp_apply_add_guarantor')));
    await t.tap(find.byKey(const Key('grp_apply_add_guarantor')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_pick_6')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('grp_apply_send')));
    await t.tap(find.byKey(const Key('grp_apply_send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_confirm')), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['apply:240000.0:6:[6]']);
    await _banner(t);
  });

  testWidgets('a guarantor sees the request on Home and agrees after a Yes', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(memberId: 6, waiting: <String, int>{'guarantees': 1}), eligibility: _eligibility());
    await _pump(t, GroupsHome(api: api));

    await t.ensureVisible(find.byKey(const Key('grp_waiting_open')));
    await t.tap(find.byKey(const Key('grp_waiting_open')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_wait_guarantees')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_guarantee_77')), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_guarantee_accept_77')));
    await t.pumpAndSettle();
    expect(find.textContaining('answer for it'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['guarantee:77:true']);
    await _banner(t);
  });

  testWidgets('the projects chairperson recommends, never above what was asked; the borrower gets no decision buttons', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(rights: <String>['view_members', 'view_finance', 'view_loans', 'recommend_loans'], office: 'mwenyekiti_miradi'));
    await _pump(t, LoanDetailScreen(api: api, me: GroupMe.fromJson(_me(rights: <String>['view_loans', 'recommend_loans'], office: 'mwenyekiti_miradi')), loanId: 9));

    expect(find.text('TSH 268,800'), findsOneWidget, reason: 'what it would cost, before it is paid out');
    expect(find.byKey(const Key('grp_loan_approve')), findsNothing);
    await t.tap(find.byKey(const Key('grp_loan_recommend')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_amount_field')), '250000');
    await t.pump();
    expect(t.widget<TextButton>(find.byKey(const Key('grp_amount_next'))).onPressed, isNull, reason: 'more than asked');
    await t.enterText(find.byKey(const Key('grp_amount_field')), '200000');
    await t.enterText(find.byKey(const Key('grp_amount_note')), 'Good record');
    await t.pump();
    await t.tap(find.byKey(const Key('grp_amount_next')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['recommend:9:200000.0:Good record']);
    await _banner(t);

    // The borrower on their own loan: withdraw only.
    final _FakeApi mine = _FakeApi(_me(memberId: 5, rights: <String>['view_loans', 'recommend_loans', 'approve_loans']));
    await _pump(t, LoanDetailScreen(api: mine, me: GroupMe.fromJson(_me(memberId: 5, rights: <String>['view_loans', 'recommend_loans', 'approve_loans'])), loanId: 9));
    expect(find.byKey(const Key('grp_loan_recommend')), findsNothing);
    expect(find.byKey(const Key('grp_loan_reject')), findsNothing);
    expect(find.byKey(const Key('grp_loan_cancel')), findsOneWidget);
  });

  testWidgets('the treasurer pays an approved loan out after a Yes, in the colour of money going out', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(rights: <String>['view_loans', 'record_payouts'], office: 'mweka_hazina'), loanJson: _loan(status: 'approved', approved: 200000));
    await _pump(t, LoanDetailScreen(api: api, me: GroupMe.fromJson(_me(rights: <String>['view_loans', 'record_payouts'], office: 'mweka_hazina')), loanId: 9));

    await t.tap(find.byKey(const Key('grp_loan_disburse')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_payout_next')));
    await t.pumpAndSettle();
    expect(find.textContaining('once someone else verifies'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['disburse:9:mpesa']);
    await _banner(t);
  });

  testWidgets('the chair approves welfare with its usual amount', (final WidgetTester t) async {
    final List<String> chair = <String>['view_members', 'view_finance', 'view_loans', 'approve_loans', 'view_benefits', 'approve_benefits', 'manage_settings'];
    final _FakeApi api = _FakeApi(_me(rights: chair, office: 'mwenyekiti'));
    await _pump(t, GroupsHome(api: api));

    await t.tap(find.byKey(const Key('grp_footer_menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Welfare').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_benefit_31')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_act_approve')));
    await t.pumpAndSettle();
    expect(find.text('100000'), findsOneWidget, reason: 'the usual amount of the kind of help');
    await t.tap(find.byKey(const Key('grp_amount_next')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['decide:31:true:100000.0']);
    await _banner(t);
  });
}
