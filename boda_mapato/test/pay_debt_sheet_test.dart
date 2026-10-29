import 'package:boda_mapato/constants/theme_constants.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/sales/sales_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/inventory_widgets.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Canned answers instead of a server. Remembers every save the app attempts.
class _FakeApi extends ApiService {
  final List<String> posts = <String>[];
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data,
      {bool requireAuth = true}) async {
    posts.add(endpoint);
    bodies.add(data);
    return <String, dynamic>{
      'data': <String, dynamic>{'id': 1, 'number': 'S-TEST-1'}
    };
  }

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint,
      {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/sales/summary')) {
      return <String, dynamic>{'data': <String, dynamic>{}};
    }
    if (endpoint.startsWith('/inventory/sales')) {
      return <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{
            'id': 2, 'number': 'S-20261008-0002', 'customer_name': 'mama anna',
            'payment_status': 'debt', 'subtotal': 112000, 'total': 112000,
            'paid_total': 0, 'created_at': '2026-10-08 12:08:25',
            'items': <dynamic>[],
          },
        ],
        'meta': <String, dynamic>{'current_page': 1, 'last_page': 1},
      };
    }
    if (endpoint.startsWith('/inventory/customers')) {
      return <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'id': 2, 'name': 'mama anna', 'phone': '0783510498'},
          <String, dynamic>{'id': 5, 'name': 'Baba John', 'phone': '0711000111'},
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

/// A signed-in user who may sell and manage customers.
class _SellerAuth extends AuthProvider {
  @override
  UserPermissions get permissions => UserPermissions.fromRole('admin');
}

late _FakeApi _api;

/// Flutter's test font draws every letter as a wide square, so rows that fit on a phone
/// "overflow" here. Those warnings say nothing about the real app, so they are ignored;
/// every other error still fails the test.
void _ignoreTestFontOverflow() {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<InventoryProvider> _pump(WidgetTester t) async {
  _ignoreTestFontOverflow();
  _api = _FakeApi();
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  final InventoryProvider inv = InventoryProvider(api: _api);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(
            create: (_) => DepotProvider(api: _FakeApi())),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _SellerAuth()),
        ChangeNotifierProvider<LocalizationService>.value(
            value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        // The app-wide theme fills every field white; the sheet must not inherit that.
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          home: const Scaffold(body: SalesScreen()),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  await inv.fetchCustomers();
  await t.pumpAndSettle();
  return inv;
}

void main() {
  testWidgets('Pay Debt sheet: Payment Method is a dark field, not white', (t) async {
    await _pump(t);

    final LocalizationService loc = LocalizationService.instance;
    await t.tap(find.text(loc.translate('sales_history')));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip(loc.translate('pay_debt')));
    await t.pumpAndSettle();

    final Finder dropdown = find.byType(DropdownButtonFormField<String>);
    expect(dropdown, findsOneWidget);
    final InputDecoration shown = t
        .widget<InputDecorator>(
            find.descendant(of: dropdown, matching: find.byType(InputDecorator)))
        .decoration;

    expect(shown.fillColor, isNot(Colors.white),
        reason: 'a white box with white text is unreadable');
    expect(shown.fillColor, ThemeConstants.invFill);
    expect(shown.labelText, loc.translate('payment_method'));
  });

  testWidgets('a debt paid by mobile money needs the reference number, and sends it', (t) async {
    await _pump(t);
    final LocalizationService loc = LocalizationService.instance;
    await t.tap(find.text(loc.translate('sales_history')));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip(loc.translate('pay_debt')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('pay_reference')), findsNothing, reason: 'cash needs no code');

    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.text(loc.translate('mobile_money')).last);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('pay_reference')), findsOneWidget);

    await t.enterText(find.byType(InvTextField).first, '5000');
    await t.tap(find.text(loc.translate('record_payment')));
    await t.pumpAndSettle();
    expect(find.text(loc.translate('reference_required')), findsOneWidget);
    expect(_api.posts.where((String e) => e.endsWith('/payments')), isEmpty);
    await t.pump(const Duration(seconds: 4));

    await t.enterText(find.byKey(const ValueKey<String>('pay_reference')), 'MP9988');
    await t.tap(find.text(loc.translate('record_payment')));
    await t.pumpAndSettle();
    final Map<String, dynamic> sent = _api.bodies.last;
    expect(_api.posts.last, '/inventory/sales/2/payments');
    expect(sent['method'], 'mobile_money');
    expect(sent['reference'], 'MP9988');
    await t.pump(const Duration(seconds: 4));
  });
}
