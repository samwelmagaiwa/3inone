import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/credit/customer_account_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/money/debts_screen.dart';
import 'package:boda_mapato/modules/inventory/services/money_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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

  /// The combined list (each customer once, old and new debt added), when the test wants it.
  List<Map<String, dynamic>>? parties;

  @override
  Future<Map<String, dynamic>> debts(String kind, {bool includePaid = false}) async => kind == 'receivable'
      ? <String, dynamic>{
          'kind': kind, 'total': 460000, 'old': 360000, 'from_records': 100000, if (parties != null) 'parties': parties,
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

Future<_FakeMoney> _open(WidgetTester t, {bool sw = false, int tab = 0, _FakeMoney? fake, DepotProvider? depot}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _FakeMoney api = fake ?? _FakeMoney();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
        if (depot != null) ChangeNotifierProvider<DepotProvider>.value(value: depot),
      ],
      child: ScreenUtilInit(designSize: const Size(800, 2000), builder: (_, __) => MaterialApp(home: DebtsScreen(api: api, initialTab: tab))),
    ),
  );
  await t.pump();
  await t.pump();

  return api;
}

Finder _k(String k) => find.byKey(Key(k));

void main() {
  testWidgets('each debt shows the percentage paid on its progress line, and the debts are divided by the glowing line', (t) async {
    await _open(t);

    expect(find.byKey(const Key('debt_percent_1')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('debt_percent_1'))).data, '0%');
    expect(t.widget<Text>(find.byKey(const Key('debt_percent_2'))).data, '50%', reason: '10,000 of 20,000');
    expect(find.byKey(const Key('debt_divider_2')), findsOneWidget);
    expect(find.byKey(const Key('debt_divider_1')), findsNothing, reason: 'none above the first');
  });

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

  group('owed to me lists each customer once, the old and the new debt together', () {
    List<Map<String, dynamic>> people() => <Map<String, dynamic>>[
          <String, dynamic>{'id': 5, 'customer_id': 5, 'name': 'mama chale', 'phone': '0764280395', 'amount': 640000, 'paid': 0, 'left': 640000, 'old_left': 210000, 'new_left': 430000, 'started_on': '2026-11-02', 'due_on': '2026-11-09', 'days_late': 0, 'note': null},
          <String, dynamic>{'id': 6, 'customer_id': 6, 'name': 'Baba Juma', 'phone': '0722000111', 'amount': 50000, 'paid': 0, 'left': 50000, 'old_left': 0, 'new_left': 50000, 'started_on': '2026-11-03', 'due_on': null, 'days_late': 0, 'note': null},
          <String, dynamic>{'id': 3, 'customer_id': null, 'name': 'Old Unlinked', 'phone': null, 'amount': 7000, 'paid': 0, 'left': 7000, 'old_left': 7000, 'new_left': 0, 'started_on': '2026-10-01', 'due_on': null, 'days_late': 0, 'note': null},
        ];

    testWidgets('a customer with both debts is one row with the total, and says how it splits', (t) async {
      await _open(t, fake: _FakeMoney()..parties = people());

      expect(find.text('mama chale'), findsOneWidget);
      expect(find.descendant(of: _k('debt_5'), matching: find.text('TSH 640,000')), findsOneWidget);
      expect(t.widget<Text>(_k('debt_split_5')).data, 'Old TSH 210,000  ·  New TSH 430,000');
      expect(_k('debt_split_6'), findsNothing, reason: 'a customer with one kind of debt needs no split');
      expect(find.text('Baba Juma'), findsOneWidget, reason: 'a customer who only has a credit sale is listed too');
    });

    testWidgets('the search box at the top finds a customer by name or number', (t) async {
      await _open(t, fake: _FakeMoney()..parties = people());
      expect(_k('debts_search_receivable'), findsOneWidget);

      await t.enterText(_k('debts_search_receivable'), 'chale');
      await t.pump();
      expect(find.text('mama chale'), findsOneWidget);
      expect(find.text('Baba Juma'), findsNothing);

      await t.enterText(_k('debts_search_receivable'), '0722');
      await t.pump();
      expect(find.text('Baba Juma'), findsOneWidget);
      expect(find.text('mama chale'), findsNothing);

      await t.enterText(_k('debts_search_receivable'), '');
      await t.pump();
      expect(find.text('mama chale'), findsOneWidget);
      expect(find.text('Baba Juma'), findsOneWidget);
    });

    testWidgets('the search of one tab does not filter the other', (t) async {
      await _open(t, fake: _FakeMoney()..parties = people());

      await t.enterText(_k('debts_search_receivable'), 'zzz');
      await t.pump();
      await t.tap(_k('tab_i_owe'));
      await t.pumpAndSettle();

      expect(_k('debts_empty_payable'), findsOneWidget);
      expect(t.widget<TextField>(find.descendant(of: _k('debts_search_payable'), matching: find.byType(TextField))).controller?.text ?? '', '', reason: 'the other tab keeps its own search');
    });

    testWidgets('a customer row opens the customer account with both debts', (t) async {
      final _AccountApi server = _AccountApi();
      final DepotProvider depot = DepotProvider(api: server);
      await _open(t, fake: _FakeMoney()..parties = people(), depot: depot);

      await t.tap(_k('debt_5'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(find.byType(CustomerAccountScreen), findsOneWidget);
      expect(server.asked.single, contains('/credit/customers/5/account'));
    });

    testWidgets('a debt that belongs to no customer still opens its own sheet', (t) async {
      await _open(t, fake: _FakeMoney()..parties = people());

      await t.tap(_k('debt_3'));
      await t.pumpAndSettle();

      expect(find.byType(CustomerAccountScreen), findsNothing);
    });

    testWidgets('an older server that sends no combined list still shows the debts from before the app', (t) async {
      await _open(t);

      expect(find.text('Mama Neema'), findsOneWidget);
      expect(_k('debts_search_receivable'), findsOneWidget);
    });
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

/// Answers the customer account page with an empty account, and remembers what was asked.
class _AccountApi extends ApiService {
  final List<String> asked = <String>[];

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async => <String, dynamic>{'data': <dynamic>[]};

  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async {
    asked.add(endpoint);

    return <String, dynamic>{
      'data': <String, dynamic>{
        'customer': <String, dynamic>{'id': 5, 'name': 'mama chale', 'phone': '0764280395', 'credit_limit': 0, 'is_blocked': false},
        'debt': <String, dynamic>{
          'old': <String, dynamic>{'entries': <dynamic>[], 'original': 210000, 'paid': 0, 'left': 210000},
          'new': <String, dynamic>{'sales': <dynamic>[], 'billed': 430000, 'paid': 0, 'left': 430000},
          'total': <String, dynamic>{'owed': 640000, 'paid': 0, 'left': 640000},
        },
        'old_debts': <dynamic>[], 'credit_sales': <dynamic>[], 'payments': <dynamic>[], 'paid_by_payments': <String, dynamic>{'old': 0, 'new': 0, 'all': 0},
      },
    };
  }
}
