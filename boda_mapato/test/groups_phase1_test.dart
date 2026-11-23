import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/groups_home.dart';
import 'package:boda_mapato/modules/groups/screens/member_detail_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _member(final int id, final String name, {final String status = 'active', final String? office, final String? number}) => <String, dynamic>{
      'id': id,
      'full_name': name,
      'phone': '07120000$id',
      'status': status,
      'office': office,
      'member_number': number ?? (status == 'active' ? 'MEG-000$id' : null),
      'application_ref': 'APP-00000$id',
      'has_sign_in': true,
    };

Map<String, dynamic> _tx(final int id, {final String status = 'pending', final int memberId = 2, final String name = 'Asha Juma'}) => <String, dynamic>{
      'id': id,
      'reference': 'TRX-$id',
      'category': 'joining_fee',
      'direction': 'in',
      'amount': 80000,
      'method': 'mpesa',
      'external_ref': 'QWE$id',
      'paid_on': '2026-11-22',
      'status': status,
      'member_id': memberId,
      'member_name': name,
    };

/// The server, as the screens see it: canned answers, and every change remembered.
class _FakeApi extends GroupsApi {
  _FakeApi({required this.meJson, this.file});

  Map<String, dynamic> meJson;
  Map<String, dynamic>? file;
  final List<String> calls = <String>[];
  List<Map<String, dynamic>> pending = <Map<String, dynamic>>[_tx(11)];

  @override
  Future<GroupMe> me() async => GroupMe.fromJson(meJson);

  @override
  Future<List<GroupTransaction>> myTransactions() async => <GroupTransaction>[GroupTransaction.fromJson(_tx(5, status: 'verified', memberId: 1))];

  @override
  Future<GroupTransaction> payMine(final Map<String, dynamic> payment) async {
    calls.add('pay:${payment['category']}:${payment['amount']}:${payment['method']}:${payment['external_ref']}');
    return GroupTransaction.fromJson(_tx(99, memberId: 1));
  }

  @override
  Future<GroupMemberPage> members({final String? status, final String? office, final String? query, final int page = 1}) async =>
      GroupMemberPage.fromJson(<String, dynamic>{
        'data': <String, dynamic>{
          'members': <Map<String, dynamic>>[_member(2, 'Asha Juma', status: 'submitted'), _member(3, 'Juma Ali')],
          'counts': <String, int>{'submitted': 1, 'active': 1},
        },
      });

  @override
  Future<GroupMemberFile> member(final int id) async => GroupMemberFile.fromJson(file!);

  @override
  Future<GroupMemberFile> moveMember(final int id, final String action, {final String? reason}) async {
    calls.add('move:$id:$action:${reason ?? ''}');
    return GroupMemberFile.fromJson(file!);
  }

  @override
  Future<GroupTransactionPage> transactions({final String? status, final String? category, final int? memberId, final String? query, final int page = 1}) async =>
      GroupTransactionPage.fromJson(<String, dynamic>{
        'data': <String, dynamic>{'transactions': status == 'pending' ? pending : <Map<String, dynamic>>[]},
      });

  @override
  Future<Map<String, dynamic>> moneySummary({final String? month}) async => <String, dynamic>{
        'verified': <String, dynamic>{'joining_fee': 160000, 'shares': 0},
        'pending_count': pending.length,
        'pending_amount': 80000,
      };

  @override
  Future<GroupTransaction> verify(final int id) async {
    calls.add('verify:$id');
    pending = <Map<String, dynamic>>[];
    return GroupTransaction.fromJson(_tx(id, status: 'verified')..['receipt_number'] = 'RC-000001');
  }

  @override
  Future<GroupTransaction> reject(final int id, final String reason) async {
    calls.add('reject:$id:$reason');
    return GroupTransaction.fromJson(_tx(id, status: 'rejected'));
  }
}

Map<String, dynamic> _me({final List<String> rights = const <String>[], final String? office, final Map<String, int> waiting = const <String, int>{}}) => <String, dynamic>{
      'is_owner': false,
      'rights': rights,
      'member': _member(1, 'Neema Mussa', office: office),
      'balances': <String, double>{'joining_fee': 80000, 'shares': 50000},
      'pending': 0,
      'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000, 'shares_required_for': 'loans', 'payment_instructions': 'M-Pesa 0712 000 000 (MEG)'},
      'waiting': waiting,
      'group': <String, dynamic>{'name': 'MEG'},
    };

Future<void> _pump(final WidgetTester t, final Widget home, {final String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(lang);
  t.view.physicalSize = const Size(411, 1200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 1200), minTextAdapt: true, builder: (_, __) => MaterialApp(home: home)),
    ),
  );
  await t.pumpAndSettle();
}

/// The green banner at the top closes itself after a few seconds: let it, so no timer is left when the test ends.
Future<void> _banner(final WidgetTester t) async {
  await t.pump(const Duration(seconds: 6));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('an ordinary member sees only Home: their file, their money and the Pay button', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(meJson: _me());
    await _pump(t, GroupsHome(api: api));

    expect(find.byKey(const Key('grp_me_name')), findsOneWidget);
    expect(find.text('Neema Mussa'), findsOneWidget);
    expect(find.byKey(const Key('grp_footer_home')), findsOneWidget);
    expect(find.byKey(const Key('grp_footer_members')), findsNothing, reason: 'no office, no register');
    expect(find.byKey(const Key('grp_footer_payments')), findsNothing);
    expect(find.text('TSH 50,000 / TSH 200,000'), findsOneWidget, reason: 'shares paid of what is due');
    expect(find.byKey(const Key('grp_pay_open')), findsOneWidget);
    expect(find.byKey(const Key('grp_wait_payments')), findsNothing);
  });

  testWidgets('paying asks for the reference of a mobile payment, then asks Yes / No before it is sent', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(meJson: _me());
    await _pump(t, GroupsHome(api: api));

    await t.tap(find.byKey(const Key('grp_pay_open')));
    await t.pumpAndSettle();
    // The joining fee is paid, so the form starts on the shares with what is still due.
    expect(find.text('Still due: TSH 150,000'), findsOneWidget);
    expect(find.byKey(const Key('grp_pay_instructions')), findsOneWidget);

    await t.ensureVisible(find.byKey(const Key('grp_pay_send')));
    await t.tap(find.byKey(const Key('grp_pay_send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_pay_error')), findsOneWidget, reason: 'M-Pesa needs its reference');
    expect(api.calls, isEmpty);

    await t.enterText(find.byKey(const Key('grp_pay_ref')), 'QAZ123');
    await t.ensureVisible(find.byKey(const Key('grp_pay_send')));
    await t.tap(find.byKey(const Key('grp_pay_send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_confirm')), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_confirm_no')));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty, reason: 'No sends nothing');

    await t.tap(find.byKey(const Key('grp_pay_send')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['pay:shares:150000.0:mpesa:QAZ123']);
    await _banner(t);
  });

  testWidgets('the treasurer verifies a waiting payment after a Yes', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(
      meJson: _me(rights: <String>['view_members', 'view_finance', 'record_payments', 'verify_payments', 'reverse_payments'], office: 'mweka_hazina', waiting: <String, int>{'payments_to_verify': 1}),
    );
    await _pump(t, GroupsHome(api: api));

    expect(find.byKey(const Key('grp_wait_payments')), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_wait_payments')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_tx_11')), findsOneWidget);
    expect(find.byKey(const Key('grp_pay_pending_stat')), findsOneWidget);

    await t.tap(find.byKey(const Key('grp_tx_11')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_act_verify')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_confirm')), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['verify:11']);
    expect(find.text('Nothing waits for verification.'), findsOneWidget);
    await _banner(t);
  });

  testWidgets('turning a payment down needs a written reason', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(meJson: _me(rights: <String>['view_members', 'view_finance', 'verify_payments'], office: 'mweka_hazina_msaidizi'));
    await _pump(t, GroupsHome(api: api));
    await t.tap(find.byKey(const Key('grp_footer_payments')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('grp_tx_11')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_act_reverse')), findsNothing, reason: 'the assistant treasurer does not reverse');
    await t.tap(find.byKey(const Key('grp_act_reject')));
    await t.pumpAndSettle();
    final TextButton yes = t.widget<TextButton>(find.byKey(const Key('grp_reason_yes')));
    expect(yes.onPressed, isNull, reason: 'no reason, no button');
    await t.enterText(find.byKey(const Key('grp_reason_field')), 'Reference not found');
    await t.pump();
    await t.tap(find.byKey(const Key('grp_reason_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['reject:11:Reference not found']);
    await _banner(t);
  });

  testWidgets('an application waiting for its joining fee cannot be approved yet; rejecting asks why', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(
      meJson: _me(rights: <String>['view_members', 'manage_members', 'approve_members', 'record_payments'], office: 'mwenyekiti'),
      file: <String, dynamic>{
        'member': _member(2, 'Asha Juma', status: 'submitted'),
        'dependants': <dynamic>[],
        'events': <dynamic>[],
        'referrals': <dynamic>[],
        'balances': <String, dynamic>{'joining_fee': 0, 'shares': 0},
        'approval_blockers': <String>['joining_fee_unpaid'],
      },
    );
    final GroupMe me = await api.me();
    await _pump(t, MemberDetailScreen(api: api, me: me, memberId: 2));

    // The member's picture sits in the top corner of the page: initials until a photo is kept, and the camera for whoever may change it.
    expect(find.byKey(const Key('grp_member_avatar')), findsOneWidget);
    expect(find.byKey(const Key('grp_member_initials')), findsOneWidget);
    expect(find.byKey(const Key('grp_blocker_joining_fee_unpaid')), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('grp_app_approve'))).onPressed, isNull);
    expect(find.byKey(const Key('grp_app_record_payment')), findsOneWidget);

    await t.tap(find.byKey(const Key('grp_app_reject')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_reason')), findsOneWidget);
    await t.enterText(find.byKey(const Key('grp_reason_field')), 'Did not pay');
    await t.pump();
    await t.tap(find.byKey(const Key('grp_reason_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['move:2:reject:Did not pay']);
    await _banner(t);
  });

  testWidgets('nobody is offered to change their own office or membership', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(
      meJson: _me(rights: <String>['view_members', 'manage_members', 'approve_members', 'manage_offices'], office: 'mwenyekiti'),
      file: <String, dynamic>{'member': _member(1, 'Neema Mussa', office: 'mwenyekiti'), 'approval_blockers': <String>[]},
    );
    final GroupMe me = await api.me();
    await _pump(t, MemberDetailScreen(api: api, me: me, memberId: 1));

    await t.tap(find.byKey(const Key('grp_member_actions')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_act_edit')), findsOneWidget);
    expect(find.byKey(const Key('grp_act_office')), findsNothing);
    expect(find.byKey(const Key('grp_act_suspend')), findsNothing);
    expect(find.byKey(const Key('grp_act_exit')), findsNothing);
  });

  testWidgets('the whole service follows the language switch', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(meJson: _me(rights: <String>['view_members'], office: 'kamati_miradi'));
    await _pump(t, GroupsHome(api: api), lang: 'sw');

    expect(find.text('Mwanzo'), findsWidgets);
    expect(find.text('Wanachama'), findsOneWidget);
    expect(find.text('Malipo yangu'), findsOneWidget);
    expect(find.text('Kamati ya Miradi · MEG-0001'), findsOneWidget);

    await t.tap(find.byKey(const Key('grp_footer_members')));
    await t.pumpAndSettle();
    expect(find.text('Ombi jipya'), findsWidgets);
    await LocalizationService.instance.changeLanguage('en');
    await t.pumpAndSettle();
    expect(find.text('Members'), findsWidgets);
    expect(find.text('Application'), findsWidgets);
  });
}
