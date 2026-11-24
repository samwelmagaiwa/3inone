import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/models/group_records_models.dart';
import 'package:boda_mapato/modules/groups/screens/member_form_screen.dart';
import 'package:boda_mapato/modules/groups/screens/records_screens.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_places.dart';

class _Api extends GroupsApi {
  _Api({this.smsSent = true, this.resendWorks = true});

  final bool smsSent;
  final bool resendWorks;
  Map<String, dynamic>? sent;
  final List<int> resent = <int>[];

  @override
  Future<(GroupInvitation?, List<GroupInvitation>)> invitations() async => (null, <GroupInvitation>[]);

  @override
  Future<({GroupMemberFile file, bool smsSent})> registerMember(final Map<String, dynamic> body) async {
    sent = body;
    return (
      file: GroupMemberFile.fromJson(<String, dynamic>{
        'member': <String, dynamic>{'id': 42, 'full_name': body['full_name'], 'phone': body['phone'], 'status': 'submitted', 'application_ref': 'APP-42'},
      }),
      smsSent: smsSent,
    );
  }

  @override
  Future<bool> resendOtp(final int memberId) async {
    resent.add(memberId);
    return resendWorks;
  }
}

/// An ordinary member: no office, no right to manage members.
GroupMe _ordinary() => GroupMe.fromJson(<String, dynamic>{
      'rights': <String>[],
      'member': <String, dynamic>{'id': 5, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active', 'member_number': 'UWM-0005'},
      'group': <String, dynamic>{'name': 'MEG'},
    });

GroupMe _approver() => GroupMe.fromJson(<String, dynamic>{
      'rights': <String>['manage_members', 'approve_members'],
      'member': <String, dynamic>{'id': 1, 'full_name': 'Katibu', 'phone': '0713000009', 'status': 'active', 'office': 'katibu'},
      'group': <String, dynamic>{'name': 'MEG'},
    });

Future<void> _pump(final WidgetTester t, final Widget child) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 3000), minTextAdapt: true, builder: (_, __) => MaterialApp(home: KeyedSubtree(key: UniqueKey(), child: child))),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _fillAndSave(final WidgetTester t, {final String phone = '0715 000 111'}) async {
  await t.enterText(find.byKey(const Key('grp_f_name')), 'Neema Mussa');
  await t.enterText(find.byKey(const Key('grp_f_phone')), phone);
  await t.ensureVisible(find.byKey(const Key('grp_f_save')));
  await t.tap(find.byKey(const Key('grp_f_save')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('every member, whatever the office, finds "Register a member" at the top of the invite screen and it opens the form', (final WidgetTester t) async {
    await _pump(t, InviteScreen(api: _Api(), me: _ordinary()));
    expect(find.byKey(const Key('grp_register_member')), findsOneWidget);
    expect(find.text('Register a member (password by SMS)'), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_register_member')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_f_name')), findsOneWidget);
    expect(find.text('Register a member'), findsOneWidget);
  });

  testWidgets('a member registering someone has no referrer to choose and no "already a member" switch: they themselves are the referrer', (final WidgetTester t) async {
    await _pump(t, MemberFormScreen(api: _Api(), me: _approver(), byMember: true, placeSource: FakePlaces()));
    expect(find.byKey(const Key('grp_f_referrer')), findsNothing);
    expect(find.byKey(const Key('grp_f_existing')), findsNothing, reason: 'even for someone who may approve members, this is a registration by a member');
  });

  testWidgets('saving asks first, and says that a one-time password will be texted to the number typed; then it is sent to the server', (final WidgetTester t) async {
    final _Api api = _Api();
    await _pump(t, MemberFormScreen(api: api, me: _ordinary(), byMember: true, placeSource: FakePlaces()));
    await _fillAndSave(t);

    expect(find.byKey(const Key('grp_confirm')), findsOneWidget);
    expect(find.textContaining('A one-time password will be texted to 0715000111'), findsOneWidget);
    expect(find.textContaining('8+ characters'), findsOneWidget);
    expect(api.sent, isNull, reason: 'nothing is sent before the Yes');
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();

    expect(api.sent?['full_name'], 'Neema Mussa');
    expect(api.sent?['phone'], '0715000111', reason: 'the number as typed, without spaces');
    expect(find.byKey(const Key('grp_reg_done')), findsOneWidget);
    expect(find.text('Registered'), findsOneWidget);
    expect(find.textContaining('texted to 0715000111'), findsOneWidget);
    expect(find.byKey(const Key('grp_reg_resend')), findsNothing, reason: 'it went, nothing to send again');
  });

  testWidgets('when the text could not be sent the registrar is told, and can ask for it to be sent again', (final WidgetTester t) async {
    final _Api api = _Api(smsSent: false);
    await _pump(t, MemberFormScreen(api: api, me: _ordinary(), byMember: true, placeSource: FakePlaces()));
    await _fillAndSave(t);
    await t.tap(find.byKey(const Key('grp_confirm_yes')));
    await t.pumpAndSettle();

    expect(find.text('Registered, the text was not sent'), findsOneWidget);
    expect(find.byKey(const Key('grp_reg_resend')), findsOneWidget);
    await t.tap(find.byKey(const Key('grp_reg_resend')));
    await t.pumpAndSettle();
    expect(api.resent, <int>[42]);
    expect(find.text('Registered'), findsOneWidget, reason: 'the second try went through');
    expect(find.byKey(const Key('grp_reg_resend')), findsNothing);
  });

  testWidgets('an officer entering a member file still sees the referrer and the existing-member switch (the normal form is unchanged)', (final WidgetTester t) async {
    await _pump(t, MemberFormScreen(api: _Api(), me: _approver(), placeSource: FakePlaces()));
    expect(find.byKey(const Key('grp_f_referrer')), findsOneWidget);
    expect(find.byKey(const Key('grp_f_existing')), findsOneWidget);
    expect(find.text('New member'), findsOneWidget);
  });
}
