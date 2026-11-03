import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/credit/credit_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/joined_sections.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Serves canned answers so the real Debts screens can be loaded without a server.
class _FakeApi extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint,
      {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/credit/customers/2/statement')) {
      return <String, dynamic>{
        'data': <String, dynamic>{
          'sales': <dynamic>[
            <String, dynamic>{
              'number': 'S-20261008-0002',
              'created_at': '2026-10-08 12:08:25',
              'total': 112000,
            },
          ],
          'payments': <dynamic>[],
        },
      };
    }
    if (endpoint.startsWith('/inventory/credit/customers')) {
      return <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{
            'id': 2, 'name': 'mama anna', 'phone': '0783510498',
            'balance': 112000, 'credit_limit': 0, 'payment_terms_days': 0,
            'is_blocked': 0,
          },
          <String, dynamic>{
            'id': 5, 'name': 'Baba John', 'phone': '0711000111',
            'balance': 5000, 'credit_limit': 0, 'payment_terms_days': 0,
            'is_blocked': 0,
          },
        ],
      };
    }
    if (endpoint.startsWith('/inventory/crate-balances')) {
      return <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{
            'customer_id': 2, 'customer_name': 'mama anna',
            'crate_type_id': 1, 'crate_type_name': 'Crate',
            'held': 10, 'deposit_at_risk': 20000,
          },
        ],
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

Future<void> _pump(WidgetTester t, Widget screen) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<DepotProvider>(
            create: (_) => DepotProvider(api: _FakeApi())),
        ChangeNotifierProvider<LocalizationService>.value(
            value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(home: screen),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  // The app starts in Swahili, so that is the wording these screens show.
  const String note = 'Makreti anayodaiwa: 10 × Crate (dhamana TZS 20000)';

  testWidgets('Debts list: mama anna shows her crates, Baba John does not',
      (t) async {
    await _pump(t, const CreditScreen());

    expect(find.text('mama anna'), findsOneWidget);
    expect(find.text('Baba John'), findsOneWidget);
    // Exactly one card carries the note -- hers.
    expect(find.text(note), findsOneWidget);
  });

  testWidgets('Debts list: each customer is a section divided from the next by the glowing line, and the three figures by vertical lines',
      (t) async {
    await _pump(t, const CreditScreen());

    // two customers: one line between them (the search box has its own gap), and two vertical lines inside each customer's figures
    expect(find.byKey(const ValueKey<String>('customer_divider_1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('customer_divider_2')), findsNothing);
    expect(find.byType(SectionGlowVerticalDivider), findsNWidgets(4));
  });

  testWidgets('Customer statement shows the crates owed above the money',
      (t) async {
    await _pump(
        t, const CustomerStatementScreen(customerId: 2, customerName: 'mama anna'));

    expect(find.text(note), findsOneWidget);
    expect(find.text('Sale S-20261008-0002'), findsOneWidget);
  });

  testWidgets('Statement of a customer with no crates shows no note', (t) async {
    await _pump(
        t, const CustomerStatementScreen(customerId: 5, customerName: 'Baba John'));

    expect(find.text(note), findsNothing);
  });
}
