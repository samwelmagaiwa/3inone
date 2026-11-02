import 'package:boda_mapato/modules/inventory/models/inv_depot_models.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/credit/credit_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Receive payment" lists what a customer still owes so it can be paid. It once asked the server for the customer's statement without
/// dates and got only THIS month's sales, so on the first day of a new month every debt from the month before vanished from the list.
class _Server extends ApiService {
  _Server({required this.sales, this.failFirst = false});

  final List<Map<String, dynamic>> sales;
  final bool failFirst;
  final List<String> asked = <String>[];

  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async {
    asked.add(endpoint);
    if (failFirst && asked.length == 1) throw ApiException('offline');
    return <String, dynamic>{'data': <String, dynamic>{'sales': sales}};
  }
}

Map<String, dynamic> _sale(String number, String status, num total, num paid, String created) =>
    <String, dynamic>{'id': number.hashCode, 'number': number, 'total': total, 'paid_total': paid, 'payment_status': status, 'created_at': created};

Future<void> _open(WidgetTester t, _Server server, InvCreditCustomer customer) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
      ],
      child: ScreenUtilInit(
        designSize: const Size(800, 2400),
        builder: (_, __) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ReceivePaymentSheet(customer: customer)))),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  const InvCreditCustomer mary = InvCreditCustomer(id: 5, name: 'mama mary magu', balance: 430000, creditLimit: 0);

  testWidgets('asks for the whole history, so a debt from an earlier month is listed', (t) async {
    final _Server server = _Server(sales: <Map<String, dynamic>>[
      _sale('S-OCT-1', 'debt', 430000, 0, '2026-10-12T09:00:00Z'),
      _sale('S-NOV-1', 'paid', 20000, 20000, '2026-11-03T09:00:00Z'),
    ]);

    await _open(t, server, mary);

    expect(server.asked.single, contains('from=2000-01-01'), reason: 'not just the current month');
    expect(find.text('S-OCT-1'), findsOneWidget, reason: 'the October debt can be paid in November');
    expect(find.text('S-NOV-1'), findsNothing, reason: 'a paid sale is not a debt');
    expect(find.text('No outstanding debts found.'), findsNothing);
  });

  testWidgets('a list that could not be loaded says so and can be tried again; it is not "no debts"', (t) async {
    final _Server server = _Server(failFirst: true, sales: <Map<String, dynamic>>[_sale('S-OCT-1', 'debt', 430000, 0, '2026-10-12T09:00:00Z')]);

    await _open(t, server, mary);

    expect(find.byKey(const ValueKey<String>('debts_load_failed')), findsOneWidget);
    expect(find.text('No outstanding debts found.'), findsNothing);

    await t.tap(find.byKey(const ValueKey<String>('debts_retry')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey<String>('debts_load_failed')), findsNothing);
    expect(find.text('S-OCT-1'), findsOneWidget);
  });

  testWidgets('an old debt (from before the app) is explained, not left as a figure that cannot be paid here', (t) async {
    final _Server server = _Server(sales: const <Map<String, dynamic>>[]);
    const InvCreditCustomer oldDebtor = InvCreditCustomer(id: 6, name: 'mama neema', balance: 430000, creditLimit: 0, oldBalance: 430000);

    await _open(t, server, oldDebtor);

    expect(find.byKey(const ValueKey<String>('old_debt_note')), findsOneWidget);
    expect(find.textContaining('TSH 430000'), findsWidgets);
    expect(find.textContaining('old debt'), findsOneWidget);
  });

  testWidgets('a customer with no old debt has no such note', (t) async {
    await _open(t, _Server(sales: <Map<String, dynamic>>[_sale('S-1', 'debt', 1000, 0, '2026-11-01T09:00:00Z')]), mary);

    expect(find.byKey(const ValueKey<String>('old_debt_note')), findsNothing);
  });

  test('the customer carries the old debt from the server', () {
    final InvCreditCustomer c = InvCreditCustomer.fromJson(<String, dynamic>{'id': 1, 'name': 'A', 'balance': '430000', 'old_balance': '100000', 'credit_limit': 0});

    expect(c.oldBalance, 100000);
  });
}
