import 'package:boda_mapato/modules/inventory/models/inv_customer_debt.dart';
import 'package:boda_mapato/modules/inventory/models/inv_depot_models.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/credit/customer_account_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/credit/merge_customers_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The same person saved twice ("mama chale" and "Mama Chale"): the owner is told, picks the record to keep, and the other is merged onto
/// it; the customer account then shows everything, with what the customer bought and the profit it brought.
class _Server extends ApiService {
  _Server({this.failMerge = false});

  final bool failMerge;
  final List<String> posted = <String>[];
  List<Map<String, dynamic>> groups = <Map<String, dynamic>>[
    <String, dynamic>{
      'customers': <Map<String, dynamic>>[
        <String, dynamic>{'id': 5, 'name': 'mama chale', 'phone': '0711000777', 'sales': 3, 'owes': 430000},
        <String, dynamic>{'id': 9, 'name': 'Mama Chale', 'phone': '', 'sales': 1, 'owes': 210000},
      ],
    },
  ];

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async => get(endpoint, requireAuth: requireAuth);

  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async {
    if (endpoint.contains('/customers/duplicates')) return <String, dynamic>{'data': groups};
    if (endpoint.contains('/credit/customers')) return <String, dynamic>{'data': <dynamic>[]};
    return <String, dynamic>{'data': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    posted.add('$endpoint ${data['into_id']}');
    if (failMerge) throw ApiException('Not allowed');
    groups = <Map<String, dynamic>>[];
    return <String, dynamic>{'message': 'Customers merged', 'data': <String, dynamic>{'kept': data['into_id']}};
  }
}

Future<DepotProvider> _open(WidgetTester t, _Server server, Widget home) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final DepotProvider depot = DepotProvider(api: server);
  await depot.fetchDuplicateCustomers();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
        ChangeNotifierProvider<DepotProvider>.value(value: depot),
      ],
      child: ScreenUtilInit(designSize: const Size(800, 3000), builder: (_, __) => MaterialApp(home: home)),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
  return depot;
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  test('a group suggests keeping the customer with the most sales', () {
    final DuplicateGroup g = DuplicateGroup.fromJson(<String, dynamic>{
      'customers': <Map<String, dynamic>>[
        <String, dynamic>{'id': 9, 'name': 'Mama Chale', 'phone': '', 'sales': 1, 'owes': 0},
        <String, dynamic>{'id': 5, 'name': 'mama chale', 'phone': '0711', 'sales': 3, 'owes': 0},
      ],
    });
    expect(g.suggested.id, 5);
  });

  test('the lifetime figures are read, and profit is null for anyone who may not see it', () {
    expect(CustomerLifetime.fromJson(<String, dynamic>{'purchases': 4, 'sales': 90000, 'profit': 30000, 'profit_visible': true}).profit, 30000);
    expect(CustomerLifetime.fromJson(<String, dynamic>{'purchases': 4, 'sales': 90000, 'profit': null, 'profit_visible': false}).profit, isNull);
    expect(CustomerLifetime.fromJson(<String, dynamic>{'purchases': 4, 'sales': 90000, 'profit': 30000, 'profit_visible': false}).profit, isNull);
  });

  testWidgets('lists each group with its customers, sales and debt, the busiest one chosen to keep', (t) async {
    await _open(t, _Server(), const MergeCustomersScreen());

    expect(find.text('mama chale'), findsOneWidget);
    expect(find.text('Mama Chale'), findsOneWidget);
    expect(find.textContaining('3 sales'), findsOneWidget);
    expect(find.textContaining('owes TSH 430,000'), findsOneWidget);
    expect(find.text('Keep this one'), findsOneWidget);
    expect(find.descendant(of: _key('merge_pick_5'), matching: find.byIcon(Icons.radio_button_checked)), findsOneWidget);
  });

  testWidgets('merging asks first, then moves the other customer onto the chosen one', (t) async {
    final _Server server = _Server();
    await _open(t, server, const MergeCustomersScreen());

    await t.tap(_key('merge_go_5'));
    await t.pumpAndSettle();
    expect(find.textContaining('Merge into mama chale'), findsOneWidget, reason: 'asks first and says who is kept');
    expect(server.posted, isEmpty);

    await t.tap(_key('merge_confirm'));
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(seconds: 6));

    expect(server.posted, <String>['/inventory/customers/9/merge 5'], reason: 'the other one (9) goes onto the kept one (5)');
    expect(_key('merge_none'), findsOneWidget, reason: 'nothing left to merge');
  });

  testWidgets('choosing the other customer keeps that one instead', (t) async {
    final _Server server = _Server();
    await _open(t, server, const MergeCustomersScreen());

    await t.tap(_key('merge_pick_9'));
    await t.pump();
    await t.tap(_key('merge_go_5'));
    await t.pumpAndSettle();
    await t.tap(_key('merge_confirm'));
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(seconds: 6));

    expect(server.posted, <String>['/inventory/customers/5/merge 9']);
  });

  testWidgets('cancelling the question merges nothing', (t) async {
    final _Server server = _Server();
    await _open(t, server, const MergeCustomersScreen());

    await t.tap(_key('merge_go_5'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(server.posted, isEmpty);
    expect(_key('merge_group_5'), findsOneWidget);
  });

  testWidgets('a refused merge leaves the group there and says why', (t) async {
    await _open(t, _Server(failMerge: true), const MergeCustomersScreen());

    await t.tap(_key('merge_go_5'));
    await t.pumpAndSettle();
    await t.tap(_key('merge_confirm'));
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(seconds: 6));

    expect(_key('merge_group_5'), findsOneWidget);
  });

  Map<String, dynamic> accountWith(Map<String, dynamic> lifetime) => <String, dynamic>{
        'customer': <String, dynamic>{'id': 5, 'name': 'mama chale', 'phone': '0711', 'credit_limit': 0, 'is_blocked': false},
        'debt': <String, dynamic>{
          'old': <String, dynamic>{'entries': <dynamic>[], 'original': 430000, 'paid': 0, 'left': 430000},
          'new': <String, dynamic>{'sales': <dynamic>[], 'billed': 210000, 'paid': 0, 'left': 210000},
          'total': <String, dynamic>{'owed': 640000, 'paid': 0, 'left': 640000},
        },
        'old_debts': <dynamic>[],
        'credit_sales': <dynamic>[],
        'payments': <dynamic>[],
        'paid_by_payments': <String, dynamic>{'old': 0, 'new': 0, 'all': 0},
        'lifetime': lifetime,
      };
  const InvCreditCustomer who = InvCreditCustomer(id: 5, name: 'mama chale', balance: 640000, creditLimit: 0);

  testWidgets('the customer account shows what the customer bought and the profit when it may be seen', (t) async {
    await _open(t, _AccountServer(accountWith(<String, dynamic>{'purchases': 4, 'sales': 560000, 'profit': 140000, 'profit_visible': true, 'first_purchase': '2026-06-02 09:00', 'last_purchase': '2026-11-01 16:30'})), const CustomerAccountScreen(customer: who));

    expect(find.descendant(of: _key('lifetime_sales'), matching: find.text('TSH 560,000')), findsOneWidget);
    expect(find.descendant(of: _key('lifetime_profit'), matching: find.text('TSH 140,000')), findsOneWidget);
    expect(find.text('2026-06-02'), findsOneWidget);
    expect(find.text('2026-11-01'), findsOneWidget);
  });

  testWidgets('a till operator sees what was bought but never the profit', (t) async {
    await _open(t, _AccountServer(accountWith(<String, dynamic>{'purchases': 4, 'sales': 560000, 'profit': null, 'profit_visible': false, 'first_purchase': '2026-06-02 09:00', 'last_purchase': '2026-11-01 16:30'})), const CustomerAccountScreen(customer: who));

    expect(_key('lifetime_profit'), findsNothing);
    expect(_key('lifetime_sales'), findsOneWidget);
  });
}

class _AccountServer extends _Server {
  _AccountServer(this.account);

  final Map<String, dynamic> account;

  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async {
    if (endpoint.contains('/account')) return <String, dynamic>{'data': account};
    return super.get(endpoint, requireAuth: requireAuth, queryParams: queryParams);
  }
}
