import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/groups_home.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _me({required final List<String> rights, final String? office, final bool owner = false, final bool withMember = true, final String? photo}) => <String, dynamic>{
      'is_owner': owner,
      'rights': rights,
      'member': withMember
          ? <String, dynamic>{'id': 1, 'full_name': 'Neema Mussa', 'phone': '0712000001', 'status': 'active', 'office': office, 'member_number': 'MEG-0001', 'photo_url': photo}
          : null,
      'balances': <String, double>{'savings': 120000, 'shares': 50000},
      'pending': 0,
      'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000, 'shares_required_for': 'loans', 'payment_instructions': ''},
      'waiting': <String, int>{'payments_to_verify': 4, 'votes_to_cast': 1},
      'group': <String, dynamic>{'name': 'MEG'},
    };

class _Api extends GroupsApi {
  _Api(this.json);

  final Map<String, dynamic> json;

  @override
  Future<GroupMe> me() async => GroupMe.fromJson(json);

  @override
  Future<List<GroupTransaction>> myTransactions() async => const <GroupTransaction>[];
}

Future<void> _pump(final WidgetTester t, final Widget home, {final Map<String, Object> prefs = const <String, Object>{}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  await LocalizationService.instance.changeLanguage('en');
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

void main() {
  test('asMember keeps the account and drops the office: no rights, no leaders\' queues, only the member\'s own waiting', () {
    final GroupMe leader = GroupMe.fromJson(_me(rights: <String>['view_finance', 'verify_payments', 'view_members'], office: 'treasurer'));
    expect(leader.canBeMe, isTrue);
    final GroupMe me = leader.asMember();
    expect(me.personal, isTrue);
    expect(me.rights, isEmpty);
    expect(me.isOwner, isFalse);
    expect(me.member?.fullName, 'Neema Mussa');
    expect(me.balances?['savings'], 120000);
    expect(me.waiting.keys, <String>['votes_to_cast']);
    expect(me.seesPayments, isFalse);
    expect(me.member?.office, isNull, reason: 'the office is not shown in ME');
    expect(me.canBeMe, isTrue, reason: 'the switch stays so they can go back');
  });

  test('an ordinary member, and an owner who is not a member, have no ME switch', () {
    expect(GroupMe.fromJson(_me(rights: const <String>[])).canBeMe, isFalse);
    expect(GroupMe.fromJson(_me(rights: <String>['view_finance'], owner: true, withMember: false)).canBeMe, isFalse);
    expect(GroupMe.fromJson(_me(rights: <String>['view_finance'], owner: true)).canBeMe, isTrue, reason: 'an owner who is a member may');
  });

  testWidgets('a leader sees the ME switch; turning it on shows only their member view, off brings the office back, and it is remembered', (final WidgetTester t) async {
    final Map<String, dynamic> json = _me(rights: <String>['view_finance', 'verify_payments', 'view_members'], office: 'treasurer');
    await _pump(t, GroupsHome(api: _Api(json)));

    expect(find.byKey(const Key('grp_me_toggle')), findsOneWidget);
    expect(find.byKey(const Key('grp_footer_members')), findsOneWidget, reason: 'the office: the register and payments');
    expect(find.byKey(const Key('grp_footer_payments')), findsOneWidget);

    await t.tap(find.byKey(const Key('grp_me_toggle')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_footer_members')), findsNothing);
    expect(find.byKey(const Key('grp_footer_payments')), findsNothing);
    expect(find.byKey(const Key('grp_footer_home')), findsOneWidget);
    expect(find.byKey(const Key('grp_my_account')), findsOneWidget, reason: 'their own account is on Home');
    expect((await SharedPreferences.getInstance()).getBool('grp_me_mode_1_MEG'), isTrue);

    await t.tap(find.byKey(const Key('grp_me_toggle')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_footer_members')), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('grp_me_mode_1_MEG'), isFalse);
  });

  testWidgets('ME stays on the next time the service opens, until the person turns it off', (final WidgetTester t) async {
    final Map<String, dynamic> json = _me(rights: <String>['view_finance', 'verify_payments', 'view_members'], office: 'treasurer');
    await _pump(t, GroupsHome(api: _Api(json)), prefs: <String, Object>{'grp_me_mode_1_MEG': true});
    expect(find.byKey(const Key('grp_footer_members')), findsNothing);
    expect(find.byKey(const Key('grp_my_account')), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_me_toggle')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_footer_members')), findsOneWidget);
  });

  testWidgets('when the server already answers as a member (ME on), the switch is still there and the header is sent; leaving clears it', (final WidgetTester t) async {
    final Map<String, dynamic> json = _me(rights: const <String>[], office: null)
      ..['can_switch_view'] = true
      ..['viewing_as_member'] = true;
    await _pump(t, GroupsHome(api: _Api(json)), prefs: <String, Object>{'grp_me_mode_1_MEG': true});
    expect(find.byKey(const Key('grp_me_toggle')), findsOneWidget, reason: 'a leader in ME can always go back');
    expect(ApiService.groupViewAsMember, isTrue);
    await t.pumpWidget(const SizedBox());
    expect(ApiService.groupViewAsMember, isFalse, reason: 'other services never send the view');
  });

  testWidgets('the switch sends the view as soon as it is turned on and stops sending it when turned off', (final WidgetTester t) async {
    final Map<String, dynamic> json = _me(rights: <String>['view_finance', 'view_members'], office: 'treasurer')..['can_switch_view'] = true;
    await _pump(t, GroupsHome(api: _Api(json)));
    expect(ApiService.groupViewAsMember, isFalse);
    expect(find.textContaining('treasurer'), findsWidgets, reason: 'the office is on Home');
    await t.tap(find.byKey(const Key('grp_me_toggle')));
    await t.pumpAndSettle();
    expect(ApiService.groupViewAsMember, isTrue);
    expect(find.textContaining('treasurer'), findsNothing, reason: 'their office is not on Home in ME');
    await t.tap(find.byKey(const Key('grp_me_toggle')));
    await t.pumpAndSettle();
    expect(ApiService.groupViewAsMember, isFalse);
  });

  testWidgets('an ordinary member has no ME switch', (final WidgetTester t) async {
    await _pump(t, GroupsHome(api: _Api(_me(rights: const <String>[]))));
    expect(find.byKey(const Key('grp_me_toggle')), findsNothing);
    expect(find.byKey(const Key('grp_my_account')), findsOneWidget);
  });

  testWidgets('the account card shows the member\'s picture (their initials until they have one) with the camera badge', (final WidgetTester t) async {
    await _pump(t, GroupsHome(api: _Api(_me(rights: const <String>[]))));
    expect(find.byKey(const Key('grp_member_avatar')), findsOneWidget);
    expect(find.byKey(const Key('grp_member_initials')), findsOneWidget);
    expect(find.byKey(const Key('grp_member_avatar_edit')), findsOneWidget, reason: 'they may set their own photo');
  });
}
