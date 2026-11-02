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

/// "Receive payment" for a customer who owed from before the app and has taken goods on credit since: the OLD debt and the NEW debt are
/// shown apart with the total of both, either can be ticked and paid, and the money goes to each as chosen. (It once listed only this
/// month's sales, so on the first of a new month every debt from the month before vanished from the list.)
class _Server extends ApiService {
  _Server({required this.summary, this.failFirst = false});

  final Map<String, dynamic> summary;
  final bool failFirst;
  final List<String> asked = <String>[];
  final List<Map<String, dynamic>> posted = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async {
    asked.add(endpoint);
    if (failFirst && asked.where((String e) => e.contains('debt-summary')).length == 1) throw ApiException('offline');
    if (endpoint.contains('debt-summary')) return <String, dynamic>{'data': <String, dynamic>{'debt': summary}};
    return <String, dynamic>{'data': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    if (endpoint == '/inventory/payments') posted.add(data);
    return <String, dynamic>{'data': <String, dynamic>{}};
  }
}

/// Old debt 350,000 (100,000 paid); new debt: sale S-1 of 50,000 (20,000 paid). All together 400,000 owed, 120,000 paid, 280,000 left.
Map<String, dynamic> _story() => <String, dynamic>{
      'old': <String, dynamic>{
        'entries': <Map<String, dynamic>>[<String, dynamic>{'id': 7, 'amount': 350000, 'paid': 100000, 'left': 250000, 'started_on': '2026-06-01', 'note': 'Soda za mwaka jana'}],
        'original': 350000,
        'paid': 100000,
        'left': 250000,
      },
      'new': <String, dynamic>{
        'sales': <Map<String, dynamic>>[<String, dynamic>{'id': 21, 'number': 'S-1', 'total': 50000, 'paid': 20000, 'left': 30000, 'payment_status': 'partial', 'due_date': null, 'created_at': '2026-11-05T09:00:00Z'}],
        'billed': 50000,
        'paid': 20000,
        'left': 30000,
      },
      'total': <String, dynamic>{'owed': 400000, 'paid': 120000, 'left': 280000},
    };

Future<void> _open(WidgetTester t, _Server server) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
      ],
      child: ScreenUtilInit(
        designSize: const Size(800, 3200),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReceivePaymentSheet(customer: const InvCreditCustomer(id: 5, name: 'mama mary magu', balance: 280000, creditLimit: 0)),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('shows the old debt, the new debt and the total of both, apart', (t) async {
    final _Server server = _Server(summary: _story());

    await _open(t, server);

    expect(server.asked.single, contains('/credit/customers/5/debt-summary'));
    expect(find.descendant(of: _key('debt_old'), matching: find.text('TSH 350,000')), findsOneWidget, reason: 'the old debt: what it was');
    expect(find.descendant(of: _key('debt_old'), matching: find.text('TSH 100,000')), findsOneWidget, reason: 'what was paid on it');
    expect(find.descendant(of: _key('debt_old'), matching: find.text('TSH 250,000')), findsOneWidget, reason: 'what is left of it');
    expect(find.descendant(of: _key('debt_new'), matching: find.text('TSH 30,000')), findsOneWidget, reason: 'what is left of the new debt');
    expect(find.descendant(of: _key('debt_total_owed'), matching: find.text('TSH 400,000')), findsOneWidget);
    expect(find.descendant(of: _key('debt_total_paid'), matching: find.text('TSH 120,000')), findsOneWidget, reason: 'all paid so far, old and new');
    expect(find.descendant(of: _key('debt_total_left'), matching: find.text('TSH 280,000')), findsOneWidget);
  });

  testWidgets('both kinds of debt can be paid: the old debt entry and the credit sale are listed, each with its own amount', (t) async {
    final _Server server = _Server(summary: _story());
    await _open(t, server);

    expect(_key('pay_line_old_7'), findsOneWidget);
    expect(_key('pay_line_sale_21'), findsOneWidget);

    await t.tap(_key('pay_line_old_7'));
    await _settle(t);
    await t.tap(_key('pay_line_sale_21'));
    await _settle(t);
    await t.enterText(_key('pay_amount_old_7'), '100000');
    await t.enterText(_key('pay_amount_sale_21'), '10000');
    await _settle(t);

    expect(find.descendant(of: _key('payment_entered'), matching: find.text('TSH 110000')), findsOneWidget);
    expect(find.descendant(of: _key('balance_after_payment'), matching: find.text('TSH 170000')), findsOneWidget, reason: '280,000 - 110,000');

    await t.tap(find.byType(ElevatedButton).last);
    await _settle(t);
    await t.pump(const Duration(seconds: 4)); // the "payment recorded" message goes away

    final Map<String, dynamic> body = server.posted.single;
    expect(body['customer_id'], 5);
    expect(body['old_allocations'], <Map<String, dynamic>>[<String, dynamic>{'debt_id': 7, 'amount': 100000.0}], reason: 'the old debt gets its own share');
    expect(body['allocations'], <Map<String, dynamic>>[<String, dynamic>{'sale_id': 21, 'amount': 10000.0}], reason: 'and so does the sale');
  });

  testWidgets('only the old debt can be paid on its own', (t) async {
    final _Server server = _Server(summary: _story());
    await _open(t, server);

    await t.tap(_key('pay_line_old_7'));
    await _settle(t);
    await t.tap(find.byType(ElevatedButton).last);
    await _settle(t);
    await t.pump(const Duration(seconds: 4)); // the "payment recorded" message goes away

    final Map<String, dynamic> body = server.posted.single;
    expect((body['old_allocations'] as List<dynamic>).single['amount'], 250000.0, reason: 'ticking it fills in what is left');
    expect(body.containsKey('allocations'), isFalse);
  });

  testWidgets('a customer who owes nothing from before the app has no old part, and still a total', (t) async {
    final Map<String, dynamic> only = <String, dynamic>{
      'old': <String, dynamic>{'entries': <dynamic>[], 'original': 0, 'paid': 0, 'left': 0},
      'new': <String, dynamic>{
        'sales': <Map<String, dynamic>>[<String, dynamic>{'id': 21, 'number': 'S-1', 'total': 40000, 'paid': 0, 'left': 40000, 'payment_status': 'debt', 'due_date': null, 'created_at': '2026-11-05T09:00:00Z'}],
        'billed': 40000,
        'paid': 0,
        'left': 40000,
      },
      'total': <String, dynamic>{'owed': 40000, 'paid': 0, 'left': 40000},
    };

    await _open(t, _Server(summary: only));

    expect(_key('debt_old'), findsNothing);
    expect(_key('debt_new'), findsOneWidget);
    expect(_key('pay_line_old_7'), findsNothing);
    expect(find.descendant(of: _key('debt_total_left'), matching: find.text('TSH 40,000')), findsOneWidget);
  });

  testWidgets('a list that could not be loaded says so and can be tried again; it is not "no debts"', (t) async {
    final _Server server = _Server(failFirst: true, summary: _story());

    await _open(t, server);

    expect(_key('debts_load_failed'), findsOneWidget);
    expect(find.text('No outstanding debts found.'), findsNothing);

    await t.tap(_key('debts_retry'));
    await _settle(t);

    expect(_key('debts_load_failed'), findsNothing);
    expect(_key('pay_line_sale_21'), findsOneWidget);
  });

  testWidgets('nothing owed at all says so', (t) async {
    final Map<String, dynamic> none = <String, dynamic>{
      'old': <String, dynamic>{'entries': <dynamic>[], 'original': 0, 'paid': 0, 'left': 0},
      'new': <String, dynamic>{'sales': <dynamic>[], 'billed': 0, 'paid': 0, 'left': 0},
      'total': <String, dynamic>{'owed': 0, 'paid': 0, 'left': 0},
    };

    await _open(t, _Server(summary: none));

    expect(find.text('No outstanding debts found.'), findsOneWidget);
  });
}
