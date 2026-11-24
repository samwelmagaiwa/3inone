import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_voting_models.dart';
import 'package:boda_mapato/modules/groups/screens/community_screen.dart';
import 'package:boda_mapato/modules/groups/screens/voting_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends GroupsApi {
  final List<int> read = <int>[];

  @override
  Future<(List<GroupNotice>, int)> notifications() async => (
        <GroupNotice>[
          GroupNotice.fromJson(<String, dynamic>{
            'id': 1, 'kind': 'member_request', 'title': 'Ombi jipya la uanachama: Neema New', 'title_en': 'New membership request: Neema New',
            'body': 'Amesajiliwa na Asha Juma.', 'body_en': 'Registered by Asha Juma. Waiting for the management: one approval is enough.',
            'link_type': 'member', 'link_id': 42, 'read': false, 'created_at': '2026-11-24 09:00:00',
          }),
          GroupNotice.fromJson(<String, dynamic>{
            'id': 2, 'kind': 'member_approved', 'title': 'Juma New: tayari imeidhinishwa na Katibu', 'title_en': 'Juma New: already approved by Katibu',
            'body': 'Hakuna haja ya kuidhinisha tena.', 'body_en': 'Nothing more to approve. The next steps go on as usual.',
            'link_type': 'member', 'link_id': 43, 'read': true, 'created_at': '2026-11-24 08:00:00',
          }),
        ],
        1,
      );

  @override
  Future<void> readNotifications({final List<int>? ids, final bool all = false}) async {
    read.addAll(ids ?? const <int>[]);
  }
}

GroupMe _ordinary() => GroupMe.fromJson(<String, dynamic>{
      'rights': <String>[],
      'member': <String, dynamic>{'id': 5, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active'},
      'group': <String, dynamic>{'name': 'MEG'},
    });

Future<void> _pump(final WidgetTester t, final Widget child, {final String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(lang);
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 1400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: KeyedSubtree(key: UniqueKey(), child: child))),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the notices screen shows a membership request waiting, and the one already approved by someone else, in both languages', (final WidgetTester t) async {
    await _pump(t, VotingNoticesScreen(api: _Api(), me: _ordinary()));
    expect(find.text('Notices'), findsOneWidget);
    expect(find.text('New membership request: Neema New'), findsOneWidget);
    expect(find.text('Juma New: already approved by Katibu'), findsOneWidget);
    expect(find.textContaining('one approval is enough'), findsOneWidget);

    await _pump(t, VotingNoticesScreen(api: _Api(), me: _ordinary()), lang: 'sw');
    expect(find.text('Arifa'), findsOneWidget);
    expect(find.text('Juma New: tayari imeidhinishwa na Katibu'), findsOneWidget);
    await LocalizationService.instance.changeLanguage('en');
  });

  testWidgets('opening a notice marks it read (a member without the right to see members only reads it)', (final WidgetTester t) async {
    final _Api api = _Api();
    await _pump(t, VotingNoticesScreen(api: api, me: _ordinary()));
    await t.tap(find.byKey(const Key('grp_notice_1')));
    await t.pumpAndSettle();
    expect(api.read, <int>[1]);
    expect(find.text('Notices'), findsOneWidget, reason: 'no file to open, so it stays here');
  });

  test('the notices to the leaders are called Management (Uongozi), the old "officers" value too', () {
    expect(audienceLabel(sw: false, audience: 'leaders'), 'Management');
    expect(audienceLabel(sw: false, audience: 'officers'), 'Management');
    expect(audienceLabel(sw: true, audience: 'leaders'), 'Uongozi');
  });
}
