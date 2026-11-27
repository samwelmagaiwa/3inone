import 'dart:convert';
import 'dart:typed_data';

import 'package:boda_mapato/models/business.dart';
import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/group_more_screen.dart';
import 'package:boda_mapato/modules/groups/services/group_doc.dart';
import 'package:boda_mapato/modules/groups/services/group_documents.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/screens/settings/business_profile_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _businessLogo = 'https://example.test/api/files/public/business_logos/b.png';
const String _groupLogo = 'https://example.test/api/files/public/business_logos/b_groups_x.png';

Business _biz({final Map<String, String> serviceLogos = const <String, String>{}}) => Business(
      id: 'b-1',
      ownerId: 'u-1',
      name: 'MEG',
      logoUrl: _businessLogo,
      serviceLogos: serviceLogos,
      billing: const BusinessBilling(plan: 'basic'),
    );

/// Only what the logo part of the page uses.
class _Source implements BusinessProfileDataSource {
  _Source(this.business);

  Business business;

  @override
  Future<Business> load() async => business;

  @override
  Future<Business> save({required String name, required String address, required String tin, required String phone, required String email, String? inventoryType}) async =>
      business;

  @override
  Future<Business> uploadLogo(final Uint8List bytes, final String filename) async => business = _biz(serviceLogos: <String, String>{'groups': _groupLogo});

  @override
  Future<Business> removeLogo() async => business = _biz();

  @override
  Future<Business> requestSmsSender({required String senderId, String? displayName}) async => business;

  @override
  Future<Business> withdrawSmsSender() async => business;
}

Future<void> _pump(final WidgetTester t, final Widget home) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(800, 2400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: home)),
    ),
  );
  await t.pumpAndSettle();
}

GroupMe _me({required final bool owner}) => GroupMe.fromJson(<String, dynamic>{
      'is_owner': owner,
      'rights': owner ? <String>['manage_settings', 'view_members'] : <String>['view_members'],
      'member': <String, dynamic>{'id': 1, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active'},
      'group': <String, dynamic>{'name': 'MEG', 'logo_url': _groupLogo},
    });

void main() {
  test('a service has its own logo, or the business logo', () {
    final Business b = Business.fromJson(<String, dynamic>{
      'id': 'b-1',
      'name': 'MEG',
      'logo_url': _businessLogo,
      'service_logos': <String, dynamic>{'groups': _groupLogo},
      'billing': <String, dynamic>{'plan': 'basic'},
    });
    expect(b.logoFor('groups'), _groupLogo);
    expect(b.logoFor('inventory'), _businessLogo);
    expect(b.logoFor(null), _businessLogo);
    expect(_me(owner: false).groupLogoUrl, _groupLogo);
    expect(_me(owner: false).asMember().groupLogoUrl, _groupLogo, reason: 'ME keeps the logo');
  });

  testWidgets('for Vikundi the page shows the group logo, says when the business logo stands in, and removes only a logo of its own', (final WidgetTester t) async {
    final _Source source = _Source(_biz());
    await _pump(t, BusinessProfileScreen(canEdit: true, logoService: 'groups', dataSource: source, pickLogo: () async => (bytes: Uint8List(4), name: 'meg.png')));

    expect(find.byKey(const ValueKey<String>('business_logo_fallback')), findsOneWidget);
    expect(find.text('Using the business logo. Add one of its own here.'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('business_logo_remove')), findsNothing, reason: 'the business logo is not removed from here');
    expect(find.text('Add logo'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey<String>('business_logo_change')));
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('business_logo_fallback')), findsNothing);
    expect(find.byKey(const ValueKey<String>('business_logo_remove')), findsOneWidget);
    expect(find.text('Change logo'), findsOneWidget);
  });

  testWidgets('only the business admin finds the group logo in More', (final WidgetTester t) async {
    await _pump(t, Scaffold(body: GroupMoreScreen(me: _me(owner: true), api: GroupsApi(), onChanged: () async {})));
    expect(find.byKey(const Key('grp_more_logo')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await _pump(t, Scaffold(body: GroupMoreScreen(me: _me(owner: false), api: GroupsApi(), onChanged: () async {})));
    expect(find.byKey(const Key('grp_more_logo')), findsNothing);
  });

  test('receipts and statements carry the logo, and still come out when it cannot be read', () async {
    final GroupDoc d = GroupDocuments.csvDoc(Uint8List.fromList(utf8.encode('Name,Amount\nAsha,1000\n')), group: 'MEG', title: 'Register', fileName: 'x');
    addTearDown(() {
      GroupDocuments.logoUrl = null;
      GroupDocuments.logoLoader = (final String url) async => null;
    });

    GroupDocuments.logoUrl = null;
    final Uint8List plain = await GroupDocuments.pdf(d);

    GroupDocuments.logoUrl = 'https://example.test/ok.png';
    GroupDocuments.logoLoader = (final String url) async =>
        base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final Uint8List withLogo = await GroupDocuments.pdf(d);
    expect(utf8.decode(withLogo.sublist(0, 4)), '%PDF');
    expect(withLogo.length, greaterThan(plain.length), reason: 'the picture is in the file');

    GroupDocuments.logoUrl = 'https://example.test/broken.webp';
    GroupDocuments.logoLoader = (final String url) async => Uint8List.fromList(<int>[1, 2, 3, 4]);
    final Uint8List broken = await GroupDocuments.pdf(d);
    expect(utf8.decode(broken.sublist(0, 4)), '%PDF', reason: 'the first letter stands in');
  });
}
