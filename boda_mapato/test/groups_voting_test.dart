import 'dart:typed_data';

import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_voting_models.dart';
import 'package:boda_mapato/modules/groups/screens/voting_detail_screen.dart';
import 'package:boda_mapato/modules/groups/screens/voting_form_screen.dart';
import 'package:boda_mapato/modules/groups/screens/voting_report_screen.dart';
import 'package:boda_mapato/modules/groups/screens/voting_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _opt(final int id, final String label, {final String? role, final int? memberId, final String? description}) =>
    <String, dynamic>{'id': id, 'label': label, 'role': role, 'member_id': memberId, 'description': description};

Map<String, dynamic> _voting(
  final int id, {
  final String kind = 'election',
  final String title = 'Uchaguzi wa Mwenyekiti',
  final String? position = 'Mwenyekiti',
  final String? series = 'Uchaguzi 2026',
  final String category = 'leadership',
  final String status = 'open',
  final String state = 'pending',
  final bool canVote = true,
  final bool secret = true,
  final bool allowChange = false,
  final int? choice,
  final List<String> buckets = const <String>['active', 'pending'],
  final Map<String, dynamic>? results,
  final String? decision,
  final bool manage = false,
  final bool report = false,
}) =>
    <String, dynamic>{
      'id': id, 'reference': 'VT-$id', 'series': series, 'category': category, 'kind': kind, 'title': title, 'description': 'Maelezo ya kura namba $id.', 'position': kind == 'election' ? position : null,
      'target': kind == 'election' ? '$position ($series)' : title, 'eligibility': 'active', 'quorum_percent': 50, 'threshold_percent': 66.7, 'secret': secret, 'allow_change': allowChange,
      'show_progress': true, 'results_visibility': 'after_close', 'opens_at': '2026-05-02 08:00:00', 'closes_at': '2026-05-09 18:00:00', 'status': status, 'eligible_count': 20,
      'results_published': false,
      'my': <String, dynamic>{'eligible': state != 'not_eligible', 'voted': state == 'voted', 'state': state, 'can_vote': canVote, 'choice': choice},
      'buckets': buckets,
      'options': kind == 'election'
          ? <Map<String, dynamic>>[_opt(id * 10 + 1, 'Asha Juma', memberId: 1, description: 'Mweka hazina wa zamani'), _opt(id * 10 + 2, 'Juma Hamisi', memberId: 2), _opt(id * 10 + 3, 'Rehema Salim', memberId: 3)]
          : <Map<String, dynamic>>[_opt(id * 10 + 1, 'Approve', role: 'approve'), _opt(id * 10 + 2, 'Reject', role: 'reject'), _opt(id * 10 + 3, 'Abstain', role: 'abstain')],
      'can_manage': manage, 'can_report': report,
      'progress': <String, dynamic>{'turnout': 7, 'eligible': 20, 'percent': 35},
      'results': results, 'decision': decision,
    };

class _Api extends GroupsApi {
  _Api(this.rows);

  List<Map<String, dynamic>> rows;
  final List<(int, int)> voted = <(int, int)>[];
  Map<String, dynamic>? created;
  final List<String> actions = <String>[];
  List<Map<String, dynamic>> notices = <Map<String, dynamic>>[];
  Map<String, dynamic>? reportJson;

  @override
  Future<List<GroupVoting>> votings() async => <GroupVoting>[for (final Map<String, dynamic> r in rows) GroupVoting.fromJson(r)];

  @override
  Future<GroupVoting> voting(final int id) async => GroupVoting.fromJson(rows.firstWhere((final Map<String, dynamic> r) => r['id'] == id));

  @override
  Future<GroupVoting> vote(final int id, final int optionId) async {
    voted.add((id, optionId));
    final Map<String, dynamic> r = rows.firstWhere((final Map<String, dynamic> x) => x['id'] == id);
    r['my'] = <String, dynamic>{'eligible': true, 'voted': true, 'state': 'voted', 'can_vote': false, 'choice': r['secret'] == true ? null : optionId};
    r['buckets'] = <String>['active'];
    return GroupVoting.fromJson(r);
  }

  @override
  Future<GroupVoting> createVoting(final Map<String, dynamic> body) async {
    created = body;
    return GroupVoting.fromJson(_voting(99, kind: body['kind'] as String, title: body['title'] as String, position: body['position'] as String?, status: 'draft', state: 'draft', canVote: false, buckets: <String>['draft']));
  }

  @override
  Future<GroupVoting> votingAction(final int id, final String action, {final Map<String, dynamic> body = const <String, dynamic>{}}) async {
    actions.add(action);
    return GroupVoting.fromJson(_voting(id, status: action == 'publish' ? 'open' : 'open'));
  }

  @override
  Future<(List<GroupNotice>, int)> notifications() async =>
      (<GroupNotice>[for (final Map<String, dynamic> n in notices) GroupNotice.fromJson(n)], notices.where((final Map<String, dynamic> n) => n['read'] != true).length);

  @override
  Future<void> readNotifications({final List<int>? ids, final bool all = false}) async {}

  @override
  Future<VotingReport> votingReport(final int id) async => VotingReport.fromJson(reportJson!);

  @override
  Future<Uint8List> votingReportCsv(final int id) async => Uint8List(0);
}

GroupMe _me(final List<String> rights) => GroupMe.fromJson(<String, dynamic>{
      'rights': rights,
      'member': <String, dynamic>{'id': 1, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active', 'member_number': 'UWM-0001'},
      'group': <String, dynamic>{'name': 'MEG'},
    });

Future<void> _pump(final WidgetTester t, final Widget home, {final double width = 411}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = Size(width, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: Size(width, 3000), minTextAdapt: true, builder: (_, __) => MaterialApp(home: KeyedSubtree(key: UniqueKey(), child: home))),
    ),
  );
  await t.pumpAndSettle();
}

/// A filter chip may sit partly beyond the screen (the test font is wide): slide it into view, then tap it.
Future<void> _tapChip(final WidgetTester t, final String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.pumpAndSettle();
  final Rect r = t.getRect(find.byKey(Key(key)));
  // Not at its very start (an arrow may sit there) and not beyond the screen.
  await t.tapAt(Offset((r.left + 80).clamp(60, 380).toDouble(), r.center.dy));
  await t.pumpAndSettle();
}

Map<String, dynamic> _results(final String decision) => <String, dynamic>{
      'options': <Map<String, dynamic>>[
        <String, dynamic>{'option_id': 11, 'label': 'Asha Juma', 'member_id': 1, 'role': null, 'votes': 5, 'percent': 62.5},
        <String, dynamic>{'option_id': 12, 'label': 'Juma Hamisi', 'member_id': 2, 'role': null, 'votes': 3, 'percent': 37.5},
        <String, dynamic>{'option_id': 13, 'label': 'Rehema Salim', 'member_id': 3, 'role': null, 'votes': 0, 'percent': 0},
      ],
      'ballots': 8, 'turnout': 8, 'eligible': 20, 'participation_percent': 40, 'quorum_percent': 30, 'quorum_met': true, 'threshold_percent': 50, 'decision': decision, 'winner_option_id': 11,
    };

void main() {
  testWidgets('the dashboard groups votings under their own series, names each position with its candidates, and says where I stand in each', (final WidgetTester t) async {
    final _Api api = _Api(<Map<String, dynamic>>[
      _voting(1),
      _voting(2, title: 'Uchaguzi wa Mweka hazina', position: 'Mweka hazina', state: 'voted', buckets: <String>['active']),
      _voting(3, kind: 'decision', title: 'Kuidhinisha bajeti ya mwaka', category: 'financial', series: null, status: 'scheduled', state: 'not_open', canVote: false, buckets: <String>['upcoming']),
    ]);
    await _pump(t, Scaffold(body: VotingScreen(me: _me(<String>[]), api: api, onChanged: () async {})));

    expect(find.text('Uchaguzi 2026'), findsOneWidget, reason: 'the two elections sit under their own series');
    expect(find.text('Financial decision'), findsOneWidget, reason: 'an agenda sits under its kind of matter');
    expect(find.text('Mwenyekiti'), findsOneWidget);
    expect(find.text('Mweka hazina'), findsOneWidget);
    expect(find.textContaining('Candidates: Asha Juma · Juma Hamisi · Rehema Salim'), findsNWidgets(2));
    expect(find.text('Vote now'), findsOneWidget);
    expect(find.text('Voted'), findsOneWidget);
    expect(find.text('Not open yet'), findsOneWidget);

    // Filters: only what waits for my vote.
    await _tapChip(t, 'grp_vote_filter_pending');
    await t.pumpAndSettle();
    expect(find.text('Mwenyekiti'), findsOneWidget);
    expect(find.text('Mweka hazina'), findsNothing);
    await _tapChip(t, 'grp_vote_filter_upcoming');
    await t.pumpAndSettle();
    expect(find.text('Kuidhinisha bajeti ya mwaka'), findsOneWidget);

    // My activity: pending and voted, no upcoming.
    await t.tap(find.text('Mine'));
    await t.pumpAndSettle();
    expect(find.text('Kuidhinisha bajeti ya mwaka'), findsNothing);
    await _tapChip(t, 'grp_vote_filter_all');
    await t.pumpAndSettle();
    expect(find.text('Mweka hazina'), findsOneWidget);
    expect(find.text('Mwenyekiti'), findsOneWidget);
  });

  testWidgets('electing: pick a candidate, review, confirm the exact position and name, then it shows as voted', (final WidgetTester t) async {
    final _Api api = _Api(<Map<String, dynamic>>[_voting(1)]);
    await _pump(t, VotingDetailScreen(api: api, me: _me(<String>[]), votingId: 1));

    expect(find.byKey(const Key('grp_vote_target')), findsOneWidget);
    expect(find.text('Mwenyekiti'), findsWidgets);
    expect(find.byKey(const Key('grp_vote_candidates')), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('grp_vote_review'))).onPressed, isNull, reason: 'nothing chosen yet');

    await t.ensureVisible(find.byKey(const Key('grp_vote_opt_12')));
    await t.tap(find.byKey(const Key('grp_vote_opt_12')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('grp_vote_review')));
    await t.tap(find.byKey(const Key('grp_vote_review')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('grp_confirm')), findsOneWidget);
    expect(find.textContaining('Voting: Mwenyekiti (Uchaguzi 2026)'), findsOneWidget);
    expect(find.textContaining('Your choice: Juma Hamisi'), findsOneWidget);
    expect(api.voted, isEmpty, reason: 'nothing is sent before the Yes');
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();

    expect(api.voted, <(int, int)>[(1, 12)]);
    expect(find.byKey(const Key('grp_vote_done')), findsOneWidget);
    expect(find.byKey(const Key('grp_vote_candidates')), findsNothing);
    expect(find.text('Voted'), findsWidgets);
    expect(find.text('You have voted. Your vote is kept secret.'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('an agenda shows approve, reject and abstain in their own colours and asks a confirmation', (final WidgetTester t) async {
    final _Api api = _Api(<Map<String, dynamic>>[_voting(3, kind: 'decision', title: 'Kuidhinisha bajeti ya mwaka', category: 'financial', series: null)]);
    await _pump(t, VotingDetailScreen(api: api, me: _me(<String>[]), votingId: 3));

    expect(find.byKey(const Key('grp_vote_agenda')), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Abstain'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('grp_vote_opt_32')));
    await t.tap(find.byKey(const Key('grp_vote_opt_32')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('grp_vote_review')));
    await t.tap(find.byKey(const Key('grp_vote_review')));
    await t.pumpAndSettle();
    expect(find.textContaining('Voting: Kuidhinisha bajeti ya mwaka'), findsOneWidget);
    expect(find.textContaining('Your choice: Reject'), findsOneWidget);
    expect(find.textContaining('You cannot change it after you submit.'), findsOneWidget);
    // No: nothing is sent.
    await t.tap(find.byKey(const Key('grp_confirm_no')));
    await t.pumpAndSettle();
    expect(api.voted, isEmpty);
  });

  testWidgets('having voted, an open ballot shows my choice and may allow a change; a member who may not vote is told why', (final WidgetTester t) async {
    final _Api api = _Api(<Map<String, dynamic>>[
      _voting(1, state: 'voted', canVote: true, secret: false, allowChange: true, choice: 12),
      _voting(2, state: 'not_eligible', canVote: false),
      _voting(4, status: 'scheduled', state: 'not_open', canVote: false, buckets: <String>['upcoming']),
    ]);
    await _pump(t, VotingDetailScreen(api: api, me: _me(<String>[]), votingId: 1));
    expect(find.text('You voted: Juma Hamisi'), findsOneWidget);
    expect(find.byKey(const Key('grp_vote_change')), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('grp_vote_change')));
    await t.tap(find.byKey(const Key('grp_vote_change')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_vote_candidates')), findsOneWidget, reason: 'the candidates come back to choose again');

    await _pump(t, VotingDetailScreen(api: api, me: _me(<String>[]), votingId: 2));
    expect(find.text('You may not vote in this one.'), findsOneWidget);
    expect(find.byKey(const Key('grp_vote_review')), findsNothing);

    await _pump(t, VotingDetailScreen(api: api, me: _me(<String>[]), votingId: 4));
    expect(find.textContaining('Voting opens 02/05/2026 08:00'), findsOneWidget);
  });

  testWidgets('the result of one voting shows its own votes and the decision, only when the server sends it', (final WidgetTester t) async {
    final _Api api = _Api(<Map<String, dynamic>>[
      _voting(1, status: 'closed', state: 'voted', canVote: false, buckets: <String>['completed'], results: _results('winner'), decision: 'winner'),
      _voting(2, status: 'open'),
    ]);
    await _pump(t, VotingDetailScreen(api: api, me: _me(<String>[]), votingId: 1));
    expect(find.byKey(const Key('grp_vote_decision')), findsOneWidget);
    expect(find.text('A winner'), findsOneWidget);
    expect(find.byKey(const Key('grp_vote_result_11')), findsOneWidget);
    expect(find.text('5  ·  62.5%'), findsOneWidget);
    expect(find.text('3  ·  37.5%'), findsOneWidget);

    await _pump(t, VotingDetailScreen(api: api, me: _me(<String>[]), votingId: 2));
    expect(find.byKey(const Key('grp_vote_decision')), findsNothing, reason: 'hidden while it runs');
    expect(find.byKey(const Key('grp_vote_progress')), findsOneWidget);
  });

  testWidgets('officers see a Manage button; a member does not', (final WidgetTester t) async {
    final _Api api = _Api(<Map<String, dynamic>>[_voting(1, status: 'draft', state: 'draft', canVote: false, buckets: <String>['draft'], manage: true, report: true)]);
    await _pump(t, VotingDetailScreen(api: api, me: _me(<String>['manage_votings']), votingId: 1));
    expect(find.byKey(const Key('grp_vote_manage')), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_vote_manage')));
    await t.pumpAndSettle();
    expect(find.text('Publish'), findsOneWidget);
    expect(find.text('Edit the draft'), findsOneWidget);
    await t.tap(find.text('Publish'));
    await t.pumpAndSettle();
    expect(find.textContaining('20 voters will be told'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.actions, <String>['publish']);

    final _Api plain = _Api(<Map<String, dynamic>>[_voting(1)]);
    await _pump(t, VotingDetailScreen(api: plain, me: _me(<String>[]), votingId: 1));
    expect(find.byKey(const Key('grp_vote_manage')), findsNothing);
  });

  testWidgets('preparing an election needs a position and two candidates; a secret ballot cannot allow changes; it is saved as a draft', (final WidgetTester t) async {
    final _Api api = _Api(<Map<String, dynamic>>[]);
    await _pump(t, VotingFormScreen(api: api));

    await t.tap(find.byKey(const Key('grp_vf_save')));
    await t.pumpAndSettle();
    expect(find.textContaining('Give the voting a title'), findsOneWidget);

    await t.enterText(find.byKey(const Key('grp_vf_title')), 'Uchaguzi wa Katibu');
    await t.tap(find.byKey(const Key('grp_vf_save')));
    await t.pumpAndSettle();
    expect(find.textContaining('Give the position being elected'), findsOneWidget);

    await t.enterText(find.byKey(const Key('grp_vf_position')), 'Katibu');
    await t.tap(find.byKey(const Key('grp_vf_save')));
    await t.pumpAndSettle();
    expect(find.textContaining('at least two candidates'), findsOneWidget);

    await t.enterText(find.descendant(of: find.byKey(const Key('grp_vf_candidate_0')), matching: find.byType(TextField)).first, 'Neema Swai');
    await t.enterText(find.descendant(of: find.byKey(const Key('grp_vf_candidate_1')), matching: find.byType(TextField)).first, 'Hassan Said');
    // The secret ballot is on, so changing a vote cannot be switched on.
    expect(t.widget<SwitchListTile>(find.byKey(const Key('grp_vf_change'))).onChanged, isNull);
    await t.ensureVisible(find.byKey(const Key('grp_vf_save')));
    await t.tap(find.byKey(const Key('grp_vf_save')));
    await t.pumpAndSettle();

    expect(api.created?['kind'], 'election');
    expect(api.created?['position'], 'Katibu');
    expect(api.created?['secret'], true);
    expect(api.created?['allow_change'], false);
    expect((api.created?['options'] as List).length, 2);
    expect(api.actions, isEmpty, reason: 'a draft is not published');
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('an agenda needs no candidates; Save and publish asks a Yes first', (final WidgetTester t) async {
    final _Api api = _Api(<Map<String, dynamic>>[]);
    await _pump(t, VotingFormScreen(api: api));
    await t.tap(find.text('Agenda'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_vf_add_candidate')), findsNothing);
    await t.enterText(find.byKey(const Key('grp_vf_title')), 'Kuidhinisha bajeti');
    await t.ensureVisible(find.byKey(const Key('grp_vf_publish')));
    await t.tap(find.byKey(const Key('grp_vf_publish')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_confirm')), findsOneWidget);
    expect(api.created, isNull, reason: 'nothing is sent before the Yes');
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.created?['kind'], 'decision');
    expect(api.actions, <String>['publish']);
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('the report of a secret ballot lists who took part, never what they chose', (final WidgetTester t) async {
    final Map<String, dynamic> v = _voting(1, status: 'closed', state: 'voted', canVote: false, results: _results('winner'), decision: 'winner', report: true);
    final _Api api = _Api(<Map<String, dynamic>>[v])
      ..reportJson = <String, dynamic>{
        'voting': v, 'results': _results('winner'), 'decision': 'winner', 'secret': true, 'final': true, 'individual': null,
        'turnout': <Map<String, dynamic>>[<String, dynamic>{'member_number': 'UWM-0002', 'name': 'Juma Hamisi', 'date': '2026-05-03'}],
        'not_voted': <Map<String, dynamic>>[<String, dynamic>{'member_number': 'UWM-0003', 'name': 'Rehema Salim'}],
      };
    await _pump(t, VotingReportScreen(api: api, votingId: 1));
    expect(find.text('Who has voted (1)'), findsOneWidget);
    expect(find.text('Not yet voted (1)'), findsOneWidget);
    expect(find.byKey(const Key('grp_vote_secret_note')), findsOneWidget);
    expect(find.byKey(const Key('grp_vote_export')), findsOneWidget);
  });

  testWidgets('the report of an open ballot that has closed lists who chose what', (final WidgetTester t) async {
    final Map<String, dynamic> v = _voting(1, status: 'closed', state: 'voted', canVote: false, secret: false, results: _results('winner'), decision: 'winner', report: true);
    final _Api api = _Api(<Map<String, dynamic>>[v])
      ..reportJson = <String, dynamic>{
        'voting': v, 'results': _results('winner'), 'decision': 'winner', 'secret': false, 'final': true,
        'individual': <Map<String, dynamic>>[<String, dynamic>{'member_number': 'UWM-0002', 'name': 'Juma Hamisi', 'option': 'Asha Juma', 'date': '2026-05-03'}],
        'turnout': <Map<String, dynamic>>[], 'not_voted': <Map<String, dynamic>>[],
      };
    await _pump(t, VotingReportScreen(api: api, votingId: 1));
    expect(find.byKey(const Key('grp_vote_secret_note')), findsNothing);
    expect(find.text('Juma Hamisi'), findsWidgets);
    expect(find.text('Asha Juma'), findsWidgets);
  });

  testWidgets('a notice opens that exact voting item, not the general dashboard', (final WidgetTester t) async {
    final _Api api = _Api(<Map<String, dynamic>>[_voting(1), _voting(2, title: 'Uchaguzi wa Mweka hazina', position: 'Mweka hazina')])
      ..notices = <Map<String, dynamic>>[
        <String, dynamic>{'id': 5, 'kind': 'voting_open', 'title': 'Kura ya Mweka hazina imefunguliwa', 'title_en': 'Voting on Treasurer is now open', 'body': 'Piga kura.', 'body_en': 'Cast your vote.', 'link_type': 'voting', 'link_id': 2, 'read': false, 'created_at': '2026-05-03'},
        <String, dynamic>{'id': 4, 'kind': 'voting_open', 'title': 'Kura ya Mwenyekiti imefunguliwa', 'title_en': 'Voting on Chairperson is now open', 'body': null, 'body_en': null, 'link_type': 'voting', 'link_id': 1, 'read': true, 'created_at': '2026-05-03'},
      ];
    await _pump(t, VotingNoticesScreen(api: api, me: _me(<String>[])));
    expect(find.text('Voting on Treasurer is now open'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_notice_5')));
    await t.pumpAndSettle();
    expect(find.byType(VotingDetailScreen), findsOneWidget);
    expect(find.text('Mweka hazina'), findsWidgets, reason: 'it is the treasurer voting, not the chairperson one');
    expect(find.text('Mwenyekiti'), findsNothing);
  });

  testWidgets('a narrow phone shows the dashboard without overflowing', (final WidgetTester t) async {
    final _Api api = _Api(<Map<String, dynamic>>[_voting(1), _voting(3, kind: 'decision', title: 'Kuidhinisha mabadiliko ya michango ya wanachama', category: 'policy', series: null)]);
    await _pump(t, Scaffold(body: VotingScreen(me: _me(<String>['manage_votings']), api: api, onChanged: () async {})), width: 320);
    expect(t.takeException(), isNull);
    await _pump(t, VotingDetailScreen(api: api, me: _me(<String>['manage_votings']), votingId: 1), width: 320);
    expect(t.takeException(), isNull);
  });
}
