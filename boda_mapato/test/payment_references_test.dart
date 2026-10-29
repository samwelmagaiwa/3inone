import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/hubs/salon_finance_hub_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/payment_references_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Money > References: every payment that came with a reference number, oldest first, with when it was paid; a tap opens the sale.
class _Ask {
  _Ask({this.from, this.to, this.query, this.channel, required this.page});

  final DateTime? from;
  final DateTime? to;
  final String? query;
  final String? channel;
  final int page;
}

class _FakeSalon extends SalonApi {
  _FakeSalon({this.pages = 1, this.fail = false});

  final int pages;
  bool fail;
  final List<_Ask> asked = <_Ask>[];
  final List<int> opened = <int>[];

  PaymentReference _row(int n, {bool cancelled = false}) => PaymentReference(
        id: n,
        saleId: 100 + n,
        saleNumber: 'S-$n',
        reference: 'REF$n',
        channel: n.isEven ? 'airtel_money' : 'mpesa',
        amount: 1000.0 * n,
        saleTotal: 5000,
        cancelled: cancelled,
        paidAt: DateTime(2026, 10, n, 9 + n, 5),
        customerName: n == 1 ? 'Neema Joseph' : null,
      );

  @override
  Future<PaymentReferencePage> paymentReferences({final DateTime? from, final DateTime? to, final String? query, final String? channel, final int page = 1}) async {
    asked.add(_Ask(from: from, to: to, query: query, channel: channel, page: page));
    if (fail) throw Exception('Server busy');
    final List<PaymentReference> rows = page == 1 ? <PaymentReference>[_row(1), _row(2), _row(3, cancelled: true)] : <PaymentReference>[_row(4)];

    return PaymentReferencePage(rows: rows, count: pages > 1 ? 4 : 3, amount: pages > 1 ? 10000 : 6000, page: page, lastPage: pages);
  }

  @override
  Future<Map<String, dynamic>> saleDetail(final int id) async {
    opened.add(id);

    return <String, dynamic>{
      'id': id,
      'number': 'S-1',
      'customer_name': 'Neema Joseph',
      'created_at': '2026-10-01 10:05:00',
      'payment_status': 'paid',
      'discount': 500,
      'total': 5000,
      'paid_total': 5000,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'product_name': 'Knotless Braids', 'quantity': 1, 'total': 4000, 'staff_name': 'Asha'},
        <String, dynamic>{'product_name': 'Gel', 'quantity': 2, 'total': 1500},
      ],
      'payments': <Map<String, dynamic>>[
        <String, dynamic>{'id': 77, 'method': 'mpesa', 'reference': 'REF1', 'amount': 5000},
      ],
    };
  }
}

class _Owner extends AuthProvider {
  @override
  UserData? get user => UserData(id: 'o1', name: 'Owner', email: 'o@example.test', role: 'admin', isActive: true);

  @override
  UserPermissions get permissions => UserPermissions.fromRole('admin');
}

Future<void> _host(WidgetTester t, Widget child, {bool sw = false}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Owner()),
      ],
      child: ScreenUtilInit(designSize: const Size(411, 2400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: Scaffold(body: child))),
    ),
  );
  for (int i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  testWidgets('lists the references in the order the API gives them (oldest first), each with when, how much and who for', (t) async {
    final _FakeSalon api = _FakeSalon();
    await _host(t, PaymentReferencesScreen(api: api, today: DateTime(2026, 10, 15)));

    expect(find.text('REF1'), findsOneWidget);
    expect(find.text('REF2'), findsOneWidget);
    expect(t.getTopLeft(find.text('REF1')).dy, lessThan(t.getTopLeft(find.text('REF2')).dy));
    expect(t.getTopLeft(find.text('REF2')).dy, lessThan(t.getTopLeft(find.text('REF3')).dy));
    expect(find.textContaining('01/10/2026 10:05'), findsOneWidget, reason: 'the day and the time it was paid');
    expect(find.textContaining('Neema Joseph'), findsOneWidget);
    expect(find.textContaining('M-Pesa'), findsWidgets);
    expect(find.text('TSH 6,000'), findsWidgets, reason: 'what they come to');
    expect(find.text('Sale cancelled'), findsOneWidget);
    expect(api.asked.single.from, DateTime(2026, 10));
    expect(api.asked.single.to, DateTime(2026, 10, 15));
  });

  testWidgets('a tap on a reference opens the whole sale: customer, what was sold, totals and every payment', (t) async {
    final _FakeSalon api = _FakeSalon();
    await _host(t, PaymentReferencesScreen(api: api, today: DateTime(2026, 10, 15)));

    await t.tap(_key('reference_1'));
    await _settle(t);

    expect(api.opened, <int>[101]);
    expect(_key('reference_sale'), findsOneWidget);
    expect(find.text('Neema Joseph'), findsWidgets);
    expect(find.textContaining('Knotless Braids × 1'), findsOneWidget);
    expect(find.textContaining('Asha'), findsOneWidget, reason: 'who served');
    expect(find.textContaining('Gel × 2'), findsOneWidget);
    expect(find.text('− TSH 500'), findsOneWidget);
    expect(find.text('TSH 5,000'), findsWidgets);
    expect(find.textContaining('M-Pesa • REF1'), findsOneWidget, reason: 'the payment, with its reference');
  });

  testWidgets('choosing a way to pay, a period or a search asks the server again with that choice', (t) async {
    final _FakeSalon api = _FakeSalon();
    await _host(t, PaymentReferencesScreen(api: api, today: DateTime(2026, 10, 15)));

    await t.ensureVisible(find.text('Airtel Money'));
    await t.tap(find.text('Airtel Money'));
    await _settle(t);
    expect(api.asked.last.channel, 'airtel_money');

    await t.ensureVisible(find.text('Last month'));
    await t.tap(find.text('Last month'));
    await _settle(t);
    expect(api.asked.last.from, DateTime(2026, 9));
    expect(api.asked.last.to, DateTime(2026, 9, 30));
    expect(api.asked.last.channel, 'airtel_money', reason: 'the other choices are kept');

    await t.ensureVisible(find.text('All'));
    await t.tap(find.text('All'));
    await _settle(t);
    expect(api.asked.last.from, isNull);
    expect(api.asked.last.to, isNull);

    await t.enterText(find.byType(TextField), 'REF2');
    await _settle(t);
    expect(api.asked.last.query, 'REF2');
  });

  testWidgets('Show more adds the next page after the ones already shown', (t) async {
    final _FakeSalon api = _FakeSalon(pages: 2);
    await _host(t, PaymentReferencesScreen(api: api, today: DateTime(2026, 10, 15)));

    expect(find.text('REF4'), findsNothing);
    await t.ensureVisible(_key('references_more'));
    await t.tap(_key('references_more'));
    await _settle(t);

    expect(api.asked.last.page, 2);
    expect(find.text('REF1'), findsOneWidget, reason: 'the first page stays');
    expect(find.text('REF4'), findsOneWidget);
    expect(_key('references_more'), findsNothing, reason: 'that was the last page');
  });

  testWidgets('no More button when everything fits in one page', (t) async {
    await _host(t, PaymentReferencesScreen(api: _FakeSalon(), today: DateTime(2026, 10, 15)));
    expect(_key('references_more'), findsNothing);
  });

  testWidgets('a failed read says so and offers Try again', (t) async {
    final _FakeSalon api = _FakeSalon()..fail = true;
    await _host(t, PaymentReferencesScreen(api: api, today: DateTime(2026, 10, 15)));
    expect(_key('references_retry'), findsOneWidget);

    api.fail = false;
    await t.tap(_key('references_retry'));
    await _settle(t);
    expect(find.text('REF1'), findsOneWidget);
  });

  testWidgets('speaks Swahili when asked', (t) async {
    await _host(t, PaymentReferencesScreen(api: _FakeSalon(), today: DateTime(2026, 10, 15)), sw: true);

    expect(find.text('Mwezi huu'), findsOneWidget);
    expect(find.text('Miamala'), findsOneWidget);
    expect(find.text('Mauzo yamefutwa'), findsOneWidget);
  });

  testWidgets('in the Money tab the References tab comes right after Expenses', (t) async {
    await _host(t, const SalonFinanceHubScreen());

    final double expenses = t.getTopLeft(find.text('Expenses')).dx;
    final double references = t.getTopLeft(find.text('References')).dx;
    final double payroll = t.getTopLeft(find.text('Payroll')).dx;
    expect(references, greaterThan(expenses));
    expect(references, lessThan(payroll));
  });
}
