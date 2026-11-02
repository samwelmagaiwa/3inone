import 'package:boda_mapato/modules/inventory/models/inv_customer_debt.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/sales/sale_receipt_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/customer_account_note.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/customer_debt_card.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The customer's account in three parts (old debt, new debt, total), on the till when a sale on credit is being made, and on the
/// receipt that is given afterwards.
const CustomerDebtSummary _story = CustomerDebtSummary(
  oldOriginal: 350000,
  oldPaid: 100000,
  oldLeft: 250000,
  newBilled: 80000,
  newPaid: 50000,
  newLeft: 30000,
  totalOwed: 430000,
  totalPaid: 150000,
  totalLeft: 280000,
);

Map<String, dynamic> _json() => <String, dynamic>{
      'old': <String, dynamic>{'entries': <dynamic>[], 'original': 350000, 'paid': 100000, 'left': 250000},
      'new': <String, dynamic>{'sales': <dynamic>[], 'billed': 80000, 'paid': 50000, 'left': 30000},
      'total': <String, dynamic>{'owed': 430000, 'paid': 150000, 'left': 280000},
    };

class _Server extends ApiService {
  final List<String> asked = <String>[];

  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async {
    asked.add(endpoint);
    return <String, dynamic>{'data': <String, dynamic>{'debt': _json()}};
  }
}

Future<void> _host(WidgetTester t, Widget child, {_Server? server}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server ?? _Server())),
      ],
      child: ScreenUtilInit(designSize: const Size(800, 2400), builder: (_, __) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)))),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  test('the summary is read from the server in its three parts', () {
    final CustomerDebtSummary s = CustomerDebtSummary.fromJson(_json());

    expect(<double>[s.oldOriginal, s.oldPaid, s.oldLeft], <double>[350000, 100000, 250000]);
    expect(<double>[s.newBilled, s.newPaid, s.newLeft], <double>[80000, 50000, 30000]);
    expect(<double>[s.totalOwed, s.totalPaid, s.totalLeft], <double>[430000, 150000, 280000]);
    expect(s.hasOld, isTrue);
    expect(s.hasAny, isTrue);
  });

  test('a sale put on credit grows the new debt and the total, and nothing else', () {
    final CustomerDebtSummary after = _story.withSale(50000);

    expect(<double>[after.oldOriginal, after.oldPaid, after.oldLeft], <double>[350000, 100000, 250000], reason: 'the old debt is untouched');
    expect(<double>[after.newBilled, after.newPaid, after.newLeft], <double>[130000, 50000, 80000]);
    expect(<double>[after.totalOwed, after.totalPaid, after.totalLeft], <double>[480000, 150000, 330000]);
    expect(identical(_story.withSale(0), _story), isTrue, reason: 'no credit, no change');
  });

  testWidgets('the card shows each part and the total, and what this sale adds', (t) async {
    await _host(t, const CustomerDebtCard(summary: _story, thisSale: 50000));

    expect(find.descendant(of: _key('debt_old'), matching: find.text('TSH 250,000')), findsOneWidget);
    expect(find.descendant(of: _key('debt_new'), matching: find.text('TSH 30,000')), findsOneWidget);
    expect(find.descendant(of: _key('debt_this_sale'), matching: find.text('TSH 50,000')), findsOneWidget);
    expect(find.descendant(of: _key('debt_total_owed'), matching: find.text('TSH 480,000')), findsOneWidget, reason: '430,000 + this sale');
    expect(find.descendant(of: _key('debt_total_paid'), matching: find.text('TSH 150,000')), findsOneWidget, reason: 'what was paid does not change');
    expect(find.descendant(of: _key('debt_total_left'), matching: find.text('TSH 330,000')), findsOneWidget);
    expect(find.text('Balance after this sale'), findsOneWidget);
  });

  testWidgets('without a sale the card says "Balance", not "after this sale"', (t) async {
    await _host(t, const CustomerDebtCard(summary: _story));

    expect(_key('debt_this_sale'), findsNothing);
    expect(find.text('Balance (old + new)'), findsOneWidget);
  });

  testWidgets('on the till: a customer who owes shows the account, and it asks the server for that customer', (t) async {
    final _Server server = _Server();

    await _host(t, const CustomerAccountNote(customerId: 5, thisSale: 20000), server: server);

    expect(server.asked.single, contains('/credit/customers/5/debt-summary'));
    expect(_key('customer_account_note'), findsOneWidget);
    expect(find.descendant(of: _key('debt_total_left'), matching: find.text('TSH 300,000')), findsOneWidget, reason: '280,000 + 20,000');
  });

  testWidgets('on the till: nothing shows for a customer who owes nothing and a sale that is paid', (t) async {
    final _Nothing server = _Nothing();

    await _host(t, const CustomerAccountNote(customerId: 9, thisSale: 0), server: server);

    expect(_key('customer_account_note'), findsNothing);
  });

  testWidgets('on the receipt: the old debt, the new debt and the total are written out', (t) async {
    await _host(t, const ReceiptAccountBlock(account: _story));

    expect(_key('receipt_account'), findsOneWidget);
    expect(find.text('CUSTOMER ACCOUNT'), findsOneWidget);
    expect(find.text('OLD DEBT (BEFORE THE APP)'), findsOneWidget);
    expect(find.text('NEW DEBT (CREDIT SALES)'), findsOneWidget);
    expect(find.text('TZS 280,000'), findsOneWidget, reason: 'the balance');
    expect(find.text('TZS 150,000'), findsWidgets, reason: 'all paid so far');
  });

  test('the receipt lines (thermal paper and PDF) carry the same figures', () {
    final List<List<String>> lines = receiptAccountLines(_story, (double v) => v.round().toString());
    final Map<String, String> byLabel = <String, String>{for (final List<String> l in lines) if (l[1].isNotEmpty) l[0]: l[1]};

    expect(byLabel['Balance (old + new)'], 'TZS 280000');
    expect(byLabel['All paid so far (old + new)'], 'TZS 150000');
    expect(lines.where((List<String> l) => l[1].isEmpty).map((List<String> l) => l[0]), <String>['OLD DEBT (BEFORE THE APP)', 'NEW DEBT (CREDIT SALES)', 'TOTAL']);

    // a customer with no old debt has no old part
    final List<List<String>> fresh = receiptAccountLines(const CustomerDebtSummary(newBilled: 40000, newLeft: 40000, totalOwed: 40000, totalLeft: 40000), (double v) => v.round().toString());
    expect(fresh.any((List<String> l) => l[0].startsWith('OLD DEBT')), isFalse);
  });
}

class _Nothing extends _Server {
  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async {
    return <String, dynamic>{
      'data': <String, dynamic>{
        'debt': <String, dynamic>{
          'old': <String, dynamic>{'entries': <dynamic>[], 'original': 0, 'paid': 0, 'left': 0},
          'new': <String, dynamic>{'sales': <dynamic>[], 'billed': 0, 'paid': 0, 'left': 0},
          'total': <String, dynamic>{'owed': 0, 'paid': 0, 'left': 0},
        },
      },
    };
  }
}
