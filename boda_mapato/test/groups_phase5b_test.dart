import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_records_models.dart';
import 'package:boda_mapato/modules/groups/screens/guest_group_screen.dart';
import 'package:boda_mapato/modules/groups/screens/records_screens.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends GroupsApi {
  final List<String> calls = <String>[];

  @override
  Future<GroupPublicInfo> publicGroup(final String code) async {
    calls.add('find:$code');
    return GroupPublicInfo.fromJson(<String, dynamic>{
      'group': 'MEG',
      'invited_by': 'Asha',
      'assets': <dynamic>[<String, dynamic>{'id': 4, 'name': 'Viti', 'hire_rate': 300, 'free_today': 50}],
    });
  }

  @override
  Future<(int, int, double)> publicAvailability(final String code, final int assetId, final String from, final String to) async => (50, 2, 300.0);

  @override
  Future<String> publicApply(final String code, final Map<String, dynamic> body) async {
    calls.add('apply:$code:${body['full_name']}:${body['consent']}');
    return 'APP-7KQ2MX';
  }

  @override
  Future<(String, double)> publicHire(final String code, final Map<String, dynamic> body) async {
    calls.add('hire:${body['quantity']}:${body['name']}');
    return ('HR-ABC123', 12000.0);
  }

  @override
  Future<(GroupInvitation?, List<GroupInvitation>)> invitations() async =>
      (GroupInvitation.fromJson(<String, dynamic>{'id': 1, 'code': 'K7P2QX9M', 'kind': 'member', 'active': true, 'used': 2}), const <GroupInvitation>[]);

  @override
  Future<void> stopCode(final int id) async => calls.add('stop:$id');

  @override
  Future<List<GroupTreeNode>> tree() async => <GroupTreeNode>[
        GroupTreeNode.fromJson(<String, dynamic>{'id': 1, 'name': 'Asha Juma', 'status': 'active', 'member_number': 'MEG-0001'}),
        GroupTreeNode.fromJson(<String, dynamic>{'id': 2, 'name': 'Rehema Said', 'status': 'active', 'member_number': 'MEG-0002', 'referrer_id': 1}),
        GroupTreeNode.fromJson(<String, dynamic>{'id': 3, 'name': 'Juma Ali', 'status': 'active', 'member_number': 'MEG-0003', 'referrer_id': 2}),
      ];
}

Future<void> _pump(final WidgetTester t, final Widget home) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1500);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 1500), minTextAdapt: true, builder: (_, __) => MaterialApp(home: home)),
    ),
  );
  await t.pumpAndSettle();
}

GroupMe _me() => GroupMe.fromJson(<String, dynamic>{
      'rights': <String>[],
      'member': <String, dynamic>{'id': 1, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active'},
      'group': <String, dynamic>{'name': 'MEG'},
    });

void main() {
  testWidgets('someone outside the group finds it by code and applies, agreeing to the use of their details', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi();
    await _pump(t, GuestGroupScreen(api: api));

    await t.tap(find.byKey(const Key('grp_guest_find')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_guest_error')), findsOneWidget, reason: 'no code yet');
    await t.enterText(find.byKey(const Key('grp_guest_code')), 'k7p2qx9m');
    await t.tap(find.byKey(const Key('grp_guest_find')));
    await t.pumpAndSettle();
    expect(find.text('MEG'), findsOneWidget);
    expect(find.text('Invited by Asha'), findsOneWidget);

    await t.enterText(find.byKey(const Key('grp_guest_name')), 'Rehema Said');
    await t.enterText(find.byKey(const Key('grp_guest_phone')), '0715000001');
    await t.ensureVisible(find.byKey(const Key('grp_guest_join_send')));
    await t.tap(find.byKey(const Key('grp_guest_join_send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_guest_join_error')), findsOneWidget, reason: 'consent first');
    await t.ensureVisible(find.byKey(const Key('grp_guest_consent')));
    await t.tap(find.byKey(const Key('grp_guest_consent')));
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('grp_guest_join_send')));
    await t.tap(find.byKey(const Key('grp_guest_join_send')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls.last, 'apply:k7p2qx9m:Rehema Said:true');
    expect(find.textContaining('APP-7KQ2MX'), findsOneWidget);
  });

  testWidgets('someone outside the group sees the price and asks to hire', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi();
    await _pump(t, GuestGroupScreen(api: api, code: 'K7P2QX9M'));
    await t.tap(find.byKey(const Key('grp_guest_find')));
    await t.pumpAndSettle();
    await t.tap(find.text('To hire'));
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const Key('grp_guest_qty')), '20');
    await t.pump();
    expect(find.text('Cost: TSH 12,000'), findsOneWidget);
    await t.enterText(find.byKey(const Key('grp_guest_hire_name')), 'Mzee Kassim');
    await t.enterText(find.byKey(const Key('grp_guest_hire_phone')), '0754000111');
    await t.ensureVisible(find.byKey(const Key('grp_guest_hire_send')));
    await t.tap(find.byKey(const Key('grp_guest_hire_send')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls.last, 'hire:20:Mzee Kassim');
    expect(find.textContaining('HR-ABC123'), findsOneWidget);
  });

  testWidgets('a member sees their own code and stops it only after a Yes', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi();
    await _pump(t, InviteScreen(api: api, me: _me()));

    expect(find.text('K7P2QX9M'), findsOneWidget);
    expect(find.byKey(const Key('grp_group_code_new')), findsNothing, reason: 'group codes are for whoever registers members');
    await t.ensureVisible(find.byKey(const Key('grp_code_stop_1')));
    await t.tap(find.byKey(const Key('grp_code_stop_1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_no')));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.byKey(const Key('grp_code_stop_1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['stop:1']);
  });

  testWidgets('the tree nests who brought whom and a search shows the path from the top', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi();
    await _pump(t, ReferralTreeScreen(api: api, whole: true));

    expect(find.textContaining('Brought in 1 · in all 2'), findsOneWidget, reason: 'Asha brought Rehema, who brought Juma');
    await t.enterText(find.byKey(const Key('grp_tree_search')), 'juma ali');
    await t.pump();
    expect(find.text('Asha Juma → Rehema Said → Juma Ali'), findsOneWidget);
  });
}
