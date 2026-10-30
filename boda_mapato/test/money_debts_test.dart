import 'package:boda_mapato/modules/inventory/screens/money/debts_screen.dart';
import 'package:boda_mapato/modules/inventory/services/money_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Debts from before the app: written down in two tabs (owed to me, I owe), paid in parts, removed only when nothing was paid.
class _FakeMoney extends MoneyApi {
  final List<Map<String, dynamic>> added = <Map<String, dynamic>>[];
  final List<(int, double)> paid = <(int, double)>[];
  final List<int> deleted = <int>[];
  final List<Map<String, dynamic>> corrected = <Map<String, dynamic>>[];
  Object? failAdd;

  @override
  Future<Map<String, dynamic>> debts(String kind, {bool includePaid = false}) async => kind == 'receivable'
      ? <String, dynamic>{
          'kind': kind, 'total': 460000, 'old': 360000, 'from_records': 100000,
          'debts': <Map<String, dynamic>>[
            <String, dynamic>{'id': 1, 'kind': kind, 'name': 'Mama Neema', 'phone': '0711000001', 'amount': 350000, 'paid': 0, 'left': 350000, 'started_on': '2026-06-01', 'due_on': '2026-07-01', 'days_late': 120, 'note': 'Soda za mwaka jana'},
            <String, dynamic>{'id': 2, 'kind': kind, 'name': 'Baba Juma', 'phone': '', 'amount': 20000, 'paid': 10000, 'left': 10000, 'started_on': '2026-10-01', 'due_on': null, 'days_late': 0, 'note': null},
          ],
        }
      : <String, dynamic>{'kind': kind, 'total': 0, 'old': 0, 'from_records': 0, 'debts': <dynamic>[]};

  @override
  Future<void> addDebt({required String kind, required String name, String? phone, required double amount, DateTime? startedOn, DateTime? dueOn, String? note, int? customerId}) async {
    if (failAdd != null) throw failAdd!;
    added.add(<String, dynamic>{'kind': kind, 'name': name, 'phone': phone, 'amount': amount, 'note': note, 'due': dueOn});
  }

  @override
  Future<void> payDebt(int id, {required double amount, String? method, String? note}) async => paid.add((id, amount));

  @override
  Future<List<Map<String, dynamic>>> debtPayments(int id) async =>
      id == 2 ? <Map<String, dynamic>>[<String, dynamic>{'id': 9, 'amount': 10000, 'method': 'cash', 'paid_on': '2026-10-15', 'note': null}] : <Map<String, dynamic>>[];

  @override
  Future<void> deleteDebt(int id) async => deleted.add(id);

  @override
  Future<void> updateDebt(int id, {required String name, String? phone, required double amount, required DateTime startedOn, DateTime? dueOn, String? note}) async {
    if (failAdd != null) throw failAdd!;
    corrected.add(<String, dynamic>{'id': id, 'name': name, 'phone': phone, 'amount': amount, 'started': startedOn, 'due': dueOn, 'note': note});
  }
}

Future<_FakeMoney> _open(WidgetTester t, {bool sw = false, int tab = 0}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _FakeMoney api = _FakeMoney();
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: MaterialApp(home: DebtsScreen(api: api, initialTab: tab)),
    ),
  );
  await t.pump();
  await t.pump();

  return api;
}

Finder _k(String k) => find.byKey(Key(k));

void main() {
  testWidgets('owed to me: the total, what came from before the app, and each debt with how much is left', (t) async {
    await _open(t);

    expect(t.widget<Text>(_k('debts_total_receivable')).data, 'TSH 460,000');
    expect(find.text('From before the app: TSH 360,000   ·   From sales: TSH 100,000'), findsOneWidget);
    expect(find.text('Mama Neema'), findsOneWidget);
    expect(find.text('120 days late'), findsOneWidget);
    expect(find.text('Soda za mwaka jana'), findsOneWidget);
    expect(find.descendant(of: _k('debt_2'), matching: find.text('TSH 10,000')), findsOneWidget, reason: 'what is left, not the whole');
    expect(find.descendant(of: _k('debt_2'), matching: find.text('Of TSH 20,000')), findsOneWidget);
  });

  testWidgets('the second tab is what I owe, with its own empty page', (t) async {
    await _open(t);

    await t.tap(_k('tab_i_owe'));
    await t.pumpAndSettle();

    expect(_k('debts_empty_payable'), findsOneWidget);
    expect(find.text('Add what I owe'), findsOneWidget);
  });

  testWidgets('adding an old debt asks for a name and an amount, then saves it', (t) async {
    final _FakeMoney api = await _open(t);

    await t.tap(_k('debt_add'));
    await t.pumpAndSettle();
    await t.tap(_k('debt_save'));
    await t.pump();
    expect(find.text('Write the debtor\'s name.'), findsOneWidget);

    await t.enterText(_k('debt_name'), 'Mzee Ali');
    await t.tap(_k('debt_save'));
    await t.pump();
    expect(find.text('Write the amount.'), findsOneWidget);

    await t.enterText(_k('debt_amount'), '125,000');
    await t.enterText(_k('debt_phone'), '0755000111');
    await t.tap(_k('debt_save'));
    await t.pumpAndSettle();

    expect(api.added.single['kind'], 'receivable');
    expect(api.added.single['name'], 'Mzee Ali');
    expect(api.added.single['amount'], 125000);
    expect(api.added.single['phone'], '0755000111');
    expect(_k('debt_name'), findsNothing, reason: 'the sheet closed');
  });

  testWidgets('a refusal from the server is shown on the form and the sheet stays open', (t) async {
    final _FakeMoney api = await _open(t);
    api.failAdd = Exception('Andika jina la mdaiwa.');

    await t.tap(_k('debt_add'));
    await t.pumpAndSettle();
    await t.enterText(_k('debt_name'), 'X');
    await t.enterText(_k('debt_amount'), '5');
    await t.tap(_k('debt_save'));
    await t.pumpAndSettle();

    expect(find.textContaining('Andika jina la mdaiwa.'), findsOneWidget);
    expect(_k('debt_name'), findsOneWidget);
  });

  testWidgets('a debt opens with its payments; paying more than is left is refused, a part payment is sent', (t) async {
    final _FakeMoney api = await _open(t);

    await t.tap(_k('debt_2'));
    await t.pumpAndSettle();
    expect(find.text('Left: TSH 10,000   (of TSH 20,000)'), findsOneWidget);
    expect(find.text('15/10/2026'), findsOneWidget, reason: 'the payment already made');
    expect(_k('debt_delete'), findsNothing, reason: 'a debt with payments is a record, not a mistake');

    await t.enterText(_k('pay_amount'), '10001');
    await t.tap(_k('pay_save'));
    await t.pump();
    expect(find.text('The amount must be between 1 and TSH 10,000.'), findsOneWidget);
    expect(api.paid, isEmpty);

    await t.enterText(_k('pay_amount'), '4000');
    await t.tap(_k('pay_save'));
    await t.pumpAndSettle();
    expect(api.paid.single, (2, 4000.0));
  });

  testWidgets('a debt nobody has paid on can be deleted', (t) async {
    final _FakeMoney api = await _open(t);

    await t.tap(_k('debt_1'));
    await t.pumpAndSettle();
    await t.tap(_k('debt_delete'));
    await t.pumpAndSettle();

    expect(api.deleted, <int>[1]);
    expect(find.text('Moved to the Trash. The owner or an admin can restore it.'), findsOneWidget, reason: 'it says where the debt went');
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('a debt can be corrected: the form opens filled in and the correction is sent', (t) async {
    final _FakeMoney api = await _open(t);

    await t.tap(_k('debt_1'));
    await t.pumpAndSettle();
    await t.tap(_k('debt_edit'));
    await t.pumpAndSettle();

    expect(find.text('Correct this debt'), findsOneWidget);
    expect(t.widget<TextField>(_k('debt_name')).controller!.text, 'Mama Neema');
    expect(t.widget<TextField>(_k('debt_amount')).controller!.text, '350,000');

    await t.enterText(_k('debt_name'), 'Mama Neema K.');
    await t.enterText(_k('debt_amount'), '360000');
    await t.tap(_k('debt_save'));
    await t.pumpAndSettle();

    expect(api.corrected.single['id'], 1);
    expect(api.corrected.single['name'], 'Mama Neema K.');
    expect(api.corrected.single['amount'], 360000);
    expect(api.added, isEmpty, reason: 'a correction is not a new debt');
  });

  testWidgets('a correction the server refuses (below what was paid) says why on the form', (t) async {
    final _FakeMoney api = await _open(t);
    api.failAdd = Exception('The amount cannot be less than what was already paid.');

    await t.tap(_k('debt_2'));
    await t.pumpAndSettle();
    await t.tap(_k('debt_edit'));
    await t.pumpAndSettle();
    await t.enterText(_k('debt_amount'), '5000');
    await t.tap(_k('debt_save'));
    await t.pumpAndSettle();

    expect(find.textContaining('cannot be less than'), findsOneWidget);
    expect(api.corrected, isEmpty);
  });

  testWidgets('in Swahili it is Swahili', (t) async {
    await _open(t, sw: true);

    expect(find.text('Ninayodai'), findsOneWidget);
    expect(find.text('Ninayodaiwa'), findsOneWidget);
    expect(find.text('Jumla ninayodai'), findsOneWidget);
    expect(find.text('Siku 120 zimepita'), findsOneWidget);
    expect(find.text('Deni la zamani'), findsOneWidget);
  });
}
