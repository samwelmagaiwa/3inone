import 'package:boda_mapato/modules/groups/models/group_asset_models.dart';
import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/groups_home.dart';
import 'package:boda_mapato/modules/groups/screens/hire_detail_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _asset() => <String, dynamic>{
      'id': 4, 'code': 'VT-01', 'name': 'Viti', 'quantity': 100, 'free_today': 100, 'condition': 'good', 'status': 'active', 'hire_rate': 300, 'custodian_id': 9, 'custodian_name': 'Keeper',
    };

Map<String, dynamic> _hire({final String status = 'requested', final String state = 'requested', final int? memberId = 5}) => <String, dynamic>{
      'id': 12, 'reference': 'HR-ABC', 'asset_id': 4, 'asset_name': 'Viti', 'member_id': memberId, 'who': 'Asha Juma', 'quantity': 60,
      'start_date': '2026-11-20', 'end_date': '2026-11-22', 'days': 3, 'rate': 300, 'amount': 54000, 'total': 54000, 'paid': 0, 'balance': 54000,
      'status': status, 'state': state, 'issued_quantity': status == 'issued' || status == 'returned' ? 60 : null,
    };

class _FakeApi extends GroupsApi {
  _FakeApi(this.meJson, {this.hireJson});

  final Map<String, dynamic> meJson;
  final Map<String, dynamic>? hireJson;
  final List<String> calls = <String>[];

  @override
  Future<GroupMe> me() async => GroupMe.fromJson(meJson);

  @override
  Future<List<GroupTransaction>> myTransactions() async => const <GroupTransaction>[];

  @override
  Future<(List<GroupAsset>, bool)> assets() async => (<GroupAsset>[GroupAsset.fromJson(_asset())], false);

  @override
  Future<(int, int, double?)> availability(final int assetId, final String from, final String to) async => (100, 3, 300.0);

  @override
  Future<List<GroupHire>> myHires() async => const <GroupHire>[];

  @override
  Future<GroupHire> askHire(final Map<String, dynamic> body) async {
    calls.add('ask:${body['asset_id']}:${body['quantity']}');
    return GroupHire.fromJson(_hire());
  }

  @override
  Future<List<GroupHire>> hires({final String? status}) async => <GroupHire>[GroupHire.fromJson(hireJson ?? _hire())];

  @override
  Future<GroupHire> decideHire(final int id, {required final bool approve, final String? note}) async {
    calls.add('decide:$id:$approve');
    return GroupHire.fromJson(_hire(status: 'approved', state: 'waiting_payment'));
  }

  @override
  Future<GroupHire> returnHire(final int id, {required final int returned, final int damaged = 0, final int missing = 0, final String? note}) async {
    calls.add('return:$id:$returned:$damaged:$missing');
    return GroupHire.fromJson(_hire(status: 'returned', state: 'damage_pending'));
  }

  @override
  Future<GroupHire> chargeHire(final int id, {required final double amount, required final String note}) async {
    calls.add('charge:$id:$amount:$note');
    return GroupHire.fromJson(_hire(status: 'returned', state: 'settled'));
  }
}

Map<String, dynamic> _me({final List<String> rights = const <String>[], final bool keeper = false, final int memberId = 1}) => <String, dynamic>{
      'is_owner': false,
      'rights': rights,
      'member': <String, dynamic>{'id': memberId, 'full_name': 'Neema Mussa', 'phone': '0712000001', 'status': 'active', 'member_number': 'MEG-0001'},
      'settings': <String, dynamic>{'joining_fee': 0, 'share_amount': 0},
      'waiting': keeper ? <String, int>{'hires_to_decide': 1} : <String, int>{},
      'keeps_assets': keeper,
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
  testWidgets('a member sees the price for the days and how many are free before asking to hire', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me());
    await _pump(t, GroupsHome(api: api));

    await t.ensureVisible(find.byKey(const Key('grp_my_hires')));
    await t.tap(find.byKey(const Key('grp_my_hires')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_asset_4')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_hireform_qty')), '60');
    await t.pump();
    expect(find.text('Cost: 60 × TSH 300 × 3 = TSH 54,000'), findsOneWidget);

    await t.enterText(find.byKey(const Key('grp_hireform_qty')), '120');
    await t.ensureVisible(find.byKey(const Key('grp_hireform_send')));
    await t.tap(find.byKey(const Key('grp_hireform_send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_hireform_error')), findsOneWidget, reason: 'only 100 are free');

    await t.enterText(find.byKey(const Key('grp_hireform_qty')), '60');
    await t.ensureVisible(find.byKey(const Key('grp_hireform_send')));
    await t.tap(find.byKey(const Key('grp_hireform_send')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['ask:4:60']);
    await _banner(t);
  });

  testWidgets('the keeper (no office) finds the request under Assets and confirms it after a Yes', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(keeper: true, memberId: 9));
    await _pump(t, GroupsHome(api: api));

    await t.ensureVisible(find.byKey(const Key('grp_waiting_open')));
    await t.tap(find.byKey(const Key('grp_waiting_open')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_wait_hires')), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_wait_hires')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_hire_12')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_hire_charge')), findsNothing);
    await t.tap(find.byKey(const Key('grp_hire_approve')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['decide:12:true']);
    await _banner(t);
  });

  testWidgets('taking things back: the counts must add up, damaged and missing ask in red', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(keeper: true, memberId: 9));
    await _pump(t, HireDetailScreen(api: api, me: GroupMe.fromJson(_me(keeper: true, memberId: 9)), hire: GroupHire.fromJson(_hire(status: 'issued', state: 'out'))));

    await t.tap(find.byKey(const Key('grp_hire_return')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_return_back')), '50');
    await t.enterText(find.byKey(const Key('grp_return_missing')), '5');
    await t.pump();
    expect(t.widget<TextButton>(find.byKey(const Key('grp_return_next'))).onPressed, isNull, reason: '50 + 5 is not 60');
    await t.enterText(find.byKey(const Key('grp_return_back')), '55');
    await t.enterText(find.byKey(const Key('grp_return_damaged')), '2');
    await t.pump();
    await t.tap(find.byKey(const Key('grp_return_next')));
    await t.pumpAndSettle();
    expect(find.textContaining('the chair decides any charge'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['return:12:55:2:5']);
    await _banner(t);
  });

  testWidgets('the chair decides a damage charge, and 0 is a decision too; the hirer gets no keeper buttons', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(rights: <String>['manage_assets', 'decide_hire_charges']));
    await _pump(t, HireDetailScreen(api: api, me: GroupMe.fromJson(_me(rights: <String>['manage_assets', 'decide_hire_charges'])), hire: GroupHire.fromJson(_hire(status: 'returned', state: 'damage_pending'))));

    await t.tap(find.byKey(const Key('grp_hire_charge')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_amount_note')), 'Old chairs, no charge');
    await t.pump();
    await t.tap(find.byKey(const Key('grp_amount_next')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['charge:12:0.0:Old chairs, no charge']);
    await _banner(t);

    final _FakeApi mine = _FakeApi(_me(memberId: 5, rights: <String>['manage_assets']));
    await t.pumpWidget(const SizedBox());
    await _pump(t, HireDetailScreen(api: mine, me: GroupMe.fromJson(_me(memberId: 5, rights: <String>['manage_assets'])), hire: GroupHire.fromJson(_hire())));
    expect(find.byKey(const Key('grp_hire_approve')), findsNothing, reason: 'nobody confirms their own hire');
    expect(find.byKey(const Key('grp_hire_cancel')), findsOneWidget);
  });
}
