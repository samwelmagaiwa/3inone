import 'package:boda_mapato/modules/groups/models/group_governance_models.dart';
import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/dividends_screen.dart';
import 'package:boda_mapato/modules/groups/screens/groups_home.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _run({final String status = 'draft'}) => <String, dynamic>{
      'id': 3, 'period_from': '2026-01-01', 'period_to': '2026-12-31', 'profit_pool': 10000, 'base': 'closing', 'method': 'rate', 'rate': 2, 'total': 3000,
      'status': status, 'note': 'AGM 2026', 'prepared_by_name': 'Mweka Hazina',
      'lines': <dynamic>[
        <String, dynamic>{'member_id': 5, 'name': 'Asha Juma', 'base': 100000, 'amount': 2000},
        <String, dynamic>{'member_id': 6, 'name': 'Juma Ali', 'base': 50000, 'amount': 1000},
      ],
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
  Future<List<GroupMeeting>> meetings() async => <GroupMeeting>[
        GroupMeeting.fromJson(<String, dynamic>{'id': 8, 'title': 'Kikao cha mwezi', 'starts_at': '2030-05-10 14:00:00', 'status': 'scheduled', 'venue': 'Ukumbi'}),
      ];

  @override
  Future<List<GroupAnnouncement>> announcements() async => <GroupAnnouncement>[
        GroupAnnouncement.fromJson(<String, dynamic>{'id': 1, 'title': 'Karibuni', 'body': 'Kikao Jumamosi', 'category': 'general', 'audience': 'all'}),
      ];

  @override
  Future<List<GroupMessage>> texts() async => const <GroupMessage>[];

  @override
  Future<void> callMeeting(final Map<String, dynamic> body) async => calls.add('call:${body['title']}:${body['notify']}');

  @override
  Future<(int, int, int)> estimateText({required final String audience, required final String body, final List<int>? memberIds}) async => (22, 1, 22);

  @override
  Future<void> sendText({required final String audience, required final String body, final List<int>? memberIds}) async => calls.add('text:$audience:$body');

  @override
  Future<List<GroupDividendRun>> dividendRuns() async => const <GroupDividendRun>[];

  @override
  Future<GroupDividendRun> prepareDividend(final Map<String, dynamic> body) async {
    calls.add('prepare:${body['base']}:${body['method']}:${body['rate']}:${body['profit_pool']}');
    return GroupDividendRun.fromJson(_run());
  }

  @override
  Future<GroupDividendRun> dividendRun(final int id) async => GroupDividendRun.fromJson(_run());

  @override
  Future<GroupDividendRun> postDividend(final int id) async {
    calls.add('post:$id');
    return GroupDividendRun.fromJson(_run(status: 'posted'));
  }
}

Map<String, dynamic> _me({final List<String> rights = const <String>[], final String? office}) => <String, dynamic>{
      'is_owner': false,
      'rights': rights,
      'member': <String, dynamic>{'id': 1, 'full_name': 'Neema Mussa', 'phone': '0712000001', 'status': 'active', 'office': office, 'member_number': 'MEG-0001'},
      'settings': <String, dynamic>{'joining_fee': 0, 'share_amount': 0},
      'waiting': <String, int>{},
      'next_meeting': <String, dynamic>{'id': 8, 'title': 'Kikao cha mwezi', 'starts_at': '2030-05-10 14:00:00', 'venue': 'Ukumbi'},
      'notices': 1,
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
  testWidgets('every member sees the next meeting and the notices on Home, and opens them', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me());
    await _pump(t, GroupsHome(api: api));

    expect(find.byKey(const Key('grp_next_meeting')), findsOneWidget);
    expect(find.text('10/05/2030 14:00 · Ukumbi'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_notices')));
    await t.pumpAndSettle();
    await t.tap(find.text('Notices'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_notice_1')), findsOneWidget);
    expect(find.byKey(const Key('grp_notice_new')), findsNothing, reason: 'a plain member posts nothing');
  });

  testWidgets('the chair calls a meeting and is told the texts use the group SMS', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(rights: <String>['view_members', 'call_meetings', 'record_meetings', 'post_announcements', 'send_texts'], office: 'mwenyekiti'));
    await _pump(t, GroupsHome(api: api));
    await t.tap(find.byKey(const Key('grp_next_meeting')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('grp_meeting_call')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_meeting_title')), 'Mkutano Mkuu');
    await t.tap(find.byKey(const Key('grp_meeting_notify')));
    await t.pump();
    await t.tap(find.byKey(const Key('grp_meeting_next')));
    await t.pumpAndSettle();
    expect(find.textContaining('Members will be texted'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['call:Mkutano Mkuu:true']);
    await _banner(t);
  });

  testWidgets('a text shows how many people and SMS it takes before it goes', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(rights: <String>['view_members', 'send_texts'], office: 'katibu'));
    await _pump(t, GroupsHome(api: api));
    await t.tap(find.byKey(const Key('grp_next_meeting')));
    await t.pumpAndSettle();
    await t.tap(find.text('Texts'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('grp_text_new')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('grp_text_body')), 'Kikao kesho saa nane.');
    await t.tap(find.byKey(const Key('grp_text_check')));
    await t.pumpAndSettle();
    expect(find.text('22 people · 22 SMS'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_text_send')));
    await t.pumpAndSettle();
    expect(find.textContaining('All members: 22 people · 22 SMS'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['text:all:Kikao kesho saa nane.']);
    await _banner(t);
  });

  testWidgets('the treasurer works out a dividend as a draft; the chair credits it after a Yes', (final WidgetTester t) async {
    final _FakeApi api = _FakeApi(_me(rights: <String>['view_finance', 'prepare_dividends'], office: 'mweka_hazina'));
    await _pump(t, DividendsScreen(api: api, me: GroupMe.fromJson(_me(rights: <String>['view_finance', 'prepare_dividends'], office: 'mweka_hazina'))));

    await t.tap(find.byKey(const Key('grp_dividend_prepare')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('grp_div_send')));
    await t.tap(find.byKey(const Key('grp_div_send')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_div_error')), findsOneWidget, reason: 'no profit, rate or decision yet');
    await t.enterText(find.byKey(const Key('grp_div_pool')), '10000');
    await t.enterText(find.byKey(const Key('grp_div_rate')), '2');
    await t.enterText(find.byKey(const Key('grp_div_note')), 'AGM 2026');
    await t.ensureVisible(find.byKey(const Key('grp_div_send')));
    await t.tap(find.byKey(const Key('grp_div_send')));
    await t.pumpAndSettle();
    expect(api.calls, <String>['prepare:closing:rate:2.0:10000.0']);
    expect(find.text('Asha Juma'), findsOneWidget);
    expect(find.byKey(const Key('grp_dividend_post')), findsNothing, reason: 'the treasurer does not post');
    expect(find.byKey(const Key('grp_dividend_discard')), findsOneWidget);

    final List<String> chair = <String>['view_finance', 'approve_dividends'];
    final _FakeApi chairApi = _FakeApi(_me(rights: chair, office: 'mwenyekiti'));
    await t.pumpWidget(const SizedBox());
    await _pump(t, DividendRunScreen(api: chairApi, me: GroupMe.fromJson(_me(rights: chair, office: 'mwenyekiti')), runId: 3));
    await t.tap(find.byKey(const Key('grp_dividend_post')));
    await t.pumpAndSettle();
    expect(find.textContaining('cannot be paid again'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();
    expect(chairApi.calls, <String>['post:3']);
    await _banner(t);
  });
}
