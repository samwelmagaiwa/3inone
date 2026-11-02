import 'package:boda_mapato/modules/inventory/models/inv_customer_debt.dart';
import 'package:boda_mapato/modules/inventory/models/inv_depot_models.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/credit/customer_account_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One customer's whole account on one page: old debt, new debt and total with all that was paid, every old debt and credit sale with
/// its payments, and all the payments together by date.
Map<String, dynamic> _account({bool withPayments = true}) => <String, dynamic>{
      'customer': <String, dynamic>{'id': 5, 'name': 'mama mary magu', 'phone': '0711000777', 'credit_limit': 0, 'is_blocked': false},
      'debt': <String, dynamic>{
        'old': <String, dynamic>{'entries': <dynamic>[], 'original': 350000, 'paid': 100000, 'left': 250000},
        'new': <String, dynamic>{'sales': <dynamic>[], 'billed': 80000, 'paid': 50000, 'left': 30000},
        'total': <String, dynamic>{'owed': 430000, 'paid': 150000, 'left': 280000},
      },
      'old_debts': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 7, 'amount': 350000, 'paid': 100000, 'left': 250000, 'started_on': '2026-06-01', 'due_on': null, 'note': 'Soda za mwaka jana',
          'payments': withPayments ? <Map<String, dynamic>>[<String, dynamic>{'id': 1, 'amount': 100000, 'method': 'cash', 'reference': null, 'paid_on': '2026-10-20'}] : <dynamic>[],
        },
      ],
      'credit_sales': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 21, 'number': 'S-1', 'total': 50000, 'paid': 20000, 'left': 30000, 'payment_status': 'partial', 'due_date': null, 'created_at': '2026-11-05 09:00:00',
          'payments': withPayments ? <Map<String, dynamic>>[<String, dynamic>{'id': 3, 'amount': 20000, 'method': 'mobile_money', 'reference': 'MP123', 'paid_on': '2026-11-06'}] : <dynamic>[],
        },
        <String, dynamic>{
          'id': 22, 'number': 'S-2', 'total': 30000, 'paid': 30000, 'left': 0, 'payment_status': 'paid', 'due_date': null, 'created_at': '2026-11-01 09:00:00',
          'payments': withPayments ? <Map<String, dynamic>>[<String, dynamic>{'id': 4, 'amount': 30000, 'method': 'cash', 'reference': null, 'paid_on': '2026-11-02'}] : <dynamic>[],
        },
      ],
      'payments': withPayments
          ? <Map<String, dynamic>>[
              <String, dynamic>{'id': 3, 'amount': 20000, 'method': 'mobile_money', 'reference': 'MP123', 'paid_on': '2026-11-06', 'kind': 'new', 'label': 'S-1'},
              <String, dynamic>{'id': 4, 'amount': 30000, 'method': 'cash', 'reference': null, 'paid_on': '2026-11-02', 'kind': 'new', 'label': 'S-2'},
              <String, dynamic>{'id': 1, 'amount': 100000, 'method': 'cash', 'reference': null, 'paid_on': '2026-10-20', 'kind': 'old', 'label': 'Soda za mwaka jana'},
            ]
          : <dynamic>[],
      'paid_by_payments': <String, dynamic>{'old': withPayments ? 100000 : 0, 'new': withPayments ? 50000 : 0, 'all': withPayments ? 150000 : 0},
    };

class _Server extends ApiService {
  _Server(this.account, {this.fail = false});

  final Map<String, dynamic> account;
  final bool fail;
  final List<String> asked = <String>[];

  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async {
    asked.add(endpoint);
    if (fail) throw ApiException('offline');
    return <String, dynamic>{'data': account};
  }
}

Future<void> _open(WidgetTester t, _Server server) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
      ],
      child: ScreenUtilInit(
        designSize: const Size(800, 4000),
        builder: (_, __) => const MaterialApp(home: CustomerAccountScreen(customer: InvCreditCustomer(id: 5, name: 'mama mary magu', balance: 280000, creditLimit: 0))),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  test('the account is read in all its parts', () {
    final CustomerAccount a = CustomerAccount.fromJson(_account());

    expect(a.name, 'mama mary magu');
    expect(<double>[a.debt.oldLeft, a.debt.newLeft, a.debt.totalLeft], <double>[250000, 30000, 280000]);
    expect(a.oldDebts.single.payments.single.amount, 100000);
    expect(a.creditSales.map((CreditSaleRecord s) => s.isPaidOff), <bool>[false, true]);
    expect(a.payments.map((AccountPayment p) => p.isOld), <bool>[false, false, true]);
    expect(<double>[a.paidOld, a.paidNew, a.paidAll], <double>[100000, 50000, 150000]);
  });

  testWidgets('shows the three parts with the total, every old debt and sale with its payments, and all payments together', (t) async {
    final _Server server = _Server(_account());

    await _open(t, server);

    expect(server.asked.single, contains('/credit/customers/5/account'));
    expect(find.descendant(of: _key('debt_old'), matching: find.text('TSH 250,000')), findsOneWidget);
    expect(find.descendant(of: _key('debt_new'), matching: find.text('TSH 30,000')), findsOneWidget);
    expect(find.descendant(of: _key('debt_total_left'), matching: find.text('TSH 280,000')), findsOneWidget);
    expect(find.descendant(of: _key('debt_total_paid'), matching: find.text('TSH 150,000')), findsOneWidget);

    // each old debt and each credit sale with the payments made on it
    expect(find.descendant(of: _key('old_debt_7'), matching: find.text('Soda za mwaka jana')), findsOneWidget);
    expect(find.descendant(of: _key('old_debt_7'), matching: find.text('TSH 100,000')), findsWidgets);
    expect(find.descendant(of: _key('credit_sale_21'), matching: find.text('Open')), findsOneWidget);
    expect(find.descendant(of: _key('credit_sale_22'), matching: find.text('Paid off')), findsOneWidget, reason: 'a sale paid off stays on the page');
    expect(find.descendant(of: _key('credit_sale_21'), matching: find.textContaining('mobile money · MP123')), findsOneWidget, reason: 'how it was paid and the reference');

    // all payments, newest first, old and new together
    expect(find.text('2026-11-06 · Sale · S-1'), findsOneWidget);
    expect(find.text('2026-10-20 · Old debt · Soda za mwaka jana'), findsOneWidget);
    expect(find.descendant(of: _key('payments_total'), matching: find.text('TSH 150,000')), findsOneWidget);
    final double newest = t.getTopLeft(find.text('2026-11-06 · Sale · S-1')).dy;
    final double oldest = t.getTopLeft(find.text('2026-10-20 · Old debt · Soda za mwaka jana')).dy;
    expect(newest, lessThan(oldest));
  });

  testWidgets('a customer who has paid nothing yet says so', (t) async {
    await _open(t, _Server(_account(withPayments: false)));

    expect(_key('no_payments'), findsOneWidget);
    expect(_key('payments_total'), findsNothing);
  });

  testWidgets('the Receive payment button is there while something is owed', (t) async {
    await _open(t, _Server(_account()));

    expect(_key('account_receive'), findsOneWidget);
  });

  testWidgets('no button when nothing is owed', (t) async {
    final Map<String, dynamic> paid = _account();
    (paid['debt'] as Map<String, dynamic>)['total'] = <String, dynamic>{'owed': 430000, 'paid': 430000, 'left': 0};

    await _open(t, _Server(paid));

    expect(_key('account_receive'), findsNothing);
  });

  testWidgets('a page that could not be loaded says so and can be tried again', (t) async {
    await _open(t, _Server(_account(), fail: true));

    expect(_key('account_load_failed'), findsOneWidget);
    expect(_key('account_retry'), findsOneWidget);
    expect(_key('debt_total_left'), findsNothing);
  });
}
