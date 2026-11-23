import 'package:boda_mapato/modules/groups/models/group_asset_models.dart';
import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/payment_form.dart';
import 'package:boda_mapato/modules/groups/screens/payment_methods_screen.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _m(final String method, {final String? number, final String? name, final String? bank, final Map<String, dynamic>? month}) =>
    <String, dynamic>{'method': method, 'number': number, 'account_name': name, 'bank_name': bank, if (month != null) 'month': month};

final List<Map<String, dynamic>> _chosen = <Map<String, dynamic>>[
  _m('mpesa', number: '0754 100 200', name: 'Umoja wa Wajasiriamali Mikocheni'),
  _m('bank_transfer', number: '2051234567', name: 'UWM Savings Group', bank: 'NMB'),
  _m('airtel_money', number: '0784 300 400', name: 'UWM Savings Group'),
];

class _Api extends GroupsApi {
  _Api({this.configured = true, this.canManage = false, List<Map<String, dynamic>>? methods}) : methods = methods ?? _chosen;

  final bool configured;
  final bool canManage;
  List<Map<String, dynamic>> methods;
  List<Map<String, dynamic>>? saved;
  String? savedReason;

  @override
  Future<({bool configured, bool canManage, List<GroupPayMethod> methods})> paymentMethods() async =>
      (configured: configured, canManage: canManage, methods: <GroupPayMethod>[for (final Map<String, dynamic> m in methods) GroupPayMethod.fromJson(m)]);

  @override
  Future<void> savePaymentMethods(final List<Map<String, dynamic>> methods, {required final String reason}) async {
    saved = methods;
    savedReason = reason;
  }
}

GroupMe _me({final List<Map<String, dynamic>> methods = const <Map<String, dynamic>>[]}) => GroupMe.fromJson(<String, dynamic>{
      'rights': <String>[],
      'member': <String, dynamic>{'id': 1, 'full_name': 'Asha Juma', 'phone': '0713000001', 'status': 'active', 'member_number': 'UWM-0001'},
      'group': <String, dynamic>{'name': 'MEG'},
      'balances': <String, double>{'joining_fee': 0, 'shares': 0, 'savings': 100000, 'contribution': 0},
      'settings': <String, dynamic>{'joining_fee': 80000, 'share_amount': 200000},
      'payment_methods': methods,
    });

Future<void> _pump(final WidgetTester t, final Widget home, {final double width = 411, final String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(lang);
  t.view.physicalSize = Size(width, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: Size(width, 2600), minTextAdapt: true, builder: (_, __) => MaterialApp(home: KeyedSubtree(key: UniqueKey(), child: home))),
    ),
  );
  await t.pumpAndSettle();
}

/// A page with one button that opens the payment form, as Home does.
class _Harness extends StatelessWidget {
  const _Harness({required this.api, required this.me});

  final GroupsApi api;
  final GroupMe me;

  @override
  Widget build(final BuildContext context) => Scaffold(body: Center(child: FilledButton(key: const Key('open_form'), onPressed: () => showPaymentForm(context, api: api, me: me), child: const Text('Open'))));
}

void main() {
  testWidgets('how to pay lists every authorised method as one joined card, each with its number, its name and the bank', (final WidgetTester t) async {
    await _pump(t, PaymentMethodsScreen(api: _Api()));

    expect(find.byType(PayToCard), findsNWidgets(3));
    expect(find.text('M-Pesa'), findsWidgets);
    expect(find.text('Bank'), findsWidgets);
    expect(find.text('Airtel Money'), findsWidgets);
    expect(find.byKey(const Key('grp_payto_number_mpesa')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('grp_payto_number_mpesa'))).data, '0754 100 200');
    expect(find.text('NMB'), findsOneWidget);
    expect(find.text('Umoja wa Wajasiriamali Mikocheni'), findsOneWidget);
    expect(find.byKey(const Key('grp_pm_edit')), findsNothing, reason: 'a member does not choose the methods');
    expect(find.byKey(const Key('grp_pm_none')), findsNothing);
  });

  testWidgets('copying a number puts it on the clipboard', (final WidgetTester t) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (final MethodCall c) async {
      if (c.method == 'Clipboard.setData') copied = (c.arguments as Map<dynamic, dynamic>)['text'] as String?;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(t, PaymentMethodsScreen(api: _Api()));
    await t.tap(find.byKey(const Key('grp_payto_copy_bank_transfer')));
    await t.pumpAndSettle();
    expect(copied, '2051234567');
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('the finance readers also see the month per method; before the group chooses, the screen says every method is accepted', (final WidgetTester t) async {
    await _pump(t, PaymentMethodsScreen(api: _Api(methods: <Map<String, dynamic>>[_m('mpesa', number: '0754 100 200', name: 'UWM', month: <String, dynamic>{'in': 50000, 'out': 0, 'count': 3})])));
    expect(find.textContaining('3 · TSH 50,000'), findsOneWidget);

    await _pump(t, PaymentMethodsScreen(api: _Api(configured: false, methods: <Map<String, dynamic>>[], canManage: true)));
    expect(find.byKey(const Key('grp_pm_none')), findsOneWidget);
    expect(find.byType(PayToCard), findsNothing);
    expect(find.byKey(const Key('grp_pm_edit')), findsOneWidget, reason: 'the Mwenyekiti can choose');
  });

  testWidgets('the Mwenyekiti switches methods on and says where each is paid; saving asks the reason and sends only what is on', (final WidgetTester t) async {
    final _Api api = _Api(configured: false, canManage: true, methods: <Map<String, dynamic>>[]);
    await _pump(t, PaymentMethodsEditor(api: api, current: const <GroupPayMethod>[]));

    await t.ensureVisible(find.byKey(const Key('grp_pme_save')));
    await t.tap(find.byKey(const Key('grp_pme_save')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_pme_error')), findsOneWidget, reason: 'nothing is on');

    Future<void> on(final String m) async {
      await t.ensureVisible(find.byKey(Key('grp_pme_on_$m')));
      await t.tap(find.byKey(Key('grp_pme_on_$m')));
      await t.pumpAndSettle();
    }

    await on('mpesa');
    await on('bank_transfer');
    await on('cash');
    expect(find.byKey(const Key('grp_pme_number_cash')), findsNothing, reason: 'cash needs no number');
    await t.ensureVisible(find.byKey(const Key('grp_pme_save')));
    await t.tap(find.byKey(const Key('grp_pme_save')));
    await t.pumpAndSettle();
    expect(find.textContaining('number to pay to for Bank'), findsOneWidget);

    await t.enterText(find.byKey(const Key('grp_pme_number_mpesa')), '0754 100 200');
    await t.enterText(find.byKey(const Key('grp_pme_name_mpesa')), 'UWM Mikocheni');
    await t.enterText(find.byKey(const Key('grp_pme_number_bank_transfer')), '2051234567');
    await t.enterText(find.byKey(const Key('grp_pme_name_bank_transfer')), 'UWM Savings');
    await t.ensureVisible(find.byKey(const Key('grp_pme_save')));
    await t.tap(find.byKey(const Key('grp_pme_save')));
    await t.pumpAndSettle();
    expect(find.textContaining('name of the bank'), findsOneWidget);

    await t.enterText(find.byKey(const Key('grp_pme_bank_bank_transfer')), 'NMB');
    await t.ensureVisible(find.byKey(const Key('grp_pme_save')));
    await t.tap(find.byKey(const Key('grp_pme_save')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_reason')), findsOneWidget);
    expect(api.saved, isNull, reason: 'nothing is sent before the reason');
    await t.enterText(find.byKey(const Key('grp_reason_field')), 'Uamuzi wa kikao cha Novemba');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('grp_reason_yes')));
    await t.pumpAndSettle();

    expect(api.savedReason, 'Uamuzi wa kikao cha Novemba');
    expect(api.saved?.map((final Map<String, dynamic> m) => m['method']).toList(), <String>['bank_transfer', 'mpesa', 'cash']);
    final Map<String, dynamic> bank = api.saved!.firstWhere((final Map<String, dynamic> m) => m['method'] == 'bank_transfer');
    expect(bank, <String, dynamic>{'method': 'bank_transfer', 'number': '2051234567', 'account_name': 'UWM Savings', 'bank_name': 'NMB'});
    expect(api.saved!.firstWhere((final Map<String, dynamic> m) => m['method'] == 'cash'), <String, dynamic>{'method': 'cash'});
    await t.pump(const Duration(seconds: 6));
  });

  testWidgets('the editor starts from what is authorised now', (final WidgetTester t) async {
    await _pump(t, PaymentMethodsEditor(api: _Api(), current: <GroupPayMethod>[for (final Map<String, dynamic> m in _chosen) GroupPayMethod.fromJson(m)]));
    expect(t.widget<SwitchListTile>(find.byKey(const Key('grp_pme_on_mpesa'))).value, isTrue);
    expect(t.widget<SwitchListTile>(find.byKey(const Key('grp_pme_on_mixx'))).value, isFalse);
    expect(t.widget<TextField>(find.byKey(const Key('grp_pme_number_mpesa'))).controller?.text, '0754 100 200');
  });

  testWidgets('the payment form offers only the authorised methods and shows where to pay for the one chosen', (final WidgetTester t) async {
    await _pump(t, _Harness(api: _Api(), me: _me(methods: _chosen)));
    await t.tap(find.byKey(const Key('open_form')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('grp_payto_mpesa')), findsOneWidget, reason: 'it starts on the first method the group chose');
    expect(find.byKey(const Key('grp_payto_number_mpesa')), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('grp_pay_method')));
    await t.tap(find.byKey(const Key('grp_pay_method')));
    await t.pumpAndSettle();
    expect(find.text('Airtel Money'), findsWidgets);
    expect(find.text('HaloPesa'), findsNothing, reason: 'not authorised');
    expect(find.text('Cash'), findsNothing, reason: 'not authorised');
    await t.tap(find.text('Airtel Money').last);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_payto_airtel_money')), findsOneWidget);
    expect(find.byKey(const Key('grp_payto_mpesa')), findsNothing);
    expect(t.widget<Text>(find.byKey(const Key('grp_payto_number_airtel_money'))).data, '0784 300 400');
  });

  testWidgets('before the group chooses, the payment form offers every method and no number', (final WidgetTester t) async {
    await _pump(t, _Harness(api: _Api(), me: _me()));
    await t.tap(find.byKey(const Key('open_form')));
    await t.pumpAndSettle();
    expect(find.byType(PayToCard), findsNothing);
    await t.ensureVisible(find.byKey(const Key('grp_pay_method')));
    await t.tap(find.byKey(const Key('grp_pay_method')));
    await t.pumpAndSettle();
    expect(find.text('HaloPesa'), findsWidgets);
    expect(find.text('Cash'), findsWidgets);
  });

  test('a hire says the nights past its return day and what they come to', () {
    final GroupHire h = GroupHire.fromJson(<String, dynamic>{
      'id': 1, 'reference': 'HR-1', 'asset_id': 1, 'asset_name': 'Viti', 'quantity': 10, 'start_date': '2026-11-20', 'end_date': '2026-11-22', 'days': 3, 'rate': 300, 'amount': 9000,
      'status': 'issued', 'state': 'overdue', 'late_nights': 3, 'late_charge_now': 9000, 'late_charge': 0, 'total': 9000, 'paid': 9000, 'balance': 0,
    });
    expect(h.lateNights, 3);
    expect(h.lateChargeNow, 9000);
  });
}
