import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_project_models.dart';
import 'package:boda_mapato/modules/groups/screens/projects_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _project(final int id, {final String status = 'proposed', final int proposedBy = 9, final int progress = 0}) => <String, dynamic>{
      'id': id,
      'reference': 'MR-00000$id',
      'title': 'Poultry house',
      'description': 'Layers for eggs',
      'budget': 5000000,
      'proposed_by_id': proposedBy,
      'proposer_name': 'Asha Juma',
      'status': status,
      'progress': progress,
      'supports': 1,
      'opposes': 0,
      'updates': <dynamic>[],
      'reviews': <dynamic>[],
    };

Map<String, dynamic> _me({required final List<String> rights, final int memberId = 1, final Map<String, int> waiting = const <String, int>{}}) => <String, dynamic>{
      'is_owner': false,
      'rights': rights,
      'member': <String, dynamic>{'id': memberId, 'full_name': 'Neema Mussa', 'phone': '0712000001', 'status': 'active', 'member_number': 'MEG-0001'},
      'balances': <String, double>{'joining_fee': 80000, 'shares': 200000, 'savings': 100000, 'contribution': 0},
      'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000},
      'waiting': waiting,
    };

class _FakeApi extends GroupsApi {
  _FakeApi(this.rows);

  final List<Map<String, dynamic>> rows;
  final List<String> calls = <String>[];

  @override
  Future<List<GroupProject>> projects({final String? status}) async => <GroupProject>[
        for (final Map<String, dynamic> r in rows)
          if (status == null || r['status'] == status) GroupProject.fromJson(r),
      ];

  @override
  Future<GroupProject> project(final int id) async => GroupProject.fromJson(rows.firstWhere((final Map<String, dynamic> r) => r['id'] == id));

  @override
  Future<GroupProject> proposeProject(final Map<String, dynamic> body) async {
    calls.add('propose:${body['title']}:${body['budget']}');
    return GroupProject.fromJson(_project(7));
  }

  @override
  Future<GroupProject> reviewProject(final int id, {required final bool supports, final String? note}) async {
    calls.add('review:$id:$supports');
    return project(id);
  }

  @override
  Future<GroupProject> decideProject(final int id, {required final bool approve, final String? note}) async {
    calls.add('decide:$id:$approve');
    return project(id);
  }

  @override
  Future<GroupProject> logProjectProgress(final int id, {required final int progress, required final String note}) async {
    calls.add('progress:$id:$progress:$note');
    return project(id);
  }
}

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

Future<void> _detail(final WidgetTester t, final _FakeApi api, final GroupMe me, final int id) =>
    _pump(t, ProjectDetailScreen(me: me, api: api, id: id));

void main() {
  testWidgets('an ordinary member proposes a project after a Yes, and sees the running ones', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(<Map<String, dynamic>>[_project(1, status: 'active', progress: 40)]);
    await _pump(t, Scaffold(body: ProjectsScreen(me: GroupMe.fromJson(_me(rights: <String>[])), api: api, onChanged: () async {})));

    expect(find.text('Poultry house'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_project_propose')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_project_title')), 'Water pump');
    await t.enterText(find.byKey(const Key('grp_project_budget')), '2500000');
    await t.tap(find.byKey(const Key('grp_project_send')));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty, reason: 'nothing is sent before the Yes');
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['propose:Water pump:2500000.0']);
    await t.pump(const Duration(seconds: 6)); // the success banner's timer
  });

  testWidgets('a project proposed by someone else: the committee may recommend, the chair may decide, an ordinary member does neither', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(<Map<String, dynamic>>[_project(1)]);

    await _detail(t, api, GroupMe.fromJson(_me(rights: <String>['view_projects', 'recommend_projects'])), 1);
    expect(find.byKey(const Key('grp_project_support')), findsOneWidget);
    expect(find.byKey(const Key('grp_project_approve')), findsNothing);
    await t.tap(find.byKey(const Key('grp_project_support')));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['review:1:true']);

    await _detail(t, api, GroupMe.fromJson(_me(rights: <String>['view_projects', 'approve_projects'])), 1);
    expect(find.byKey(const Key('grp_project_approve')), findsOneWidget);
    expect(find.byKey(const Key('grp_project_support')), findsNothing);
    await t.tap(find.byKey(const Key('grp_project_approve')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls.last, 'decide:1:true');

    await _detail(t, api, GroupMe.fromJson(_me(rights: <String>[])), 1);
    expect(find.byKey(const Key('grp_project_support')), findsNothing);
    expect(find.byKey(const Key('grp_project_approve')), findsNothing);
    expect(find.byKey(const Key('grp_project_progress')), findsNothing);
    await t.pump(const Duration(seconds: 6)); // the success banner's timer
  });

  testWidgets('nobody reviews or decides their own proposal; the proposer may withdraw it', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(<Map<String, dynamic>>[_project(1, proposedBy: 1)]);
    await _detail(t, api, GroupMe.fromJson(_me(rights: <String>['view_projects', 'recommend_projects', 'approve_projects'])), 1);

    expect(find.byKey(const Key('grp_project_support')), findsNothing);
    expect(find.byKey(const Key('grp_project_approve')), findsNothing);
    expect(find.byKey(const Key('grp_project_withdraw')), findsOneWidget);
  });

  testWidgets('the Projects Chairperson logs progress, names a manager and closes a running project', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(<Map<String, dynamic>>[_project(1, status: 'active', progress: 40)]);
    await _detail(t, api, GroupMe.fromJson(_me(rights: <String>['view_projects', 'manage_projects', 'recommend_projects'])), 1);

    expect(find.byKey(const Key('grp_project_manager')), findsOneWidget);
    expect(find.byKey(const Key('grp_project_complete')), findsOneWidget);
    expect(find.byKey(const Key('grp_project_cancel')), findsOneWidget);
    expect(find.byKey(const Key('grp_project_approve')), findsNothing);
    await t.tap(find.byKey(const Key('grp_project_progress')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_project_note')), 'Roof done');
    await t.pump();
    await t.tap(find.byKey(const Key('grp_project_progress_save')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['progress:1:40:Roof done']);
    await t.pump(const Duration(seconds: 6)); // the success banner's timer
  });
}
