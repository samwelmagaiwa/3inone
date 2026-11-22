import 'package:boda_mapato/modules/groups/models/group_governance_models.dart';
import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/meeting_record_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _item(final int id, {final String kind = 'action', final int? assignee = 5, final String status = 'open', final bool overdue = false}) => <String, dynamic>{
      'id': id,
      'meeting_id': 1,
      'meeting_title': 'Kikao cha mwezi',
      'kind': kind,
      'text': kind == 'action' ? 'Kupata bei ya mabati' : 'Banda lijengwe kabla ya Julai',
      'assignee_id': kind == 'action' ? assignee : null,
      'assignee_name': kind == 'action' ? 'Asha Juma' : null,
      'due_date': kind == 'action' ? '2026-05-12' : null,
      'status': status,
      'overdue': overdue,
    };

GroupMeeting _meeting({final String minutes = 'draft', final List<Map<String, dynamic>>? items}) => GroupMeeting.fromJson(<String, dynamic>{
      'id': 1,
      'title': 'Kikao cha mwezi',
      'starts_at': '2026-05-10 14:00:00',
      'status': 'held',
      'minutes_status': minutes,
      'minutes_approved_by_name': minutes == 'approved' ? 'Chair Member' : null,
      'items': items ?? <Map<String, dynamic>>[_item(1, kind: 'resolution'), _item(2)],
    });

GroupMe _me({required final List<String> rights, final int memberId = 9}) => GroupMe.fromJson(<String, dynamic>{
      'is_owner': false,
      'rights': rights,
      'member': <String, dynamic>{'id': memberId, 'full_name': 'Neema Mussa', 'phone': '0712000001', 'status': 'active', 'member_number': 'MEG-0001'},
      'balances': <String, double>{'joining_fee': 0, 'shares': 0, 'savings': 0, 'contribution': 0},
      'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000},
    });

class _FakeApi extends GroupsApi {
  final List<String> calls = <String>[];

  @override
  Future<void> addMeetingItem(final int id, final Map<String, dynamic> body) async => calls.add('add:$id:${body['kind']}:${body['text']}');

  @override
  Future<void> removeMeetingItem(final int id, final int itemId) async => calls.add('remove:$id:$itemId');

  @override
  Future<void> completeMeetingItem(final int id, final int itemId) async => calls.add('done:$id:$itemId');

  @override
  Future<void> approveMinutes(final int id) async => calls.add('approve:$id');

  @override
  Future<void> reopenMinutes(final int id, final String reason) async => calls.add('reopen:$id:$reason');

  @override
  Future<List<GroupMeetingItem>> meetingActions({final bool all = false}) async => <GroupMeetingItem>[GroupMeetingItem.fromJson(_item(2, overdue: true))];
}

Future<void> _pump(final WidgetTester t, final Widget child) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 1400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)))),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _section(final WidgetTester t, final _FakeApi api, final GroupMe me, final GroupMeeting m) =>
    _pump(t, MeetingRecordSection(api: api, me: me, meeting: m, onChanged: () async {}));

void main() {
  testWidgets('the secretary writes while the minutes are a draft: resolutions and actions, removed after a Yes; no approval button', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi();
    await _section(t, api, _me(rights: <String>['record_meetings']), _meeting());

    expect(find.text('Draft'), findsOneWidget);
    expect(find.byKey(const Key('grp_add_resolution')), findsOneWidget);
    expect(find.byKey(const Key('grp_add_action')), findsOneWidget);
    expect(find.byKey(const Key('grp_minutes_approve')), findsNothing);
    await t.tap(find.byKey(const Key('grp_add_resolution')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_item_text')), 'Tutaweka akiba ya dharura');
    await t.pump();
    await t.tap(find.byKey(const Key('grp_item_save')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['add:1:resolution:Tutaweka akiba ya dharura']);
    await t.pump(const Duration(seconds: 6));

    await t.tap(find.byKey(const Key('grp_item_remove_1')));
    await t.pumpAndSettle();
    expect(api.calls.length, 1, reason: 'nothing is removed before the Yes');
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls.last, 'remove:1:1');
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('the chair approves the draft minutes after a Yes; an ordinary member sees no buttons', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi();
    await _section(t, api, _me(rights: <String>['approve_minutes']), _meeting());

    expect(find.byKey(const Key('grp_add_resolution')), findsNothing);
    await t.tap(find.byKey(const Key('grp_minutes_approve')));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['approve:1']);
    await t.pump(const Duration(seconds: 6));

    await _section(t, api, _me(rights: <String>[]), _meeting());
    expect(find.byKey(const Key('grp_minutes_approve')), findsNothing);
    expect(find.byKey(const Key('grp_add_action')), findsNothing);
    expect(find.byKey(const Key('grp_item_remove_1')), findsNothing);
  });

  testWidgets('approved minutes: the action is ticked off by its owner (or the secretary), and the chair may reopen them', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi();
    // Member 5 owns the action.
    await _section(t, api, _me(rights: <String>[], memberId: 5), _meeting(minutes: 'approved'));
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Chair Member'), findsOneWidget);
    expect(find.byKey(const Key('grp_add_action')), findsNothing, reason: 'approved minutes are not edited');
    await t.tap(find.byKey(const Key('grp_item_done_2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['done:1:2']);
    await t.pump(const Duration(seconds: 6));

    // Someone else has no button for it.
    await _section(t, api, _me(rights: <String>[], memberId: 7), _meeting(minutes: 'approved'));
    expect(find.byKey(const Key('grp_item_done_2')), findsNothing);

    await _section(t, api, _me(rights: <String>['approve_minutes']), _meeting(minutes: 'approved'));
    expect(find.byKey(const Key('grp_minutes_reopen')), findsOneWidget);
    expect(find.byKey(const Key('grp_minutes_approve')), findsNothing);
  });

  testWidgets('the follow-up list shows open actions with what is overdue, and ticks one off after a Yes', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi();
    await _pump(t, SizedBox(height: 900, child: MeetingActionsScreen(api: api, all: true)));

    expect(find.text('Kupata bei ya mabati'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_maction_done_2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['done:1:2']);
    await t.pump(const Duration(seconds: 6));
  });
}
