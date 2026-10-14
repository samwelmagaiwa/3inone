import 'dart:typed_data';

import 'package:boda_mapato/models/business.dart';
import 'package:boda_mapato/models/sms_sender.dart';
import 'package:boda_mapato/screens/settings/business_profile_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Business _biz({
  String name = 'Mama Duka',
  String address = 'Sinza, Dar',
  String tin = '123-456-789',
  String phone = '0712345678',
  String email = 'duka@example.test',
  String? logo,
  String? inventoryType,
  BusinessBilling billing = const BusinessBilling(plan: 'basic'),
  SmsSenderInfo sender = const SmsSenderInfo(),
}) =>
    Business(
        id: 'b-1',
        ownerId: 'u-1',
        name: name,
        address: address,
        tin: tin,
        phone: phone,
        email: email,
        logoUrl: logo,
        inventoryType: inventoryType,
        billing: billing,
        smsSender: sender);

class _FakeSource implements BusinessProfileDataSource {
  _FakeSource(this.business);

  Business business;
  Object? loadError;
  Object? saveError;
  Object? requestError;
  final List<({String senderId, String? displayName})> senderRequests = <({String senderId, String? displayName})>[];
  int withdrawals = 0;
  final List<Map<String, String>> saves = <Map<String, String>>[];
  final List<String?> savedTypes = <String?>[];
  final List<String> logoUploads = <String>[];
  int logoRemovals = 0;

  @override
  Future<Business> load() async {
    if (loadError != null) throw loadError!;
    return business;
  }

  @override
  Future<Business> save({
    required String name,
    required String address,
    required String tin,
    required String phone,
    required String email,
    String? inventoryType,
  }) async {
    if (saveError != null) throw saveError!;
    saves.add(<String, String>{'name': name, 'address': address, 'tin': tin, 'phone': phone, 'email': email});
    savedTypes.add(inventoryType);
    // The server tidies a TIN into 123-456-789.
    final String digits = tin.replaceAll(RegExp(r'\D'), '');
    business = _biz(
      name: name,
      address: address,
      tin: digits.length == 9 ? '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}' : tin,
      phone: phone,
      email: email,
      logo: business.logoUrl,
      billing: business.billing,
      inventoryType: inventoryType ?? business.inventoryType,
    );
    return business;
  }

  @override
  Future<Business> uploadLogo(Uint8List bytes, String filename) async {
    logoUploads.add(filename);
    business = _biz(name: business.name, logo: 'https://example.test/api/files/public/business_logos/new.png');
    return business;
  }

  @override
  Future<Business> removeLogo() async {
    logoRemovals++;
    business = _biz(name: business.name);
    return business;
  }

  @override
  Future<Business> requestSmsSender({required String senderId, String? displayName}) async {
    if (requestError != null) throw requestError!;
    senderRequests.add((senderId: senderId, displayName: displayName));
    business = _biz(name: business.name, sender: SmsSenderInfo(senderId: senderId, displayName: (displayName ?? '').isEmpty ? null : displayName, status: 'pending'));
    return business;
  }

  @override
  Future<Business> withdrawSmsSender() async {
    withdrawals++;
    business = _biz(name: business.name);
    return business;
  }
}

Widget _host(_FakeSource source,
        {bool canEdit = true, bool showInventoryType = false, Future<PickedLogo?> Function()? pick, VoidCallback? onChanged}) =>
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(800, 2400),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(
          home: BusinessProfileScreen(
              canEdit: canEdit, showInventoryType: showInventoryType, dataSource: source, pickLogo: pick, onChanged: onChanged),
        ),
      ),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

/// The success banner stays up for three seconds; let it go before the test ends.
Future<void> _bannerGone(WidgetTester t) async {
  await t.pump(const Duration(seconds: 4));
  await t.pumpAndSettle();
}

String _text(WidgetTester t, String key) => t.widget<TextFormField>(_key(key)).controller!.text;

void main() {
  testWidgets('the owner sees the details and the plan', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_FakeSource(_biz())));
    await t.pumpAndSettle();

    expect(_text(t, 'business_name_field'), 'Mama Duka');
    expect(_text(t, 'business_tin_field'), '123-456-789');
    expect(_text(t, 'business_phone_field'), '0712345678');
    expect(_text(t, 'business_email_field'), 'duka@example.test');
    expect(_text(t, 'business_address_field'), 'Sinza, Dar');
    expect(find.text('Mpango: Msingi'), findsOneWidget);
    expect(find.text('Haina tarehe ya kuisha'), findsOneWidget);
    expect(_key('business_save'), findsOneWidget);
  });

  testWidgets('saving sends what was typed and shows what the server kept', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(_biz());
    int changed = 0;
    await t.pumpWidget(_host(source, onChanged: () => changed++));
    await t.pumpAndSettle();

    await t.enterText(_key('business_name_field'), 'Mama Duka Ltd');
    await t.enterText(_key('business_tin_field'), '987654321');
    await t.enterText(_key('business_address_field'), 'Kariakoo');
    await t.tap(_key('business_save'));
    await t.pumpAndSettle();
    await _bannerGone(t);

    expect(source.saves, hasLength(1));
    expect(source.saves.single['name'], 'Mama Duka Ltd');
    expect(source.saves.single['address'], 'Kariakoo');
    expect(source.saves.single['phone'], '0712345678', reason: 'untouched fields are sent as they were');
    expect(_text(t, 'business_tin_field'), '987-654-321', reason: 'the form shows the tidied TIN');
    expect(changed, 1, reason: 'the rest of the app is told to refresh');
  });

  testWidgets('a bad value is explained and nothing is sent', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(_biz());
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();

    await t.enterText(_key('business_tin_field'), '12-34');
    await t.enterText(_key('business_phone_field'), 'call me');
    await t.enterText(_key('business_email_field'), 'nope');
    await t.enterText(_key('business_name_field'), '  ');
    await t.tap(_key('business_save'));
    await t.pumpAndSettle();

    expect(find.textContaining('TIN lazima iwe na tarakimu 9'), findsOneWidget);
    expect(find.textContaining('Namba ya simu si sahihi'), findsOneWidget);
    expect(find.text('Barua pepe si sahihi'), findsOneWidget);
    expect(find.text('Jina la biashara linahitajika'), findsOneWidget);
    expect(source.saves, isEmpty);
  });

  testWidgets('empty optional fields are allowed', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(_biz());
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();

    for (final String k in <String>['business_tin_field', 'business_phone_field', 'business_email_field', 'business_address_field']) {
      await t.enterText(_key(k), '');
    }
    await t.tap(_key('business_save'));
    await t.pumpAndSettle();
    await _bannerGone(t);

    expect(source.saves, hasLength(1));
    expect(source.saves.single['tin'], '');
  });

  testWidgets('the server\'s refusal is shown under the form', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(_biz())..saveError = Exception('The tin must have 9 digits.');
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();

    await t.tap(_key('business_save'));
    await t.pumpAndSettle();

    expect(find.text('The tin must have 9 digits.'), findsOneWidget);
  });

  testWidgets('staff only read: the fields are locked and there is no save button', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_FakeSource(_biz()), canEdit: false));
    await t.pumpAndSettle();

    expect(_key('business_save'), findsNothing);
    expect(_key('business_logo_change'), findsNothing);
    expect(_key('business_read_only_note'), findsOneWidget);
    expect(t.widget<TextFormField>(_key('business_name_field')).enabled, isFalse);
    expect(_text(t, 'business_name_field'), 'Mama Duka');
  });

  testWidgets('the owner can add, change and remove the logo', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(_biz());
    await t.pumpWidget(_host(source, pick: () async => (bytes: Uint8List.fromList(<int>[1, 2, 3]), name: 'logo.png')));
    await t.pumpAndSettle();

    expect(_key('business_logo_remove'), findsNothing, reason: 'no logo yet');
    expect(find.text('Weka nembo'), findsOneWidget);

    await t.tap(_key('business_logo_change'));
    await t.pumpAndSettle();
    await _bannerGone(t);
    expect(source.logoUploads, <String>['logo.png']);
    expect(find.text('Badilisha nembo'), findsOneWidget);

    await t.tap(_key('business_logo_remove'));
    await t.pumpAndSettle();
    await _bannerGone(t);
    expect(source.logoRemovals, 1);
    expect(_key('business_logo_remove'), findsNothing);
  });

  testWidgets('cancelling the picker changes nothing', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(_biz());
    await t.pumpWidget(_host(source, pick: () async => null));
    await t.pumpAndSettle();

    await t.tap(_key('business_logo_change'));
    await t.pumpAndSettle();

    expect(source.logoUploads, isEmpty);
  });

  testWidgets('a business running out is flagged on the page', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_FakeSource(_biz(billing: BusinessBilling(plan: 'trial', validUntil: DateTime(2026, 11, 14), daysLeft: 3)))));
    await t.pumpAndSettle();

    expect(_key('subscription_banner'), findsOneWidget);
    expect(find.text('Mpango: Jaribio'), findsOneWidget);
    expect(find.textContaining('14 Nov 2026'), findsOneWidget);
  });

  testWidgets('a business that is fine is not', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_FakeSource(_biz(billing: BusinessBilling(plan: 'basic', validUntil: DateTime(2027, 6, 1), daysLeft: 200)))));
    await t.pumpAndSettle();

    expect(_key('subscription_banner'), findsNothing);
    expect(find.text('Mpango: Msingi'), findsOneWidget);
  });

  testWidgets('a business without inventory is not asked what kind of stock business it is', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_FakeSource(_biz(inventoryType: 'retail'))));
    await t.pumpAndSettle();

    expect(_key('business_type_retail'), findsNothing);
  });

  testWidgets('the owner sees the kind of business and can change it', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(_biz(inventoryType: 'retail'));
    await t.pumpWidget(_host(source, showInventoryType: true));
    await t.pumpAndSettle();

    expect(t.widget<ChoiceChip>(_key('business_type_retail')).selected, isTrue);
    expect(t.widget<ChoiceChip>(_key('business_type_wholesale')).selected, isFalse);

    await t.ensureVisible(_key('business_type_wholesale'));
    await t.tap(_key('business_type_wholesale'));
    await t.pump();
    await t.ensureVisible(_key('business_save'));
    await t.tap(_key('business_save'));
    await t.pumpAndSettle();

    expect(source.savedTypes, <String?>['wholesale']);
    expect(t.widget<ChoiceChip>(_key('business_type_wholesale')).selected, isTrue);
    await _bannerGone(t);
  });

  testWidgets('saving other details does not resend the kind of business when it was not touched', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(_biz(inventoryType: 'retail'));
    await t.pumpWidget(_host(source, showInventoryType: true));
    await t.pumpAndSettle();

    await t.enterText(_key('business_address_field'), 'Kariakoo');
    await t.ensureVisible(_key('business_save'));
    await t.tap(_key('business_save'));
    await t.pumpAndSettle();

    expect(source.savedTypes, <String?>[null]);
    await _bannerGone(t);
  });

  testWidgets('a business that never chose a kind shows as a depot, the way it has always worked', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_FakeSource(_biz()), showInventoryType: true));
    await t.pumpAndSettle();

    expect(t.widget<ChoiceChip>(_key('business_type_depot')).selected, isTrue);
  });

  testWidgets('someone who is not the owner sees the kind of business but cannot change it', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_FakeSource(_biz(inventoryType: 'mixed')), canEdit: false, showInventoryType: true));
    await t.pumpAndSettle();

    expect(t.widget<ChoiceChip>(_key('business_type_mixed')).selected, isTrue);
    expect(t.widget<ChoiceChip>(_key('business_type_retail')).onSelected, isNull);
  });

  testWidgets('when it cannot be loaded the reason is shown with a retry', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(_biz())..loadError = Exception('Hakuna muunganisho');
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();

    expect(find.text('Hakuna muunganisho'), findsOneWidget);
    source.loadError = null;
    await t.tap(find.text('Jaribu tena'));
    await t.pumpAndSettle();

    expect(_text(t, 'business_name_field'), 'Mama Duka');
  });

  group('the SMS sender name', () {
    Future<_FakeSource> open(WidgetTester t, SmsSenderInfo sender, {bool canEdit = true}) async {
      _tall(t);
      final _FakeSource source = _FakeSource(_biz(sender: sender));
      await t.pumpWidget(_host(source, canEdit: canEdit));
      await t.pumpAndSettle();
      return source;
    }

    String title(WidgetTester t) => (t.widget(_key('sms_sender_title')) as Text).data!;
    String text(WidgetTester t) => (t.widget(_key('sms_sender_text')) as Text).data!;

    testWidgets('a business with none says so and the owner asks for one', (t) async {
      final _FakeSource source = await open(t, const SmsSenderInfo());

      expect(title(t), 'Bado huna jina lako');
      expect(_key('withdraw_sender'), findsNothing);

      await t.ensureVisible(_key('request_sender'));
      await t.tap(_key('request_sender'));
      await t.pumpAndSettle();
      await t.enterText(_key('request_sender_id_field'), 'MAMAASHA');
      await t.enterText(_key('request_display_name_field'), 'Mama Asha');
      await t.tap(_key('submit_request'));
      await t.pumpAndSettle();

      expect(source.senderRequests.single.senderId, 'MAMAASHA');
      expect(source.senderRequests.single.displayName, 'Mama Asha');
      expect(title(t), 'MAMAASHA');
      expect(text(t), contains('linasubiri'));
      expect(_key('withdraw_sender'), findsOneWidget);
      await _bannerGone(t);
    });

    testWidgets('a name that cannot work is refused on the spot and nothing is sent', (t) async {
      final _FakeSource source = await open(t, const SmsSenderInfo());

      await t.ensureVisible(_key('request_sender'));
      await t.tap(_key('request_sender'));
      await t.pumpAndSettle();
      await t.enterText(_key('request_sender_id_field'), '1AB');
      await t.tap(_key('submit_request'));
      await t.pumpAndSettle();

      expect(find.textContaining('Herufi 3 hadi 11'), findsOneWidget);
      expect(source.senderRequests, isEmpty);
      expect(_key('submit_request'), findsOneWidget, reason: 'the dialog stays open');
    });

    testWidgets('a refusal from the server is shown', (t) async {
      final _FakeSource source = await open(t, const SmsSenderInfo());
      source.requestError = Exception('Jina hili tayari linatumiwa na biashara nyingine.');

      await t.ensureVisible(_key('request_sender'));
      await t.tap(_key('request_sender'));
      await t.pumpAndSettle();
      await t.enterText(_key('request_sender_id_field'), 'TAKENNAME');
      await t.tap(_key('submit_request'));
      await t.pumpAndSettle();

      expect(find.text('Jina hili tayari linatumiwa na biashara nyingine.'), findsOneWidget);
      expect(title(t), 'Bado huna jina lako');
    });

    testWidgets('a waiting request can be changed or withdrawn', (t) async {
      final _FakeSource source = await open(t, const SmsSenderInfo(senderId: 'MAMAASHA', status: 'pending'));
      expect(title(t), 'MAMAASHA');
      expect(find.text('Badilisha ombi'), findsOneWidget);

      await t.ensureVisible(_key('withdraw_sender'));
      await t.tap(_key('withdraw_sender'));
      await t.pumpAndSettle();

      expect(source.withdrawals, 1);
      expect(title(t), 'Bado huna jina lako');
      await _bannerGone(t);
    });

    testWidgets('an approved name is shown and is the administrator\'s to change', (t) async {
      await open(t, const SmsSenderInfo(senderId: 'MAMAASHA', status: 'approved'));

      expect(title(t), 'MAMAASHA');
      expect(text(t), 'Ujumbe wa wateja wako unaonekana kutoka MAMAASHA.');
      expect(_key('request_sender'), findsNothing);
      expect(find.text('Kulibadilisha, wasiliana na msimamizi.'), findsOneWidget);
    });

    testWidgets('a rejected name shows why and the owner can ask again', (t) async {
      await open(t, const SmsSenderInfo(senderId: 'MPESAX', status: 'rejected', note: 'Looks like a mobile money brand'));

      expect(text(t), contains('halikukubaliwa: Looks like a mobile money brand'));
      expect(_key('request_sender'), findsOneWidget);
      expect(find.text('Omba jina'), findsOneWidget);
    });

    testWidgets('staff see where it stands but cannot ask', (t) async {
      await open(t, const SmsSenderInfo(senderId: 'MAMAASHA', status: 'pending'), canEdit: false);

      expect(title(t), 'MAMAASHA');
      expect(_key('request_sender'), findsNothing);
      expect(_key('withdraw_sender'), findsNothing);
    });

    testWidgets('the card follows the app language', (t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalizationService.instance.changeLanguage('en');
      addTearDown(() => LocalizationService.instance.changeLanguage('sw'));
      await open(t, const SmsSenderInfo(senderId: 'MAMAASHA', status: 'approved'));

      expect(text(t), "Your customers' texts show MAMAASHA as the sender.");
      expect(find.text('To change it, contact your administrator.'), findsOneWidget);
      expect(find.textContaining('wateja'), findsNothing);
    });
  });
}
