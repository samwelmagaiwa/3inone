import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/member_form_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_places.dart';

class _Api extends GroupsApi {
  Map<String, dynamic>? sent;

  @override
  Future<GroupMemberFile> createMember(final Map<String, dynamic> body) async {
    sent = body;
    throw Exception('stop here');
  }
}

GroupMe _me() => GroupMe.fromJson(<String, dynamic>{
      'rights': <String>['manage_members'],
      'member': <String, dynamic>{'id': 1, 'full_name': 'Katibu', 'phone': '0713000001', 'status': 'active', 'office': 'katibu'},
      'group': <String, dynamic>{'name': 'MEG'},
    });

Future<void> _choose(final WidgetTester t, final int level, final String id) async {
  final Finder field = find.byKey(ValueKey<String>('place_select_$level'));
  await t.ensureVisible(field);
  await t.tap(field);
  await t.pumpAndSettle();
  await t.tap(find.byKey(ValueKey<String>('place_option_$id')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a member is registered with an address chosen from region down to street, the way the other services do', (final WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage('en');
    t.view.physicalSize = const Size(411, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final _Api api = _Api();
    await t.pumpWidget(
      ChangeNotifierProvider<LocalizationService>.value(
        value: LocalizationService.instance,
        child: ScreenUtilInit(
          designSize: const Size(411, 3000),
          minTextAdapt: true,
          builder: (_, __) => MaterialApp(home: MemberFormScreen(api: api, me: _me(), placeSource: FakePlaces())),
        ),
      ),
    );
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const Key('grp_f_name')), 'Asha Juma');
    await t.enterText(find.byKey(const Key('grp_f_phone')), '0713000009');
    await _choose(t, 0, '1');
    await _choose(t, 1, '11');
    await _choose(t, 2, '111');
    await _choose(t, 3, '1111');

    await t.ensureVisible(find.byKey(const Key('grp_f_save')));
    await t.tap(find.byKey(const Key('grp_f_save')));
    await t.pumpAndSettle();
    if (find.byKey(const Key('grp_confirm_yes')).evaluate().isNotEmpty) {
      await t.tap(find.byKey(const Key('grp_confirm_yes')));
      await t.pumpAndSettle();
    }

    expect(api.sent?['region'], 'Dar es Salaam');
    expect(api.sent?['district'], 'Kinondoni');
    expect(api.sent?['ward'], 'Mikocheni');
    expect(api.sent?['street'], 'Mikocheni A');
  });
}
